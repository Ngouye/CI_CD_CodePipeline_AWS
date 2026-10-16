# Flotte EC2 (Auto Scaling Group) déployée en blue/green par CodeDeploy :
# à chaque release, CodeDeploy copie l'ASG, déploie sur les instances "green",
# bascule l'ALB puis termine les instances "blue".

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-default-x86_64"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2"
  description = "Instances EC2 : entree depuis l'ALB uniquement"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-ec2" }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "Depuis l'ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr HTTPS sortant via NAT (dnf, agent CodeDeploy, ECR, SSM).
resource "aws_vpc_security_group_egress_rule" "ec2_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS sortant (paquets, CodeDeploy, ECR, SSM)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-app-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.ec2_instance_type
  ebs_optimized = true

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region = var.aws_region
  }))

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # IMDSv2 obligatoire ; hop limit 1 = les conteneurs n'accèdent pas aux credentials de l'instance.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-app", Project = var.project_name }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-app", Project = var.project_name }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-app"
  min_size                  = 1
  max_size                  = var.ec2_desired_capacity + 1
  desired_capacity          = var.ec2_desired_capacity
  vpc_zone_identifier       = aws_subnet.private[*].id
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

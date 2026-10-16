#!/usr/bin/env bash
# Prépare les artefacts consommés par CodeDeploy :
#   dist/ecs : imageDetail.json + taskdef.json + appspec.yaml (action CodeDeployToECS)
#   dist/ec2 : appspec.yml + scripts de hooks + image.env      (action CodeDeploy EC2)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

: "${IMAGE_URI:?}" "${IMAGE_TAG:?}" "${AWS_REGION:?}"
: "${TASK_FAMILY:?}" "${CONTAINER_NAME:?}" "${EXECUTION_ROLE_ARN:?}" "${TASK_ROLE_ARN:?}" "${LOG_GROUP:?}"

DIST="$ROOT_DIR/dist"
rm -rf "$DIST"
mkdir -p "$DIST/ecs" "$DIST/ec2"

render() {
  sed -e "s|__TASK_FAMILY__|$TASK_FAMILY|g" \
      -e "s|__CONTAINER_NAME__|$CONTAINER_NAME|g" \
      -e "s|__EXECUTION_ROLE_ARN__|$EXECUTION_ROLE_ARN|g" \
      -e "s|__TASK_ROLE_ARN__|$TASK_ROLE_ARN|g" \
      -e "s|__LOG_GROUP__|$LOG_GROUP|g" \
      -e "s|__AWS_REGION__|$AWS_REGION|g" \
      -e "s|__APP_VERSION__|$IMAGE_TAG|g" \
      "$1" >"$2"
}

# --- ECS blue/green -----------------------------------------------------------
jq -n --arg uri "$IMAGE_URI" '{ImageURI: $uri}' >"$DIST/ecs/imageDetail.json"
render deploy/ecs/taskdef.json "$DIST/ecs/taskdef.json"
render deploy/ecs/appspec.yaml "$DIST/ecs/appspec.yaml"
jq empty "$DIST/ecs/taskdef.json"

# --- EC2 blue/green -----------------------------------------------------------
cp deploy/ec2/appspec.yml "$DIST/ec2/"
cp -r deploy/ec2/scripts "$DIST/ec2/"
chmod +x "$DIST/ec2/scripts/"*.sh
cat >"$DIST/ec2/image.env" <<EOF
IMAGE_URI=$IMAGE_URI
APP_VERSION=$IMAGE_TAG
AWS_REGION=$AWS_REGION
EOF

find "$DIST" -type f | sort

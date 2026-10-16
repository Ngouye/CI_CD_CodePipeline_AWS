# Registre de l'image de base : ECR Public par défaut (sans limite depuis AWS/CodeBuild).
# GitHub Actions passe --build-arg NODE_REGISTRY=docker.io/library (runners non limités sur Docker Hub).
ARG NODE_REGISTRY=public.ecr.aws/docker/library

# ---- Étape 1 : dépendances de production uniquement --------------------------
FROM ${NODE_REGISTRY}/node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# ---- Étape 2 : image d'exécution minimale ------------------------------------
FROM ${NODE_REGISTRY}/node:22-alpine

ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="devsecops-demo-app" \
      org.opencontainers.image.description="Application de démonstration du pipeline AWS CodePipeline DevSecOps" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV NODE_ENV=production \
    PORT=8080 \
    APP_VERSION=${APP_VERSION}

# Correctifs OS + suppression de npm/yarn/corepack (inutiles à l'exécution,
# ils réduisent la surface d'attaque et le bruit des scanners Trivy/Dockle).
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /app
# Fichiers détenus par root et en lecture seule pour l'utilisateur applicatif.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY public ./public

USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:8080/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

CMD ["node", "src/server.js"]

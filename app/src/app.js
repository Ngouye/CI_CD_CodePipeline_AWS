'use strict';

const path = require('node:path');
const escapeHtml = require('escape-html');
const express = require('express');
const helmet = require('helmet');

const SECURITY_GATES = [
  'Secrets — Gitleaks, TruffleHog',
  'SAST — Semgrep, Bearer, SonarQube',
  'IaC — Checkov, tfsec',
  'SCA — Trivy',
  'Image — Dockle, Trivy',
  'DAST — OWASP ZAP',
];

function getInfo() {
  return {
    service: 'devsecops-demo-app',
    version: process.env.APP_VERSION || 'dev',
    target: process.env.DEPLOY_TARGET || 'local',
  };
}

function renderHome({ version, target }) {
  const gates = SECURITY_GATES.map((gate) => `<li>${escapeHtml(gate)}</li>`).join('');
  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DevSecOps CodePipeline</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <main>
    <p class="eyebrow">AWS CodePipeline · CodeBuild · CodeDeploy</p>
    <h1>Pipeline CI/CD DevSecOps</h1>
    <dl>
      <dt>Version</dt><dd><code>${escapeHtml(version)}</code></dd>
      <dt>Cible</dt><dd>${escapeHtml(target)}</dd>
      <dt>Stratégie</dt><dd>Blue/Green via AWS CodeDeploy</dd>
    </dl>
    <h2>Contrôles de sécurité franchis</h2>
    <ul>${gates}</ul>
  </main>
</body>
</html>`;
}

function createApp() {
  // Pas de cookie, de session ni de route mutante (GET uniquement) : aucune surface CSRF.
  // nosemgrep: javascript.express.security.audit.express-check-csurf-middleware-usage.express-check-csurf-middleware-usage
  const app = express();
  app.disable('x-powered-by');

  // En-têtes de sécurité stricts (vérifiés par OWASP ZAP dans l'étape DAST).
  // Pas de "upgrade-insecure-requests" : la démo est servie en HTTP derrière l'ALB.
  app.use(
    helmet({
      contentSecurityPolicy: {
        useDefaults: false,
        directives: {
          defaultSrc: ["'self'"],
          baseUri: ["'self'"],
          fontSrc: ["'self'"],
          formAction: ["'self'"],
          frameAncestors: ["'none'"],
          imgSrc: ["'self'"],
          objectSrc: ["'none'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'"],
        },
      },
      crossOriginEmbedderPolicy: true,
    }),
  );
  app.use((req, res, next) => {
    res.setHeader('Permissions-Policy', 'camera=(), geolocation=(), microphone=()');
    res.setHeader('Cache-Control', 'no-store');
    next();
  });

  app.use('/static', express.static(path.join(__dirname, '..', 'public'), { maxAge: '1h' }));

  app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.get('/api/info', (req, res) => {
    res.json(getInfo());
  });

  app.get('/', (req, res) => {
    res.type('html').send(renderHome(getInfo()));
  });

  app.use((req, res) => {
    res.status(404).json({ error: 'Not Found' });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    const status = err.status >= 400 && err.status < 500 ? err.status : 500;
    res.status(status).json({ error: status === 500 ? 'Internal Server Error' : 'Bad Request' });
  });

  return app;
}

module.exports = { createApp, escapeHtml };

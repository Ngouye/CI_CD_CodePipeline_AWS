'use strict';

const { createApp } = require('./app');

const port = Number.parseInt(process.env.PORT, 10) || 8080;
const log = (msg, extra = {}) => console.log(JSON.stringify({ level: 'info', msg, ...extra }));

const server = createApp().listen(port, () => log('server started', { port }));

// Arrêt propre : ECS / CodeDeploy envoient SIGTERM lors du basculement blue/green.
function shutdown(signal) {
  log('shutting down', { signal });
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

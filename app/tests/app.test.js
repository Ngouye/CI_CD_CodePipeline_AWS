'use strict';

const request = require('supertest');
const { createApp, escapeHtml } = require('../src/app');

describe('devsecops-demo-app', () => {
  const app = createApp();

  afterEach(() => {
    delete process.env.APP_VERSION;
    delete process.env.DEPLOY_TARGET;
  });

  it('GET /health répond 200', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });

  it('GET /api/info expose la version et la cible de déploiement', async () => {
    process.env.APP_VERSION = 'abc1234';
    process.env.DEPLOY_TARGET = 'Amazon ECS (Fargate)';

    const res = await request(app).get('/api/info');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      service: 'devsecops-demo-app',
      version: 'abc1234',
      target: 'Amazon ECS (Fargate)',
    });
  });

  it('GET / affiche la page avec la version échappée', async () => {
    process.env.APP_VERSION = '<script>alert(1)</script>';

    const res = await request(app).get('/');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
    expect(res.text).not.toContain('<script>alert(1)</script>');
  });

  it('renvoie les en-têtes de sécurité attendus', async () => {
    const res = await request(app).get('/');

    expect(res.headers['x-powered-by']).toBeUndefined();
    expect(res.headers['content-security-policy']).toContain("default-src 'self'");
    expect(res.headers['content-security-policy']).toContain("frame-ancestors 'none'");
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['permissions-policy']).toBeDefined();
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('sert les fichiers statiques', async () => {
    const res = await request(app).get('/static/style.css');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/css/);
  });

  it('renvoie 404 en JSON pour une route inconnue', async () => {
    const res = await request(app).get('/does-not-exist');
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Not Found' });
  });

  it('escapeHtml neutralise les caractères spéciaux', () => {
    expect(escapeHtml(`<a href="x">'&'</a>`)).toBe('&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
  });
});

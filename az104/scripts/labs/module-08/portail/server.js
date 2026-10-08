// server.js — portail client Arvéo, version PaaS (App Service Linux, Node.js 22 LTS)
// Aucune dépendance npm : module http et fetch natifs (Node.js 18 ou plus).
// __VERSION__ est remplacé par empaqueter-portail.sh (v3, v4...) AVANT l'archivage.
// Variables lues (paramètres d'application) :
//   PORT              port d'écoute fourni par App Service (8080 par défaut)
//   ARVEO_ENV         environnement affiché (paramètre d'emplacement : production / recette)
//   API_URL           URL de l'API de suivi des colis (défi 08.5), ex. http://10.7.6.68:8080/
//   WEBSITE_INSTANCE_ID  identifiant de l'instance du plan (fourni par App Service)
// Routes : /health (sonde de santé), /api/ (relais vers API_URL), / (page d'accueil)
'use strict';
const http = require('http');
const os = require('os');

const VERSION = '__VERSION__';
const PORT = process.env.PORT || 8080;
const ENV = process.env.ARVEO_ENV || 'non defini';
const API_URL = process.env.API_URL || '';
const INSTANCE = (process.env.WEBSITE_INSTANCE_ID || os.hostname()).slice(0, 8);

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj) + '\n');
}

http.createServer(async (req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('OK\n');
  }
  if (req.url.startsWith('/api/')) {
    if (!API_URL) {
      return json(res, 503, { erreur: 'API_URL non configuree' });
    }
    try {
      const r = await fetch(API_URL, { signal: AbortSignal.timeout(3000) });
      res.writeHead(r.status, { 'Content-Type': 'application/json' });
      return res.end(await r.text());
    } catch (e) {
      return json(res, 502, { erreur: 'API injoignable', detail: e.message });
    }
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<h1>Arveo - portail client ${VERSION}</h1>` +
    `<p>App Service - ${ENV} - instance ${INSTANCE}</p>\n`);
}).listen(PORT, () => {
  console.log(`Portail Arveo ${VERSION} (${ENV}) a l'ecoute sur le port ${PORT}`);
});

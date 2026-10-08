#!/usr/bin/env bash
# portail-v2.sh — exécuté DANS la VM par l'extension Custom Script (lab 07.6)
# Déploie la version 2 du portail client Arvéo sur vm-stNN-web01 et vm-stNN-web02 :
#   - page d'accueil v2 (nom et zone du serveur) ;
#   - relais /api/ vers l'équilibreur interne de l'API (lbi-stNN-api, 10.NN.5.100:8080).
# __OCT__ est remplacé AVANT l'encodage base64 (sed côté Cloud Shell, replace() côté Bicep).
# Idempotent : relançable sans effet de bord.
set -euo pipefail

API_IP="10.__OCT__.5.100"

# Attente de la fin de cloud-init : sinon la page v1 écrite au premier démarrage écrase la v2
cloud-init status --wait >/dev/null 2>&1 || true

ZONE=$(curl -s -H Metadata:true --max-time 5 \
  "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-02-01&format=text" || true)

cat > /var/www/html/index.html <<EOF
<h1>Arveo - portail client v2</h1><p>Serveur : $(hostname) - zone ${ZONE:-aucune}</p>
EOF

cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 80 default_server;
  root /var/www/html;
  index index.html;
  location / {
    try_files \$uri \$uri/ =404;
  }
  location /api/ {
    proxy_pass http://${API_IP}:8080/;
    proxy_connect_timeout 3s;
  }
}
EOF

nginx -t
systemctl reload nginx
echo "Portail v2 deploye sur $(hostname) (zone ${ZONE:-aucune}), API ${API_IP}:8080"

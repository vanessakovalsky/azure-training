#!/usr/bin/env bash
# simuler-echecs-ssh.sh — défi 10.4 : écrit des échecs d'authentification SSH FACTICES dans le
# journal système de vm-stNN-web01 (logger, facilité authpriv, niveau warning, étiquette sshd).
# - Niveau warning : collecté par dcr-stNN-linux (module 7 : Warning et plus grave).
#   Un vrai sshd journalise ses échecs au niveau info (question 4.b du défi).
# - Adresses réservées à la documentation (RFC 5737) : aucune connexion réelle n'a lieu.
# - 203.0.113.50 dépasse le seuil de la règle (5 en 10 min) ; 198.51.100.7 reste en dessous.
# Usage : ./simuler-echecs-ssh.sh <NN> [<NB_AU_DESSUS>] [<NB_EN_DESSOUS>]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
NB1="${2:-8}"
NB2="${3:-3}"
ST="st${NN}"

SCRIPT="for i in \$(seq ${NB1}); do
  logger -p authpriv.warning -t sshd \"Failed password for invalid user admin from 203.0.113.50 port \$((40000 + i)) ssh2\"
done
for i in \$(seq ${NB2}); do
  logger -p authpriv.warning -t sshd \"Failed password for root from 198.51.100.7 port \$((50000 + i)) ssh2\"
done
echo \"   203.0.113.50 : ${NB1} échecs\"
echo \"   198.51.100.7 : ${NB2} échecs\""

echo "== Échecs SSH simulés sur vm-${ST}-web01 (journal authpriv, niveau warning)"
az vm run-command invoke -g "rg-${ST}-app" -n "vm-${ST}-web01" \
  --command-id RunShellScript --scripts "$SCRIPT" \
  --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
echo "Visibles dans la table Syslog sous 1 à 5 min."

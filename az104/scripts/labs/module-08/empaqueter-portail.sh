#!/usr/bin/env bash
# empaqueter-portail.sh — archive zip du portail Arvéo pour App Service (labs 08.2 et 08.3)
# Remplace __VERSION__ dans server.js, puis crée ~/arveo-build/portail-<VERSION>.zip
# (server.js et package.json à la RACINE de l'archive, condition du déploiement zip).
# Usage : ./empaqueter-portail.sh <VERSION>      (ex. v3, v4)
set -euo pipefail

VERSION="${1:?Version requise (ex. v3)}"
[[ "$VERSION" =~ ^v[0-9]+$ ]] || { echo "Version invalide : $VERSION (format attendu : v3)" >&2; exit 1; }
command -v zip >/dev/null || { echo "Commande zip absente (préinstallée dans Cloud Shell)" >&2; exit 1; }

SRC="$(cd "$(dirname "$0")" && pwd)/portail"
OUT="${HOME}/arveo-build"
ZIP="${OUT}/portail-${VERSION}.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp "${SRC}/package.json" "$TMP/"
sed "s/__VERSION__/${VERSION}/g" "${SRC}/server.js" > "${TMP}/server.js"
if command -v node >/dev/null; then   # contrôle de syntaxe (Node présent dans Cloud Shell)
  node --check "${TMP}/server.js" || { echo "server.js invalide" >&2; exit 1; }
fi

mkdir -p "$OUT"
rm -f "$ZIP"
( cd "$TMP" && zip -q "$ZIP" server.js package.json )

echo "$ZIP"
unzip -Z1 "$ZIP"

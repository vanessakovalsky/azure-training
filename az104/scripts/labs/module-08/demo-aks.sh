#!/usr/bin/env bash
# demo-aks.sh — démonstration AKS de la formatrice (S8.3, J4 vers 10:52)
# Un seul cluster pour le groupe, dans rg-formation-aks, relié au registre de la formatrice.
#   preparer : registre crarveoformation + image de l'API + cluster aks-formation (J-1, 10 à 15 min)
#   demo     : déploiement de l'API (3 réplicas), service LoadBalancer, autoréparation, mise à l'échelle
#   arreter  : arrêt du cluster (calcul non facturé, disques et IP conservés) — après la démo
#   supprimer: suppression du groupe rg-formation-aks (fin de formation)
# Usage : ./demo-aks.sh <preparer|demo|arreter|supprimer>
set -euo pipefail

ACTION="${1:?Action requise : preparer | demo | arreter | supprimer}"
RG="rg-formation-aks"
LOC="francecentral"
AKS="aks-formation"
ACR="crarveoformation"        # [À VÉRIFIER] disponibilité du nom au J-10
IMAGE="arveo/api-suivi-colis:2.0"
DIR="$(cd "$(dirname "$0")" && pwd)"
TAGS=(Projet=Arveo Environnement=Formation Proprietaire=formatrice)

case "$ACTION" in
  preparer)
    az group create -n "$RG" -l "$LOC" --tags "${TAGS[@]}" -o none
    az acr show -n "$ACR" -o none 2>/dev/null \
      || az acr create -g "$RG" -n "$ACR" --sku Basic --tags "${TAGS[@]}" -o none
    az acr build -r "$ACR" -t "$IMAGE" "${DIR}/api" --no-logs -o none
    # Niveau Free (sans SLA), 2 nœuds B2s_v2 ; --attach-acr attribue AcrPull à l'identité des kubelets
    az aks create -g "$RG" -n "$AKS" -l "$LOC" --tier free \
      --node-count 2 --node-vm-size Standard_B2s_v2 --generate-ssh-keys \
      --attach-acr "$ACR" --tags "${TAGS[@]}" -o none
    az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
    kubectl get nodes -o wide
    ;;
  demo)
    az aks start -g "$RG" -n "$AKS" -o none 2>/dev/null || true
    az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing >/dev/null
    kubectl get nodes
    kubectl create deployment api-suivi-colis --image="${ACR}.azurecr.io/${IMAGE}" \
      --replicas=3 --port=8080 --dry-run=client -o yaml | kubectl apply -f -
    kubectl expose deployment api-suivi-colis --type=LoadBalancer --port=80 --target-port=8080 \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl rollout status deployment/api-suivi-colis --timeout=120s
    kubectl get pods -o wide
    echo "Attente de l'IP publique du service (1 à 2 min)"
    for _ in $(seq 24); do
      IP=$(kubectl get svc api-suivi-colis -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
      [[ -n "$IP" ]] && break; sleep 5
    done
    for _ in 1 2 3 4; do curl -s "http://${IP}/"; done
    echo "== Autoréparation : suppression d'un pod"
    kubectl delete "$(kubectl get pods -l app=api-suivi-colis -o name | head -n 1)" --wait=false
    sleep 3; kubectl get pods
    echo "== Mise à l'échelle : 5 réplicas"
    kubectl scale deployment api-suivi-colis --replicas=5
    kubectl rollout status deployment/api-suivi-colis --timeout=120s
    kubectl get pods -o wide
    ;;
  arreter)
    kubectl delete service api-suivi-colis --ignore-not-found   # libère l'IP publique du service
    kubectl delete deployment api-suivi-colis --ignore-not-found
    az aks stop -g "$RG" -n "$AKS" -o none
    az aks show -g "$RG" -n "$AKS" --query "powerState.code" -o tsv
    ;;
  supprimer)
    az group delete -n "$RG" --yes --no-wait
    echo "Suppression de ${RG} lancée (groupe MC_ du cluster supprimé avec lui)"
    ;;
  *)
    echo "Action inconnue : $ACTION" >&2; exit 1 ;;
esac

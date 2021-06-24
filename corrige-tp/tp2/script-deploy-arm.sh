#!/bin/bash

# Se connecter si besoin 
# en mode interactif (navigateur ouvert)
# az login

# uniquement en console
# az login -u <username> -p <password>

# Création groupe ressource
az group create \
    -l eastus \
    -n tp2-vanessa

# Déploiement avec le template 
az deployment group create \
    --resource-group tp2-vanessa \
    --template-file arm-template-vm-python.json \
    --parameters @arm-parameter-vm-python.json
#!/bin/bash

# Se connecter si besoin 
# en mode interactif (navigateur ouvert)
# az login

# uniquement en console
# az login -u <username> -p <password>

# Création groupe ressource
az group create \
    -l eastus \
    -n tp1-vanessa

# Création VM Azure
az vm create \
  --resource-group tp1-vanessa \
  --name node-vm \
  --location eastus \
  --image UbuntuLTS \
  --admin-username azureuser \
  --generate-ssh-keys \
  --custom-data cloud-init-github.txt

# Ouverture du port 80 sur la VM

az vm open-port \
  --port 80 \
  --resource-group tp1-vanessa \
  --name node-vm


# TP 2 - Déploiement avec des templates Azure Resources Manager

Ce TP a pour objectifs : 
* de vous faire créer des templates de ressources
* d'automatiser avec Azure Cli le déploiement des ressources depuis les templates


## Template

Créer un template pour les éléments suivants : 
* Réseau virtuel
* Sous-réseau
* Passerelle NAT
* Groupe de sécurité 
* VM avec commande pour installer une application Flask, voir ici : https://docs.microsoft.com/fr-fr/azure-stack/user/azure-stack-dev-start-howto-vm-python?view=azs-2102#install-python 

## Script 

* Créer un script qui va déployer l'ensemble des templates créé 
* En sortie le script devra afficher le nom de domaine de l'application pour qu'on puisse aller visualiser l'application une fois celle-ci déployer.


## Rendu

Vous devez produire des templates et un script qui effectue les différentes actions nécessaires pour arriver au résultat attendu 
Le tout est à rendre sur Teams (soit directement dans les fichiers soit sous forme d'un lien vers un dépôt git public)

## Pour aller plus loin 
* Ajouter un template pour créer une ressource Azure Storage Blob
* Se connecter depuis l'application Python, à l'aide du SDK sur le conteneur de Azure Storage Blob et déposer un fichier https://docs.microsoft.com/fr-fr/azure/developer/python/azure-sdk-overview 
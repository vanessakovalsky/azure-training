# TP 1 - Automatiser le déploiement d'une application Node JS

L'objectif de ce TP est d'automatiser le déploiement d'une application Web écrite en Node JS sur Azure à l'aide d'Azure CLI

L'application se trouve ici : https://github.com/azure-devops/fabrikam-node 

Les ressources à crée sont les suivantes :
* Groupe de ressource az cli, nommé tp1-$myname (en remplaçant $myname par votre nom)
* Une VM Linux avec Nginx et NodeJs installé et le port 80 ouvert sur cette VM

Une fois la VM créé il faudra déployer le code depuis le dépôt Github et lancer le script deployapp.sh pour que l'application soit utilisable

## Rendu

Vous devez produire un script qui effectue les différentes actions nécessaires pour arriver au résultat attendue 
Le script est à rendre sur Teams (soit directement dans les fichiers soit sous forme d'un lien vers un dépôt git public)

## Pour aller plus loin 

* Ajouter un pipeline Azure qui va builder l'application (faire les actions du script deployapp.sh) et déployer le site à chaque push sur le depôt git.
* Ajouter la mise à l'échelle automatique sur la machine virtuelle depuis Azure Cli
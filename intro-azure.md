# Introduction : installation des outils pour Azure    

Cet exercice a pour objectif :
* de faire le tour de l'interface graphique d'Azure
* d'installer les outils nécessaires à la manipulation des ressources sur Azure

## Interface graphique :
* Se connecter sur https://portal.azure.com 
* * identifiant : votre email
* * mot de passe : celui-fournit
* Pensez à changer votre mot de passe
* A quels items dans le menu avez vous accès ?

## Installation des outils :
L'accès en ligne de commande peut se faire au travers de différents outils :
* PowerShell avec l'installation du module AzureShell
* AzureCli
* Une image docker qui embarque PowerShell et le module AzureShell

Il n'est pas utile d'installer les 3 outils, seulement d'installer l'outil avec lequel vous serez le plus à l'aise, en fonction de vos connaissances et de ce que vous avez déjà d'installé sur vos ordinateurs.

## Installation PowerShell et module AzureShell
* Pour installer PowerShell, suivre les instructions présentes sur cette page : https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7 
* Installer le module AzureShell dans Power Shell : https://docs.microsoft.com/fr-fr/powershell/azure/install-az-ps?view=azps-5.0.0 

## Installation AzureCLI
* Pour installer AzureCLI, suivre les instructions présentes sur cette page : https://docs.microsoft.com/fr-fr/cli/azure/install-azure-cli 

## Pour utiliser AzureCli dans un conteneur Docker :
* Suivre les instructions de cette page : https://docs.microsoft.com/fr-fr/cli/azure/run-azure-cli-docker 

# Accèder à l'outil depuis la GUI :

* Depuis l'interface graphiquer cliquer sur l'icone du shell :
[https://docs.microsoft.com/fr-fr/azure/cloud-shell/media/overview/overview-cloudshell-icon.png] 
* Choisir si vous préfèrez utiliser Bash (AzureCli) ou PowerShell 
* Cela doit ouvrir une fenêtre sur votre ordinateur avec le bon outil, vous permettant ainsi de manipuler les différentes ressources en ligne de commande.

-> Félicitations, vous êtes prêt à explorer les ressources de Azure
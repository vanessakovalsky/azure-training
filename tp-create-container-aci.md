# Exercice - Créer des instances Azure Container

## Objectifs

Dans cet exercice vous allez:

- Tâche 1: Deployer une image Docker en utilisant Azure Container Instance
- Tâche 2: Parcourir les fonctionnalités de Azure Container Instance

## Temps estimé: 20 minutes

## Tâche 1: Deployer une image Docker en utilisant Azure Container Instance

1. Se connecter au [Azure portal](https://portal.azure.com).

1. Dans le portail Azure, rechercher et sélectionner **Container instances** puis, sur l'écran **Container instances**, cliquer sur **+ New**.

1. Sur l'onglet **Basics** de l'écran **Create container instance**,  définir les paramètres suivants (en laissant les autres paramètres par défaut):

    | Setting | Value |
    | ---- | ---- |
    | Subscription | le nom de l'abonnement que vous utilisez pour cet exercice |
    | Resource group | le nom d'un nouveau groupe de ressource **az104-09b-rg1-$myname** |
    | Container name | **az104-9b-c1** |
    | Region | le nom d'une région où l'on peut créer des instances Azure Containers |
    | Image Source | **Quickstart images** |
    | Image | **mcr.microsoft.com/azuredocs/aci-helloworld:latest (Linux)** |

1. Cliquer sur **Next: Networking >** et, sur l'onglet **Networking** de l'écran **Create container instance**, définir les paramètres suivants (en laissant les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | DNS name label | tout DNS unique et valide |

    >**Note**: Votre conteneur sera accessible publiquement à  dns-name-label.region.azurecontainer.io. Si vous obtenez un message d'erreur **DNS name label not available** , choisir une valeur différente.

1. Cliquer sur **Next: Advanced >**, vérifier les paramètres de l'onglet **Advanced** sur l'écran **Create container instance** sans faire de modifications, cliquer sur **Review + Create**, vérifier que la validation est passée et cliquer sur **Create**.

    >**Note**: Attendre que le déploiement soit complet. Cela devrait prendre environ 3 minutes.

    >**Note**: Pendant que vous patienter, vous serez peut être intéressé pour voir le [code derrière l'application exemple](https://github.com/Azure-Samples/aci-helloworld). Pour le voir, naviguer dans le dossier app.

## Tâche 2: Parcourir les fonctionnalités de Azure Container Instance

1. Sur l'écran de déploiement, cliquer sur le lien **Go to resource**.

1. Dans l'onglet **Overview** de l'instance de conteneur, vérifier que **Status** est positionné sur **Running**.

1. Copie la valeur **FQDN** de l'instance de conteneur, ouvrir un nouvel onglet dans le navigateur, et se rendre à l'URL correspondante.

1. Vérifier que la page affiche **Welcome to Azure Container Instance**.

1. Fermer le nouvel onglet de navigateur, revenir sur le portail Azure, dans la section **Settings** de l'écran de l'instance de conteneur, cliquer sur **Containers**, puis cliquer sur **Logs**.

1. Vérifier que vous voyez les entrées de logs qui représente les requêtes HTTP GET générées en affichant l'application dans le navigateur.

## Nettoyage des ressources

  >**Note**: Souvenez-vous de supprimer toutes les ressources Azure crées que vous n'utilisez plus. En supprimant les ressources non nécessaires, vous vous assurez de ne pas être facturé en plus.

1. Dans le portail Azure, démarrer une session **PowerShell** avec **Cloud Shell**.

1. Lister tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante :

   ```powershell
   Get-AzResourceGroup -Name 'az104-09b*'
   ```

1. Supprimer tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante:

   ```powershell
   Get-AzResourceGroup -Name 'az104-09b*' | Remove-AzResourceGroup -Force -AsJob
   ```

   >**Note**: La commande s'exécute de manière asynchrone (comme demandé par le paramèter -AsJob), donc vous pouvez relancer immédiatement une autre commande PowerShell dans la même session PowerShell, cela prendra quelques minutes avant que le groupes de ressources ne soit réellement supprimé.
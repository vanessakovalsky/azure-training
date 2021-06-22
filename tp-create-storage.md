
# Exercice - Gestion Azure Storage


## Objectifs

Dans cet exercice vous allez 


+ Tâche 1: Créer et configurer les comptes Azure Storage
+ Tâche 2: Gérer les blob storage
+ Tâche 3: Gérer l'authentification et les authorisations pour Azure Storage

Bonus : 
+ Tâche 4: Création de l'environnement
+ Tâche 5: Créer et configurer un partage Azure Files
+ Tâche 6: Gérer les accès réseaux sur Azure Storage

## Temps estimé: 40 minutes


## Tâche 1: Créer et configurer les comptes Azure Storage


1. Dans le portail Azure, rechercher et sélectionner **Storage accounts**, puis cliquer **+ New**.

1. Sur l'onglet **Basics** de l'écran **Create storage account**, définir les paramètres suivants (en remplaçant $myname par votre nom et en laissant les autres valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Subscription | Nom de l'abonnement Azure que vous utilisé |
    | Resource group | le nom du **nouveau** groupe de ressources **az104-07-rg1-$myname** |
    | Storage account name | tout nom unique global d'une longueur comprise entre 3 et 24 constitués de lettre et de chiffres |
    | Location | Le nom d'une région Azure où vous pouvez créer votre compte Azure Storage  |
    | Performance | **Standard** |
    | Redundancy | **Geo-redundant storage (GRS)** |

1. Cliquer **Next: Advanced >**, sur l'onglet **Advanced** de la page **Create storage account**, vérifier les options disponibles, accepter celle par défaut et cliquer sur **Next: Networking >**.

1. Sur l'onglet **Networking** de la page **Create storage account**, vérifier les options disponibles, accepter l'option par défaut  **Public endpoint (all networks}** et cliquer sur **Next: Data protection >**.

1. Sur l'onglet **Data protection** de la page **Create storage account**, vérifier les options disponibles, accepter celle par défaut et cliquer sur **Review + Create**, attendre que le processe de validation soit complet et cliquer sur **Create**.

    >**Note**: Attendre que le compte de Stockage soit crée. Cela devrait prendre environ 2 minutes.

1. Sur l'écran de déploiement, cliquer sur **Go to resource** pour afficher le compte de Stockage Azure.

1. Sur l'écran du compte de Stockage, dans la section **Data management**, cliquer sur **Geo-replication** et noter la deuxième localisation. 

1. Sur l'écran du compte de Stockage, dans la section **Settings**, selectionner **Configuration**, dans la liste déroulante **Replication** selectionner **Locally redundant storage (LRS)** et enregistrer les changements.

1. Revenir à l'écran **Geo-replication** et voir que à ce point, le compte de Stockage n'a que la localisation primaire.

1. Afficher de nouveau l'écran de **Configuration** du compte de Stockage, définir **Blob access tier (default)** sur **Cool**, et enregistrer les modifications.

    > **Note**: Le tier accès froids est optimum pour les données qui ne sont pas accédées souvent.

## Tâche 2: Gérer les blob storage


1. Sur l'écran du compte de Stockage, dans la section  **Data storage**, cliquer sur **Containers**.

1. Cliquer sur **+ Container** et créer un conteneur avec les paramètres suivants (en remplaçant $myname par votre nom) :

    | Setting | Value |
    | --- | --- |
    | Name | **az104-07-container-$myname**  |
    | Public access level | **Private (no anonymous access)** |

1. Dans la liste des conteneurs, cliquer sur **az104-07-container-$myname** et cliquer sur **Upload**.

1. Télécharger et ouvrir ce fichier https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/07/LICENSE .

1. Sur l'écran **Upload blob**, ouvrir la section **Advanced** et spécifier les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- | --- |
    | Authentication type | **Account key**  |
    | Blob type | **Block blob** |
    | Block size | **4 MB** |
    | Access tier | **Hot** |
    | Upload to folder | **licenses** |

    > **Note**: L'accès tier ne peut pas être définir pour chaque objet individuel.

1. Cliquer sur **Upload**.

    > **Note**: Noter que l'envoi du fichier crée automatiquement un sous-dossier nommé **licenses** comme indiqué dans les paramètres de l'objet.

1. Revenir à l'écran **az104-07-container-$myname** blade, cliquer sur **licenses** puis cliquer sur **LICENSE**.

1. Sur l'écran **licenses/LICENSE**, vérifier les options disponibles.

    > **Note**: Vous avez la possibilité de télécharger l'objet, de changer son accès tier (actuellement positionné sur **Hot**), mettre un verrou, ce qui aura pour effet de changer son statut pour **Locked** (il est actuellement défini sur  **Unlocked**) et protégé l'objet des modifications ou suppressions, ou bien assignés des métadonnées personnalisées (en définissant une pair clé/valeur arbitraire). Vous avez aussi la possibilité de **Modifier** le fichier deirectement dans l'interface du Portail Azure, sans avoir besoin de le télécharger d'abord. Vous pouvez aussi créer des instantannées, ou généré un jeton SAS (voir la tâche suivante).

## Tâche 3: Gérer l'authentification et les authorisations pour Azure Storage


1. Dans l'écran **licenses/LICENSE**, sur l'onglet **Overview**, cliquer sur le bouton **Copy to clipboard** à côté de l'**URL**.

1. Ouvrir un navigateur en mode privé et coller l'URL copiée à l'étape précédente.

1. Vous devriez obtenir un message formatté en XML de type **ResourceNotFound** ou **PublicAccessNotPermitted**.

    > **Note**: C'est normal, puisque le conteneur que vous avez créer à son niveau d'accès public défini sur  **Private (no anonymous access)**.

1. Fermer le navigateur privé et retourner sur la page qui affiche  **licenses/LICENSE** du conteneur Azure Storage, et aller sur l'onglet **Generate SAS**.

1. Sur l'onglet **Generate SAS** de l'écran **licenses/LICENSE**, spécifier les paramètres suivants (en laissant les autres paramètres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Signing key | **Key 1** |
    | Permissions | **Read** |
    | Start date | yesterday's date |
    | Start time | current time |
    | Expiry date | tomorrow's date |
    | Expiry time | current time |
    | Allowed IP addresses | leave blank |
    

1. Cliquer sur **Generate SAS token and URL**.

1. Cliquer sur le bouton **Copy to clipboard** à côté de **Blob SAS URL**.

1. Ouvrir un navigateur en mode privé et coller l'URL copiée à l'étape précédente..

    > **Note**: Si vous utilisez  Microsoft Edge, vous devriez voir la page **The MIT License (MIT)**. Si vous utiliser Chrome, Chromium ou Firefox, vous devriez pouvoir voir le contenu du fichier après l'avoir télécharger et ouvert avec un éditeur de texte.

    > **Note**: C'est ce qui est prévu, puisque votre accès est maintenant basé sur le jeton SAS nouvellement généré.

    > **Note**: Enregistrer l'URL de l'objet SAS. Vous en aurez besoin plus tard.

1. Fermer le navigateur privé et retourner sur la page qui affiche  **licenses/LICENSE** du conteneur Azure Storage, et retourner sur l'écran **az104-07-container-$myname**.

1. Cliquer sur le lien **Switch to the Azure AD User Account** à côté du libellé **Authentication method**.

    > **Note**: Vous pouvez voir une erreur lorsque vous changer de méthode d'authentification (l'erreur est *"You do not have permissions to list the data using your user account with Azure AD"*). C'est normal.  

    > **Note**: A ce moment, vous n'avez plus accès au conteneur.

1. Sur l'écran **az104-07-container-$myname**, cliquer sur **Access Control (IAM)**.

1. Dans la section **Add**, cliquer sur **Add a role assignment**.

1. Sur l'écran **Add role assignment**, définir les paramètres suivants :

    | Setting | Value |
    | --- | --- |
    | Role | **Storage Blob Data Owner** |
    | Assign access to | **User, group, or service principal** |
    | Select | le nom du compte utilisateur |

1. Enregistrer les modifications et retourner sur l'écran **Overview** du conteneur  **az104-07-container-$myname** et vérifier que vous pouvez de nouveau accéder au conteneur.

    > **Note**: Cela peut prendre jusqu'à 5 minutes pour que le changement soit effectif.

## Bonus

## Tâche 4: Création de l'environnement

1. Se connecter au [Azure portal](https://portal.azure.com).

1. Dans le portail Azure, ouvrir **Azure Cloud Shell** en cliquant sur l'icône en hait à droite du Portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**. 

    >**Note**: Si c'est la première fois que vous démarrer **Cloud Shell** vous aurez un message  **You have no storage mounted**, selectionner l'inscription que vous utiliser pour cette exercie et cliquer sur **Create storage**. 

1. Dans la barre d'outil de Cloud Shell, cliquer sur l'icône **Upload/Download files** , dans le menu déroulant, cliquer sur  **Upload**, et télécharger les fichiers **https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/07/az104-07-vm-template.json** et **https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/07/az104-07-vm-parameters.json** dans le home directory du Cloud Shell.

1. Depuis le paneau Cloud Shell, exécuter les commande suivantes pour créer le groupe de ressource qui hébergera la machine vivrutel (remplacer le  `[Azure_region]`  avec le nom de la région Azure où vous voulez déployer votre machine virtuelle et remplacer $myname par votre nom) 

    >**Note**: Pour obtenir la liste des noms des régions Azure, exécuter `(Get-AzLocation).Location`

   ```powershell
   $location = '[Azure_region]'

   $rgName = 'az104-07-rg0-$myname'

   New-AzResourceGroup -Name $rgName -Location $location
   ```
1. Depuis le paneau Cloud Shell, exécuter les commande suivantes pour déployer la machine virtuel en utilisant le template téléchargé et le fichier de paramètres :

   ```powershell
   New-AzResourceGroupDeployment `
      -ResourceGroupName $rgName `
      -TemplateFile $HOME/az104-07-vm-template.json `
      -TemplateParameterFile $HOME/az104-07-vm-parameters.json `
      -AsJob
   ```

    >**Note**: Ne pas attendre que le déploiement soit terminé, mais avancer sur la tâche suivante.

1. Fermer le panneau Cloud Shell.

#### Tâche 5: Créer et configurer un partage Azure Files

> **Note**: Avant de commencer cette tâche, assurez vous que la machine virtuel crée lors de la première tâche fonctionne.

1. Dans le portail Azure, revenir à l'écran du compte de stockage créé lors de la première tâche et dans la section **Data storage**, cliquer sur **File shares**.

1. Cliquer sur **+ File share**  et un créer un partage de fichier avec les paramètres suivants (en remplaçant $myname par votre nom):

    | Setting | Value |
    | --- | --- |
    | Name | **az104-07-share-$myname** |
    | Quota | **1024** |

1. Cliquer sur le partage de fichier que vous venez de créer et cliquer sur **Connect**.

1. Sur l'écran **Connect** , assurez vous que l'onglet **Windows** est sélectionné. Vous trouvez alors en dessous une zone de texte grise avec un script, sélectionner l'ensemble du script et dans coin en bas à droit de cette zone et cliquer sur  **Copy to clipboard**.

1. Dans le portail Azure, rechercher et sélectionnerIn the Azure portal,  **Virtual machines**, et, dans la liste des machines virtuelles cliquer sur **az104-07-vm0-$myname**.

1. Sur l'écran **az104-07-vm0-$myname**, dans la section **Operations**, cliquer sur **Run command**.

1. Sur l'écran **az104-07-vm0-$myname - Run command**, cliquer sur **RunPowerShellScript**.

1. Sur l'écran **Run Command Script**, copier le script que vous avez copier plus tôt dans le panneau  **PowerShell Script** et cliquer sur **Run**.

1. Vérifier que le script s'est exécuté correctement.

1. Remplacer le contenu du panneau **PowerShell Script** avec le script suivant et cliquer sur **Run**:

   ```powershell
   New-Item -Type Directory -Path 'Z:\az104-07-folder'

   New-Item -Type File -Path 'Z:\az104-07-folder\az-104-07-file.txt'
   ```

1. Vérifier que le script s'est exécuté correctement.

1. Revenir à l'écran de partage de fichier  **az104-07-share-$myname**, cliquer sur **Refresh**, et vérifier que **az104-07-folder** apparait dans la liste des dossiers.

1. Cliquer sur **az104-07-folder** et vérifier que  **az104-07-file.txt** apparait dans la liste des fichiers.

## Tâche 6: Gérer les accès réseaux sur Azure Storage

1. Dans le portail Azure, revenir à l'écran du compte de stockage crée précédemment, dans la section **Security + Networking**, cliquer sur  **Networking** puis cliquer sur **Firewalls and virtual networks**.

1. Cliquer sur l'option **Selected networks** et vérifier les paramètres de configurationoption qui deviennent disponible une fois cette option activée.

    > **Note**: Vous pouvez utiliser ces paramètres pour configurer une connection directentre entre des machines virtuelles Azure sur des sous-réseau désignée de réseau virtuel et des comptes de stockage en utilisant les services de points de terminaisons.

1. Cocher la case de **Add your client IP address** et enregistrer les modifications.

1. Ouvrir un navigateur en mode privé et coller l'URL de l'objet SAS généré dans la tâche précédente.

1. Vous devriez avoir une page qui affiche **The MIT License (MIT)**.

    > **Note**: C'est ce qui est attendu puisque vous êtes connectés depuis votre adresse IP cliente.

1. Fermer le navigateur privé et retourner sur la page qui affiche  **licenses/LICENSE** du conteneur Azure Storage,et ouvrir le panneau Azure Cloud Shell.

1. Dans le portail Azure, ouvrir **Azure Cloud Shell** en cliquant sur l'icône en haut à droite du Portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**. 

1. Depuis le panneau de Cloud Shell, exécuter la tentative suivante de téléchargement de l'objet LICENCE depuis le conteneur  **az104-07-container-$myname** du compte de stockage(remplacer `[blob SAS URL]` par votre URL d'objet SAS générée à la tâche précédente):

   ```powershell
   Invoke-WebRequest -URI '[blob SAS URL]'
   ```
1. Vérifier que la tentatibe de téléchargement échoue.V

    > **Note**: Vous devriez obtenir un message disant :  **AuthorizationFailure: This request is not authorized to perform this operation**. C'est normal, puisque vous vous connecter depuis l'adresse IP assignée à un VM Azure qui contient l'instance de Cloud Shell.

1. Fermer le panneau Cloud Shell.

## Nettoyage des ressources

   >**Note**: Souvenez-vous de supprimer toutes les ressources Azure crées que vous n'utilisez plus. En supprimant les ressources non nécessaires, vous vous assurez de ne pas être facturé en plus.

1. Dans le portail Azure, démarrer une session **PowerShell** avec **Cloud Shell**.

1. Lister tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante :

   ```powershell
   Get-AzResourceGroup -Name 'az104-07*'
   ```

1. Supprimer tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante:

   ```powershell
   Get-AzResourceGroup -Name 'az104-07-$myname*' | Remove-AzResourceGroup -Force -AsJob
   ```

    >**Note**: La commande s'exécute de manière asynchrone (comme demandé par le paramèter -AsJob), donc vous pouvez relancer immédiatement une autre commande PowerShell dans la même session PowerShell, cela prendra quelques minutes avant que le groupes de ressources ne soit réellement supprimé.

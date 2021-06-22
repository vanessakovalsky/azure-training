# Exercice - Implémenter un réseau virtuel

## Objectifs

Dans cet exercice vous allez:

+ Tâche 1: Créer et configurer un réseau virtuel
+ Tâche 2: Déployer des machines virtuelles sur le réseau virtuel
+ Tâche 3: Configurer les adresses IP privés et publiques des VM Azure
+ Tâche 4: Configurer les groupes de sécurités réseau 
+ Tâche 5: Configurer les DNS Azure pour la résolution interne de nom de domaine 
+ Tâche 6: Configure les DNS Azure pour la résolution externe de nom de domaine

## Temps estimé: 40 minutes

## Tâche 1: Créer et configurer un réseau virtuel

1. Se connecter au [Azure portal](https://portal.azure.com).

1. Dans le portail Azure, rechercher et sélectionner **Virtual networks**, sur l'écran **Virtual networks** , cliquer sur **+ Add**.

1. Créer un réseau virtuel avec les paramètres suivants :  (laisser les autres valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement Azure que vous utilisez |
    | Resource Group | le nom d'un **nouveau** groupe de ressource **az104-04-rg1-$myname** |
    | Name | **az104-04-vnet1** |
    | Region | le nom de la région Azure disponible dans l'abonnement que vous utilisez pour cet exercice |

1. Cliquer sur **Next : IP Addresses** et entrer les valeur suivantes 

    | Setting | Value |
    | --- | --- |
    | IPv4 address space | **10.40.0.0/20** |

1. Cliquer sur  **+ Add subnet** et entre les valeurs suivantes puis cliquer sur **Add**

    | Setting | Value |
    | --- | --- |
    | Subnet name | **subnet0** |
    | Subnet address range | **10.40.0.0/24** |

1. Accepter les valeurs par défaut et cliquer sur **Review and Create**. Laisser la validation se faire, et cliquer sur  **Create** de nouveau pour soumettre le déploiement.

    >**Note:** Attendre que le réseau virtuel soit créé.Cela devrait prendre moins d'une minute. .

1. Cliquer sur **Go to resource**

1. Sur l'écran du réseau virtuel **az104-04-vnet1** , cliquer sur **Subnets** puis cliquer sur **+ Subnet**.

1. Créer un sous-réseau avec les valeurs suivantes (en remplaçant $myname par votre nom et en laissant les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | Name | **subnet1-$myname** |
    | Address range (CIDR block) | **10.40.1.0/24** |
    | Network security group | **None** |
    | Route table | **None** |

1. Cliquer sur **Save**

## Tâche 2: Déployer des machines virtuelles sur le réseau virtuel

1. Dans le portail Azure, ouvrez **Azure Cloud Shell** en cliquant sur l'icône en haut à droite du portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**.

     >**Note**: Si c'est la première fois que vous démarrer **Cloud Shell** vous aurez un message  **You have no storage mounted**, selectionner l'inscription que vous utiliser pour cette exercie et cliquer sur **Create storage**. 

1. Dans la barre d'outil de Cloud Shell, cliquer sur l'icône **Upload/Download files** , dans le menu déroulant, cliquer sur  **Upload**, et télécharger les fichiers **https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/04/az104-04-vms-loop-template.json** and **https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/04/az104-04-vms-loop-parameters.json** dans le home directory du Cloud Shell..

    >**Note**: Vous devez envoyer chaque fichier séparément .

1. Depuis le paneau du Cloud Shell, exécuter le script suivant pour déployer deux machines virtuelles en utilisant les fichiers de templates et de paramètre que vous avez envoyer:

   ```powershell
   $rgName = 'az104-04-rg1-$myname'

   New-AzResourceGroupDeployment `
      -ResourceGroupName $rgName `
      -TemplateFile $HOME/az104-04-vms-loop-template.json `
      -TemplateParameterFile $HOME/az104-04-vms-loop-parameters.json
   ```

    >**Note**: Cette méthode de déploiement en utilisant les templates ARM utilise Azure PowerShell. Vous pouvez faire la même chose en utilisant la commande équivalente avec Azure CLI **az deployment create** (pour plus d'information, voir ici [Déployer des ressources à l’aide de modèles ARM et l’interface CLI Azure](https://docs.microsoft.com/fr-fr/azure/azure-resource-manager/templates/deploy-cli).

    >**Note**: Attendre que le déploiement soit terminé avant de passer à la tache suivante. Cela devrait prendre environ 2 minutes.

1. Fermer le panneau Cloud Shell.

#### Tâche 3: Configurer les adresses IP privés et publiques des VM Azure

   >**Note**: Les adresses IP publiques et privés sont actuellement assignées aux interfaces réseaux, qui sont elle mêmes attachés aux machine virtuelle Azure, cependant on fait souvent référence aux adresses IP assignées aux VM Azure plutôt.

1. Dans le portail Azure, rechercher et sélectionner **Resource groups**, et, sur l'écran **Resource groups**, cliquer sur **az104-04-rg1-$myname**.

1. Sur l'écran du groupe de ressource **az104-04-rg1-$myname**, dans la liste de ses ressources, cliquer sur **az104-04-vnet1-$myname**.

1. Sur l'écran su réseau virtuel **az104-04-vnet1-$myname**, vérifier la section **Connected devices** et vérifier qu'il y a deux interfaces réseaux **az104-04-nic0** and **az104-04-nic1** attaché au réseau virtuel.

1. Cliquer sur **az104-04-nic0** et, sur l'écran **az104-04-nic0**, cliquer sur **IP configurations**.

    >**Note**: Vérifier que **ipconfig1** est actuellement définit avec une adresse IP privé dynamique.

1. Dans la liste des configurations IP, cliquer sur **ipconfig1**.

1. Dans l'écran **ipconfig1**, dans la section **Public IP address settings**, selectionner **Associate**, cliquer sur **+ Create new**, définir les paramètres suivants et cliquer sur **OK**:

    | Setting | Value |
    | --- | --- |
    | Name | **az104-04-pip0-$myname** |
    | SKU | **Standard** |

1. Dans l'écran **ipconfig1**, définir **Assignment** à **Static**, supprimer la valeur par défaut de  **IP address** et remplacer là par **10.40.0.4**.

1. Revenir à l'écran **ipconfig1**, enregistrer les changements. Assurez vous d'attendre que l'opération de sauvegarde soit complète avant de passer à l'étape suivante.

1. Revenir à l'écran **az104-04-vnet1**

1. Cliquer sur **az104-04-nic1** et, sur l'écran **az104-04-nic1**, cliquer sur **IP configurations**.

    >**Note**: Vérifier que **ipconfig1** est actuellement définit avec une adresse IP privé dynamique.

1. Dans la liste des configurations IP, cliquer sur **ipconfig1**.

1. Dans l'écran **ipconfig1**, dans la section **Public IP address settings**, selectionner **Associate**, cliquer sur **+ Create new**, définir les paramètres suivants et cliquer sur **OK**: 


    | Setting | Value |
    | --- | --- |
    | Name | **az104-04-pip1-$myname** |
    | SKU | **Standard** |

1. Dans l'écran **ipconfig1**, définir **Assignment** à **Static**, supprimer la valeur par défaut de  **IP address** et remplacer là par **10.40.1.4**.

1. Revenir à l'écran **ipconfig1**, enregistrer les changements. 

1. Revenir à l'écran du groupe de ressource **az104-04-rg1-$myname**, dans la liste de ses ressources, cliquer sur **az104-04-vm0**, et depuis l'écran de la machine virtuelle **az104-04-vm0**, noter l'entrée adresse IP publique.

1. Revenir à l'écran du groupe de ressource **az104-04-rg1-$myname**, dans la liste de ses ressources, cliquer sur **az104-04-vm1**, et depuis l'écran de la machine virtuelle **az104-04-vm1**, noter l'entrée adresse IP publique.


    >**Note**: Vous aurez besoin des deux adresse IP dans la dernière tâche de cet exercice.

## Tâche 4: Configurer les groupes de sécurités réseau

1. Dans le portail Azure, revenir à l'écran de groupe de  ressource **az104-04-rg1-$myname**, et dans la liste de ces ressources cliquer sur **az104-04-vm0**.

1. Sur l'aperçu de **az104-04-vm0**, cliquer sur **Connect**, cliquer sur **RDP** dans le menu déroulant, sur l'écran **Connect with RDP**, cliquer sur **Download RDP File** en utilisant l'adresse IP publique et en suivant le prompt pour démarrer la session Remote Desktop.

1. Noter que la tentative de connexion echoue.

    >**Note**: Cela est normal, car l'adresse IP publique des SKU standard, par défaut, nécessite que l'interface réseau  sur lesquels ils sont assignées soit protégés par un groupe de sécurité réseau. Pour autoriser la connection Remote Desktop, vous allez créer un groupe de sécurité réseau qui autorise explicitement le trafic RDP entran depuis Internet et l'assigner sur l'interface réseau de nos deux machines virtuelles.

1. Dans le portail Azure, rechercher et sélectionner **Network security groups**, et, sur l'écran **Network security groups**, cliquer sur **+ Add**.

1. Créer un groupe de sécurité réseau avec les paramètres suivants (en laissant les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement azure utilisé pour cet exercice |
    | Resource Group | **az104-04-rg1-$myname** |
    | Name | **az104-04-nsg01** |
    | Region | le nom de la région Azure que vous utiliser pour cet exercice |

1. Cliquer sur **Review and Create**. Attendre la validation et appuyer sur **Create** pour soumettre le déploiement.

    >**Note**: Attendr que le déploiement soit terminé. Cela devrait prendre environ 2 minutes.

1. Sur l'écran de déploiement, cliquer **Go to resource** pour ouvrir l'écran du groupe de sécurité réseau **az104-04-nsg01**.

1. Sur l'écran du groupe de sécurité réseau **az104-04-nsg01**, dans la section **Settings**, cliquer sur **Inbound security rules**.

1. Ajouter une règle entrante avec les paramètres suivants (en laissant les autres valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Source | **Any** |
    | Source port ranges | * |
    | Destination | **Any** |
    | Service | **RDP** |
    | Action | **Allow** |
    | Priority | **300** |
    | Name | **AllowRDPInBound** |

1. Sur l'écran du groupe de sécurité réseau **az104-04-nsg01**, dans la section **Settings**, cliquer sur **Network interfaces** puis cliquer sur **+ Associate**.

1. Associer le groupe de sécurité réseau **az104-04-nsg01** avec les interfaces réseau **az104-04-nic0** et **az104-04-nic1**.

    >**Note**: Cela peut prendre 5 minutes pour que les règles du nouveau Groupe de Sécurité Réseau soit appliquer sur la carte d'Interface Réseau.

1. Revenir à l'écran machine virtuelle **az104-04-vm0**.

    >**Note**: Dans les étapes suivantes, vous vérifierez que vous pouvez vous connecter avec succ-s à la machine virtuel cibleet se connecter en utilisant le nom d'utilisateur **Student** et le mot de passe **Pa55w.rd1234**.

1. Sur l'écran **az104-04-vm0**, cliquer sur **Connect**, cliquer sur **RDP**, sur l'écran **Connect with RDP**, cliquer sur **Download RDP File** en utilisant l'adresse IP publique et en suivant le prompt pour démarrer la session Remote Desktop.

    >**Note**: Ces étapes font référence à une connexion via Remote Desktop sur un ordinateur Windows. Sur un Mac, vous pouvez utiliser Remote Desktop Client depuis Mac App Store et sur les ordinateurs sous Linux, vous pouvez utiliser un client RDP Open Source.

    >**Note**: Vous pouvez ignorer les avertissements du prompts lors de votre connexion aux machines virtuelles cibles..

1. Lorsqu'on vous le demande, se connecter en utilisant l'identifiant **Student** et le mot de passe **Pa55w.rd1234**.

    >**Note**: Laisser la session Remote Desktop ouverte. Vous en aurez besoin dans la tâche suivante.

## Tâche 5: Configure Azure DNS for internal name resolution


1. Dans le portail Azure, rechercher et sélectionner **Private DNS zones** et, sur l'écran **Private DNS zones** , cliquer sur **+ Add**.

1. Créér une zone privé DNS avec les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement azure que vous utilisez pour cet exercice |
    | Resource Group | **az104-04-rg1-$myname** |
    | Name | **kovalibre.org** |

1. Cliquer sur **Review and Create**. Attendre que la validation soit faite, et appuyer de nouveau sur **Create** pour soumettre votre déploiement.

    >**Note**: Attendre que la zone privé DNS soit créé. Cela devrait prendre environ 2 minutes.

1. Cliquer sur **Go to resource** pour ouvrir l'écran de la zone privé DNS **kovalibre.org**.

1. Sur l'écran de la zone privé DNS **kovalibre.org**, dans la section **Settings**, cliquer sur **Virtual network links**

1. Cliquer sur **+ Add** pour créer un lien vers un réseau virtuel avec les paramètres suivants (laisser les autres paraamètres avec leurs valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Link name | **az104-04-vnet1-link** |
    | Subscription | le nom de l'abonnement azure que vous utilisez pour cet exercice |
    | Virtual network | **az104-04-vnet1** |
    | Enable auto registration | enabled |

1. Cliquer sur **OK**.

    >**Note:** Attendre que le lien vers le réseau virtuel soit crée. Cela devrait prendre moins d'une minute.

1. Sur l'écran de la zone privé DNS **kovalibre.org**, dans la  sidebar, cliquer sur **Overview**

1. Vérifier que l'enregistrement DNS pour  **az104-04-vm0** et **az104-04-vm1** apparait dans la lists des enregistrements comme **Auto registered**.

    >**Note:** Vous aurez peut être besoin d'attendre quelqques minutes et de rafraichier la page si les enregistrements ne sont pas listés.

1. Revenir sur la session Remote Desktop de **az104-04-vm0**, faire un clic-droit sur le bouton **Start** et, dans le menu du clic-droit, cliquer sur **Windows PowerShell (Admin)**.

1. Dans la fenêtre de console Windows PowerShell, exécuter le test suivant de résolution interne de nom dans la nouvelle zone privé DNS:

   ```powershell
   nslookup az104-04-vm0.kovalibre.org
   nslookup az104-04-vm1.kovalibre.org
   ```

1. Vérifier que la sortie de la commande inclut l'adresse IP privé de **az104-04-vm1** (**10.40.1.4**).

#### Tâche 6: Configure les DNS Azure pour la résolution externe de nom de domaine


1. Dans le navigateur web, ouvrir un nouvel onglet et aller sur  <https://www.godaddy.com/domains/domain-name-search>.

1. Utiliser la recherche de nomo de domaine pour identifier un nom de domaine qui n'est pas utilisé.

1. Dans le portail Azure, rechercher et sélectionner **DNS zones** et, sur l'écran **DNS zones**, cliquer sur **+ Add**.

1. Créer une zone DNS avec les paramètres suivants (laisser les autres paramètres avec leurs valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement azure que vous utilisez pour cet exercice |
    | Resource Group | **az104-04-rg1-$myname** |
    | Name | le nom DNS que vous avez identifié à l'étape précédente |

1. Cliquer sur **Review and Create**. Attendre que la validation soit faite et appuyer de nouveau sur **Create** pour soumettre votre déploiement.

    >**Note**: Attendre que la zone DNS soit créé. Cela devrait prendre environ 2 minutes.

1. Cliquer **Go to resource** pour ouvrir l'écran de la zone DNS nouvellement créé.

1. Sur l'écran de la zone DNS, cliquer sur **+ Record set**.

1. Ajouter un enregistrement avec les paramètres suivants (laisser les autres paramètres avec leurs valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Name | **az104-04-vm0** |
    | Type | **A** |
    | Alias record set | **No** |
    | TTL | **1** |
    | TTL unit | **Hours** |
    | IP address | l'adresse IP publique **az104-04-vm0** identifié lors de la tâche 3 de cet exercice |

1. Cliquer sur **OK**

1. Sur l'écran de la zone DNS, cliquer sur **+ Record set**.

1. Ajouter un enregistrement avec les paramètres suivants (laisser les autres paramètres avec leurs valeurs par défaut):

    | Setting | Value |
    | --- | --- |
    | Name | **az104-04-vm1** |
    | Type | **A** |
    | Alias record set | **No** |
    | TTL | **1** |
    | TTL unit | **Hours** |
    | IP address | l'adresse IP publique **az104-04-vm1** identifié lors de la tâche 3 de cet exercice |

1. Cliquer sur **OK**

1. Sur l'écran de la zone DNS, noter le nom de l'entrée **Name server 1**.

1. Dans le portail Azure, ouvrir une session **PowerShell** dans **Cloud Shell** en cliquant sur l'icône en haut à droite du portail.

1. Dans le panneau Cloud Shell, exécuter le test suivant de résolution de nom externe de l'enregistrement DNS de **az104-04-vm0**  dans la zone que nous venons de créé. (remplacer `[Name server 1]` avec le nom de **Name server 1** que vous avez noter précédemment dans cette tâche et `[domain name]` par le nom du domaine DNS créé plus tôt dans cette tâche):

   ```powershell
   nslookup az104-04-vm0.[domain name] [Name server 1]
   ```

1. Verifier que la sortie de la commande inclut l'adresse IP publique de **az104-04-vm0**.

1.  Dans le panneau Cloud Shell, exécuter le test suivant de résolution de nom externe de l'enregistrement DNS de **az104-04-vm1**  dans la zone que nous venons de créé. (remplacer `[Name server 1]` avec le nom de **Name server 1** que vous avez noter précédemment dans cette tâche et `[domain name]` par le nom du domaine DNS créé plus tôt dans cette tâche):

   ```powershell
   nslookup az104-04-vm1.[domain name] [Name server 1]
   ```

1. Verifier que la sortie de la commande inclut l'adresse IP publique de **az104-04-vm1**.

## Nettoyage des ressources

   >**Note**: Souvenez-vous de supprimer toutes les ressources Azure crées que vous n'utilisez plus. En supprimant les ressources non nécessaires, vous vous assurez de ne pas être facturé en plus.

1. Dans le portail Azure, démarrer une session **PowerShell** avec **Cloud Shell**.

1. Lister tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante :

   ```powershell
   Get-AzResourceGroup -Name 'az104-04*'
   ```

1. Supprimer tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante:

   ```powershell
   Get-AzResourceGroup -Name 'az104-04*' | Remove-AzResourceGroup -Force -AsJob
   ```

    >**Note**: La commande s'exécute de manière asynchrone (comme demandé par le paramèter -AsJob), donc vous pouvez relancer immédiatement une autre commande PowerShell dans la même session PowerShell, cela prendra quelques minutes avant que le groupes de ressources ne soit réellement supprimé.
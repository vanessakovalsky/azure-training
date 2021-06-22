# Exercice - Gérer les machines virtuelles

## Objectifs

Dans cet exercice vous allez:

+ Tâche 1: Déployer une machine virtuelle Azure zone-resilient en utilisant le portail Azure et les templates Azure Resource Manager
+ Tâche 2: Configurer les machines virtuelles en utilisant l'extension machine virtuelle
+ Tâche 3: Mettre à l'échelle le calcul et le stockage pour les machines virtuelles Azure
+ Tâche 4: Enregistrer les fournisseurs de ressource Microsoft.Insights (Monitoring) and Microsoft.AlertsManagement (alerte)
+ Tâche 5: Deployer une machine virtuelle Azure zone-resilient mise à l'échelle en utilisant le portail Azure
+ Tâche 6: Configurer la mise à l'échelle des machines virtuelles Azure en utilisant l'extension machine virtuelle

Bonus
+ Tâche 7: Mettre à l'échelle le calcul et le stockage pour les ensemble de machines virtuels Azure

## Temps estimé: 50 minutes

## Tâche 1: Déployer une machine virtuelle Azure zone-resilient en utilisant le portail Azure et les templates Azure Resource Manager

1. Se connecter sur le [Azure portal](http://portal.azure.com).

1. Dans le portail Azure, rechercher et sélectionner **Virtual machines** et, sur l'écran **Virtual machines**, cliquer sur **+ Add**.

1. Sur l'onglet **Basics** de l'écran **Create a virtual machine**, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut) :

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement que vous utilisez dans cet exercice |
    | Resource group | le nom de notre nouveau groupe de ressource **az104-08-rg01-$myname** |
    | Virtual machine name | **az104-08-vm0** |
    | Region | sélectionner une zone de disponibilité que vous pouvez utilisez et qui permet la création de machine virtuelle |
    | Availability options | **Availability zone** |
    | Availability zone | **1** |
    | Image | **Windows Server 2019 Datacenter - Gen1** |
    | Azure Spot instance | **No** |
    | Size | **Standard D2s v3** |
    | Username | **Student** |
    | Password | **Pa55w.rd1234** |
    | Public inbound ports | **None** |
    | Would you like to use an existing Windows Server license? | **No** |

1. Cliquer sur **Next: Disks >** et, sur l'onglet **Disks** de l'écran **Create a virtual machine**, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | OS disk type | **Premium SSD** |
    | Enable Ultra Disk compatibility | **No** |

1. Cliquer sur **Next: Networking >** et, sur l'onglet **Networking** de l'écran **Create a virtual machine**, cliquer sur **Create new** en dessous de la zone de texte **Virtual network**.

1. Sur l'écran **Create virtual network** blade, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Name | **az104-08-rg01-vnet** |
    | Address range | **10.80.0.0/20** |
    | Subnet name | **subnet0** |
    | Subnet range | **10.80.0.0/24** |

1. Cliquer sur **OK** et, revenir sur l'onglet **Networking** de l'écran **Create a virtual machine** , specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Subnet | **subnet0** |
    | Public IP | **default** |
    | NIC network security group | **basic** |
    | Public inbound Ports | **None** |
     | Accelerated networking | **Off**
    | Place this virtual machine behind an existing load balancing solution? | **No** |

1. Cliquer sur **Next: Management >** et, sur l'onglet **Management** de l'écran **Create a virtual machine**, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Boot diagnostics | **Enable with custom storage account** |
    | Diagnostics storage account | accept the default value |
    | Patch orchestration options | **Manual updates** |  

    >**Note**: Si nécessaire, sélectionner un compte de stockage dans la liste déroulante. Noter le nom du compte de stockage, vous en aurez besoin plus tard.

1. Cliquer sur **Next: Advanced >**, sur l'onglet **Advanced** de l'écran **Create a virtual machine**, vérifier les paramètre sans les modifier et cliquer sur **Review + Create**.

1. Sur l'écran **Review + Create**, cliquer sur **Create**.

1. Sur l'écran de déploiement, cliquer sur **Template**.

1. Visualiser le template qui représente le déploiement en cours et cliquer sur **Deploy**.

    >**Note**: Vous utiliserez l'option de déploiement d'une seconde machine virtuelle avec la même configuration sauf pour la zone de disponibilité.

1. Sur l'écran **Custom deployment**, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Resource group | **az104-08-rg01-$myname** |
    | Network Interface Name | **az104-08-vm1-nic1** |
    | Public IP Address Name | **az104-08-vm1-ip** |
    | Virtual Machine Name | **az104-08-vm1** |
    | Virtual Machine Computer Name | **az104-08-vm1** |
    | Admin Username | **Student** |
    | Admin Password | **Pa55w.rd1234** |
    | Enable Hotpatching | **false** |
    | Zone | **2** |

    >**Note**: Vous devez modifier les paramètres correspondants au proprités des différentes ressources que vous déployer en utilisant ce template, cela inclut la machine virtuel et son interface réseau.

1. Cliquer sur **Review + Create**, sur l'écran **Review + Create**, cliquer sur **Create**.

    >**Note**: Attendre que les deux déploiements soit terminés avant de passer à la tâche suivante. Cela devrait prendre environ 5 minutes

## Tâche 2: Configurer les machines virtuelles en utilisant l'extension machine virtuelle

1. Dans le portail Azure, rechercher et selectionner **Storage accounts** et, sur l'écran **Storage accounts**, cliquer sur l'entrée qui représente le compte de stockage de diagnostique que vous avez créé à la tâche précédente.

1. Sur l'écran du compte de stockage, dans la section **Blob service**, cliquer sur **Containers** puis cliquer sur **+ Container**.

1. Sur l'écran **New container**, specifier les paramètres suivants (en laissant les autres avec leur valeur par défaut) et cliquer sur **Create**:

    | Setting | Value |
    | --- | --- |
    | Name | **scripts** |
    | Public access level | **Private (no anonymous access**) |

1. Revenir sur l'écran du compte de stockage qui affiche la liste des conteneurs et cliquer sur **scripts**.

1. Sur l'écran **scripts**, cliquer sur **Upload**.

1. Télécharger le fichier  https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/08/az104-08-install_IIS.ps1 

1. Sur l'écran **Upload blob**, cliquer sur l'icône de dossier, dans la boite de dialogue **Open**, selectionner le fichier **az104-08-install_IIS.ps1**, cliquer **Open**, et revenir sur l'écran **Upload blob**, cliquer sur **Upload**.

1. Dans le portail Azure, rechercher et sélectionner **Virtual machines** et, sur l'écran **Virtual machines**, cliquer sur **az104-08-vm0**.

1. Sur l'écran de machine virtuelle **az104-08-vm0**, dans la section **Settings**, cliquer sur **Extensions**, puis cliquer sur **+ Add**.

1. Sur l'écran **New resource** , cliquer sur **Custom Script Extension** puis cliquer sur **Create**.

1. Sur l'écran **Install extension**, cliquer sur **Browse**.

1. Sur l'écran **Storage accounts**, cliquer sur le nom du compte de stockage dans lequel vous avez téléchargé le script **az104-08-install_IIS.ps1**, sur l'écran **Containers**, cliquer sur **scripts**, sur l'écran **scripts**, cliquer sur **az104-08-install_IIS.ps1**, puis cliquer sur **Select**.

1. Revenir sur l'écran **Install extension**, cliquer sur **OK**.

1. Dans le portail Azure, rechercher et sélectionner **Virtual machines** et, sur l'écran **Virtual machines**, cliquer sur **az104-08-vm1**.

1. Sur l'écran **az104-08-vm1**, dans la section **Automation**, cliquer sur **Export template**.

1. Sur l'écran **az104-08-vm1 - Export template**, cliquer sur **Deploy**.

1. Sur l'écran **Custom deployment**, cliquer sur **Edit template**.

    >**Note**: Ne pas tenir compte du message  **The resource group is in a location that is not supported by one or more resources in the template. Please choose a different resource group**. C'est attendu et peut être ignoré dans ce cas.

1. Sur l'écran **Edit template**, dans la section affichant le contenu du template, insérer le code suivant en démarrant ligne **20** (directement en dessous de la ligne `"resources": [` ):

   >**Note**: Si vous utilisez un outil qui colle le code ligne par ligne, cela peut ajout d'autre accolade qui provoqueront des erreurs de validations. Vous devriez copier le code dans notepad en premier puis le coller sur la ligne 20.

   ```json
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "az104-08-vm1/customScriptExtension",
            "apiVersion": "2018-06-01",
            "location": "[resourceGroup().location]",
            "dependsOn": [
                "az104-08-vm1"
            ],
            "properties": {
                "publisher": "Microsoft.Compute",
                "type": "CustomScriptExtension",
                "typeHandlerVersion": "1.7",
                "autoUpgradeMinorVersion": true,
                "settings": {
                    "commandToExecute": "powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools && powershell.exe remove-item 'C:\\inetpub\\wwwroot\\iisstart.htm' && powershell.exe Add-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value $('Hello World from ' + $env:computername)"
              }
            }
        },

   ```

   >**Note**: Cette section du template définit la même machine virtuelle Azure que le script d'extension personnalisé que vous avez déployer plut tôt pour la première machine virtuelle via Azure PowerShell.

1. Cliquer sur **Save** et, revenir sur l'écran **Custom template**, cliquer sur **Review + Create** et, sur l'écran **Review + Create**, cliquer sur **Create**

    >**Note**: Attendre que le déploiement du template soit rerminé. Vous pouvez suivre son avancement depuis l'écran **Extensions** des machines virtuelles  **az104-08-vm0** et **az104-08-vm1**. Cela ne devrait pas prendre plus de 3 minutes.

1. Pour vérifier que la configuration de l'extension basé sur le Script Custom est une réussite, revenir sur l'écran **az104-08-vm1**, dans la section **Operations**, cliquer sur **Run command**, et, dans la liste des commandes, cliquer sur **RunPowerShellScript**.

1. Sur l'écran **Run Command Script**, taper la commande suivante et cliquer sur **Run** pour accéder au site web hébergé sur **az104-08-vm0**:

   ```powershell
   Invoke-WebRequest -URI http://10.80.0.4 -UseBasicParsing
   ```

    >**Note**: Le paramètre **-UseBasicParsing** est nécessaire pour éliminiter les dépendances à Internet Explorer pour compléter l'éxécution du cmdlet

    >**Note**: Vous pouvez aussi vous connecter à la VM **az104-08-vm0** et exécuter `Invoke-WebRequest -URI http://10.80.0.5 -UseBasicParsing` pour accéder au site héberger sur **az104-08-vm1**.

## Tâche 3: Mettre à l'échelle le calcul et le stockage pour les machines virtuelles Azure


1. Dans le portail Azure, rechercher et sélectionner **Virtual machines** et, sur l'écran **Virtual machines**, cliquer sur **az104-08-vm0**.

1. Sur l'écran machine virtuelle **az104-08-vm0** , cliquer sur **Size** et définir la taille de la machine virtuelle sur  **Standard DS1_v2** et cliquer sur **Resize**

    >**Note**: Choisir une autre taille si **Standard DS1_v2** n'est pas disponible.

1. Sur l'écran machine virtuelle **az104-08-vm0** , cliquer sur **Disks**, sous **Data disks** cliquer sur **+ Create and attach a new disk**.

1. Créer un disque géré avec les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Disk name | **az104-08-vm0-datadisk-0** |
    | Storage type | **Premium SSD** |
    | Size (GiB| **1024** |

1. Revenir sur l'écran **az104-08-vm0 - Disks**, sous **Data disks** cliquer sur **+ Create and attach a new disk**.

1. Créer un disque géré avec les paramètres suivants (en laissant les autres avec leur valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | Disk name | **az104-08-vm0-datadisk-1** |
    | Storage type | **Premium SSD** |
    | Size (GiB)| **1024 GiB** |

1. Revenir sur l'écran **az104-08-vm0 - Disks**, cliquer sur **Save**.

1. Sur l'écran **az104-08-vm0**, dans la section **Operations** , cliquer sur **Run command**, et, dans la liste des commandes, cliquer sur **RunPowerShellScript**.

1. Sur l'écran **Run Command Script**, taper le texte suivant et cliquer sur **Run** pour créer un disque Z: constitué de deux nouveaux disques attachés avec un modèle simple et un provisionnement fixe :

   ```powershell
   New-StoragePool -FriendlyName storagepool1 -StorageSubsystemFriendlyName "Windows Storage*" -PhysicalDisks (Get-PhysicalDisk -CanPool $true)

   New-VirtualDisk -StoragePoolFriendlyName storagepool1 -FriendlyName virtualdisk1 -Size 2046GB -ResiliencySettingName Simple -ProvisioningType Fixed

   Initialize-Disk -VirtualDisk (Get-VirtualDisk -FriendlyName virtualdisk1)

   New-Partition -DiskNumber 4 -UseMaximumSize -DriveLetter Z
   ```

    > **Note**: Attendre la confirmation que la commande s'est exécutée complètement avec succès.

1. Dans le portail Azure, rechercher et sélectionner **Virtual machines** et, sur l'écran **Virtual machines**, cliquer sur **az104-08-vm1**.

1. Sur l'écran **az104-08-vm1**, dans la section **Automation**, cliquer sur **Export template**.

1. Sur l'écran **az104-08-vm1 - Export template**, cliquer sur **Deploy**.

1. Sur l'écran **Custom deployment**, cliquer sur **Edit template**.


    >**Note**: Ne pas tenir compte du message  **The resource group is in a location that is not supported by one or more resources in the template. Please choose a different resource group**. C'est attendu et peut être ignoré dans ce cas.

1. Sur l'écran **Edit template**, dans la section qui affiche le contenu du template, remplacer la ligne **30** `"vmSize": "Standard_D2s_v3"` par la ligne suivante:

   ```json
                    "vmSize": "Standard_DS1_v2"

   ```

    >**Note**: Cette section du template définit la même taille de machine virtuelle que vous avez définit pour la première machine virtuelle créé via le portail Azure.

1. Sur l'écran **Edit template**, dans la section affichant le contenu du template, remplacer la ligne **50** (`"dataDisks": [ ]` ) par le code suivant :

   ```json
                    "dataDisks": [
                      {
                        "lun": 0,
                        "name": "az104-08-vm1-datadisk0",
                        "diskSizeGB": "1024",
                        "caching": "ReadOnly",
                        "createOption": "Empty"
                      },
                      {
                        "lun": 1,
                        "name": "az104-08-vm1-datadisk1",
                        "diskSizeGB": "1024",
                        "caching": "ReadOnly",
                        "createOption": "Empty"
                      }
                    ]
   ```

    >**Note**: Si vous utilisez un outil qui colle le code ligne par ligne, cela peut ajout d'autre accolade qui provoqueront des erreurs de validations. Vous devriez copier le code dans notepad en premier puis le coller sur la ligne 49.

    >**Note**: Cette section du template crée deux disques gérés et les attache à **az104-08-vm1**, comme la configuration du stockage faite pour la première machine virtuelle via le portail Azure.


1. Cliquer sur **Save** et, revenir sur l'écran **Custom template**, cocher la case **I agree to the terms and conditions stated above** et cliquer sur **Purchase**.

    >**Note**: Attendre que le déploiement du template soit complet. Vous pouvez suivre son avancement depuis l'écran  **Disks** de la machine virtuelle **az104-08-vm1**. Cela ne devrait pas prendre plus de 3 minutes.

1. Revenir sur l'écran **az104-08-vm1**, dans la section **Operations**, cliquer sur **Run command**, et, dans la liste des commandes, cliquer sur **RunPowerShellScript**.

1. Sur l'écran **Run Command Script**, taper le code suviant et  cliquer sur **Run** pour créer un disque Z: constitué de deux nouveaux disques attachés avec un modèle simple et un provisionnement fixe :

   ```powershell
   New-StoragePool -FriendlyName storagepool1 -StorageSubsystemFriendlyName "Windows Storage*" -PhysicalDisks (Get-PhysicalDisk -CanPool $true)

   New-VirtualDisk -StoragePoolFriendlyName storagepool1 -FriendlyName virtualdisk1 -Size 2046GB -ResiliencySettingName Simple -ProvisioningType Fixed

   Initialize-Disk -VirtualDisk (Get-VirtualDisk -FriendlyName virtualdisk1)

   New-Partition -DiskNumber 4 -UseMaximumSize -DriveLetter Z
   ```

    > **Note**: Attendre la confirmation que la commande se soit terminé complétement avec succès.

## Tâche 4: Enregistrer les fournisseurs de ressource Microsoft.Insights (Monitoring) and Microsoft.AlertsManagement (alerte)

1. Dans le portail Azure, ouvrir **Azure Cloud Shell** en cliquant sur l'icône en haut à droite du portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**.

    >**Note**: Si c'est la première fois que vous démarrer **Cloud Shell** vous aurez un message  **You have no storage mounted**, selectionner l'inscription que vous utiliser pour cette exercie et cliquer sur **Create storage**. 

1. Depuis le panneau Cloud Shell, exécuter les commandes suivante poru enregistrer les fournisseurs de ressources de  Microsoft.Insights et Microsoft.AlertsManagement.

   ```powershell
   Register-AzResourceProvider -ProviderNamespace Microsoft.Insights

   Register-AzResourceProvider -ProviderNamespace Microsoft.AlertsManagement
   ```

## Tâche 5: Deployer une machine virtuelle Azure zone-resilient mise à l'échelle en utilisant le portail Azure

1. Dans le portail Azure, rechercher et sélectionner **Virtual machine scale sets** et, sur l'écran **Virtual machine scale sets**, cliquer sur **+ Add**, cliquer sur **+ Virtual machine**.

1. Sur l'onglet **Basics** de l'écran **Create a virtual machine scale set**, définir les paramètres suivants (en laissant les autres paramètres par défaut) et cliquer sur **Next : Disks >**:

    | Setting | Value |
    | --- | --- |
    | Subscription | le nom de l'abonnement que vous utilisez pour cet exercice |
    | Resource group | le nom d'un nouveau groupe de ressource **az104-08-rg02-$myname** |
    | Virtual machine scale set name | **az10408vmss0** |
    | Region | sélectionner une région qui supporte les zones de disponibilités et qui est différente de celles utilisés pour créer les VM sur les tâches précédentes |
    | Availability zone | **Zones 1, 2, 3** |
    | Image | **Windows Server 2019 Datacenter - Gen1** |
    | Azure Spot instance | **No** |
    | Size | **Standard D2s_v3** |
    | Username | **Student** |
    | Password | **Pa55w.rd1234** |
    | Already have a Windows Server license? | **No** |

    >**Note**: Pour la liste des régions Azure qui supporte le déploiement de machines virtuelles Windows sur des zones de disponibilité, voir la doc [Régions et zones de disponibilité dans Azure?](https://docs.microsoft.com/fr-fr/azure/availability-zones/az-overview)

1. Sur l'onglet **Disks** de l'écran **Create a virtual machine scale set**, accepter les valeurs par défaut et cliquer sur **Next : Networking >**.

1. Sur l'onglet **Networking** de l'écran **Create a virtual machine scale set**, cliquer sur le lien **Create virtual network** en dessous de la zone de texte **Virtual network** et créer un nouveau réseau virtuel avec les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- | --- |
    | Name | **az104-08-rg02-vnet** |
    | Address range | **10.82.0.0/20** |
    | Subnet name | **subnet0** |
    | Subnet range | **10.82.0.0/24** |

    >**Note**: Une fois le nouveau réseau virtuel créé, revenir à l'onglet **Networking** de l'écran **Create a virtual machine scale set**, la valeur de  **Virtual network** sera automatiquement définie sur **az104-08-rg02-vnet**.

1. Revenir sur l'onglet **Networking** de l'écran **Create a virtual machine scale set**, cliquer sur l'icône **Edit network interface** à droite de l'entrée de l'interface réseau.

1. Sur l'écran **Edit network interface**, dans la section **NIC network security group**, cliquer sur **Advanced** et cliquer sur **Create new** sous la liste déroulante**Configure network security group**.

1. Sur l'écran **Create network security group**, définir les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- | --- |
    | Name | **az10408vmss0-nsg** |

1. Cliquer sur **Add an inbound rule** et ajouter une règle de sécurité entrante avec les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- | --- |
    | Source | **Any** |
    | Source port ranges | **\*** |
    | Destination | **Any** |
    | Destination port ranges | **80** |
    | Protocol | **TCP** |
    | Action | **Allow** |
    | Priority | **1010** |
    | Name | **custom-allow-http** |

1. Cliquer sur **Add** et, revenir sur l'écran **Create network security group**, cliquer sur **OK**.

1. Revenir sur l'écran **Edit network interface**, dans la section **Public IP address**, cliquer sur **Enabled** et cliquer sur **OK**.

1. Revenir sur l'onglet **Networking** de l'écran **Create a virtual machine scale set**, sous la section **Load balancing**, s'assurer que l'entrée **Use a load balancer** est sélectionner et définir **Load balancing settings** (en laissant les autres paramètres par défaut) et cliquer sur **Next : Scaling >**:

    | Setting | Value |
    | --- | --- |
    | Load balancing options | **Azure load balancer** |
    | Select a load balancer | **(new) az10408vmss0-lb** |
    | Select a backend pool | **(new) bepool** |

1. Sur l'onglet **Scaling** de l'écran **Create a virtual machine scale set**, définir les paramètres suivants (en laissant les autres paramètres par défaut) et cliquer sur **Next : Management >**:

    | Setting | Value |
    | --- | --- |
    | Initial instance count | **2** |
    | Scaling policy | **Manual** |

1. Sur l'onglet **Management** de l'écran **Create a virtual machine scale set** blade, définir les paramètres suivants (en laissant les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | Boot diagnostics | **Enable with custom storage account** |
    | Diagnostics storage account | accepter la valeur par défaut |

    >**Note**: Vous aurez besoin du nom du compte de stockage dans la prochaine tâche.

1. cliquer sur **Next : Health >**:

1. Sur l'onglet **Health** de l'écran **Create a virtual machine scale set** , vérifier les paramètres par défaut sans les modifier et cliquer sur **Next : Advanced >**.

1. Sur l'onglet **Advanced** de l'écran **Create a virtual machine scale set**, définir les paramètres suivants (en laissant les autres paramètres par défaut) et cliquer sur **Review + create**.

    | Setting | Value |
    | --- | --- |
    | Spreading algorithm | **Fixed spreading (not recommended with zones)** |

    >**Note**: Le paramètre **Max spreading**  n'est actuellement pas fonctionnel.

1. Sur l'onglet **Review + create** de l'écran **Create a virtual machine scale set**, vérifier que la validation est passer et cliquer sur **Create**.

    >**Note**: Attendre que le déploiement de la mise à l'échelle des machines virtuelles soit complet. Cela devrait prendre environ 5 minutes.

## Tâche 6: Configurer la mise à l'échelle des machines virtuelles Azure en utilisant l'extension machine virtuelle

1. Dans le portail Azure, rechercher et sélectionner **Storage accounts** et, sur l'écran **Storage accounts**, cliquer sur l'entrée qui représente le compte de stockage de diagnostique que vous avez créer à la tâche précédente.

1. Sur l'écran compte de stockage, dans la section **Blob service**, cliquer sur **Containers** puis cliquer sur **+ Container**.

1. Sur l'écran **New container**, définir les paramètres suivants (en laissant les autres paramètres par défaut) et cliquer sur **Create**:

    | Setting | Value |
    | --- | --- |
    | Name | **scripts** |
    | Public access level | **Private (no anonymous access**) |

1. Revenir sur l'écran dy compte de stockage qui affiche la liste des conteneurs, cliquer sur **scripts**.

1. Télécharger le fichier https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/08/az104-08-install_IIS.ps1 

1. Sur l'écran **scripts**, cliquer sur **Upload**.

1. Sur l'écran **Upload blob**, cliquer sur l'icone du dossier, dans la boite de dialogue **Ouvrir**, rechercher et selctionner le fichier **az104-08-install_IIS.ps1**, cliquer sur **Open**, et revenir sur l'écran **Upload blob**, cliquer sur **Upload**.

1. Dans le portail Azure, revenir à l'écran **Virtual machine scale sets** et cliquer sur **az10408vmss0**.

1. Sur l'écran **az10408vmss0**, dans la section **Settings**, cliquer sur **Extensions**, et cliquer sur **+ Add**.

1. Sur l'écran **New resource**, cliquer sur **Custom Script Extension** puis cliquer sur **Create**.

1. Depuis l'écran **Install extension**, **Browse** et **Select** le script **az104-08-install_IIS.ps1** qui a été téléchargé dans le conteneur **scripts** dans le compte de stockage plus tôt dans cette tâche puis cliquer sur **OK**.

    >**Note**: Attendre que l'installation de l'extension soit complète avant de passer à l'étape suivante.

1. Dans la section **Settings** de l'écran **az10408vmss0**, cliquer sur **Instances**, selectionner la casé à cocher à côté des deux instances de mise à l'échelle de VM, cliquer sur **Upgrade**, et, lorsqu'on vous demande la confirmation, cliquer sur **Yes**.

    >**Note**: Attendre que la mise à jour soit complète avant de passer à l'étape suivante.

1. Dans le portail Azure, rechercher et sélectionner **Load balancers** et, dans la liste des équilibreurs de charges, cliquer sur **az10408vmss0-lb**.

1. Sur l'écran **az10408vmss0-lb**, noter la valeur de **Public IP address** aassigné à l'équilibreur de charge frontend, ouvrir un nouvel onglet et aller à l'adresse IP publique.

    >**Note**: Vérifier que le navigateur affiche le nom d'une de l'instance de VM mise à l'échelle  **az10408vmss0**.

## Tâche 7: Mettre à l'échelle le calcul et le stockage pour les ensemble de machines virtuels Azure

1. Dans le portail Azure, rechercher et sélectionner **Virtual machine scale sets** et selectionner l'ensemble de mise à l'échelle **az10408vmss0**

1. Dans l'écran **az10408vmss0**, dans la section **Settings**, cliquer sur **Size**.

1. Dans la liste des tailles disponibles, selectionner **Standard DS1_v2** et cliquer sur **Resize**.

1. Dans la section **Settings**, cliquer sur **Instances**, selectionner les cases à cocher en face des deux ensembles de mises à l'échelle des instances de machines virtuelles, cliquer sur **Upgrade**, puis, lorsqu'on vous demande la confirmation, cliquer sur **Yes**.

1. Dans la liste des instances, cliquer sur l'entrée représentant la première instance et, sur l'écran ensemble de mise à l'échelle d'instance, noter sa **Location** (cela devrait être une des zones de la région Azure cible dans laquelles vous avez déployer vos ensembles de mises à l'échelle de machines virtuelles Azure).

1. Revenir à l'écran **az10408vmss0 - Instances**, cliquer sur l'entrée qui représente la seconde instance,et, sur l'écran ensemble de mise à l'échelle d'instance, noter sa **Location** (cela devrait être une des zones de la région Azure cible dans laquelles vous avez déployer vos ensembles de mises à l'échelle de machines virtuelles Azure).

1. Revenir à l'écran **az10408vmss0 - Instances**, et dans la section **Settings**, cliquer sur **Scaling**.

1. Sur l'écran **az10408vmss0 - Scaling**, selectionner l'option **Custom autoscale**  et configurer la mise à l'échelle automatique avec les paramètres suivants (en laissant les autres paramètres par défaut):

    | Setting | Value |
    | --- |--- |
    | Scale mode | **Scale based on a metric** |

1. Cliquer sur le lien **+ Add a rule** et, sur l'écran **Scale rule**, définir les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- |--- |
    | Metric source | **Current resource (az10480vmss0)** |
    | Time aggregation | **Average** |
    | Metric namespace | **Virtual Machine Host** |
    | Metric name | **Network In Total** |
    | Operator | **Greater than** |
    | Metric threshold to trigger scale action | **10** |
    | Duration (in minutes) | **1** |
    | Time grain statistic | **Average** |
    | Operation | **Increase count by** |
    | Instance count | **1** |
    | Cool down (minutes) | **5** |

    >**Note**: Evidemment, ces valeurs ne représente pas une configuration réaliste, puisque le but est de déclancher la mise à l'échelle automatique dès que possible, sans attendre de délais supplémentaire.

1. Cliquer sur **Add** et, revenir sur l'écran **az10408vmss0 - Scaling**, définir les paramètres suivants (en laissant les autres paramètres par défaut) :

    | Setting | Value |
    | --- |--- |
    | Instance limits Minimum | **1** |
    | Instance limits Maximum | **3** |
    | Instance limits Default | **1** |

1. Cliquer sur **Save**.

1. Dans le portail Azure, ouvrir **Azure Cloud Shell** ben cliquant sur l'icône en haut à droite de l'écran du portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**.

1. Depuis le panneau Cloud Shell, exécuter les commandes suivantes pour identifier l'adresse IP publique de l'équilibreur de charge devant les ensembles de mises à l'échelle de machines virtuelles Azure **az10408vmss0**.

   ```powershell
   $rgName = 'az104-08-rg02'

   $lbpipName = 'az10408vmss0-ip'

   $pip = (Get-AzPublicIpAddress -ResourceGroupName $rgName -Name $lbpipName).IpAddress
   ```

1. Depuis le panneau Cloud Shell, exécuter les commandes suivantes to start and infinite loop that sends the HTTP requests to the web sites hosted Sur l'écran instances of Azure virtual machine scale set **az10408vmss0**.

   ```powershell
   while ($true) { Invoke-WebRequest -Uri "http://$pip" }
   ```

1. Réduire le panneau Cloud Shell sans le fermer, revenir sur l'écran **az10408vmss0 - Instances** et surveiller le nombres d'instances instances.

    >**Note**: Vous devrez peut être attendre quelques minutes et cliquer sur **Refresh**.

1. Une fois que la 3ème instance est créé, aller sur son écan pour trouver sa **Location** (elle doit être différentes des deux premières zones identifiées plus tôt dans cette tâche).

1. Fermer le panneau Cloud Shell.

1. Sur l'écran **az10408vmss0**, dans la section **Settings**, cliquer sur **Disks**, cliquer sur **+ Create and attach a new disk**, et attacher unu nouveau disque géré avec les paramètres suivants (laisser les autres valeurs avec leurs valeur par défaut):

    | Setting | Value |
    | --- | --- |
    | LUN | **0** |
    | Storage type | **Standard HDD** |
    | Size (GiB) | **32** |

1. Enregistrer les modifications, dans la section  **Settings** de l'écran **az10408vmss0**, cliquer sur **Instances**, selectionner les cases à cocher à côté des deux instances d'ensemble de mise à l'échelle de machines virtuelles, cliquer sur **Upgrade**, et, lorsqu'on vous demande une confirmation, cliquer sur **Yes**.

    >**Note**: Le disque attaché à l'étape précédente est un disque brut. Avant de l'utiliser, il est nécessaire de créer une partition, créer un système de fichier et de le monter. Pour le faire, vous pouvez utiliser l'extension Azure virtual machine Custom Script. Avant ça, vous devrez supprimer l'extension Custom Script.

1. Dans la section **Settings** de l'écran **az10408vmss0** , cliquer sur **Extensions**, cliquer sur **CustomScriptExtension**, puis cliquer sur **Uninstall**.

    >**Note**: Attendre que la désinstallation soit complète.

1. Dans le portail Azure, ouvrir **Azure Cloud Shell** en cliquant sur l'icône en haut à droite du portail Azure.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**.

1. Dans la barre d'outils du panneau Cloud Shell, cliquer sur l'icône **Upload/Download files**, dans le menu déroulant, cliquer sur **Upload** et envoyer le fichierand upload the file **https://github.com/MicrosoftLearning/AZ-104-MicrosoftAzureAdministrator/blob/master/Allfiles/Labs/08/az104-08-configure_VMSS_disks.ps1** dans le home directory de Cloud Shell.

1. Dans le panneau Cloud Shell, exécuter les commandes suivantes pour afficher le contenu du script:

   ```powershell
   Set-Location -Path $HOME

   Get-Content -Path ./az104-08-configure_VMSS_disks.ps1
   ```

    >**Note**: Le script install une extension custom script qui configure le disque attaché.

1. Dans le panneau Cloud Shell, exécuter les commandes suivantes pour lancer le script et configurer les disques des ensembles de mises à l'échelle des machines virtuelles Azure:

   ```powershell
   ./az104-08-configure_VMSS_disks.ps1
   ```

1. Fermer le panneau Cloud Shell.

1. Dans la section **Settings** de l'écran **az10408vmss0**, cliquer sur **Instances**, selectionner les cases à cocher en face des deux instances d'ensemble de mise à l'échelle de machines virtuelles, cliquer sur **Upgrade**, et, lorsqu'on vous demande confirmation, cliquer sur **Yes**.

## Nettoyage des ressources

  >**Note**: Souvenez-vous de supprimer toutes les ressources Azure crées que vous n'utilisez plus. En supprimant les ressources non nécessaires, vous vous assurez de ne pas être facturé en plus.

1. Dans le portail Azure, démarrer une session **PowerShell** avec **Cloud Shell**.

1. Supprimer le fichier az104-08-configure_VMSS_disks.ps1 en exécutant la commande suivante:

   ```powershell
   rm ~\az104-08*
   ```

1. Lister tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante :

   ```powershell
   Get-AzResourceGroup -Name 'az104-08*'
   ```

1. Supprimer tous les groupes de ressources créé pendant cet exercice en exécutant la commande suivante:

   ```powershell
   Get-AzResourceGroup -Name 'az104-08*' | Remove-AzResourceGroup -Force -AsJob
   ```

   >**Note**: La commande s'exécute de manière asynchrone (comme demandé par le paramèter -AsJob), donc vous pouvez relancer immédiatement une autre commande PowerShell dans la même session PowerShell, cela prendra quelques minutes avant que le groupes de ressources ne soit réellement supprimé.
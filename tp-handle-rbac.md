# Exercice - Gérer les inscriptions et RBAC 

## Objectifs

Dans cet exercice vous allez : 
+ Tache 1 : Implanter des groupes de gestions
+ Tache 2 : Créer des rôles RBAC personnalisés 
+ Tache 3 : Assigner des rôles RBAC

## Temps estimé : 30 minutes


##  Tache 1 : Implanter des groupes de gestions

1. Se connecter au [portail Azure](https://portal.azure.com).

1. Rechercher et sélectionner  **Management groups** pour arriver sur l'écran **Management groups** .

1. Lire le message en haut de la page de **Management groups**. Si vous voyez le message suivant : **You are registered as a directory admin but do not have the necessary permissions to access the root management group**, merci d'effectuer les actions suivantes :

    1. Dans le portail Azure, rechercher et sélectionner **Azure Active Directory**.
    
    1. Sur la page qui affiche les propriétés de votre locataire  Azure Active Directory, dans le menu vertical à gauche, dans la section **Manage**, selectionner **Properties**.
    
    1. Sur la page **Properties** de votre locataire  Azure Active Directory, dans la section **Access management for Azure resources**, selectionner **Yes** puis sélectionner **Save**.
    
    1. Revenir à la page de **Management groups***, et sélectionner **Refresh**.

1. Sur la page **Management groups**, cliquer **+ Add**.

    >**Note**: Si vous n'avez pas précédemement créer de groupes de Gestion, selectionner **Start using management groups**

1. Créer un groupe de gestion avec les paramètres suviants en remplçant $myname par votre nom :

    | Setting | Value |
    | --- | --- |
    | Management group ID | **az104-02-mg1-$myname** |
    | Management group display name | **az104-02-mg1-$myname** |

1. Dans la liste des groupes de gestions, cliquer sur l'entrée qui correspond au groupe que vous avez créé..

1. Sur la page **az104-02-mg1-$myname**, cliquer sur **Subscriptions**. 

1. Sur la page **az104-02-mg1-$myname \| Subscriptions** , cliquer sur **+ Add**, sur l'écran **Add subscription**, dans la liste déroulante **Subscription**, selectionner l'inscription que vous utiliser pour cet exercice et cliquer sur **Save**.

    >**Note**: Sur la page **az104-02-mg1-$myname \| Subscriptions**, copier l'ID de votre inscription Azure. Vous en aurez besoin plus tard.

## Tache 2 : Créer des rôles RBAC personnalisés

1. Créer un fichier **az104-02a-customRoleDefinition.json** dans un éditeur de texte et coller ce contenu:

   ```json
   {
      "Name": "Support Request Contributor (Custom)",
      "IsCustom": true,
      "Description": "Allows to create support requests",
      "Actions": [
          "Microsoft.Resources/subscriptions/resourceGroups/read",
          "Microsoft.Support/*"
      ],
      "NotActions": [
      ],
      "AssignableScopes": [
          "/providers/Microsoft.Management/managementGroups/az104-02-mg1",
          "/subscriptions/SUBSCRIPTION_ID"
      ]
   }
   ```

1. Remplacer le `SUBSCRIPTION_ID` par votre ID d'inscription que vous avez copié et enregistrer le fichier. .

1. Dans le portail Azure, ouvrir **Cloud Shell** en cliquant sur l'icone dans la barre d'outil à droite de la barre de recherche.

1. Si Azure vous demande de choisir entre  **Bash** ou **PowerShell**, selectionner **PowerShell**. 

    >**Note**: Si c'est la première fois que vous démarrer **Cloud Shell** vous aurez un message  **You have no storage mounted**, selectionner l'inscription que vous utiliser pour cette exercie et cliquer sur **Create storage**. 

1. Dans la barre d'outil de Cloud Shell, cliquer sur l'icône **Upload/Download files** , dans le menu déroulant, cliquer sur  **Upload**, et télécharger le fichier **az104-02a-customRoleDefinition.json**  dans  Cloud Shell depuis votre ordinateur.

1. Dans Cloud Shell, exécuter la commande suivante pour créer la définition du rôle personnalisé:

   ```powershell
   New-AzRoleDefinition -InputFile $HOME/az104-02a-customRoleDefinition.json
   ```

1. Fermer l'onglet Cloud Shell.

## Tache 3 : Assigner des rôles RBAC

1. Dans le portail Azure, rechercher et sélectionner **Azure Active Directory**, sur l'écran Azure Active Directory, cliquer sur  **Users**, puis cliquer sur **+ New user**.

1. Créer un nouvel utilisateur avec les informations suivantes en remplaçant $myname par votre nom et en laissant les autres informations par défaut:):

    | Setting | Value |
    | --- | --- |
    | User name | **az104-02-aaduser1-$myname**|
    | Name | **az104-02-aaduser1-$myname**|
    | Let me create the password | enabled |
    | Initial password | **Pa55w.rd1234** |

    >**Note**: **Copier** le **User name** complet. Vous en aurez besoin plus tard.

1. Dans le portail Azure, revenir à la gestion du groupe **az104-02-mg1-$myname** et afficher ses **details**.

1. Cliquer sur **Access control (IAM)**, cliquer sur **+ Add** puis sur **Role assignment**, et assigner le rôle **Support Request Contributor (Custom)** à l'utilisateur que vous venez de créer.

1. Ouvrir un navigateur **Privé** et se connecter au [Azure portal](https://portal.azure.com) en utilisant le compte utilisateur que vous venez de créer. Mettre à jour le mot de passe.

    >**Note**: Plutôt que de taper le nom complet de l'utilsiateur vous pouvez le coller.

1. Dans la fenêtre de navigation privé, dans le portail Azure, rechercher et sélectionner **Resource groups** pour vérifier que l'utilisateur az104-02-aaduser1-$myname peut voir tous les groupes de ressources.

1. Dans la fenêtre de navigation privé, dans le portail Azure, rechercher et sélectionner  **All resources** pour vérifier que l'utilisateur az104-02-aaduser1-$myname ne peut voir aucune ressource.

1. Dans la fenêtre de navigation privé, dans le portail Azure, rechercher et sélectionner **Help + support** et cliquer sur **+ New support request**. 

1. Dans la fenêtre de navigation privé, sur l'onglet **Basic** de la page **Help + support - New support request** , selectionner le type de demande **Service and subscription limits (quotas)** et noter que l'inscription que vous utiliser dans cet exercice est listé dans la liste déroulante **Subscription**.

    >**Note**: La présence de l'inscription que vous utilisez dans cet exercice dans la liste déroulante **Subscription** indique que le compte que vous utilisez à les permissions nécessaires pour créer des demandes de supports spécifiques à l'inscription.

    >**Note**: Si vous ne voyez pas l'option **Service and subscription limits (quotas)**, se déconnecter du portail Azure et se reconnecter.

1. Ne pas continuer à créer la requête de support. Déconnectez vous du compte az104-02-aaduser1-$myname depuis le portail et fermer la fenêtre de navigation privée.

## Nettoyage des ressources

   >**Note**: Souvenez-vous de supprimer toutes les ressources Azure crées que vous n'utilisez plus. 

   >**Note**: En supprimant les ressources non nécessaires, vous vous assurez de ne pas être facturé en plus.

1. Dans le portail Azure, rechercher et sélectionner **Azure Active Directory**, sur l'écran Azure Active Directory , cliquer sur **Users**.

1. Sur l'écran **Users - All users**, cliquer sur **az104-02-aaduser1-$myname**.

1. Sur l'écran **az104-02-aaduser1-$myname - Profile** , copier la valeur de l'attribut **Object ID** .

1. Dans le portail Azure, démarrer une session **PowerShell** avec **Cloud Shell**.

1. Dans l'onglet Cloud Shell, exécuter les commande suivantes pour supprimer l'assignatio du rôle personnalisé (remplacer `[object_ID]` avec la valeur de l'attribut de **object ID** du compte utilisateur Azure Active Directory **az104-02-aaduser1-$myname** que vous avez copier plus tôt dans cette tâche):

   ```powershell
   $scope = (Get-AzRoleAssignment -RoleDefinitionName 'Support Request Contributor (Custom)').Scope

   Remove-AzRoleAssignment -ObjectId '[object_ID]' -RoleDefinitionName 'Support Request Contributor (Custom)' -Scope $scope
   ```

1. Dans l'onglet Cloud Shell, exécuter la commande suivante pour supprimer le rôle personnalisé:

   ```powershell
   Remove-AzRoleDefinition -Name 'Support Request Contributor (Custom)' -Force
   ```

1. Dans le portail Azure, revenir à la page  **Users - All users** de **Azure Active Directory**, et supprimer le compte utilisateur **az104-02-aaduser1-$myname**.

1. Dans le portail Azure, revenir à la page  **Management groups**. 

1. Sur l'écran **Management groups**, dans la colonne **Child subscriptions** , sur la ligne représentant le nom du groupe de gestion que vous voulez sélectionner le lien qui représente le nombre de son abonnement courant..

   >**Note**: Il est probable que le groupe cible soit  **Tenant Root management group**, sauf si vous avez créer une hiérarchie de groupes avant de faire cette exercice.
   
1. Sur l'écran **Subscriptions**  de la cible du group e de gestion, sélectionner **+ Add**.

1. Sur l'écran **Add subscription**, dans la liste déroulante **Subscriptions**, selectionner le nom de l'abonnement Azure utilisé dans cet exercice et cliquer sur **Save**.

1. Revenir à l'écran **Management groups**, faite un clic droit sur l'icône **ellipsis** à droite du groupe **az104-02-mg1** et cliquer sur  **Delete**.

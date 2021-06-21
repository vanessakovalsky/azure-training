# Exercice - Gérer les utilisateurs et groupes dans Azure  Active Directory

## Objectifs

Dans cet exercice, vous allez : 

+ Tache 1: Créer et configurer des utilisateurs  Azure AD
+ Tache 2: Créer des groupes Azure AD avec des assygnations et de l'ajout de membre dynamique
+ Tache 3: Créer un locataire Azure  Active Directory (AD)
+ Tache 4: Gérer les utilisateurs invités dans Azure AD 

## Temps estimé : 30 minutes

## Tache 1: Créer et configurer des utilisateurs  Azure AD

1. Se connecter au [Azure portal](https://portal.azure.com).

1. Dans le portail Azure, rechercher et sélectionner **Azure Active Directory**.

1. Dans le panneau Azure Active Directory, descendre to en bas et cliquer sur la section **Manage** , cliquer sur **User settings**, et vérifier les options de configuration disponibles.

1. Dans le panneau Azure Active Directory, dans la section **Manage**, cliquer sur **Users**, puis cliquer sur votre compte utilisateur pour voir vos propre paramètre de **Profile**. 

1. Cliquer sur **edit**, dans la section **Settings**, définir **Usage location** sur **United States** et cliquer sur  **save** pour appliquer le changement.

    >**Note**: Cela est nécessaire pour pouvoir assigner une licence Azure AD Premium P2 à votre compte utilisateur plus tard dans cet exercice.

1. Revenir à l'écran **Users - All users** , puis cliquer sur **+ New user**.

1. Créer un nouvel utilisateur avec les informations suivantes en remplaçant $myname par votre nom et en laissant les autres informations par défaut:

    | Setting | Value |
    | --- | --- |
    | User name | **az104-01a-aaduser1-$myname** |
    | Name | **az104-01a-aaduser1-$myname** |
    | Let me create the password | enabled |
    | Initial password | **Pa55w.rd124** |
    | Usage location | **United States** |
    | Job title | **Cloud Administrator** |
    | Department | **IT** |

    >**Note**: **Copier** le **User Principal Name** complet (user name plus domain). Vous en aurez besoin plus tard.

1. Dans la liste des utilisateurs, cliquer sur le compte nouvellement créé pour l'afficher.

1. Vérifier les options disponible dans la section **Manage** et noter que vous pouvezidentifier les rôles Azure AD qui lui sont assignées autant que les permissions du compte utilisateurs sur les ressources Azure. 

1. Dans la section **Manage**, cliquer sur **Assigned roles**, puis cliquer sur le bouton **+ Add assignment** et assigné le rôle **User administrator** à **az104-01a-aaduser1-$myname**.

    >**Note**: Vous pouvez aussi assigner un rôle Azure AD directement à la création de l'utilisateur

1. Ouvrir une fenêtre de navigation privée dans votre navigateur et connecter vous sur le  [Azure portal](https://portal.azure.com) en utilisant le compte utilisateur que vous avez créé. Vous devrez alors changer le mot de passe lors de la première coonnexion.

    >**Note**: Plutôt que de taper le nom d'utilisateur, vous pouvez le coller.

1. Dans la fenêtre de navigation privée du navigateur, sur le portail Azure, rechercher et sélectionner **Azure Active Directory**.

    >**Note**: Même si le compte utilisateur peut accéder au locataire Active Directory, il ne peut accéder aux ressources Azure. C'est ce qui est attendu puisque de tels accès nécessite d'être donné explicitement en utilisant RBAC. 

1. Dans la fenêtre de navigation privée du navigateur, sur l'écran Azure AD, descendre à la section, cliquer sur **User settings**, et voir que vous n'avez pas la permission de modifier les options de configurations.

1. Dans la fenêtre de navigation privée du navigateur, sur l'écran Azure AD, dans la section **Manage**, cliquer sur **Users**, puis cliquer sur **+ New user**.

1. Créer un nouvel utilisateur avec les informations suivantes en remplaçant $myname par votre nom et en laissant les autres informations par défaut:

    | Setting | Value |
    | --- | --- |
    | User name | **az104-01a-aaduser2-$myname** |
    | Name | **az104-01a-aaduser2-$myname** |
    | Let me create the password | enabled |
    | Initial password | **Pa55w.rd124** |
    | Usage location | **United States** |
    | Job title | **System Administrator** |
    | Department | **IT** |

1. Se déconnecter de l'utilistaur az104-01a-aaduser1-$myname dans le portail Azure et fermer la fenêtre de navigation privé.

## Tache 2: Créer des groupes Azure AD avec des assygnations et de l'ajout de membre dynamique

1. Revenir sur portail où vous êtes connecté avec votre compte utilisateur  **user account**, revenir à l'écran  **Overview** du locataire Azure AD et, dans la section **Manage**, cliquer sur **Licenses**.

    >**Note**: Les licences Azure AD Premium P1 ou P2 sont requises pour créer des groupes dynamiques.

1. Dans la section **Manage**, cliquer sur **All products**.

1. Cliquer **+ Try/Buy** et activer l'essai gratuit de Azure AD Premium P2.

1. Rafraichier la fenêtre pour vérifier que l'activation est bien effectuée. 

1. Dans l'écran **Licenses - All products**, sélectionner l'entrée **Azure Active Directory Premium P2**, et assigner toutes les options de la licence Azure AD Premium P2 à votre compte utilisateur et aux deux comptes que vous avez créé.

1. Dans le portail Azure, revenir à l'écran du locataire Azure AD et cliquer sur **Groups**.

1. Utiliser le bouton **+ New group** pour créer un groupe avec les paramètres suivants (remplacer $myname par votre nom) :

    | Setting | Value |
    | --- | --- |
    | Group type | **Security** |
    | Group name | **IT Cloud Administrators $myname** |
    | Group description | **IT cloud administrators** |
    | Membership type | **Dynamic User** |

    >**Note**: Si la liste déroulante **Membership type** est grisée, attendre quelques minutes et rafraichir la page du navigateur.

1. Cliquer sur **Add dynamic query**.

1. Dans l'onglet **Configure Rules** de l'écran **Dynamic membership rules**, créer une nouvelle règle avec les paramètres suivants:

    | Setting | Value |
    | --- | --- |
    | Property | **jobTitle** |
    | Operator | **Equals** |
    | Value | **Cloud Administrator** |

1. Enregistrer la règle et revenir à l'écran  **New Group** blade, cliquer sur **Create**. 

1. Revenir à l'écran **Groups - All groups** du locataire Azure AD, cliquer sur le bouton **+ New group** et créer un nouveau groupe avec les paramètres suivants (en remplaçant $myname par votre nom):

    | Setting | Value |
    | --- | --- |
    | Group type | **Security** |
    | Group name | **IT System Administrators $myname** |
    | Group description | **IT system administrators** |
    | Membership type | **Dynamic User** |

1. Cliquer sur **Add dynamic query**.

1. Dans l'onglet **Configure Rules** de l'écran **Dynamic membership rules**, créer une nouvelle règle avec les paramètres suivants:

    | Setting | Value |
    | --- | --- |
    | Property | **jobTitle** |
    | Operator | **Equals** |
    | Value | **System Administrator** |

1. Enregistrer la règle et revenir à l'écran  **New Group** blade, cliquer sur **Create**.

1. Revenir à l'écran **Groups - All groups** du locataire Azure AD, cliquer sur le bouton **+ New group** et créer un nouveau groupe avec les paramètres suivants (en remplaçant $myname par votre nom):

    | Setting | Value |
    | --- | --- |
    | Group type | **Security** |
    | Group name | **IT Lab Administrators $myname** |
    | Group description | **IT Lab administrators** |
    | Membership type | **Assigned** |

1. Cliquer **No members selected**.

1. Depuis l'écran **Add members**, rechercher et sélectionner les groupes **IT Cloud Administrators $myname** and **IT System Administrators $myname** et revenir à l'écran **New Group** , cliquer sur **Create**.

1. Revenir à l'écran **Groups - All groups**, cliquer sur l'entrée représentant le groupe **IT Cloud Administrators**, puis afficher l'écran de ses **Members**. Vérifier que  **az104-01a-aaduser1-$myname** apparait bien dans la liste des membres du groupes.

    >**Note**: Vous pouvez observer des délais pour la mise à jour des membres des groupes dynamiques. Pour accélerer la miste à jour, aller sur l'écran du groupe, afficher l'écran  **Dynamic membership rules**, **Edit** la règle listée dans le bloc de texte **Rule syntax** en ajoutant un espace à la fin et sauvegarder la modification.

1. Revenir à l'écran **Groups - All groups**, cliquer sur l'entrée représentant le groupe **IT System Administrators**, puis afficher l'écran de ses **Members**. Vérifier que  **az104-01a-aaduser2-$myname** apparait bien dans la liste des membres du groupes. 


## Tache 3: Créer un locataire Azure  Active Directory (AD)


1. Dans le portail Azure, rechercher et sélectionner **Azure Active Directory**.

1. Cliquer sur **+ Create a tenant** et donner les paramètres suviantes :

    | Setting | Value |
    | --- | --- |
    | Directory type | **Azure Active Directory** |
    
1. Cliquer sur **Next : Configuration**

    | Setting | Value |
    | --- | --- |
    | Organization name | **$myname Lab** |
    | Initial domain name | any valid DNS name consisting of lower case letters and digits and starting with a letter | 
    | Country/Region | **United States** |

1. Cliquer sur **Review + create** puis cliquer sur **Create**.

1. Afficher l'écran du nouveau locataire Azure AD en utilisant le lien **Click here to navigate to your new tenant: $myname Lab** ou sur le bouton **Directory + Subscription** (à droite du bouton Cloud Shell) dans la barre d'outils du portail Azure.

## Tache 4: Gérer les utilisateurs invités dans Azure AD.

1. Dans le portail Azure, affichant le locataire $myname Lab, dans la section **Manage**, cliquer sur **Users**, puis cliquer sur **+ New user**.

1. Créer un nouvel utilisateur avec les paramètre suivants (laisser les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | User name | **az104-01b-aaduser1** |
    | Name | **az104-01b-aaduser1** |
    | Let me create the password | enabled |
    | Initial password | **Pa55w.rd124** |
    | Job title | **System Administrator** |
    | Department | **IT** |

1. Cliquer sur le profile nouvellement créé.

    >**Note**: **Copier** le **User Principal Name** complet (user name plus domain). Vous en aurez besoin plus tard

1. Revenir au locataire Azure AD par défaut en utilistant le bouton **Directory + Subscription**  (juste à droite du bouton Cloud Shell) dans la barre d'outils du portail Azure.

1. Revenir à l'écran **Users - All users**, puis cliquer sur **+ New guest user**.

1. Créer un nouvel utilisateur invité avec les paramètres suivants (laisser les autres paramètres par défaut):

    | Setting | Value |
    | --- | --- |
    | Name | **az104-01b-aaduser1** |
    | Email address | Le User Principal Name que vous avez copié plus tôt dans cette tâche |
    | Usage location | **United States** |
    | Job title | **Lab Administrator** |
    | Department | **IT** |

1. Cliquer sur **Invite**. 

1. Revenir à l'écran **Users - All users**, cliquer sur l'entrée de l'utilisateur invité que vous venez de créé.

1. Sur l'écran **az104-01b-aaduser1 - Profile**, cliquer sur **Groups**.

1. Cliquer **+ Add membership** et ajouter l'utilisateur invité au groupe **IT Lab Administrators**.


#### Nettoyage des ressources

   >**Note**: Rappeler vous de toujours supprimer les ressources Azure que vous n'utilisez plus. Supprimer les ressources non utilisés vous évitera une augmentation des coûts non attendu. Même s'il n'y a pas de coût supplémentaire pour les loctaire Azure Active directory e leur objets, vous devez considérer le fait de supprimer les comptes utilisateurs, les groupes et les locataires créés lors de cet exercice pour des raison de sécurité.

1. Dans le **Azure Portal** rechercher **Azure Active Directory** dans la barre de recherche. Dans **Azure Active Directory** sous **Manage** selectionner **Licenses**. Sur l'écran **Licenses** sous **Manage** selectionner **All Products** puis  selectionner l'item **Azure Active Directory Premium P2** dans la liste. Sélectionner les **Licensed Users**. Selectionner le compte utilisateur **az104-01a-aaduser1-$myname** et **az104-01a-aaduser2-$myname** à qui vous avez assigner des licences dans cet exercice, cliquer sur **Remove license**, et cliquer sur **OK** pour confirmer.

1. Dans le **Azure Portal**, aller à la page **Users - All users** , cliquer sur l'entrée représentant le compte utilisateur invité **az104-01b-aaduser1**, sur le profil de  **az104-01b-aaduser1 - Profile** cliquer sur **Delete**, et cliquer sur **OK** pour confirmer.

1. Refaire cela pour l'ensemble des comptes utilisateurs créés dans cet exercice.

1. Aller à la page **Groups - All groups**, selectionner les groupes créés dans cet exercice et cliquer sur **Delete**,  et cliquer sur **OK** pour confirmer..

1. Dans le portail Azure, afficher la page du locataire Azure AD $myname Labs en utilisant le bouton **Directory + Subscription**  (juste à droit du bouton Cloud Shell) dans la barre d'outils du portail Azure.

1. Aller sur la page **Users - All users**, cliquer sur la ligne du compte utilsiateur **az104-01b-aaduser1**, sur la page  **az104-01b-aaduser1 - Profile** cliquer sur **Delete**,  et cliquer sur **OK** pour confirmer..

1. Aller sur la page **$myname Lab - Overview** du locataire Azure AD $myname Lab, cliquer **Delete tenant**, sur l'écran de  **Delete tenant '$myname Lab'**, cliquer sur le lien **Get permission to delete Azure resources**, sur l'écran **Properties** de Azure Active Directory, définir **Access management for Azure resources** sur **Yes** et cliquer sur **Save**.

1. Se déconnecter et se reconnecter sur le portail Azure. 

1. Revenir sur la page **Delete tenant '$myname Lab'** et cliquer sur  **Delete**.

> **Note**: Vous devrez attendre pour la fin de la licence d'essai pour ce locataire avant de pouvoir le supprimer. Cela n'entraine pas de coût supplémentaire.


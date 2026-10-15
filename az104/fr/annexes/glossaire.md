# Glossaire — Administration Microsoft Azure (AZ-104)

Un terme par ligne, avec le module où il est traité. Ordre alphabétique.

| Terme | Définition | Module |
|---|---|---|
| Abonnement (subscription) | Unité de facturation et limite de quotas ; contient les groupes de ressources | M2 |
| Accès conditionnel | Règles d'accès Entra ID selon l'utilisateur, l'appareil, l'emplacement, le risque (licence P1) | M1 |
| Accès public (stockage) | Point de terminaison Internet d'un compte de stockage ; désactivable au profit d'un private endpoint | M6 |
| ACR (Azure Container Registry) | Registre privé d'images de conteneurs ; construction d'images par ACR Tasks | M8 |
| ACI (Azure Container Instances) | Exécution d'un conteneur sans cluster ni VM à gérer | M8 |
| Affectation de stratégie | Application d'une définition Azure Policy à un scope, avec paramètres | M2 |
| Agent Azure Monitor (AMA) | Agent de collecte du système invité, piloté par des règles de collecte (DCR) | M7, M10 |
| AKS (Azure Kubernetes Service) | Kubernetes managé : plan de contrôle géré par Azure | M8 |
| Alerte | Règle = portée + signal + condition + groupe d'actions ; gravité Sev0 à Sev4 | M10 |
| App Service | Hébergement PaaS d'applications web ; capacité fournie par un plan App Service | M8 |
| ARM (Azure Resource Manager) | Couche de déploiement et de gestion d'Azure ; modèles JSON déclaratifs | M3 |
| ASG (Application Security Group) | Groupe logique de cartes réseau, utilisable comme source ou destination d'une règle NSG | M4 |
| Azure Files | Partages de fichiers SMB / NFS managés dans un compte de stockage | M6 |
| Azure File Sync | Synchronisation entre un serveur Windows et un partage Azure Files, avec hiérarchisation | M6 |
| Azure Firewall | Pare-feu managé avec états, règles réseau et applicatives, journalisation | M4 |
| Azure Policy | Service d'évaluation de conformité et de refus de ressources non conformes | M2 |
| Bastion | Accès RDP / SSH aux VMs depuis le portail, sans IP publique sur les VMs | M7 |
| Bicep | Langage déclaratif compilé en modèle ARM ; idempotent | M3 |
| Budget | Seuil de coût avec alertes ; n'arrête aucune ressource | M2 |
| Cloud-init | Configuration d'une VM Linux au premier démarrage (données personnalisées) | M7 |
| Cloud Shell | Terminal Bash / PowerShell dans le navigateur, outils Azure préinstallés | M0, M3 |
| Coffre Recovery Services | Coffre de sauvegarde des VMs, d'Azure Files et de l'agent MARS | M9 |
| Compte de stockage | Espace de noms unique pour blobs, fichiers, files d'attente et tables | M6 |
| Cycle de vie (lifecycle) | Règles de changement de niveau ou de suppression des blobs selon leur âge | M6 |
| DCR (règle de collecte de données) | Ce que l'agent Azure Monitor collecte et où il l'envoie | M7, M10 |
| Disque managé | Disque de VM géré par Azure (HDD, SSD Standard, SSD Premium, Ultra) | M7 |
| Emplacement de déploiement (slot) | Copie d'une application App Service ; échange sans interruption | M8 |
| Entra ID (ex-Azure AD) | Service d'identité de Microsoft : utilisateurs, groupes, applications | M1 |
| Espace de travail Log Analytics | Stockage des journaux interrogeables en KQL ; rétention et coût au Go | M3, M10 |
| ExpressRoute | Liaison privée opérateur vers Azure, sans transit Internet | M5 |
| Extension de VM | Agent exécuté dans la VM (Custom Script, Azure Monitor, etc.) | M7 |
| Géo-redondance (GRS / RA-GRS) | Copie asynchrone vers la région appariée ; RA = lecture du secondaire | M6 |
| Groupe à haute disponibilité (availability set) | Répartition de VMs sur des domaines d'erreur et de mise à jour d'un datacenter | M7 |
| Groupe d'actions | Destinataires et actions d'une alerte (courriel, SMS, webhook…) | M10 |
| Groupe d'administration | Niveau au-dessus des abonnements pour stratégies et RBAC | M2 |
| Groupe de ressources | Conteneur logique de ressources partageant un cycle de vie | M2 |
| Groupe dynamique | Appartenance calculée par une règle sur les attributs (licence P1) | M1 |
| Hiérarchisation cloud (cloud tiering) | File Sync : fichiers peu utilisés remplacés par des pointeurs sur le serveur | M6 |
| Hub-spoke | Topologie : réseau central partagé (pare-feu, passerelle) relié par peering à des réseaux applicatifs | M4 |
| Identité managée | Identité Entra ID d'une ressource Azure, sans secret à gérer | M6, M8 |
| Invité (B2B) | Utilisateur externe invité dans le tenant | M1 |
| KQL (Kusto Query Language) | Langage de requête de Log Analytics | M10 |
| Load Balancer | Répartition de charge de niveau 4 (TCP / UDP), public ou interne | M7 |
| MARS (agent) | Agent Microsoft Azure Recovery Services : sauvegarde de fichiers d'un serveur | M9 |
| Moindre privilège | Attribuer le rôle minimal au scope minimal | M2 |
| Network Watcher | Outils de diagnostic réseau : saut suivant, vérification des flux IP, journaux de flux | M10 |
| NSG (Network Security Group) | Règles de filtrage entrant / sortant sur un sous-réseau ou une carte réseau | M4 |
| Passerelle NAT | Sortie Internet explicite et à IP fixe pour un sous-réseau | M6, M7 |
| Passerelle de réseau local | Représentation du site distant (IP publique, plages) pour un VPN | M5 |
| Passerelle VPN | Passerelle de réseau virtuel pour les tunnels IPsec site-à-site ou point-à-site | M5 |
| Peering | Liaison privée entre deux réseaux virtuels ; non transitif | M5 |
| Plan App Service | Capacité de calcul et niveau de fonctionnalités d'App Service ; unité de facturation | M8 |
| Point de récupération | État restaurable d'une ressource sauvegardée (instantané ou coffre) | M9 |
| Private endpoint | Carte réseau privée d'un service PaaS dans un sous-réseau du client | M6 |
| RBAC (Azure) | Contrôle d'accès par rôles : principal + rôle + scope | M2 |
| Région appariée | Région de secours désignée par Microsoft pour la géo-réplication | M6 |
| Réplication d'objets | Copie asynchrone de blobs entre deux comptes | M6 |
| RPO / RTO | Perte de données maximale admise / durée d'interruption maximale admise | M9 |
| SAS (signature d'accès partagé) | Jeton d'accès délégué, limité en droits et en durée ; de compte, de service ou de délégation d'utilisateur | M6 |
| Scope | Niveau d'application d'un rôle ou d'une stratégie : groupe d'administration, abonnement, groupe, ressource | M2 |
| Site Recovery | Réplication et basculement de VMs vers une autre région | M9 |
| SSPR | Réinitialisation de mot de passe en libre-service | M1 |
| Suppression réversible (soft delete) | Conservation temporaire des blobs, conteneurs ou éléments sauvegardés supprimés | M6, M9 |
| Tag | Paire clé / valeur sur une ressource ou un groupe : coûts, propriétaire, environnement | M2 |
| Transit de passerelle | Usage, par un spoke, de la passerelle VPN du hub via le peering | M5 |
| UDR (route définie par l'utilisateur) | Route personnalisée d'une table de routes, ex. `0.0.0.0/0` vers le pare-feu | M4 |
| Unité administrative (AU) | Périmètre Entra ID pour déléguer l'administration d'une partie des utilisateurs et groupes | M1 |
| Versioning (blob) | Conservation automatique des versions précédentes d'un blob | M6 |
| Virtual WAN | Service managé de réseau étendu (hubs Microsoft, VPN, ExpressRoute) | M5 |
| VMSS (groupe identique) | Ensemble de VMs identiques avec mise à l'échelle automatique | M7 |
| VNet (réseau virtuel) | Réseau privé isolé dans une région, découpé en sous-réseaux | M4 |
| Zone de disponibilité | Datacenter(s) isolé(s) d'une région ; restrictions possibles selon l'abonnement | M7 |
| Zone DNS privée | Résolution de noms interne aux réseaux virtuels liés | M4, M6 |

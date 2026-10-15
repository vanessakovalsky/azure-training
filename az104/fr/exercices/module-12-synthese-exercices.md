# Module 12 — Cas de synthèse : audit de fin de migration Arvéo

Fil rouge : **fin de la migration d'Arvéo**. Le cabinet d'audit mandaté par la DSI arrive lundi. Sept demandes à traiter dans l'environnement `st<NN>`, avec une preuve pour chacune.

Usage : cas de révision en autonomie, après la formation. Solution complète dans `corrections/module-12-synthese-corrections.md`. Chaque demande mobilise un ou plusieurs modules ; la colonne « Modules » indique où relire.

**Durée indicative** : 45 min · **Prérequis** : état de fin de formation (modules 6, 7, 9 et 10), ou rattrapages correspondants · **Niveau** : ⭐⭐

**Bloc de variables** :
```bash
NN=<NN>
ST="st${NN}"
SES=<SES>
SUB_ID=$(az account show --query id -o tsv)
```
`<NN>` = numéro de stagiaire sur deux chiffres · `<SES>` = code de session du module 6 (suffixe des comptes de stockage)

---

## Les sept demandes

| # | Demande | Modules | Preuve attendue |
|---|---|---|---|
| 1 | Groupe de sécurité attribué `st<NN>-GRP-Audit`, créé dans l'unité administrative `AU-st<NN>` ; rôle **Lecteur** sur `rg-st<NN>-data` uniquement, attribué au groupe | M1, M2 | `az role assignment list -g rg-st<NN>-data` : le groupe, rôle `Reader` ; aucune autre attribution pour ce groupe |
| 2 | Tag `Audit=2026` ajouté à `rg-st<NN>-app` SANS écraser les tags existants ; tentative de création d'un NSG `nsg-st<NN>-eval` en **West Europe** dans `rg-st<NN>-app` | M2 | Tags existants conservés ; message `RequestDisallowedByPolicy` relevé |
| 3 | Fichier `eval.bicep` : NSG `nsg-st<NN>-eval` en France Central dans `rg-st<NN>-app`, règle entrante `Deny-SSH-Internet` (TCP 22, source `Internet`, priorité 100, refus) ; déploiement, puis second déploiement identique | M3, M4 | Second déploiement `Succeeded` sans modification (`what-if` : `NoChange`) |
| 4 | Règles effectives de la carte réseau de `vm-st<NN>-web01` | M4, M7 | Nom de la règle qui autorise HTTP, nom de la règle par défaut qui refuse le reste ; une phrase d'explication |
| 5 | Conteneur `audit` dans `starveost<NN>arch<SES>`, fichier `preuve.txt`, **SAS de délégation d'utilisateur** en lecture seule, valable 1 h, HTTPS uniquement | M6 | `curl` du SAS : contenu du fichier ; écriture avec le même SAS : refusée (`403`) |
| 6 | Sauvegarde immédiate de `vm-st<NN>-web02` dans `rsv-st<NN>-arveo`, rétention 7 jours | M9 | Identifiant du travail ; état `InProgress` ou `Completed` |
| 7 | Règle d'alerte métrique `ar-st<NN>-eval-cpu` : CPU de `vm-st<NN>-web02` > 80 % sur 5 min, groupe d'actions `ag-st<NN>-exploitation` ; requête KQL : dernier `Heartbeat` par ordinateur | M10 | Règle visible ; requête et résultat (une ligne par VM web) |

## Questions écrites
1-2 phrases chacune :
- a. Demande 5 : pourquoi `starveost<NN>data<SES>` répond-il `403` depuis Cloud Shell, même avec un SAS valide ?
- b. Demande 6 : quel point de récupération est disponible en premier, et pourquoi ?
- c. Demande 1 : pourquoi attribuer le rôle au groupe plutôt qu'à l'utilisateur ?
- d. Demande 3 : quel avantage du second déploiement identique pour un audit ?

## Indices
- Demande 1 : création dans l'AU par `az rest` sur `https://graph.microsoft.com/v1.0/directory/administrativeUnits/<ID_AU>/members` (même principe qu'au module 1).
- Demande 2 : `az tag update --operation Merge`.
- Demande 4 : `az network nic list-effective-nsg` (VM démarrée).
- Demande 5 : `az storage container generate-sas --as-user --auth-mode login` ; rôle de données requis sur le compte.
- Demande 6 : `az backup protection backup-now --retain-until`.
- Demande 7 : `az monitor metrics alert create --condition "avg Percentage CPU > 80"`.

## Auto-évaluation
15 questions, une seule bonne réponse, réponses dans la correction. Repère : 10/15.

1. Groupe dont les membres sont ajoutés automatiquement selon le service de l'utilisateur : quel type, et quelle licence ?
   - A. Groupe attribué, aucune licence
   - B. Groupe dynamique d'utilisateurs, Entra ID P1 au minimum
   - C. Groupe Microsoft 365, licence Exchange
   - D. Unité administrative, Entra ID P2
2. Une affectation « Allowed locations » existe sur un groupe de ressources. Effet sur une ressource existante hors région ?
   - A. Supprimée automatiquement
   - B. Déplacée vers une région autorisée
   - C. Conservée, signalée non conforme ; seules les nouvelles créations sont refusées
   - D. Bloquée en lecture seule
3. Un auditeur doit lire les ressources d'un seul groupe de ressources. Attribution correcte ?
   - A. `Reader` sur l'abonnement
   - B. `Contributor` sur le groupe de ressources
   - C. `Reader` sur le groupe de ressources, attribué à un groupe Entra ID
   - D. Lecteur général (Global Reader) Entra ID
4. Avantage principal d'un fichier Bicep par rapport à une suite de commandes CLI ?
   - A. Exécution plus rapide
   - B. Déclaratif et idempotent : un second déploiement ne recrée rien
   - C. Aucun droit RBAC nécessaire
   - D. Ressources gratuites
5. Trafic d'un spoke vers Internet forcé à travers Azure Firewall : quel objet ?
   - A. Table de routes (UDR) `0.0.0.0/0` → IP privée du pare-feu, associée au sous-réseau
   - B. Règle NSG sortante vers le pare-feu
   - C. Peering avec « Utiliser les passerelles distantes »
   - D. Zone DNS privée
6. Peering hub ↔ spoke ; le spoke doit joindre Lyon par la passerelle VPN du hub. Réglages ?
   - A. Aucun : le peering est transitif
   - B. « Autoriser le transit de passerelle » côté hub, « Utiliser les passerelles distantes » côté spoke
   - C. Une passerelle VPN par spoke
   - D. Un second peering spoke ↔ Lyon
7. Liaison privée garantie, 10 Gbit/s, sans transit par Internet, vers le datacenter : quel service ?
   - A. VPN site-à-site
   - B. VPN point-à-site
   - C. ExpressRoute
   - D. Peering global
8. Compte de stockage avec private endpoint et accès public désactivé : requête depuis Internet avec un SAS valide ?
   - A. Acceptée : le SAS prime sur le réseau
   - B. Refusée (`403`) : le pare-feu du compte s'applique avant l'autorisation
   - C. Redirigée vers le private endpoint
   - D. Acceptée en lecture seule
9. Azure File Sync, hiérarchisation cloud activée : effet sur le serveur de Lyon ?
   - A. Fichiers peu utilisés remplacés par des pointeurs, contenu rapatrié à la demande
   - B. Fichiers supprimés du serveur après synchronisation
   - C. Partage en lecture seule
   - D. Aucun : la hiérarchisation ne concerne que le compte Archive
10. SLA le plus élevé pour deux VMs web identiques ?
   - A. Deux VMs dans le même groupe à haute disponibilité
   - B. Deux VMs dans deux zones de disponibilité, derrière un Load Balancer Standard
   - C. Une VM avec disque Premium SSD
   - D. Deux VMs dans la même zone
11. Configuration d'une VM existante sans connexion interactive, rejouable : quel outil ?
   - A. Bastion
   - B. Extension Custom Script
   - C. Capture d'image
   - D. Groupe à haute disponibilité
12. Mise en production sans interruption d'une nouvelle version sur App Service ?
   - A. Redémarrage de l'application
   - B. Déploiement dans un emplacement `staging`, puis échange
   - C. Augmentation du niveau du plan
   - D. Suppression puis recréation de l'application
13. Restauration d'un fichier précis de `web01`, sans toucher la VM en production ?
   - A. Remplacer l'existant
   - B. Restauration de disques, disque attaché à une VM de travail, copie du fichier
   - C. Site Recovery, basculement
   - D. Capture instantanée du disque OS en production
14. Alerte quand le CPU d'une VM dépasse 80 % pendant 5 min, avec courriel à l'exploitation ?
   - A. Paramètre de diagnostic vers Log Analytics
   - B. Règle d'alerte métrique reliée à un groupe d'actions
   - C. Alerte du journal d'activité
   - D. Classeur Azure Monitor
15. VM injoignable sur le port 1433 : quel outil Network Watcher indique la règle NSG en cause ?
   - A. Vérification des flux IP (IP flow verify)
   - B. Capture de paquets
   - C. Topologie
   - D. Moniteur de connexion

## Nettoyage
```bash
az network nsg delete -g "rg-${ST}-app" -n "nsg-${ST}-eval"
az monitor metrics alert delete -g "rg-${ST}-app" -n "ar-${ST}-eval-cpu"
az group update -n "rg-${ST}-app" --remove tags.Audit -o none
```

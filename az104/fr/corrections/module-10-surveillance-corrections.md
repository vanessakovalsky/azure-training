# Module 10 — Corrections

Toutes les commandes supposent le bloc de variables des exercices exécuté (`NN`, `COURRIEL`, `OCT`, `ST`, `RG_*`, `VAULT`, `WS_ID`, `WS`, `DIAG_SA`, fonctions `vmrun`, `kql`, `alertes`). Les sorties sont données pour le stagiaire `07` ; la colonne technique `TableName` des sorties de `kql` est omise.

---

## Lab 10.1 ⭐ — Explorer les données de supervision d'Arvéo

### Solution
Les étapes du lab sont complètes. Contrôles finaux :
```bash
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor diagnostic-settings list --resource "$LB_ID" --query "[].name" -o tsv
kql "union withsource=Table AzureMetrics, AzureDiagnostics, AddonAzureBackupJobs
| where TimeGenerated > ago(1h) | summarize Lignes = count() by Table"
```
Sortie attendue (vers 13:55 ; tables vides tant que les premières données ne sont pas ingérées, volumes variables) :
```
diag-arveo
Table                 Lignes
--------------------  --------
AzureMetrics          412
AzureDiagnostics      36
AddonAzureBackupJobs  2
```

### Pourquoi
- **Préparation à 13:30** : un paramètre de diagnostic n'envoie que les données émises APRÈS sa création. Créés à 14:30, les paramètres du coffre et du NSG laisseraient le lab 10.3 sans données ; même logique que la sauvegarde de 09:00 (M9) et les passerelles VPN (J2).
- **Coffre en tables spécifiques à la ressource (`Dedicated`)** : Azure Backup recommande ce mode ; chaque catégorie a sa table typée (`AddonAzureBackupJobs`, `CoreAzureBackup`…), plus simple à interroger et moins volumineuse que la table commune `AzureDiagnostics`.
- **NSG et Load Balancer en mode par défaut** : leurs journaux et métriques n'existent pas en tables spécifiques `[À VÉRIFIER]` ; ils arrivent dans `AzureDiagnostics` et `AzureMetrics`.
- **Dimension `BackendIPAddress`** : `DipAvailability` agrégée sur le pool masquerait un serveur sur deux en panne (moyenne 50 %) ; découpée par adresse, elle désigne le serveur fautif.
- **Journal d'activité par CLI** : l'export vers `AzureActivity` exige un paramètre de diagnostic de l'ABONNEMENT, hors des droits stagiaires (Lecteur) ; la lecture directe (90 jours) reste disponible.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `preparer-supervision.sh` : `log-stNN-shared absent` | Socle du module 3 supprimé ou non créé | `./scripts/catch-up/module-03/deploy.sh <NN>` puis relancer |
| `diagnostic-settings create` : `Data sink ... is already used` | Même catégorie déjà envoyée au même espace (bonus 4 du M9 sur le coffre) | Normal : le script conserve le paramètre existant ; lire son nom avec `diagnostic-settings list` |
| `metrics list` : colonnes vides pour la dernière tranche | Tranche en cours, non agrégée | Lire les tranches précédentes ou `--offset` plus long |
| Santé du pool : une seule adresse | Un serveur hors pool (rattrapage M7 incomplet) ou VM arrêtée | `az vm start` ; `az network lb address-pool show ... --query "length(backendIPConfigurations)"` |
| Journal de flux : `InvalidResourceType` ou option `--vnet` inconnue | Version de la CLI | Cloud Shell à jour ; à défaut, portail : Network Watcher › Journaux de flux › Créer, type « Réseau virtuel » |
| Journal de flux : `AuthorizationFailed` sur `NetworkWatcherRG` | Rôle Contributeur de réseau absent | Formatrice : `provision-stagiaires.sh` (idempotent) |
| `Heartbeat` : AUCUNE | Agent arrêté ou VM redémarrée sans sortie Internet | `az vm extension show ... -n AzureMonitorLinuxAgent` ; passerelle NAT `ng-stNN-app` sur `snet-web` |

---

## Lab 10.2 ⭐⭐ — Alertes et groupe d'actions d'Arvéo

### Solution
```bash
# 1. Groupe d'actions (courriel de confirmation envoyé à l'adresse)
AG_ID=$(az monitor action-group create -g "$RG_SHARED" -n "ag-${ST}-exploitation" \
  --short-name "ag-${ST}-exp" --action email exploitation "$COURRIEL" \
  --tags $TAGS --query id -o tsv)
# 2. CPU durable, toutes les VMs de rg-stNN-app (France Central)
az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-cpu-vm" \
  --scopes "$(az group show -n "$RG_APP" --query id -o tsv)" \
  --target-resource-type Microsoft.Compute/virtualMachines --target-resource-region "$LOC" \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m \
  --severity 2 --action "$AG_ID" --description "Arvéo : CPU moyen > 80 % sur 5 min" \
  --tags $TAGS -o none
# 3. Serveur sorti du pool, une série par adresse
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-lb-sante" --scopes "$LB_ID" \
  --condition "avg DipAvailability < 100 where BackendIPAddress includes 10.${OCT}.4.11 or 10.${OCT}.4.12" \
  --window-size 5m --evaluation-frequency 1m --severity 1 --action "$AG_ID" \
  --description "Arvéo : serveur du pool bp-web en échec de sonde" --tags $TAGS -o none
# 4. Suppression d'une règle de NSG (journal d'activité)
az monitor activity-log alert create -g "$RG_SHARED" -n "alr-${ST}-nsg-regle" \
  --scope "$(az group show -n "$RG_SPOKE" --query id -o tsv)" "$(az group show -n "$RG_APP" --query id -o tsv)" \
  --condition category=Administrative and operationName=Microsoft.Network/networkSecurityGroups/securityRules/delete \
  --action-group "$AG_ID" --description "Arvéo : règle de NSG supprimée" --tags $TAGS -o none
# Contrôles
az monitor metrics alert list -g "$RG_SHARED" -o table \
  --query "[].{Regle:name, Gravite:severity, Active:enabled, Fenetre:windowSize, Frequence:evaluationFrequency}"
az monitor activity-log alert list -g "$RG_SHARED" -o table --query "[].{Regle:name, Active:enabled}"
```
Sortie attendue :
```
Regle              Gravite    Active    Fenetre    Frequence
-----------------  ---------  --------  ---------  -----------
alr-st07-cpu-vm    2          True      PT5M       PT1M
alr-st07-lb-sante  1          True      PT5M       PT1M
Regle               Active
------------------  --------
alr-st07-nsg-regle  True
```
Étapes 5 et 6 (déclenchement, suivi toutes les 2 min) :
```bash
alertes
```
Sortie attendue vers 14:20 (heures UTC, cibles et gravité de l'alerte du journal d'activité `[À VÉRIFIER]` libellés) :
```
Regle               Cible           Gravite    Condition    Debut
------------------  --------------  ---------  -----------  ------------------------
alr-st07-cpu-vm     vm-st07-web01   Sev2       Fired        2026-10-08T12:13:41.52Z
alr-st07-lb-sante   lbe-st07-web    Sev1       Fired        2026-10-08T12:10:12.08Z
alr-st07-nsg-regle  nsg-st07-web    Sev4       Fired        2026-10-08T12:09:55.31Z
```
Après l'étape 7, 3 à 6 min plus tard : `alr-st07-cpu-vm` et `alr-st07-lb-sante` passent à `Resolved` (courriel de résolution) ; `alr-st07-nsg-regle` reste `Fired`.

Réponses de l'étape 8 :
- **a.** La portée « groupe de ressources » couvre toutes les VMs présentes ET futures du groupe dans la région : les instances de `vmss-st<NN>-api` (orchestration Flexible : chaque instance est une VM) ajoutées par la mise à l'échelle sont surveillées sans modifier la règle. Une liste figée de VMs devrait être maintenue à chaque ajout. Chaque VM reste une série distincte : une alerte par VM en violation.
- **b.** Une alerte du journal d'activité est SANS ÉTAT : elle réagit à un événement ponctuel (la suppression a eu lieu), il n'existe aucune condition qui redevienne fausse. Chaque suppression crée une nouvelle alerte ; seul un opérateur la passe à « Accusée » puis « Fermée ».
- **c.** Délai observé de 6 à 9 min, décomposé : émission de la métrique par la plateforme (environ 1 min) ; remplissage de la fenêtre (la moyenne sur 5 min dépasse 80 % après environ 4 min à 100 %) ; attente de l'évaluation suivante (jusqu'à 1 min) ; création de l'alerte et envoi du courriel (1 à 2 min). La fenêtre est le facteur principal : c'est le prix de l'absence de fausses alertes sur les pics.

### Pourquoi
- **Groupe d'actions dans `rg-st<NN>-shared`** : objet transverse, réutilisé par toutes les règles (et par le défi 10.4) ; un changement d'astreinte se fait à un seul endroit.
- **Règles dans `rg-st<NN>-shared`, portées ailleurs** : une règle d'alerte peut vivre dans un autre groupe que sa cible ; la supervision reste groupée et survit à la reconstruction de `rg-st<NN>-app`.
- **Gravité 1 pour la santé du pool, 2 pour le CPU** : un serveur hors pool divise par deux la capacité du portail (HA dégradée) ; une saturation CPU peut être transitoire (mise à l'échelle de l'API).
- **`systemd-run`** : la charge survit à la fin de la commande d'exécution managée, qui termine les processus lancés en arrière-plan classique `[À VÉRIFIER]` ; `--collect` nettoie l'unité à l'arrêt.
- **Deux VMs B2s_v2 à 100 %** : crédits CPU des séries B consommés pendant 10 à 15 min ; sans crédits, la VM serait bridée à sa performance de référence et le seuil de 80 % pourrait ne pas être atteint (métrique `CPU Credits Remaining`).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucun courriel de confirmation | Courrier indésirable, adresse mal saisie | Vérifier `emailReceivers[0].emailAddress` ; dossier indésirables ; expéditeur `azure-noreply@microsoft.com` `[À VÉRIFIER]` |
| `metrics alert create` : `--target-resource-region` requis | Portée groupe de ressources sans type ni région | Ajouter `--target-resource-type` ET `--target-resource-region` |
| `metrics alert create` : dimension refusée | Syntaxe de `where ... includes` | Valeurs séparées par `or` ; ou portail (« Fractionner par dimensions ») |
| `activity-log alert create` : `--action-group` inconnu | Ancienne version de la CLI | `--action-group` remplacé par `az monitor activity-log alert action-group add` `[À VÉRIFIER]` ; ou portail |
| Alerte CPU jamais déclenchée | Crédits CPU épuisés (VM B bridée), ou charge arrêtée (session de commande terminée) | `vmrun web01 "systemctl status arveo-charge --no-pager \| head -n 3"` ; métrique `CPU Credits Remaining` |
| Alerte de santé déclenchée pour les DEUX adresses | nginx arrêté sur les deux VMs, ou règle sur le pool sans dimension | Vérifier `curl` sur l'IP publique ; redémarrer nginx |
| `RequestDisallowedByPolicy` (emplacement `global`) | Stratégie « emplacements autorisés » du M2 sans exclusion de `global` | Formatrice : vérifier la définition (la stratégie intégrée exclut `global`) ; exemption sur `rg-stNN-shared` |
| `alertes` : `az graph` inconnu | Extension `resource-graph` non installée | `az extension add -n resource-graph` (ou installation dynamique activée dans le bloc de variables) |

### Variantes acceptables
- Portail : **Monitor** › **Alertes** › **Créer** › **Règle d'alerte**, portée « groupe de ressources », type de ressource « Machines virtuelles » ; parcours de l'examen AZ-104.
- Bicep : `scripts/catch-up/module-10/main.bicep` (même résultat, versionné ; dimension `BackendIPAddress` avec la valeur `*` pour inclure tout serveur futur du pool).
- Destinataire « rôle Azure Resource Manager » (Propriétaires de l'abonnement) au lieu d'une adresse : pas d'adresse à maintenir, mais destinataires plus larges.
- Fenêtre de 10 min pour le CPU : moins de bruit, détection plus tardive.

---

## Lab 10.3 ⭐⭐ — Interroger `log-st<NN>-shared` en KQL

### Solution
Q1 (requête fournie) :
```bash
kql "$(sed -n '/^\/\/ Q1/,/^\/\/ Q2/p' scripts/labs/module-10/requetes-arveo.kql)"
```
Sortie attendue (instances de l'API absentes : agent installé sur les seuls serveurs web) :
```
Computer       Dernier                       Minutes    Etat
-------------  ----------------------------  ---------  ------
vm-st07-web01  2026-10-08T12:34:11.0000000Z  0          OK
vm-st07-web02  2026-10-08T12:34:09.0000000Z  0          OK
```
Q2 — CPU par minute :
```kql
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName in ("_Total", "total")
| summarize CpuMoyen = round(avg(CounterValue), 1), CpuMax = round(max(CounterValue), 1)
    by Computer, bin(TimeGenerated, 1m)
| order by TimeGenerated desc
| render timechart
```
Sortie attendue (extrait, pendant la charge du lab 10.2 ; `render` ignoré par la CLI) :
```
Computer       TimeGenerated                 CpuMoyen    CpuMax
-------------  ----------------------------  ----------  --------
vm-st07-web01  2026-10-08T12:15:00.0000000Z  99.6        99.8
vm-st07-web02  2026-10-08T12:15:00.0000000Z  1.2         1.9
```
Q3 — Syslog :
```kql
Syslog
| where TimeGenerated > ago(4h)
| summarize Evenements = count() by Facility, SeverityLevel
| order by Evenements desc
```
Sortie attendue (volumes variables ; aucun niveau inférieur à `warning`, filtré par la DCR) :
```
Facility    SeverityLevel    Evenements
----------  ---------------  ------------
daemon      warning          41
auth        warning          3
authpriv    warning          11
```
Q4 — Travaux de sauvegarde :
```kql
AddonAzureBackupJobs
| where TimeGenerated > ago(4h)
| join kind=leftouter (
    CoreAzureBackup
    | where OperationName == "BackupItem"
    | distinct BackupItemUniqueId, BackupItemFriendlyName
  ) on BackupItemUniqueId
| project Heure = JobStartDateTime, Element = BackupItemFriendlyName, Operation = JobOperation,
    Etat = JobStatus, DureeSec = JobDurationInSecs
| order by Heure desc
```
Sortie attendue (lignes et délai de remontée `[À VÉRIFIER]` ; `Element` vide tant que `CoreAzureBackup` n'a pas émis l'élément) :
```
Heure                         Element       Operation    Etat       DureeSec
----------------------------  ------------  -----------  ---------  ----------
2026-10-08T11:31:40.0000000Z  partage-lyon  Backup       Completed  64
```
Q5 — Santé du pool :
```kql
AzureMetrics
| where MetricName == "DipAvailability" and Resource =~ "lbe-st07-web"
| summarize Sante = round(avg(Average), 1) by bin(TimeGenerated, 5m)
| order by TimeGenerated asc
```
Sortie attendue (extrait autour de l'arrêt de nginx sur `web02`) :
```
TimeGenerated                 Sante
----------------------------  -------
2026-10-08T12:05:00.0000000Z  100.0
2026-10-08T12:10:00.0000000Z  62.5
2026-10-08T12:15:00.0000000Z  50.0
```
Q6 — Volume par table, puis enregistrement :
```bash
Q6='Usage
| where TimeGenerated > ago(24h) and IsBillable == true
| summarize Mo = round(sum(Quantity), 2) by DataType
| order by Mo desc'
kql "$Q6"
az monitor log-analytics workspace saved-search create -g "$RG_SHARED" \
  --workspace-name "log-${ST}-shared" -n arveo-volume-tables --category Arveo \
  --display-name "Volume ingéré par table" --saved-query "$Q6" -o none
```
Sortie attendue (volumes variables) :
```
DataType              Mo
--------------------  ------
Perf                  4.12
AzureMetrics          1.37
Syslog                0.41
Heartbeat             0.19
AzureDiagnostics      0.08
AddonAzureBackupJobs  0.01
```

Réponses de l'étape 5 :
- **a.** En général `Perf` : 3 compteurs échantillonnés chaque minute, par instance (chaque cœur, chaque disque) et par VM. Estimation mensuelle = somme de Q6 × 30, à corriger du fait que les VMs n'ont tourné qu'une partie de la journée (ici quelques dizaines de Mo par mois, soit un coût faible). En production : surveiller Q6 chaque semaine et réduire la fréquence d'échantillonnage ou les compteurs avant de toucher à la rétention.
- **b.** `AzureActivity` n'est alimentée que par un paramètre de diagnostic de l'ABONNEMENT (export du journal d'activité). Les stagiaires ne sont que Lecteurs de l'abonnement : aucun export configuré. Le journal d'activité existe pourtant (90 jours, portail et `az monitor activity-log list`).
- **c.** Écart de quelques minutes et valeur 50 au lieu de 0 : `AzureMetrics` reçoit des agrégats d'une minute SANS dimension (moyenne des deux serveurs : un sur deux en échec = 50 %), regroupés ici par tranches de 5 min, avec un délai d'ingestion ; l'alerte évalue la métrique de plateforme par adresse (`BackendIPAddress`), sur une fenêtre glissante de 5 min, toutes les minutes.

### Pourquoi
- **`where` sur `TimeGenerated` en premier** : réduit les données lues ; une requête sans filtre de temps parcourt toute la rétention (30 jours).
- **`join kind=leftouter`** : conserve un travail même si l'élément n'a pas encore de ligne dans `CoreAzureBackup` (émission moins fréquente `[À VÉRIFIER]`).
- **`=~` sur `Resource`** : `AzureMetrics` stocke le nom de ressource en majuscules (`LBE-ST07-WEB`).
- **Requête enregistrée** : partagée par tous les utilisateurs de l'espace de travail, versionnable par ARM ; une requête dans un fichier local ne l'est pas.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Failed to resolve table or column expression named 'AddonAzureBackupJobs'` | Table pas encore créée (aucune donnée reçue) | Attendre ; vérifier le paramètre du coffre (lab 10.1 étape 5) ; jobs du M9 antérieurs à 13:30 non remontés |
| Q2 vide | Libellé d'instance différent | `Perf \| where ObjectName == "Processor" \| distinct InstanceName` |
| Q5 vide | Paramètre `diag-arveo` du Load Balancer créé après l'arrêt de nginx | Normal : aucun historique ; refaire un arrêt de 5 min sur `web02` |
| `kql` : `BadArgumentError` | Guillemets de la requête mal échappés dans Bash | Requête entre apostrophes dans une variable (`Q6='...'`), ou fichier `.kql` lu par `$(cat ...)` |
| `saved-search create` : `--saved-query` vide | Variable non définie dans la nouvelle session Cloud Shell | Redéfinir `Q6` |

### Variantes acceptables
- Q2 avec `make-series` au lieu de `summarize ... bin()` : séries complètes (valeurs manquantes à 0), adaptées aux graphiques.
- Q4 depuis le portail : coffre › **Rapports de sauvegarde** (classeur basé sur les mêmes tables) `[À VÉRIFIER]` délai d'actualisation.
- Q6 avec `_BilledSize` sur chaque table (`union withsource=Table * | summarize sum(_BilledSize) by Table`) : plus précis, beaucoup plus coûteux à exécuter.

---

## Défi 10.4 ⭐⭐⭐ — Détecter les attaques SSH par force brute

### Solution
Requête et fonction (CLI) :
```bash
SSH_KQL='Syslog
| where Facility in ("auth", "authpriv") and SyslogMessage has "Failed password"
| parse SyslogMessage with * "from " IpSource " port " *
| project TimeGenerated, Computer, IpSource, SyslogMessage'
az monitor log-analytics workspace saved-search create -g "$RG_SHARED" \
  --workspace-name "log-${ST}-shared" -n arveo-echecs-ssh --category Arveo \
  --display-name "Échecs SSH Arvéo" --saved-query "$SSH_KQL" --func-alias ArveoEchecsSsh -o none
```
Règle d'alerte (Bicep versionné, `scripts/catch-up/module-10/alerte-ssh.bicep` : fonction ET règle) :
```bash
AG_ID=$(az monitor action-group show -g "$RG_SHARED" -n "ag-${ST}-exploitation" --query id -o tsv)
az deployment group what-if -g "$RG_SHARED" \
  --template-file scripts/catch-up/module-10/alerte-ssh.bicep \
  --parameters numero="$NN" actionGroupId="$AG_ID"
az deployment group create -g "$RG_SHARED" -n defi-m10 \
  --template-file scripts/catch-up/module-10/alerte-ssh.bicep \
  --parameters numero="$NN" actionGroupId="$AG_ID" --query "properties.outputs" -o json
```
Sortie attendue :
```
{
  "functionAlias": { "type": "String", "value": "ArveoEchecsSsh" },
  "ruleName": { "type": "String", "value": "alr-st07-ssh-echecs" }
}
```
Extrait du fichier (critère de la règle) :
```bicep
criteria: {
  allOf: [
    {
      query: requete
      timeAggregation: 'Count'
      dimensions: [
        { name: 'Computer', operator: 'Include', values: [ '*' ] }
        { name: 'IpSource', operator: 'Include', values: [ '*' ] }
      ]
      operator: 'GreaterThanOrEqual'
      threshold: seuil
      failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
    }
  ]
}
```
Preuve (étape 3) :
```bash
./scripts/labs/module-10/simuler-echecs-ssh.sh "$NN"
sleep 300
kql "ArveoEchecsSsh | summarize Echecs = count() by Computer, IpSource"
alertes
```
Sortie attendue (5 à 12 min après la simulation pour l'alerte) :
```
Computer       IpSource      Echecs
-------------  ------------  --------
vm-st07-web01  203.0.113.50  8
vm-st07-web01  198.51.100.7  3
Regle                Cible            Gravite    Condition    Debut
-------------------  ---------------  ---------  -----------  ------------------------
alr-st07-ssh-echecs  log-st07-shared  Sev1       Fired        2026-10-08T12:52:03.11Z
```
Portail : alerte › **Détails** : dimensions `Computer = vm-st07-web01`, `IpSource = 203.0.113.50`, valeur `8`. Aucune alerte pour `198.51.100.7` (3 < 5). Si les deux simulations sont lancées dans la même fenêtre de 10 min, `198.51.100.7` ne déclenche toujours pas : les dimensions séparent les compteurs.

Réponses de l'étape 4 :
- **a.** Délai mesuré de 5 à 12 min : écriture locale et envoi par l'agent (secondes), ingestion dans l'espace de travail (1 à 5 min), attente de la prochaine évaluation (0 à 5 min), création de l'alerte et courriel (1 à 2 min). Réduction : fréquence d'évaluation de 1 min (coût de la règle plus élevé `[À VÉRIFIER]` tarifs) ; l'ingestion n'est pas compressible. Pour une réaction en secondes : Microsoft Defender pour serveurs ou Microsoft Sentinel (règles d'analyse, réponse automatisée), hors périmètre AZ-104.
- **b.** Non : `dcr-st<NN>-linux` ne collecte `authpriv` qu'à partir de `Warning` ; les vrais échecs `sshd` (niveau `info`) ne sont PAS collectés, la règle ne verrait jamais une vraie attaque. Correction : ajouter dans `dcr-arveo-linux.bicep` une seconde source Syslog `authpriv` à partir de `Info` (les autres facilités restent à `Warning`), puis redéployer ; les agents récupèrent la configuration sans réinstallation. Impact : chaque connexion, chaque `sudo` journalisé devient facturable ; contenir le volume par une transformation de la DCR (`transformKql` ne conservant que `Failed password` et `Accepted`) et le suivre par la requête Q6.
- **c.** Une alerte de métrique évalue des séries numériques émises par la plateforme (CPU, octets, sondes) ; aucune métrique ne compte les échecs SSH, encore moins par adresse source. L'information n'existe que dans le texte des journaux du système invité : seule une requête KQL peut l'extraire (`parse`) et la regrouper.

### Pourquoi
- **Fenêtre de 10 min, fréquence de 5 min** : chaque minute est examinée deux fois (fenêtres qui se chevauchent), une rafale à cheval sur deux évaluations est détectée.
- **Dimensions `Computer` et `IpSource`** : une alerte par couple ; l'équipe sécurité sait immédiatement quel serveur et quelle adresse bloquer. Sans dimension, 8 + 3 échecs = 11 déclencheraient une alerte unique sans attribution.
- **`autoMitigate`** : l'alerte se résout quand la fenêtre ne contient plus 5 échecs ; une nouvelle rafale crée une nouvelle alerte.
- **Requête complète dans la règle, fonction à part** : la règle ne dépend pas d'un objet modifiable par d'autres équipes ; la fonction sert aux enquêtes.
- **Adresses RFC 5737** : réservées à la documentation, aucun risque d'accuser une adresse réelle.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `kql "ArveoEchecsSsh"` : fonction inconnue | Alias manquant (`--func-alias`) ou délai de publication | `saved-search show ... --query functionAlias` ; attendre 1 à 2 min |
| Aucune ligne `Failed password` | Simulation non exécutée, ou DCR modifiée (niveau) | Relancer la simulation ; `kql "Syslog \| where ProcessName == 'sshd' \| take 5"` |
| `IpSource` vide | Motif `parse` différent du message (espaces) | Tester `parse` sur `take 5` ; motif `"from " IpSource " port "` |
| Déploiement : `ScheduledQueryRules ... query is invalid` | Requête qui ne renvoie pas les colonnes de dimension | `project` doit contenir `Computer` et `IpSource` |
| Une alerte unique, sans dimension | Dimensions omises | Ajouter les deux dimensions avec la valeur `*` |
| Alerte jamais résolue | `autoMitigate` désactivé | Propriété `autoMitigate: true` |

### Variantes acceptables
- CLI : `az monitor scheduled-query create --scopes <ID_ESPACE> --condition "count 'Echecs' >= 5 where Computer includes * and IpSource includes * at least 1 violations out of 1 aggregated points" --condition-query Echecs="<KQL>" --evaluation-frequency 5m --window-size 10m --severity 1 --action-groups <ID_GROUPE_ACTIONS>` `[À VÉRIFIER]` grammaire de `--condition` pour les dimensions.
- Mesure par `summarize count() by Computer, IpSource` dans la requête puis seuil sur la colonne (agrégation `Total`) : équivalent, plus explicite.
- Seuil de 10 échecs en 15 min : moins de faux positifs (utilisateur qui se trompe de mot de passe), détection plus tardive.

---

## Lab 10.5 ⭐⭐ — Diagnostiquer les flux Arvéo avec Network Watcher

### Solution
```bash
# 1. Instance et journal de flux
az network watcher list -o table \
  --query "[?location=='francecentral'].{Nom:name, Groupe:resourceGroup, Etat:provisioningState}"
FA="flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration"
az network watcher flow-log show --location "$LOC" --name "fl-${ST}-spoke-app" -o json \
  --query "{Cible:targetResourceId, Stockage:storageId, Actif:enabled, TA:${FA}.enabled, Intervalle:${FA}.trafficAnalyticsInterval}" \
  | sed 's#/subscriptions/[^"]*/##'
```
Sortie attendue :
```
Nom                           Groupe            Etat
----------------------------  ----------------  ---------
NetworkWatcher_francecentral  NetworkWatcherRG  Succeeded
{
  "Actif": true,
  "Cible": "vnet-st07-spoke-app",
  "Intervalle": 10,
  "Stockage": "starveost07diag",
  "TA": true
}
```
Étape 2 : commandes de l'énoncé (fournies).
```bash
# 3. Résolution des problèmes de connexion (30 à 60 s chacune)
az network watcher test-connectivity -g "$RG_APP" --source-resource "vm-${ST}-web01" \
  --dest-address "10.${OCT}.5.100" --dest-port 8080 --protocol Tcp \
  --query "{Etat:connectionStatus, Envoyees:probesSent, Echecs:probesFailed}" -o table
az network watcher test-connectivity -g "$RG_APP" --source-resource "vm-${ST}-web01" \
  --dest-address sql.arveo.internal --dest-port 1433 --protocol Tcp -o json \
  --query "{Etat:connectionStatus, Envoyees:probesSent, Echecs:probesFailed, Problemes:hops[].issues[].type}"
```
Sortie attendue (nombre de sondes variable ; type de problème `[À VÉRIFIER]` libellé) :
```
Etat       Envoyees    Echecs
---------  ----------  --------
Reachable  66          0
{
  "Echecs": 30,
  "Envoyees": 30,
  "Etat": "Unreachable",
  "Problemes": [ "UserDefinedRoute" ]
}
```
Le nom `sql.arveo.internal` est résolu (zone privée liée au spoke app, module 4) : le DNS n'est pas en cause.
```bash
# 4. Saut suivant
for DEST in "10.${OCT}.8.10" "10.${OCT}.5.100"; do
  az network watcher show-next-hop -g "$RG_APP" --vm "vm-${ST}-web01" \
    --source-ip "10.${OCT}.4.11" --dest-ip "$DEST" \
    --query "{Destination:'${DEST}', Saut:nextHopType, Route:routeTableId}" -o table
done
```
Sortie attendue :
```
Destination    Saut    Route
-------------  ------  ------------
10.7.8.10      None    System Route
Destination    Saut      Route
-------------  --------  ------------
10.7.5.100     VnetLocal  System Route
```
```bash
# 5. IP flow verify (sens entrant)
ipflow() {   # ipflow <VM> <IP_LOCALE:PORT> <IP_DISTANTE:PORT>
  az network watcher test-ip-flow -g "$RG_APP" --vm "$1" --direction Inbound --protocol TCP \
    --local "$2" --remote "$3" --query "[access, ruleName]" -o tsv | paste - -
}
ipflow "vm-${ST}-web01" "10.${OCT}.4.11:80" 198.51.100.10:50000
ipflow "vm-${ST}-web01" "10.${OCT}.4.11:22" 198.51.100.10:50000
ipflow "$API_VM" "${API_IP}:8080" "10.${OCT}.4.11:50000"
ipflow "$API_VM" "${API_IP}:8080" "10.${OCT}.8.10:50000"
```
Sortie attendue (préfixe du nom de règle `[À VÉRIFIER]` selon la version de l'API) :
```
Allow	securityRules/Allow-HTTP-HTTPS-Inbound
Deny	defaultSecurityRules/DenyAllInBound
Allow	securityRules/Allow-API-From-Web
Deny	defaultSecurityRules/DenyAllInBound
```
```bash
# 6. Traffic analytics (après 15:30)
kql "NTANetAnalytics
| where TimeGenerated > ago(2h) and SubType == 'FlowLog'
| summarize Lignes = count() by FlowType, FlowStatus, DestIp, DestPort
| top 10 by Lignes"
kql "NTANetAnalytics
| where TimeGenerated > ago(2h) and SubType == 'FlowLog' and FlowStatus == 'Denied'
| project TimeGenerated, SrcIp, DestIp, DestPort, NsgRule"
```
Sortie attendue (extrait ; types, libellés et volumes `[À VÉRIFIER]` selon le traitement) :
```
FlowType     FlowStatus    DestIp      DestPort    Lignes
-----------  ------------  ----------  ----------  --------
AzurePublic  Allowed       10.7.4.11   80          14
AzurePublic  Allowed       10.7.4.12   80          13
IntraVNet    Allowed       10.7.5.4    8080        9
IntraVNet    Denied        10.7.5.4    22          1
TimeGenerated                 SrcIp      DestIp    DestPort    NsgRule
----------------------------  ---------  --------  ----------  ------------------------------
2026-10-08T13:20:00.0000000Z  10.7.4.11  10.7.5.4  22          nsg-st07-app/Deny-VNet-Inbound
```
- Clients du portail en `AzurePublic` : les requêtes partent de Cloud Shell, hébergé dans Azure (un client Internet serait `ExternalPublic`).
- Tentative SQL vers `10.<OCT>.8.10` absente ou sans décision NSG : le paquet est abandonné faute de route, avant tout filtrage `[À VÉRIFIER]` comportement des journaux de flux de VNet.

Réponses de l'étape 7 :
- **a.** Cause : le nettoyage de fin de J2 (`module-04-firewall.sh`) a supprimé le pare-feu et dissocié les tables de routes ; les spokes app et données ne sont appairés qu'avec le hub, et le peering n'est PAS transitif. Le spoke app n'a aucune route vers `10.<OCT>.8.0/22` : la route système `10.0.0.0/8` → `None` abandonne le paquet. Corrections : (1) recréer le pare-feu et les UDR (`./scripts/catch-up/module-04/deploy.sh <NN>`) : architecture cible, filtrage centralisé, coût horaire du pare-feu ; (2) peering direct spoke app ↔ spoke données : gratuit à l'heure (trafic facturé au Go), mais contourne le contrôle central. Modifier `nsg-st<NN>-data` est inutile : le paquet ne quitte jamais le spoke app, et ce NSG autorise déjà TCP 1433 depuis `snet-web` (`Allow-SQL-From-Web`).
- **b.** `Deny-VNet-Inbound` a pour source l'étiquette `VirtualNetwork` du spoke app : son espace d'adressage, les VNets appairés (hub) et les réseaux appris par passerelle. Le spoke données n'est pas appairé au spoke app : `10.<OCT>.8.10` n'appartient pas à l'étiquette. Aucune règle explicite ne s'applique, `AllowVnetInBound` non plus : la règle par défaut `DenyAllInBound` décide. Même mécanisme que les cas b et c de l'exercice 04.2.
- **c.** Un journal de flux n'a aucun historique, et Traffic analytics ajoute 10 à 30 min de traitement. Activé à l'ouverture du ticket, il ne montrerait ni le début de l'incident ni l'état « normal » de référence. Sur un réseau critique, il est activé en permanence : son coût (au Go) est celui d'une assurance.

### Pourquoi
- **Ordre route → filtrage → connexion** : un saut `None` rend inutile toute analyse de NSG ; la résolution des problèmes de connexion confirme ensuite le diagnostic de bout en bout, avec de vrais paquets.
- **Extension `NetworkWatcherAgentLinux`** : la résolution des problèmes de connexion envoie des sondes depuis la VM ; IP flow verify et le saut suivant lisent seulement la configuration (aucune extension).
- **Journal de flux sur le VNet entier** : couvre `snet-web` et `snet-app`, VMs présentes et futures (instances de l'API), sans dépendre d'un NSG ; les journaux de flux NSG ne peuvent plus être créés (retraite le 30 septembre 2027).
- **Stockage `starveost<NN>diag`** : même région que le VNet (exigence des journaux de flux), compte Standard déjà présent (module 3), rétention de 7 jours suffisante pour la formation.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `test-connectivity` : extension requise | `NetworkWatcherAgentLinux` absente (préparation non jouée) | `az vm extension set --publisher Microsoft.Azure.NetworkWatcher --name NetworkWatcherAgentLinux` |
| `test-connectivity` : `AuthorizationFailed` | Droits sur `NetworkWatcherRG` | Formatrice : rôle Contributeur de réseau (provisioning) |
| Connexion à l'API `Unreachable` | Instances de l'API encore désallouées ou en démarrage | `az vm list -g rg-stNN-app -d -o table` ; attendre `VM running` et la sonde du Load Balancer |
| `test-ip-flow` sur l'instance : VM introuvable | Nom de l'instance mal copié | `echo "$API_VM"` ; redéfinir les variables de l'étape 2 |
| `NTANetAnalytics` inconnue ou vide | Moins de 20 à 30 min depuis la création, ou trafic généré trop tard | Relancer l'étape 2 et attendre ; vérifier les blobs : `az storage blob list --account-name <COMPTE> -c insights-logs-flowlogflowevent --auth-mode login --num-results 3 -o table` |
| Aucun flux `Denied` | Étape 2 non exécutée (tentative SSH) | Relancer l'étape 2 ; attendre le traitement suivant |

### Variantes acceptables
- Portail : **Network Watcher** › **Saut suivant**, **Vérification des flux IP**, **Résolution des problèmes de connexion** (mêmes résultats, parcours de l'examen AZ-104).
- **Diagnostics NSG** (`az network watcher run-configuration-diagnostic`) au lieu d'IP flow verify : évalue tous les NSG du chemin (sous-réseau et carte) et renvoie l'ordre d'évaluation `[À VÉRIFIER]` paramètres.
- Étape 6 : **Traffic analytics** dans le portail (cartes, flux refusés par sous-réseau), alimenté par la même table.

---

## Bonus

1. **Fenêtre de maintenance** `[À VÉRIFIER]` options de planification de la CLI :
   ```bash
   az monitor alert-processing-rule create -g "$RG_SHARED" -n "apr-${ST}-maintenance" \
     --scopes "$(az group show -n "$RG_APP" --query id -o tsv)" \
     --rule-type RemoveAllActionGroups --description "Correctifs du mardi soir" \
     --schedule-recurrence-type Weekly --schedule-recurrence Tuesday \
     --schedule-start-time 22:00:00 --schedule-end-time 23:00:00 \
     --schedule-time-zone "Romance Standard Time" --tags $TAGS -o none
   ```
   Les alertes déclenchées pendant la fenêtre apparaissent dans **Alertes** ; aucun courriel n'est envoyé. Fuseau Windows `Romance Standard Time` = Paris (heure d'été comprise).
2. **Moniteur de connexion** `[À VÉRIFIER]` options :
   ```bash
   az network watcher connection-monitor create --location "$LOC" --name "cm-${ST}-api" \
     --endpoint-source-name web01 \
     --endpoint-source-resource-id "$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)" \
     --endpoint-dest-name api --endpoint-dest-address "10.${OCT}.5.100" \
     --test-config-name tcp8080 --protocol Tcp --tcp-port 8080 --frequency 30 \
     --workspace-ids "$WS_ID" -o none
   ```
   Requête : `NWConnectionMonitorTestResult | summarize avg(AvgRoundTripTimeMs), max(ChecksFailedPercent) by bin(TimeGenerated, 5m)` `[À VÉRIFIER]` colonnes. La désallocation d'une instance ne fait pas échouer le test (Load Balancer) : seule la perte des deux instances le ferait.
3. **Capture de paquets** :
   ```bash
   az network watcher packet-capture create -g "$RG_APP" --vm "vm-${ST}-web02" -n "pc-${ST}-web02" \
     --storage-account "$DIAG_SA" --time-limit 60 \
     --filters '[{"protocol":"TCP","localPort":"80"}]' -o none
   ```
   Le fichier `.cap` est déposé dans le conteneur `network-watcher-logs` du compte. Les sondes du Load Balancer arrivent de `168.63.129.16` toutes les 5 s environ ; les requêtes clientes conservent l'adresse source du client (pas de SNAT entrant sur un Load Balancer public).
4. **Classeur** : **Monitor** › **Classeurs** › **Nouveau** ; ajouter un paramètre « Intervalle de temps », trois éléments de requête (Q1 en grille, Q2 en graphique de lignes, requête Resource Graph `alertsmanagementresources | where name startswith 'alr-st<NN>-'` en grille), enregistrer dans `rg-st<NN>-shared` ; **Modifier** › **</>** (éditeur avancé) › **Modèle ARM** pour la version IaC.
5. **Seuil dynamique** `[À VÉRIFIER]` grammaire :
   ```bash
   az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-cpu-dyn" \
     --scopes "$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)" \
     --condition "avg Percentage CPU > dynamic medium 2 of 4" \
     --window-size 5m --evaluation-frequency 5m --severity 3 --tags $TAGS -o none
   ```
   Avec quelques heures d'historique, la bande calculée est étroite et peu fiable ; le seuil dynamique devient pertinent après plusieurs jours (saisonnalité journalière et hebdomadaire).

---

## QCM — Réponses
1. **B** — Les métriques de plateforme sont collectées par défaut ; le système invité exige l'agent Azure Monitor et une DCR.
2. **B** — Un paramètre de diagnostic n'envoie que les données émises après sa création : aucun historique rétroactif.
3. **B** — Le journal d'activité est conservé 90 jours ; au-delà, export par un paramètre de diagnostic de l'abonnement.
4. **C** — La moyenne sur 5 min (environ 22 %) reste sous 80 % : la fenêtre filtre les pics.
5. **B** — Le groupe d'actions regroupe notifications et actions, réutilisable par toutes les règles.
6. **C** — Une règle de traitement planifiée supprime les notifications sans empêcher la création des alertes.
7. **C** — `summarize ... by` agrège (par exemple `count()`) en regroupant par une ou plusieurs colonnes.
8. **B** — La table `Heartbeat` reçoit une pulsation par minute de chaque agent.
9. **B** — `None` : aucune route ne mène à la destination, le paquet est abandonné avant tout NSG.
10. **B** — Les journaux de flux NSG sont en retraite (30 septembre 2027) et ne peuvent plus être créés.

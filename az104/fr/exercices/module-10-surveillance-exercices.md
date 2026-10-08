# Module 10 — Exercices

Fil rouge : **centre de supervision d'Arvéo**. L'espace de travail `log-stNN-shared` du socle (module 3) reçoit depuis le module 7 les pulsations, les compteurs de performance et le Syslog des serveurs web ; il reçoit désormais les journaux du coffre de sauvegarde (module 9), du NSG du portail, les métriques du Load Balancer et les flux réseau du spoke applicatif. Trois alertes préviennent l'équipe d'exploitation (saturation CPU, serveur sorti du pool, règle de filtrage supprimée), une quatrième détecte les attaques SSH par force brute. Network Watcher sert enfin à diagnostiquer le ticket ouvert par l'équipe ERP depuis la suppression du pare-feu.

| Ressource | Nom (stagiaire 07) | Groupe | Lab |
|---|---|---|---|
| Paramètres de diagnostic | `diag-arveo` sur `rsv-st07-arveo` et `nsg-st07-web` (13:30), sur `lbe-st07-web` (lab) | shared / spoke / app | 10.1 |
| Groupe d'actions | `ag-st07-exploitation` (nom court `ag-st07-exp`) | `rg-st07-shared` | 10.2 |
| Alertes de métrique | `alr-st07-cpu-vm`, `alr-st07-lb-sante` | `rg-st07-shared` | 10.2 |
| Alerte du journal d'activité | `alr-st07-nsg-regle` | `rg-st07-shared` | 10.2 |
| Alerte de journal, fonction KQL | `alr-st07-ssh-echecs`, `ArveoEchecsSsh` | `rg-st07-shared` | 10.4 |
| Journal de flux de VNet, extension | `fl-st07-spoke-app` (13:30), `NetworkWatcherAgentLinux` sur `vm-st07-web01` | `NetworkWatcherRG` / `rg-st07-app` | 10.5 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<COURRIEL>` = adresse de messagerie du stagiaire, consultable pendant la formation (notifications des alertes)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
COURRIEL=<COURRIEL>
OCT=$((10#$NN))
ST="st${NN}"
RG_SHARED="rg-${ST}-shared"
RG_APP="rg-${ST}-app"
RG_SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
VAULT="rsv-${ST}-arveo"
WS_ID=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" --query id -o tsv)
WS=$(az monitor log-analytics workspace show --ids "$WS_ID" --query customerId -o tsv)
DIAG_SA=$(az storage account list -g "$RG_SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)   # module 3
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<COMMANDE BASH>" : exécution sur vm-stNN-<nom> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
kql() {     # kql "<REQUÊTE>" : exécution dans log-stNN-shared
  az monitor log-analytics query -w "$WS" --analytics-query "$1" -o table
}
alertes() { # alertes : alertes déclenchées par les règles alr-stNN-* (Azure Resource Graph)
  az graph query --first 50 -o table --query "data" -q "alertsmanagementresources
    | where type =~ 'microsoft.alertsmanagement/alerts' and name startswith 'alr-${ST}-'
    | project Regle=name, Cible=tostring(properties.essentials.targetResourceName),
      Gravite=tostring(properties.essentials.severity),
      Condition=tostring(properties.essentials.monitorCondition),
      Debut=tostring(properties.essentials.startDateTime) | order by Debut desc"
}
echo "$ST ${WS_ID##*/} ${#WS} $DIAG_SA $COURRIEL"
```
Résultat attendu (stagiaire 07 ; nom du compte avec suffixe éventuel du module 3) :
```
st07 log-st07-shared 36 starveost07diag prenom.nom@exemple.fr
```
`36` : longueur de l'ID client (GUID) de l'espace de travail, utilisé par `kql`. Les sorties de `kql` comportent une colonne technique `TableName`, omise dans les résultats attendus.

**État de départ** : fin du module 9. `web01` et `web02` en fonctionnement depuis 09:00 (portail v2 servi par `lbe-st<NN>-web`), agent Azure Monitor et règle `dcr-st<NN>-linux` actifs depuis le module 7 ; instances de l'API `vmss-st<NN>-api` désallouées depuis la fin du J3 ; coffre `rsv-st<NN>-arveo` avec ses travaux de sauvegarde ; serveur de Lyon désalloué à 12:28 (non utilisé ici) ; VMs de test du module 4 désallouées, pare-feu et tables de routes supprimés depuis la fin du J2. Le module 10 n'utilise aucune ressource du module 8. Stagiaire en retard : `./scripts/catch-up/module-10/deploy.sh <NN> <COURRIEL>` (10 à 15 min) produit l'état de FIN du module 10.

---

## Lab 10.1 ⭐ — Explorer les données de supervision d'Arvéo (guidé)
**Durée** : 12 min en séance (+ 3 min à 13:30) · **Objectif** : exploiter les métriques, les paramètres de diagnostic et le journal d'activité des ressources Arvéo (objectif 11)
**Contexte** : avant de définir des alertes, l'équipe d'exploitation fait l'inventaire de ce qui est déjà mesuré. Les journaux de ressources n'ayant aucun historique, la préparation de 13:30 les active dès le début du module : à 14:30, les tables seront alimentées.
**Prérequis** : bloc de variables exécuté ; état de départ conforme.

### Étapes
1. **(13:30, au retour de la pause déjeuner)** Lancer la préparation de la supervision (2 à 4 min) :
   ```bash
   ./scripts/labs/module-10/preparer-supervision.sh "$NN"
   ```
   Résultat attendu (nombre d'instances et IDs variables) :
   ```
   == VMs web
      vm-st07-web01 : VM running
      vm-st07-web02 : VM running
   == API vmss-st07-api
      2 instance(s) : démarrage lancé ; mise à l'échelle as-st07-api réactivée
   == VM de test de la base (vm-st07-test-data)
      démarrage lancé (lab 10.5)
   == Agent Network Watcher sur vm-st07-web01
      NetworkWatcherAgentLinux : Succeeded
   == Paramètres de diagnostic vers log-st07-shared
      rsv-st07-arveo : diag-arveo créé (6 catégories, tables spécifiques à la ressource)
      nsg-st07-web : diag-arveo créé (allLogs)
   == Sauvegarde de partage-lyon (travail pour la table AddonAzureBackupJobs)
      travail lancé : InProgress
   == Journal de flux de VNet fl-st07-spoke-app (Traffic analytics toutes les 10 min)
      créé dans NetworkWatcherRG (stockage starveost07diag)
   == Pulsations des 15 dernières minutes (log-st07-shared)
      vm-st07-web01 vm-st07-web02
   ```

2. **(13:43)** Lire le CPU des deux serveurs web sur la dernière demi-heure :
   ```bash
   for VM in web01 web02; do
     az monitor metrics list --resource "$(az vm show -g "$RG_APP" -n "vm-${ST}-${VM}" --query id -o tsv)" \
       --metric "Percentage CPU" --interval PT5M --aggregation Average Maximum --offset 30m -o table
   done
   ```
   Résultat attendu (valeurs variables, une ligne par tranche de 5 min et par VM) :
   ```
   Timestamp            Name            Average    Maximum
   -------------------  --------------  ---------  ---------
   2026-10-08 13:15:00  Percentage CPU  2.41       6.8
   2026-10-08 13:20:00  Percentage CPU  1.97       3.12
   ```

3. Lire la santé du pool `bp-web` par serveur (métrique `DipAvailability`, dimension `BackendIPAddress`) :
   ```bash
   LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
   az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M \
     --aggregation Average --offset 15m --filter "BackendIPAddress eq '*'" -o table \
     --query "value[0].timeseries[].{IP:metadatavalues[0].value, Sante:max(data[?average!=null].average)}"
   ```
   Résultat attendu :
   ```
   IP         Sante
   ---------  -------
   10.7.4.11  100.0
   10.7.4.12  100.0
   ```

4. Lister les catégories de diagnostic du Load Balancer, puis créer le paramètre `diag-arveo` (métriques vers l'espace de travail) :
   ```bash
   az monitor diagnostic-settings categories list --resource "$LB_ID" \
     --query "[].{Categorie:name, Type:categoryType}" -o table
   az monitor diagnostic-settings create -n diag-arveo --resource "$LB_ID" --workspace "$WS_ID" \
     --metrics '[{"category":"AllMetrics","enabled":true}]' --query name -o tsv
   ```
   Résultat attendu (catégorie de journaux éventuelle `[À VÉRIFIER]` selon la région) :
   ```
   Categorie                Type
   -----------------------  -------
   LoadBalancerHealthEvent  Logs
   AllMetrics               Metrics
   diag-arveo
   ```

5. Vérifier les trois paramètres de diagnostic d'Arvéo (deux créés à 13:30, un à l'étape 4) :
   ```bash
   VAULT_ID=$(az backup vault show -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)
   NSG_ID=$(az network nsg show -g "$RG_SPOKE" -n "nsg-${ST}-web" --query id -o tsv)
   for ID in "$VAULT_ID" "$NSG_ID" "$LB_ID"; do
     az monitor diagnostic-settings list --resource "$ID" -o tsv \
       --query "[].[name, workspaceId, logAnalyticsDestinationType]" | sed "s#/subscriptions/.*/#${ID##*/} -> #"
   done
   ```
   Résultat attendu :
   ```
   diag-arveo	rsv-st07-arveo -> log-st07-shared	Dedicated
   diag-arveo	nsg-st07-web -> log-st07-shared	None
   diag-arveo	lbe-st07-web -> log-st07-shared	None
   ```
   `Dedicated` : tables spécifiques à la ressource (`AddonAzureBackupJobs`…) ; `None` : mode par défaut (`AzureDiagnostics`, `AzureMetrics`).

6. Lire les opérations d'écriture de la journée sur `rg-st<NN>-app` dans le journal d'activité :
   ```bash
   az monitor activity-log list -g "$RG_APP" --offset 8h -o table \
     --query "[?category.value=='Administrative' && status.value=='Succeeded'] | [:8].{Heure:eventTimestamp, Operation:operationName.localizedValue}"
   ```
   Résultat attendu (extrait ; opérations et libellés variables) :
   ```
   Heure                             Operation
   --------------------------------  ----------------------------------------
   2026-10-08T11:33:10.512341+00:00  Create or Update Diagnostic Setting
   2026-10-08T11:31:02.120554+00:00  Start Virtual Machine
   2026-10-08T10:14:48.881920+00:00  Run Command on Virtual Machine
   ```

7. **Portail** : **Monitor** › **Métriques** : tracer `Percentage CPU` (moyenne) de `vm-st<NN>-web01` et `vm-st<NN>-web02` sur la dernière heure, sur un même graphique ; puis **Monitor** › **Journal d'activité**, filtre groupe de ressources `rg-st<NN>-app`, période 6 heures : ouvrir une opération et relever son appelant (`Caller`).

### Critères de réussite
- [ ] `az monitor diagnostic-settings list --resource <ID_LB> --query "[].name" -o tsv` renvoie `diag-arveo`.
- [ ] Les trois ressources (coffre, NSG web, Load Balancer) ont un paramètre de diagnostic vers `log-st<NN>-shared`.
- [ ] La santé du pool affiche les deux adresses `10.<OCT>.4.11` et `10.<OCT>.4.12`.
- [ ] Le graphique du portail montre les deux VMs ; l'appelant d'une opération du journal d'activité est relevé.

---

## Lab 10.2 ⭐⭐ — Alertes et groupe d'actions d'Arvéo (semi-autonome)
**Durée** : 20 min · **Objectif** : créer des alertes de métrique et de journal d'activité reliées à un groupe d'actions, puis prouver leur déclenchement et leur résolution (objectif 11)
**Contexte** : la DSI d'Arvéo fixe trois règles de supervision pour le portail : être prévenue d'une saturation CPU DURABLE sur n'importe quelle VM applicative (instances futures de l'API comprises), savoir quand un serveur web quitte le pool du Load Balancer, et tracer toute suppression d'une règle de filtrage réseau. Les notifications partent par courriel vers l'équipe d'exploitation.
**Prérequis** : lab 10.1 terminé ; adresse `<COURRIEL>` consultable.

**Énoncé** :
1. Créer le groupe d'actions `ag-st<NN>-exploitation` (nom court `ag-st<NN>-exp`) dans `rg-st<NN>-shared`, avec une notification par courriel vers `<COURRIEL>`. Vérifier la réception du courriel de confirmation d'ajout au groupe.
2. Créer la règle `alr-st<NN>-cpu-vm` (gravité 2) : CPU moyen > 80 % sur 5 min, évaluée chaque minute, pour TOUTES les VMs de `rg-st<NN>-app` en France Central.
3. Créer la règle `alr-st<NN>-lb-sante` (gravité 1) sur `lbe-st<NN>-web` : `DipAvailability` moyenne < 100 sur 5 min, évaluée chaque minute, une série par adresse du pool (`BackendIPAddress`).
4. Créer la règle `alr-st<NN>-nsg-regle` (journal d'activité) : suppression d'une règle de sécurité de NSG dans `rg-st<NN>-spoke` OU `rg-st<NN>-app`.
5. Déclencher les trois règles (fourni) :
   ```bash
   vmrun web01 "systemd-run --unit=arveo-charge --collect timeout 900 \
     sh -c 'yes >/dev/null & yes >/dev/null & wait'; echo charge lancée"
   vmrun web02 "systemctl stop nginx; echo nginx arrêté"
   az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" -n Test-Alerte \
     --priority 4090 --access Deny --protocol Tcp --destination-port-ranges 9999 -o none
   az network nsg rule delete -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" -n Test-Alerte
   date +%T
   ```
   Résultat attendu : `charge lancée`, `nginx arrêté`, puis l'heure de lancement (début de la mesure).
6. Suivre les alertes (fonction `alertes` ou portail **Monitor** › **Alertes**) jusqu'à ce que les trois règles aient déclenché ; relever l'heure de chaque courriel reçu.
7. Mettre fin aux deux incidents (fourni), puis attendre la résolution des alertes avec état :
   ```bash
   vmrun web01 "systemctl stop arveo-charge; echo charge arrêtée"
   vmrun web02 "systemctl start nginx; echo nginx démarré"
   ```
8. Répondre par écrit :
   - a. Pourquoi une portée « groupe de ressources » plutôt que la liste des deux VMs web pour la règle CPU ?
   - b. Pourquoi l'alerte `alr-st<NN>-nsg-regle` ne passe-t-elle jamais à l'état « Résolue » ?
   - c. Décomposer le délai observé entre le lancement de la charge et le courriel de la règle CPU.

**Indices** :
- Groupe d'actions : `az monitor action-group create --short-name <NOM_COURT> --action email <NOM_RECEPTEUR> <ADRESSE> --tags ...` ; ID : `--query id -o tsv`.
- Règle CPU : `az monitor metrics alert create --scopes <ID_GROUPE> --target-resource-type Microsoft.Compute/virtualMachines --target-resource-region francecentral --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --severity 2 --action <ID_GROUPE_ACTIONS>`.
- Dimension : `--condition "avg DipAvailability < 100 where BackendIPAddress includes 10.<OCT>.4.11 or 10.<OCT>.4.12"`.
- Journal d'activité : `az monitor activity-log alert create --scope <ID_RG_1> <ID_RG_2> --condition category=Administrative and operationName=Microsoft.Network/networkSecurityGroups/securityRules/delete --action-group <ID_GROUPE_ACTIONS>`.
- Délais indicatifs : CPU 6 à 10 min (fenêtre de 5 min + évaluation), santé du pool 2 à 6 min, journal d'activité 3 à 10 min `[À VÉRIFIER]` mesurés au J-1.
- Liste des règles : `az monitor metrics alert list -g rg-st<NN>-shared -o table` et `az monitor activity-log alert list -g rg-st<NN>-shared -o table`.

**Critères de réussite** :
- [ ] `az monitor action-group show -g rg-st<NN>-shared -n ag-st<NN>-exploitation --query "emailReceivers[0].status" -o tsv` renvoie `Enabled`.
- [ ] Les trois règles existent et sont activées (`enabled` = `true`).
- [ ] `alertes` montre une alerte `alr-st<NN>-cpu-vm` sur `vm-st<NN>-web01`, une `alr-st<NN>-lb-sante` et une `alr-st<NN>-nsg-regle`.
- [ ] Après l'étape 7, les alertes CPU et santé du pool sont `Resolved`.
- [ ] Les trois réponses de l'étape 8 sont rédigées, délais mesurés à l'appui.

---

## Lab 10.3 ⭐⭐ — Interroger `log-st<NN>-shared` en KQL (semi-autonome)
**Durée** : 20 min · **Objectif** : interroger un espace Log Analytics en KQL pour diagnostiquer l'état des VMs, des sauvegardes et du réseau, et en mesurer le coût (objectif 11)
**Contexte** : le responsable d'exploitation d'Arvéo prépare sa réunion hebdomadaire. Il attend six réponses chiffrées, chacune issue d'une requête réutilisable, conservée dans le dépôt Git.
**Prérequis** : lab 10.2 étape 5 lancée (charge CPU de `web01`) ; paramètres de diagnostic de 13:30 actifs depuis au moins 45 min.

**Énoncé** :
1. Ouvrir `scripts/labs/module-10/requetes-arveo.kql`. La requête Q1 est complète ; Q2 à Q6 contiennent des `TODO`.
2. Exécuter Q1 dans le portail (**log-st<NN>-shared** › **Journaux**, mode KQL), puis avec la fonction `kql`.
3. Compléter et exécuter Q2 à Q6, en CLI ou dans le portail :
   - Q2 : CPU moyen et maximal par minute de chaque serveur web sur la dernière heure ; dans le portail, tracer la courbe (`render timechart`) et y repérer la charge du lab 10.2 ;
   - Q3 : nombre d'événements Syslog par facilité et par niveau sur les 4 dernières heures ;
   - Q4 : travaux de sauvegarde depuis 13:30 (opération, état, nom de l'élément protégé, durée) ;
   - Q5 : disponibilité moyenne du pool `bp-web` par tranche de 5 min depuis la table `AzureMetrics` ; repérer l'arrêt de nginx sur `web02` ;
   - Q6 : volume facturable ingéré par table sur 24 h, en Mo, trié par volume décroissant.
4. Enregistrer Q6 dans l'espace de travail comme requête (catégorie `Arveo`, nom « Volume ingéré par table »).
5. Répondre par écrit :
   - a. Quelle table coûte le plus ? Estimer le volume mensuel de l'espace de travail au rythme actuel.
   - b. Pourquoi la table `AzureActivity` est-elle absente, alors que le journal d'activité contient des événements ?
   - c. Q5 montre-t-elle l'arrêt de nginx à la même minute que l'alerte `alr-st<NN>-lb-sante` ? Expliquer l'écart éventuel.

**Indices** :
- Tables et colonnes : panneau **Tables** du portail, ou `<TABLE> | getschema` ; échantillon : `<TABLE> | take 5`.
- Q2 : `Perf`, `ObjectName == "Processor"`, `CounterName == "% Processor Time"`, instance totale (`InstanceName in ("_Total", "total")` `[À VÉRIFIER]` libellé AMA Linux), `summarize avg(), max() by Computer, bin(TimeGenerated, 1m)`.
- Q3 : `Syslog`, `summarize count() by Facility, SeverityLevel`.
- Q4 : `AddonAzureBackupJobs` (`JobOperation`, `JobStatus`, `JobDurationInSecs`, `BackupItemUniqueId`) ; nom de l'élément : `CoreAzureBackup` (`BackupItemUniqueId`, `BackupItemFriendlyName`) avec `join kind=leftouter`.
- Q5 : `AzureMetrics`, `MetricName == "DipAvailability"`, `Resource =~ "lbe-st<NN>-web"`, `bin(TimeGenerated, 5m)`.
- Q6 : `Usage`, colonnes `DataType`, `Quantity` (Mo), `IsBillable`.
- Requête enregistrée : `az monitor log-analytics workspace saved-search create -g <GROUPE> --workspace-name <ESPACE> -n <ID> --category Arveo --display-name "<NOM>" --saved-query "<KQL>"`.

**Critères de réussite** :
- [ ] Q1 à Q6 s'exécutent sans erreur ; Q2 montre `web01` au-dessus de 80 % pendant la charge du lab 10.2.
- [ ] Q4 renvoie au moins le travail `Backup` de `partage-lyon` lancé à 13:30.
- [ ] Q5 montre une valeur inférieure à 100 pendant l'arrêt de nginx sur `web02`.
- [ ] `az monitor log-analytics workspace saved-search list -g rg-st<NN>-shared --workspace-name log-st<NN>-shared --query "[?category=='Arveo'].displayName" -o tsv` affiche la requête Q6.
- [ ] Les trois réponses de l'étape 5 sont rédigées.

---

## Défi 10.4 ⭐⭐⭐ — Détecter les attaques SSH par force brute (autonome)
**Durée** : 10 min en séance (règle livrée ; preuve vérifiée au retour de pause) · **Objectif** : créer une alerte de recherche dans les journaux avec dimensions, reliée au groupe d'actions, et en évaluer les limites (objectif 11)
**Contexte** : le RSSI d'Arvéo constate dans les journaux du module 7 des tentatives de connexion SSH sur les serveurs web. Il demande une détection automatique, par serveur et par adresse source, notifiée à l'exploitation, et une requête réutilisable par l'équipe sécurité. La règle doit être livrée sous forme versionnée.

Simulation des tentatives (fournie, à lancer AVANT de tester la règle) :
```bash
./scripts/labs/module-10/simuler-echecs-ssh.sh "$NN"
```
Résultat attendu :
```
== Échecs SSH simulés sur vm-st07-web01 (journal authpriv, niveau warning)
   203.0.113.50 : 8 échecs
   198.51.100.7 : 3 échecs
Visibles dans la table Syslog sous 1 à 5 min.
```

**Exigences** :

| Élément | Exigence |
|---|---|
| Détection | Au moins 5 messages `Failed password` en 10 min, par serveur ET par adresse source |
| Règle | `alr-st<NN>-ssh-echecs`, gravité 1, évaluation toutes les 5 min, résolution automatique, `ag-st<NN>-exploitation` |
| Réutilisation | Fonction KQL `ArveoEchecsSsh` enregistrée dans `log-st<NN>-shared` (catégorie `Arveo`) |
| Livraison | Fichier Bicep (ou script CLI) versionné, tags Arvéo, aucune valeur propre au stagiaire en dur |
| Preuve | Alerte déclenchée pour `vm-st<NN>-web01` et `203.0.113.50`, aucune pour `198.51.100.7` |

**Énoncé** :
1. Écrire et tester la requête dans le portail, puis l'enregistrer comme fonction `ArveoEchecsSsh` (colonnes `TimeGenerated`, `Computer`, `IpSource`, `SyslogMessage`).
2. Déployer la règle d'alerte conforme aux exigences.
3. Lancer la simulation, puis prouver le résultat : alerte déclenchée (fonction `alertes`, dimensions visibles dans le portail), courriel reçu.
4. Répondre par écrit :
   - a. Délai mesuré entre la simulation et le courriel : de quoi se compose-t-il ? Comment le réduire, et à quel prix ?
   - b. Un vrai démon `sshd` journalise ses échecs au niveau `info` de `authpriv`. La règle `dcr-st<NN>-linux` (module 7) les collecterait-elle ? Que modifier, avec quel impact sur le coût ?
   - c. Pourquoi une alerte de métrique ne peut-elle pas répondre à ce besoin ?

**Critères de réussite** :
- [ ] `az monitor scheduled-query show -g rg-st<NN>-shared -n alr-st<NN>-ssh-echecs --query "{Freq:evaluationFrequency, Fenetre:windowSize, Grav:severity, Auto:autoMitigate}" -o table` affiche `PT5M`, `PT10M`, `1`, `True`.
- [ ] `kql "ArveoEchecsSsh | summarize count() by Computer, IpSource"` renvoie 8 lignes pour `203.0.113.50` et 3 pour `198.51.100.7`.
- [ ] `alertes` montre `alr-st<NN>-ssh-echecs` déclenchée ; aucune série pour `198.51.100.7` dans le portail.
- [ ] Le fichier Bicep (ou le script) est versionné ; les trois réponses de l'étape 4 sont rédigées.

---

## Lab 10.5 ⭐⭐ — Diagnostiquer les flux Arvéo avec Network Watcher (semi-autonome)
**Durée** : 20 min (5 min avant la pause, 15 min après) · **Objectif** : diagnostiquer des flux réseau avec Network Watcher et exploiter les journaux de flux de VNet (objectif 11)
**Contexte** : l'équipe ERP ouvre un ticket : « depuis mardi soir, la base de test `sql.arveo.internal:1433` (`vm-st<NN>-test-data`) n'est plus joignable depuis le portail ; l'API répond toujours ». L'équipe sécurité demande en parallèle la preuve que SSH est refusé depuis Internet sur les serveurs web et que l'API n'accepte que le portail. Le journal de flux du spoke applicatif est actif depuis 13:30.
**Prérequis** : préparation de 13:30 terminée (agent Network Watcher, journal de flux, VM de test démarrée) ; bloc de variables exécuté.

**Énoncé** :
1. **(15:10, avant la pause)** Vérifier l'instance Network Watcher de France Central et la configuration du journal de flux `fl-st<NN>-spoke-app` : cible, compte de stockage, état, intervalle de Traffic analytics.
2. **(Avant la pause)** Générer du trafic (fourni) : requêtes clientes sur le portail, appels de l'API depuis `web01`, tentative SSH de `web01` vers une instance de l'API, tentative SQL vers la base de test.
   ```bash
   LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
   API_VM=$(az vm list -g "$RG_APP" --query "[?virtualMachineScaleSet!=null] | [0].name" -o tsv)
   API_IP=$(az vm list-ip-addresses -g "$RG_APP" -n "$API_VM" \
     --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
   for i in $(seq 20); do curl -s -o /dev/null "http://${LB_IP}/"; curl -s -o /dev/null "http://${LB_IP}/api/"; done
   vmrun web01 "curl -s -m 3 -o /dev/null http://10.${OCT}.5.100:8080/ && echo API-OK
   timeout 3 bash -c '</dev/tcp/${API_IP}/22' 2>/dev/null && echo SSH-OUVERT || echo SSH-REFUSE
   timeout 3 bash -c '</dev/tcp/10.${OCT}.8.10/1433' 2>/dev/null && echo SQL-OK || echo SQL-ECHEC"
   echo "$API_VM $API_IP"
   ```
   Résultat attendu (nom et adresse de l'instance variables) :
   ```
   API-OK
   SSH-REFUSE
   SQL-ECHEC
   vmss-st07-api_1a2b3c4d 10.7.5.4
   ```
3. **(15:30, après la pause)** Résolution des problèmes de connexion depuis `vm-st<NN>-web01` : vers l'API (`10.<OCT>.5.100`, TCP 8080), puis vers `sql.arveo.internal` (TCP 1433). Relever l'état, le nombre de sondes en échec et les problèmes signalés sur les sauts.
4. Saut suivant depuis `web01` (`10.<OCT>.4.11`) vers `10.<OCT>.8.10`, puis vers `10.<OCT>.5.100`.
5. Vérification des flux IP (IP flow verify), sens entrant, et règle décisive de chaque cas :

   | Cas | VM cible | Port local | Source distante |
   |---|---|---|---|
   | a | `vm-st<NN>-web01` | TCP 80 | `198.51.100.10:50000` (Internet) |
   | b | `vm-st<NN>-web01` | TCP 22 | `198.51.100.10:50000` (Internet) |
   | c | instance de l'API (`$API_VM`) | TCP 8080 | `10.<OCT>.4.11:50000` (`web01`) |
   | d | instance de l'API (`$API_VM`) | TCP 8080 | `10.<OCT>.8.10:50000` (base de test) |

6. Interroger `NTANetAnalytics` : les 10 combinaisons type de flux / état / destination / port les plus fréquentes sur 2 h, puis les flux REFUSÉS (source, destination, port, règle NSG). Retrouver la tentative SSH de l'étape 2.
7. Répondre par écrit :
   - a. Cause du ticket ERP et deux corrections possibles. Pourquoi modifier `nsg-st<NN>-data` ne servirait à rien ?
   - b. Pourquoi le cas d n'est-il pas décidé par `Deny-VNet-Inbound` ?
   - c. Pourquoi le journal de flux a-t-il été créé à 13:30 et non à l'ouverture du ticket ?

**Indices** :
- Instance : `az network watcher list --query "[?location=='francecentral']"`.
- Journal de flux : `az network watcher flow-log show --location francecentral --name <NOM>` (propriétés `targetResourceId`, `storageId`, `enabled`, `flowAnalyticsConfiguration`).
- Connexion : `az network watcher test-connectivity -g <GROUPE> --source-resource <VM> --dest-address <ADRESSE_OU_NOM> --dest-port <PORT> --protocol Tcp` (30 à 60 s) ; propriétés `connectionStatus`, `probesFailed`, `hops[].issues`.
- Saut suivant : `az network watcher show-next-hop -g <GROUPE> --vm <VM> --source-ip <IP> --dest-ip <IP>`.
- IP flow verify : `az network watcher test-ip-flow -g <GROUPE> --vm <VM> --direction Inbound --protocol TCP --local <IP>:<PORT> --remote <IP>:<PORT>` ; IP de l'instance : `$API_IP`.
- Traffic analytics : colonnes `SubType` (`FlowLog`), `FlowType`, `FlowStatus`, `SrcIp`, `DestIp`, `DestPort`, `NsgRule` ; données traitées toutes les 10 min, visibles 20 à 30 min après le flux `[À VÉRIFIER]`.
- Rappels : M4 (étiquette `VirtualNetwork`, peering non transitif), nettoyage du J2 (`module-04-firewall.sh`).

**Critères de réussite** :
- [ ] Connexion vers l'API : `Reachable` ; vers `sql.arveo.internal:1433` : `Unreachable`.
- [ ] Saut suivant vers `10.<OCT>.8.10` : `None` ; vers `10.<OCT>.5.100` : `VnetLocal`.
- [ ] Les quatre cas IP flow verify sont notés avec leur règle décisive (a : autorisé ; b, c, d : décision et règle justifiées).
- [ ] La requête `NTANetAnalytics` renvoie des flux du spoke applicatif, dont au moins un flux refusé.
- [ ] Les trois réponses de l'étape 7 sont rédigées.

---

## Bonus 🚀
1. **Fenêtre de maintenance** : créer la règle de traitement `apr-st<NN>-maintenance` qui supprime les notifications des alertes de `rg-st<NN>-app` chaque mardi de 22:00 à 23:00 (heure de Paris). Vérifier qu'elle n'empêche pas la création des alertes. Indice : `az monitor alert-processing-rule create --rule-type RemoveAllActionGroups --schedule-recurrence-type Weekly` `[À VÉRIFIER]` options de planification.
2. **Moniteur de connexion** : créer `cm-st<NN>-api` qui teste toutes les 30 s la connexion TCP 8080 de `vm-st<NN>-web01` vers `10.<OCT>.5.100`, résultats dans `log-st<NN>-shared`. Désallouer une instance de l'API et observer la table `NWConnectionMonitorTestResult` `[À VÉRIFIER]` nom de table.
3. **Capture de paquets** : capturer 60 s de trafic TCP 80 sur `vm-st<NN>-web02` vers `starveost<NN>diag`, générer quelques requêtes sur le portail, télécharger le fichier `.cap` et l'ouvrir avec Wireshark (ou `tcpdump -r`). Repérer les sondes du Load Balancer (`168.63.129.16`).
4. **Classeur « Santé Arvéo »** : créer un classeur dans `rg-st<NN>-shared` avec trois visualisations (Q1 en tableau, Q2 en courbe, alertes actives de l'abonnement filtrées sur `alr-st<NN>-`), un paramètre de période, puis l'exporter en modèle ARM (**Modifier** › **Éditeur avancé**).
5. **Seuil dynamique** : créer une copie de la règle CPU avec un seuil dynamique (sensibilité moyenne) et comparer, dans le portail, la bande de valeurs « normales » calculée avec le seuil statique de 80 %.

## Nettoyage
- **Fin du module (15:43)**, avant l'évaluation :
  ```bash
  ./scripts/cleanup/module-10-monitoring.sh "$NN"
  ```
  Le script arrête la charge CPU et redémarre nginx sur `web02` si nécessaire, supprime le journal de flux `fl-st<NN>-spoke-app` (coût de Traffic analytics), les captures de paquets et moniteurs de connexion du bonus, et désalloue la VM de test `vm-st<NN>-test-data`. Relançable sans risque.
- Conservés pour l'évaluation finale : paramètres de diagnostic, groupe d'actions, règles d'alerte, fonction KQL, extension Network Watcher.
- **Fin de formation**, avant la suppression des groupes de ressources (après `module-09-backup.sh --purge`) :
  ```bash
  ./scripts/cleanup/module-10-monitoring.sh "$NN" --purge
  ```
  Supprime en plus les règles d'alerte, la règle de traitement, le groupe d'actions, les requêtes enregistrées, les paramètres de diagnostic et l'extension Network Watcher. Les objets créés dans `NetworkWatcherRG` (journaux de flux, moniteurs de connexion, captures) ne disparaissent PAS avec les groupes `rg-st<NN>-*` : ce script est le seul à les supprimer.
- Rattrapage complet du module : `./scripts/catch-up/module-10/deploy.sh <NN> <COURRIEL>`.
- Coûts : ingestion Log Analytics au Go, règles d'alerte de métrique par série surveillée, règles de journal par fréquence d'évaluation, journaux de flux au Go collecté, Traffic analytics au Go traité, notifications (courriels inclus dans un quota gratuit) `[À VÉRIFIER]` calculatrice de prix Azure.

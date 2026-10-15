# Module 12 — Cas de synthèse : corrections

Solution des sept demandes du cas `module-12-synthese-exercices.md`, avec le bloc de variables de l'énoncé. Sorties données pour `st07`, `SES=1510`.

---

## Demande 1 — Accès de l'auditeur (M1, M2)

```bash
AU_ID=$(az rest --method get \
  --url "https://graph.microsoft.com/v1.0/directory/administrativeUnits?\$filter=displayName eq 'AU-${ST}'" \
  --query "value[0].id" -o tsv)
az rest --method post \
  --url "https://graph.microsoft.com/v1.0/directory/administrativeUnits/${AU_ID}/members" \
  --headers "Content-Type=application/json" \
  --body "{\"@odata.type\":\"#microsoft.graph.group\",\"displayName\":\"${ST}-GRP-Audit\",
           \"mailEnabled\":false,\"mailNickname\":\"${ST}-grp-audit\",\"securityEnabled\":true}" -o none
GID=$(az ad group show --group "${ST}-GRP-Audit" --query id -o tsv)
az role assignment create --assignee-object-id "$GID" --assignee-principal-type Group \
  --role Reader --scope "$(az group show -n "rg-${ST}-data" --query id -o tsv)" -o none
az role assignment list -g "rg-${ST}-data" \
  --query "[?principalName=='${ST}-GRP-Audit'].{Role:roleDefinitionName, Scope:scope}" -o table
```
Sortie attendue :
```
Role    Scope
------  ------------------------------------------------------------------
Reader  /subscriptions/<ID>/resourceGroups/rg-st07-data
```

### Pourquoi
- Création DANS l'AU : seule voie ouverte à un administrateur de groupes délégué (module 1).
- `--assignee-principal-type Group` : évite l'erreur de réplication quand le groupe vient d'être créé.
- Question c : le rôle suit la fonction (le groupe), pas la personne ; un départ = retrait du groupe, sans toucher aux attributions.

---

## Demande 2 — Conformité (M2)

```bash
az tag update --resource-id "$(az group show -n "rg-${ST}-app" --query id -o tsv)" \
  --operation Merge --tags Audit=2026 -o none
az group show -n "rg-${ST}-app" --query tags -o json
az network nsg create -g "rg-${ST}-app" -n "nsg-${ST}-eval" -l westeurope
```
Sortie attendue : tags existants (`Projet`, `Environnement`, `Proprietaire`) + `Audit`, puis `(RequestDisallowedByPolicy) Resource 'nsg-st07-eval' was disallowed by policy.`

### Pourquoi
- `--operation Merge` ajoute sans écraser ; `az group update --tags` remplace TOUS les tags.
- Refus par l'affectation « Regions autorisees » du module 2 : effet `deny` évalué à la création.

---

## Demande 3 — Règle versionnée (M3, M4)

`eval.bicep` :
```bicep
param location string = 'francecentral'
param numero string

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-st${numero}-eval'
  location: location
  tags: {
    Projet: 'Arveo'
    Environnement: 'Formation'
    Proprietaire: 'st${numero}'
  }
  properties: {
    securityRules: [
      {
        name: 'Deny-SSH-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}
```
```bash
az deployment group create -g "rg-${ST}-app" -f eval.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
az deployment group what-if -g "rg-${ST}-app" -f eval.bicep -p numero="$NN"
az deployment group create -g "rg-${ST}-app" -f eval.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Sortie attendue : `Succeeded`, puis `what-if` : `Resource changes: 1 no change.`, puis `Succeeded`.

### Pourquoi
- Tags dans le modèle : la stratégie « tag obligatoire » du module 2 refuserait sinon le NSG.
- Question d : idempotence = preuve que l'état réel correspond au code ; l'auditeur lit le fichier, pas le portail.

---

## Demande 4 — Flux effectifs (M4, M7)

```bash
az vm start -g "rg-${ST}-app" -n "vm-${ST}-web01" -o none
az network nic list-effective-nsg -g "rg-${ST}-app" -n "nic-${ST}-web01" \
  --query "value[].effectiveSecurityRules[?direction=='Inbound'].{Nom:name, Acces:access, Port:destinationPortRange, Priorite:priority}" -o table
```
Sortie attendue (extrait) :
```
Nom                                  Acces   Port     Priorite
-----------------------------------  ------  -------  --------
securityRules/Allow-HTTP-HTTPS-Inbound  Allow   80-80    100
defaultSecurityRules/AllowVnetInBound   Allow   0-65535  65000
defaultSecurityRules/DenyAllInBound     Deny    0-65535  65500
```
Explication : le trafic HTTP du Load Balancer est autorisé par `Allow-HTTP-HTTPS-Inbound` (priorité 100) ; tout autre flux venant d'Internet tombe sur `DenyAllInBound`. Règles effectives = NSG du sous-réseau + NSG de la carte, évalués dans cet ordre en entrée.

---

## Demande 5 — Partage de preuve (M6)

```bash
SA_ARCH="starveost${NN}arch${SES}"
az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$SA_ARCH" --query id -o tsv)" -o none
sleep 60   # propagation du rôle de données
az storage container create --account-name "$SA_ARCH" -n audit --auth-mode login -o none
echo "Preuve d'audit Arvéo $(date -u +%F)" > preuve.txt
az storage blob upload --account-name "$SA_ARCH" -c audit -n preuve.txt -f preuve.txt --auth-mode login -o none
EXP=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ)
SAS=$(az storage container generate-sas --account-name "$SA_ARCH" -n audit --permissions r \
  --expiry "$EXP" --https-only --as-user --auth-mode login -o tsv)
URL="https://${SA_ARCH}.blob.core.windows.net/audit/preuve.txt?${SAS}"
curl -s "$URL"
curl -s -o /dev/null -w "%{http_code}\n" -X PUT -H "x-ms-blob-type: BlockBlob" -d "x" "$URL"
```
Sortie attendue : `Preuve d'audit Arvéo 2026-10-16`, puis `403`.

### Pourquoi
- SAS de délégation d'utilisateur : signé par une clé Entra ID, durée limitée à 7 jours, révocable ; fonctionne même avec `allowSharedKeyAccess=false`.
- Question a : `starveost<NN>data<SES>` a l'accès public désactivé (défi 06.4) ; le pare-feu du compte est évalué AVANT l'autorisation : aucun jeton ne passe depuis Internet.

---

## Demande 6 — Sauvegarde à la demande (M9)

```bash
VAULT="rsv-${ST}-arveo"
CONT=$(az backup container list -g "rg-${ST}-shared" -v "$VAULT" --backup-management-type AzureIaasVM \
  --query "[?contains(name,'vm-${ST}-web02')].name | [0]" -o tsv)
az backup protection backup-now -g "rg-${ST}-shared" -v "$VAULT" -c "$CONT" \
  -i "vm-${ST}-web02" --backup-management-type AzureIaasVM \
  --retain-until "$(date -u -d '+7 days' +%d-%m-%Y)" --query name -o tsv
az backup job list -g "rg-${ST}-shared" -v "$VAULT" \
  --query "[?properties.entityFriendlyName=='vm-${ST}-web02'] | [0].{Etat:properties.status, Operation:properties.operation}" -o table
```
Sortie attendue : un identifiant de travail, puis `InProgress  Backup`.

### Pourquoi
- Question b : le point **instantané** (snapshot local, niveau « Snapshot ») est disponible en quelques minutes ; le point **coffre** arrive après le transfert, plus tard. Restauration la plus rapide = instantané.

---

## Demande 7 — Surveillance (M10)

```bash
az monitor metrics alert create -g "rg-${ST}-app" -n "ar-${ST}-eval-cpu" \
  --scopes "$(az vm show -g "rg-${ST}-app" -n "vm-${ST}-web02" --query id -o tsv)" \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --severity 2 \
  --action "$(az monitor action-group show -g "rg-${ST}-shared" -n "ag-${ST}-exploitation" --query id -o tsv)" -o none
```
Requête KQL (espace `log-st<NN>-shared`) :
```kusto
Heartbeat
| summarize DernierBattement = max(TimeGenerated) by Computer
| order by Computer asc
```
Sortie attendue : deux lignes, `vm-st07-web01` et `vm-st07-web02`, horodatage de moins de 5 min.

Groupe d'actions `ag-st<NN>-exploitation` : dans `rg-st<NN>-shared` (lab 10.2 et rattrapage du module 10).

---

## Auto-évaluation — réponses

| Q | Réponse | Justification |
|---|---|---|
| 1 | B | Règle d'appartenance dynamique = Entra ID P1 |
| 2 | C | Effet `deny` évalué à la création et à la mise à jour ; l'existant est signalé non conforme |
| 3 | C | Moindre privilège : scope minimal, attribution à un groupe |
| 4 | B | Déclaratif = état cible ; idempotence vérifiée par la demande 3 |
| 5 | A | Le NSG filtre, l'UDR achemine |
| 6 | B | Peering non transitif ; transit de passerelle explicite des deux côtés |
| 7 | C | Circuit privé opérateur, débits garantis |
| 8 | B | Réseau avant autorisation |
| 9 | A | Pointeurs (reparse points), rappel à l'ouverture |
| 10 | B | 99,99 % avec zones contre 99,95 % avec groupe à haute disponibilité |
| 11 | B | Script exécuté par l'agent, rejouable |
| 12 | B | Échange = préchauffage puis bascule du trafic |
| 13 | B | Disque restauré en parallèle, VM en production intacte |
| 14 | B | Signal métrique + groupe d'actions |
| 15 | A | Règle autorisante ou bloquante nommée pour un 5-uplet |

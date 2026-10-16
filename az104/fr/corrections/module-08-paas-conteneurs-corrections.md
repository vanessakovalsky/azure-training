# Module 08 — Corrections

Exemples donnés pour le stagiaire 07, session `2610` (`NN=07`, `OCT=7`, `SES=2610`). Toutes les solutions supposent le bloc de variables des exercices exécuté dans Cloud Shell (Bash) : `NN`, `SES`, `OCT`, `ST`, `RG_APP`, `RG_SPOKE`, `LOC`, `TAGS`, `PLAN`, `APP`, `ACR`, `HOST`. Identifiants d'instance, empreintes d'image, adresses et horodatages varient d'une exécution à l'autre.

## Exercice 08.1 ⭐ — Choisir le plan App Service

### Solution
| N° | Niveau | Exigence décisive |
|---|---|---|
| 1 Maquette intranet | Free F1 (ou Basic B1 si la maquette doit rester réactive) | Aucune exigence ; F1 gratuit, quota de CPU quotidien, ni Always On ni domaine personnalisé |
| 2 Portail client 2026 | Standard S1 | Emplacements (mise en production sans interruption) et mise à l'échelle automatique : Standard minimum ; intégration au réseau virtuel : Basic minimum |
| 3 Portail client 2027 | Premium v3 (P0v3 ou P1v3) | Redondance de zone : Premium v2 à v4 uniquement, 2 instances minimum |
| 4 Extranet des douanes | Isolated v2 (App Service Environment v3) | Environnement mono-locataire, déployé dans un VNet d'Arvéo |

Étape 2 : application 2, **2 instances minimum** : le contrôle d'intégrité n'a d'effet qu'avec au moins deux instances (l'instance défaillante est retirée de l'équilibrage), la maintenance de la plateforme redémarre les instances l'une après l'autre sans coupure, et un pic n'attend pas le délai de la mise à l'échelle.

Étape 3 : techniquement possible (plusieurs applications par plan), mais déconseillé : la maquette consommerait le CPU et la mémoire des instances du portail (voisin bruyant), serait facturée au prix du niveau du portail, et suivrait ses règles de mise à l'échelle. Règle courante : un plan par environnement (production, hors production), et un plan dédié aux applications critiques.

### Pourquoi
- Les fonctions (emplacements, mise à l'échelle automatique, redondance de zone, intégration au réseau virtuel) sont des propriétés du NIVEAU DU PLAN, pas de l'application : choisir le plan, c'est choisir les fonctions.
- Le niveau le moins cher qui couvre TOUTES les exigences est retenu ; la taille (S1, S2, S3) se règle ensuite par la mesure (CPU, mémoire).
- Redondance de zone : la plateforme impose 2 instances minimum et les facture ; 3 instances garantissent une capacité suffisante pendant la perte d'une zone (sans attendre la mise à l'échelle, non garantie dans ce cas).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Basic retenu pour l'application 2 | Confusion entre mise à l'échelle manuelle (Basic) et automatique | Relire la slide « Plans : quel niveau ? » : emplacements et règles à partir de Standard |
| Standard retenu pour l'application 3 | Redondance de zone supposée disponible partout | Premium v2 à v4 uniquement |
| Premium retenu pour l'application 4 | Isolement réseau confondu avec private endpoint | Private endpoint = accès entrant privé sur infrastructure partagée ; « dédié » = Isolated v2 |

### Variantes acceptables
- Application 2 en Premium v3 P0v3 : valide (mêmes fonctions, matériel plus récent, redondance de zone possible plus tard) ; à comparer au prix de S1 `[À VÉRIFIER]` sur la calculatrice de prix.
- Application 1 sur un plan Basic existant hors production : valide si ce plan n'héberge rien de critique.

---

## Lab 08.2 ⭐ — Publier le portail v3 sur App Service

### Solution
Les commandes sont celles des étapes 1 à 7, sans modification. Contrôles finaux :
```bash
az webapp show -g "$RG_APP" -n "$APP" --query "[state, httpsOnly, clientAffinityEnabled]" -o tsv
az webapp config appsettings list -g "$RG_APP" -n "$APP" \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
```
Résultat attendu :
```
Running
true
false
production	True
```

Étape 8 (portail) : dans Kudu › **Environment**, `WEBSITE_INSTANCE_ID` (64 caractères hexadécimaux, les 8 premiers apparaissent dans la page) et `PORT=8080` ; aucune session SSH sur un système à corriger, contrairement aux VMs du module 7.

### Pourquoi
- **Plan Linux** (`--is-linux`) : Node.js s'exécute dans un conteneur géré par la plateforme ; un plan Linux n'héberge que des applications Linux.
- **S1** : niveau minimal des emplacements et de la mise à l'échelle automatique (exercice 08.3) ; 1 instance à la création, 2 ensuite par la mise à l'échelle automatique.
- **Nom avec le code de session** : `<application>.azurewebsites.net` est un nom DNS public, unique dans tout Azure ; le code de session évite les collisions entre stagiaires et entre sessions de formation.
- **HTTPS seul et TLS 1.2** : la plateforme fournit le certificat de `*.azurewebsites.net` ; toute requête HTTP est redirigée (`301`).
- **Affinité ARR désactivée** : par défaut, un cookie colle chaque navigateur à une instance ; le portail est sans état, chaque requête peut aller sur n'importe quelle instance (exercice 08.3).
- **FTP désactivé** : protocole historique, identifiants de publication à protéger ; le déploiement zip passe par le site SCM (Kudu) en HTTPS.
- **Commande de démarrage explicite** et `SCM_DO_BUILD_DURING_DEPLOYMENT=false` : aucune dépendance npm, donc aucun build Oryx ; démarrage plus rapide et prévisible.
- **Contrôle d'intégrité** `/health` : la plateforme interroge chaque instance ; une instance qui échoue durablement est retirée de l'équilibrage, puis remplacée `[À VÉRIFIER]` seuils par défaut (`WEBSITE_HEALTHCHECK_MAXPINGFAILURES`).
- **`ARVEO_ENV` en paramètre d'emplacement** dès la création : il décrit l'environnement, pas le code ; préparation de l'exercice 08.3.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Website with given name ... already exists` | Nom déjà utilisé dans Azure (autre session, faute de frappe sur `NN` ou `SES`) | Vérifier `echo $APP` ; sinon ajouter une lettre au code de session pour tout le module (`SES=2610b`) et prévenir la formatrice |
| `This region has quota of 0 instances for your subscription` `[À VÉRIFIER]` libellé | Quota App Service de l'abonnement épuisé ou nul en France Central | Formatrice : demande de quota (préparation J-10) ; dépannage : plan d'un binôme partagé pour le lab |
| `Linux Runtime 'NODE:22-lts' is not supported` | Runtime absent de la liste | Utiliser une version `NODE:*-lts` affichée à l'étape 1 |
| Page « Your web app is running and waiting for your content » | Déploiement non effectué ou en échec | Relancer `az webapp deploy` ; lire `az webapp log deployment show` `[À VÉRIFIER]` |
| `Application Error` ou `503` sur `/` | Commande de démarrage absente, ou `server.js` dans un sous-dossier de l'archive | `az webapp config show --query appCommandLine` ; `unzip -Z1 ~/arveo-build/portail-v3.zip` doit lister `server.js` à la racine |
| `curl http://` renvoie `200` au lieu de `301` | HTTPS seul non activé | `az webapp update --https-only true` |
| `409 Conflict` sur `az webapp deploy` | Déploiement précédent encore en cours | Attendre 1 min, relancer |
| `az webapp log tail` muet | Journaux du conteneur non activés, ou démarrage antérieur à l'activation | Étape 7 dans l'ordre : `log config`, `restart`, puis `log tail` |

---

## Exercice 08.3 ⭐⭐ — Mise en production de la v4 par échange, mise à l'échelle automatique

### Solution
```bash
# 1. Emplacement staging, configuration copiée depuis la production
az webapp deployment slot create -g "$RG_APP" -n "$APP" --slot staging \
  --configuration-source "$APP" --query "defaultHostName" -o tsv
STG=$(az webapp deployment slot list -g "$RG_APP" -n "$APP" --query "[0].defaultHostName" -o tsv)

# 2. Paramètre d'emplacement propre à staging, puis lecture des deux emplacements
az webapp config appsettings set -g "$RG_APP" -n "$APP" --slot staging \
  --slot-settings ARVEO_ENV=recette -o none
az webapp config appsettings list -g "$RG_APP" -n "$APP" \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
az webapp config appsettings list -g "$RG_APP" -n "$APP" --slot staging \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
```
Résultat attendu :
```
app-st07-portail-2610-staging.azurewebsites.net
production	True
recette	True
```

```bash
# 3. v4 publiée dans staging seulement
./scripts/labs/module-08/empaqueter-portail.sh v4
az webapp deploy -g "$RG_APP" -n "$APP" --slot staging \
  --src-path ~/arveo-build/portail-v4.zip --type zip -o none
curl -s "https://${HOST}/"; curl -s "https://${STG}/"
```
Résultat attendu :
```
/home/<UTILISATEUR>/arveo-build/portail-v4.zip
server.js
package.json
<h1>Arveo - portail client v3</h1><p>App Service - production - instance 3f9c1a2b</p>
<h1>Arveo - portail client v4</h1><p>App Service - recette - instance 3f9c1a2b</p>
```

```bash
# 4. Boucle de contrôle (énoncé), échange, fin de la boucle
az webapp deployment slot swap -g "$RG_APP" -n "$APP" --slot staging --target-slot production
kill %1 2>/dev/null; sort ~/arveo-build/echange.log | uniq -c -f1 | head
grep -vc ' 200 ' ~/arveo-build/echange.log

# 5. Vérification après l'échange
curl -s "https://${HOST}/"; curl -s "https://${STG}/"
```
Résultat attendu (horodatages et nombres de lignes variables) :
```
     41 07:52:01 200 client v3
     38 07:52:42 200 client v4
0
<h1>Arveo - portail client v4</h1><p>App Service - production - instance 3f9c1a2b</p>
<h1>Arveo - portail client v3</h1><p>App Service - recette - instance 3f9c1a2b</p>
```
`0` : aucune ligne sans code `200`.

```bash
# 6. Mise à l'échelle automatique du plan
PLAN_ID=$(az appservice plan show -g "$RG_APP" -n "$PLAN" --query id -o tsv)
az monitor autoscale create -g "$RG_APP" -n "as-${ST}-portail" --resource "$PLAN_ID" \
  --min-count 2 --max-count 4 --count 2 --tags $TAGS -o none
az monitor autoscale rule create -g "$RG_APP" --autoscale-name "as-${ST}-portail" \
  --condition "CpuPercentage > 70 avg 10m" --scale out 1 -o none
az monitor autoscale rule create -g "$RG_APP" --autoscale-name "as-${ST}-portail" \
  --condition "CpuPercentage < 30 avg 15m" --scale in 1 -o none
az monitor autoscale show -g "$RG_APP" -n "as-${ST}-portail" \
  --query "profiles[0].[capacity.minimum, capacity.maximum, length(rules)]" -o tsv

# 7. Deux instances (1 à 5 min après l'étape 6)
az webapp list-instances -g "$RG_APP" -n "$APP" --query "length(@)" -o tsv
for i in $(seq 20); do curl -s "https://${HOST}/" | grep -o 'instance [0-9a-f]*'; done | sort | uniq -c
```
Résultat attendu (répartition variable) :
```
2
4
2
2
     11 instance 3f9c1a2b
      9 instance 8d41e0c7
```

Réponses de l'étape 8 :
- **a.** `ARVEO_ENV` décrit l'emplacement (production ou recette), pas la version du code. Non marqué, il voyagerait avec le code lors de l'échange : la production afficherait `recette` et la recette `production`. En entreprise, les chaînes de connexion vers la base de production et la base de recette sont marquées de la même façon : sans cela, l'échange brancherait la production sur la base de recette.
- **b.** Nouvel échange `staging` ↔ production : `staging` contient toujours la v3, déjà démarrée ; retour en 1 à 2 min, sans redéploiement ni interruption. Puis corriger la v4 et la republier dans `staging`. Condition : ne rien publier dans `staging` entre la mise en production et la décision de retour arrière.
- **c.** Basic n'offre ni emplacements ni mise à l'échelle automatique (seulement 1 à 3 instances fixées à la main). Surcoût : 2 instances S1 en permanence = 2 fois le prix horaire d'une instance S1 (jusqu'à 4 fois pendant les pics) ; l'emplacement `staging` n'ajoute rien, il s'exécute sur les mêmes instances. Tarifs `[À VÉRIFIER]` calculatrice de prix Azure.

### Pourquoi
- **`--configuration-source`** : l'emplacement reprend la pile, la commande de démarrage, le contrôle d'intégrité et les paramètres d'application de la production ; `ARVEO_ENV` est ensuite redéfini explicitement, car la copie des paramètres d'emplacement n'est pas garantie `[À VÉRIFIER]`.
- **Publication dans `staging` seulement** : la recette se fait sur l'adresse de l'emplacement, sur les mêmes instances et avec la même configuration que la production, sauf les paramètres d'emplacement.
- **Échange** : la plateforme applique à la source les paramètres d'emplacement de la cible, attend que ses instances répondent (préchauffage), puis permute le routage ; d'où l'absence d'erreur dans la boucle de contrôle.
- **Mise à l'échelle automatique sur le PLAN** : c'est le plan qui porte les instances ; `CpuPercentage` est une métrique du plan (moyenne de ses instances). Règle de réduction obligatoire, seuils éloignés (70 / 30) et durées différentes (10 / 15 min) pour éviter l'effet yo-yo, comme au module 7.
- **Minimum 2** : la mise à l'échelle automatique porte immédiatement le plan de 1 à 2 instances (capacité actuelle hors de l'intervalle autorisé).
- **Deux identifiants dans les 20 requêtes** : preuve que l'équilibrage interne d'App Service répartit les requêtes, possible parce que l'affinité ARR a été désactivée au lab 08.2 (et parce que `curl` ne renvoie aucun cookie).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| La production affiche `recette` après l'échange | `ARVEO_ENV` défini avec `--settings` (non marqué) dans un des emplacements | Le redéfinir avec `--slot-settings` dans les deux emplacements, puis échanger de nouveau |
| `staging` affiche `production` | Paramètre copié par `--configuration-source` et non redéfini | Étape 2 : `--slot staging --slot-settings ARVEO_ENV=recette` |
| Échange en échec (`warm-up` ou délai dépassé) `[À VÉRIFIER]` libellé | `staging` ne démarre pas (archive mal construite, commande de démarrage absente) | `curl https://$STG/` ; `az webapp log tail --slot staging` ; corriger puis relancer l'échange |
| `echange.log` vide | Boucle lancée dans une autre session Cloud Shell, ou `HOST` vide | `echo $HOST` ; relancer le bloc de variables |
| `No metric definitions` à la création de la règle | `--resource` vise l'application au lieu du plan | Utiliser l'ID du plan (`az appservice plan show --query id`) |
| Une seule instance dans les 20 requêtes | Mise à l'échelle pas encore appliquée, ou affinité ARR encore active | `az appservice plan show --query sku.capacity` (attendre `2`) ; `az webapp show --query clientAffinityEnabled` |

### Variantes acceptables
- Échange en deux phases (aperçu) : `az webapp deployment slot swap ... --action preview`, contrôle de `staging` avec la configuration de production, puis `--action swap` (ou `--action reset` pour annuler).
- Profil horaire supplémentaire : 3 instances de 7 h 45 à 10 h 15 en semaine (`az monitor autoscale profile create --recurrence week mon tue wed thu fri --start 07:45 --end 10:15 --timezone "Romance Standard Time"`) `[À VÉRIFIER]` options ; utile quand le pic est prévisible.
- Déploiement de la v4 depuis un pipeline GitHub Actions (action `azure/webapps-deploy`, paramètre `slot-name: staging`) : cible du projet, hors du temps du lab.

---

## Lab 08.4 ⭐⭐ — Construire l'image de l'API dans ACR et l'exécuter sur ACI

### Solution
Étape 1 (lecture) : image de base Azure Linux nginx de MCR (paramétrable par `IMAGE_BASE`), écoute sur 8080, journaux d'accès sur la sortie standard et d'erreur sur la sortie d'erreur (lisibles par `az container logs`), réponse JSON fixe complétée par le nom d'hôte du conteneur (`$hostname` de nginx), route `/health` en texte.

```bash
# 2. Registre Basic, compte administrateur désactivé
az acr check-name -n "$ACR" --query nameAvailable -o tsv
az acr create -g "$RG_APP" -n "$ACR" -l "$LOC" --sku Basic --admin-enabled false --tags $TAGS \
  --query "{Nom:name, Serveur:loginServer, Niveau:sku.name, Admin:adminUserEnabled}" -o table
```
Résultat attendu :
```
true
Nom              Serveur                     Niveau    Admin
---------------  --------------------------  --------  -------
crarveost072610  crarveost072610.azurecr.io  Basic     False
```

```bash
# 3. Construction (énoncé), puis 4. lecture du registre
az acr repository list -n "$ACR" -o tsv
az acr repository show-tags -n "$ACR" --repository arveo/api-suivi-colis -o tsv
az acr repository show -n "$ACR" --image arveo/api-suivi-colis:2.0 --query digest -o tsv
```
Résultat attendu (empreinte variable) :
```
arveo/api-suivi-colis
2.0
sha256:6f1c0b9e4a7d2c3b8e5f9a0d1c2b3a4f5e6d7c8b9a0f1e2d3c4b5a6f7e8d9c0b
```

```bash
# 5. Identité affectée par l'utilisateur, rôle AcrPull sur le registre seul
ID=$(az identity create -g "$RG_APP" -n "id-${ST}-aci" -l "$LOC" --tags $TAGS --query id -o tsv)
PID=$(az identity show --ids "$ID" --query principalId -o tsv)
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)
az role assignment create --assignee-object-id "$PID" --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID" --query roleDefinitionName -o tsv
sleep 60   # propagation de l'attribution

# 6. Conteneur public
az container create -g "$RG_APP" -n "aci-${ST}-api" -l "$LOC" --os-type Linux \
  --image "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
  --acr-identity "$ID" --assign-identity "$ID" --cpu 0.5 --memory 0.5 \
  --ports 8080 --ip-address Public --dns-name-label "arveo-${ST}-api-${SES}" \
  --restart-policy Always --tags $TAGS \
  --query "{Etat:provisioningState, FQDN:ipAddress.fqdn}" -o table
```
Résultat attendu (1 à 2 min) :
```
AcrPull
Etat       FQDN
---------  ----------------------------------------------------
Succeeded  arveo-st07-api-2610.francecentral.azurecontainer.io
```

```bash
# 7. Tests, état, journaux
FQDN=$(az container show -g "$RG_APP" -n "aci-${ST}-api" --query ipAddress.fqdn -o tsv)
for i in 1 2 3; do curl -s "http://${FQDN}:8080/"; done; curl -s "http://${FQDN}:8080/health"
az container show -g "$RG_APP" -n "aci-${ST}-api" \
  --query "{Etat:instanceView.state, Redemarrages:containers[0].instanceView.restartCount}" -o table
az container logs -g "$RG_APP" -n "aci-${ST}-api" | tail -n 2
```
Résultat attendu (nom d'hôte, adresse source et horodatages variables) :
```
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOTE>"}
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOTE>"}
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOTE>"}
OK
Etat     Redemarrages
-------  --------------
Running  0
<IP_CLOUD_SHELL> - - [08/Oct/2026:08:21:05 +0000] "GET / HTTP/1.1" 200 96 "-" "curl/8.5.0"
<IP_CLOUD_SHELL> - - [08/Oct/2026:08:21:06 +0000] "GET /health HTTP/1.1" 200 3 "-" "curl/8.5.0"
```

Réponses de l'étape 9 :
- **a.** Le compte administrateur est un identifiant unique et partagé (nom + mot de passe), avec les droits de lecture ET d'écriture sur tout le registre : secret à stocker, à faire tourner, et non traçable par personne ou par service. L'identité managée n'a aucun secret à gérer, `AcrPull` limite au tirage (moindre privilège) et chaque accès est authentifié par Entra ID. Affectée par l'utilisateur, car l'identité doit exister et être autorisée AVANT la création du groupe de conteneurs, qui tire l'image dès son démarrage (identité affectée par le système non prise en charge pour ce tirage).
- **b.** ACI facture à la seconde les vCPU et la mémoire DEMANDÉS (0,5 vCPU, 0,5 Go), du tirage de l'image jusqu'à l'arrêt ou la suppression du groupe, que le conteneur reçoive des requêtes ou non : pas de mise à l'échelle à zéro. Le plan S1 de l'exercice 08.3 facture 2 instances à l'heure en permanence. Pour un conteneur de recette ou un traitement ponctuel, ACI coûte bien moins ; pour un service permanent, comparer avec Container Apps (mise à l'échelle à zéro). Tarifs `[À VÉRIFIER]` calculatrice de prix Azure.
- **c.** Non : une seule instance (aucune haute disponibilité, aucune zone), aucune mise à l'échelle automatique, aucun équilibreur ni TLS (HTTP en clair sur 8080), exposition publique, adresse non garantie au redémarrage, aucune mise à jour progressive. Azure Container Apps répond à ces limites (entrée HTTPS gérée, réplicas multiples, révisions, mise à l'échelle, environnement intégré au VNet) ; AKS si Arvéo veut piloter Kubernetes.

### Pourquoi
- **ACR Tasks** (`az acr build`) : Cloud Shell n'a pas de démon Docker ; le contexte (dossier `api`) est envoyé au registre, construit dans Azure et poussé directement, sans transiter par un poste.
- **Image de base MCR** : les registres Microsoft ne sont pas soumis aux limites de téléchargement anonyme de Docker Hub, fréquentes sur les adresses partagées d'ACR Tasks.
- **Étiquette `2.0` + empreinte** : l'étiquette est mobile (elle peut être réattribuée à une autre image), l'empreinte `sha256` désigne une image précise et immuable ; en production, déployer par empreinte ou par étiquettes jamais réutilisées.
- **Rôle au scope du registre** : `AcrPull` sur `rg-st<NN>-app` donnerait accès à tous les registres présents et futurs du groupe ; le scope le plus étroit suffit.
- **`sleep 60`** : une attribution de rôle met jusqu'à quelques minutes à être prise en compte ; un tirage immédiat échoue (`unauthorized`).
- **`--restart-policy Always`** : service permanent ; un traitement ponctuel utiliserait `OnFailure` ou `Never`, et le groupe passerait à l'état `Succeeded` / `Terminated` à la fin du traitement.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `az acr build` : `TasksOperationsNotAllowed` `[À VÉRIFIER]` libellé | ACR Tasks non autorisé sur l'abonnement (certaines offres d'essai) | Importer l'image préparée par la formatrice : `az acr import -n $ACR --source crarveoformation.azurecr.io/arveo/api-suivi-colis:2.0 --image arveo/api-suivi-colis:2.0` (rôle `AcrPull` du stagiaire sur ce registre, voir guide formateur) |
| Construction : `manifest unknown` ou `toomanyrequests` sur l'image de base | Image de base indisponible ou limitée | Relancer avec `--build-arg IMAGE_BASE=<AUTRE_IMAGE_NGINX>` (validée au J-1) |
| `az container create` : `InaccessibleImage` ou `unauthorized` | Rôle pas encore propagé, ou identité absente de `--acr-identity` | Attendre 1 à 2 min ; vérifier `az role assignment list --assignee $PID --all -o table` ; relancer |
| `DnsNameLabelAlreadyInUse` `[À VÉRIFIER]` libellé | Étiquette DNS déjà prise dans la région | Vérifier `NN` et `SES` ; sinon ajouter une lettre à l'étiquette |
| `curl` sans réponse sur le FQDN | Port 8080 absent de `--ports`, ou conteneur en redémarrage en boucle | `az container show --query "containers[0].instanceView.events[].message"` ; `az container logs` |
| `MissingSubscriptionRegistration` | Fournisseur `Microsoft.ContainerInstance` non enregistré | Formatrice : `az provider register -n Microsoft.ContainerInstance` |

### Variantes acceptables
- Déploiement par le fichier `scripts/catch-up/module-08/aci.bicep` (paramètres `acrLoginServer`, `identityId`) : même résultat, rejouable.
- Création du registre et de l'identité en Bicep (`main.bicep` du rattrapage, ressources `acr`, `idAci`, `acrPull`).
- Étiquette immuable supplémentaire générée par la tâche : `-t arveo/api-suivi-colis:{{.Run.ID}}` (identifiant de l'exécution).

---

## Défi 08.5 ⭐⭐⭐ — Portail PaaS et API conteneurisée privée

### Solution
```bash
VNET="vnet-${ST}-spoke-app"
VNET_ID=$(az network vnet show -g "$RG_SPOKE" -n "$VNET" --query id -o tsv)
ID=$(az identity show -g "$RG_APP" -n "id-${ST}-aci" --query id -o tsv)

# NSG de snet-aci : 8080 depuis snet-appsvc uniquement
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-aci" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-aci" -n Allow-8080-From-AppSvc \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "10.${OCT}.6.0/26" --destination-port-ranges 8080 -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-aci" -n Deny-VNet-Inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-port-ranges '*' -o none

# Sous-réseaux délégués dans la réserve 10.OCT.6.0/23
az network vnet subnet create -g "$RG_SPOKE" --vnet-name "$VNET" -n snet-appsvc \
  --address-prefixes "10.${OCT}.6.0/26" --delegations Microsoft.Web/serverFarms -o none
az network vnet subnet create -g "$RG_SPOKE" --vnet-name "$VNET" -n snet-aci \
  --address-prefixes "10.${OCT}.6.64/27" \
  --delegations Microsoft.ContainerInstance/containerGroups \
  --nat-gateway "ng-${ST}-app" --network-security-group "nsg-${ST}-aci" -o none
SNET_ACI="${VNET_ID}/subnets/snet-aci"
SNET_APPSVC="${VNET_ID}/subnets/snet-appsvc"

# Conteneur privé
az container create -g "$RG_APP" -n "aci-${ST}-api-priv" -l "$LOC" --os-type Linux \
  --image "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
  --acr-identity "$ID" --assign-identity "$ID" --cpu 0.5 --memory 0.5 --ports 8080 \
  --vnet "$VNET_ID" --subnet "$SNET_ACI" --restart-policy Always --tags $TAGS \
  --query "{Type:ipAddress.type, IP:ipAddress.ip}" -o table
IP_PRIV=$(az container show -g "$RG_APP" -n "aci-${ST}-api-priv" --query ipAddress.ip -o tsv)

# Portail : intégration au réseau virtuel + API_URL (paramètre d'emplacement de la production)
az webapp vnet-integration add -g "$RG_APP" -n "$APP" --vnet "$VNET_ID" --subnet "$SNET_APPSVC" -o none
az webapp config appsettings set -g "$RG_APP" -n "$APP" \
  --slot-settings "API_URL=http://${IP_PRIV}:8080/" -o none
```
Résultat attendu (2 à 3 min pour le conteneur ; adresse variable dans `10.7.6.64/27`) :
```
Type     IP
-------  ---------
Private  10.7.6.68
```

Tests de l'étape 2 :
```bash
sleep 30   # redémarrage de l'application après la modification des paramètres
curl -s "https://${HOST}/api/"                                                     # a
az container show -g "$RG_APP" -n "aci-${ST}-api-priv" \
  --query "[ipAddress.type, ipAddress.ip, ipAddress.fqdn]" -o tsv                  # b
az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-web01" --command-id RunShellScript \
  --scripts "timeout 3 bash -c '</dev/tcp/${IP_PRIV}/8080' && echo OUVERT || echo REFUSE" \
  --query "value[0].message" -o tsv | grep -E 'OUVERT|REFUSE'                      # c
STG=$(az webapp deployment slot list -g "$RG_APP" -n "$APP" --query "[0].defaultHostName" -o tsv)
curl -s "https://${STG}/api/"                                                      # d
```
Résultat attendu :
```
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOTE>"}
Private
10.7.6.68
None
REFUSE
{"erreur":"API_URL non configuree"}
```
(`None` ou ligne vide pour le FQDN selon la version de la CLI.)

Réponses de l'étape 3 :
- **a.** `snet-aci` est un sous-réseau créé en 2026 : aucun accès sortant implicite (retrait de l'accès sortant par défaut, module 7). Le groupe de conteneurs tire son image depuis le point de terminaison PUBLIC du registre : sans passerelle NAT, le tirage échoue et le groupe reste en attente puis en échec. Alternative sans sortie Internet : private endpoint du registre (niveau Premium) dans un autre sous-réseau, avec zone DNS privée `privatelink.azurecr.io`.
- **b.** L'adresse privée d'un groupe ACI n'est pas garantie au redémarrage ou à la recréation : `API_URL` pointerait vers une adresse obsolète et `/api/` répondrait `502`. Parades : enregistrement A dans une zone DNS privée liée au spoke, mis à jour à chaque déploiement (et `API_URL` par nom) ; ou Azure Container Apps dans un environnement interne intégré au VNet, qui fournit un nom stable et un équilibrage entre réplicas.
- **c.** L'intégration au réseau virtuel ne concerne que le trafic SORTANT de l'application. Le portail reste joignable publiquement sur `*.azurewebsites.net`. Pour le rendre privé : private endpoint de l'application dans un sous-réseau (accès public désactivé), clients via VPN ou ExpressRoute, ou publication par Application Gateway / Front Door avec WAF devant le private endpoint.

### Pourquoi
- **Deux sous-réseaux distincts** : un sous-réseau délégué n'accueille que le service auquel il est délégué ; App Service et ACI ne peuvent pas partager le même.
- **Tailles** : `/26` pour l'intégration d'App Service (une adresse par instance du plan, marge pour la mise à l'échelle et les mises à niveau `[À VÉRIFIER]` taille minimale recommandée) ; `/27` pour quelques groupes de conteneurs. Les deux tiennent dans la réserve `10.<OCT>.6.0/23` prévue au module 4.
- **NSG en refus explicite du VNet** : la règle par défaut `AllowVnetInBound` autoriserait `snet-web` et le hub ; la règle 4000 ne laisse passer que `snet-appsvc` (règle 100), d'où le test c.
- **`API_URL` en paramètre d'emplacement** : seule la production est intégrée au VNet (l'intégration est propre à chaque emplacement) ; marquée, l'adresse reste en production lors des prochains échanges, d'où le test d.
- **VNet non redéclaré** : modifier `vnet-st<NN>-spoke-app` en Bicep sans y décrire tous les sous-réseaux existants les supprimerait ou échouerait (mode incrémental, propriété `subnets` remplacée) ; les sous-réseaux sont ajoutés un par un.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `SubnetMissingRequiredDelegation` | Délégation oubliée | `az network vnet subnet update --delegations <SERVICE>` (sous-réseau vide) |
| Conteneur privé `Waiting` puis `Failed`, événement de tirage en erreur | Pas de passerelle NAT sur `snet-aci` | `az network vnet subnet update ... -n snet-aci --nat-gateway ng-st<NN>-app`, puis recréer le conteneur |
| `/api/` renvoie `502` `API injoignable` | NSG : source `snet-web` au lieu de `snet-appsvc` ; intégration absente ; mauvaise adresse | `az webapp vnet-integration list` ; `az network nsg rule list -g rg-st<NN>-spoke --nsg-name nsg-st<NN>-aci -o table` ; comparer `API_URL` et `ipAddress.ip` |
| `/api/` renvoie `503` en production | `API_URL` défini dans `staging` ou non défini | `az webapp config appsettings list --query "[?name=='API_URL']"` sur la production |
| `vnet-integration add` refusé | Sous-réseau non délégué, déjà utilisé, ou plan Free | Sous-réseau vide délégué à `Microsoft.Web/serverFarms` ; plan Basic ou supérieur |
| `az container create` : options IP publique et sous-réseau incompatibles | `--ip-address Public` ou `--dns-name-label` ajoutés en mode VNet | Retirer ces deux options |

### Variantes acceptables
- Conteneur privé par `scripts/catch-up/module-08/aci.bicep` avec `prive=true subnetId=<ID_SNET_ACI>` ; réseau en CLI.
- `API_URL` par nom : zone DNS privée `api.arveo.internal` (module 4) liée au spoke app, enregistrement A vers l'adresse du conteneur. Le portail résout par le DNS du VNet grâce à l'intégration `[À VÉRIFIER]` routage DNS de l'intégration.
- Azure Container Apps (environnement interne dans un sous-réseau dédié) à la place d'ACI : nom stable, plusieurs réplicas ; plus de temps de mise en place.

---

## Bonus

1. **Azure Container Apps** :
   ```bash
   ID=$(az identity show -g "$RG_APP" -n "id-${ST}-aci" --query id -o tsv)
   az containerapp env create -g "$RG_APP" -n "cae-${ST}-arveo" -l "$LOC" \
     --logs-destination none --tags $TAGS -o none
   az containerapp create -g "$RG_APP" -n "ca-${ST}-api" --environment "cae-${ST}-arveo" \
     --image "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
     --registry-server "${ACR}.azurecr.io" --registry-identity "$ID" --user-assigned "$ID" \
     --ingress external --target-port 8080 --min-replicas 0 --max-replicas 3 --tags $TAGS \
     --query properties.configuration.ingress.fqdn -o tsv
   curl -s "https://<FQDN>/"
   az containerapp replica list -g "$RG_APP" -n "ca-${ST}-api" --query "length(@)" -o tsv
   ```
   Après 5 à 10 min sans requête, le nombre de réplicas passe à `0` ; la requête suivante redémarre un réplica (démarrage à froid de quelques secondes). Entrée HTTPS fournie, contrairement à ACI.
2. **Test en production** :
   ```bash
   az webapp traffic-routing set -g "$RG_APP" -n "$APP" --distribution staging=20 -o none
   for i in $(seq 30); do curl -s "https://${HOST}/" | grep -o 'client v[0-9]'; done | sort | uniq -c
   az webapp traffic-routing clear -g "$RG_APP" -n "$APP"
   ```
   Environ 24 réponses de la production et 6 de `staging` (tirage aléatoire par requête, faute de cookie conservé). Un navigateur reste sur sa version grâce au cookie `x-ms-routing-name`.
3. **Restrictions d'accès** :
   ```bash
   IP=$(curl -s https://api.ipify.org)
   az webapp config access-restriction add -g "$RG_APP" -n "$APP" --slot staging \
     --rule-name CloudShell --action Allow --ip-address "${IP}/32" --priority 100 -o none
   az webapp config access-restriction set -g "$RG_APP" -n "$APP" --slot staging \
     --use-same-restrictions-for-scm-site true -o none
   az webapp config access-restriction show -g "$RG_APP" -n "$APP" --slot staging -o json \
     --query "ipSecurityRestrictions[].{Nom:name, Action:action, IP:ipAddress}"
   ```
   Dès qu'une règle Allow existe, un refus implicite s'applique au reste (`403` depuis un navigateur extérieur). Restrictions propres à l'emplacement : non échangées.
4. **Conteneur sur App Service** :
   ```bash
   CLIENT_ID=$(az identity show -g "$RG_APP" -n "id-${ST}-aci" --query clientId -o tsv)
   az webapp create -g "$RG_APP" -p "$PLAN" -n "app-${ST}-api-${SES}" \
     --container-image-name "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
     --assign-identity "$ID" --acr-use-identity --acr-identity "$ID" --tags $TAGS -o none
   az webapp config appsettings set -g "$RG_APP" -n "app-${ST}-api-${SES}" \
     --settings WEBSITES_PORT=8080 -o none
   curl -s "https://app-${ST}-api-${SES}.azurewebsites.net/"
   ```
   Options de `az webapp create` pour un conteneur et une identité affectée par l'utilisateur `[À VÉRIFIER]` selon la version de la CLI ; équivalent par configuration : `acrUseManagedIdentityCreds=true` et `acrUserManagedIdentityID=$CLIENT_ID` (`az webapp config set --generic-configurations`). L'application partage les instances du plan (aucun coût supplémentaire), bénéficie des emplacements et de la mise à l'échelle du plan, mais ne descend jamais à zéro.

---

## QCM — Réponses
1. **C** — Les emplacements de déploiement existent à partir du niveau Standard (5), puis Premium et Isolated (20).
2. **B** — Le plan est l'unité de facturation : ses instances sont facturées à l'heure, applications arrêtées ou non.
3. **A** — Changer de niveau ou de taille modifie la puissance de chaque instance : mise à l'échelle verticale.
4. **C** — Les paramètres d'emplacement restent attachés à leur emplacement ; le code et les paramètres non marqués sont échangés.
5. **B** — Sans affinité ARR, aucun cookie ne colle un client à une instance : chaque requête peut aller sur toutes les instances.
6. **B** — `az acr build` envoie le contexte à ACR Tasks, qui construit et pousse l'image dans Azure.
7. **B** — ACI tire une image d'ACR avec une identité affectée par l'utilisateur ; `AcrPull` suffit (le système n'est pas pris en charge).
8. **B** — ACI facture à la seconde et s'arrête avec le traitement grâce à la stratégie `Never` ou `OnFailure`.
9. **A** — Container Apps met à l'échelle par événements (KEDA) jusqu'à zéro réplica, sans exposer Kubernetes.
10. **B** — L'intégration au réseau virtuel ne concerne que le trafic sortant ; l'accès entrant privé passe par un private endpoint.

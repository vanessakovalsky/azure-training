# Module 08 — Exercices

Fil rouge : **le portail client et l'API de suivi des colis passent en PaaS**. Au module 7, Arvéo a construit le portail sur deux VMs et l'API sur un VMSS : chaque correctif d'OS, chaque mise à jour de nginx reste à sa charge. La DSI teste ici l'alternative managée : le portail est republié sur App Service (version v3, puis v4 mise en production par échange d'emplacements, plan mis à l'échelle automatiquement), et l'API est empaquetée en image de conteneur, construite dans Azure Container Registry et exécutée sur Azure Container Instances. Le défi relie les deux en privé, sans exposer l'API sur Internet. Les VMs du module 7 ne sont pas modifiées : le module 9 les sauvegarde.

| Ressource | Nom (stagiaire 07, session `2610`) | Groupe | Lab |
|---|---|---|---|
| Plan App Service | `asp-st07-portail` (Linux, Standard S1) | `rg-st07-app` | 08.2 |
| Application et emplacement | `app-st07-portail-2610`, emplacement `staging` | `rg-st07-app` | 08.2, 08.3 |
| Mise à l'échelle automatique | `as-st07-portail` (2 à 4 instances) | `rg-st07-app` | 08.3 |
| Registre de conteneurs | `crarveost072610` (Basic), image `arveo/api-suivi-colis:2.0` | `rg-st07-app` | 08.4 |
| Identité et conteneur public | `id-st07-aci` (rôle `AcrPull`), `aci-st07-api` | `rg-st07-app` | 08.4 |
| API privée (défi) | `snet-appsvc` `10.7.6.0/26`, `snet-aci` `10.7.6.64/27`, `nsg-st07-aci`, `aci-st07-api-priv` | `rg-st07-spoke` / `rg-st07-app` | 08.5 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<SES>` = code de session à 4 caractères du module 6 (ex. `2610`) : rend uniques les noms publics (application, registre, étiquette DNS)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
SES=<SES>
OCT=$((10#$NN))
ST="st${NN}"
RG_APP="rg-${ST}-app"
RG_SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
PLAN="asp-${ST}-portail"
APP="app-${ST}-portail-${SES}"
ACR="crarveo${ST}${SES}"
HOST=$(az webapp show -g "$RG_APP" -n "$APP" --query defaultHostName -o tsv 2>/dev/null)
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
echo "$ST $PLAN $APP $ACR ${HOST:-application-absente}"
```
Résultat attendu (stagiaire 07, session `2610` ; avant le lab 08.2, l'application n'existe pas encore) :
```
st07 asp-st07-portail app-st07-portail-2610 crarveost072610 application-absente
```
Après le lab 08.2, la dernière valeur devient `app-st07-portail-2610.azurewebsites.net`.

**État de départ** : fin du module 7. `web01` et `web02` redémarrées à 09:00 par `lancer-sauvegarde.sh` (module 9), portail v2 servi par `lbe-st<NN>-web` ; instances de l'API `vmss-st<NN>-api` désallouées (non utilisées ici) ; passerelle NAT `ng-st<NN>-app` sur `snet-web` et `snet-app` ; réserve d'adressage `10.<OCT>.6.0/23` libre dans `vnet-st<NN>-spoke-app` (module 4). Le module 8 ne modifie aucune ressource des modules précédents, à l'exception de deux sous-réseaux ajoutés dans la réserve par le défi 08.5. Stagiaire en retard : `./scripts/catch-up/module-08/deploy.sh <NN> <SES>` (8 à 15 min) produit l'état de FIN du module 8 (`--defi` en troisième argument : solution du défi incluse).

---

## Exercice 08.1 ⭐ — Choisir le plan App Service (en binôme)
**Durée** : 4 min · **Objectif** : choisir un niveau de plan App Service adapté à un besoin et justifier le choix (objectif 9)
**Contexte** : avant de migrer le portail, la DSI d'Arvéo recense quatre applications web candidates à App Service. Elle attend, pour chacune, le niveau de plan le moins cher qui couvre TOUTES les exigences.
**Prérequis** : slides de la séquence S8.1.

| N° | Application | Exigences |
|---|---|---|
| 1 | Maquette du nouvel intranet | Démonstration interne de 2 semaines, aucune exigence de disponibilité ni de domaine |
| 2 | Portail client (cible 2026) | Mise en production sans interruption, mise à l'échelle automatique selon le CPU, appels sortants vers un VNet |
| 3 | Portail client (cible 2027) | Exigences de l'application 2, plus résistance à la perte d'une zone de disponibilité |
| 4 | Extranet des douanes | Isolement réseau complet, environnement dédié à Arvéo (aucune infrastructure partagée) |

### Étapes
1. Pour chaque application, indiquer le niveau (et une taille) en citant l'exigence qui le justifie.
2. Pour l'application 2, préciser le nombre minimal d'instances recommandé et pourquoi.
3. Répondre : les applications 2 et 3 peuvent-elles partager un plan avec la maquette 1 ? Quel risque ?

### Critères de réussite
- [ ] Un niveau par application, chacun justifié par une exigence du tableau.
- [ ] L'application 3 utilise un niveau compatible avec la redondance de zone, avec son nombre minimal d'instances.
- [ ] Le partage d'un plan est discuté (coût mutualisé, ressources partagées, fonctions communes au plan).

---

## Lab 08.2 ⭐ — Publier le portail v3 sur App Service (guidé)
**Durée** : 15 min · **Objectif** : publier le portail Arvéo sur App Service, sécurisé et configuré par paramètres d'application (objectif 9)
**Contexte** : la DSI veut comparer le portail sur VMs (module 7) avec une version managée : même page, mêmes routes `/health` et `/api/`, mais plus aucun système d'exploitation à maintenir. La version v3 du portail est une petite application Node.js sans dépendance, fournie dans `scripts/labs/module-08/portail/`.
**Prérequis** : bloc de variables exécuté ; fournisseur `Microsoft.Web` enregistré (formatrice).

### Étapes
1. Vérifier les versions de Node.js proposées par App Service Linux :
   ```bash
   az webapp list-runtimes --os linux -o tsv | grep -i '^node'
   ```
   Résultat attendu (liste variable `[À VÉRIFIER]`) :
   ```
   NODE:24-lts
   NODE:22-lts
   NODE:20-lts
   ```
2. Créer le plan Linux Standard S1 :
   ```bash
   az appservice plan create -g "$RG_APP" -n "$PLAN" -l "$LOC" --is-linux --sku S1 --tags $TAGS \
     --query "{Nom:name, Niveau:sku.tier, Taille:sku.name, Instances:sku.capacity}" -o table
   ```
   Résultat attendu (30 s à 1 min) :
   ```
   Nom               Niveau    Taille    Instances
   ----------------  --------  --------  -----------
   asp-st07-portail  Standard  S1        1
   ```
3. Créer l'application dans ce plan :
   ```bash
   az webapp create -g "$RG_APP" -p "$PLAN" -n "$APP" --runtime "NODE:22-lts" --tags $TAGS \
     --query "{Nom:name, Hote:defaultHostName, Etat:state}" -o table
   HOST=$(az webapp show -g "$RG_APP" -n "$APP" --query defaultHostName -o tsv)
   ```
   Résultat attendu :
   ```
   Nom                    Hote                                     Etat
   ---------------------  ---------------------------------------  -------
   app-st07-portail-2610  app-st07-portail-2610.azurewebsites.net  Running
   ```
4. Sécuriser et configurer l'application : HTTPS seul, affinité ARR désactivée, TLS 1.2 minimum, FTP désactivé, Always On, commande de démarrage, contrôle d'intégrité, paramètres d'application :
   ```bash
   az webapp update -g "$RG_APP" -n "$APP" --https-only true --client-affinity-enabled false -o none
   az webapp config set -g "$RG_APP" -n "$APP" \
     --startup-file "node server.js" --min-tls-version 1.2 --ftps-state Disabled \
     --always-on true --generic-configurations '{"healthCheckPath": "/health"}' -o none
   az webapp config appsettings set -g "$RG_APP" -n "$APP" \
     --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false \
     --slot-settings ARVEO_ENV=production -o none
   az webapp config show -g "$RG_APP" -n "$APP" -o table --query \
     "{Runtime:linuxFxVersion, Demarrage:appCommandLine, TLS:minTlsVersion, FTP:ftpsState, Sante:healthCheckPath}"
   az webapp config appsettings list -g "$RG_APP" -n "$APP" -o table \
     --query "[].{Nom:name, Valeur:value, Emplacement:slotSetting}"
   ```
   Résultat attendu :
   ```
   Runtime      Demarrage       TLS    FTP       Sante
   -----------  --------------  -----  --------  -------
   NODE|22-lts  node server.js  1.2    Disabled  /health
   Nom                             Valeur      Emplacement
   ------------------------------  ----------  -------------
   SCM_DO_BUILD_DURING_DEPLOYMENT  false       False
   ARVEO_ENV                       production  True
   ```
5. Empaqueter le portail v3, puis le publier par déploiement zip :
   ```bash
   ./scripts/labs/module-08/empaqueter-portail.sh v3
   az webapp deploy -g "$RG_APP" -n "$APP" --src-path ~/arveo-build/portail-v3.zip --type zip -o none
   ```
   Résultat attendu (déploiement : 1 à 2 min, aucune sortie) :
   ```
   /home/<UTILISATEUR>/arveo-build/portail-v3.zip
   server.js
   package.json
   ```
6. Tester la page, la sonde de santé, la redirection HTTP → HTTPS et la route `/api/` :
   ```bash
   curl -s "https://${HOST}/"; curl -s "https://${HOST}/health"
   curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "http://${HOST}/"
   curl -s "https://${HOST}/api/"
   ```
   Résultat attendu (identifiant d'instance variable) :
   ```
   <h1>Arveo - portail client v3</h1><p>App Service - production - instance 3f9c1a2b</p>
   OK
   301 https://app-st07-portail-2610.azurewebsites.net/
   {"erreur":"API_URL non configuree"}
   ```
   `503` sur `/api/` : normal à ce stade (aucune API configurée ; voir défi 08.5).
7. Activer les journaux du conteneur, redémarrer l'application et suivre son démarrage (60 s, puis arrêt automatique) :
   ```bash
   az webapp log config -g "$RG_APP" -n "$APP" --docker-container-logging filesystem -o none
   az webapp restart -g "$RG_APP" -n "$APP"
   timeout 60 az webapp log tail -g "$RG_APP" -n "$APP" | grep -m1 'ecoute'
   ```
   Résultat attendu (horodatage variable) :
   ```
   2026-10-08T07:41:12.512Z  Portail Arveo v3 (production) a l'ecoute sur le port 8080
   ```
8. **Portail** : ouvrir `app-st<NN>-portail-<SES>` :
   - **Vue d'ensemble** : plan, état, nom d'hôte par défaut ;
   - **Paramètres** › **Variables d'environnement** : `ARVEO_ENV` porte la mention « Paramètre d'emplacement » ;
   - **Outils de développement** › **Outils avancés** (Kudu) › **Environment** : relever `WEBSITE_INSTANCE_ID` et `PORT`.

### Critères de réussite
- [ ] `az webapp show -g rg-st<NN>-app -n app-st<NN>-portail-<SES> --query "[state, httpsOnly, clientAffinityEnabled]" -o tsv` affiche `Running`, `true`, `false`.
- [ ] `curl -s https://<HOST>/` affiche `portail client v3` et `production`.
- [ ] La requête HTTP renvoie `301` vers l'adresse HTTPS.
- [ ] `ARVEO_ENV` est un paramètre d'emplacement (`slotSetting` = `True`).

---

## Exercice 08.3 ⭐⭐ — Mise en production de la v4 par échange, mise à l'échelle automatique (semi-autonome)
**Durée** : 18 min · **Objectif** : mettre à jour le portail sans interruption grâce aux emplacements, puis configurer et prouver la mise à l'échelle automatique du plan (objectif 9)
**Contexte** : l'équipe web d'Arvéo livre la version v4 du portail. Règle de la DSI : toute version passe d'abord en recette sur l'adresse de l'emplacement `staging`, puis en production par échange, sans aucune requête client en erreur. Le plan doit tenir les pics du matin (8 h à 10 h) seul, avec au moins deux instances en permanence.
**Prérequis** : lab 08.2 terminé.

**Énoncé** :
1. Créer l'emplacement `staging` de l'application, en copiant la configuration de la production.
2. Dans `staging` uniquement, définir `ARVEO_ENV=recette` comme paramètre d'emplacement. Afficher les paramètres d'application des deux emplacements.
3. Empaqueter la v4 et la publier dans `staging` SEULEMENT. Vérifier : production = v3 / `production`, staging = v4 / `recette`.
4. Lancer la boucle de contrôle de la production (fournie), échanger `staging` avec la production, puis arrêter la boucle :
   ```bash
   ( for i in $(seq 120); do R=$(curl -s -w '|%{http_code}' "https://${HOST}/")
       echo "$(date +%T) ${R##*|} $(grep -o 'client v[0-9]' <<< "$R")"; sleep 1
     done > ~/arveo-build/echange.log ) &
   ```
   Après l'échange : `kill %1` (ou attendre 2 min), puis lire `~/arveo-build/echange.log`.
5. Vérifier : production = v4 / `production`, staging = v3 / `recette`.
6. Configurer la mise à l'échelle automatique `as-st<NN>-portail` du plan : 2 à 4 instances (2 par défaut) ; +1 si le CPU moyen dépasse 70 % sur 10 min ; −1 s'il passe sous 30 % sur 15 min.
7. Prouver les deux instances : liste des instances de l'application, puis 20 requêtes sur la production réparties sur deux identifiants d'instance.
8. Répondre par écrit :
   - a. Pourquoi `ARVEO_ENV` doit-il être un paramètre d'emplacement ? Que montrerait la production après l'échange sinon ?
   - b. La v4 présente un défaut découvert 10 min après la mise en production : procédure et durée du retour arrière ?
   - c. Pourquoi cet exercice est-il impossible sur un plan Basic B1 ? Quel est le surcoût du plan actuel par rapport à une seule instance S1 ?

**Indices** :
- Emplacement : `az webapp deployment slot create -g <GROUPE> -n <APPLICATION> --slot staging --configuration-source <APPLICATION>`.
- Paramètre d'emplacement : `az webapp config appsettings set ... --slot staging --slot-settings ARVEO_ENV=recette` ; lecture : `az webapp config appsettings list ... [--slot staging]`.
- Adresse de l'emplacement : `az webapp deployment slot list -g <GROUPE> -n <APPLICATION> --query "[].defaultHostName" -o tsv`.
- Publication : `az webapp deploy ... --slot staging --src-path <ZIP> --type zip`.
- Échange : `az webapp deployment slot swap ... --slot staging --target-slot production` (1 à 2 min).
- Mise à l'échelle : `az appservice plan show ... --query id -o tsv`, puis `az monitor autoscale create --resource <ID_PLAN>` et `az monitor autoscale rule create --condition "CpuPercentage > 70 avg 10m" --scale out 1`.
- Instances : `az webapp list-instances -g <GROUPE> -n <APPLICATION> --query "[].name" -o tsv` ; comptage : `for i in $(seq 20); do curl -s https://${HOST}/ | grep -o 'instance [0-9a-f]*'; done | sort | uniq -c`.

**Critères de réussite** :
- [ ] `curl -s https://<HOST>/` affiche `v4` et `production` ; l'adresse de `staging` affiche `v3` et `recette`.
- [ ] `~/arveo-build/echange.log` ne contient que des codes `200` et montre le passage de `client v3` à `client v4`.
- [ ] `az monitor autoscale show -g rg-st<NN>-app -n as-st<NN>-portail --query "profiles[0].[capacity.minimum, capacity.maximum, length(rules)]" -o tsv` affiche `2`, `4`, `2`.
- [ ] Les 20 requêtes de l'étape 7 sont servies par deux instances différentes.
- [ ] Les trois réponses de l'étape 8 sont rédigées.

---

## Lab 08.4 ⭐⭐ — Construire l'image de l'API dans ACR et l'exécuter sur ACI (semi-autonome)
**Durée** : 25 min (15 min avant la pause, 10 min après) · **Objectif** : construire une image dans Azure Container Registry et l'exécuter sur Azure Container Instances avec une identité managée (objectif 9)
**Contexte** : l'équipe de développement d'Arvéo empaquette l'API de suivi des colis en image de conteneur : même contrat JSON qu'au module 7 (`"service":"api-suivi-colis"`), mais plus de cloud-init ni de nginx à mettre à jour sur chaque VM. La sécurité impose un registre privé, aucun mot de passe de registre stocké, et l'accès en lecture SEULE de la plateforme d'exécution au registre. Ce premier déploiement sur ACI est une recette technique, publique et temporaire.
**Prérequis** : bloc de variables exécuté ; fournisseurs `Microsoft.ContainerRegistry` et `Microsoft.ContainerInstance` enregistrés (formatrice).

**Énoncé** :
1. Lire `scripts/labs/module-08/api/Dockerfile` et `nginx.conf` : image de base, port d'écoute, destination des journaux, contenu de la réponse.
2. Vérifier la disponibilité du nom `crarveost<NN><SES>`, puis créer le registre Basic, compte administrateur DÉSACTIVÉ.
3. Construire et pousser l'image avec ACR Tasks (fourni, 1 à 2 min) :
   ```bash
   az acr build -r "$ACR" -t arveo/api-suivi-colis:2.0 scripts/labs/module-08/api
   ```
   Résultat attendu (fin du journal ; identifiant d'exécution et durée variables) :
   ```
   Successfully pushed image: crarveost072610.azurecr.io/arveo/api-suivi-colis:2.0
   Run ID: ca1 was successful after 48s
   ```
4. Lister les référentiels et les étiquettes du registre, puis afficher l'empreinte (`digest`) de l'image `2.0`.
5. Créer l'identité managée affectée par l'utilisateur `id-st<NN>-aci` et lui attribuer le rôle `AcrPull` sur le registre SEULEMENT.
6. Créer le conteneur public `aci-st<NN>-api` : image `2.0` tirée avec `id-st<NN>-aci`, Linux, 0,5 vCPU, 0,5 Go, port 8080, étiquette DNS `arveo-st<NN>-api-<SES>`, redémarrage `Always`, tags Arvéo.
7. Tester : trois requêtes sur `http://<FQDN>:8080/` et une sur `/health` ; afficher l'état du groupe, le nombre de redémarrages et les journaux du conteneur.
8. **Portail** : registre › **Référentiels** (manifeste et empreinte) et **Services** › **Tâches** › **Exécutions** (`ca1`) ; conteneur › **Conteneurs** › **Événements** et **Journaux**.
9. Répondre par écrit :
   - a. Pourquoi une identité affectée par l'utilisateur avec `AcrPull`, plutôt que le compte administrateur du registre ?
   - b. Que facture ACI pour ce conteneur, et quand ? Comparer avec le plan App Service de l'exercice 08.3.
   - c. Ce conteneur conviendrait-il comme API de production d'Arvéo ? Citer trois limites et le service qui y répond.

**Indices** :
- Nom : `az acr check-name -n <NOM> --query nameAvailable -o tsv`.
- Registre : `az acr create -g <GROUPE> -n <NOM> -l <REGION> --sku Basic --admin-enabled false --tags ...`.
- Lecture : `az acr repository list -n <NOM> -o tsv` ; `az acr repository show-tags -n <NOM> --repository <REFERENTIEL> -o tsv` ; `az acr repository show -n <NOM> --image <REFERENTIEL>:<ETIQUETTE> --query digest -o tsv`.
- Identité : `az identity create ... --query id -o tsv` ; ID du principal : `--query principalId` ; attribution : `az role assignment create --assignee-object-id <ID_PRINCIPAL> --assignee-principal-type ServicePrincipal --role AcrPull --scope <ID_REGISTRE>`.
- Attendre 1 à 2 min après l'attribution du rôle (propagation) avant de créer le conteneur.
- Conteneur : `az container create --os-type Linux --image <SERVEUR>/<REFERENTIEL>:<ETIQUETTE> --acr-identity <ID_IDENTITE> --assign-identity <ID_IDENTITE> --cpu 0.5 --memory 0.5 --ports 8080 --dns-name-label <ETIQUETTE> --restart-policy Always`.
- FQDN : `az container show ... --query ipAddress.fqdn -o tsv` ; état : `--query "{Etat:instanceView.state, Redemarrages:containers[0].instanceView.restartCount}"` ; journaux : `az container logs -g <GROUPE> -n <NOM>`.

**Critères de réussite** :
- [ ] `az acr show -n crarveost<NN><SES> --query "[sku.name, adminUserEnabled]" -o tsv` affiche `Basic` et `false`.
- [ ] `az acr repository show-tags -n crarveost<NN><SES> --repository arveo/api-suivi-colis -o tsv` affiche `2.0`.
- [ ] L'unique attribution de rôle de `id-st<NN>-aci` est `AcrPull` sur le registre (`az role assignment list --assignee <ID_PRINCIPAL> --all -o table`).
- [ ] `curl -s http://arveo-st<NN>-api-<SES>.francecentral.azurecontainer.io:8080/` renvoie le JSON `"plateforme":"conteneur"`.
- [ ] Les journaux du conteneur montrent les requêtes de l'étape 7 ; les trois réponses de l'étape 9 sont rédigées.

---

## Défi 08.5 ⭐⭐⭐ — Portail PaaS et API conteneurisée privée (autonome)
**Durée** : 25 min (apprenants rapides, pendant le lab 08.4 et la démonstration AKS ; sinon solution commentée) · **Objectif** : relier une application App Service à un conteneur privé par l'intégration au réseau virtuel, sans exposer l'API sur Internet (objectif 9)
**Contexte** : la recette du lab 08.4 est concluante, mais le RSSI refuse toute API exposée sur Internet. Exigence : le portail PaaS appelle l'API conteneurisée par une adresse PRIVÉE du spoke applicatif ; seul le portail peut l'appeler, ni les VMs web du module 7 ni Internet. La version v4 du portail relaie déjà `/api/` vers l'adresse lue dans `API_URL`.

**Exigences** :

| Élément | Exigence |
|---|---|
| Sous-réseaux | Dans la réserve de `vnet-st<NN>-spoke-app` : `snet-appsvc` `10.<OCT>.6.0/26` délégué à `Microsoft.Web/serverFarms` ; `snet-aci` `10.<OCT>.6.64/27` délégué à `Microsoft.ContainerInstance/containerGroups` |
| Conteneur | `aci-st<NN>-api-priv`, image `2.0` tirée avec `id-st<NN>-aci`, IP PRIVÉE dans `snet-aci`, aucune IP publique, port 8080 |
| Sortie Internet de `snet-aci` | Par la passerelle NAT existante `ng-st<NN>-app` |
| Filtrage | `nsg-st<NN>-aci` sur `snet-aci` : 8080 depuis `snet-appsvc` uniquement, refus du reste du trafic VNet |
| Portail | Intégration au réseau virtuel dans `snet-appsvc` ; `API_URL` = `http://<IP_PRIVEE>:8080/`, paramètre d'emplacement de la production |

**Énoncé** :
1. Déployer l'ensemble, en CLI documentée ou en Bicep (`vnet-st<NN>-spoke-app` NON redéclaré).
2. Prouver le fonctionnement par quatre tests :
   - a. `https://<HOST>/api/` renvoie le JSON de l'API avec `"plateforme":"conteneur"` ;
   - b. le conteneur privé n'a aucune adresse publique ni FQDN ;
   - c. depuis `vm-st<NN>-web01` (`snet-web`), une connexion TCP au port 8080 du conteneur privé échoue ;
   - d. l'adresse de `staging` répond toujours `503` sur `/api/`.
3. Répondre par écrit :
   - a. Pourquoi la passerelle NAT est-elle indispensable sur `snet-aci` ? Que se passe-t-il sans elle ?
   - b. Le conteneur privé redémarre et change d'adresse : conséquence, et deux façons de s'en prémunir.
   - c. Pourquoi l'intégration au réseau virtuel ne suffit-elle pas à rendre le portail lui-même privé ? Quel mécanisme le ferait ?

**Critères de réussite** :
- [ ] `az network vnet subnet list -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-app --query "[?starts_with(name, 'snet-a')].[name, addressPrefix, delegations[0].serviceName]" -o tsv` affiche `snet-app` puis les deux nouveaux sous-réseaux avec leur délégation.
- [ ] `az container show -g rg-st<NN>-app -n aci-st<NN>-api-priv --query "[ipAddress.type, ipAddress.ip, ipAddress.fqdn]" -o tsv` affiche `Private`, une adresse `10.<OCT>.6.x` et aucun FQDN.
- [ ] `az webapp vnet-integration list -g rg-st<NN>-app -n app-st<NN>-portail-<SES> --query "[0].vnetResourceId" -o tsv` se termine par `snet-appsvc`.
- [ ] Les quatre tests donnent le résultat attendu ; les trois réponses de l'étape 3 sont rédigées.

---

## Bonus 🚀
1. **Azure Container Apps** : créer l'environnement `cae-st<NN>-arveo` (consommation, sans espace de travail : `--logs-destination none`) et l'application `ca-st<NN>-api` (image `2.0` tirée avec `id-st<NN>-aci`, entrée externe sur le port cible 8080, 0 à 3 réplicas). Appeler son FQDN, attendre 5 à 10 min sans trafic, puis vérifier le nombre de réplicas : `az containerapp replica list` `[À VÉRIFIER]` délai de mise à l'échelle à zéro. Fournisseur `Microsoft.App` requis.
2. **Test en production** : envoyer 20 % des visiteurs de la production vers `staging` (`az webapp traffic-routing set --distribution staging=20`), compter les versions servies sur 30 requêtes (cookie `x-ms-routing-name` non conservé par `curl`), puis remettre 100 % en production (`az webapp traffic-routing clear`).
3. **Restrictions d'accès** : limiter l'emplacement `staging` (site principal ET site SCM) à l'adresse IP publique de sortie de Cloud Shell (`curl -s https://api.ipify.org`), avec une règle de refus implicite pour le reste. Vérifier depuis un navigateur hors Cloud Shell : `403`. Indice : `az webapp config access-restriction add --slot staging --rule-name CloudShell --action Allow --ip-address <IP>/32 --priority 100` et `az webapp config access-restriction set --slot staging --use-same-restrictions-for-scm-site true` `[À VÉRIFIER]` options.
4. **Conteneur sur App Service** : créer dans le MÊME plan l'application `app-st<NN>-api-<SES>` exécutant l'image `2.0` du registre, tirée par l'identité `id-st<NN>-aci` (paramètres `acrUseManagedIdentityCreds` et `acrUserManagedIdentityID`, `WEBSITES_PORT=8080`) `[À VÉRIFIER]` options de `az webapp create` pour un conteneur. Comparer avec ACI : coût, mise à l'échelle, emplacements.

## Nettoyage
- **Fin du module (10:58)** :
  ```bash
  ./scripts/cleanup/module-08-paas.sh "$NN" "$SES"
  ```
  Le script supprime les conteneurs (`aci-st<NN>-api`, `aci-st<NN>-api-priv`), les ressources Container Apps du bonus 1, la mise à l'échelle automatique, les applications (emplacement `staging` compris) puis le plan App Service. Relançable sans risque.
- Conservés : registre `crarveost<NN><SES>` et son image, identité `id-st<NN>-aci`, sous-réseaux et NSG du défi (réutilisables par le rattrapage). Les modules 9 et 10 n'utilisent aucune ressource du module 8.
- **Fin de formation** :
  ```bash
  ./scripts/cleanup/module-08-paas.sh "$NN" "$SES" --purge
  ```
  Supprime en plus le registre, l'identité, `snet-appsvc`, `snet-aci` et `nsg-st<NN>-aci` (nouvel essai automatique tant qu'un sous-réseau est encore réservé par son service).
- Rattrapage complet du module : `./scripts/catch-up/module-08/deploy.sh <NN> <SES> [--defi]`.
- Coûts : plan App Service S1 à l'heure par instance (applications arrêtées comprises), conteneurs ACI à la seconde (vCPU + mémoire), registre Basic par jour + stockage, exécutions ACR Tasks à la seconde, Container Apps à la consommation `[À VÉRIFIER]` calculatrice de prix Azure.

# Module 08 — Exercises

Common thread: **the customer portal and the parcel-tracking API move to PaaS**. In module 7, Arvéo built the portal on two VMs and the API on a VMSS: every OS patch, every nginx update is still Arvéo's job. Here the IT department tests the managed alternative: the portal is republished on App Service (version v3, then v4 released by a slot swap, plan autoscaled), and the API is packaged as a container image, built in Azure Container Registry and run on Azure Container Instances. The challenge connects both privately, without exposing the API to the Internet. The module 7 VMs are not modified: module 9 backs them up.

Lab scripts are shared with the French-speaking groups: their comments, messages and the pages they produce are in French; resource names are kept as is.

| Resource | Name (trainee 07, session `2610`) | Group | Lab |
|---|---|---|---|
| App Service plan | `asp-st07-portail` (Linux, Standard S1) | `rg-st07-app` | 08.2 |
| App and slot | `app-st07-portail-2610`, slot `staging` | `rg-st07-app` | 08.2, 08.3 |
| Autoscale | `as-st07-portail` (2 to 4 instances) | `rg-st07-app` | 08.3 |
| Container registry | `crarveost072610` (Basic), image `arveo/api-suivi-colis:2.0` | `rg-st07-app` | 08.4 |
| Identity and public container | `id-st07-aci` (`AcrPull` role), `aci-st07-api` | `rg-st07-app` | 08.4 |
| Private API (challenge) | `snet-appsvc` `10.7.6.0/26`, `snet-aci` `10.7.6.64/27`, `nsg-st07-aci`, `aci-st07-api-priv` | `rg-st07-spoke` / `rg-st07-app` | 08.5 |

Variables used in every lab:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<SES>` = 4-character session code from module 6 (e.g. `2610`): makes public names unique (app, registry, DNS label)
- `<URL_DEPOT>` = URL of the course Git repository, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Variable block**: paste it again into Cloud Shell (Bash) at the start of EACH lab (session closed after 20 min of inactivity).
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
Expected output (trainee 07, session `2610`; before lab 08.2 the app does not exist yet):
```
st07 asp-st07-portail app-st07-portail-2610 crarveost072610 application-absente
```
After lab 08.2, the last value becomes `app-st07-portail-2610.azurewebsites.net`.

**Starting state**: end of module 7. `web01` and `web02` restarted at 09:00 by `lancer-sauvegarde.sh` (module 9), portal v2 served by `lbe-st<NN>-web`; `vmss-st<NN>-api` instances deallocated (not used here); NAT gateway `ng-st<NN>-app` on `snet-web` and `snet-app`; address reserve `10.<OCT>.6.0/23` free in `vnet-st<NN>-spoke-app` (module 4). Module 8 modifies no resource from previous modules, except two subnets added to the reserve by challenge 08.5. Trainee running late: `./scripts/catch-up/module-08/deploy.sh <NN> <SES>` (8 to 15 min) produces the END state of module 8 (`--defi` as third argument: challenge solution included).

---

## Exercise 08.1 ⭐ — Choosing the App Service plan (in pairs)
**Duration** : 4 min · **Objective** : choose an App Service plan tier that fits a need and justify the choice (objective 9)
**Context** : before migrating the portal, Arvéo's IT department lists four web apps that are candidates for App Service. For each one, it expects the cheapest plan tier that covers ALL requirements.
**Prerequisites** : slides of sequence S8.1.

| # | App | Requirements |
|---|---|---|
| 1 | New intranet mock-up | 2-week internal demo, no availability or domain requirement |
| 2 | Customer portal (2026 target) | No-downtime releases, CPU-based autoscale, outbound calls to a VNet |
| 3 | Customer portal (2027 target) | Requirements of app 2, plus resilience to the loss of an availability zone |
| 4 | Customs extranet | Full network isolation, environment dedicated to Arvéo (no shared infrastructure) |

### Steps
1. For each app, state the tier (and a size), quoting the requirement that justifies it.
2. For app 2, state the recommended minimum instance count and why.
3. Answer: can apps 2 and 3 share a plan with mock-up 1? What is the risk?

### Success criteria
- [ ] One tier per app, each justified by a requirement from the table.
- [ ] App 3 uses a tier compatible with zone redundancy, with its minimum instance count.
- [ ] Plan sharing is discussed (shared cost, shared resources, features common to the plan).

---

## Lab 08.2 ⭐ — Publishing portal v3 on App Service (guided)
**Duration** : 15 min · **Objective** : publish the Arvéo portal on App Service, secured and configured through app settings (objective 9)
**Context** : the IT department wants to compare the VM-based portal (module 7) with a managed version: same page, same `/health` and `/api/` routes, but no operating system to maintain anymore. Portal version v3 is a small Node.js app with no dependency, provided in `scripts/labs/module-08/portail/`.
**Prerequisites** : variable block run; `Microsoft.Web` provider registered (trainer).

### Steps
1. Check the Node.js versions offered by App Service on Linux:
   ```bash
   az webapp list-runtimes --os linux -o tsv | grep -i '^node'
   ```
   Expected output (list varies `[TO VERIFY]`):
   ```
   NODE:24-lts
   NODE:22-lts
   NODE:20-lts
   ```
2. Create the Linux Standard S1 plan:
   ```bash
   az appservice plan create -g "$RG_APP" -n "$PLAN" -l "$LOC" --is-linux --sku S1 --tags $TAGS \
     --query "{Name:name, Tier:sku.tier, Size:sku.name, Instances:sku.capacity}" -o table
   ```
   Expected output (30 s to 1 min):
   ```
   Name              Tier      Size    Instances
   ----------------  --------  ------  -----------
   asp-st07-portail  Standard  S1      1
   ```
3. Create the app in this plan:
   ```bash
   az webapp create -g "$RG_APP" -p "$PLAN" -n "$APP" --runtime "NODE:22-lts" --tags $TAGS \
     --query "{Name:name, Host:defaultHostName, State:state}" -o table
   HOST=$(az webapp show -g "$RG_APP" -n "$APP" --query defaultHostName -o tsv)
   ```
   Expected output:
   ```
   Name                   Host                                     State
   ---------------------  ---------------------------------------  -------
   app-st07-portail-2610  app-st07-portail-2610.azurewebsites.net  Running
   ```
4. Secure and configure the app: HTTPS only, ARR affinity off, TLS 1.2 minimum, FTP disabled, Always On, startup command, health check, app settings:
   ```bash
   az webapp update -g "$RG_APP" -n "$APP" --https-only true --client-affinity-enabled false -o none
   az webapp config set -g "$RG_APP" -n "$APP" \
     --startup-file "node server.js" --min-tls-version 1.2 --ftps-state Disabled \
     --always-on true --generic-configurations '{"healthCheckPath": "/health"}' -o none
   az webapp config appsettings set -g "$RG_APP" -n "$APP" \
     --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false \
     --slot-settings ARVEO_ENV=production -o none
   az webapp config show -g "$RG_APP" -n "$APP" -o table --query \
     "{Runtime:linuxFxVersion, Startup:appCommandLine, TLS:minTlsVersion, FTP:ftpsState, Health:healthCheckPath}"
   az webapp config appsettings list -g "$RG_APP" -n "$APP" -o table \
     --query "[].{Name:name, Value:value, Slot:slotSetting}"
   ```
   Expected output:
   ```
   Runtime      Startup         TLS    FTP       Health
   -----------  --------------  -----  --------  --------
   NODE|22-lts  node server.js  1.2    Disabled  /health
   Name                            Value       Slot
   ------------------------------  ----------  ------
   SCM_DO_BUILD_DURING_DEPLOYMENT  false       False
   ARVEO_ENV                       production  True
   ```
5. Package portal v3, then publish it with a zip deployment:
   ```bash
   ./scripts/labs/module-08/empaqueter-portail.sh v3
   az webapp deploy -g "$RG_APP" -n "$APP" --src-path ~/arveo-build/portail-v3.zip --type zip -o none
   ```
   Expected output (deployment: 1 to 2 min, no output):
   ```
   /home/<USER>/arveo-build/portail-v3.zip
   server.js
   package.json
   ```
6. Test the page, the health probe, the HTTP → HTTPS redirect and the `/api/` route:
   ```bash
   curl -s "https://${HOST}/"; curl -s "https://${HOST}/health"
   curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "http://${HOST}/"
   curl -s "https://${HOST}/api/"
   ```
   Expected output (instance ID varies):
   ```
   <h1>Arveo - portail client v3</h1><p>App Service - production - instance 3f9c1a2b</p>
   OK
   301 https://app-st07-portail-2610.azurewebsites.net/
   {"erreur":"API_URL non configuree"}
   ```
   `503` on `/api/`: expected at this point (no API configured; see challenge 08.5).
7. Turn on container logging, restart the app and follow its startup (60 s, then automatic stop):
   ```bash
   az webapp log config -g "$RG_APP" -n "$APP" --docker-container-logging filesystem -o none
   az webapp restart -g "$RG_APP" -n "$APP"
   timeout 60 az webapp log tail -g "$RG_APP" -n "$APP" | grep -m1 'ecoute'
   ```
   Expected output (timestamp varies):
   ```
   2026-10-08T07:41:12.512Z  Portail Arveo v3 (production) a l'ecoute sur le port 8080
   ```
8. **Portal**: open `app-st<NN>-portail-<SES>`:
   - **Overview**: plan, state, default host name;
   - **Settings** › **Environment variables**: `ARVEO_ENV` is marked "Deployment slot setting";
   - **Development Tools** › **Advanced Tools** (Kudu) › **Environment**: note `WEBSITE_INSTANCE_ID` and `PORT`.

### Success criteria
- [ ] `az webapp show -g rg-st<NN>-app -n app-st<NN>-portail-<SES> --query "[state, httpsOnly, clientAffinityEnabled]" -o tsv` shows `Running`, `true`, `false`.
- [ ] `curl -s https://<HOST>/` shows `portail client v3` and `production`.
- [ ] The HTTP request returns `301` to the HTTPS address.
- [ ] `ARVEO_ENV` is a slot setting (`slotSetting` = `True`).

---

## Exercise 08.3 ⭐⭐ — Releasing v4 with a swap, autoscale (semi-autonomous)
**Duration** : 18 min · **Objective** : update the portal with no downtime thanks to slots, then configure and prove autoscale on the plan (objective 9)
**Context** : Arvéo's web team delivers portal version v4. IT rule: every version first goes through acceptance testing on the `staging` slot address, then to production through a swap, with no customer request failing. The plan must handle the morning peaks (8 to 10 am) on its own, with at least two instances at all times.
**Prerequisites** : lab 08.2 completed.

**Instructions** :
1. Create the app's `staging` slot, copying the production configuration.
2. In `staging` only, set `ARVEO_ENV=recette` as a slot setting. Display the app settings of both slots.
3. Package v4 and publish it to `staging` ONLY. Check: production = v3 / `production`, staging = v4 / `recette`.
4. Start the production monitoring loop (provided), swap `staging` with production, then stop the loop:
   ```bash
   ( for i in $(seq 120); do R=$(curl -s -w '|%{http_code}' "https://${HOST}/")
       echo "$(date +%T) ${R##*|} $(grep -o 'client v[0-9]' <<< "$R")"; sleep 1
     done > ~/arveo-build/echange.log ) &
   ```
   After the swap: `kill %1` (or wait 2 min), then read `~/arveo-build/echange.log`.
5. Check: production = v4 / `production`, staging = v3 / `recette`.
6. Configure autoscale `as-st<NN>-portail` on the plan: 2 to 4 instances (2 by default); +1 if average CPU exceeds 70 % over 10 min; −1 if it drops below 30 % over 15 min.
7. Prove the two instances: list of the app's instances, then 20 production requests spread over two instance IDs.
8. Answer in writing:
   - a. Why must `ARVEO_ENV` be a slot setting? What would production show after the swap otherwise?
   - b. v4 has a defect found 10 min after release: rollback procedure and duration?
   - c. Why is this exercise impossible on a Basic B1 plan? What is the extra cost of the current plan compared with a single S1 instance?

**Hints** :
- Slot: `az webapp deployment slot create -g <GROUP> -n <APP> --slot staging --configuration-source <APP>`.
- Slot setting: `az webapp config appsettings set ... --slot staging --slot-settings ARVEO_ENV=recette`; reading: `az webapp config appsettings list ... [--slot staging]`.
- Slot address: `az webapp deployment slot list -g <GROUP> -n <APP> --query "[].defaultHostName" -o tsv`.
- Publishing: `az webapp deploy ... --slot staging --src-path <ZIP> --type zip`.
- Swap: `az webapp deployment slot swap ... --slot staging --target-slot production` (1 to 2 min).
- Autoscale: `az appservice plan show ... --query id -o tsv`, then `az monitor autoscale create --resource <PLAN_ID>` and `az monitor autoscale rule create --condition "CpuPercentage > 70 avg 10m" --scale out 1`.
- Instances: `az webapp list-instances -g <GROUP> -n <APP> --query "[].name" -o tsv`; counting: `for i in $(seq 20); do curl -s https://${HOST}/ | grep -o 'instance [0-9a-f]*'; done | sort | uniq -c`.

**Success criteria** :
- [ ] `curl -s https://<HOST>/` shows `v4` and `production`; the `staging` address shows `v3` and `recette`.
- [ ] `~/arveo-build/echange.log` contains only `200` codes and shows the switch from `client v3` to `client v4`.
- [ ] `az monitor autoscale show -g rg-st<NN>-app -n as-st<NN>-portail --query "profiles[0].[capacity.minimum, capacity.maximum, length(rules)]" -o tsv` shows `2`, `4`, `2`.
- [ ] The 20 requests of step 7 are served by two different instances.
- [ ] The three answers of step 8 are written.

---

## Lab 08.4 ⭐⭐ — Building the API image in ACR and running it on ACI (semi-autonomous)
**Duration** : 25 min (15 min before the break, 10 min after) · **Objective** : build an image in Azure Container Registry and run it on Azure Container Instances with a managed identity (objective 9)
**Context** : Arvéo's development team packages the parcel-tracking API as a container image: same JSON contract as in module 7 (`"service":"api-suivi-colis"`), but no more cloud-init or nginx to update on each VM. Security requires a private registry, no registry password stored anywhere, and READ-ONLY access from the runtime platform to the registry. This first ACI deployment is a technical acceptance test, public and temporary.
**Prerequisites** : variable block run; `Microsoft.ContainerRegistry` and `Microsoft.ContainerInstance` providers registered (trainer).

**Instructions** :
1. Read `scripts/labs/module-08/api/Dockerfile` and `nginx.conf`: base image, listening port, log destination, response content.
2. Check that the name `crarveost<NN><SES>` is available, then create the Basic registry, admin account DISABLED.
3. Build and push the image with ACR Tasks (provided, 1 to 2 min):
   ```bash
   az acr build -r "$ACR" -t arveo/api-suivi-colis:2.0 scripts/labs/module-08/api
   ```
   Expected output (end of the log; run ID and duration vary):
   ```
   Successfully pushed image: crarveost072610.azurecr.io/arveo/api-suivi-colis:2.0
   Run ID: ca1 was successful after 48s
   ```
4. List the registry's repositories and tags, then display the digest of image `2.0`.
5. Create the user-assigned managed identity `id-st<NN>-aci` and assign it the `AcrPull` role on the registry ONLY.
6. Create the public container `aci-st<NN>-api`: image `2.0` pulled with `id-st<NN>-aci`, Linux, 0.5 vCPU, 0.5 GB, port 8080, DNS label `arveo-st<NN>-api-<SES>`, restart `Always`, Arvéo tags.
7. Test: three requests to `http://<FQDN>:8080/` and one to `/health`; display the group state, the restart count and the container logs.
8. **Portal**: registry › **Repositories** (manifest and digest) and **Services** › **Tasks** › **Runs** (`ca1`); container › **Containers** › **Events** and **Logs**.
9. Answer in writing:
   - a. Why a user-assigned identity with `AcrPull` rather than the registry admin account?
   - b. What does ACI bill for this container, and when? Compare with the App Service plan of exercise 08.3.
   - c. Would this container be suitable as Arvéo's production API? Give three limits and the service that addresses them.

**Hints** :
- Name: `az acr check-name -n <NAME> --query nameAvailable -o tsv`.
- Registry: `az acr create -g <GROUP> -n <NAME> -l <REGION> --sku Basic --admin-enabled false --tags ...`.
- Reading: `az acr repository list -n <NAME> -o tsv`; `az acr repository show-tags -n <NAME> --repository <REPOSITORY> -o tsv`; `az acr repository show -n <NAME> --image <REPOSITORY>:<TAG> --query digest -o tsv`.
- Identity: `az identity create ... --query id -o tsv`; principal ID: `--query principalId`; assignment: `az role assignment create --assignee-object-id <PRINCIPAL_ID> --assignee-principal-type ServicePrincipal --role AcrPull --scope <REGISTRY_ID>`.
- Wait 1 to 2 min after the role assignment (propagation) before creating the container.
- Container: `az container create --os-type Linux --image <SERVER>/<REPOSITORY>:<TAG> --acr-identity <IDENTITY_ID> --assign-identity <IDENTITY_ID> --cpu 0.5 --memory 0.5 --ports 8080 --dns-name-label <LABEL> --restart-policy Always`.
- FQDN: `az container show ... --query ipAddress.fqdn -o tsv`; state: `--query "{State:instanceView.state, Restarts:containers[0].instanceView.restartCount}"`; logs: `az container logs -g <GROUP> -n <NAME>`.

**Success criteria** :
- [ ] `az acr show -n crarveost<NN><SES> --query "[sku.name, adminUserEnabled]" -o tsv` shows `Basic` and `false`.
- [ ] `az acr repository show-tags -n crarveost<NN><SES> --repository arveo/api-suivi-colis -o tsv` shows `2.0`.
- [ ] The only role assignment of `id-st<NN>-aci` is `AcrPull` on the registry (`az role assignment list --assignee <PRINCIPAL_ID> --all -o table`).
- [ ] `curl -s http://arveo-st<NN>-api-<SES>.francecentral.azurecontainer.io:8080/` returns the JSON with `"plateforme":"conteneur"`.
- [ ] The container logs show the requests of step 7; the three answers of step 9 are written.

---

## Challenge 08.5 ⭐⭐⭐ — PaaS portal and private containerized API (autonomous)
**Duration** : 25 min (fast learners, during lab 08.4 and the AKS demo; otherwise walkthrough of the solution) · **Objective** : connect an App Service app to a private container through VNet integration, without exposing the API to the Internet (objective 9)
**Context** : the acceptance test of lab 08.4 is conclusive, but the CISO refuses any API exposed to the Internet. Requirement: the PaaS portal calls the containerized API through a PRIVATE address of the application spoke; only the portal can call it, neither the module 7 web VMs nor the Internet. Portal version v4 already relays `/api/` to the address read from `API_URL`.

**Requirements** :

| Item | Requirement |
|---|---|
| Subnets | In the reserve of `vnet-st<NN>-spoke-app`: `snet-appsvc` `10.<OCT>.6.0/26` delegated to `Microsoft.Web/serverFarms`; `snet-aci` `10.<OCT>.6.64/27` delegated to `Microsoft.ContainerInstance/containerGroups` |
| Container | `aci-st<NN>-api-priv`, image `2.0` pulled with `id-st<NN>-aci`, PRIVATE IP in `snet-aci`, no public IP, port 8080 |
| `snet-aci` Internet egress | Through the existing NAT gateway `ng-st<NN>-app` |
| Filtering | `nsg-st<NN>-aci` on `snet-aci`: 8080 from `snet-appsvc` only, rest of VNet traffic denied |
| Portal | VNet integration in `snet-appsvc`; `API_URL` = `http://<PRIVATE_IP>:8080/`, production slot setting |

**Instructions** :
1. Deploy everything, with documented CLI or Bicep (`vnet-st<NN>-spoke-app` NOT redeclared).
2. Prove it works with four tests:
   - a. `https://<HOST>/api/` returns the API JSON with `"plateforme":"conteneur"`;
   - b. the private container has no public address and no FQDN;
   - c. from `vm-st<NN>-web01` (`snet-web`), a TCP connection to port 8080 of the private container fails;
   - d. the `staging` address still answers `503` on `/api/`.
3. Answer in writing:
   - a. Why is the NAT gateway essential on `snet-aci`? What happens without it?
   - b. The private container restarts and changes address: consequence, and two ways to guard against it.
   - c. Why doesn't VNet integration make the portal itself private? Which mechanism would?

**Success criteria** :
- [ ] `az network vnet subnet list -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-app --query "[?starts_with(name, 'snet-a')].[name, addressPrefix, delegations[0].serviceName]" -o tsv` shows `snet-app`, then the two new subnets with their delegation.
- [ ] `az container show -g rg-st<NN>-app -n aci-st<NN>-api-priv --query "[ipAddress.type, ipAddress.ip, ipAddress.fqdn]" -o tsv` shows `Private`, a `10.<OCT>.6.x` address and no FQDN.
- [ ] `az webapp vnet-integration list -g rg-st<NN>-app -n app-st<NN>-portail-<SES> --query "[0].vnetResourceId" -o tsv` ends with `snet-appsvc`.
- [ ] The four tests give the expected result; the three answers of step 3 are written.

---

## Bonus 🚀
1. **Azure Container Apps**: create the environment `cae-st<NN>-arveo` (consumption, no workspace: `--logs-destination none`) and the app `ca-st<NN>-api` (image `2.0` pulled with `id-st<NN>-aci`, external ingress on target port 8080, 0 to 3 replicas). Call its FQDN, wait 5 to 10 min with no traffic, then check the replica count: `az containerapp replica list` `[TO VERIFY]` scale-to-zero delay. `Microsoft.App` provider required.
2. **Testing in production**: send 20 % of production visitors to `staging` (`az webapp traffic-routing set --distribution staging=20`), count the versions served over 30 requests (`x-ms-routing-name` cookie not kept by `curl`), then send 100 % back to production (`az webapp traffic-routing clear`).
3. **Access restrictions**: restrict the `staging` slot (main site AND SCM site) to the Cloud Shell outbound public IP (`curl -s https://api.ipify.org`), with an implicit deny for everything else. Check from a browser outside Cloud Shell: `403`. Hint: `az webapp config access-restriction add --slot staging --rule-name CloudShell --action Allow --ip-address <IP>/32 --priority 100` and `az webapp config access-restriction set --slot staging --use-same-restrictions-for-scm-site true` `[TO VERIFY]` options.
4. **Container on App Service**: in the SAME plan, create the app `app-st<NN>-api-<SES>` running the registry's image `2.0`, pulled by identity `id-st<NN>-aci` (settings `acrUseManagedIdentityCreds` and `acrUserManagedIdentityID`, `WEBSITES_PORT=8080`) `[TO VERIFY]` `az webapp create` options for a container. Compare with ACI: cost, scaling, slots.

## Cleanup
- **End of module (10:58)**:
  ```bash
  ./scripts/cleanup/module-08-paas.sh "$NN" "$SES"
  ```
  The script deletes the containers (`aci-st<NN>-api`, `aci-st<NN>-api-priv`), the Container Apps resources of bonus 1, the autoscale setting, the apps (`staging` slot included), then the App Service plan. Safe to rerun.
- Kept: registry `crarveost<NN><SES>` and its image, identity `id-st<NN>-aci`, challenge subnets and NSG (reusable by the catch-up script). Modules 9 and 10 use no module 8 resource.
- **End of the course**:
  ```bash
  ./scripts/cleanup/module-08-paas.sh "$NN" "$SES" --purge
  ```
  Also deletes the registry, the identity, `snet-appsvc`, `snet-aci` and `nsg-st<NN>-aci` (automatic retries while a subnet is still held by its service).
- Full module catch-up: `./scripts/catch-up/module-08/deploy.sh <NN> <SES> [--defi]`.
- Costs: S1 App Service plan billed hourly per instance (stopped apps included), ACI containers per second (vCPU + memory), Basic registry per day + storage, ACR Tasks runs per second, Container Apps on consumption `[TO VERIFY]` Azure pricing calculator.

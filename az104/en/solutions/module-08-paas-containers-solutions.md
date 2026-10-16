# Module 08 — Solutions

Examples given for trainee 07, session `2610` (`NN=07`, `OCT=7`, `SES=2610`). All solutions assume the exercise variable block has been run in Cloud Shell (Bash): `NN`, `SES`, `OCT`, `ST`, `RG_APP`, `RG_SPOKE`, `LOC`, `TAGS`, `PLAN`, `APP`, `ACR`, `HOST`. Instance IDs, image digests, addresses and timestamps vary from one run to another. Lab scripts are shared with the French-speaking groups: their comments, messages and the pages they produce are in French.

## Exercise 08.1 ⭐ — Choosing the App Service plan

### Solution
| # | Tier | Deciding requirement |
|---|---|---|
| 1 Intranet mock-up | Free F1 (or Basic B1 if the mock-up must stay responsive) | No requirement; F1 is free, daily CPU quota, neither Always On nor custom domain |
| 2 Customer portal 2026 | Standard S1 | Slots (no-downtime releases) and autoscale: Standard minimum; VNet integration: Basic minimum |
| 3 Customer portal 2027 | Premium v3 (P0v3 or P1v3) | Zone redundancy: Premium v2 to v4 only, 2 instances minimum |
| 4 Customs extranet | Isolated v2 (App Service Environment v3) | Single-tenant environment, deployed in an Arvéo VNet |

Step 2: app 2, **2 instances minimum**: the health check only has an effect with at least two instances (the failing instance is removed from load balancing), platform maintenance restarts instances one after the other with no downtime, and a peak does not have to wait for autoscale to react.

Step 3: technically possible (several apps per plan), but not recommended: the mock-up would consume the CPU and memory of the portal instances (noisy neighbor), would be billed at the portal tier price, and would follow its scaling rules. Common rule: one plan per environment (production, non-production), and a dedicated plan for critical apps.

### Why
- Features (slots, autoscale, zone redundancy, VNet integration) are properties of the PLAN TIER, not of the app: choosing the plan means choosing the features.
- The cheapest tier covering ALL requirements is chosen; the size (S1, S2, S3) is then tuned by measurement (CPU, memory).
- Zone redundancy: the platform enforces and bills 2 instances minimum; 3 instances guarantee enough capacity while a zone is lost (without waiting for autoscale, which is not guaranteed in that case).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Basic chosen for app 2 | Manual scaling (Basic) confused with autoscale | Read the "Plans: which tier?" slide again: slots and rules from Standard |
| Standard chosen for app 3 | Zone redundancy assumed to be available everywhere | Premium v2 to v4 only |
| Premium chosen for app 4 | Network isolation confused with private endpoint | Private endpoint = private inbound access on shared infrastructure; "dedicated" = Isolated v2 |

### Acceptable variants
- App 2 on Premium v3 P0v3: valid (same features, newer hardware, zone redundancy possible later); compare with the S1 price `[TO VERIFY]` in the pricing calculator.
- App 1 on an existing non-production Basic plan: valid if that plan hosts nothing critical.

---

## Lab 08.2 ⭐ — Publishing portal v3 on App Service

### Solution
The commands are those of steps 1 to 7, unchanged. Final checks:
```bash
az webapp show -g "$RG_APP" -n "$APP" --query "[state, httpsOnly, clientAffinityEnabled]" -o tsv
az webapp config appsettings list -g "$RG_APP" -n "$APP" \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
```
Expected output:
```
Running
true
false
production	True
```

Step 8 (portal): in Kudu › **Environment**, `WEBSITE_INSTANCE_ID` (64 hexadecimal characters, the first 8 appear on the page) and `PORT=8080`; no SSH session on a system to patch, unlike the module 7 VMs.

### Why
- **Linux plan** (`--is-linux`): Node.js runs in a container managed by the platform; a Linux plan only hosts Linux apps.
- **S1**: minimum tier for slots and autoscale (exercise 08.3); 1 instance at creation, 2 afterwards through autoscale.
- **Name with the session code**: `<app>.azurewebsites.net` is a public DNS name, unique across Azure; the session code avoids collisions between trainees and between course sessions.
- **HTTPS only and TLS 1.2**: the platform provides the `*.azurewebsites.net` certificate; every HTTP request is redirected (`301`).
- **ARR affinity off**: by default, a cookie pins each browser to one instance; the portal is stateless, every request can go to any instance (exercise 08.3).
- **FTP disabled**: legacy protocol, publishing credentials to protect; zip deployment goes through the SCM site (Kudu) over HTTPS.
- **Explicit startup command** and `SCM_DO_BUILD_DURING_DEPLOYMENT=false`: no npm dependency, so no Oryx build; faster and predictable startup.
- **Health check** `/health`: the platform polls each instance; an instance that keeps failing is removed from load balancing, then replaced `[TO VERIFY]` default thresholds (`WEBSITE_HEALTHCHECK_MAXPINGFAILURES`).
- **`ARVEO_ENV` as a slot setting** from the start: it describes the environment, not the code; preparation for exercise 08.3.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `Website with given name ... already exists` | Name already used in Azure (another session, typo in `NN` or `SES`) | Check `echo $APP`; otherwise add a letter to the session code for the whole module (`SES=2610b`) and tell the trainer |
| `This region has quota of 0 instances for your subscription` `[TO VERIFY]` wording | Subscription App Service quota exhausted or zero in France Central | Trainer: quota request (D-10 preparation); workaround: one plan shared by a pair for the lab |
| `Linux Runtime 'NODE:22-lts' is not supported` | Runtime missing from the list | Use a `NODE:*-lts` version displayed in step 1 |
| "Your web app is running and waiting for your content" page | Deployment not done or failed | Run `az webapp deploy` again; read `az webapp log deployment show` `[TO VERIFY]` |
| `Application Error` or `503` on `/` | Startup command missing, or `server.js` in a subfolder of the archive | `az webapp config show --query appCommandLine`; `unzip -Z1 ~/arveo-build/portail-v3.zip` must list `server.js` at the root |
| `curl http://` returns `200` instead of `301` | HTTPS only not enabled | `az webapp update --https-only true` |
| `409 Conflict` on `az webapp deploy` | Previous deployment still running | Wait 1 min, try again |
| `az webapp log tail` silent | Container logging not on, or startup before logging was enabled | Step 7 in order: `log config`, `restart`, then `log tail` |

---

## Exercise 08.3 ⭐⭐ — Releasing v4 with a swap, autoscale

### Solution
```bash
# 1. staging slot, configuration copied from production
az webapp deployment slot create -g "$RG_APP" -n "$APP" --slot staging \
  --configuration-source "$APP" --query "defaultHostName" -o tsv
STG=$(az webapp deployment slot list -g "$RG_APP" -n "$APP" --query "[0].defaultHostName" -o tsv)

# 2. staging-specific slot setting, then reading both slots
az webapp config appsettings set -g "$RG_APP" -n "$APP" --slot staging \
  --slot-settings ARVEO_ENV=recette -o none
az webapp config appsettings list -g "$RG_APP" -n "$APP" \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
az webapp config appsettings list -g "$RG_APP" -n "$APP" --slot staging \
  --query "[?name=='ARVEO_ENV'].[value, slotSetting]" -o tsv
```
Expected output:
```
app-st07-portail-2610-staging.azurewebsites.net
production	True
recette	True
```

```bash
# 3. v4 published to staging only
./scripts/labs/module-08/empaqueter-portail.sh v4
az webapp deploy -g "$RG_APP" -n "$APP" --slot staging \
  --src-path ~/arveo-build/portail-v4.zip --type zip -o none
curl -s "https://${HOST}/"; curl -s "https://${STG}/"
```
Expected output:
```
/home/<USER>/arveo-build/portail-v4.zip
server.js
package.json
<h1>Arveo - portail client v3</h1><p>App Service - production - instance 3f9c1a2b</p>
<h1>Arveo - portail client v4</h1><p>App Service - recette - instance 3f9c1a2b</p>
```

```bash
# 4. Monitoring loop (instructions), swap, end of the loop
az webapp deployment slot swap -g "$RG_APP" -n "$APP" --slot staging --target-slot production
kill %1 2>/dev/null; sort ~/arveo-build/echange.log | uniq -c -f1 | head
grep -vc ' 200 ' ~/arveo-build/echange.log

# 5. Check after the swap
curl -s "https://${HOST}/"; curl -s "https://${STG}/"
```
Expected output (timestamps and line counts vary):
```
     41 07:52:01 200 client v3
     38 07:52:42 200 client v4
0
<h1>Arveo - portail client v4</h1><p>App Service - production - instance 3f9c1a2b</p>
<h1>Arveo - portail client v3</h1><p>App Service - recette - instance 3f9c1a2b</p>
```
`0`: no line without a `200` code.

```bash
# 6. Plan autoscale
PLAN_ID=$(az appservice plan show -g "$RG_APP" -n "$PLAN" --query id -o tsv)
az monitor autoscale create -g "$RG_APP" -n "as-${ST}-portail" --resource "$PLAN_ID" \
  --min-count 2 --max-count 4 --count 2 --tags $TAGS -o none
az monitor autoscale rule create -g "$RG_APP" --autoscale-name "as-${ST}-portail" \
  --condition "CpuPercentage > 70 avg 10m" --scale out 1 -o none
az monitor autoscale rule create -g "$RG_APP" --autoscale-name "as-${ST}-portail" \
  --condition "CpuPercentage < 30 avg 15m" --scale in 1 -o none
az monitor autoscale show -g "$RG_APP" -n "as-${ST}-portail" \
  --query "profiles[0].[capacity.minimum, capacity.maximum, length(rules)]" -o tsv

# 7. Two instances (1 to 5 min after step 6)
az webapp list-instances -g "$RG_APP" -n "$APP" --query "length(@)" -o tsv
for i in $(seq 20); do curl -s "https://${HOST}/" | grep -o 'instance [0-9a-f]*'; done | sort | uniq -c
```
Expected output (distribution varies):
```
2
4
2
2
     11 instance 3f9c1a2b
      9 instance 8d41e0c7
```

Answers to step 8:
- **a.** `ARVEO_ENV` describes the slot (production or acceptance), not the code version. Unmarked, it would travel with the code during the swap: production would show `recette` and acceptance would show `production`. In the enterprise, the connection strings to the production and acceptance databases are marked the same way: otherwise, the swap would connect production to the acceptance database.
- **b.** A new `staging` ↔ production swap: `staging` still holds v3, already started; back in 1 to 2 min, with no redeployment and no downtime. Then fix v4 and republish it to `staging`. Condition: publish nothing to `staging` between the release and the rollback decision.
- **c.** Basic offers neither slots nor autoscale (only 1 to 3 instances set by hand). Extra cost: 2 S1 instances at all times = twice the hourly price of one S1 instance (up to 4 times during peaks); the `staging` slot adds nothing, it runs on the same instances. Prices `[TO VERIFY]` Azure pricing calculator.

### Why
- **`--configuration-source`**: the slot takes the stack, startup command, health check and app settings from production; `ARVEO_ENV` is then set again explicitly, because copying slot settings is not guaranteed `[TO VERIFY]`.
- **Publishing to `staging` only**: acceptance testing happens on the slot address, on the same instances and with the same configuration as production, except slot settings.
- **Swap**: the platform applies the target's slot settings to the source, waits for its instances to answer (warm-up), then switches routing; hence no error in the monitoring loop.
- **Autoscale on the PLAN**: the plan carries the instances; `CpuPercentage` is a plan metric (average of its instances). Scale-in rule mandatory, distant thresholds (70 / 30) and different durations (10 / 15 min) to avoid flapping, as in module 7.
- **Minimum 2**: autoscale immediately takes the plan from 1 to 2 instances (current capacity outside the allowed range).
- **Two IDs in the 20 requests**: proof that App Service's internal load balancing spreads the requests, possible because ARR affinity was turned off in lab 08.2 (and because `curl` sends back no cookie).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Production shows `recette` after the swap | `ARVEO_ENV` set with `--settings` (unmarked) in one of the slots | Set it again with `--slot-settings` in both slots, then swap again |
| `staging` shows `production` | Setting copied by `--configuration-source` and not redefined | Step 2: `--slot staging --slot-settings ARVEO_ENV=recette` |
| Swap failed (`warm-up` or timeout) `[TO VERIFY]` wording | `staging` does not start (badly built archive, missing startup command) | `curl https://$STG/`; `az webapp log tail --slot staging`; fix then swap again |
| `echange.log` empty | Loop started in another Cloud Shell session, or `HOST` empty | `echo $HOST`; run the variable block again |
| `No metric definitions` when creating the rule | `--resource` targets the app instead of the plan | Use the plan ID (`az appservice plan show --query id`) |
| A single instance in the 20 requests | Autoscale not applied yet, or ARR affinity still on | `az appservice plan show --query sku.capacity` (wait for `2`); `az webapp show --query clientAffinityEnabled` |

### Acceptable variants
- Swap with preview (two phases): `az webapp deployment slot swap ... --action preview`, check `staging` with the production configuration, then `--action swap` (or `--action reset` to cancel).
- Additional schedule profile: 3 instances from 7:45 to 10:15 on weekdays (`az monitor autoscale profile create --recurrence week mon tue wed thu fri --start 07:45 --end 10:15 --timezone "Romance Standard Time"`) `[TO VERIFY]` options; useful when the peak is predictable.
- Deploying v4 from a GitHub Actions pipeline (action `azure/webapps-deploy`, parameter `slot-name: staging`): project target, outside the lab time.

---

## Lab 08.4 ⭐⭐ — Building the API image in ACR and running it on ACI

### Solution
Step 1 (reading): Azure Linux nginx base image from MCR (configurable through `IMAGE_BASE`), listens on 8080, access logs on standard output and error logs on standard error (readable through `az container logs`), fixed JSON response completed with the container host name (nginx `$hostname`), `/health` route in plain text.

```bash
# 2. Basic registry, admin account disabled
az acr check-name -n "$ACR" --query nameAvailable -o tsv
az acr create -g "$RG_APP" -n "$ACR" -l "$LOC" --sku Basic --admin-enabled false --tags $TAGS \
  --query "{Name:name, Server:loginServer, Tier:sku.name, Admin:adminUserEnabled}" -o table
```
Expected output:
```
true
Name             Server                      Tier    Admin
---------------  --------------------------  ------  -------
crarveost072610  crarveost072610.azurecr.io  Basic   False
```

```bash
# 3. Build (instructions), then 4. reading the registry
az acr repository list -n "$ACR" -o tsv
az acr repository show-tags -n "$ACR" --repository arveo/api-suivi-colis -o tsv
az acr repository show -n "$ACR" --image arveo/api-suivi-colis:2.0 --query digest -o tsv
```
Expected output (digest varies):
```
arveo/api-suivi-colis
2.0
sha256:6f1c0b9e4a7d2c3b8e5f9a0d1c2b3a4f5e6d7c8b9a0f1e2d3c4b5a6f7e8d9c0b
```

```bash
# 5. User-assigned identity, AcrPull role on the registry only
ID=$(az identity create -g "$RG_APP" -n "id-${ST}-aci" -l "$LOC" --tags $TAGS --query id -o tsv)
PID=$(az identity show --ids "$ID" --query principalId -o tsv)
ACR_ID=$(az acr show -n "$ACR" --query id -o tsv)
az role assignment create --assignee-object-id "$PID" --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID" --query roleDefinitionName -o tsv
sleep 60   # assignment propagation

# 6. Public container
az container create -g "$RG_APP" -n "aci-${ST}-api" -l "$LOC" --os-type Linux \
  --image "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
  --acr-identity "$ID" --assign-identity "$ID" --cpu 0.5 --memory 0.5 \
  --ports 8080 --ip-address Public --dns-name-label "arveo-${ST}-api-${SES}" \
  --restart-policy Always --tags $TAGS \
  --query "{State:provisioningState, FQDN:ipAddress.fqdn}" -o table
```
Expected output (1 to 2 min):
```
AcrPull
State      FQDN
---------  ----------------------------------------------------
Succeeded  arveo-st07-api-2610.francecentral.azurecontainer.io
```

```bash
# 7. Tests, state, logs
FQDN=$(az container show -g "$RG_APP" -n "aci-${ST}-api" --query ipAddress.fqdn -o tsv)
for i in 1 2 3; do curl -s "http://${FQDN}:8080/"; done; curl -s "http://${FQDN}:8080/health"
az container show -g "$RG_APP" -n "aci-${ST}-api" \
  --query "{State:instanceView.state, Restarts:containers[0].instanceView.restartCount}" -o table
az container logs -g "$RG_APP" -n "aci-${ST}-api" | tail -n 2
```
Expected output (host name, source address and timestamps vary):
```
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOST>"}
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOST>"}
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOST>"}
OK
State    Restarts
-------  ----------
Running  0
<CLOUD_SHELL_IP> - - [08/Oct/2026:08:21:05 +0000] "GET / HTTP/1.1" 200 96 "-" "curl/8.5.0"
<CLOUD_SHELL_IP> - - [08/Oct/2026:08:21:06 +0000] "GET /health HTTP/1.1" 200 3 "-" "curl/8.5.0"
```

Answers to step 9:
- **a.** The admin account is a single, shared credential (user name + password) with read AND write rights on the whole registry: a secret to store and rotate, not traceable per person or per service. The managed identity has no secret to manage, `AcrPull` limits it to pulling (least privilege) and every access is authenticated by Entra ID. User-assigned, because the identity must exist and be authorized BEFORE the container group is created, since it pulls the image as soon as it starts (system-assigned identity not supported for this pull).
- **b.** ACI bills per second for the REQUESTED vCPU and memory (0.5 vCPU, 0.5 GB), from the image pull until the group is stopped or deleted, whether the container receives requests or not: no scale to zero. The S1 plan of exercise 08.3 bills 2 instances hourly at all times. For an acceptance container or a one-off job, ACI costs far less; for a permanent service, compare with Container Apps (scale to zero). Prices `[TO VERIFY]` Azure pricing calculator.
- **c.** No: a single instance (no high availability, no zone), no autoscale, no load balancer or TLS (plain HTTP on 8080), public exposure, address not guaranteed across restarts, no rolling update. Azure Container Apps addresses these limits (managed HTTPS ingress, multiple replicas, revisions, scaling, VNet-integrated environment); AKS if Arvéo wants to run Kubernetes itself.

### Why
- **ACR Tasks** (`az acr build`): Cloud Shell has no Docker daemon; the context (`api` folder) is uploaded to the registry, built in Azure and pushed directly, without going through a workstation.
- **MCR base image**: Microsoft registries are not subject to Docker Hub anonymous download limits, which are frequent on the shared addresses used by ACR Tasks.
- **Tag `2.0` + digest**: a tag is mutable (it can be reassigned to another image), the `sha256` digest designates one precise, immutable image; in production, deploy by digest or with tags that are never reused.
- **Role at registry scope**: `AcrPull` on `rg-st<NN>-app` would grant access to every current and future registry in the group; the narrowest scope is enough.
- **`sleep 60`**: a role assignment can take a few minutes to take effect; an immediate pull fails (`unauthorized`).
- **`--restart-policy Always`**: permanent service; a one-off job would use `OnFailure` or `Never`, and the group would move to `Succeeded` / `Terminated` at the end of the job.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `az acr build`: `TasksOperationsNotAllowed` `[TO VERIFY]` wording | ACR Tasks not allowed on the subscription (some trial offers) | Import the image prepared by the trainer: `az acr import -n $ACR --source crarveoformation.azurecr.io/arveo/api-suivi-colis:2.0 --image arveo/api-suivi-colis:2.0` (trainee `AcrPull` role on that registry, see trainer guide) |
| Build: `manifest unknown` or `toomanyrequests` on the base image | Base image unavailable or throttled | Rerun with `--build-arg IMAGE_BASE=<OTHER_NGINX_IMAGE>` (validated on D-1) |
| `az container create`: `InaccessibleImage` or `unauthorized` | Role not propagated yet, or identity missing from `--acr-identity` | Wait 1 to 2 min; check `az role assignment list --assignee $PID --all -o table`; try again |
| `DnsNameLabelAlreadyInUse` `[TO VERIFY]` wording | DNS label already taken in the region | Check `NN` and `SES`; otherwise add a letter to the label |
| `curl` gets no answer on the FQDN | Port 8080 missing from `--ports`, or container in a restart loop | `az container show --query "containers[0].instanceView.events[].message"`; `az container logs` |
| `MissingSubscriptionRegistration` | `Microsoft.ContainerInstance` provider not registered | Trainer: `az provider register -n Microsoft.ContainerInstance` |

### Acceptable variants
- Deployment through `scripts/catch-up/module-08/aci.bicep` (parameters `acrLoginServer`, `identityId`): same result, replayable.
- Registry and identity created in Bicep (catch-up `main.bicep`, resources `acr`, `idAci`, `acrPull`).
- Additional immutable tag generated by the task: `-t arveo/api-suivi-colis:{{.Run.ID}}` (run ID).

---

## Challenge 08.5 ⭐⭐⭐ — PaaS portal and private containerized API

### Solution
```bash
VNET="vnet-${ST}-spoke-app"
VNET_ID=$(az network vnet show -g "$RG_SPOKE" -n "$VNET" --query id -o tsv)
ID=$(az identity show -g "$RG_APP" -n "id-${ST}-aci" --query id -o tsv)

# snet-aci NSG: 8080 from snet-appsvc only
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-aci" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-aci" -n Allow-8080-From-AppSvc \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "10.${OCT}.6.0/26" --destination-port-ranges 8080 -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-aci" -n Deny-VNet-Inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-port-ranges '*' -o none

# Delegated subnets in the 10.OCT.6.0/23 reserve
az network vnet subnet create -g "$RG_SPOKE" --vnet-name "$VNET" -n snet-appsvc \
  --address-prefixes "10.${OCT}.6.0/26" --delegations Microsoft.Web/serverFarms -o none
az network vnet subnet create -g "$RG_SPOKE" --vnet-name "$VNET" -n snet-aci \
  --address-prefixes "10.${OCT}.6.64/27" \
  --delegations Microsoft.ContainerInstance/containerGroups \
  --nat-gateway "ng-${ST}-app" --network-security-group "nsg-${ST}-aci" -o none
SNET_ACI="${VNET_ID}/subnets/snet-aci"
SNET_APPSVC="${VNET_ID}/subnets/snet-appsvc"

# Private container
az container create -g "$RG_APP" -n "aci-${ST}-api-priv" -l "$LOC" --os-type Linux \
  --image "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
  --acr-identity "$ID" --assign-identity "$ID" --cpu 0.5 --memory 0.5 --ports 8080 \
  --vnet "$VNET_ID" --subnet "$SNET_ACI" --restart-policy Always --tags $TAGS \
  --query "{Type:ipAddress.type, IP:ipAddress.ip}" -o table
IP_PRIV=$(az container show -g "$RG_APP" -n "aci-${ST}-api-priv" --query ipAddress.ip -o tsv)

# Portal: VNet integration + API_URL (production slot setting)
az webapp vnet-integration add -g "$RG_APP" -n "$APP" --vnet "$VNET_ID" --subnet "$SNET_APPSVC" -o none
az webapp config appsettings set -g "$RG_APP" -n "$APP" \
  --slot-settings "API_URL=http://${IP_PRIV}:8080/" -o none
```
Expected output (2 to 3 min for the container; address varies within `10.7.6.64/27`):
```
Type     IP
-------  ---------
Private  10.7.6.68
```

Tests of step 2:
```bash
sleep 30   # app restart after the settings change
curl -s "https://${HOST}/api/"                                                     # a
az container show -g "$RG_APP" -n "aci-${ST}-api-priv" \
  --query "[ipAddress.type, ipAddress.ip, ipAddress.fqdn]" -o tsv                  # b
az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-web01" --command-id RunShellScript \
  --scripts "timeout 3 bash -c '</dev/tcp/${IP_PRIV}/8080' && echo OUVERT || echo REFUSE" \
  --query "value[0].message" -o tsv | grep -E 'OUVERT|REFUSE'                      # c
STG=$(az webapp deployment slot list -g "$RG_APP" -n "$APP" --query "[0].defaultHostName" -o tsv)
curl -s "https://${STG}/api/"                                                      # d
```
Expected output (`OUVERT` = open, `REFUSE` = refused):
```
{"service":"api-suivi-colis","version":"2.0","plateforme":"conteneur","instance":"<HOST>"}
Private
10.7.6.68
None
REFUSE
{"erreur":"API_URL non configuree"}
```
(`None` or an empty line for the FQDN, depending on the CLI version.)

Answers to step 3:
- **a.** `snet-aci` is a subnet created in 2026: no implicit outbound access (default outbound access retired, module 7). The container group pulls its image from the registry's PUBLIC endpoint: without a NAT gateway, the pull fails and the group stays pending, then fails. Alternative with no Internet egress: registry private endpoint (Premium tier) in another subnet, with the private DNS zone `privatelink.azurecr.io`.
- **b.** The private address of an ACI group is not guaranteed across restarts or re-creation: `API_URL` would point to a stale address and `/api/` would answer `502`. Mitigations: A record in a private DNS zone linked to the spoke, updated at each deployment (and `API_URL` by name); or Azure Container Apps in an internal, VNet-integrated environment, which provides a stable name and load balancing across replicas.
- **c.** VNet integration only covers the app's OUTBOUND traffic. The portal remains publicly reachable on `*.azurewebsites.net`. To make it private: app private endpoint in a subnet (public access disabled), clients through VPN or ExpressRoute, or publication through Application Gateway / Front Door with WAF in front of the private endpoint.

### Why
- **Two separate subnets**: a delegated subnet only hosts the service it is delegated to; App Service and ACI cannot share the same one.
- **Sizes**: `/26` for App Service integration (one address per plan instance, headroom for scaling and upgrades `[TO VERIFY]` recommended minimum size); `/27` for a few container groups. Both fit in the `10.<OCT>.6.0/23` reserve planned in module 4.
- **NSG with an explicit VNet deny**: the default `AllowVnetInBound` rule would allow `snet-web` and the hub; rule 4000 only lets `snet-appsvc` through (rule 100), hence test c.
- **`API_URL` as a slot setting**: only production is VNet-integrated (integration is per slot); marked, the address stays in production during the next swaps, hence test d.
- **VNet not redeclared**: changing `vnet-st<NN>-spoke-app` in Bicep without describing all existing subnets would delete them or fail (incremental mode, `subnets` property replaced); subnets are added one by one.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `SubnetMissingRequiredDelegation` | Delegation forgotten | `az network vnet subnet update --delegations <SERVICE>` (empty subnet) |
| Private container `Waiting` then `Failed`, pull error event | No NAT gateway on `snet-aci` | `az network vnet subnet update ... -n snet-aci --nat-gateway ng-st<NN>-app`, then recreate the container |
| `/api/` returns `502` `API injoignable` | NSG source is `snet-web` instead of `snet-appsvc`; integration missing; wrong address | `az webapp vnet-integration list`; `az network nsg rule list -g rg-st<NN>-spoke --nsg-name nsg-st<NN>-aci -o table`; compare `API_URL` and `ipAddress.ip` |
| `/api/` returns `503` in production | `API_URL` set in `staging` or not set | `az webapp config appsettings list --query "[?name=='API_URL']"` on production |
| `vnet-integration add` rejected | Subnet not delegated, already used, or Free plan | Empty subnet delegated to `Microsoft.Web/serverFarms`; Basic plan or higher |
| `az container create`: public IP and subnet options incompatible | `--ip-address Public` or `--dns-name-label` added in VNet mode | Remove both options |

### Acceptable variants
- Private container through `scripts/catch-up/module-08/aci.bicep` with `prive=true subnetId=<SNET_ACI_ID>`; network in CLI.
- `API_URL` by name: private DNS zone `api.arveo.internal` (module 4) linked to the app spoke, A record to the container address. The portal resolves through the VNet DNS thanks to the integration `[TO VERIFY]` DNS routing of the integration.
- Azure Container Apps (internal environment in a dedicated subnet) instead of ACI: stable name, several replicas; longer to set up.

---

## Bonus

1. **Azure Container Apps**:
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
   After 5 to 10 min with no request, the replica count drops to `0`; the next request starts a replica again (cold start of a few seconds). HTTPS ingress provided, unlike ACI.
2. **Testing in production**:
   ```bash
   az webapp traffic-routing set -g "$RG_APP" -n "$APP" --distribution staging=20 -o none
   for i in $(seq 30); do curl -s "https://${HOST}/" | grep -o 'client v[0-9]'; done | sort | uniq -c
   az webapp traffic-routing clear -g "$RG_APP" -n "$APP"
   ```
   About 24 answers from production and 6 from `staging` (random draw per request, since no cookie is kept). A browser stays on its version thanks to the `x-ms-routing-name` cookie.
3. **Access restrictions**:
   ```bash
   IP=$(curl -s https://api.ipify.org)
   az webapp config access-restriction add -g "$RG_APP" -n "$APP" --slot staging \
     --rule-name CloudShell --action Allow --ip-address "${IP}/32" --priority 100 -o none
   az webapp config access-restriction set -g "$RG_APP" -n "$APP" --slot staging \
     --use-same-restrictions-for-scm-site true -o none
   az webapp config access-restriction show -g "$RG_APP" -n "$APP" --slot staging -o json \
     --query "ipSecurityRestrictions[].{Name:name, Action:action, IP:ipAddress}"
   ```
   As soon as an Allow rule exists, an implicit deny applies to everything else (`403` from an outside browser). Restrictions are slot-specific: not swapped.
4. **Container on App Service**:
   ```bash
   CLIENT_ID=$(az identity show -g "$RG_APP" -n "id-${ST}-aci" --query clientId -o tsv)
   az webapp create -g "$RG_APP" -p "$PLAN" -n "app-${ST}-api-${SES}" \
     --container-image-name "${ACR}.azurecr.io/arveo/api-suivi-colis:2.0" \
     --assign-identity "$ID" --acr-use-identity --acr-identity "$ID" --tags $TAGS -o none
   az webapp config appsettings set -g "$RG_APP" -n "app-${ST}-api-${SES}" \
     --settings WEBSITES_PORT=8080 -o none
   curl -s "https://app-${ST}-api-${SES}.azurewebsites.net/"
   ```
   `az webapp create` options for a container and a user-assigned identity `[TO VERIFY]` depending on the CLI version; configuration equivalent: `acrUseManagedIdentityCreds=true` and `acrUserManagedIdentityID=$CLIENT_ID` (`az webapp config set --generic-configurations`). The app shares the plan instances (no extra cost), benefits from the plan's slots and scaling, but never goes down to zero.

---

## QCM — Answers
1. **C** — Deployment slots are available from the Standard tier (5), then Premium and Isolated (20).
2. **B** — The plan is the billing unit: its instances are billed hourly, whether the apps are stopped or not.
3. **A** — Changing tier or size changes the power of each instance: vertical scaling.
4. **C** — Slot settings stay attached to their slot; code and unmarked settings are swapped.
5. **B** — Without ARR affinity, no cookie pins a client to an instance: each request can go to any instance.
6. **B** — `az acr build` uploads the context to ACR Tasks, which builds and pushes the image in Azure.
7. **B** — ACI pulls an ACR image with a user-assigned identity; `AcrPull` is enough (system-assigned is not supported).
8. **B** — ACI bills per second and stops with the job thanks to the `Never` or `OnFailure` policy.
9. **A** — Container Apps scales on events (KEDA) down to zero replicas, without exposing Kubernetes.
10. **B** — VNet integration only covers outbound traffic; private inbound access goes through a private endpoint.

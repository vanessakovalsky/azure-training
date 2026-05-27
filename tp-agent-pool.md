# TP8 : Gérer la file d'attente et utiliser des agents privés

**Durée estimée : 90 minutes**

#### Objectifs
- Créer et configurer un agent pool privé
- Installer un agent self-hosted
- Configurer les capabilities
- Observer la gestion de la file d'attente
- Optimiser les builds avec le cache

---

#### Partie 1 : Créer un agent pool (15 min)

**Créer le pool dans Azure DevOps**

```
1. Organisation Settings → Agent pools → Add pool

   Type: Self-hosted
   Name: ShopConnect-Private
   ☑ Grant access permission to all pipelines
   [Create]

2. ShopConnect-Private → Security
   Ajouter les utilisateurs autorisés:
   - Project Administrators: Administrator
   - Developers: User
   - Readers: Reader
```

**Générer le PAT pour l'agent**

```
User Settings → Personal Access Tokens → New Token

Name: Agent-ShopConnect-Token
Organization: votre-organisation
Expiration: 1 year
Scopes:
  ☑ Agent Pools: Read & manage

[Create]
⚠️ COPIER LE TOKEN MAINTENANT (ne sera plus visible)
```

---

#### Partie 2 : Installer l'agent (30 min)

**Option A : Agent Windows (votre machine de formation)**

```powershell
# 1. Télécharger l'agent
# Azure DevOps → Org Settings → Agent pools → ShopConnect-Private → New agent
# → Windows → x64 → Download

# 2. Créer le répertoire
New-Item -ItemType Directory -Path C:\AzureAgent
Set-Location C:\AzureAgent

# 3. Extraire l'archive (après téléchargement)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory(
    "$env:USERPROFILE\Downloads\vsts-agent-win-x64-*.zip",
    "C:\AzureAgent"
)

# 4. Configurer (mode interactif)
.\config.cmd
```

Répondre aux questions :

```
Enter server URL: https://dev.azure.com/VOTRE-ORGANISATION
Enter authentication type (press enter for PAT): PAT
Enter personal access token: [COLLER VOTRE PAT]
Enter agent pool (press enter for default): ShopConnect-Private
Enter agent name (press enter for VOTRE-PC): TRAINING-AGENT-01
Enter work folder (press enter for _work): _work
Enter run agent as service? (Y/N): N  # Mode interactif pour la formation
```

```powershell
# 5. Démarrer l'agent
.\run.cmd

# Vérifier dans Azure DevOps:
# Org Settings → Agent pools → ShopConnect-Private → Agents
# → TRAINING-AGENT-01 (Status: Online ✓)
```

**Option B : Agent via Docker (si Docker disponible)**

```bash
# Créer le Dockerfile pour l'agent
cat > Dockerfile.agent << 'EOF'
FROM ubuntu:22.04

# Installer les prérequis
RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    libicu-dev \
    libssl-dev \
    dotnet-sdk-8.0 \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Créer l'utilisateur agent
RUN useradd -m -s /bin/bash azureagent

# Télécharger et configurer l'agent
WORKDIR /opt/azure-agent
RUN curl -LO \
    "https://vstsagentpackage.azureedge.net/agent/3.236.1/vsts-agent-linux-x64-3.236.1.tar.gz" \
    && tar xzf vsts-agent-linux-x64-3.236.1.tar.gz \
    && rm vsts-agent-linux-x64-3.236.1.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R azureagent:azureagent /opt/azure-agent

USER azureagent

# Script de démarrage
COPY start-agent.sh /start-agent.sh
CMD ["/start-agent.sh"]
EOF

cat > start-agent.sh << 'EOF'
#!/bin/bash
./config.sh \
  --unattended \
  --url "$AZP_URL" \
  --auth pat \
  --token "$AZP_TOKEN" \
  --pool "$AZP_POOL" \
  --agent "${AZP_AGENT_NAME:-docker-agent-$(hostname)}" \
  --work "_work" \
  --replace

./run.sh
EOF
chmod +x start-agent.sh

# Build et run
docker build -t azure-devops-agent -f Dockerfile.agent .

docker run -d \
  -e AZP_URL="https://dev.azure.com/votre-organisation" \
  -e AZP_TOKEN="VOTRE_PAT" \
  -e AZP_POOL="ShopConnect-Private" \
  -e AZP_AGENT_NAME="docker-agent-01" \
  --name azure-agent-01 \
  azure-devops-agent

# Vérifier
docker logs azure-agent-01 --follow
```

---

#### Partie 3 : Configurer les capabilities (15 min)

**Ajouter des capabilities à l'agent**

```
1. Org Settings → Agent pools → ShopConnect-Private → Agents
2. TRAINING-AGENT-01 → Capabilities → User capabilities → + Add capability

Ajouter:
├─ Team = Frontend
├─ SpecialSoftware = LicensedTool
├─ BuildType = Dedicated
└─ Environment = Training
```

**Tester le routage via demands**

```yaml
# azure-pipelines-demands.yml

trigger: none

jobs:
# Job 1: Sans demands (n'importe quel agent)
- job: AnyAgent
  pool:
    name: 'ShopConnect-Private'
  displayName: 'Run on any available agent'
  steps:
  - script: |
      echo "Running on: $AGENT_NAME"
      echo "OS: $AGENT_OS"
    displayName: 'Show agent info'

# Job 2: Avec demand (seulement l'agent Frontend)
- job: FrontendAgent
  pool:
    name: 'ShopConnect-Private'
    demands:
    - Team -equals Frontend
  displayName: 'Run on Frontend team agent'
  steps:
  - script: |
      echo "Running on Frontend agent: $AGENT_NAME"
    displayName: 'Frontend-specific task'

# Job 3: Demand non satisfaite (test d'attente)
- job: SpecialAgent
  pool:
    name: 'ShopConnect-Private'
    demands:
    - GPU -equals NVIDIA-RTX4090  # Aucun agent n'a cette capability
  displayName: 'This job will wait (no matching agent)'
  steps:
  - script: echo "Running on GPU agent"
```

**Observer dans la file d'attente :**

```
1. Lancer le pipeline
2. Org Settings → Agent pools → ShopConnect-Private → Jobs
3. Observer:
   - AnyAgent: En cours (agent disponible)
   - FrontendAgent: En cours (si Team=Frontend configuré)
   - SpecialAgent: En attente (aucun agent GPU disponible)
```

---

#### Partie 4 : Optimiser avec le cache (30 min)

**Créer un pipeline avec et sans cache**

```bash
cd C:\Projects\ShopConnect

cat > azure-pipelines-cache-test.yml << 'EOF'
trigger: none

stages:
# Test 1: Sans cache (baseline)
- stage: BuildWithoutCache
  displayName: 'Build WITHOUT Cache'
  jobs:
  - job: NoCacheJob
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: UseDotNet@2
      inputs:
        version: '8.0.x'
    
    - task: DotNetCoreCLI@2
      displayName: 'Restore (no cache)'
      inputs:
        command: 'restore'
    
    - task: DotNetCoreCLI@2
      displayName: 'Build'
      inputs:
        command: 'build'
        arguments: '--no-restore --configuration Release'
    
    - task: DotNetCoreCLI@2
      displayName: 'Test'
      inputs:
        command: 'test'
        arguments: '--no-build --configuration Release'

# Test 2: Avec cache
- stage: BuildWithCache
  displayName: 'Build WITH Cache'
  dependsOn: []  # Pas de dépendance → parallèle avec le premier
  jobs:
  - job: CacheJob
    pool:
      vmImage: 'ubuntu-latest'
    variables:
      NUGET_PACKAGES: $(Pipeline.Workspace)/.nuget/packages
    steps:
    - task: UseDotNet@2
      inputs:
        version: '8.0.x'
    
    # Cache NuGet
    - task: Cache@2
      displayName: 'Cache NuGet packages'
      inputs:
        key: 'nuget | "$(Agent.OS)" | **/*.csproj'
        restoreKeys: |
          nuget | "$(Agent.OS)"
        path: $(NUGET_PACKAGES)
    
    - task: DotNetCoreCLI@2
      displayName: 'Restore (with cache)'
      inputs:
        command: 'restore'
    
    - task: DotNetCoreCLI@2
      displayName: 'Build'
      inputs:
        command: 'build'
        arguments: '--no-restore --configuration Release'
    
    - task: DotNetCoreCLI@2
      displayName: 'Test'
      inputs:
        command: 'test'
        arguments: '--no-build --configuration Release'
EOF

git add azure-pipelines-cache-test.yml
git commit -m "ci: add cache performance test"
git push origin main
```

**Observer les résultats :**

```
Première exécution (cache froid):
├─ BuildWithoutCache: ~5 min 30s
└─ BuildWithCache:    ~5 min 45s (+15s pour créer le cache)

Deuxième exécution (cache chaud):
├─ BuildWithoutCache: ~5 min 30s (identique)
└─ BuildWithCache:    ~3 min 15s (économie: ~40%)

Observer dans les logs:
Cache task:
  ✓ Cache restored from key: nuget | Linux | abc123...
  Saved 842 MB from cache
```

---

#### Partie 5 : Gestion avancée de la file d'attente (15 min)

**Simuler une file d'attente**

```bash
# Déclencher plusieurs builds rapidement
for i in {1..5}; do
  echo "Triggering build $i..."
  # Via l'interface: Pipeline → Run pipeline (5 fois)
done

# Observer dans:
# Org Settings → Agent pools → ShopConnect-Private → Jobs

# Ou via API:
curl -X POST \
  "https://dev.azure.com/VOTRE-ORG/ShopConnect/_apis/pipelines/1/runs?api-version=7.0" \
  -H "Authorization: Basic $(echo -n :$PAT | base64)" \
  -H "Content-Type: application/json" \
  -d '{"resources":{"repositories":{"self":{"refName":"refs/heads/main"}}}}'
```

**Observer et gérer la queue :**

```
Azure DevOps → Pipelines (liste) → ...

Vue de toutes les exécutions en cours et en attente:
┌──────────────────────────────────────────────────────────────┐
│ Run #125   │ In progress   │ Agent 1 │ Started 2m ago        │
│ Run #126   │ In progress   │ Agent 2 │ Started 1m ago        │
│ Run #127   │ Queued        │ -       │ Waiting 3m             │
│ Run #128   │ Queued        │ -       │ Waiting 2m             │
│ Run #129   │ Queued        │ -       │ Waiting 1m             │
└──────────────────────────────────────────────────────────────┘

Actions disponibles:
- Annuler une exécution en file
- Voir l'agent assigné
- Réordonner (non disponible nativement, via pools dédiés)
```

---

#### Livrables attendus

✅ Agent pool privé "ShopConnect-Private" créé
✅ Agent installé et online (Windows, Linux, ou Docker)
✅ Capabilities configurées sur l'agent
✅ Demands testées dans un pipeline
✅ Pipeline avec cache mesuré (avant/après)
✅ File d'attente observée et comprise

---

#### Questions de validation

1. **Quelle est la différence entre Microsoft-hosted et self-hosted agents ?**

2. **Qu'est-ce qu'une "capability" et comment l'utiliser pour router les jobs ?**

3. **Quel est l'impact du cache sur les performances des builds ?**

4. **Pourquoi le service d'un agent self-hosted doit-il être exécuté avec un compte de service dédié ?**

5. **Comment vérifier qu'un agent est bien en ligne et disponible ?**

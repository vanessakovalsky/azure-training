# TP7 : Gérer les versions et visualiser les logs

**Durée estimée : 3h30**

#### Objectifs
- Mettre en place le versioning automatique
- Gérer les variables par environnement via Key Vault
- Analyser et visualiser les logs de déploiement
- Implémenter la gestion d'erreurs

---

#### Partie 1 : Versioning automatique (50 min)

**Ajouter le versioning au projet**

```bash
cd C:\Projects\ShopConnect

# Créer le fichier GitVersion.yml
cat > GitVersion.yml << 'EOF'
mode: Mainline

branches:
  main:
    regex: ^master$|^main$
    tag: ''
    increment: Patch
    prevent-increment-of-merged-branch-version: true
    track-merge-target: false
    source-branches: []
    tracks-release-branches: false
    is-release-branch: false
    pre-release-weight: 55000

  develop:
    regex: ^dev(elop)?(ment)?$
    tag: alpha
    increment: Minor
    source-branches: ['main']
    pre-release-weight: 0

  feature:
    regex: ^features?[/-]
    tag: useBranchName
    increment: Inherit
    source-branches: ['develop', 'main']
    pre-release-weight: 30000

  release:
    regex: ^releases?[/-]
    tag: beta
    increment: None
    source-branches: ['develop', 'main']
    pre-release-weight: 30000

  hotfix:
    regex: ^hotfix(es)?[/-]
    tag: beta
    increment: Patch
    source-branches: ['main', 'develop']
    pre-release-weight: 30000
EOF

# Exposer la version dans l'application
cat > src/ShopConnect.API/Controllers/VersionController.cs << 'EOF'
using Microsoft.AspNetCore.Mvc;
using System.Reflection;

namespace ShopConnect.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VersionController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        var version = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion ?? "1.0.0";
        
        return Ok(new
        {
            version,
            buildNumber = Environment.GetEnvironmentVariable("BUILD_NUMBER") ?? "local",
            environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Development",
            timestamp = DateTime.UtcNow
        });
    }
    
    [HttpGet("health")]
    public IActionResult Health() => Ok(new { status = "healthy", timestamp = DateTime.UtcNow });
}
EOF

git add .
git commit -m "feat: add versioning and health endpoint"
git push origin main
```

**Créer le pipeline avec versioning**

```bash
cat > azure-pipelines-versioned.yml << 'EOF'
trigger:
  branches:
    include:
    - main
    - develop
    - feature/*
    - release/*
    - hotfix/*
  tags:
    include:
    - v*

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'

name: $(Build.DefinitionName)_$(Date:yyyyMMdd)$(Rev:.r)

stages:
- stage: Version
  displayName: 'Calculate Version'
  jobs:
  - job: VersionJob
    displayName: 'GitVersion'
    steps:
    - checkout: self
      fetchDepth: 0

    - task: gitversion/setup@0
      displayName: 'Install GitVersion'
      inputs:
        versionSpec: '5.x'

    - task: gitversion/execute@0
      displayName: 'Execute GitVersion'
      name: GitVersion

    - script: |
        echo "SemVer:      $(GitVersion.SemVer)"
        echo "FullSemVer:  $(GitVersion.FullSemVer)"
        echo "BranchName:  $(GitVersion.BranchName)"
        echo "Commit:      $(GitVersion.Sha)"
      displayName: 'Display version info'

- stage: Build
  displayName: 'Build v$(GitVersion.SemVer)'
  dependsOn: Version
  variables:
    semVer: $[ stageDependencies.Version.VersionJob.outputs['GitVersion.SemVer'] ]
    fullSemVer: $[ stageDependencies.Version.VersionJob.outputs['GitVersion.FullSemVer'] ]
  jobs:
  - job: BuildJob
    steps:
    - checkout: self
      fetchDepth: 0

    - task: gitversion/setup@0
      inputs:
        versionSpec: '5.x'

    - task: gitversion/execute@0
      name: GitVersion

    - task: DotNetCoreCLI@2
      displayName: 'Build v$(GitVersion.SemVer)'
      inputs:
        command: 'build'
        arguments: >
          --configuration $(buildConfiguration)
          /p:Version=$(GitVersion.SemVer)
          /p:AssemblyVersion=$(GitVersion.AssemblySemVer)
          /p:FileVersion=$(GitVersion.MajorMinorPatch)
          /p:InformationalVersion=$(GitVersion.InformationalVersion)

    - task: DotNetCoreCLI@2
      displayName: 'Run tests'
      inputs:
        command: 'test'
        arguments: '--configuration $(buildConfiguration) --no-build'

    - task: DotNetCoreCLI@2
      displayName: 'Publish'
      inputs:
        command: 'publish'
        arguments: >
          --configuration $(buildConfiguration)
          /p:Version=$(GitVersion.SemVer)
          --output $(Build.ArtifactStagingDirectory)/$(GitVersion.SemVer)
        zipAfterPublish: true

    - task: PublishBuildArtifacts@1
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)'
        artifactName: 'drop-v$(GitVersion.SemVer)'

    - script: |
        echo "##vso[build.updatebuildnumber]$(GitVersion.SemVer)"
        echo "##vso[build.addbuildtag]v$(GitVersion.SemVer)"
      displayName: 'Update build number and tag'
EOF

git add azure-pipelines-versioned.yml
git commit -m "ci: add versioned pipeline"
git push origin main
```

**Observer les résultats :**

```bash
# Feature branch → alpha version
git checkout -b feature/new-auth
git commit --allow-empty -m "feat: trigger versioned build"
git push origin feature/new-auth
# Version attendue: 1.2.0-feature-new-auth.1

# Develop → alpha
git checkout develop
git merge feature/new-auth
git push origin develop
# Version attendue: 1.2.0-alpha.3

# Main → release
git checkout main
git merge develop
git push origin main
# Version attendue: 1.2.0
```

---

#### Partie 2 : Variables par environnement (45 min)

**Créer les groupes de variables**

```
1. Pipelines → Library → + Variable group

Groupe 1: ShopConnect-Common
  ApplicationName = ShopConnect
  AzureRegion = westeurope
  [Save]

Groupe 2: ShopConnect-Dev
  WebAppName = shopconnect-webapp-dev
  LogLevel = Debug
  EnableSwagger = true
  [Save]

Groupe 3: ShopConnect-Test
  WebAppName = shopconnect-webapp-test
  LogLevel = Information
  EnableSwagger = false
  [Save]

Groupe 4: ShopConnect-Prod
  WebAppName = shopconnect-webapp-prod
  LogLevel = Warning
  EnableSwagger = false
  [Save]
```

**Créer le pipeline avec groupes**

```yaml
# azure-pipelines-multienv.yml

trigger:
  branches:
    include: [main]

stages:
- stage: Build
  jobs:
  - job: BuildJob
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: DotNetCoreCLI@2
      inputs:
        command: 'build'
        arguments: '--configuration Release'
    - task: DotNetCoreCLI@2
      inputs:
        command: 'publish'
        arguments: '--configuration Release --output $(Build.ArtifactStagingDirectory)'
        zipAfterPublish: true
    - task: PublishBuildArtifacts@1
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)'
        artifactName: 'drop'

- stage: DeployDev
  dependsOn: Build
  variables:
  - group: ShopConnect-Common
  - group: ShopConnect-Dev
  jobs:
  - deployment: DeployDevJob
    environment: Development
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: drop
          - script: |
              echo "Deploying to: $(WebAppName)"
              echo "Log Level: $(LogLevel)"
              echo "Swagger: $(EnableSwagger)"
            displayName: 'Show config'
          - task: AzureWebApp@1
            inputs:
              azureSubscription: 'Azure-ShopConnect'
              appName: '$(WebAppName)'
              package: '$(Pipeline.Workspace)/drop/**/*.zip'
              appSettings: |
                -ASPNETCORE_ENVIRONMENT Development
                -Logging:LogLevel:Default $(LogLevel)
                -EnableSwagger $(EnableSwagger)

- stage: DeployTest
  dependsOn: DeployDev
  condition: succeeded()
  variables:
  - group: ShopConnect-Common
  - group: ShopConnect-Test
  jobs:
  - deployment: DeployTestJob
    environment: Test
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: drop
          - script: |
              echo "Deploying to: $(WebAppName)"
              echo "Log Level: $(LogLevel)"
            displayName: 'Show config'
          - task: AzureWebApp@1
            inputs:
              azureSubscription: 'Azure-ShopConnect'
              appName: '$(WebAppName)'
              package: '$(Pipeline.Workspace)/drop/**/*.zip'
              appSettings: |
                -ASPNETCORE_ENVIRONMENT Test
                -Logging:LogLevel:Default $(LogLevel)
                -EnableSwagger $(EnableSwagger)

- stage: DeployProd
  dependsOn: DeployTest
  condition: succeeded()
  variables:
  - group: ShopConnect-Common
  - group: ShopConnect-Prod
  jobs:
  - deployment: DeployProdJob
    environment: Production
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: drop
          - task: AzureWebApp@1
            inputs:
              azureSubscription: 'Azure-ShopConnect'
              appName: '$(WebAppName)'
              package: '$(Pipeline.Workspace)/drop/**/*.zip'
              appSettings: |
                -ASPNETCORE_ENVIRONMENT Production
                -Logging:LogLevel:Default $(LogLevel)
                -EnableSwagger $(EnableSwagger)
```

**Vérifier les variables déployées**

```bash
# Vérifier la config de chaque env via l'API
for env in dev test prod; do
  echo "=== $env ==="
  curl -s "https://shopconnect-webapp-$env.azurewebsites.net/api/version" | jq .
done
```

---

#### Partie 3 : Visualiser et analyser les logs (55 min)

**Configurer Application Insights**

```bash
# Créer une ressource Application Insights par environnement
for env in dev test prod; do
  az monitor app-insights component create \
    --app "shopconnect-ai-$env" \
    --location westeurope \
    --resource-group shopconnect-rg \
    --kind web \
    --application-type web
  
  # Récupérer la clé d'instrumentation
  KEY=$(az monitor app-insights component show \
    --app "shopconnect-ai-$env" \
    --resource-group shopconnect-rg \
    --query "instrumentationKey" -o tsv)
  
  echo "$env Application Insights Key: $KEY"
done
```

**Ajouter la collecte de logs dans le pipeline**

```yaml
# Ajouter ces steps à votre pipeline de release

# Step 1: Activer les logs détaillés avant déploiement
- task: AzureCLI@2
  displayName: 'Enable verbose logging'
  inputs:
    azureSubscription: 'Azure-ShopConnect'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az webapp log config \
        --name $(WebAppName) \
        --resource-group $(ResourceGroup) \
        --application-logging filesystem \
        --level verbose \
        --web-server-logging filesystem \
        --detailed-error-messages true

# Step 2: Télécharger les logs en cas d'erreur
- task: AzureCLI@2
  displayName: 'Download logs on failure'
  condition: failed()
  inputs:
    azureSubscription: 'Azure-ShopConnect'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      mkdir -p $(Build.ArtifactStagingDirectory)/failure-logs
      
      # Logs App Service
      az webapp log download \
        --name $(WebAppName) \
        --resource-group $(ResourceGroup) \
        --log-file $(Build.ArtifactStagingDirectory)/failure-logs/appservice-logs.zip
      
      # Décompresser et afficher les 200 dernières lignes
      cd $(Build.ArtifactStagingDirectory)/failure-logs
      unzip -o appservice-logs.zip 2>/dev/null || true
      
      echo "=== Recent App Logs ==="
      find . -name "*.txt" -newer appservice-logs.zip -exec tail -50 {} \; 2>/dev/null || \
        echo "No recent log files found"

# Step 3: Publier les logs comme artefact
- task: PublishBuildArtifacts@1
  displayName: 'Publish failure logs'
  condition: failed()
  inputs:
    pathToPublish: '$(Build.ArtifactStagingDirectory)/failure-logs'
    artifactName: 'failure-logs-$(Build.BuildId)'
```

**Script d'analyse des logs post-déploiement**

```bash
# Script: analyze-deployment-logs.sh
#!/bin/bash

WEBAPP_NAME="${1:-shopconnect-webapp-prod}"
RESOURCE_GROUP="${2:-shopconnect-rg}"
LOG_DIR="/tmp/deployment-logs-$(date +%Y%m%d%H%M%S)"

mkdir -p "$LOG_DIR"

echo "====================================="
echo "DEPLOYMENT LOG ANALYSIS"
echo "App: $WEBAPP_NAME"
echo "Time: $(date)"
echo "====================================="

# Télécharger les logs
az webapp log download \
  --name "$WEBAPP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --log-file "$LOG_DIR/logs.zip" 2>/dev/null

if [ -f "$LOG_DIR/logs.zip" ]; then
  cd "$LOG_DIR"
  unzip -o logs.zip > /dev/null 2>&1
  
  # Analyser les erreurs HTTP 5xx
  echo ""
  echo "=== HTTP 5xx Errors (last hour) ==="
  find . -name "*.log" -exec grep -l "HTTP/1.1\" 5" {} \; | while read f; do
    echo "File: $f"
    grep "HTTP/1.1\" 5" "$f" | tail -20
  done
  
  # Analyser les exceptions
  echo ""
  echo "=== Application Exceptions ==="
  find . -name "*.txt" -exec grep -l "Exception\|Error" {} \; | while read f; do
    echo "File: $f"
    grep -E "(Exception|Error|FATAL)" "$f" | tail -20
  done
  
  # Résumé
  echo ""
  echo "=== Summary ==="
  ERRORS=$(find . -name "*.log" -exec grep -c "HTTP/1.1\" 5" {} + 2>/dev/null | \
    awk -F: '{sum += $2} END {print sum}')
  echo "5xx Errors: ${ERRORS:-0}"
  
  EXCEPTIONS=$(find . -name "*.txt" -exec grep -c "Exception" {} + 2>/dev/null | \
    awk -F: '{sum += $2} END {print sum}')
  echo "Exceptions: ${EXCEPTIONS:-0}"
else
  echo "No logs available (check Azure CLI permissions)"
fi

echo ""
echo "Logs saved to: $LOG_DIR"
```

**Visualiser les logs dans Azure DevOps**

```
1. Aller dans une exécution de pipeline
2. Cliquer sur un job
3. Voir les étapes et leurs logs

Navigation dans les logs:
├─ [Chercher]  → Ctrl+F dans les logs
├─ [Télécharger] → Télécharger les logs complets
├─ [Timestamps] → Activer les timestamps
└─ [Niveaux]   → Filtrer par niveau (error, warning, info)

Télécharger les logs d'un pipeline:
1. Pipeline run → [...] → Download logs
2. Fichier ZIP avec un répertoire par job/step
```

---

#### Partie 4 : Rapport de release (50 min)

**Créer un rapport de release automatisé**

```bash
cat > scripts/generate-release-report.ps1 << 'EOF'
param(
    [string]$Organization,
    [string]$Project,
    [string]$Pat,
    [string]$BuildId,
    [string]$OutputPath = "release-report.md"
)

$base64Pat = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$headers = @{
    Authorization = "Basic $base64Pat"
    "Content-Type" = "application/json"
}

$baseUrl = "https://dev.azure.com/$Organization/$Project/_apis"

# 1. Récupérer les informations du build
$build = Invoke-RestMethod `
    -Uri "$baseUrl/build/builds/$BuildId?api-version=7.0" `
    -Headers $headers

# 2. Récupérer les work items liés
$workItems = Invoke-RestMethod `
    -Uri "$baseUrl/build/builds/$BuildId/workitems?api-version=7.0" `
    -Headers $headers

# 3. Récupérer les résultats de tests
$testRuns = Invoke-RestMethod `
    -Uri "$baseUrl/test/runs?buildId=$BuildId&api-version=7.0" `
    -Headers $headers

# 4. Récupérer les artefacts
$artifacts = Invoke-RestMethod `
    -Uri "$baseUrl/build/builds/$BuildId/artifacts?api-version=7.0" `
    -Headers $headers

# 5. Générer le rapport Markdown
$report = @"
# Release Report

**Date:** $(Get-Date -Format "dd/MM/yyyy HH:mm")
**Build:** $($build.buildNumber)
**Branch:** $($build.sourceBranch)
**Commit:** $($build.sourceVersion.Substring(0, 8))
**Status:** $($build.result)

---

## 📦 What's in this Release

### User Stories & Features
$(
    $workItems.value | Where-Object { $_.type -in @("User Story", "Feature") } | ForEach-Object {
        "- [$($_.id)] $($_.title)"
    } | Join-String -Separator "`n"
)

### Bug Fixes
$(
    $workItems.value | Where-Object { $_.type -eq "Bug" } | ForEach-Object {
        "- 🐛 [$($_.id)] $($_.title)"
    } | Join-String -Separator "`n"
)

---

## 🧪 Test Results

| Metric | Value |
|--------|-------|
| Total Tests | $($testRuns.value.totalTests | Measure-Object -Sum | Select-Object -ExpandProperty Sum) |
| Passed | $($testRuns.value.passedTests | Measure-Object -Sum | Select-Object -ExpandProperty Sum) |
| Failed | $($testRuns.value.unanalyzedTests | Measure-Object -Sum | Select-Object -ExpandProperty Sum) |

---

## 📂 Artifacts

$(
    $artifacts.value | ForEach-Object {
        "- **$($_.name)**: $($_.resource.downloadUrl)"
    } | Join-String -Separator "`n"
)

---

## 🚀 Deployment Targets

| Environment | Status | URL |
|-------------|--------|-----|
| Development | ✅ Deployed | https://shopconnect-webapp-dev.azurewebsites.net |
| Test | ✅ Deployed | https://shopconnect-webapp-test.azurewebsites.net |
| Production | ⏳ Pending approval | https://shopconnect-webapp-prod.azurewebsites.net |

---

*Generated automatically by Azure DevOps Pipeline*
"@

$report | Out-File -FilePath $OutputPath -Encoding UTF8
Write-Host "Report generated: $OutputPath"
EOF

git add scripts/
git commit -m "ci: add release report script"
git push origin main
```

---

#### Livrables attendus

✅ Pipeline avec versioning automatique GitVersion
✅ Groupes de variables par environnement configurés
✅ Application Insights configuré sur chaque environnement
✅ Script de collecte de logs en cas d'échec
✅ Rapport de release généré automatiquement

---

#### Questions de validation

1. **Quelle est la différence entre MAJOR, MINOR et PATCH en SemVer ?**

2. **Pourquoi est-il important de ne jamais stocker de secrets directement dans le YAML ?**

3. **Comment récupérer les logs d'un déploiement qui a échoué dans Azure ?**

4. **Quelle est la différence entre `continueOnError: true` et `condition: always()` ?**

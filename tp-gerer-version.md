# TP7 : Gérer les versions et visualiser les logs

**Durée estimée : 3h30**

## Objectifs
- Mettre en place le versioning automatique
- Analyser et visualiser les logs de déploiement
- Implémenter la gestion d'erreurs

---

## Partie 1 : Versioning automatique (50 min)

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

    - task: gitversion-setup@4.5.0
      displayName: Install GitVersion
      inputs:
        versionSpec: '6.7.x'

    - task: gitversion-execute@4.5.0
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

    - task: gitversion-setup@4.5.0
      inputs:
        versionSpec: '6.7.x'

    - task: gitversion-execute@4.5.0
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

## Partie 2 : Variables par environnement (45 min)

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

## Partie 3 : Visualiser et analyser les logs (55 min)

### Exercice 1 : Explorer les logs d'un pipeline réussi (10 min)

**Objectif :** Se familiariser avec la navigation dans les logs Azure DevOps.

```
1. Aller dans Pipelines → votre pipeline CI → dernière exécution réussie

2. Cliquer sur le job "BuildJob"

3. Explorer chaque étape :
   ├─ Restore NuGet packages  → Combien de packages restaurés ?
   ├─ Build solution          → Durée de la compilation ?
   ├─ Run unit tests          → Combien de tests exécutés ?
   └─ Publish artifacts       → Taille de l'artefact publié ?

4. Activer les timestamps :
   Bouton [Timestamps] en haut à droite des logs
   → Observer le temps passé entre chaque ligne

5. Utiliser la recherche :
   Ctrl+F dans les logs
   → Rechercher "warning"
   → Rechercher "error"
   → Combien de warnings y a-t-il ?

6. Télécharger les logs complets :
   [...] en haut à droite → Download logs
   → Ouvrir le ZIP
   → Observer la structure :
      logs/
      ├─ 1_Build Stage/
      │  ├─ 1_Checkout source code.log
      │  ├─ 2_Restore NuGet packages.log
      │  ├─ 3_Build solution.log
      │  ├─ 4_Run unit tests.log
      │  └─ 5_Publish artifacts.log
      └─ ...
```

**Questions :**
- Quelle étape prend le plus de temps ?
- Y a-t-il des warnings dans les logs de build ?
- Quelle est la taille du fichier de log de l'étape "Run unit tests" ?

---

### Exercice 2 : Simuler un échec et analyser les logs (20 min)

**Objectif :** Introduire volontairement une régression, observer l'échec dans les logs, identifier la cause et corriger.

#### Étape 1 — Introduire le bug

```bash
git checkout develop

# Modifier le service pour introduire un bug
cat > src/ShopConnect.API/Services/ProductService.cs << 'EOF'
using ShopConnect.API.Models;

namespace ShopConnect.API.Services;

public class ProductService : IProductService
{
    private static readonly List<Product> _products = new()
    {
        new Product { Id = 1, Name = "Laptop Pro",    Price = 1299.99m, Category = "Electronics" },
        new Product { Id = 2, Name = "Wireless Mouse", Price = 39.99m,  Category = "Accessories" },
        new Product { Id = 3, Name = "USB-C Hub",     Price = 59.99m,  Category = "Accessories" }
    };

    private static int _nextId = 4;

    public IEnumerable<Product> GetAll()
    {
        // BUG SIMULÉ : lève une exception
        throw new NotImplementedException("Feature temporarily disabled");
    }

    public Product? GetById(int id) =>
        _products.FirstOrDefault(p => p.Id == id);

    public Product Create(Product product)
    {
        product.Id = _nextId++;
        _products.Add(product);
        return product;
    }

    public bool Delete(int id)
    {
        var product = GetById(id);
        if (product == null) return false;
        _products.Remove(product);
        return true;
    }
}
EOF

git add .
git commit -m "perf: temporary refactor (introduces regression)"
git push origin develop
```

#### Étape 2 — Observer l'échec dans Azure DevOps

```
Le pipeline CI se déclenche automatiquement.

Dans Pipelines → ShopConnect CI → exécution en cours :

1. Observer le badge rouge sur l'étape "Run unit tests"

2. Cliquer sur l'étape en rouge

3. Dans les logs, repérer :
   ┌─────────────────────────────────────────────────────┐
   │ ##[error]Error Message:                             │
   │ System.NotImplementedException:                     │
   │   Feature temporarily disabled                      │
   │                                                     │
   │    at ShopConnect.API.Services.ProductService       │
   │       .GetAll()                                     │
   │    at ShopConnect.Tests.ProductServiceTests         │
   │       .GetAll_ReturnsAllProducts()                  │
   │                                                     │
   │ Failed tests:                                       │
   │   GetAll_ReturnsAllProducts                         │
   │   GetAll_ReturnsAtLeastThreeProducts                │
   │   Create_ProductIsRetrievableAfterCreation          │
   │                                                     │
   │ Total tests: 10  |  Passed: 7  |  Failed: 3        │
   └─────────────────────────────────────────────────────┘

4. Aller dans l'onglet "Tests" de l'exécution :
   → Observer les 3 tests échoués en rouge
   → Cliquer sur un test échoué
   → Lire le stack trace complet

5. Aller dans l'onglet "Summary" :
   → Observer le message d'erreur global
   → Voir quelle étape a bloqué le pipeline
```

**Questions à répondre avant de corriger :**
- Quelle méthode exacte lève l'exception ?
- Combien de tests sont impactés par ce bug ?
- Est-ce que le pipeline est allé jusqu'à la publication des artefacts ?
- À quelle ligne du code source se trouve l'erreur ?

#### Étape 3 — Corriger et vérifier

```bash
# Corriger le service
cat > src/ShopConnect.API/Services/ProductService.cs << 'EOF'
using ShopConnect.API.Models;

namespace ShopConnect.API.Services;

public class ProductService : IProductService
{
    private static readonly List<Product> _products = new()
    {
        new Product { Id = 1, Name = "Laptop Pro",    Price = 1299.99m, Category = "Electronics" },
        new Product { Id = 2, Name = "Wireless Mouse", Price = 39.99m,  Category = "Accessories" },
        new Product { Id = 3, Name = "USB-C Hub",     Price = 59.99m,  Category = "Accessories" }
    };

    private static int _nextId = 4;

    public IEnumerable<Product> GetAll() => _products;

    public Product? GetById(int id) =>
        _products.FirstOrDefault(p => p.Id == id);

    public Product Create(Product product)
    {
        product.Id = _nextId++;
        _products.Add(product);
        return product;
    }

    public bool Delete(int id)
    {
        var product = GetById(id);
        if (product == null) return false;
        _products.Remove(product);
        return true;
    }
}
EOF

git add .
git commit -m "fix(products): restore GetAll implementation

Root cause: NotImplementedException introduced in previous commit
Fix: Restore original implementation returning all products
Impacts: 3 unit tests were failing

Fixes #[numéro du bug si créé dans Boards]"

git push origin develop
```

```
Vérifier dans Azure DevOps :
→ Le nouveau build est vert ✅
→ Onglet Tests : 10/10 passés
→ Comparer les deux exécutions côte à côte :
  Pipelines → votre pipeline → [icône comparaison]
```

---

### Exercice 3 : Collecter des diagnostics via le pipeline (25 min)

**Objectif :** Ajouter des étapes de diagnostic dans le pipeline de release pour collecter les informations de l'application déployée et les rendre disponibles comme artefacts.

#### Étape 1 — Ajouter les étapes de diagnostic au pipeline de release

```bash
# Modifier azure-pipelines-release.yml
# Ajouter les étapes suivantes dans chaque stage de déploiement
# après la tâche AzureWebApp@1
```

Voici les étapes à ajouter dans le stage `DeployDev` (et à répliquer pour Test et Prod) :

```yaml
# ─── À ajouter après la tâche AzureWebApp@1 ───────────────────────

- task: PowerShell@2
  displayName: 'Collect app diagnostics'
  condition: always()
  inputs:
    targetType: 'inline'
    script: |
      $baseUrl = "$(DeployStep.AppServiceApplicationUrl)"
      Write-Host "##[group]Application Diagnostics - $(Environment)"

      # ── Health check ──────────────────────────────────────────
      Write-Host ""
      Write-Host "=== Health Check ==="
      try {
        $health = Invoke-RestMethod `
          -Uri "$baseUrl/health" `
          -TimeoutSec 10
        Write-Host "  Status      : $($health.status)"
        Write-Host "  Version     : $($health.version)"
        Write-Host "  Environment : $($health.environment)"
        Write-Host "  Timestamp   : $($health.timestamp)"
      } catch {
        Write-Warning "  Health endpoint unreachable: $_"
      }

      # ── Test des endpoints ────────────────────────────────────
      Write-Host ""
      Write-Host "=== Endpoint Status ==="
      $endpoints = @(
        @{ path = "/api/products";   method = "GET"; expectedCode = 200 },
        @{ path = "/api/products/1"; method = "GET"; expectedCode = 200 },
        @{ path = "/api/products/0"; method = "GET"; expectedCode = 404 }
      )

      $allOk = $true
      foreach ($ep in $endpoints) {
        try {
          $r = Invoke-WebRequest `
            -Uri "$baseUrl$($ep.path)" `
            -Method $ep.method `
            -UseBasicParsing `
            -TimeoutSec 10
          $icon = if ($r.StatusCode -eq $ep.expectedCode) { "✅" } else { "⚠️" }
          Write-Host "  $icon $($ep.method) $($ep.path) → $($r.StatusCode)"
          if ($r.StatusCode -ne $ep.expectedCode) { $allOk = $false }
        } catch {
          $code = $_.Exception.Response.StatusCode.value__
          $icon = if ($code -eq $ep.expectedCode) { "✅" } else { "❌" }
          Write-Host "  $icon $($ep.method) $($ep.path) → $code"
          if ($code -ne $ep.expectedCode) { $allOk = $false }
        }
      }

      if ($allOk) {
        Write-Host ""
        Write-Host "✅ All endpoints responding as expected"
      } else {
        Write-Warning "⚠️ Some endpoints returned unexpected status codes"
      }

      Write-Host "##[endgroup]"

- task: PowerShell@2
  displayName: 'Generate diagnostic report'
  condition: always()
  inputs:
    targetType: 'inline'
    script: |
      $baseUrl  = "$(DeployStep.AppServiceApplicationUrl)"
      $env      = "$(Environment)"
      $dir      = "$(Build.ArtifactStagingDirectory)/diagnostics"
      New-Item -ItemType Directory -Path $dir -Force | Out-Null

      # ── Récupérer les infos health ────────────────────────────
      $healthStatus = "UNREACHABLE"
      $appVersion   = "unknown"
      $appEnv       = "unknown"
      try {
        $health       = Invoke-RestMethod -Uri "$baseUrl/health" -TimeoutSec 10
        $healthStatus = $health.status
        $appVersion   = $health.version
        $appEnv       = $health.environment
      } catch {}

      # ── Construire le rapport ─────────────────────────────────
      $report = @"
========================================
DEPLOYMENT DIAGNOSTIC REPORT
========================================
Generated    : $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
Build        : $(Build.BuildNumber)
Branch       : $(Build.SourceBranchName)
Commit       : $(Build.SourceVersion)
Pipeline     : $(Build.DefinitionName)
Agent        : $(Agent.Name)
Environment  : $env
App URL      : $baseUrl
----------------------------------------
APPLICATION STATUS
----------------------------------------
Health       : $healthStatus
Version      : $appVersion
Environment  : $appEnv
----------------------------------------
ENDPOINT CHECKS
----------------------------------------
"@

      # ── Tester les endpoints ──────────────────────────────────
      $endpoints = @(
        @{ path = "/api/products";   expectedCode = 200 },
        @{ path = "/api/products/1"; expectedCode = 200 },
        @{ path = "/api/products/0"; expectedCode = 404 }
      )

      foreach ($ep in $endpoints) {
        try {
          $r    = Invoke-WebRequest `
            -Uri "$baseUrl$($ep.path)" `
            -UseBasicParsing -TimeoutSec 10
          $icon = if ($r.StatusCode -eq $ep.expectedCode) { "PASS" } else { "WARN" }
          $report += "`n[$icon] GET $($ep.path) → $($r.StatusCode)"
        } catch {
          $code = $_.Exception.Response.StatusCode.value__
          $icon = if ($code -eq $ep.expectedCode) { "PASS" } else { "FAIL" }
          $report += "`n[$icon] GET $($ep.path) → $code"
        }
      }

      $report += "`n`n========================================"

      # ── Sauvegarder et afficher ───────────────────────────────
      $file = "$dir/report-$env-$(Build.BuildId).txt"
      $report | Out-File -FilePath $file -Encoding UTF8
      Write-Host $report
      Write-Host ""
      Write-Host "Report saved: $file"

- task: PublishBuildArtifacts@1
  displayName: 'Publish diagnostic report'
  condition: always()
  inputs:
    pathToPublish: '$(Build.ArtifactStagingDirectory)/diagnostics'
    artifactName: 'diagnostic-$(Environment)-$(Build.BuildId)'
```

#### Étape 2 — Déclencher le pipeline et consulter les rapports

```
1. Pousser un changement pour déclencher le pipeline :

   git add azure-pipelines-release.yml
   git commit -m "ci: add diagnostic steps to release pipeline"
   git push origin main

2. Suivre l'exécution dans Azure DevOps

3. Consulter les diagnostics en ligne :
   → Cliquer sur le stage "DeployDev"
   → Cliquer sur l'étape "Collect app diagnostics"
   → Observer le groupe de logs "Application Diagnostics"

4. Télécharger le rapport :
   Pipeline run → Artifacts
   → diagnostic-Development-[BuildId]/
   → report-Development-[BuildId].txt
   → Ouvrir le fichier
```

#### Étape 3 — Simuler un déploiement en échec et comparer les rapports

```bash
# Introduire une erreur uniquement au runtime
# (le build passe, mais l'app plante au démarrage)

cat > src/ShopConnect.API/Program.cs << 'EOF'
using ShopConnect.API.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddSingleton<IProductService, ProductService>();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

// BUG RUNTIME : exception au démarrage
throw new Exception("Simulated startup failure");

app.Run();
public partial class Program { }
EOF

git add .
git commit -m "test: simulate runtime startup failure"
git push origin main
```

```
Observer dans Azure DevOps :
→ Le build CI réussit (le bug est au runtime, pas à la compilation)
→ Le déploiement sur Dev réussit (l'app est uploadée)
→ L'étape "Collect app diagnostics" affiche :
   Health : UNREACHABLE  ← l'app ne démarre pas
→ L'étape "Health check" échoue → le stage est en erreur

Comparer les deux rapports téléchargés :
  report-Development-125.txt  → Health: healthy   ✅
  report-Development-126.txt  → Health: UNREACHABLE ❌

→ Différence visible immédiatement dans les artefacts
```

```bash
# Corriger immédiatement
git revert HEAD
git push origin main

# Observer le pipeline redevenir vert
```

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

# TP6 : Automatiser les déploiements et les valider

**Durée estimée : 90 minutes**

#### Objectifs
- Implémenter un pipeline de déploiement conditionnel
- Configurer des quality gates automatiques
- Tester les approbations manuelles
- Mettre en place un rollback automatique

---

#### Partie 1 : Pipeline conditionnel selon la branche (25 min)

**Créer le pipeline**

```bash
cd C:\Projects\ShopConnect

cat > azure-pipelines-conditional.yml << 'EOF'
trigger:
  branches:
    include:
    - main
    - develop
    - feature/*
    - release/*

resources:
  pipelines:
  - pipeline: buildPipeline
    source: 'ShopConnect-CI'
    trigger:
      branches:
        include:
        - main
        - develop

variables:
  azureSubscription: 'Azure-ShopConnect'

stages:
# Build (toutes les branches)
- stage: Build
  displayName: 'Build'
  jobs:
  - job: BuildJob
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - script: |
        echo "Building branch: $(Build.SourceBranchName)"
        echo "Reason: $(Build.Reason)"
      displayName: 'Build Info'

# Deploy Dev: feature/* et develop
- stage: DeployDev
  displayName: 'Deploy → Dev'
  dependsOn: Build
  condition: |
    and(
      succeeded('Build'),
      or(
        startsWith(variables['Build.SourceBranch'], 'refs/heads/feature/'),
        eq(variables['Build.SourceBranch'], 'refs/heads/develop')
      ),
      ne(variables['Build.Reason'], 'PullRequest')
    )
  jobs:
  - deployment: DeployDevJob
    displayName: 'Deploy Dev'
    environment: 'Development'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: |
              echo "✓ Deploying to Dev"
              echo "Branch: $(Build.SourceBranchName)"
            displayName: 'Deploy to Dev'

# Deploy Test: develop et release/*
- stage: DeployTest
  displayName: 'Deploy → Test'
  dependsOn: Build
  condition: |
    and(
      succeeded('Build'),
      or(
        eq(variables['Build.SourceBranch'], 'refs/heads/develop'),
        startsWith(variables['Build.SourceBranch'], 'refs/heads/release/')
      )
    )
  jobs:
  - deployment: DeployTestJob
    displayName: 'Deploy Test'
    environment: 'Test'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: |
              echo "✓ Deploying to Test"
            displayName: 'Deploy to Test'

# Deploy Prod: main uniquement avec approbation
- stage: DeployProd
  displayName: 'Deploy → Production'
  dependsOn:
  - Build
  - DeployTest
  condition: |
    and(
      succeeded('Build'),
      in(dependencies.DeployTest.result, 'Succeeded', 'Skipped'),
      eq(variables['Build.SourceBranch'], 'refs/heads/main'),
      ne(variables['Build.Reason'], 'Schedule')
    )
  jobs:
  - deployment: DeployProdJob
    displayName: 'Deploy Production'
    environment: 'Production'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - script: |
              echo "✅ Deploying to Production!"
              echo "Build: $(Build.BuildNumber)"
            displayName: 'Deploy to Prod'
EOF

git add azure-pipelines-conditional.yml
git commit -m "ci: add conditional deployment pipeline"
git push origin main
```

**Tester les conditions :**

```bash
# Test 1: Push depuis develop → Dev + Test
git checkout develop
echo "test" >> README.md
git add . && git commit -m "test: trigger dev and test deploy"
git push origin develop

# Résultat attendu:
# ✓ Build
# ✓ Deploy Dev
# ✓ Deploy Test
# ✗ Deploy Prod (condition non remplie)

# Test 2: Push depuis main → Prod avec approbation
git checkout main
git merge develop
git push origin main

# Résultat attendu:
# ✓ Build
# ✗ Deploy Dev (condition: pas depuis main)
# ✓ Deploy Test (condition: ok depuis main... non! → Skipped)
# ⏸ Deploy Prod (attend approbation)
```

---

#### Partie 2 : Quality Gates automatiques (25 min)

**Ajouter des checks à l'environnement**

```
Pipelines → Environments → Production → [...] → Approvals and checks

1. [+ Add Check]
   Type: Required template
   
   ┌────────────────────────────────────────────┐
   │ Allowed templates                          │
   ├────────────────────────────────────────────┤
   │                                            │
   │ Repository: ShopConnect                    │
   │ Ref: refs/heads/main                       │
   │ Path: /templates/production-deploy.yml     │
   │                                            │
   │ [Add]                                      │
   └────────────────────────────────────────────┘

2. [+ Add Check]
   Type: Invoke REST API
   
   ┌────────────────────────────────────────────┐
   │ Invoke REST API                            │
   ├────────────────────────────────────────────┤
   │                                            │
   │ Connection: Generic-Connection             │
   │ Method: GET                                │
   │ URL suffix: /api/health                    │
   │ Headers: Content-Type: application/json   │
   │ Body: (empty for GET)                      │
   │                                            │
   │ Success criteria:                          │
   │ eq(root['status'], 'healthy')              │
   │                                            │
   │ Control options:                           │
   │ Timeout: 5 minutes                         │
   │ Re-evaluation: every 1 minute              │
   │                                            │
   │ [Add]                                      │
   └────────────────────────────────────────────┘
```

**Créer le template de déploiement production**

```bash
mkdir -p templates

cat > templates/production-deploy.yml << 'EOF'
# templates/production-deploy.yml

parameters:
- name: webAppName
  type: string
- name: azureSubscription
  type: string
- name: packagePath
  type: string
  default: '$(Pipeline.Workspace)/**/*.zip'

stages:
- stage: DeployProduction
  jobs:
  - deployment: DeployProdJob
    environment: Production
    strategy:
      runOnce:
        deploy:
          steps:

          - script: |
              echo "========================================"
              echo "PRODUCTION DEPLOYMENT CHECKLIST"
              echo "========================================"
            displayName: 'Pre-deployment checklist'

          - task: AzureWebApp@1
            inputs:
              azureSubscription: '${{ parameters.azureSubscription }}'
              appType: 'webAppLinux'
              appName: '${{ parameters.webAppName }}'
              package: '${{ parameters.packagePath }}'

          - task: PowerShell@2
            inputs:
              targetType: inline
              script: |
                Write-Host "Health check"
EOF
```
* Créer un nouveau fichier de pipeline :

```
cat > azure-pipelines-use-tempalte.yml << 'EOF'

git add .
git commit -m "ci: add production deploy template"
git push origin main
```

---

#### Partie 3 : Rollback automatique (20 min)

**Créer le pipeline avec rollback**

```bash
cat > azure-pipelines-rollback.yml << 'EOF'
trigger: none

resources:
  pipelines:
  - pipeline: buildPipeline
    source: 'ShopConnect-CI'

variables:
  azureSubscription: 'Azure-ShopConnect'
  webAppName: 'shopconnect-webapp-prod'
  resourceGroup: 'shopconnect-rg'

stages:
- stage: DeployWithRollback
  displayName: 'Deploy with Auto-Rollback'
  jobs:
  - deployment: DeployProdJob
    environment: 'Production'
    pool:
      vmImage: 'ubuntu-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          # Étape 1: Sauvegarder la version actuelle
          - task: AzureCLI@2
            displayName: 'Tag current deployment (rollback point)'
            inputs:
              azureSubscription: '$(azureSubscription)'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                echo "Current deployment tagged as rollback point"
                TIMESTAMP=$(date +%Y%m%d%H%M%S)
                echo "##vso[task.setvariable variable=rollbackTimestamp]$TIMESTAMP"
                echo "Rollback timestamp: $TIMESTAMP"
          
          # Étape 2: Déployer la nouvelle version
          - download: buildPipeline
            artifact: drop
          
          - task: AzureWebApp@1
            displayName: 'Deploy new version'
            inputs:
              azureSubscription: '$(azureSubscription)'
              appType: 'webAppLinux'
              appName: '$(webAppName)'
              package: '$(Pipeline.Workspace)/buildPipeline/drop/**/*.zip'
        
        postRouteTraffic:
          steps:
          # Étape 3: Vérifier la santé
          - task: PowerShell@2
            displayName: 'Health validation (auto-rollback on failure)'
            inputs:
              targetType: 'inline'
              script: |
                $url = "https://$(webAppName).azurewebsites.net/health"
                $maxRetries = 6
                $success = $false
                
                for ($i = 1; $i -le $maxRetries; $i++) {
                  Write-Host "Attempt $i/$maxRetries - Checking $url"
                  Start-Sleep -Seconds 10
                  
                  try {
                    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
                    if ($r.StatusCode -eq 200) {
                      $success = $true
                      Write-Host "✅ Health check OK!"
                      break
                    }
                  } catch {
                    Write-Host "  Failed: $_"
                  }
                }
                
                if (-not $success) {
                  Write-Error "❌ Health checks failed. Triggering rollback..."
                  exit 1
                }
        
        on:
          failure:
            steps:
            - task: AzureCLI@2
              displayName: '⚠️ AUTO-ROLLBACK'
              inputs:
                azureSubscription: '$(azureSubscription)'
                scriptType: 'bash'
                scriptLocation: 'inlineScript'
                inlineScript: |
                  echo "⚠️  DEPLOYMENT FAILED - INITIATING ROLLBACK"
                  echo "Timestamp: $(rollbackTimestamp)"
                  
                  # Redéployer la version précédente depuis les slots Azure
                  az webapp deployment slot swap \
                    --name $(webAppName) \
                    --resource-group $(resourceGroup) \
                    --slot staging \
                    --target-slot production || \
                  echo "Slot swap not available - manual intervention required"
                  
                  echo "Rollback completed. Please verify the application."
EOF

git add azure-pipelines-rollback.yml
git commit -m "ci: add pipeline with auto-rollback"
git push origin main
```

---

#### Partie 4 : Notification de déploiement (20 min)

**Configurer les notifications projet**

```
Project Settings → Notifications → New subscription

Subscription 1 - Deployment success:
Event: Release deployment completed
Delivery: Send email
Filter: 
  - Environment name: Production
  - Status: Succeeded
Recipients: team@contoso.com

Subscription 2 - Deployment failure:
Event: Release deployment completed
Delivery: Send email
Filter:
  - Status: Failed
Recipients: oncall@contoso.com, devlead@contoso.com
```

**Ajouter la notification Teams dans le pipeline**

```yaml
# À ajouter dans votre pipeline
- task: PowerShell@2
  displayName: 'Notify deployment result'
  condition: always()
  inputs:
    targetType: 'inline'
    script: |
      $status = "$(Agent.JobStatus)"
      $isSuccess = $status -eq "Succeeded"
      $color = if ($isSuccess) { "00FF00" } else { "FF0000" }
      $icon = if ($isSuccess) { "✅" } else { "❌" }
      
      $card = @{
        "@type" = "MessageCard"
        "@context" = "https://schema.org/extensions"
        "themeColor" = $color
        "summary" = "Deployment $status"
        "title" = "$icon ShopConnect - Production Deployment $status"
        "sections" = @(
          @{
            "facts" = @(
              @{ "name" = "Build"; "value" = "$(Build.BuildNumber)" },
              @{ "name" = "Branch"; "value" = "$(Build.SourceBranchName)" },
              @{ "name" = "Triggered by"; "value" = "$(Build.RequestedFor)" },
              @{ "name" = "Status"; "value" = $status }
            )
          }
        )
      }
      
      Invoke-RestMethod `
        -Uri "$(TeamsWebhookUrl)" `
        -Method Post `
        -Body ($card | ConvertTo-Json -Depth 5) `
        -ContentType "application/json"
      
      Write-Host "Notification sent!"
```

---

#### Livrables attendus

✅ Pipeline conditionnel fonctionnel (3 branches → 3 comportements)
✅ Quality gates configurés sur l'environnement Production
✅ Template de déploiement production créé
✅ Rollback automatique implémenté et testé
✅ Notifications configurées (email ou Teams)

---

#### Questions de validation

1. **Quelle est la différence entre `condition: succeeded()` et `condition: always()` ?**

2. **Comment bloquer un déploiement automatique en production depuis une branche feature ?**

3. **Qu'est-ce qu'un quality gate et pourquoi est-il important ?**

4. **Dans quel cas un rollback automatique est-il préférable à un rollback manuel ?**

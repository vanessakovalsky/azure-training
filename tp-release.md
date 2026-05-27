# TP5 : Mettre en place un déploiement multi-environnements

**Durée estimée : 90 minutes**

#### Objectifs
- Créer des environnements (Dev, Test, Prod)
- Créer un release pipeline multi-stage
- Configurer les approbations
- Déployer vers Azure App Service
- Tester le déploiement complet

---

#### Partie 1 : Préparer l'infrastructure Azure (20 min)

**Créer les ressources Azure**

```bash
# Se connecter à Azure
az login

# Créer un resource group
az group create \
  --name shopconnect-rg \
  --location westeurope

# Créer un App Service Plan
az appservice plan create \
  --name shopconnect-plan \
  --resource-group shopconnect-rg \
  --sku B1 \
  --is-linux

# Créer 3 Web Apps (Dev, Test, Prod)
az webapp create \
  --name shopconnect-webapp-dev \
  --resource-group shopconnect-rg \
  --plan shopconnect-plan \
  --runtime "DOTNET|8.0"

az webapp create \
  --name shopconnect-webapp-test \
  --resource-group shopconnect-rg \
  --plan shopconnect-plan \
  --runtime "DOTNET|8.0"

az webapp create \
  --name shopconnect-webapp-prod \
  --resource-group shopconnect-rg \
  --plan shopconnect-plan \
  --runtime "DOTNET|8.0"

# Vérifier
az webapp list --resource-group shopconnect-rg --output table
```

**Créer une Service Connection**

```
1. Azure DevOps → Project Settings → Service connections
2. [New service connection]
3. Azure Resource Manager
4. Service principal (automatic)
5. Subscription: [Your Azure subscription]
   Resource group: shopconnect-rg
   Service connection name: Azure-ShopConnect
6. [Save]
```

---

#### Partie 2 : Créer les environnements (15 min)

**Créer les environnements dans Azure DevOps**

```
1. Pipelines → Environments → [New environment]

Environment 1:
Name: Development
Description: Development environment (auto-deploy)
[Create]

Environment 2:
Name: Test
Description: Test environment (auto-deploy)
[Create]

Environment 3:
Name: Production
Description: Production environment (manual approval)
[Create]
```

**Configurer les approbations pour Production**

```
Production → [...] → Approvals and checks

1. [Approvals]
   Approvers: Vous-même
   Minimum approvers: 1
   Instructions: "Please verify all tests passed before approving"
   [Create]

2. [Business hours]  (optionnel)
   Time zone: (UTC+01:00) Brussels, Copenhagen, Madrid, Paris
   Days: Monday to Friday
   Start time: 09:00
   End time: 18:00
   [Create]
```

---

#### Partie 3 : Créer le pipeline multi-stage YAML (30 min)

**Créer le fichier de release**

```bash
cd C:\Projects\ShopConnect

cat > azure-pipelines-release.yml << 'EOF'
trigger: none  # Déclenchement manuel ou via pipeline build

resources:
  pipelines:
  - pipeline: buildPipeline
    source: 'ShopConnect-CI'
    trigger:
      branches:
        include:
        - main

variables:
  azureSubscription: 'Azure-ShopConnect'
  resourceGroup: 'shopconnect-rg'

stages:
# Stage 1: Deploy to Dev
- stage: DeployDev
  displayName: 'Deploy to Development'
  jobs:
  - deployment: DeployDevJob
    displayName: 'Deploy to Dev Environment'
    environment: 'Development'
    pool:
      vmImage: 'ubuntu-latest'
    variables:
      webAppName: 'shopconnect-webapp-dev'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: buildPipeline
            artifact: drop
            displayName: 'Download Build Artifact'
          
          - task: AzureWebApp@1
            displayName: 'Deploy to Dev Web App'
            inputs:
              azureSubscription: '$(azureSubscription)'
              appType: 'webAppLinux'
              appName: '$(webAppName)'
              package: '$(Pipeline.Workspace)/buildPipeline/drop/**/*.zip'
              deploymentMethod: 'zipDeploy'
          
          - task: PowerShell@2
            displayName: 'Health Check - Dev'
            inputs:
              targetType: 'inline'
              script: |
                Write-Host "Waiting 30 seconds for app to start..."
                Start-Sleep -Seconds 30
                
                $url = "https://$(webAppName).azurewebsites.net"
                Write-Host "Checking: $url"
                
                try {
                  $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
                  if ($response.StatusCode -eq 200) {
                    Write-Host "✓ Dev deployment successful!"
                  } else {
                    Write-Error "Health check failed - Status: $($response.StatusCode)"
                    exit 1
                  }
                } catch {
                  Write-Error "Health check failed - Error: $_"
                  exit 1
                }

# Stage 2: Deploy to Test
- stage: DeployTest
  displayName: 'Deploy to Test'
  dependsOn: DeployDev
  condition: succeeded()
  jobs:
  - deployment: DeployTestJob
    displayName: 'Deploy to Test Environment'
    environment: 'Test'
    pool:
      vmImage: 'ubuntu-latest'
    variables:
      webAppName: 'shopconnect-webapp-test'
    strategy:
      runOnce:
        deploy:
          steps:
          - download: buildPipeline
            artifact: drop
          
          - task: AzureWebApp@1
            displayName: 'Deploy to Test Web App'
            inputs:
              azureSubscription: '$(azureSubscription)'
              appType: 'webAppLinux'
              appName: '$(webAppName)'
              package: '$(Pipeline.Workspace)/buildPipeline/drop/**/*.zip'
          
          - task: PowerShell@2
            displayName: 'Run Smoke Tests'
            inputs:
              targetType: 'inline'
              script: |
                Start-Sleep -Seconds 30
                
                $baseUrl = "https://$(webAppName).azurewebsites.net"
                $endpoints = @("/", "/api/products")
                
                $allPassed = $true
                foreach ($endpoint in $endpoints) {
                  $url = "$baseUrl$endpoint"
                  Write-Host "Testing: $url"
                  
                  try {
                    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
                    if ($response.StatusCode -eq 200) {
                      Write-Host "  ✓ Passed"
                    } else {
                      Write-Host "  ✗ Failed - Status: $($response.StatusCode)"
                      $allPassed = $false
                    }
                  } catch {
                    Write-Host "  ✗ Failed - Error: $_"
                    $allPassed = $false
                  }
                }
                
                if (-not $allPassed) {
                  Write-Error "Smoke tests failed!"
                  exit 1
                }
                
                Write-Host "✓ All smoke tests passed!"

# Stage 3: Deploy to Production
- stage: DeployProd
  displayName: 'Deploy to Production'
  dependsOn: DeployTest
  condition: succeeded()
  jobs:
  - deployment: DeployProdJob
    displayName: 'Deploy to Production Environment'
    environment: 'Production'  # Requires manual approval
    pool:
      vmImage: 'ubuntu-latest'
    variables:
      webAppName: 'shopconnect-webapp-prod'
    strategy:
      runOnce:
        preDeploy:
          steps:
          - script: |
              echo "========================================="
              echo "PRODUCTION DEPLOYMENT"
              echo "========================================="
              echo "Build: $(Build.BuildNumber)"
              echo "Web App: $(webAppName)"
              echo "Time: $(date)"
              echo "========================================="
            displayName: 'Pre-deployment Info'
        
        deploy:
          steps:
          - download: buildPipeline
            artifact: drop
          
          - task: AzureWebApp@1
            displayName: 'Deploy to Production Web App'
            inputs:
              azureSubscription: '$(azureSubscription)'
              appType: 'webAppLinux'
              appName: '$(webAppName)'
              package: '$(Pipeline.Workspace)/buildPipeline/drop/**/*.zip'
              deploymentMethod: 'zipDeploy'
        
        routeTraffic:
          steps:
          - task: PowerShell@2
            displayName: 'Warm-up Production'
            inputs:
              targetType: 'inline'
              script: |
                Write-Host "Warming up production application..."
                Start-Sleep -Seconds 30
                
                $url = "https://$(webAppName).azurewebsites.net"
                for ($i = 1; $i -le 3; $i++) {
                  Write-Host "  Warm-up request $i/3"
                  Invoke-WebRequest -Uri $url -UseBasicParsing | Out-Null
                  Start-Sleep -Seconds 2
                }
                
                Write-Host "✓ Warm-up completed"
        
        postRouteTraffic:
          steps:
          - task: PowerShell@2
            displayName: 'Verify Production Deployment'
            inputs:
              targetType: 'inline'
              script: |
                $url = "https://$(webAppName).azurewebsites.net"
                Write-Host "Final verification: $url"
                
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                  Write-Host "========================================="
                  Write-Host "✓ PRODUCTION DEPLOYMENT SUCCESSFUL!"
                  Write-Host "========================================="
                  Write-Host "Application URL: $url"
                  Write-Host "========================================="
                } else {
                  Write-Error "Production deployment verification failed!"
                  exit 1
                }
        
        on:
          failure:
            steps:
            - script: |
                echo "❌ DEPLOYMENT FAILED!"
                echo "Consider rolling back to previous version"
              displayName: 'Deployment Failed'
          success:
            steps:
            - script: |
                echo "✅ Deployment completed successfully"
                echo "Next steps: Monitor application health"
              displayName: 'Deployment Succeeded'
EOF

# Pousser
git add azure-pipelines-release.yml
git commit -m "ci: add multi-stage release pipeline"
git push origin main
```

**Créer le pipeline dans Azure DevOps**

```
1. Pipelines → New pipeline
2. Azure Repos Git → ShopConnect
3. Existing Azure Pipelines YAML file
4. Path: /azure-pipelines-release.yml
5. [Continue]
6. [Save] (ne pas exécuter tout de suite)
```

---

#### Partie 4 : Tester le déploiement (25 min)

**Déclencher le pipeline**

```
1. Pipelines → ShopConnect-Release → [Run pipeline]
2. Branch: main
3. [Run]
```

**Suivre l'exécution**

```
Stage 1: DeployDev
├─ Download artifact  ✓
├─ Deploy to Dev      ✓
└─ Health Check       ✓
Status: Succeeded

Stage 2: DeployTest (auto)
├─ Download artifact  ✓
├─ Deploy to Test     ✓
└─ Smoke tests        ✓
Status: Succeeded

Stage 3: DeployProd (waiting for approval)
Status: Waiting for approval...

┌────────────────────────────────────────────┐
│ Approval required                          │
├────────────────────────────────────────────┤
│                                            │
│ Environment: Production                    │
│ Stage: DeployProd                          │
│                                            │
│ Please verify all tests passed before      │
│ approving.                                 │
│                                            │
│ Comment: (optional)                        │
│ ┌────────────────────────────────────┐   │
│ │ Tests verified, approving deployment│   │
│ └────────────────────────────────────┘   │
│                                            │
│ [Approve]  [Reject]                        │
└────────────────────────────────────────────┘

Après approbation:
├─ Pre-deployment     ✓
├─ Deploy to Prod     ✓
├─ Warm-up            ✓
└─ Verification       ✓
Status: Succeeded ✅
```

**Vérifier les déploiements**

```bash
# Dev
curl https://shopconnect-webapp-dev.azurewebsites.net

# Test
curl https://shopconnect-webapp-test.azurewebsites.net

# Prod
curl https://shopconnect-webapp-prod.azurewebsites.net
```

---

#### Livrables attendus

À la fin du TP, vous devez avoir :

✅ 3 Azure Web Apps créées (Dev, Test, Prod)
✅ 3 environnements configurés dans Azure DevOps
✅ Pipeline multi-stage YAML fonctionnel
✅ Approbation manuelle configurée pour Production
✅ Déploiement réussi sur les 3 environnements

---

#### Questions de validation

1. **Quelle est la différence entre un Build Pipeline et un Release Pipeline ?**
   
2. **Pourquoi utiliser des environnements séparés (Dev, Test, Prod) ?**
   
3. **Quand devriez-vous utiliser une approbation manuelle ?**
   
4. **Qu'est-ce qu'un smoke test et pourquoi est-il important après un déploiement ?**

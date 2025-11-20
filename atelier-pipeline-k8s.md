
# Exercice 7 : Pipeline Azure DevOps

## Objectif
Créer un pipeline complet CI/CD pour AKS avec Azure DevOps

## Durée estimée
60 minutes

---

## Étape 1 : Prérequis Azure (5 min)

### 1.1 Vérifier les ressources
```bash
RESOURCE_GROUP="rg-aks-training"
AKS_CLUSTER="aks-training-cluster"
ACR_NAME="acrakstraining$RANDOM"  # Nom unique
LOCATION="westeurope"

# Vérifier que le cluster existe
az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP

# Créer un Azure Container Registry
az acr create \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --sku Basic \
  --location $LOCATION

# Attacher l'ACR au cluster AKS
az aks update \
  --name $AKS_CLUSTER \
  --resource-group $RESOURCE_GROUP \
  --attach-acr $ACR_NAME

echo "ACR Name: $ACR_NAME"
```

---

## Étape 2 : Préparer le projet (10 min)

### 2.1 Créer la structure du projet
```bash
# Créer le répertoire du projet
mkdir -p aks-devops-demo
cd aks-devops-demo

# Créer l'application (Node.js simple)
mkdir -p src
cat <<'EOF' > src/server.js
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from AKS DevOps Pipeline!',
    version: process.env.APP_VERSION || '1.0.0',
    hostname: require('os').hostname()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF

# Créer package.json
cat <<'EOF' > src/package.json
{
  "name": "aks-demo-app",
  "version": "1.0.0",
  "description": "Demo app for AKS DevOps pipeline",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
```

### 2.2 Créer le Dockerfile
```bash
cat <<'EOF' > Dockerfile
FROM node:18-alpine

WORKDIR /app

COPY src/package*.json ./
RUN npm install --production

COPY src/ ./

EXPOSE 8080

USER node

CMD ["npm", "start"]
EOF
```

### 2.3 Créer les manifestes Kubernetes
```bash
mkdir -p k8s

# Deployment
cat <<'EOF' > k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aks-demo-app
  namespace: devops-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: aks-demo-app
  template:
    metadata:
      labels:
        app: aks-demo-app
    spec:
      containers:
      - name: app
        image: #{ACR_NAME}#.azurecr.io/aks-demo-app:#{Build.BuildId}#
        ports:
        - containerPort: 8080
        env:
        - name: APP_VERSION
          value: "#{Build.BuildId}#"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

# Service
cat <<'EOF' > k8s/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: aks-demo-app
  namespace: devops-demo
spec:
  type: LoadBalancer
  selector:
    app: aks-demo-app
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
EOF

# Namespace
cat <<'EOF' > k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-demo
EOF
```

---

## Étape 3 : Créer le projet Azure DevOps (5 min)

### 3.1 Se connecter à Azure DevOps
1. Aller sur https://dev.azure.com
2. Créer une nouvelle organisation si nécessaire
3. Créer un nouveau projet nommé "AKS-Training"

### 3.2 Initialiser le repository Git
```bash
# Initialiser Git
git init

# Créer .gitignore
cat <<'EOF' > .gitignore
node_modules/
*.log
.env
.DS_Store
EOF

# Commit initial
git add .
git commit -m "Initial commit - AKS DevOps Demo"
```

### 3.3 Pousser vers Azure DevOps
```bash
# Remplacer <ORGANIZATION> et <PROJECT> par vos valeurs
git remote add origin https://dev.azure.com/<ORGANIZATION>/<PROJECT>/_git/aks-demo-app
git push -u origin --all
```

---

## Étape 4 : Créer les Service Connections (5 min)

### 4.1 Service Connection pour Azure
1. Dans Azure DevOps, aller dans **Project Settings** > **Service connections**
2. Cliquer sur **New service connection**
3. Sélectionner **Azure Resource Manager**
4. Choisir **Service principal (automatic)**
5. Sélectionner votre subscription Azure
6. Sélectionner le resource group: `rg-aks-training`
7. Nommer la connection: `Azure-AKS-Connection`
8. Cocher "Grant access permission to all pipelines"
9. Sauvegarder

### 4.2 Service Connection pour ACR
1. Créer une nouvelle service connection
2. Sélectionner **Docker Registry**
3. Choisir **Azure Container Registry**
4. Sélectionner votre ACR
5. Nommer: `ACR-Connection`
6. Sauvegarder

### 4.3 Service Connection pour AKS
1. Créer une nouvelle service connection
2. Sélectionner **Kubernetes**
3. Choisir **Azure Subscription**
4. Sélectionner votre cluster AKS
5. Nommer: `AKS-Connection`
6. Sauvegarder

---

## Étape 5 : Créer le pipeline CI/CD (15 min)

### 5.1 Créer azure-pipelines.yml
```bash
cat <<'EOF' > azure-pipelines.yml
trigger:
  branches:
    include:
    - main
    - develop
  paths:
    exclude:
    - README.md
    - docs/*

variables:
  # Azure Resources
  azureSubscription: 'Azure-AKS-Connection'
  acrServiceConnection: 'ACR-Connection'
  kubernetesServiceConnection: 'AKS-Connection'
  
  # ACR
  containerRegistry: '$(ACR_NAME).azurecr.io'
  imageRepository: 'aks-demo-app'
  dockerfilePath: '$(Build.SourcesDirectory)/Dockerfile'
  tag: '$(Build.BuildId)'
  
  # Kubernetes
  k8sNamespace: 'devops-demo'
  manifestsFolder: '$(Build.SourcesDirectory)/k8s'
  
  # Build Agent
  vmImageName: 'ubuntu-latest'

stages:
- stage: Build
  displayName: 'Build and Push'
  jobs:
  - job: Build
    displayName: 'Build Docker Image'
    pool:
      vmImage: $(vmImageName)
    steps:
    - task: Docker@2
      displayName: 'Build and Push Image to ACR'
      inputs:
        command: buildAndPush
        repository: $(imageRepository)
        dockerfile: $(dockerfilePath)
        containerRegistry: $(acrServiceConnection)
        tags: |
          $(tag)
          latest
    
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Kubernetes Manifests'
      inputs:
        PathtoPublish: '$(manifestsFolder)'
        ArtifactName: 'manifests'
        publishLocation: 'Container'

- stage: DeployDev
  displayName: 'Deploy to Dev'
  dependsOn: Build
  condition: succeeded()
  jobs:
  - deployment: DeployDev
    displayName: 'Deploy to Dev Environment'
    pool:
      vmImage: $(vmImageName)
    environment: 'dev'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: DownloadBuildArtifacts@0
            inputs:
              buildType: 'current'
              downloadType: 'single'
              artifactName: 'manifests'
              downloadPath: '$(System.ArtifactsDirectory)'
          
          - task: KubernetesManifest@0
            displayName: 'Create Namespace'
            inputs:
              action: 'deploy'
              kubernetesServiceConnection: $(kubernetesServiceConnection)
              namespace: $(k8sNamespace)
              manifests: '$(System.ArtifactsDirectory)/manifests/namespace.yaml'
          
          - task: replacetokens@5
            displayName: 'Replace Tokens in Manifests'
            inputs:
              rootDirectory: '$(System.ArtifactsDirectory)/manifests'
              targetFiles: '**/*.yaml'
              encoding: 'auto'
              tokenPattern: 'custom'
              tokenPrefix: '#{'
              tokenSuffix: '}#'
              writeBOM: true
              actionOnMissing: 'warn'
              keepToken: false
              actionOnNoFiles: 'continue'
              enableTransforms: false
              useLegacyPattern: false
              enableTelemetry: true
          
          - task: KubernetesManifest@0
            displayName: 'Deploy to Kubernetes'
            inputs:
              action: 'deploy'
              kubernetesServiceConnection: $(kubernetesServiceConnection)
              namespace: $(k8sNamespace)
              manifests: |
                $(System.ArtifactsDirectory)/manifests/deployment.yaml
                $(System.ArtifactsDirectory)/manifests/service.yaml
              containers: '$(containerRegistry)/$(imageRepository):$(tag)'

- stage: DeployProd
  displayName: 'Deploy to Production'
  dependsOn: DeployDev
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployProd
    displayName: 'Deploy to Production Environment'
    pool:
      vmImage: $(vmImageName)
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: DownloadBuildArtifacts@0
            inputs:
              buildType: 'current'
              downloadType: 'single'
              artifactName: 'manifests'
              downloadPath: '$(System.ArtifactsDirectory)'
          
          - task: replacetokens@5
            displayName: 'Replace Tokens in Manifests'
            inputs:
              rootDirectory: '$(System.ArtifactsDirectory)/manifests'
              targetFiles: '**/*.yaml'
              encoding: 'auto'
              tokenPattern: 'custom'
              tokenPrefix: '#{'
              tokenSuffix: '}#'
              writeBOM: true
              actionOnMissing: 'warn'
              keepToken: false
              actionOnNoFiles: 'continue'
              enableTransforms: false
              useLegacyPattern: false
              enableTelemetry: true
          
          - task: KubernetesManifest@0
            displayName: 'Deploy to Production'
            inputs:
              action: 'deploy'
              kubernetesServiceConnection: $(kubernetesServiceConnection)
              namespace: $(k8sNamespace)
              manifests: |
                $(System.ArtifactsDirectory)/manifests/deployment.yaml
                $(System.ArtifactsDirectory)/manifests/service.yaml
              containers: '$(containerRegistry)/$(imageRepository):$(tag)'
EOF
```

### 5.2 Créer les variables dans le pipeline
```bash
# Pousser le fichier
git add azure-pipelines.yml
git commit -m "Add Azure Pipelines configuration"
git push
```

---

## Étape 6 : Configurer le pipeline dans Azure DevOps (10 min)

### 6.1 Créer le pipeline
1. Dans Azure DevOps, aller dans **Pipelines** > **Pipelines**
2. Cliquer sur **New Pipeline**
3. Sélectionner **Azure Repos Git**
4. Sélectionner votre repository
5. Choisir **Existing Azure Pipelines YAML file**
6. Sélectionner `/azure-pipelines.yml`
7. Cliquer sur **Continue**

### 6.2 Ajouter les variables
1. Cliquer sur **Variables** en haut à droite
2. Ajouter la variable:
   - Name: `ACR_NAME`
   - Value: `<votre-acr-name>`
3. Sauvegarder

### 6.3 Installer l'extension Replace Tokens
1. Aller sur Azure DevOps Marketplace
2. Chercher "Replace Tokens"
3. Installer l'extension dans votre organisation

### 6.4 Créer les Environments
1. Aller dans **Pipelines** > **Environments**
2. Créer un environment nommé `dev`
3. Créer un environment nommé `production`
4. Pour `production`, ajouter une **Approval** :
   - Cliquer sur les 3 points > **Approvals and checks**
   - Ajouter **Approvals**
   - Ajouter des approvers

---

## Étape 7 : Exécuter le pipeline (5 min)

### 7.1 Lancer le pipeline
1. Cliquer sur **Run pipeline**
2. Sélectionner la branche `main`
3. Cliquer sur **Run**

### 7.2 Suivre l'exécution
1. Observer les stages:
   - **Build**: Construction et push de l'image Docker
   - **DeployDev**: Déploiement automatique en dev
   - **DeployProd**: Attend l'approbation pour production

### 7.3 Approuver le déploiement en production
1. Quand le stage **DeployProd** est en attente
2. Cliquer sur **Review**
3. Ajouter un commentaire
4. Cliquer sur **Approve**

---

## Étape 8 : Vérifier le déploiement (5 min)

### 8.1 Vérifier dans Kubernetes
```bash
# Voir les pods
kubectl get pods -n devops-demo

# Voir le service
kubectl get svc -n devops-demo

# Récupérer l'IP externe
kubectl get svc aks-demo-app -n devops-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 8.2 Tester l'application
```bash
# Attendre que le LoadBalancer soit prêt
kubectl get svc aks-demo-app -n devops-demo -w

# Récupérer l'IP
EXTERNAL_IP=$(kubectl get svc aks-demo-app -n devops-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Tester
curl http://$EXTERNAL_IP/
curl http://$EXTERNAL_IP/health
```

---

## Étape 9 : Implémenter un rollback (5 min)

### 9.1 Ajouter un stage de rollback dans le pipeline
```yaml
# Ajouter à la fin de azure-pipelines.yml
- stage: Rollback
  displayName: 'Rollback Production'
  dependsOn: DeployProd
  condition: failed()
  jobs:
  - job: Rollback
    displayName: 'Rollback to Previous Version'
    pool:
      vmImage: $(vmImageName)
    steps:
    - task: Kubernetes@1
      displayName: 'Rollback Deployment'
      inputs:
        connectionType: 'Kubernetes Service Connection'
        kubernetesServiceEndpoint: $(kubernetesServiceConnection)
        namespace: $(k8sNamespace)
        command: 'rollout'
        arguments: 'undo deployment/aks-demo-app'
```

### 9.2 Tester le rollback manuellement
```bash
# Voir l'historique des déploiements
kubectl rollout history deployment/aks-demo-app -n devops-demo

# Rollback à la version précédente
kubectl rollout undo deployment/aks-demo-app -n devops-demo

# Rollback à une version spécifique
kubectl rollout undo deployment/aks-demo-app -n devops-demo --to-revision=1

# Vérifier le statut
kubectl rollout status deployment/aks-demo-app -n devops-demo
```

---

## Étape 10 : Ajouter des tests automatisés (5 min)

### 10.1 Créer un stage de tests
```yaml
# Ajouter après le stage Build dans azure-pipelines.yml
- stage: Test
  displayName: 'Run Tests'
  dependsOn: Build
  jobs:
  - job: IntegrationTests
    displayName: 'Integration Tests'
    pool:
      vmImage: $(vmImageName)
    steps:
    - task: Docker@2
      displayName: 'Pull Image from ACR'
      inputs:
        command: pull
        containerRegistry: $(acrServiceConnection)
        arguments: '$(containerRegistry)/$(imageRepository):$(tag)'
    
    - script: |
        # Lancer le conteneur
        docker run -d -p 8080:8080 --name test-container \
          $(containerRegistry)/$(imageRepository):$(tag)
        
        # Attendre que le conteneur soit prêt
        sleep 10
        
        # Tester le endpoint de santé
        curl -f http://localhost:8080/health || exit 1
        
        # Tester le endpoint principal
        curl -f http://localhost:8080/ || exit 1
        
        # Arrêter le conteneur
        docker stop test-container
        docker rm test-container
      displayName: 'Run Integration Tests'
```

---

## Points de vérification

✅ Azure Container Registry créé et attaché à AKS
✅ Projet Azure DevOps créé avec repository Git
✅ Service Connections configurées (Azure, ACR, AKS)
✅ Pipeline YAML créé avec stages multiples
✅ Pipeline build l'image Docker et la pousse vers ACR
✅ Déploiement automatique en dev
✅ Approbation manuelle pour production
✅ Application accessible via LoadBalancer
✅ Rollback fonctionnel
✅ Tests automatisés intégrés

---

## Bonus : Notifications

### Ajouter des notifications Slack/Teams
```yaml
# Ajouter à la fin de chaque stage
- task: PublishBuildArtifacts@1
  condition: always()
  inputs:
    PathtoPublish: '$(Build.ArtifactStagingDirectory)'
    ArtifactName: 'logs'

# Ou utiliser une extension pour Slack/Teams
- task: SlackNotification@1
  condition: always()
  inputs:
    SlackApiToken: '$(SLACK_TOKEN)'
    Channel: '#deployments'
    Message: 'Deployment to $(k8sNamespace) - Status: $(Agent.JobStatus)'
```

---

## Nettoyage

```bash
# Supprimer le namespace
kubectl delete namespace devops-demo

# Supprimer l'ACR (optionnel)
az acr delete --name $ACR_NAME --resource-group $RESOURCE_GROUP --yes

# Dans Azure DevOps: supprimer le projet si nécessaire
```

---

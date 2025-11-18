# Atelier : Déploiement de conteneurs Docker vers Azure App Service

### Objectifs pédagogiques

À la fin de cet atelier, les participants seront capables de :

- Comprendre le déploiement de conteneurs Docker sur Azure App Service
- Configurer un pipeline CI/CD dans Azure DevOps pour automatiser le déploiement
- Implémenter des bonnes pratiques de déploiement avec intégration GitHub
- Configurer les variables d'environnement et les secrets pour le déploiement sécurisé

### Prérequis

- Un abonnement Azure actif
- Un compte Azure DevOps
- Un repository GitHub contenant une application conteneurisée
- Docker installé localement
- Azure CLI installé localement

### Durée estimée

3 heures

### Introduction

Azure App Service offre un service d'hébergement géré pour les applications web qui peuvent être déployées dans des conteneurs Docker. Dans cet atelier, nous allons explorer comment intégrer le déploiement de conteneurs dans un pipeline CI/CD automatisé avec Azure DevOps et GitHub Actions.


### Partie 1 : Préparation de l'environnement

#### 1.1 Configuration de l'application Docker

Nous allons utiliser une application web simple en Node.js comme exemple. Voici la structure du projet :

```
app/
├── Dockerfile
├── package.json
├── server.js
└── views/
    └── index.html
```

---

#### Contenu du fichier `server.js` :

```javascript
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.use(express.static('views'));

app.get('/api/info', (req, res) => {
  res.json({
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    message: 'Application déployée avec succès!'
  });
});

app.listen(port, () => {
  console.log(`App listening at http://localhost:${port}`);
});
```

---

#### Contenu du fichier `Dockerfile` :

```dockerfile
FROM node:14-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["node", "server.js"]
```

---

#### Contenu du fichier `package.json` :

```json
{
  "name": "azure-devops-docker-demo",
  "version": "1.0.0",
  "description": "Application demo pour le déploiement de conteneurs Docker vers Azure App Service",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "echo \"Tests passed successfully\" && exit 0"
  },
  "dependencies": {
    "express": "^4.17.1"
  }
}
```

### 1.2 Créer un registry de conteneurs dans Azure

1. Ouvrez le terminal et connectez-vous à Azure CLI :
   ```bash
   az login
   ```

2. Créez un groupe de ressources :
   ```bash
   az group create --name rg-docker-webapp --location westeurope
   ```

3. Créez un Azure Container Registry (ACR) :
   ```bash
   az acr create --resource-group rg-docker-webapp --name <votre-nom-acr-unique> --sku Basic --admin-enabled true
   ```

4. Récupérez les informations d'identification de l'ACR :
   ```bash
   az acr credential show --name <votre-nom-acr-unique>
   ```

### Partie 2 : Configuration d'Azure App Service

#### 2.1 Créer un plan App Service

```bash
az appservice plan create --name asp-docker-webapp --resource-group rg-docker-webapp --sku B1 --is-linux
```

---

#### 2.2 Créer une Web App pour conteneurs

```bash
az webapp create --resource-group rg-docker-webapp --plan asp-docker-webapp --name <votre-nom-webapp-unique> --deployment-container-image-name nginx:latest
```

### Partie 3 : Configuration du pipeline CI/CD avec Azure DevOps

#### 3.1 Créer un projet Azure DevOps

1. Connectez-vous à votre compte Azure DevOps
2. Créez un nouveau projet nommé "DockerWebAppDemo"
3. Importez votre code source depuis GitHub ou initialisez un nouveau dépôt

---

#### 3.2 Configurer les variables et les secrets

1. Dans Azure DevOps, accédez à Pipelines > Library > Variable groups
2. Créez un groupe de variables "docker-webapp-variables" avec :
   - `acrName` : Nom de votre Azure Container Registry
   - `acrLoginServer` : URL du serveur de login ACR (format : <nom-acr>.azurecr.io)
   - `webAppName` : Nom de votre Web App Azure

3. Ajoutez les secrets suivants :
   - `acrUsername` : Nom d'utilisateur ACR (récupéré précédemment)
   - `acrPassword` : Mot de passe ACR (récupéré précédemment)

---

#### 3.3 Créer le fichier de pipeline Azure DevOps

Créez un fichier nommé `azure-pipelines.yml` à la racine de votre projet :

```yaml
trigger:
- main

variables:
- group: docker-webapp-variables

stages:
- stage: Build
  displayName: 'Build and Push Docker Image'
  jobs:
  - job: BuildPushImage
    displayName: 'Build and Push Docker Image'
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: Docker@2
      displayName: 'Build Docker Image'
      inputs:
        command: build
        repository: $(acrName)/docker-webapp-demo
        dockerfile: '$(Build.SourcesDirectory)/Dockerfile'
        tags: |
          $(Build.BuildId)
          latest
    
    - task: Docker@2
      displayName: 'Push Docker Image to ACR'
      inputs:
        command: login
        containerRegistry: 'docker-registry-connection'
        
    - task: Docker@2
      displayName: 'Push Docker image'
      inputs:
        command: push
        repository: $(acrName)/docker-webapp-demo
        tags: |
          $(Build.BuildId)
          latest

- stage: Deploy
  displayName: 'Deploy to Azure App Service'
  dependsOn: Build
  jobs:
  - job: DeployToAppService
    displayName: 'Deploy to App Service'
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: AzureWebAppContainer@1
      displayName: 'Azure Web App on Container Deploy'
      inputs:
        azureSubscription: 'azure-connection'
        appName: $(webAppName)
        containers: '$(acrLoginServer)/docker-webapp-demo:$(Build.BuildId)'
```

---

#### 3.4 Configurer les connexions de service

1. Dans Azure DevOps, accédez à Project Settings > Service connections
2. Créez une connexion nommée "azure-connection" vers votre abonnement Azure
3. Créez une connexion nommée "docker-registry-connection" vers votre Azure Container Registry

### Partie 4 : Configuration avec GitHub Actions (alternative)

#### 4.1 Créer les secrets GitHub

Ajoutez les secrets suivants à votre repository GitHub :

- `AZURE_CREDENTIALS` : Informations d'identification JSON pour l'accès à Azure
- `ACR_USERNAME` : Nom d'utilisateur ACR
- `ACR_PASSWORD` : Mot de passe ACR
- `ACR_LOGIN_SERVER` : URL du serveur de login ACR
- `WEBAPP_NAME` : Nom de votre App Service

---

#### 4.2 Créer le workflow GitHub Actions

Créez un fichier `.github/workflows/docker-deploy.yml` :

```yaml
name: Build and Deploy to Azure App Service

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Login to Azure Container Registry
      uses: docker/login-action@v1
      with:
        registry: ${{ secrets.ACR_LOGIN_SERVER }}
        username: ${{ secrets.ACR_USERNAME }}
        password: ${{ secrets.ACR_PASSWORD }}
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v2
      with:
        context: .
        push: true
        tags: ${{ secrets.ACR_LOGIN_SERVER }}/docker-webapp-demo:${{ github.sha }}, ${{ secrets.ACR_LOGIN_SERVER }}/docker-webapp-demo:latest
    
    - name: Login to Azure
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy to Azure App Service
      uses: azure/webapps-deploy@v2
      with:
        app-name: ${{ secrets.WEBAPP_NAME }}
        images: ${{ secrets.ACR_LOGIN_SERVER }}/docker-webapp-demo:${{ github.sha }}
```

### Partie 5 : Tester le déploiement

#### 5.1 Déclencher le pipeline

1. Validez et poussez vos modifications vers le dépôt
2. Observez l'exécution du pipeline dans Azure DevOps ou GitHub Actions
3. Vérifiez les logs de déploiement

---

#### 5.2 Vérifier l'application

1. Accédez à votre application : `https://<votre-nom-webapp-unique>.azurewebsites.net`
2. Testez l'endpoint API : `https://<votre-nom-webapp-unique>.azurewebsites.net/api/info`

### Partie 6 : Bonnes pratiques et optimisations

#### 6.1 Configuration des slots de déploiement

```bash
# Créer un slot de staging
az webapp deployment slot create --name <votre-nom-webapp-unique> --resource-group rg-docker-webapp --slot staging
```

Modifiez votre pipeline pour déployer d'abord sur le slot de staging, puis échanger avec la production :

```yaml
# Ajoutez ces étapes au stage de déploiement
- task: AzureAppServiceManage@0
  inputs:
    azureSubscription: 'azure-connection'
    Action: 'Swap Slots'
    WebAppName: $(webAppName)
    ResourceGroupName: 'rg-docker-webapp'
    SourceSlot: 'staging'
    SwapWithProduction: true
```

---

#### 6.2 Configuration du monitoring

1. Activez Application Insights pour votre App Service
2. Configurez des alertes pour les métriques importantes (temps de réponse, erreurs HTTP)

---

#### 6.3 Optimisation des images Docker

1. Utilisez des images de base légères (alpine)
2. Implémentez le multi-stage building
3. Minimisez le nombre de couches

Exemple de Dockerfile multi-stage :

```dockerfile
# Build stage
FROM node:14-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

# Production stage
FROM node:14-alpine
WORKDIR /app
COPY --from=build /app .
EXPOSE 3000
CMD ["node", "server.js"]
```

### Exercices pratiques pour aller plus loin

1. Modifiez l'application pour inclure une nouvelle fonctionnalité et observez le déploiement automatique
2. Configurez des variables d'environnement spécifiques pour chaque environnement (dev, staging, prod)
3. Implémentez un test de disponibilité post-déploiement dans le pipeline


### Ressources complémentaires

- [Documentation Azure App Service](https://docs.microsoft.com/fr-fr/azure/app-service/)
- [Docker sur Azure App Service](https://docs.microsoft.com/fr-fr/azure/app-service/configure-custom-container)
- [Guide des meilleures pratiques pour les pipelines Azure DevOps](https://docs.microsoft.com/fr-fr/azure/devops/pipelines/best-practices)
- [GitHub Actions pour Azure](https://docs.microsoft.com/fr-fr/azure/developer/github/github-actions)

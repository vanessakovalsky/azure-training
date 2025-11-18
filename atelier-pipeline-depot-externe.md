# Atelier 3 : Intégration du contrôle de source externe avec Azure Pipelines

### Durée estimée : 120 minutes

### Objectifs d'apprentissage
- Connecter Azure Pipelines à un dépôt GitHub externe
- Configurer des connexions de service sécurisées
- Utiliser des variables et secrets dans les pipelines
- Mettre en place une intégration continue entre GitHub et Azure DevOps

### Prérequis
- Compte GitHub
- Accès à une organisation Azure DevOps
- Connaissance de base de Git et des pipelines YAML

### Étapes détaillées

#### Partie 1 : Préparation du dépôt GitHub

1. **Création d'un dépôt GitHub**
   - Connectez-vous à votre compte GitHub
   - Créez un nouveau dépôt (ex: "azure-pipelines-demo")
   - Initialisez-le avec un README.md

---

2. **Ajout d'une application simple**
   - Clonez le dépôt sur votre machine locale
   - Créez une application web simple
     - Pour Node.js:
       ```bash
       git clone https://github.com/votre-compte/azure-pipelines-demo
       cd azure-pipelines-demo
       npm init -y
       npm install express --save
       ```
     - Créez un fichier `app.js` avec un serveur Express basique
     - Créez un fichier `azure-pipelines.yml` à la racine (vide pour l'instant)

---

3. **Commit et push du code initial**
   ```bash
   git add .
   git commit -m "Initial commit with Express app"
   git push
   ```

---

#### Partie 2 : Configuration de la connexion Azure DevOps à GitHub

4. **Création d'une connexion de service GitHub**
   - Dans Azure DevOps, naviguez vers *Project Settings > Service connections*
   - Cliquez sur "New service connection"
   - Sélectionnez "GitHub"
   - Choisissez "GitHub App" comme méthode d'authentification
   - Cliquez sur "Authorize" pour permettre à Azure DevOps d'accéder à GitHub
   - Sélectionnez votre compte GitHub et autorisez l'accès
   - Nommez la connexion (ex: "GitHub-Connection")
   - Cliquez sur "Save"

---

5. **Vérification des autorisations**
   - Dans GitHub, allez dans *Settings > Applications*
   - Vérifiez que "Azure Pipelines" est autorisé
   - Examinez les permissions accordées

---

#### Partie 3 : Configuration du pipeline Azure pour le dépôt GitHub

6. **Création du pipeline dans Azure DevOps**
   - Naviguez vers *Pipelines > Pipelines*
   - Cliquez sur "New pipeline"
   - Sélectionnez "GitHub" comme source de code
   - Autorisez Azure DevOps à accéder à GitHub si demandé
   - Sélectionnez votre dépôt "azure-pipelines-demo"
   - Choisissez "Node.js" comme modèle de départ

---

7. **Configuration du fichier YAML**
   - Azure DevOps va générer un pipeline YAML de base pour Node.js
   - Modifiez le pipeline comme suit:
     ```yaml
     trigger:
       branches:
         include:
         - main
       paths:
         include:
         - '**'
         exclude:
         - '*.md'
     
     pool:
       vmImage: 'ubuntu-latest'
     
     variables:
       # Déclaration de variables non-secrètes
       nodeVersion: '16.x'
       # Les secrets seront ajoutés via le vault
     
     steps:
     - task: NodeTool@0
       inputs:
         versionSpec: '$(nodeVersion)'
       displayName: 'Install Node.js'
     
     - script: |
         npm install
       displayName: 'npm install'
     
     - script: |
         npm test
       displayName: 'Run tests'
       continueOnError: true  # Continuer même si les tests échouent (pour l'atelier)
     
     - script: |
         echo "Application name: $(applicationName)"
         echo "Environment: $(environment)"
       displayName: 'Echo variables'
       # Les variables applicationName et environment seront définies plus tard
     ```
   - Cliquez sur "Save and run"
   - Choisissez de valider directement dans la branche main
   - Le pipeline échouera car les variables ne sont pas encore définies, c'est normal

---

#### Partie 4 : Configuration des variables et secrets

8. **Création de variables de pipeline**
   - Dans Azure DevOps, naviguez vers votre pipeline
   - Cliquez sur "Edit"
   - Cliquez sur les "..." en haut à droite et sélectionnez "Variables"
   - Ajoutez deux variables:
     - Nom: `applicationName`, Valeur: `AzureWorkshopApp`, Maintenir secret: Non
     - Nom: `environment`, Valeur: `Development`, Maintenir secret: Non
   - Cliquez sur "Save"

---

9. **Configuration d'Azure Key Vault pour les secrets**
   - Dans Azure Portal, créez un nouveau Key Vault ou utilisez un existant
   - Ajoutez deux secrets:
     - `dbConnectionString` avec une valeur fictive
     - `apiKey` avec une valeur fictive

10. **Création d'une connexion de service à Azure**
    - Dans Azure DevOps, *Project Settings > Service connections* 
    - Cliquez sur "New service connection"
    - Sélectionnez "Azure Resource Manager"
    - Choisissez "Service principal (automatic)"
    - Sélectionnez votre abonnement Azure
    - Nommez la connexion (ex: "Azure-Workshop-Connection")
    - Cliquez sur "Save"

---

11. **Mise à jour du pipeline pour utiliser Key Vault**
    - Modifiez votre pipeline YAML pour ajouter l'accès à Key Vault:
      ```yaml
      trigger:
        branches:
          include:
          - main
        paths:
          include:
          - '**'
          exclude:
          - '*.md'
      
      pool:
        vmImage: 'ubuntu-latest'
      
      variables:
        nodeVersion: '16.x'
      
      steps:
      - task: NodeTool@0
        inputs:
          versionSpec: '$(nodeVersion)'
        displayName: 'Install Node.js'
      
      - task: AzureKeyVault@2
        inputs:
          azureSubscription: 'Azure-Workshop-Connection'
          KeyVaultName: 'votre-key-vault-name'
          SecretsFilter: 'dbConnectionString,apiKey'
          RunAsPreJob: true
        displayName: 'Get secrets from Azure Key Vault'
      
      - script: |
          npm install
        displayName: 'npm install'
      
      - script: |
          npm test
        displayName: 'Run tests'
        continueOnError: true
      
      - script: |
          echo "Application name: $(applicationName)"
          echo "Environment: $(environment)"
          echo "Using connection string: $(dbConnectionString)"
          echo "API Key length: $(apiKey)"
        displayName: 'Echo variables'
      ```
    - Committez les changements au fichier YAML (Azure DevOps le fera pour vous si vous utilisez l'éditeur)

---

12. **Test du pipeline avec variables et secrets**
    - Exécutez le pipeline
    - Vérifiez les logs pour confirmer que les variables sont correctement utilisées
    - Notez que les secrets de Key Vault sont masqués dans les logs

---

#### Partie 5 : Configuration des webhooks et déclencheurs

13. **Inspection des webhooks GitHub**
    - Dans votre dépôt GitHub, allez dans *Settings > Webhooks*
    - Observez le webhook créé automatiquement par Azure Pipelines
    - Examinez les événements qui déclenchent le webhook

14. **Test des déclencheurs par push**
    - Modifiez un fichier dans votre dépôt GitHub (via l'interface web ou localement)
    - Pushez les modifications
    - Observez le déclenchement automatique du pipeline dans Azure DevOps

---

15. **Configuration des pull requests**
    - Modifiez votre pipeline pour ajouter des déclencheurs de pull request:
      ```yaml
      trigger:
        branches:
          include:
          - main
        paths:
          include:
          - '**'
          exclude:
          - '*.md'
      
      pr:
        branches:
          include:
          - main
      ```
    - Créez une nouvelle branche et une pull request dans GitHub
    - Vérifiez que le pipeline se déclenche lors de la création de la PR

---

#### Partie 6 : Publication d'artefacts et status checks (suite)

18. **Test complet d'intégration**
    - Créez une nouvelle branche dans votre dépôt GitHub: `git checkout -b feature/test-integration`
    - Modifiez ou ajoutez un fichier dans le projet
    - Committez et pushez les modifications
    - Créez une Pull Request vers la branche main
    - Observez le déclenchement automatique du pipeline
    - Vérifiez que le status check est requis avant de pouvoir fusionner la PR
    - Une fois le pipeline réussi, fusionnez la PR
    - Observez le déclenchement d'un nouveau build sur la branche main

---

#### Partie 7 : Personnalisation et optimisation

19. **Ajout d'un badge de statut dans le README**

    - Dans Azure DevOps, accédez à votre pipeline
    - Cliquez sur "..." et sélectionnez "Status badge"
    - Copiez le markdown généré
    - Modifiez le README.md dans votre dépôt GitHub pour y ajouter le badge
    - Committez et pushez les modifications

---

20. **Configuration du cache pour les dépendances**

    - Modifiez votre pipeline pour ajouter la mise en cache des modules npm:
      ```yaml
      steps:
      - task: NodeTool@0
        inputs:
          versionSpec: '$(nodeVersion)'
        displayName: 'Install Node.js'
      
      - task: AzureKeyVault@2
        inputs:
          azureSubscription: 'Azure-Workshop-Connection'
          KeyVaultName: 'votre-key-vault-name'
          SecretsFilter: 'dbConnectionString,apiKey'
          RunAsPreJob: true
        displayName: 'Get secrets from Azure Key Vault'
      
      - task: Cache@2
        inputs:
          key: 'npm | "$(Agent.OS)" | package-lock.json'
          restoreKeys: |
            npm | "$(Agent.OS)"
          path: '$(npm.config.cache)'
        displayName: 'Cache npm modules'
      
      - script: |
          npm install
        displayName: 'npm install'
      
      # ... reste du pipeline
      ```
    - Exécutez le pipeline deux fois consécutives
    - Vérifiez que la deuxième exécution utilise le cache

### Livrables
- Dépôt GitHub connecté à Azure Pipelines
- Pipeline CI fonctionnel qui s'exécute automatiquement sur les pushes et PRs
- Variables et secrets correctement configurés et utilisés
- Status checks GitHub qui protègent la branche main
- Badge de statut dans le README
- Optimisation des performances avec cache

### Ressources supplémentaires
- [Connexion de service GitHub](https://docs.microsoft.com/azure/devops/pipelines/library/service-endpoints)
- [Utilisation d'Azure Key Vault dans Azure Pipelines](https://docs.microsoft.com/azure/devops/pipelines/release/azure-key-vault)
- [Protection des branches GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [Caching dans Azure Pipelines](https://docs.microsoft.com/azure/devops/pipelines/release/caching)

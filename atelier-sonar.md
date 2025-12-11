# Atelier  : Gérer la dette technique avec SonarCloud et Azure DevOps

### Objectifs pédagogiques
- Comprendre le concept de dette technique
- Configurer SonarCloud pour l'analyse de code
- Intégrer SonarCloud avec Azure DevOps
- Établir des règles de qualité de code dans les pipelines
- Mettre en place une stratégie d'amélioration continue

### Prérequis
- Un compte Azure DevOps avec les permissions appropriées
- Un projet Azure DevOps contenant du code source
- Un compte SonarCloud (version d'essai gratuite disponible)

### Partie 1 : Configuration de SonarCloud

**Instructions:**

1. **Créer un compte SonarCloud**
   - Rendez-vous sur [SonarCloud](https://sonarcloud.io/)
   - Créez un compte en utilisant votre compte Azure DevOps
   - Créez une nouvelle organisation SonarCloud

2. **Installer l'extension SonarCloud pour Azure DevOps**
   - Allez sur le [Marketplace Azure DevOps](https://marketplace.visualstudio.com/)
   - Recherchez "SonarCloud"
   - Installez l'extension pour votre organisation

---

3. **Créer un projet SonarCloud**
   - Dans SonarCloud, créez un nouveau projet
   - Sélectionnez votre organisation
   - Choisissez "Configurer avec Azure Pipelines"
   - Notez votre token d'accès et votre clé de projet

4. **Questions de réflexion:**
   - Pourquoi est-il préférable d'utiliser SonarCloud plutôt que SonarQube pour les projets cloud-native?
   - Quels types de problèmes SonarCloud peut-il identifier dans votre code?

### Partie 2 : Intégration de SonarCloud dans le pipeline CI/CD

**Instructions:**

1. **Configurer les variables de service connection**
   - Dans Azure DevOps, accédez à Paramètres du projet > Service connections
   - Créez une connexion de service SonarCloud
   - Utilisez le token d'accès précédemment obtenu


2. **Pour les projets JavaScript/TypeScript**
   - Utilisez cette configuration alternative:

```yaml
- task: SonarCloudPrepare@4
  inputs:
    SonarQube: 'VanessaSonarCloud'
    organization: 'vdavid0968'
    scannerMode: 'cli'
    configMode: 'manual'
    cliProjectKey: 'votre-cle-projet'
    cliProjectName: 'votre-nomè-de-projet'
    cliSources: 'node-sample'
- task: SonarCloudAnalyze@4
  inputs:
    jdkversion: 'JAVA_HOME_17_X64'
```

3. **Questions de réflexion:**
   - Comment l'intégration de SonarCloud peut-elle améliorer votre processus de revue de code?
   - Quels avantages y a-t-il à collecter la couverture de code avec l'analyse SonarCloud?


## BONUS

### Partie 3 : Configuration des Quality Gates

**Instructions:**

1. **Configurer un Quality Gate dans SonarCloud**
   - Accédez à votre projet dans SonarCloud
   - Allez dans Administration > Quality Gates
   - Créez un nouveau Quality Gate ou utilisez "Sonar Way"
   - Configurez les conditions suivantes:
     - Couverture de code > 80%
     - Bugs critiques = 0
     - Dette technique < 5% (ratio)
     - Code dupliqué < 3%

---

2. **Configurer l'échec du build en cas de non-respect du Quality Gate**
   - Modifiez votre pipeline pour ajouter une étape de vérification:

```yaml
- task: SonarCloudPublish@1
  inputs:
    pollingTimeoutSec: '300'

- task: PowerShell@2
  displayName: 'Vérifier Quality Gate SonarCloud'
  inputs:
    targetType: 'inline'
    script: |
      $status = Invoke-RestMethod -Uri "https://sonarcloud.io/api/qualitygates/project_status?projectKey=votre-projet-key" -Headers @{Authorization = "Bearer $(SonarToken)"}
      Write-Host "Quality Gate Status: $($status.projectStatus.status)"
      if ($status.projectStatus.status -eq "ERROR") {
        Write-Host "##vso[task.logissue type=error]Le Quality Gate SonarCloud a échoué."
        Write-Host "##vso[task.complete result=Failed;]"
      }
```

---

3. **Ajouter une condition de déploiement basée sur le Quality Gate**
   - Dans votre pipeline de release, ajoutez une gate avant le déploiement:
     - Utilisez la tâche "Evaluate SonarCloud Quality Gate"
     - Configurez-la pour bloquer le déploiement si le Quality Gate échoue

4. **Questions de réflexion:**
   - Quelle est l'importance des Quality Gates dans la gestion de la dette technique?
   - Comment équilibrer les exigences de qualité strictes avec les délais de livraison?

### Partie 4 : Analyse et remédiation de la dette technique

**Instructions:**

1. **Exécuter une première analyse complète**
   - Déclenchez manuellement votre pipeline pour analyser le code
   - Consultez les résultats dans SonarCloud

---

2. **Créer un plan de remédiation**
   - Analysez le rapport de dette technique
   - Identifiez les 5 problèmes les plus importants
   - Créez des user stories dans Azure DevOps pour chaque problème:

```
Titre: Corriger [Type de problème] dans [Composant]
Description:
- Problème détecté par SonarCloud: [Description du problème]
- Localisation: [Fichier/Méthode]
- Impact: [Sécurité/Maintenabilité/Performance]
- Effort estimé: [X] Story Points
```

---

3. **Mettre en place un suivi de la dette technique**
   - Créez un dashboard Azure DevOps avec:
     - Un widget SonarCloud montrant l'évolution de la dette technique
     - Un rapport de bugs détectés par SonarCloud
     - Un suivi des user stories de remédiation

4. **Questions de réflexion:**
   - Comment équilibrer le développement de nouvelles fonctionnalités et la correction de la dette technique?
   - Quels indicateurs clés utiliser pour suivre la santé du code?

### Partie 5 : Automatisation du processus d'amélioration continue

**Instructions:**

1. **Configurer des Pull Request Decorators**
   - Dans SonarCloud, activez l'analyse des pull requests
   - Configurez Azure DevOps pour afficher les résultats SonarCloud dans les PRs

2. **Créer une politique de branche liée à SonarCloud**
   - Dans Repos > Branches > Policies
   - Ajoutez une politique "Status Check"
   - Sélectionnez SonarCloud comme provider

---

3. **Configurer des rapports hebdomadaires**
   - Activez les notifications SonarCloud
   - Configurez l'envoi de rapports hebdomadaires par email

4. **Questions de réflexion:**
   - Comment l'automatisation peut-elle aider à maintenir la qualité du code sur le long terme?
   - Quelles mesures organisationnelles peuvent compléter les outils techniques?

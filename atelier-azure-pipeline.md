# Atelier 2 : Activation de l'intégration continue avec Azure Pipelines

### Durée estimée : 120 minutes

### Objectifs d'apprentissage
- Mettre en place un pipeline CI complet pour une application web
- Configurer des tests automatisés avec publication de résultats
- Implémenter l'analyse de couverture de code
- Comprendre les stratégies de déclenchement de builds

### Prérequis
- Accès à une organisation Azure DevOps
- Connaissances de base en développement web (.NET Core ou Node.js)
- Git installé sur votre poste de travail

### Étapes détaillées

#### Partie 1 : Préparation du projet

1. **Création du dépôt**
   - Dans Azure DevOps, naviguez vers *Repos > Files*
   - Cliquez sur "Initialize repository" s'il est vide
   - Ou créez un nouveau dépôt si nécessaire

---

2. **Création d'une application web simple**
   - Clonez le dépôt sur votre poste local: `git clone [url-du-depot]`
   - Pour .NET Core:
     ```bash
     dotnet new webapi -o WebApiSample
     cd WebApiSample
     dotnet new xunit -o WebApiSample.Tests
     ```
   - Ou pour Node.js:
     ```bash
     mkdir node-sample
     cd node-sample
     npm init -y
     npm install express --save
     npm install jest supertest --save-dev
     ```

---

   - Créez quelques fichiers de base:
     - Pour .NET Core: un contrôleur API simple et un test unitaire
     - Pour Node.js: un serveur Express simple et un test Jest

---

3. **Configuration des tests**
   - Pour .NET Core, créez un test simple dans WebApiSample.Tests:
     ```csharp
     using Xunit;
     using WebApiSample.Controllers;
     
     public class WeatherForecastControllerTests
     {
         [Fact]
         public void Get_ReturnsData()
         {
             // Arrange
             var controller = new WeatherForecastController();
             
             // Act
             var result = controller.Get();
             
             // Assert
             Assert.NotNull(result);
             Assert.NotEmpty(result);
         }
     }
     ```

---

   - Pour Node.js, créez un test Jest:
     ```javascript
     const request = require('supertest');
     const app = require('./app');
     
     test('GET / responds with Hello World', async () => {
       const response = await request(app).get('/');
       expect(response.status).toBe(200);
       expect(response.text).toContain('Hello World');
     });
     ```

---

4. **Commit et push du code**
   ```bash
   git add .
   git commit -m "Initial commit with web application and tests"
   git push
   ```

---

#### Partie 2 : Configuration du pipeline CI

5. **Création du pipeline YAML**

   - Dans Azure DevOps, naviguez vers *Pipelines > Pipelines*
   - Cliquez sur "New pipeline"
   - Sélectionnez votre référentiel source
   - Pour .NET Core, choisissez le modèle "ASP.NET Core" ou "Starter pipeline"
   - Pour Node.js, choisissez le modèle "Node.js" ou "Starter pipeline"

---

6. **Configuration du pipeline pour .NET Core**

   - Modifiez le YAML comme suit:
     ```yaml
     trigger:
       branches:
         include:
         - main
         - feature/*
       paths:
         include:
         - WebApiSample/**
         exclude:
         - '*.md'
     
     pool:
       vmImage: 'ubuntu-latest'
     
     variables:
       buildConfiguration: 'Release'
       projectPath: 'WebApiSample'
       testProjectPath: 'WebApiSample.Tests'
     
     steps:
     - task: DotNetCoreCLI@2
       displayName: 'Restore packages'
       inputs:
         command: 'restore'
         projects: '$(projectPath)/**/*.csproj'
     
     - task: DotNetCoreCLI@2
       displayName: 'Build solution'
       inputs:
         command: 'build'
         projects: '$(projectPath)/**/*.csproj'
         arguments: '--configuration $(buildConfiguration)'
     
     - task: DotNetCoreCLI@2
       displayName: 'Run tests'
       inputs:
         command: 'test'
         projects: '$(testProjectPath)/**/*.csproj'
         arguments: '--configuration $(buildConfiguration) --collect:"XPlat Code Coverage"'
         publishTestResults: true
     
     - task: PublishCodeCoverageResults@1
       displayName: 'Publish code coverage report'
       inputs:
         codeCoverageTool: 'Cobertura'
         summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'
     
     - task: DotNetCoreCLI@2
       displayName: 'Publish website'
       inputs:
         command: 'publish'
         publishWebProjects: true
         arguments: '--configuration $(buildConfiguration) --output $(Build.ArtifactStagingDirectory)'
         zipAfterPublish: true
     
     - task: PublishBuildArtifacts@1
       displayName: 'Publish artifacts'
       inputs:
         PathtoPublish: '$(Build.ArtifactStagingDirectory)'
         ArtifactName: 'webapp'
     ```

---

7. **Configuration du pipeline pour Node.js**

   - Modifiez le YAML comme suit:
     ```yaml
     trigger:
       branches:
         include:
         - main
         - feature/*
       paths:
         include:
         - node-sample/**
         exclude:
         - '*.md'
     
     pool:
       vmImage: 'ubuntu-latest'
     
     steps:
     - task: NodeTool@0
       inputs:
         versionSpec: '16.x'
       displayName: 'Install Node.js'
     
     - script: |
         cd node-sample
         npm install
       displayName: 'npm install'
     
     - script: |
         cd node-sample
         npm test
       displayName: 'Run tests'
     
     - script: |
         cd node-sample
         npm test -- --coverage
       displayName: 'Run tests with coverage'
     
     - task: PublishTestResults@2
       inputs:
         testResultsFormat: 'JUnit'
         testResultsFiles: '**/junit.xml'
         searchFolder: '$(System.DefaultWorkingDirectory)/node-sample'
         mergeTestResults: true
         testRunTitle: 'Node.js Tests'
       condition: succeededOrFailed()
       displayName: 'Publish test results'
     
     - task: PublishCodeCoverageResults@1
       inputs:
         codeCoverageTool: 'Cobertura'
         summaryFileLocation: '$(System.DefaultWorkingDirectory)/node-sample/coverage/cobertura-coverage.xml'
         reportDirectory: '$(System.DefaultWorkingDirectory)/node-sample/coverage'
       displayName: 'Publish code coverage'
     
     - task: ArchiveFiles@2
       inputs:
         rootFolderOrFile: '$(System.DefaultWorkingDirectory)/node-sample'
         includeRootFolder: false
         archiveType: 'zip'
         archiveFile: '$(Build.ArtifactStagingDirectory)/$(Build.BuildId).zip'
         replaceExistingArchive: true
       displayName: 'Archive files'
     
     - task: PublishBuildArtifacts@1
       inputs:
         PathtoPublish: '$(Build.ArtifactStagingDirectory)'
         ArtifactName: 'node-app'
         publishLocation: 'Container'
       displayName: 'Publish artifacts'
     ```

---

8. **Sauvegarde et exécution du pipeline**

   - Cliquez sur "Save and run"
   - Observez l'exécution du pipeline
   - Vérifiez que les tests sont exécutés et que les résultats sont publiés

---

#### Partie 3 : Test et amélioration des déclencheurs

9. **Ajout de déclencheurs pour Pull Requests**

   - Modifiez la section `trigger` dans votre YAML:
     ```yaml
     trigger:
       branches:
         include:
         - main
         - feature/*
       paths:
         include:
         - WebApiSample/** # ou node-sample/**
         exclude:
         - '*.md'
     
     pr:
       branches:
         include:
         - main
       paths:
         include:
         - WebApiSample/** # ou node-sample/**
         exclude:
         - '*.md'
     ```

---

10. **Test des déclencheurs**

    - Créez une nouvelle branche: `git checkout -b feature/nouvelle-fonctionnalite`
    - Ajoutez un fichier ou modifiez du code existant
    - Committez et poussez: 
      ```bash
      git add .
      git commit -m "Ajout d'une nouvelle fonctionnalité"
      git push --set-upstream origin feature/nouvelle-fonctionnalite
      ```
    - Dans Azure DevOps, créez une Pull Request vers la branche main
    - Vérifiez que le pipeline se déclenche automatiquement

---

#### Partie 4 : Configuration de la couverture de code et des badges

11. **Amélioration de la couverture de code**

    - Ajoutez d'autres tests pour augmenter la couverture
    - Pour .NET Core, ajoutez des tests supplémentaires pour couvrir différentes conditions
    - Pour Node.js, assurez-vous que Jest est configuré pour la couverture

---

12. **Ajout d'un badge de build au README**

    - Créez un fichier README.md à la racine du projet
    - Dans Azure DevOps, naviguez vers votre pipeline
    - Cliquez sur les "..." et sélectionnez "Status badge"
    - Copiez le markdown du badge
    - Ajoutez-le à votre README.md:
      ```markdown
      # Projet Demo CI/CD
      
      [![Build Status](https://dev.azure.com/votre-org/votre-projet/_apis/build/status/votre-pipeline?branchName=main)](https://dev.azure.com/votre-org/votre-projet/_build/latest?definitionId=X&branchName=main)
      
      Cette application démontre l'intégration continue avec Azure Pipelines.
      ```
    - Committez et poussez le README

---

13. **Configuration des politiques de branche**

    - Dans Azure DevOps, allez dans *Repos > Branches*
    - Cliquez sur "..." à côté de la branche main
    - Sélectionnez "Branch policies"
    - Activez "Require a minimum number of reviewers"
    - Ajoutez votre pipeline dans "Build validation"
    - Sauvegardez les politiques

### Livrables

- Application web avec tests unitaires
- Pipeline CI fonctionnel avec déclencheurs configurés
- Rapports de test et de couverture de code
- README avec badge de build
- Pull Request démontrant le déclenchement automatique du pipeline

### Ressources supplémentaires

- [Documentation des déclencheurs de pipelines](https://docs.microsoft.com/azure/devops/pipelines/build/triggers)
- [Publication des résultats de test](https://docs.microsoft.com/azure/devops/pipelines/test/review-continuous-test-results-after-build)
- [Analyse de couverture de code](https://docs.microsoft.com/azure/devops/pipelines/tasks/test/publish-code-coverage-results)

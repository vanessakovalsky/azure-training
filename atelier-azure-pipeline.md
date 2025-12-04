# Atelier 2 : Activation de l'intégration continue avec Azure Pipelines


### Objectifs d'apprentissage
- Mettre en place un pipeline CI complet pour une application web
- Configurer des tests automatisés avec publication de résultats
- Implémenter l'analyse de couverture de code
- Comprendre les stratégies de déclenchement de builds

### Prérequis
- Accès à une organisation Azure DevOps
- Connaissances de base en développement web (Node.js)
- Git installé sur votre poste de travail

### Étapes détaillées

#### Partie 1 : Préparation du projet

1. **Création du dépôt**
   - Dans Azure DevOps, naviguez vers *Repos > New
   - Importer le dépôt depuis celui-ci : https://github.com/vanessakovalsky/express-demojs

2. **Cloner le dépôt en local sur votre machine**

#### Partie 2 : Configuration du pipeline CI

5. **Création du pipeline YAML**

   - Dans Azure DevOps, naviguez vers *Pipelines > Pipelines*
   - Cliquez sur "New pipeline"
   - Sélectionnez votre référentiel source
   - Choisissez le modèle "Node.js" ou "Starter pipeline"


6. **Configuration du pipeline pour Node.js**

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
         versionSpec: '18.x'
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

7. **Sauvegarde et exécution du pipeline**

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
         - node-sample/**
         exclude:
         - '*.md'
     
     pr:
       branches:
         include:
         - main
       paths:
         include:
         - node-sample/**
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

    - Vérifier la présence du fichier README.md à la racine du projet
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

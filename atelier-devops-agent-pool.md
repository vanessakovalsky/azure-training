# Atelier 1 : Configuration des pools d'agents et compréhension des styles de pipelines

### Durée estimée : 90 minutes

### Objectifs d'apprentissage
- Configurer un pool d'agents auto-hébergé dans Azure DevOps
- Comprendre les différences entre les pipelines YAML et Classic
- Maîtriser les concepts de capacités et demandes d'agent
- Identifier les scénarios appropriés pour chaque type de pipeline

### Prérequis
- Accès à une organisation Azure DevOps
- Machine virtuelle Windows, Linux ou macOS pour héberger l'agent
- Permissions suffisantes dans Azure DevOps pour créer des pools d'agents

### Étapes détaillées

#### Partie 1 : Création d'un pool d'agents auto-hébergé

1. **Connexion à Azure DevOps**
   - Connectez-vous à votre organisation Azure DevOps
   - Accédez au projet où vous souhaitez configurer le pool d'agents

2. **Création du pool d'agents**
   - Naviguez vers *Project Settings > Pipelines > Agent pools*
   - Cliquez sur "Add pool"
   - Sélectionnez "Self-hosted" comme type de pool
   - Nommez votre pool (ex: "WorkshopPool")
   - Cliquez sur "Create"

3. **Préparation de la machine pour l'agent**
   - Assurez-vous que la machine respecte les [prérequis système](https://docs.microsoft.com/azure/devops/pipelines/agents/v2-windows?view=azure-devops#check-prerequisites)
   - Pour Windows: PowerShell 3.0 ou supérieur, .NET Framework 4.6.2 ou supérieur
   - Pour Linux: GLIBC 2.17 ou supérieur, Curl, tar, git

---

#### Partie 2 : Installation et configuration de l'agent

4. **Téléchargement de l'agent**
   - Dans le pool d'agents nouvellement créé, cliquez sur "New agent"
   - Sélectionnez le système d'exploitation de votre machine (Windows/Linux/macOS)
   - Téléchargez le package de l'agent sur votre machine

---

5. **Installation de l'agent (Windows)**
   - Extrayez le package ZIP dans un dossier (ex: `C:\agents\agent1`)
   - Ouvrez PowerShell en tant qu'administrateur dans ce dossier
   - Exécutez la commande de configuration:
     ```powershell
     .\config.cmd --url https://dev.azure.com/votreorganisation --auth pat --token votrePersonalAccessToken --pool WorkshopPool --agent AgentName1 --replace
     ```
   - Suivez les instructions pour compléter la configuration
   - Installez l'agent comme service:
     ```powershell
     .\config.cmd --service install
     .\config.cmd --service start
     ```

---

6. **Installation de l'agent (Linux)**
   - Extrayez le package dans un dossier: `mkdir ~/agent && cd ~/agent && tar zxvf ~/Downloads/vsts-agent-linux-x64-VERSION.tar.gz`
   - Exécutez la configuration:
     ```bash
     ./config.sh --url https://dev.azure.com/votreorganisation --auth pat --token votrePersonalAccessToken --pool WorkshopPool --agent AgentName1 --replace
     ```
   - Installez et démarrez comme service:
     ```bash
     sudo ./svc.sh install
     sudo ./svc.sh start
     ```

7. **Vérification de l'installation**
   - Retournez dans Azure DevOps > Agent pools > WorkshopPool
   - Vérifiez que votre agent apparaît comme "Online"

---

#### Partie 3 : Configuration des capacités d'agent

8. **Ajout de capacités à l'agent**
   - Dans le pool d'agents, localisez votre agent
   - Allez dans l'onglet "Capabilities"
   - Ajoutez des capacités personnalisées:
     - Cliquez sur "Add capability"
     - Ajoutez `CustomTool` comme nom et `Workshop` comme valeur
     - Ajoutez `Environment` comme nom et `Training` comme valeur
   - Cliquez sur "Save"

9. **Examinez les capacités détectées automatiquement**
   - Observez les capacités découvertes automatiquement (OS, outils installés, etc.)
   - Notez comment ces capacités peuvent être utilisées dans les pipelines

---

#### Partie 4 : Création d'un pipeline YAML

10. **Création d'un dépôt de code simple**
    - Créez un nouveau référentiel dans Azure Repos ou utilisez un existant
    - Ajoutez un fichier `index.html` simple

---

11. **Création du pipeline YAML**
    - Dans votre projet Azure DevOps, naviguez vers *Pipelines > Pipelines*
    - Cliquez sur "New pipeline"
    - Sélectionnez votre référentiel source
    - Choisissez "Starter pipeline" comme modèle

---

    - Modifiez le YAML pour cibler votre agent auto-hébergé:
      ```yaml
      trigger:
      - main

      pool:
        name: WorkshopPool
        demands:
          - CustomTool -equals Workshop
          - Environment -equals Training

      steps:
      - script: echo Bonjour depuis l'agent $(Agent.Name)
        displayName: 'Echo agent info'

      - script: |
          echo Liste des capacités de l'agent:
          echo OS: $(Agent.OS)
          echo Directory: $(Agent.HomeDirectory)
        displayName: 'Liste des capacités'

      - script: |
          echo Contenu du répertoire de travail:
          dir
        displayName: 'Liste des fichiers'
        condition: eq(variables['Agent.OS'], 'Windows_NT')

      - script: |
          echo Contenu du répertoire de travail:
          ls -la
        displayName: 'Liste des fichiers'
        condition: ne(variables['Agent.OS'], 'Windows_NT')
      ```
    - Cliquez sur "Save and run"
    - Observez l'exécution du pipeline sur votre agent auto-hébergé

---

#### Partie 5 : Création d'un pipeline Classic

12. **Création du pipeline Classic**

    - Dans *Pipelines > Pipelines*, cliquez sur "New pipeline"
    - Choisissez "Use the classic editor"
    - Sélectionnez votre référentiel source
    - Choisissez "Empty job" comme modèle
    - Configurez l'agent:
      - Sélectionnez votre pool d'agents "WorkshopPool"
      - Dans "Demands", ajoutez vos contraintes personnalisées:
        - `CustomTool = Workshop`
        - `Environment = Training`

---

- Ajoutez trois tâches "Command line":
- 
      - Tâche 1:
        - Display name: "Echo agent info"
        - Script: `echo Bonjour depuis l'agent $(Agent.Name)`
      - Tâche 2:
        - Display name: "Liste des capacités"
        - Script: 
          ```
          echo Liste des capacités de l'agent:
          echo OS: $(Agent.OS)
          echo Directory: $(Agent.HomeDirectory)
          ```
      - Tâche 3:
        - Display name: "Liste des fichiers"
        - Script pour Windows: `dir`
        - Script pour Linux/macOS: `ls -la`
        - Control options > Run this task: Custom condition
        - Condition pour Windows: `eq(variables['Agent.OS'], 'Windows_NT')`
        - Créez une tâche similaire pour Linux avec condition inverse
    - Sauvegardez et exécutez le pipeline

---

#### Partie 6 : Comparaison et analyse

13. **Comparaison des approches**
    - Comparez les résultats d'exécution des deux pipelines
    - Analysez les logs générés
    - Notez les différences et similitudes dans la configuration

14. **Analyse des scénarios d'utilisation**
    - Discutez des cas d'utilisation appropriés pour:
      - Les agents Microsoft-hébergés vs auto-hébergés
      - Les pipelines YAML vs Classic
    - Considérez les facteurs tels que:
      - Besoins d'accès au réseau interne
      - Exigences de personnalisation
      - Gestion du code dans le référentiel (GitOps)

### Livrables
- Agent auto-hébergé fonctionnel dans Azure DevOps
- Pipeline YAML configuré pour utiliser l'agent auto-hébergé
- Pipeline Classic équivalent
- Document de comparaison des deux approches de pipeline

### Ressources supplémentaires
- [Documentation des agents auto-hébergés](https://docs.microsoft.com/azure/devops/pipelines/agents/agents)
- [Utilisation des demandes et capacités](https://docs.microsoft.com/azure/devops/pipelines/process/demands)
- [Comparaison des pipelines YAML et Classic](https://docs.microsoft.com/azure/devops/pipelines/get-started/pipelines-get-started)

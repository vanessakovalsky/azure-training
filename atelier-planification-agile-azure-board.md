# Atelier : Planification agile et gestion de portefeuille avec Azure Boards

### Objectifs

- Configurer Azure Boards pour la gestion agile des projets
- Créer et organiser un backlog de produit
- Configurer des sprints et des tableaux Kanban
- Établir un suivi du travail avec les requêtes et rapports
- Connecter les éléments de travail aux commits Git

### Prérequis

- Accès à un projet Azure DevOps
- Permissions pour créer et gérer des éléments de travail
- Un navigateur web moderne



### Étape 1 : Configuration initiale d'Azure Boards

1. **Accéder à Azure Boards**

   - Connectez-vous à votre organisation Azure DevOps
   - Sélectionnez votre projet
   - Cliquez sur "Boards" dans la barre de navigation gauche

2. **Choisir une méthodologie Agile**

   - Accédez à Paramètres du projet > Boards > Processus
   - Sélectionnez l'un des modèles suivants:
     - **Scrum** : Pour une approche Scrum stricte (Product Backlog Items, Sprints)
     - **Agile** : Pour une méthodologie hybride (User Stories, Iterations)
     - **Basic** : Pour une approche simplifiée (Issues, Epics)
     - **CMMI** : Pour des projets nécessitant plus de formalisme (Requirements, Reviews)

---

3. **Configurer les zones (Areas)**

   - Accédez à Paramètres du projet > Boards > Team configuration > Areas
   - Créez une structure qui reflète les composants de votre application:
     ```
     [Nom du Projet]
     ├── Frontend
     ├── Backend
     │   ├── API
     │   └── Database
     └── Infrastructure
     ```

4. **Configurer les itérations (Sprints)**

   - Accédez à Paramètres du projet > Boards > Team configuration > Iterations
   - Créez vos sprints avec les dates appropriées:
     ```
     [Nom du Projet]
     ├── Release 1
     │   ├── Sprint 1 (JJ/MM/AAAA - JJ/MM/AAAA)
     │   ├── Sprint 2 (JJ/MM/AAAA - JJ/MM/AAAA)
     │   └── Sprint 3 (JJ/MM/AAAA - JJ/MM/AAAA)
     └── Release 2
         ├── Sprint 4 (JJ/MM/AAAA - JJ/MM/AAAA)
         └── Sprint 5 (JJ/MM/AAAA - JJ/MM/AAAA)
     ```

---

5. **Configurer les équipes**

   - Accédez à Paramètres du projet > Teams
   - Créez des équipes correspondant à vos besoins:
     - Team Frontend
     - Team Backend
     - Team Infrastructure
   - Associez chaque équipe aux zones et itérations appropriées


### Étape 2 : Création de la structure de backlog

1. **Définir les Epics (grandes initiatives)**

   - Accédez à Boards > Backlogs > Epics
   - Créez 3-4 epics représentant les grandes fonctionnalités de votre produit
   - Exemple:
     ```
     Epic 1: Authentification & Sécurité
     Epic 2: Gestion des commandes
     Epic 3: Tableau de bord utilisateur
     Epic 4: Intégration des paiements
     ```

---

2. **Créer les Features (fonctionnalités)**

   - Accédez à Boards > Backlogs > Features
   - Créez des features rattachées à chaque epic
   - Exemple pour "Authentification & Sécurité":
     ```
     Feature 1: Inscription utilisateur
     Feature 2: Connexion avec authentification à deux facteurs
     Feature 3: Gestion des rôles et permissions
     Feature 4: Réinitialisation de mot de passe
     ```

---

3. **Définir les User Stories / PBIs**

   - Accédez à Boards > Backlogs > Stories / PBIs
   - Créez des stories détaillant les fonctionnalités
   - Utilisez le format: "En tant que [rôle], je veux [action] afin de [bénéfice]"
   - Exemple pour "Inscription utilisateur":
     ```
     Story 1: En tant que nouvel utilisateur, je veux créer un compte avec mon email afin d'accéder à l'application
     Story 2: En tant que système, je veux valider le format de l'email afin d'assurer des données correctes
     Story 3: En tant qu'administrateur, je veux voir les nouveaux inscrits afin de surveiller la croissance
     ```

---

4. **Définir l'effort et la valeur métier**

   - Pour chaque story, définissez:
     - Story Points (effort): utilisez la suite de Fibonacci (1, 2, 3, 5, 8, 13...)
     - Business Value: évaluez l'importance (ex: 1-10)
   - Utilisez la vue Planning Poker pour estimer en équipe

### Étape 3 : Configuration du tableau Kanban

1. **Personnaliser les colonnes Kanban**

   - Accédez à Boards > Boards
   - Cliquez sur l'icône d'engrenage (paramètres)
   - Configurez les colonnes suivantes:
     ```
     - Backlog (initial)
     - Analysed
     - In Progress (WIP limit: 3)
     - Code Review (WIP limit: 2)
     - Testing
     - Done (final)
     ```

---

2. **Configurer les couloirs (swimlanes)**

   - Dans les paramètres du tableau, accédez à "Swimlanes"
   - Créez les couloirs suivants:
     ```
     - Expedite (pour les urgences)
     - Standard (par défaut)
     - Technical Debt
     ```

3. **Tester le déplacement des cartes**

   - Déplacez quelques stories à travers les colonnes
   - Vérifiez que les limites WIP fonctionnent
   - Observez les changements automatiques d'état

### Étape 4 : Planification de Sprint

1. **Prioriser le Backlog**

   - Accédez à Boards > Backlogs
   - Réorganisez les items par drag & drop
   - Les items les plus importants doivent être en haut

2. **Planifier un Sprint**

   - Cliquez sur "Sprint" en haut du backlog
   - Sélectionnez le Sprint en cours
   - Faites glisser les stories du backlog vers le sprint
   - Vérifiez la capacité de l'équipe vs. la somme des points

---

3. **Définir la capacité de l'équipe**

   - Dans la vue Sprint, cliquez sur "Capacity"
   - Ajoutez les membres de l'équipe
   - Définissez les jours de congés et pourcentage d'allocation
   - Observez les graphiques de capacité

4. **Créer des tâches détaillées**

   - Pour chaque User Story, créez 3-5 tâches techniques
   - Estimez chaque tâche en heures
   - Assurez-vous que chaque tâche est assignée

### Étape 5 : Connexion avec le contrôle de code source

1. **Lier les éléments de travail aux branches**

   - Créez une nouvelle branche dans Azure Repos
   - Utilisez la convention: `type/ID-description-courte`
   - Exemple: `feature/1234-user-registration`

2. **Lier les commits aux éléments de travail**

   - Dans votre message de commit, référencez l'ID:
   ```
   git commit -m "Ajout du formulaire d'inscription #1234"
   ```

---

3. **Créer une Pull Request liée**

   - Dans Azure Repos, créez une Pull Request
   - Dans la description, utilisez `#ID` ou `AB#ID` pour lier l'élément

4. **Observer le tableau des liens**

   - Retournez dans Azure Boards
   - Ouvrez la story et vérifiez l'onglet "Development"
   - Constatez les liens automatiques avec les commits, branches et PRs

### Étape 6 : Suivi et rapports

1. **Créer des requêtes personnalisées**

   - Accédez à Boards > Queries
   - Créez une nouvelle requête:
     - Type: "Flat list of work items"
     - Colonnes: ID, Title, State, AssignedTo, Tags
     - Critères: State = "In Progress" AND AssignedTo = @Me

2. **Configurer un dashboard**

   - Accédez à Overview > Dashboards
   - Créez un nouveau dashboard "Sprint Status"
   - Ajoutez les widgets:
     - Burndown chart
     - Sprint Overview
     - Query Results (basé sur votre requête)
     - Velocity

---

3. **Analyser les métriques de cycle**

   - Accédez à Analytics > Velocity
   - Observez la vélocité sur plusieurs sprints
   - Identifiez les tendances et opportunités d'amélioration

4. **Créer un rapport personnalisé**

   - Accédez à Analytics > Analytics views
   - Créez une vue pour "Cycle Time"
   - Analysez le temps moyen entre les états

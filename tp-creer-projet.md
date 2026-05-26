# TP1 : Créer et configurer un nouveau projet Azure DevOps

**Durée estimée : 45 minutes**

#### Objectifs
- Créer un projet Azure DevOps
- Configurer la structure organisationnelle
- Définir les équipes et les sprints
- Gérer les permissions

#### Partie 1 : Création du projet (10 min)

**Scénario :**
Vous êtes responsable de la mise en place d'un nouveau projet pour une application e-commerce nommée "ShopConnect".

**Tâches :**

1. Connectez-vous à Azure DevOps (https://dev.azure.com)

2. Créez un nouveau projet avec les paramètres suivants :
   - **Nom** : ShopConnect
   - **Description** : Application e-commerce multi-plateforme
   - **Visibility** : Private
   - **Version control** : Git
   - **Work item process** : Agile

3. Vérifiez la création en accédant aux différentes sections (Boards, Repos, Pipelines)

#### Partie 2 : Configuration de la structure (15 min)

**Area Paths à créer :**

```
ShopConnect
├─ Frontend
│  ├─ Web
│  └─ Mobile
├─ Backend
│  ├─ API
│  └─ Database
├─ Infrastructure
└─ Security
```

**Étapes :**

1. Aller dans **Project Settings** → **Project configuration** → **Areas**
2. Créer la structure ci-dessus
3. Pour chaque area, définir une description

**Iterations (Sprints) à créer :**

```
ShopConnect
├─ Release 1.0
│  ├─ Sprint 1 (2 semaines à partir d'aujourd'hui)
│  ├─ Sprint 2 (2 semaines suivantes)
│  └─ Sprint 3 (2 semaines suivantes)
```

**Étapes :**

1. Aller dans **Project Settings** → **Project configuration** → **Iterations**
2. Créer les releases et sprints avec les dates appropriées

#### Partie 3 : Création des équipes (10 min)

**Équipes à créer :**

1. **Frontend Team**
   - Area paths : Frontend
   - Membres : Vous-même + 2 utilisateurs fictifs

2. **Backend Team**
   - Area paths : Backend
   - Membres : Vous-même + 2 utilisateurs fictifs

**Étapes :**

1. Aller dans **Project Settings** → **Teams**
2. Créer les équipes
3. Configurer leurs area paths respectifs
4. Configurer les iterations par défaut

#### Partie 4 : Configuration des permissions (10 min)

**Scénario de permissions :**

- **Alice** (alice@example.com) : Project Administrator
- **Bob** (bob@example.com) : Développeur Frontend (Contributor)
- **Charlie** (charlie@example.com) : QA Tester (Contributor avec accès Test Plans)
- **David** (david@example.com) : Stakeholder (Reader)

**Tâches :**

1. Inviter les utilisateurs dans le projet
2. Assigner les groupes appropriés
3. Configurer les permissions sur le repository :
   - Bob : Peut créer des branches et faire des pull requests
   - Charlie : Lecture seule sur le code
   - David : Aucun accès au code

4. Protéger la branche `main` avec les policies suivantes :
   - Minimum 1 reviewer requis
   - Check for linked work items
   - Build validation (sera configurée plus tard)

#### Livrables attendus

À la fin du TP, vous devez avoir :

✅ Un projet Azure DevOps fonctionnel nommé "ShopConnect"
✅ Une structure d'area paths organisée par composant
✅ 3 sprints planifiés sur 6 semaines
✅ 2 équipes configurées avec leurs zones respectives
✅ 4 utilisateurs avec des permissions différenciées
✅ Une branche `main` protégée par des policies

#### Questions de validation

1. Quelle est la différence entre un Area Path et une Iteration ?
2. Pourquoi est-il important de protéger la branche `main` ?
3. Quel groupe de sécurité devriez-vous utiliser pour un consultant externe qui doit uniquement consulter l'avancement ?
4. Comment pouvez-vous visualiser rapidement qui a accès à votre projet ?

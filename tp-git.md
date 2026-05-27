# TP2 : Utiliser Git avec Azure DevOps

**Durée estimée : 90 minutes**

#### Objectifs
- Cloner un repository Azure DevOps
- Créer et gérer des branches
- Faire des commits et des push
- Créer une Pull Request
- Résoudre un conflit de fusion

---

#### Partie 1 : Configuration et clonage (20 min)

**Prérequis :**
- Projet "ShopConnect" créé au TP1
- Git installé sur votre machine
- Visual Studio ou VS Code installé

**Tâches :**

1. **Configurer Git localement**

```bash
# Ouvrir un terminal (Git Bash sur Windows)
# Configurer votre identité
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@example.com"

# Configurer l'éditeur par défaut
git config --global core.editor "code --wait"  # VS Code
# OU
git config --global core.editor "notepad"      # Notepad

# Vérifier la configuration
git config --list
```

2. **Créer un repository dans Azure DevOps**

```
Azure DevOps → ShopConnect → Repos → Initialize repository
Options:
- ✓ Add a README
- ✓ Add .gitignore: VisualStudio
- □ Add a license
```

3. **Cloner le repository**

```bash
# Méthode 1: HTTPS
cd C:\Projects
git clone https://dev.azure.com/<votre-org>/ShopConnect/_git/ShopConnect
cd ShopConnect

# Vérifier
git remote -v
git branch
ls  # Voir README.md et .gitignore
```

4. **Exploration du repository**

```bash
# Voir l'historique
git log --oneline

# Voir le contenu de .gitignore
cat .gitignore

# Vérifier le statut
git status
```

---

#### Partie 2 : Créer une structure de projet (25 min)

**Scénario :** Créer la structure initiale d'une application ASP.NET Core

**Tâches :**

1. **Créer la structure de dossiers**

```bash
# Dans le répertoire ShopConnect
mkdir src
mkdir tests
mkdir docs

cd src
mkdir ShopConnect.Web
mkdir ShopConnect.API
mkdir ShopConnect.Core

cd ../tests
mkdir ShopConnect.Tests

cd ..
```

2. **Créer des fichiers de base**

```bash
# README pour chaque composant
echo "# ShopConnect Web Application" > src/ShopConnect.Web/README.md
echo "# ShopConnect API" > src/ShopConnect.API/README.md
echo "# ShopConnect Core Library" > src/ShopConnect.Core/README.md
echo "# ShopConnect Tests" > tests/ShopConnect.Tests/README.md

# Documentation
echo "# Architecture Overview" > docs/ARCHITECTURE.md
echo "# API Documentation" > docs/API.md
```

3. **Ajouter et commiter les changements**

```bash
# Voir les fichiers non trackés
git status

# Ajouter tous les nouveaux fichiers
git add .

# Vérifier ce qui va être commité
git status

# Faire le commit
git commit -m "feat: add initial project structure

- Create src, tests, and docs directories
- Add README files for each component
- Add architecture documentation"

# Pousser vers Azure DevOps
git push origin main
```

4. **Vérifier dans Azure DevOps**

```
Azure DevOps → Repos → Files
Vérifier que la structure est présente:
ShopConnect/
├─ src/
│  ├─ ShopConnect.Web/
│  ├─ ShopConnect.API/
│  └─ ShopConnect.Core/
├─ tests/
│  └─ ShopConnect.Tests/
├─ docs/
│  ├─ ARCHITECTURE.md
│  └─ API.md
├─ .gitignore
└─ README.md
```

---

#### Partie 3 : Branches et développement de features (25 min)

**Scénario :** Développer deux features en parallèle

**Feature 1 : Authentication (Vous)**

```bash
# 1. Créer et basculer sur la branche feature
git checkout -b feature/authentication
```
* Sous linux: 
```bash
# 2. Créer le fichier AuthController.cs
cat > src/ShopConnect.API/AuthController.cs << 'EOF'
using Microsoft.AspNetCore.Mvc;

namespace ShopConnect.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        [HttpPost("login")]
        public IActionResult Login([FromBody] LoginRequest request)
        {
            // TODO: Implement login logic
            return Ok(new { token = "sample-jwt-token" });
        }

        [HttpPost("register")]
        public IActionResult Register([FromBody] RegisterRequest request)
        {
            // TODO: Implement registration logic
            return Ok(new { message = "User registered successfully" });
        }
    }

    public class LoginRequest
    {
        public string Email { get; set; }
        public string Password { get; set; }
    }

    public class RegisterRequest
    {
        public string Email { get; set; }
        public string Password { get; set; }
        public string ConfirmPassword { get; set; }
    }
}
EOF
```
* Avecc powershell :
```psh
@'
using Microsoft.AspNetCore.Mvc;

 

namespace ShopConnect.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        [HttpPost("login")]
        public IActionResult Login([FromBody] LoginRequest request)
        {
            // TODO: Implement login logic
            return Ok(new { token = "sample-jwt-token" });
        }

 

        [HttpPost("register")]
        public IActionResult Register([FromBody] RegisterRequest request)
        {
            // TODO: Implement registration logic
            return Ok(new { message = "User registered successfully" });
        }
    }

 

    public class LoginRequest
    {
        public string Email { get; set; }
        public string Password { get; set; }
    }

 

    public class RegisterRequest
    {
        public string Email { get; set; }
        public string Password { get; set; }
        public string ConfirmPassword { get; set; }
    }
}
'@ > src/ShopConnect.API/AuthController.cs
```
```bash
# 3. Mettre à jour la documentation
cat >> docs/API.md << 'EOF'

## Authentication Endpoints

### POST /api/auth/login
Authenticate a user and return a JWT token.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### POST /api/auth/register
Register a new user.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "password123",
  "confirmPassword": "password123"
}
```
EOF

# 4. Commiter les changements
git add .
git commit -m "feat(auth): add authentication endpoints

- Add AuthController with login and register endpoints
- Add request models for authentication
- Update API documentation"

# 5. Pousser la branche
git push origin feature/authentication
```

**Feature 2 : Product Catalog (Simuler un collègue)**

```bash
# Revenir sur main
git checkout main

# Créer une nouvelle branche
git checkout -b feature/product-catalog

# Créer ProductController.cs
cat > src/ShopConnect.API/ProductController.cs << 'EOF'
using Microsoft.AspNetCore.Mvc;

namespace ShopConnect.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ProductController : ControllerBase
    {
        [HttpGet]
        public IActionResult GetAll()
        {
            // TODO: Implement product listing
            return Ok(new[] { 
                new { id = 1, name = "Product 1", price = 29.99 },
                new { id = 2, name = "Product 2", price = 49.99 }
            });
        }

        [HttpGet("{id}")]
        public IActionResult GetById(int id)
        {
            // TODO: Implement product details
            return Ok(new { id, name = "Product", price = 29.99 });
        }

        [HttpPost]
        public IActionResult Create([FromBody] CreateProductRequest request)
        {
            // TODO: Implement product creation
            return CreatedAtAction(nameof(GetById), new { id = 1 }, request);
        }
    }

    public class CreateProductRequest
    {
        public string Name { get; set; }
        public decimal Price { get; set; }
        public string Description { get; set; }
    }
}
EOF

# Commiter et pousser
git add .
git commit -m "feat(products): add product catalog endpoints"
git push origin feature/product-catalog
```

---

#### Partie 4 : Pull Requests (20 min)

**Créer une Pull Request pour feature/authentication**

1. **Via l'interface Azure DevOps**

```
Azure DevOps → Repos → Pull Requests → New Pull Request

Source branch: feature/authentication
Target branch: main

Title: Add authentication endpoints
Description:
## Changes
- Add AuthController with login and register endpoints
- Add authentication documentation

## Testing
- Manual testing completed
- Unit tests will be added in next iteration

## Related Work Items
Fixes #[Work Item ID]

Reviewers: [Ajouter des reviewers]
Work Items: [Lier un work item si disponible]

[Create]
```

2. **Configurer la Pull Request** (ces option seront visible au moment de l'approbation, les configurations se font dans les paramètres du projet, au niveau des policy de branches)

```
Options à vérifier:
✓ Delete feature/authentication after merging
✓ Complete associated work items after merging
✓ Squash changes when merging (pour un historique propre)
```

3. **Review de code**

```
En tant que reviewer:
1. Aller dans la PR
2. Files → Voir les changements
3. Ajouter des commentaires:
   - Cliquer sur une ligne de code
   - Ajouter un commentaire constructif
   - Exemples:
     • "Consider adding input validation here"
     • "Great! This follows our coding standards"
     • "Could you add XML comments for this method?"
4. Status: Approve ✓
```

4. **Compléter la Pull Request**

```
Une fois approuvée:
1. Vérifier que tous les commentaires sont résolus
2. [Complete] → [Complete merge]
3. Vérifier que la branche est supprimée
```

5. **Mettre à jour votre repository local**

```bash
# Basculer sur main
git checkout main

# Récupérer les dernières modifications
git pull origin main

# Vérifier que votre feature est intégrée
git log --oneline -5

# Supprimer la branche locale (optionnel, déjà supprimée en remote)
git branch -d feature/authentication
```

---

#### Partie 5 : Gestion de conflits (20 min)

**Scénario :** Deux développeurs modifient le même fichier

**Setup du conflit :**

1. **Créer une modification sur main (simuler un autre dev)**

```bash
git checkout main
git pull

# Modifier README.md directement sur main (normalement à éviter!)
echo "## Project Status: In Development" >> README.md

git add README.md
git commit -m "docs: update project status"
git push origin main
```

2. **Créer une branche avec modification conflictuelle**

```bash
# Créer une branche depuis l'ancien main (avant le push)
git checkout -b feature/update-readme origin/main~1

# Modifier README.md différemment
echo "## Current Status: Active Development" >> README.md

git add README.md
git commit -m "docs: add project status section"
git push origin feature/update-readme
```

3. **Créer une Pull Request → Conflit détecté**

```
Azure DevOps → Create PR: feature/update-readme → main

⚠️ Message affiché:
"Merge conflicts exist. Resolve conflicts before completing this pull request."
```

**Résolution du conflit :**

**Option 1 : Via Azure DevOps Web (simple)**

```
1. Dans la PR, cliquer sur [Resolve conflicts]
2. Sélectionner README.md
3. Éditeur de conflit s'affiche:

<<<<<<< feature/update-readme (Your changes)
## Current Status: Active Development
=======
## Project Status: In Development
>>>>>>> main (Changes in main)

4. Éditer manuellement pour combiner:
## Project Status: Active Development

5. [Mark as resolved]
6. [Commit merge]
```

**Option 2 : Via ligne de commande (recommandé)**

```bash
# Sur votre branche
git checkout feature/update-readme

# Mettre à jour votre branche avec main
git fetch origin
git merge origin/main

# Conflit détecté!
# Auto-merging README.md
# CONFLICT (content): Merge conflict in README.md

# Ouvrir le fichier dans un éditeur
code README.md

# Voir les marqueurs de conflit:
<<<<<<< HEAD
## Current Status: Active Development
=======
## Project Status: In Development
>>>>>>> origin/main

# Éditer pour résoudre (supprimer les marqueurs):
## Project Status: Active Development

# Sauvegarder, puis:
git add README.md
git commit -m "merge: resolve conflict in README.md"
git push origin feature/update-readme

# Retourner à la PR → Le conflit est résolu → [Complete]
```

---

#### Livrables attendus

À la fin du TP, vous devez avoir :

✅ Repository "ShopConnect" cloné localement
✅ Structure de projet créée et poussée
✅ Deux branches de feature créées avec du code
✅ Au moins une Pull Request créée, reviewée et mergée
✅ Un conflit de merge résolu

---

#### Questions de validation

1. **Quelle est la différence entre `git fetch` et `git pull` ?**
   - Réponse attendue : `git fetch` télécharge les commits distants sans les fusionner, `git pull` fait un `fetch` suivi d'un `merge`.

2. **Pourquoi est-il important de faire des Pull Requests plutôt que de pousser directement sur `main` ?**
   - Réponse attendue : Review de code, validation automatique (CI), traçabilité, prévention d'erreurs.

3. **Comment annuler le dernier commit (qui n'a pas encore été poussé) ?**
   - Réponse attendue : `git reset HEAD~1` (garde les changements) ou `git reset --hard HEAD~1` (supprime les changements).

4. **Que se passe-t-il si vous faites un `git push --force` sur une branche partagée ?**
   - Réponse attendue : Écrase l'historique distant, peut perdre le travail des autres développeurs → À ÉVITER sur les branches partagées.

---

#### Exercices bonus (optionnels)

**Bonus 1 : Git Aliases**

Créer des alias pour simplifier les commandes courantes :

```bash
git config --global alias.st "status -sb"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.cm "commit -m"
git config --global alias.lg "log --graph --oneline --decorate --all"
git config --global alias.last "log -1 HEAD"

# Utiliser les alias
git st      # au lieu de git status
git lg      # voir un beau graphe des branches
```

**Bonus 2 : Git Hooks**

Créer un hook pre-commit pour vérifier le format des messages de commit :

```bash
# Créer le fichier .git/hooks/commit-msg
cat > .git/hooks/commit-msg << 'EOF'
#!/bin/sh

commit_msg=$(cat "$1")
pattern="^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .+"

if ! echo "$commit_msg" | grep -qE "$pattern"; then
    echo "ERROR: Commit message format incorrect!"
    echo "Format attendu: <type>(<scope>): <message>"
    echo "Example: feat(auth): add login endpoint"
    exit 1
fi
EOF

# Rendre exécutable
chmod +x .git/hooks/commit-msg

# Tester
git commit -m "mauvais message"  # ❌ Refusé
git commit -m "feat(auth): valid message"  # ✅ Accepté
```

**Bonus 3 : Utiliser Git Stash**

Scénario : Vous travaillez sur une feature mais devez rapidement corriger un bug :

```bash
# Vous êtes sur feature/payment avec des modifications non commitées
git status
# modified: PaymentController.cs

# Urgence : corriger un bug sur main
git stash save "WIP: payment gateway integration"

# Basculer sur main et créer une branche de bugfix
git checkout main
git checkout -b bugfix/critical-error

# Corriger le bug...
# git add, git commit, git push, créer PR, etc.

# Revenir à votre feature
git checkout feature/payment
git stash pop

# Continuer votre travail
```

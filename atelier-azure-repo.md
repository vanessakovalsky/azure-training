# Atelier : Contrôle de version avec Git dans Azure Repos

### Objectifs pédagogiques

À la fin de cet atelier, les participants seront capables de :

- Configurer et utiliser Azure Repos avec Git
- Comprendre les concepts fondamentaux du contrôle de version distribué
- Appliquer les meilleures pratiques Git dans un contexte DevOps d'entreprise
- Gérer efficacement les branches, les pull requests et les stratégies de branche
- Intégrer Azure Repos avec les workflows CI/CD d'Azure DevOps

### Prérequis

- Un compte Azure DevOps actif
- Git installé localement (version 2.25 ou ultérieure)
- Visual Studio Code ou IDE préféré
- Notions de base en développement logiciel
- Connexion internet stable

### Durée approximative

- 3 heures


### Partie 1 : Configuration initiale d'Azure Repos

#### Exercice 1.1 : Création d'un projet Azure DevOps et initialisation d'un dépôt Git

1. Connectez-vous à votre compte Azure DevOps
2. Créez un nouveau projet :
   - Nom : `AZ400-Git-Workshop`
   - Description : `Atelier pour la certification AZ-400 - Contrôle de version avec Git`
   - Visibilité : `Privée`
   - Contrôle de version : `Git`
   
3. Une fois le projet créé, naviguez vers la section **Repos**
4. Notez l'URL du dépôt Git qui vient d'être créé

---

#### Exercice 1.2 : Configuration de Git en local

1. Ouvrez un terminal ou invite de commande
2. Configurez vos informations d'identification Git globales :

```bash
git config --global user.name "Votre Nom"
git config --global user.email "votre.email@domaine.com"
```

3. (Optionnel) Configurez d'autres paramètres utiles :

```bash
git config --global core.autocrlf true  # Pour les utilisateurs Windows
git config --global init.defaultBranch main
git config --global pull.rebase false
```

4. Vérifiez votre configuration :

```bash
git config --list
```

---

#### Exercice 1.3 : Clonage du dépôt

1. Dans Azure DevOps, accédez à votre dépôt et cliquez sur **Cloner**
2. Copiez l'URL HTTPS ou SSH (selon votre configuration)
3. Dans votre terminal, naviguez vers le dossier où vous souhaitez cloner le dépôt :

```bash
cd ~/Documents/Projets/  # Ou tout autre chemin de votre choix
git clone <URL_copiée>
cd AZ400-Git-Workshop
```

4. Vérifiez que le dépôt a été correctement cloné :

```bash
git status
```

### Partie 2 : Premiers pas avec Git dans Azure Repos

#### Exercice 2.1 : Structure du projet et premier commit

1. Créez la structure de base du projet :

```bash
mkdir src
mkdir docs
mkdir tests
```

2. Créez un fichier README.md à la racine du projet :

```bash
echo "# Projet AZ-400 Workshop\n\nCe projet est utilisé pour l'atelier Azure DevOps - Certification AZ-400." > README.md
```

3. Ajoutez et validez vos modifications :

```bash
git add .
git commit -m "Initial commit: structure de base du projet"
```

---

4. Poussez vos modifications vers Azure Repos :

```bash
git push origin main
```

5. Rafraîchissez votre navigateur pour voir les changements dans Azure Repos

---

#### Exercice 2.2 : Création de fichiers pour l'application

1. Créez un fichier application de base dans le dossier src :

```bash
echo "console.log('Application de démonstration pour Azure DevOps');" > src/app.js
```

2. Créez un fichier de documentation :

```bash
echo "# Documentation\n\nCe document contient la documentation pour l'application de démonstration." > docs/documentation.md
```

3. Ajoutez et validez ces fichiers :

```bash
git add src/app.js docs/documentation.md
git commit -m "Ajout des fichiers d'application et de documentation"
git push origin main
```

---

#### Exercice 2.3 : Utilisation de .gitignore

1. Créez un fichier .gitignore à la racine du projet :

```bash
echo "# Fichiers et dossiers à ignorer\nnode_modules/\n.vscode/\n*.log\n.env\ntmp/\ndist/" > .gitignore
```

2. Validez le fichier .gitignore :

```bash
git add .gitignore
git commit -m "Ajout du fichier .gitignore"
git push origin main
```

### Partie 3 : Travail avec les branches

#### Exercice 3.1 : Création d'une branche de fonctionnalité

1. Créez une nouvelle branche pour une fonctionnalité :

```bash
git checkout -b feature/nouvelle-fonctionnalite
```

2. Modifiez le fichier app.js :

```bash
echo "// Module principale de l'application\nfunction main() {\n  console.log('Application de démonstration pour Azure DevOps');\n  console.log('Nouvelle fonctionnalité ajoutée');\n}\n\nmain();" > src/app.js
```

3. Validez vos modifications sur cette branche :

```bash
git add src/app.js
git commit -m "Implémentation de la nouvelle fonctionnalité"
git push -u origin feature/nouvelle-fonctionnalite
```

---

#### Exercice 3.2 : Création d'une Pull Request

1. Dans Azure DevOps, naviguez vers **Repos > Pull Requests**
2. Cliquez sur **Nouvelle Pull Request**
3. Configurez la Pull Request :
   - Branche source : `feature/nouvelle-fonctionnalite`
   - Branche cible : `main`
   - Titre : `Ajout d'une nouvelle fonctionnalité`
   - Description : `Cette PR ajoute une nouvelle fonctionnalité à l'application principale.`
   
4. Assignez la PR à vous-même ou à un collègue
5. Cliquez sur **Créer**

---

#### Exercice 3.3 : Examen et validation d'une Pull Request

1. Examinez les changements de code dans l'interface d'Azure DevOps
2. Ajoutez un commentaire sur une ligne spécifique du code
3. Approuvez la Pull Request
4. Complétez la Pull Request avec l'option de fusion standard
5. Vérifiez que les changements ont été fusionnés dans la branche main

---

#### Exercice 3.4 : Synchronisation du dépôt local

1. Retournez à votre terminal
2. Basculez sur la branche main :

```bash
git checkout main
```

3. Récupérez les dernières modifications :

```bash
git pull origin main
```

4. Vérifiez que votre branche locale est à jour :

```bash
git log --oneline --graph --decorate --all -n 10
```


### Partie 4 : Stratégies de branche et protection du code

#### Exercice 4.1 : Configuration des stratégies de branche

1. Dans Azure DevOps, naviguez vers **Repos > Branches**
2. Localisez la branche `main`, cliquez sur les points de suspension (...) et sélectionnez **Stratégies de branche**
3. Configurez les stratégies suivantes :
   - **Nombre minimal de réviseurs** : 1
   - **Autoriser les votants à approuver leurs propres modifications** : Désactivé
   - **Validation du build** : Activé (si un pipeline est disponible)
   - **Liens de travail requis** : Activé

4. Cliquez sur **Enregistrer**

---

#### Exercice 4.2 : Travailler avec une branche protégée

1. Créez une nouvelle branche pour corriger un bogue :

```bash
git checkout -b bugfix/correction-erreur
```

2. Modifiez le fichier app.js pour corriger une "erreur" :

```bash
echo "// Module principale de l'application\nfunction main() {\n  console.log('Application de démonstration pour Azure DevOps');\n  console.log('Nouvelle fonctionnalité ajoutée - Bug corrigé');\n}\n\nmain();" > src/app.js
```

---


3. Validez vos modifications :

```bash
git add src/app.js
git commit -m "Correction du bug dans la nouvelle fonctionnalité"
git push -u origin bugfix/correction-erreur
```

4. Créez une Pull Request et observez comment les stratégies de branche sont appliquées


### Partie 5 : Résolution de conflits

#### Exercice 5.1 : Création d'un conflit

1. Créez deux branches différentes :

```bash
git checkout main
git pull
git checkout -b feature/equipe-a
```

2. Modifiez le fichier README.md dans cette branche :

```bash
echo "# Projet AZ-400 Workshop\n\nCe projet est utilisé pour l'atelier Azure DevOps - Certification AZ-400.\n\n## Équipe A\nContribution de l'équipe A au projet." > README.md
```

3. Validez et poussez les modifications :

```bash
git add README.md
git commit -m "Ajout de la section Équipe A dans README"
git push -u origin feature/equipe-a
```

---

4. Créez une autre branche à partir de main :

```bash
git checkout main
git checkout -b feature/equipe-b
```

5. Modifiez le même fichier README.md mais différemment :

```bash
echo "# Projet AZ-400 Workshop\n\nCe projet est utilisé pour l'atelier Azure DevOps - Certification AZ-400.\n\n## Fonctionnalités\nListe des fonctionnalités implémentées par l'équipe B." > README.md
```

6. Validez et poussez les modifications :

```bash
git add README.md
git commit -m "Ajout de la section Fonctionnalités dans README"
git push -u origin feature/equipe-b
```

---

#### Exercice 5.2 : Fusion et résolution de conflits

1. Fusionnez la branche feature/equipe-a dans main via une PR dans Azure DevOps
2. Essayez de fusionner feature/equipe-b dans main et observez le conflit

3. Pour résoudre le conflit localement :

```bash
git checkout main
git pull
git checkout feature/equipe-b
git merge main
```

---

4. Résolvez le conflit en modifiant le fichier README.md :

```bash
# Projet AZ-400 Workshop

Ce projet est utilisé pour l'atelier Azure DevOps - Certification AZ-400.

## Équipe A
Contribution de l'équipe A au projet.

## Fonctionnalités
Liste des fonctionnalités implémentées par l'équipe B.
```

5. Marquez le conflit comme résolu et terminez la fusion :

```bash
git add README.md
git commit -m "Résolution du conflit entre les équipes A et B"
git push origin feature/equipe-b
```

6. Créez une nouvelle PR pour fusionner feature/equipe-b dans main


### Partie 6 : Intégration avec les workflows CI/CD

#### Exercice 6.1 : Configuration d'un déclencheur de build sur les commits

1. Dans Azure DevOps, naviguez vers **Pipelines**
2. Créez un nouveau pipeline :
   - Sélectionnez **Azure Repos Git** comme source
   - Choisissez votre projet `AZ400-Git-Workshop`
   - Utilisez le modèle "Node.js" ou "Starter pipeline"

---
   
3. Modifiez le pipeline YAML pour inclure un déclencheur sur le dépôt Git :

```yaml
trigger:
- main
- feature/*

pool:
  vmImage: 'ubuntu-latest'

steps:
- script: echo "Exécution du build suite à un commit Git"
  displayName: 'Run build script'
```

4. Enregistrez et exécutez le pipeline

---

#### Exercice 6.2 : Tests des déclencheurs CI/CD

1. Créez une nouvelle branche de fonctionnalité :

```bash
git checkout main
git pull
git checkout -b feature/integration-ci-cd
```

2. Ajoutez un fichier de test simple :

```bash
mkdir -p tests/unit
echo "console.log('Test unitaire factice');\nconsole.log('Tous les tests ont réussi!');" > tests/unit/test.js
```

---

3. Validez et poussez les modifications :

```bash
git add tests/unit/test.js
git commit -m "Ajout de tests unitaires factices"
git push -u origin feature/integration-ci-cd
```

4. Observez le déclenchement automatique du pipeline CI dans Azure DevOps

### Partie 7 : Techniques Git avancées dans Azure Repos

#### Exercice 7.1 : Utilisation des tags Git

1. Créez un tag pour marquer une version de votre code :

```bash
git checkout main
git pull
git tag -a v1.0.0 -m "Version 1.0.0 - Premier livrable"
git push origin v1.0.0
```

2. Vérifiez dans Azure Repos que le tag est visible

---

#### Exercice 7.2 : Utilisation de git rebase

1. Créez une branche pour expérimenter le rebase :

```bash
git checkout -b feature/rebase-demo
```

2. Effectuez quelques modifications et commits :

```bash
echo "// Fichier de configuration\nconst config = {\n  env: 'development',\n  debug: true\n};\n\nmodule.exports = config;" > src/config.js
git add src/config.js
git commit -m "Ajout du fichier de configuration"

echo "// Utilitaires\nfunction formatDate(date) {\n  return date.toISOString();\n}\n\nmodule.exports = {\n  formatDate\n};" > src/utils.js
git add src/utils.js
git commit -m "Ajout de fonctions utilitaires"
```

---

3. Pendant ce temps, simulez des modifications sur main :

```bash
git checkout main
echo "# Tests\n\nCe dossier contient les tests automatisés du projet." > tests/README.md
git add tests/README.md
git commit -m "Documentation des tests"
git push origin main
```

4. Rebasez votre branche de fonctionnalité sur main :

```bash
git checkout feature/rebase-demo
git rebase main
```

5. Poussez les modifications (forcée car rebase) :

```bash
git push --force-with-lease origin feature/rebase-demo
```

---

#### Exercice 7.3 : Utilisation de git cherry-pick

1. Créez une nouvelle branche pour un hotfix :

```bash
git checkout main
git checkout -b hotfix/urgent-fix
```

2. Effectuez une correction :

```bash
echo "// Fichier avec correctif urgent\nconst fix = {\n  applyPatch: () => console.log('Correctif appliqué')\n};\n\nmodule.exports = fix;" > src/hotfix.js
git add src/hotfix.js
git commit -m "Ajout d'un correctif urgent"
```

3. Prenez note de l'identifiant du commit (hash)
4. Appliquez ce commit spécifique sur main :

```bash
git checkout main
git cherry-pick <hash_du_commit>
git push origin main
```

### Partie 8 : Audit et historique dans Azure Repos

#### Exercice 8.1 : Explorer l'historique des commits

1. Dans Azure DevOps, naviguez vers **Repos > Commits**
2. Explorez l'historique des commits pour le projet
3. Utilisez les filtres pour rechercher des commits spécifiques
4. Examinez les différences introduites par chaque commit

---

#### Exercice 8.2 : Utilisation des outils de blame

1. Dans Azure DevOps, naviguez vers **Repos > Files**
2. Ouvrez un fichier de votre choix (par exemple, README.md)
3. Cliquez sur **Blame** dans le menu supérieur
4. Observez qui a modifié quelles lignes et quand

---

#### Exercice 8.3 : Récupération d'anciennes versions

1. Dans votre terminal, affichez l'historique complet :

```bash
git log --pretty=format:"%h %ad | %s%d [%an]" --graph --date=short
```

2. Identifiez un commit ancien et récupérez temporairement son contenu :

```bash
git checkout <hash_du_commit> -- README.md
```

3. Examinez les différences :

```bash
git diff --staged README.md
```

4. Validez ou annulez ces modifications selon votre choix

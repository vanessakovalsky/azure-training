# Atelier 4 : Mise en œuvre des actions GitHub pour CI/CD

### Durée estimée : 120 minutes

### Objectifs d'apprentissage
- Configurer un workflow GitHub Actions complet pour CI/CD
- Utiliser des matrices pour tester sur plusieurs environnements
- Mettre en place le cache pour optimiser les performances
- Implémenter un processus de déploiement conditionnel
- Utiliser les secrets GitHub pour les informations sensibles

### Prérequis
- Compte GitHub
- Connaissances de base en Git et YAML
- Notions de développement Web (.NET Core ou Node.js ou Python)

### Étapes détaillées

#### Partie 1 : Préparation du dépôt GitHub

1. **Création du dépôt GitHub**
   - Connectez-vous à votre compte GitHub
   - Créez un nouveau dépôt (ex: "github-actions-workshop")
   - Initialisez-le avec un README.md
   - Ajoutez un .gitignore pour le langage que vous allez utiliser (Node.js, Python ou .NET)

---

2. **Clonage du dépôt et création d'une application web simple**

   - Clonez le dépôt sur votre machine locale
   - Pour Node.js:
     ```bash
     git clone https://github.com/votre-compte/github-actions-workshop
     cd github-actions-workshop
     npm init -y
     npm install express --save
     npm install jest supertest --save-dev
     ```

---

   - Créez un fichier `app.js` avec un serveur Express de base:
     ```javascript
     const express = require('express');
     const app = express();
     
     app.get('/', (req, res) => {
       res.send('Hello, GitHub Actions!');
     });
     
     app.get('/api/status', (req, res) => {
       res.json({ status: 'ok', version: '1.0.0' });
     });
     
     const port = process.env.PORT || 3000;
     
     if (require.main === module) {
       app.listen(port, () => {
         console.log(`Server running on port ${port}`);
       });
     }
     
     module.exports = app;
     ```

---

   - Créez un fichier de test `app.test.js`:
     ```javascript
     const request = require('supertest');
     const app = require('./app');
     
     test('GET / responds with Hello message', async () => {
       const response = await request(app).get('/');
       expect(response.status).toBe(200);
       expect(response.text).toContain('Hello, GitHub Actions');
     });
     
     test('GET /api/status returns correct status', async () => {
       const response = await request(app).get('/api/status');
       expect(response.status).toBe(200);
       expect(response.body).toHaveProperty('status', 'ok');
     });
     ```

---

   - Mettez à jour `package.json` pour ajouter des scripts:

```json
     "scripts": {
       "start": "node app.js",
       "test": "jest",
       "test:coverage": "jest --coverage"
     }
```

3. **Commit et push du code initial**
   ```bash
   git add .
   git commit -m "Initial commit with Express app and tests"
   git push
   ```

---

#### Partie 2 : Configuration d'un workflow GitHub Actions basique

4. **Création du répertoire de workflows**
   - Créez un répertoire `.github/workflows` à la racine de votre projet:
     ```bash
     mkdir -p .github/workflows
     ```

---

5. **Création d'un workflow CI basique**
   - Créez un fichier `.github/workflows/ci.yml`:
     ```yaml
     name: Node.js CI
     
     on:
       push:
         branches: [ main ]
       pull_request:
         branches: [ main ]
     
     jobs:
       build:
         runs-on: ubuntu-latest
         
         steps:
         - uses: actions/checkout@v3
         
         - name: Use Node.js 16.x
           uses: actions/setup-node@v3
           with:
             node-version: 16.x
             cache: 'npm'
         
         - name: Install dependencies
           run: npm ci
         
         - name: Run tests
           run: npm test
         
         - name: Check code style
           run: |
             echo "Checking code style (simulated)"
             # Ici, vous pourriez utiliser ESLint, Prettier, etc.
     ```

---

6. **Commit et push du workflow**

```bash
   git add .github/workflows/ci.yml
   git commit -m "Add basic GitHub Actions workflow"
   git push
```

7. **Vérification de l'exécution du workflow**
   - Dans GitHub, accédez à votre dépôt
   - Allez dans l'onglet "Actions"
   - Vérifiez que votre workflow s'est exécuté correctement
   - Examinez les logs d'exécution

---

#### Partie 3 : Configuration d'une matrice de tests

8. **Mise à jour du workflow pour utiliser une matrice**
   - Modifiez le fichier `.github/workflows/ci.yml`:
     ```yaml
     name: Node.js CI
     
     on:
       push:
         branches: [ main ]
       pull_request:
         branches: [ main ]
     
     jobs:
       test:
         runs-on: ${{ matrix.os }}
         
         strategy:
           matrix:
             os: [ubuntu-latest, windows-latest]
             node-version: [14.x, 16.x, 18.x]
             # Exclure certaines combinaisons si nécessaire
             exclude:
               - os: windows-latest
                 node-version: 14.x
         
         steps:
         - uses: actions/checkout@v3
         
         - name: Use Node.js ${{ matrix.node-version }}
           uses: actions/setup-node@v3
           with:
             node-version: ${{ matrix.node-version }}
             cache: 'npm'
         
         - name: Install dependencies
           run: npm ci
         
         - name: Run tests
           run: npm test
           
         - name: Generate test coverage
           run: npm run test:coverage
     ```

---

9. **Commit et push des modifications**

```bash
   git add .github/workflows/ci.yml
   git commit -m "Add test matrix across multiple Node.js versions and OSes"
   git push
```

10. **Vérification de l'exécution de la matrice**
    - Dans GitHub, accédez à l'onglet "Actions"
    - Observez comment plusieurs jobs sont exécutés pour chaque combinaison d'OS et de version Node.js
    - Examinez les résultats pour chaque combinaison

---

#### Partie 4 : Configuration du cache et optimisation

11. **Amélioration du cache pour les dépendances**
    - Modifiez le workflow pour optimiser le cache:
      ```yaml
      - name: Use Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v3
        with:
          node-version: ${{ matrix.node-version }}
          cache: 'npm'
      
      # Alternative plus détaillée si vous préférez:
      - name: Cache node modules
        uses: actions/cache@v3
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-
      ```

---

12. **Ajout d'étapes de publication d'artefacts**
    - Ajoutez les étapes suivantes à votre workflow:
      ```yaml
      - name: Archive production artifacts
        if: success() && matrix.os == 'ubuntu-latest' && matrix.node-version == '16.x'
        uses: actions/upload-artifact@v3
        with:
          name: node-app
          path: |
            .
            !node_modules/
            !.git/
      
      - name: Archive code coverage results
        if: success() && matrix.os == 'ubuntu-latest' && matrix.node-version == '16.x'
        uses: actions/upload-artifact@v3
        with:
          name: code-coverage-report
          path: coverage/
      ```

---

13. **Ajout d'un job de build séparé**
    - Restructurez le workflow pour séparer les tests et le build:
      ```yaml
      name: Node.js CI/CD
      
      on:
        push:
          branches: [ main ]
        pull_request:
          branches: [ main ]
      
      jobs:
        test:
          runs-on: ${{ matrix.os }}
          
          strategy:
            matrix:
              os: [ubuntu-latest, windows-latest]
              node-version: [14.x, 16.x, 18.x]
              exclude:
                - os: windows-latest
                  node-version: 14.x
          
          steps:
          - uses: actions/checkout@v3
          
          - name: Use Node.js ${{ matrix.node-version }}
            uses: actions/setup-node@v3
            with:
              node-version: ${{ matrix.node-version }}
              cache: 'npm'
          
          - name: Install dependencies
            run: npm ci
          
          - name: Run tests
            run: npm test
            
          - name: Generate test coverage
            run: npm run test:coverage
      
        build:
          needs: test
          runs-on: ubuntu-latest
          
          steps:
          - uses: actions/checkout@v3
          
          - name: Use Node.js 16.x
            uses: actions/setup-node@v3
            with:
              node-version: 16.x
              cache: 'npm'
          
          - name: Install dependencies
            run: npm ci
          
          - name: Build application
            run: |
              echo "Building application for production..."
              npm run build --if-present
          
          - name: Archive production artifacts
            uses: actions/upload-artifact@v3
            with:
              name: node-app
              path: |
                .
                !node_modules/
                !.git/
      ```

---

14. **Commit et push des modifications**

```bash
    git add .github/workflows/ci.yml
    git commit -m "Optimize workflow with caching and separate build job"
    git push
```

---

#### Partie 5 : Configuration des secrets et déploiement conditionnel

15. **Ajout de secrets GitHub**
    - Dans GitHub, accédez à votre dépôt
    - Allez dans *Settings > Secrets and variables > Actions*
    - Cliquez sur "New repository secret"
    - Ajoutez deux secrets:
      - Nom: `AZURE_CREDENTIALS` (avec une valeur JSON simulée pour l'atelier)
      - Nom: `DEPLOYMENT_URL` (avec une URL fictive, ex: https://myapp.azurewebsites.net)

---

16. **Ajout d'un job de déploiement**
    - Modifiez votre workflow pour ajouter un job de déploiement:
      ```yaml
      deploy:
        needs: build
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        runs-on: ubuntu-latest
        
        environment:
          name: production
          url: ${{ secrets.DEPLOYMENT_URL }}
        
        steps:
        - name: Download artifact
          uses: actions/download-artifact@v3
          with:
            name: node-app
        
        - name: Display structure of downloaded files
          run: ls -R
        
        - name: Set up Azure credentials
          uses: azure/login@v1
          with:
            creds: ${{ secrets.AZURE_CREDENTIALS }}
            # Note: Pour un vrai déploiement, utilisez des creds valides
        
        - name: 'Deploy to Azure Web App (simulated)'
          run: |
            echo "Deploying to ${{ secrets.DEPLOYMENT_URL }}"
            # Simulons le déploiement pour l'atelier
            echo "Application would be deployed to Azure Web App"
      ```

---

17. **Création d'un environnement GitHub**
    - Dans GitHub, accédez à votre dépôt
    - Allez dans *Settings > Environments*
    - Cliquez sur "New environment"
    - Nommez-le "production"
    - Activez "Required reviewers" et ajoutez-vous comme reviewer
    - Cliquez sur "Save protection rules"

18. **Commit et push du workflow complet**

```bash
    git add .github/workflows/ci.yml
    git commit -m "Add deployment job with environment protection"
    git push
```

---

#### Partie 6 : Test du processus CI/CD complet

19. **Test du processus par une Pull Request**
    - Créez une nouvelle branche: `git checkout -b feature/update-api`
    - Modifiez le code, par exemple, ajoutez un nouvel endpoint dans `app.js`:
      ```javascript
      app.get('/api/info', (req, res) => {
        res.json({
          name: 'github-actions-demo',
          environment: process.env.NODE_ENV || 'development',
          timestamp: new Date().toISOString()
        });
      });
      ```

---

- Ajoutez un test pour ce nouvel endpoint dans `app.test.js`:
```javascript
      test('GET /api/info returns application info', async () => {
        const response = await request(app).get('/api/info');
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('name');
        expect(response.body).toHaveProperty('timestamp');
      });
```
- Committez et pushez les modifications
- Créez une Pull Request vers la branche main
- Observez l'exécution des workflows de test

---

20. **Test du déploiement conditionnel**
    - Une fois les tests passés, fusionnez la Pull Request
    - Observez le déclenchement du workflow complet, y compris le job de déploiement
    - Notez comment le déploiement attend une approbation (si configuré)
    - Approuvez le déploiement et observez son exécution

21. **Ajout d'un badge de statut au README**
    - Modifiez le README.md pour ajouter un badge de statut:

```markdown
      # GitHub Actions Workshop
      
      ![CI/CD](https://github.com/votre-compte/github-actions-workshop/actions/workflows/ci.yml/badge.svg)
      
      This repository demonstrates a complete CI/CD pipeline using GitHub Actions.
```

- Committez et pushez les modifications

### Livrables
- Application web simple avec tests unitaires
- Workflow GitHub Actions avec matrice de tests
- Configuration de cache pour optimiser les performances
- Processus de build et publication d'artefacts
- Workflow de déploiement conditionnel avec protection d'environnement
- README avec badge de statut

### Ressources supplémentaires
- [Documentation GitHub Actions](https://docs.github.com/en/actions)
- [Marketplace GitHub Actions](https://github.com/marketplace?type=actions)
- [GitHub Actions pour Node.js](https://docs.github.com/en/actions/guides/building-and-testing-nodejs)
- [Utilisation des environnements](https://docs.github.com/en/actions/deployment/using-environments-for-deployment)

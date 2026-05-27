# TP4 : Générer les builds et compiler le projet

**Durée estimée : 90 minutes**

#### Objectifs
- Créer un pipeline de build YAML
- Compiler une application .NET
- Exécuter des tests unitaires
- Publier des artefacts
- Configurer les déclencheurs

---

#### Partie 1 : Préparer le code source (15 min)

**Créer une application .NET simple avec tests**

```bash
# Créer la structure
cd C:\Projects\ShopConnect
mkdir src tests
cd src

# Créer l'application Web API
dotnet new webapi -n ShopConnect.API
cd ShopConnect.API

# Créer un controller simple
cat > Controllers/ProductController.cs << 'EOF'
using Microsoft.AspNetCore.Mvc;

namespace ShopConnect.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductController : ControllerBase
{
    private static readonly List<Product> Products = new()
    {
        new Product { Id = 1, Name = "Laptop", Price = 999.99m },
        new Product { Id = 2, Name = "Mouse", Price = 29.99m },
        new Product { Id = 3, Name = "Keyboard", Price = 79.99m }
    };

    [HttpGet]
    public ActionResult<IEnumerable<Product>> GetAll()
    {
        return Ok(Products);
    }

    [HttpGet("{id}")]
    public ActionResult<Product> GetById(int id)
    {
        var product = Products.FirstOrDefault(p => p.Id == id);
        if (product == null)
            return NotFound();
        return Ok(product);
    }

    [HttpPost]
    public ActionResult<Product> Create(Product product)
    {
        product.Id = Products.Max(p => p.Id) + 1;
        Products.Add(product);
        return CreatedAtAction(nameof(GetById), new { id = product.Id }, product);
    }
}

public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
}
EOF

cd ../../tests

# Créer le projet de tests
dotnet new xunit -n ShopConnect.API.Tests
cd ShopConnect.API.Tests

# Ajouter référence au projet API
dotnet add reference ../../src/ShopConnect.API/ShopConnect.API.csproj

# Créer des tests
cat > ProductControllerTests.cs << 'EOF'
using ShopConnect.API.Controllers;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace ShopConnect.API.Tests;

public class ProductControllerTests
{
    [Fact]
    public void GetAll_ReturnsAllProducts()
    {
        // Arrange
        var controller = new ProductController();

        // Act
        var result = controller.GetAll();

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        var products = Assert.IsAssignableFrom<IEnumerable<Product>>(okResult.Value);
        Assert.Equal(3, products.Count());
    }

    [Fact]
    public void GetById_ExistingId_ReturnsProduct()
    {
        // Arrange
        var controller = new ProductController();

        // Act
        var result = controller.GetById(1);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result.Result);
        var product = Assert.IsType<Product>(okResult.Value);
        Assert.Equal(1, product.Id);
        Assert.Equal("Laptop", product.Name);
    }

    [Fact]
    public void GetById_NonExistingId_ReturnsNotFound()
    {
        // Arrange
        var controller = new ProductController();

        // Act
        var result = controller.GetById(999);

        // Assert
        Assert.IsType<NotFoundResult>(result.Result);
    }

    [Fact]
    public void Create_ValidProduct_ReturnsCreatedProduct()
    {
        // Arrange
        var controller = new ProductController();
        var newProduct = new Product { Name = "Monitor", Price = 299.99m };

        // Act
        var result = controller.Create(newProduct);

        // Assert
        var createdResult = Assert.IsType<CreatedAtActionResult>(result.Result);
        var product = Assert.IsType<Product>(createdResult.Value);
        Assert.Equal("Monitor", product.Name);
        Assert.True(product.Id > 0);
    }
}
EOF

# Tester localement
cd ..
dotnet test

# Pousser vers Azure Repos
cd ../..
git add .
git commit -m "feat: add API with unit tests"
git push origin main
```

---

#### Partie 2 : Créer le pipeline YAML (25 min)

**Créer le fichier de pipeline**

```bash
cd C:\Projects\ShopConnect

# Créer le pipeline
cat > azure-pipelines.yml << 'EOF'
# Starter pipeline for ShopConnect

trigger:
  branches:
    include:
    - main
    - develop
  paths:
    include:
    - src/*
    - tests/*
    exclude:
    - README.md
    - docs/*

pr:
  branches:
    include:
    - main
    - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'
  dotnetVersion: '8.0.x'
  solution: '**/*.sln'

name: $(Date:yyyyMMdd)$(Rev:.r)

stages:
- stage: Build
  displayName: 'Build and Test'
  jobs:
  - job: BuildJob
    displayName: 'Build Job'
    steps:
    
    - checkout: self
      displayName: 'Checkout source code'
      clean: true
    
    - task: UseDotNet@2
      displayName: 'Use .NET SDK $(dotnetVersion)'
      inputs:
        version: $(dotnetVersion)
        includePreviewVersions: false
    
    - task: DotNetCoreCLI@2
      displayName: 'Restore NuGet packages'
      inputs:
        command: 'restore'
        projects: '**/*.csproj'
    
    - task: DotNetCoreCLI@2
      displayName: 'Build solution'
      inputs:
        command: 'build'
        projects: '**/*.csproj'
        arguments: '--configuration $(buildConfiguration) --no-restore'
    
    - task: DotNetCoreCLI@2
      displayName: 'Run unit tests'
      inputs:
        command: 'test'
        projects: '**/*Tests.csproj'
        arguments: '--configuration $(buildConfiguration) --no-build --collect:"XPlat Code Coverage" --logger trx'
        publishTestResults: true
    
    - task: PublishCodeCoverageResults@1
      displayName: 'Publish code coverage'
      condition: succeeded()
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'
    
    - task: DotNetCoreCLI@2
      displayName: 'Publish application'
      inputs:
        command: 'publish'
        publishWebProjects: true
        arguments: '--configuration $(buildConfiguration) --output $(Build.ArtifactStagingDirectory) --no-build'
        zipAfterPublish: true
        modifyOutputPath: true
    
    - task: PublishBuildArtifacts@1
      displayName: 'Publish build artifacts'
      inputs:
        pathToPublish: '$(Build.ArtifactStagingDirectory)'
        artifactName: 'drop'
        publishLocation: 'Container'
    
    - script: |
        echo "Build Number: $(Build.BuildNumber)"
        echo "Build ID: $(Build.BuildId)"
        echo "Source Branch: $(Build.SourceBranchName)"
        echo "Commit: $(Build.SourceVersion)"
      displayName: 'Display build info'
EOF

# Commiter et pousser
git add azure-pipelines.yml
git commit -m "ci: add Azure Pipeline configuration"
git push origin main
```

**Créer le pipeline dans Azure DevOps**

```
1. Azure DevOps → Pipelines → New Pipeline
2. Where is your code? → Azure Repos Git
3. Select repository: ShopConnect
4. Configure: Existing Azure Pipelines YAML file
5. Path: /azure-pipelines.yml
6. [Continue]
7. [Run]
```

---

#### Partie 3 : Personnaliser et améliorer le pipeline (30 min)

**Ajouter des variables de groupe**

```
1. Pipelines → Library → + Variable group
   Name: ShopConnect-Build-Variables
   
   Variables:
   - DotNetVersion: 8.0.x
   - BuildConfiguration: Release
   - ArtifactName: shopconnect-artifacts
   
   [Save]

2. Modifier azure-pipelines.yml:
```

```yaml
variables:
- group: ShopConnect-Build-Variables
- name: vmImage
  value: 'ubuntu-latest'
```

**Ajouter un build badge**

```
1. Pipeline → [...] → Status badge
2. Copier le Markdown
3. Ajouter au README.md:

## Build Status

[![Build Status](https://dev.azure.com/your-org/ShopConnect/_apis/build/status/ShopConnect-CI?branchName=main)](https://dev.azure.com/your-org/ShopConnect/_build/latest?definitionId=XX&branchName=main)
```

**Ajouter un scheduled build (nightly)**

```yaml
# Ajouter après le trigger:
schedules:
- cron: "0 2 * * *"
  displayName: Nightly build
  branches:
    include:
    - main
  always: true
```

**Ajouter une notification d'échec**

```yaml
# Ajouter à la fin du job:
- task: Bash@3
  displayName: 'Notify on failure'
  condition: failed()
  inputs:
    targetType: 'inline'
    script: |
      echo "Build failed!"
      echo "Build number: $(Build.BuildNumber)"
      echo "Failed at: $(date)"
      # Ici: intégration avec Slack/Teams/Email
```

---

#### Partie 4 : Tester les déclencheurs (20 min)

**Test 1: Push trigger**

```bash
# Modifier un fichier
echo "// Comment" >> src/ShopConnect.API/Program.cs

git add .
git commit -m "test: trigger build on push"
git push origin main

# Vérifier que le build se déclenche automatiquement
```

**Test 2: Pull Request trigger**

```bash
# Créer une nouvelle branche
git checkout -b feature/add-category

# Modifier
cat >> src/ShopConnect.API/Controllers/ProductController.cs << 'EOF'

// TODO: Add category support
EOF

git add .
git commit -m "feat: add category TODO"
git push origin feature/add-category

# Créer une PR dans Azure DevOps
# Vérifier que le build PR se déclenche
```

**Test 3: Manual trigger**

```
1. Pipelines → ShopConnect-CI → Run pipeline
2. Branch: main
3. [Run]
```

---

#### Livrables attendus

À la fin du TP, vous devez avoir :

✅ Code source .NET avec tests unitaires
✅ Pipeline YAML fonctionnel
✅ Build successful avec tests passants
✅ Artefacts publiés
✅ Au moins 3 déclencheurs configurés
✅ Build badge ajouté au README

---

#### Questions de validation

1. **Quelle est la différence entre `trigger` et `pr` dans un pipeline YAML ?**
   
2. **Pourquoi est-il important de publier les résultats de tests et la couverture de code ?**
   
3. **Qu'est-ce qu'un artefact de build et à quoi sert-il ?**
   
4. **Comment empêcher un build de se déclencher sur certains chemins (ex: docs/) ?**

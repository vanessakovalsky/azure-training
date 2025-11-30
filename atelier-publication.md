### Atelier 1 : Contrôler les déploiements en utilisant les Release Gates

**Objectif :** Mettre en place des Release Gates dans Azure DevOps pour contrôler automatiquement la progression d'un déploiement.

**Durée :** 2 heures

**Prérequis :**

- Un compte Azure DevOps
- Un projet avec une application simple
- Un pipeline CI/CD de base

---

**Étapes :**

1. **Configuration des métriques de surveillance :**
   - Créer une application Azure App Service
   - Configurer Application Insights
   - Définir des alertes sur les métriques clés (temps de réponse, taux d'erreur)

2. **Création des Release Gates :**
   ```
   - Dans Azure DevOps, créer un pipeline de release
   - Configurer un pre-deployment gate :
     - Vérification des builds réussies
     - Vérification des PR approuvées
   - Configurer un post-deployment gate :
     - Vérification des alertes Application Insights
     - Vérification des tests de disponibilité
   ```

---

3. **Test du pipeline :**
   - Déclencher un déploiement
   - Observer le comportement des gates
   - Simuler des erreurs pour voir le blocage du déploiement

4. **Analyse et ajustement :**
   - Analyser les journaux de déploiement
   - Ajuster les seuils des métriques
   - Optimiser la configuration des gates

### Atelier 2 : Créer un tableau de bord des versions

**Objectif :** Construire un tableau de bord personnalisé dans Azure DevOps pour suivre l'état et la qualité des déploiements.

**Durée :** 1,5 heure

**Prérequis :**

- Un compte Azure DevOps
- Plusieurs pipelines de release configurés

---

**Étapes :**

1. **Analyse des besoins :**
   - Identifier les KPIs essentiels pour l'équipe
   - Définir les métriques à suivre (fréquence, succès/échec, durée)

2. **Configuration des widgets :**
   ```
   - Créer un nouveau tableau de bord dans Azure DevOps
   - Ajouter le widget "Deployment Status"
   - Ajouter le widget "Release Pipeline Overview"
   - Ajouter le widget "Query Results" pour les bugs post-déploiement
   - Configurer le widget "Metrics" pour les performances
   ```

---

3. **Personnalisation avancée :**
   - Créer des requêtes personnalisées pour les problèmes
   - Configurer des filtres par environnement
   - Ajouter des indicateurs visuels (feux tricolores)

4. **Partage et itération :**
   - Partager le tableau de bord avec l'équipe
   - Recueillir les commentaires
   - Affiner les métriques et la présentation

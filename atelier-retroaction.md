# Détail des Ateliers Azure DevOps et Gestion des Incidents

Guide étape par étape pour réaliser ces deux exercices.

---

## **Exercice 1 : Création d'un tableau de bord Azure DevOps**

### **Étape 1 : Préparation et planification (15-20 min)**

1. **Identifiez vos besoins**
   - Listez les équipes qui utiliseront le tableau de bord (développeurs, managers, ops)
   - Déterminez la fréquence de consultation (temps réel, quotidien, hebdomadaire)
   - Identifiez les projets Azure DevOps à surveiller

2. **Rassemblez les informations d'accès**
   - Vérifiez vos permissions sur Azure DevOps (vous devez être contributeur ou admin du projet)
   - Notez les noms des projets et repositories concernés

### **Étape 2 : Création du tableau de bord (10 min)**

1. Connectez-vous à Azure DevOps (dev.azure.com/votre-organisation)
2. Naviguez vers **Overview > Dashboards**
3. Cliquez sur **New Dashboard**
4. Nommez-le (exemple : "Tableau de Bord Production - Équipe Dev")
5. Choisissez **Team Dashboard** ou **Project Dashboard** selon votre besoin
6. Cliquez sur **Create**

### **Étape 3 : Configuration de l'état des builds (15-20 min)**

1. **Widget Build History**
   - Cliquez sur **Add Widget** (icône +)
   - Recherchez "Build History"
   - Faites glisser le widget sur le tableau de bord
   - Cliquez sur **Configure** (icône engrenage)
   - Sélectionnez votre pipeline de build
   - Définissez le nombre de builds à afficher (recommandé : 10-15)
   - Sauvegardez

2. **Widget Build Chart**
   - Ajoutez le widget "Chart for Build Pipelines"
   - Configurez-le pour afficher le taux de réussite
   - Choisissez la période (7 ou 30 derniers jours)
   - Sélectionnez le type de graphique (histogramme ou courbe)

### **Étape 4 : Affichage des bugs ouverts (20 min)**

1. **Créez une requête Work Items**
   - Allez dans **Boards > Queries**
   - Cliquez sur **New Query**
   - Configurez les critères :
     ```
     Work Item Type = Bug
     AND State = Active
     AND State = New
     ```
   - Ajoutez les colonnes : ID, Titre, Gravité, Assigné à, État
   - Sauvegardez la requête : "Bugs Ouverts"

2. **Ajoutez le widget Query Results**
   - Retournez au tableau de bord
   - Ajoutez "Query Results"
   - Sélectionnez votre requête "Bugs Ouverts"
   - Configurez l'affichage (liste ou graphique)

3. **Widget Chart pour les bugs par gravité**
   - Ajoutez "Chart for Work Items"
   - Créez un graphique en secteurs ou colonnes
   - Groupez par "Severity" (Critical, High, Medium, Low)
   - Filtrez sur Type = Bug et État ≠ Closed


### **Étape 5 : Évolution du backlog (15-20 min)**

1. **Widget Burndown**
   - Ajoutez "Sprint Burndown"
   - Sélectionnez votre équipe et le sprint actuel
   - Ce widget montre l'avancement du travail

2. **Widget Velocity**
   - Ajoutez "Velocity"
   - Configurez pour afficher les 6 derniers sprints
   - Permet de voir la capacité de livraison de l'équipe

3. **Widget Cumulative Flow Diagram**
   - Ajoutez "Cumulative Flow Diagram"
   - Montre la distribution des work items par état
   - Idéal pour identifier les goulots d'étranglement

4. **Widget Work Items Count**
   - Ajoutez plusieurs widgets "Query Tile"
   - Créez des compteurs pour :
     - Stories en cours
     - Stories à faire
     - Tasks en cours
     - Bugs ouverts

### **Étape 7 : Organisation et finalisation (15 min)**

1. **Organisez visuellement le tableau de bord**
   - Regroupez les widgets par thème (Build, Qualité, Backlog, Performance)
   - Utilisez des widgets "Markdown" comme séparateurs/titres
   - Ajustez les tailles pour optimiser l'espace

2. **Ajoutez un titre descriptif**
   - Widget "Markdown" en haut avec :
     ```markdown
     # 📊 Tableau de Bord Production - Équipe Backend
     **Dernière mise à jour:** Automatique
     **Objectif Sprint:** Réduire les bugs critiques à 0
     ```

3. **Configurez le rafraîchissement**
   - Cliquez sur les paramètres du dashboard
   - Activez le rafraîchissement automatique (5-15 minutes)

4. **Définissez les permissions**
   - Paramètres > Security
   - Définissez qui peut voir/modifier le dashboard

---

## **Exercice 2 : Mise en place d'un processus de gestion des incidents**

### **Étape 1 : Définition des rôles et responsabilités (30 min)**

1. **Identifiez les rôles clés**
   
   Créez un document avec cette structure :

   **Incident Manager**
   - Coordonne la réponse à l'incident
   - Prend les décisions d'escalade
   - Communique avec les parties prenantes
   - Anime la rétrospective

   **Technical Lead**
   - Dirige l'investigation technique
   - Coordonne les développeurs
   - Valide les solutions proposées

   **Communication Lead**
   - Rédige les communications internes/externes
   - Met à jour le status page
   - Gère les notifications clients

   **Developer on Call**
   - Effectue le diagnostic technique
   - Implémente les corrections
   - Documente les actions prises

2. **Définissez les niveaux de gravité**

   | Niveau | Critères | Temps de réponse | Exemple |
   |--------|----------|------------------|---------|
   | **P0 - Critical** | Service complètement indisponible | 15 min | Site web down |
   | **P1 - High** | Fonctionnalité majeure impactée | 1 heure | Paiements en échec |
   | **P2 - Medium** | Fonctionnalité mineure impactée | 4 heures | Export CSV lent |
   | **P3 - Low** | Impact cosmétique ou mineur | 24 heures | Faute d'orthographe |

### **Étape 2 : Création des étapes de diagnostic (45 min)**

1. **Phase de détection et déclaration (5 premières minutes)**

   Créez un guide avec ces étapes :

   ```
   ✅ DÉTECTION
   1. L'incident est détecté via :
      - Alerte monitoring automatique
      - Signalement client
      - Signalement interne
   
   2. Création du ticket incident
      - Utilisez le template Azure DevOps "Incident"
      - Titre : [P0/P1/P2/P3] Description courte
      - Renseignez : heure détection, système impacté, impact utilisateur
   
   3. Notification immédiate
      - Alertez le canal Slack/Teams #incidents
      - Mentionnez l'Incident Manager de garde
      - Pour P0/P1 : appelez directement par téléphone
   ```

2. **Phase d'évaluation initiale (5-15 minutes)**

   ```
   ✅ ÉVALUATION INITIALE
   1. L'Incident Manager évalue :
      - Nombre d'utilisateurs impactés
      - Fonctionnalités touchées
      - Impact business
   
   2. Confirmation du niveau de gravité
      - Si P0 ou P1 : activation de la war room
      - Si P2 ou P3 : suivi standard
   
   3. Constitution de l'équipe d'intervention
      - Incident Manager : [Nom]
      - Technical Lead : [Nom]
      - Développeurs nécessaires : [Liste]
      - Communication Lead (si P0/P1) : [Nom]
   ```

3. **Phase de diagnostic technique (temps variable)**

   ```
   ✅ DIAGNOSTIC TECHNIQUE
   1. Collecte d'informations
      - Consultez les logs (Splunk, ELK, CloudWatch)
      - Vérifiez les métriques (CPU, RAM, requêtes/sec)
      - Analysez les traces distribuées
      - Consultez les alertes de monitoring
   
   2. Identification de la cause racine
      - Hypothèse 1 : [à tester]
      - Hypothèse 2 : [à tester]
      - Tests à effectuer : [liste]
   
   3. Documentation en temps réel
      - Actualisez le ticket Azure DevOps toutes les 15 min
      - Notez chaque action entreprise
      - Documentez ce qui ne fonctionne PAS (pour éviter de retester)
   ```

4. **Phase de résolution (temps variable)**

   ```
   ✅ RÉSOLUTION
   1. Choix de la stratégie
      - Fix rapide (hotfix)
      - Rollback vers version stable
      - Désactivation de fonctionnalité
      - Scaling/redémarrage de ressources
   
   2. Validation de la solution
      - Tests en pré-production
      - Validation par le Technical Lead
      - Approbation du changement (pour prod)
   
   3. Déploiement
      - Déploiement de la correction
      - Surveillance accrue pendant 1h
      - Confirmation de la résolution
   ```

5. **Phase de clôture (30 minutes)**

   ```
   ✅ CLÔTURE
   1. Vérification complète
      - Tous les systèmes sont opérationnels
      - Métriques revenues à la normale
      - Aucune nouvelle alerte
   
   2. Communication de résolution
      - Notification aux utilisateurs impactés
      - Mise à jour du status page
      - Communication interne
   
   3. Planification post-incident
      - Programmer la rétrospective (dans 24-48h)
      - Créer les tickets de suivi
      - Archiver les logs et informations
   ```

### **Étape 3 : Définition des procédures d'escalade (20 min)**

Créez un flowchart d'escalade :

```
📞 MATRICE D'ESCALADE

Niveau 1 : Developer on Call
└─ Si non résolu en 30 min → Niveau 2

Niveau 2 : Technical Lead + Incident Manager
└─ Si non résolu en 1h → Niveau 3

Niveau 3 : Engineering Manager + CTO
└─ Si impact business critique → Niveau 4

Niveau 4 : Direction (CEO, COO)
```

**Critères d'escalade automatique :**
- Incident P0 non résolu après 30 minutes
- Incident P1 non résolu après 2 heures
- Impact business > 100K€
- Perte de données client
- Faille de sécurité détectée
- Couverture médiatique négative

**Contacts d'escalade :**
| Rôle | Nom | Téléphone | Email | Disponibilité |
|------|-----|-----------|-------|---------------|
| Technical Lead | [Nom] | [Tel] | [Email] | 24/7 |
| Incident Manager | [Nom] | [Tel] | [Email] | 24/7 |
| Engineering Manager | [Nom] | [Tel] | [Email] | 8h-22h |
| CTO | [Nom] | [Tel] | [Email] | Sur demande |

### **Étape 4 : Création du template de rétrospective (30 min)**

Créez un document Azure DevOps Wiki ou Word avec ce template :

```markdown
# 🔍 Rétrospective d'Incident - [ID Incident]

## Informations générales
- **Date de l'incident :** JJ/MM/AAAA HH:MM
- **Durée totale :** XX heures XX minutes
- **Gravité :** P0 / P1 / P2 / P3
- **Systèmes impactés :** [Liste]
- **Utilisateurs impactés :** [Nombre ou pourcentage]
- **Impact business estimé :** [Montant ou description]

## Participants à la rétrospective
- Incident Manager : [Nom]
- Technical Lead : [Nom]
- Développeurs : [Liste]
- Product Owner : [Nom]
- Autres : [Liste]

---

## 📋 Chronologie détaillée

| Heure | Événement | Action prise | Responsable |
|-------|-----------|--------------|-------------|
| HH:MM | Détection initiale | [Description] | [Nom] |
| HH:MM | Déclaration incident | Création ticket #XXXX | [Nom] |
| HH:MM | [Événement] | [Action] | [Nom] |
| HH:MM | Résolution | [Description solution] | [Nom] |

---

## 🎯 Cause racine (Root Cause Analysis)

### Qu'est-ce qui s'est passé ?
[Description détaillée du problème technique]

### Pourquoi cela s'est-il produit ?
Utilisez la méthode des "5 Pourquoi" :
1. **Pourquoi 1 :** [Réponse]
2. **Pourquoi 2 :** [Réponse]
3. **Pourquoi 3 :** [Réponse]
4. **Pourquoi 4 :** [Réponse]
5. **Pourquoi 5 (cause racine) :** [Réponse]

### Facteurs contributifs
- Facteur 1 : [Description]
- Facteur 2 : [Description]
- Facteur 3 : [Description]

---

## ✅ Ce qui a bien fonctionné

- ✅ [Point positif 1]
- ✅ [Point positif 2]
- ✅ [Point positif 3]

*Exemples : Détection rapide, bonne coordination, communication efficace*

---

## ❌ Ce qui doit être amélioré

- ❌ [Point d'amélioration 1]
- ❌ [Point d'amélioration 2]
- ❌ [Point d'amélioration 3]

*Exemples : Alerting insuffisant, documentation manquante, rollback compliqué*

---

## 🚀 Plan d'action (Action Items)

| # | Action | Responsable | Date limite | Priorité | Statut |
|---|--------|-------------|-------------|----------|--------|
| 1 | [Action corrective] | [Nom] | JJ/MM/AAAA | Haute | 🔴 À faire |
| 2 | [Amélioration monitoring] | [Nom] | JJ/MM/AAAA | Haute | 🔴 À faire |
| 3 | [Documentation] | [Nom] | JJ/MM/AAAA | Moyenne | 🟡 À faire |
| 4 | [Formation équipe] | [Nom] | JJ/MM/AAAA | Basse | 🟢 À faire |

**Règle importante :** Chaque action doit avoir un responsable et une deadline !

---

## 📊 Métriques de l'incident

- **Time to Detect (TTD) :** [Temps entre apparition et détection]
- **Time to Acknowledge (TTA) :** [Temps entre détection et prise en charge]
- **Time to Resolve (TTR) :** [Temps entre prise en charge et résolution]
- **Mean Time to Recovery (MTTR) :** [Temps total de détection à résolution]

**Objectifs vs Réalisé :**
| Métrique | Objectif | Réalisé | Écart |
|----------|----------|---------|-------|
| TTD | < 5 min | XX min | ✅/❌ |
| TTA | < 15 min | XX min | ✅/❌ |
| TTR | < 2h | XX h | ✅/❌ |

---

## 💰 Impact business

### Impact direct
- Perte de revenus estimée : [Montant]
- Transactions échouées : [Nombre]
- Clients contactés : [Nombre]

### Impact réputation
- Mentions sur réseaux sociaux : [Nombre]
- Tickets support générés : [Nombre]
- Taux de satisfaction client : [Impact]

---

## 📝 Communication

### Communication externe
- Status page mis à jour : ✅ Oui / ❌ Non
- Email aux clients envoyé : ✅ Oui / ❌ Non
- Réseaux sociaux : ✅ Oui / ❌ Non

### Communication interne
- Équipes notifiées : [Liste]
- Direction informée : ✅ Oui / ❌ Non
- Post-mortem partagé : ✅ Oui / ❌ Non

---

## 🎓 Leçons apprises

1. **Leçon 1 :** [Description et comment l'appliquer à l'avenir]
2. **Leçon 2 :** [Description et comment l'appliquer à l'avenir]
3. **Leçon 3 :** [Description et comment l'appliquer à l'avenir]

---

## 📎 Annexes

- Lien vers le ticket incident : [URL]
- Logs pertinents : [Liens]
- Captures d'écran : [Liens]
- Graphiques monitoring : [Liens]
- Enregistrement de la war room : [Lien si applicable]

---

## Signatures

- **Rédigé par :** [Nom] - [Date]
- **Validé par :** [Nom Engineering Manager] - [Date]
- **Approuvé par :** [Nom CTO] - [Date]
```

### **Étape 5 : Implémentation dans Azure DevOps (20 min)**

1. **Créez un Work Item Type "Incident"**
   - Allez dans Project Settings > Process
   - Ajoutez les champs personnalisés : Gravité, Time to Detect, Time to Resolve
   - Ajoutez un workflow spécifique : New → Investigating → Resolving → Resolved → Closed

2. **Créez des templates**
   - Dans Azure DevOps Wiki, créez une page "Gestion des Incidents"
   - Ajoutez tous vos documents (rôles, procédures, template rétrospective)
   - Créez des templates de Work Items pour faciliter la déclaration

3. **Configurez les notifications**
   - Project Settings > Notifications
   - Créez des règles pour notifier l'équipe lors de la création d'incidents P0/P1
   - Configurez l'intégration avec Slack/Teams

### **Étape 6 : Formation et drill (optionnel mais recommandé)**

1. **Organisez une session de formation** (2h)
   - Présentez le processus complet
   - Faites des exercices de rôle

2. **Planifiez des simulations d'incidents** (Game Days)
   - Une fois par trimestre
   - Simulez un incident P1
   - Testez le processus et identifiez les améliorations

---

## 📌 Points clés de succès

Pour les **deux exercices**, assurez-vous de :

1. **Impliquer les équipes** dans la conception
2. **Itérer** : commencez simple et améliorez progressivement
3. **Mesurer** : suivez les métriques pour améliorer
4. **Former** : tous doivent connaître les processus
5. **Tester** : validez avec des simulations

**Durée totale estimée :**
- Exercice 1 : 2-3 heures
- Exercice 2 : 3-4 heures

Besoin de précisions sur une étape en particulier ?

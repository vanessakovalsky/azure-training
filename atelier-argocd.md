# Atelier pas à pas — Déployer sur AKS avec Argo CD depuis Azure DevOps


**Pré-requis** :

* Argo CD est déjà installé sur le cluster AKS.
* Un projet Azure DevOps existe et les stagiaires ont accès au projet (repo code + permissions pour créer Service Connections).
* Les stagiaires ont accès à un terminal avec `az`, `kubectl`, `helm`, `git`, `yq` et `docker` ou utilisent les agents Microsoft hébergés dans les pipelines.

---

## Objectifs pédagogiques

À la fin de l'atelier, les stagiaires seront capables de :

1. Construire et pousser une image Docker vers ACR depuis Azure DevOps.
2. Scanner l'image avec Trivy dans la pipeline et échouer si vulnérabilités critiques existent.
3. Valider les manifests Helm localement avec Conftest (policies Rego).
4. Mettre à jour un repo GitOps (Helm Chart / values.yaml) depuis le pipeline.
5. Observer Argo CD déployer automatiquement la nouvelle version sur AKS.
6. Comprendre la complémentarité CI (Conftest/Trivy) et enforcement runtime (Gatekeeper).

---

## Plan de l'atelier

1. Préparations & prérequis (15 min)
2. Structure du repo GitOps & Helm chart (30 min)
3. Pipeline Azure DevOps complet (YAML) (45 min)
4. Intégration Trivy + Conftest (30 min)
5. Gatekeeper : installation & contraintes (30 min)
6. Exercices pratiques & corrections (30–45 min)
7. Q&A, retours et bonnes pratiques (15 min)

Durée totale estimée : ~3h — adaptable.

---

# 1) Préparations & prérequis (exécuté par les stagiaires)

**Compte/permissions** :

* Accès au projet Azure DevOps (rights: create pipelines, créer Service Connections si possible).
* Accès à un repo Git (GitHub, Azure Repos) pour le `gitops-infra` (privé ou public).
* ACR existant (`monacr`), ou instructions pour en créer.
* AKS opérationnel avec ArgoCD installé.

**Vérifications rapides (commands)** :

```bash
# vérifier kubernetes access
kubectl get pods -n argocd
# vérifier login az
az account show
# vérifier helm
helm version
```

Si `kubectl get pods -n argocd` retourne les pods ArgoCD en `Running`, on est prêt.

---

# 2) GitOps repo — structure et fichiers (atelier guidé)

Créez un repo nommé `gitops-infra` avec cette structure :

```
gitops-infra/
├─ charts/
│  └─ mon-app/
│     ├ Chart.yaml
│     ├ values.yaml
│     └ templates/
│         └ deployment.yaml
└─ apps/
   └─ argocd-application.yaml  # optional: Application CR to register app in ArgoCD

policies/
└─ k8s/
   ├ no-root.rego
   └ require-resources.rego
```

### Exemple minimal `Chart.yaml`

```yaml
apiVersion: v2
name: mon-app
version: 0.1.0
description: Chart demo pour atelier
```

### Exemple minimal `values.yaml`

```yaml
image:
  repository: monacr.azurecr.io/mon-app
  tag: "latest"
replicaCount: 2
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### Exemple `templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mon-app.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "mon-app.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "mon-app.name" . }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

> **Exercice** : initialiser le repo, commit et push. Vérifier que ArgoCD peut lire ce repo (si privé, configurer la clé SSH dans ArgoCD: `Settings -> Repositories`).

---

# 3) Pipeline Azure DevOps (YAML) — *Hands-on*

Nous fournissons un pipeline prêt à l'emploi. Les stagiaires le collent dans le repo applicatif (ou dans un repo pipeline) sous `azure-pipelines.yml`.

> **But** : Builder l'image, la scanner (Trivy), renderer le chart, valider policies, mettre à jour `values.yaml` dans `gitops-infra`.

### `azure-pipelines.yml` (version complète pour l'atelier)

```yaml
trigger:
  - main

variables:
  imageName: "mon-app"
  containerRegistry: "monacr.azurecr.io"
  gitopsRepo: "git@github.com:mon-org/gitops-infra.git"
  gitopsBranch: "main"
  helmChartPath: "charts/mon-app"
  valuesFile: "charts/mon-app/values.yaml"
  aksNamespace: "production"
  tag: "$(Build.BuildId)"
  trivyFailSeverity: "CRITICAL,HIGH"

stages:
  - stage: Build_and_Scan
    displayName: "Build image & Security Scans"
    jobs:
      - job: Build
        pool:
          vmImage: ubuntu-latest
        steps:
          - checkout: self
            persistCredentials: true

          - task: Docker@2
            displayName: "Build and push image to ACR"
            inputs:
              containerRegistry: "ACR-Service-Connection"
              repository: "$(imageName)"
              command: buildAndPush
              Dockerfile: Dockerfile
```

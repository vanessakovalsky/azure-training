# Atelier GitOps complet : AKS + ArgoCD + Azure DevOps

## 🎯 Objectif de l’atelier
Cet atelier a pour but d’initier les stagiaires à :
- L’approche **GitOps** avec Argo CD.
- L’intégration d’ArgoCD dans une chaîne CI/CD Azure DevOps.
- Le déploiement d’applications sur **AKS** via un repo GitOps.
- L’utilisation d’un chart **Helm**.
- L’ajout de contrôles **DevSecOps** (Trivy, Conftest, Gatekeeper).

L’atelier part du principe que :
- Le **cluster AKS existe déjà**.
- **ArgoCD est déjà installé sur AKS**.
- Le **projet Azure DevOps existe déjà**.

---

# 🧩 Partie 1 — Préparation du GitOps

## 📁 1. Structure du repo GitOps
Créer un repo nommé `gitops-infra` avec la structure suivante :

```
.gitignore
apps/
  myapp/
    values.yaml
    Chart.yaml
    templates/
      deployment.yaml
      service.yaml
```

## 📄 2. Chart Helm minimal
### Chart.yaml
```yaml
apiVersion: v2
name: myapp
version: 0.1.0
appVersion: "1.0"
```

### values.yaml
```yaml
image:
  repository: monacr.azurecr.io/myapp
  tag: "latest"

replicaCount: 2
```

### templates/deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
```

### templates/service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

---

# 🧩 Partie 2 — Configuration ArgoCD

## 1. Déclarer l'application dans ArgoCD
Créer le fichier `myapp-argocd.yaml` :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:mon-org/gitops-infra.git
    targetRevision: main
    path: apps/myapp
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Appliquer :
```bash
kubectl apply -f myapp-argocd.yaml
```

---

# 🧩 Partie 3 — Pipeline Azure DevOps (CI + GitOps)

## azure-pipelines.yml (avec Helm, Trivy, Conftest)
```yaml
trigger:
  - main

variables:
  imageName: "myapp"
  containerRegistry: "monacr.azurecr.io"
  gitopsRepo: "git@github.com:mon-org/gitops-infra.git"
  gitopsBranch: "main"
  valuesPath: "apps/myapp/values.yaml"

stages:
  - stage: Build
    displayName: "Build + Scan + GitOps Update"
    jobs:
      - job: Build
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: Docker@2
            displayName: "Build and push Docker image"
            inputs:
              containerRegistry: "ACR-Service-Connection"
              repository: $(imageName)
              command: buildAndPush
              Dockerfile: Dockerfile
              tags: |
                $(Build.BuildId)

          - script: |
              curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -
              ./bin/trivy image --exit-code 1 $(containerRegistry)/$(imageName):$(Build.BuildId)
            displayName: "Scan image with Trivy"

          - script: |
              curl -L -o conftest.tar.gz https://github.com/open-policy-agent/conftest/releases/latest/download/conftest_Linux_x86_64.tar.gz
              tar -xf conftest.tar.gz
              ./conftest test k8s/
            displayName: "Run Conftest policies"

          - checkout: gitops
            repository: gitopsRepo
            persistCredentials: true

          - script: |
              sed -i "s/tag:.*/tag: \"$(Build.BuildId)\"/" $(valuesPath)
              git config user.name "azure-pipelines"
              git config user.email "azure@pipelines.com"
              git add $(valuesPath)
              git commit -m "chore: update image to $(Build.BuildId)"
              git push origin $(gitopsBranch)
            displayName: "Update GitOps repo"
```

---

# 🧩 Partie 4 — Policies de Sécurité

## 1. Conftest (OPA) – Exemple policy
Créer `policy/no_latest.rego` :
```rego
package main

 deny[msg] {
   input.kind == "Deployment"
   image := input.spec.template.spec.containers[_].image
   endswith(image, ":latest")
   msg = "L'image ne doit pas utiliser le tag 'latest'"
 }
```

## 2. Gatekeeper – Policy (Optional)
ConstraintTemplate :
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8sdenyprivileged
spec:
  crd:
    spec:
      names:
        kind: K8sDenyPrivileged
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdenyprivileged
        deny[msg] {
          input.review.kind.kind == "Pod"
          c := input.review.object.spec.containers[_]
          c.securityContext.privileged == true
          msg := "No privileged containers allowed"
        }
```

Constraint :
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDenyPrivileged
metadata:
  name: no-privileged
```

---

# 🧪 Partie 5 — Exercices pratiques

## Exercice 1 — Premier déploiement avec ArgoCD
1. Modifier le `values.yaml` (ex : `replicaCount = 3`).
2. Commit/push.
3. Observer la synchronisation automatique.

## Exercice 2 — Ajouter une nouvelle route /health dans l'app
1. Modifier le code.
2. Push → pipeline → GitOps → ArgoCD.

## Exercice 3 — Forcer une violation de policy
1. Mettre `image.tag: latest`.
2. Exécuter le pipeline.
3. Comprendre la violation Conftest.

## Exercice 4 — Gatekeeper
1. Déployer un Pod privileged.
2. Observer le refus.

---

# 🧯 Troubleshooting
- **ArgoCD ne déploie pas** : vérifier la clé SSH du repo GitOps.
- **Le pipeline échoue sur Trivy** : gérer les CVE via `–ignore-unfixed`.
- **Conftest fail** : exécuter `conftest test apps/myapp` localement.
- **Le cluster refuse les Pods** : vérifier les constraints Gatekeeper.

---

# 🎉 Fin de l’atelier
Cet atelier fournit une vision complète de GitOps, du build jusqu’au déploiement sécurisé sur AKS via ArgoCD et Azure DevOps.


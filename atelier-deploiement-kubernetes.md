# Atelier : Déploiement de base sur kubernetes

## Objectif
Déployer une application web complète avec base de données sur AKS

## Etape 0 : pré-requis

* Installer Azure cli : https://learn.microsoft.com/fr-fr/cli/azure/install-azure-cli?view=azure-cli-latest
* Se connecter `az login`
* Installer Kubectl : https://kubernetes.io/fr/docs/tasks/tools/install-kubectl/ 

## Étape 1 : Configurer la connexion à AKS

### Définir les variables
```bash
# Définir les variables
RESOURCE_GROUP="FormationOrsysMalakoff"
LOCATION="France Central"
AKS_CLUSTER="demokubernetes"
```

### Récupérer les credentials
```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --overwrite-existing

# Vérifier la connexion
kubectl get nodes
```

## Étape 2 : Créer le namespace (2 min)

* /!\ : ajouter votre prenom au namespace pour le retrouver
```bash
# Créer le namespace
kubectl create namespace webapp

# Définir comme namespace par défaut
kubectl config set-context --current --namespace=webapp
```

---

## Étape 3 : Déployer PostgreSQL (10 min)

### 3.1 Créer le StorageClass (si nécessaire)
```bash
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-premium
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
```

### 3.2 Créer le Secret pour PostgreSQL
```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username=postgres \
  --from-literal=password=SuperSecurePassword123! \
  --namespace=webapp
```

### 3.3 Créer le fichier postgres-statefulset.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: webapp
spec:
  ports:
  - port: 5432
    targetPort: 5432
  clusterIP: None
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: webapp
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:14
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: POSTGRES_DB
          value: webapp_db
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: managed-premium
      resources:
        requests:
          storage: 10Gi
```

### 3.4 Déployer PostgreSQL
```bash
kubectl apply -f postgres-statefulset.yaml

# Vérifier le déploiement
kubectl get statefulset postgres -n webapp
kubectl get pvc -n webapp
kubectl get pods -l app=postgres -n webapp
```

### 3.5 Tester la connexion PostgreSQL
```bash
# Se connecter au pod
kubectl exec -it postgres-0 -n webapp -- psql -U postgres -d webapp_db

# Dans psql, créer une table de test
CREATE TABLE test (id SERIAL PRIMARY KEY, name VARCHAR(100));
INSERT INTO test (name) VALUES ('Hello from AKS');
SELECT * FROM test;
\q
```

---

## Étape 4 : Déployer l'API Backend (10 min)

### 4.1 Créer le ConfigMap pour l'API
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: webapp
data:
  LOG_LEVEL: "info"
  PORT: "8080"
  DB_HOST: "postgres.webapp.svc.cluster.local"
  DB_PORT: "5432"
  DB_NAME: "webapp_db"
EOF
```

### 4.2 Créer le fichier api-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: webapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: mendhak/http-https-echo:26  # Image de test
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: HTTP_PORT
          valueFrom:
            configMapKeyRef:
              name: api-config
              key: PORT
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: api-config
              key: LOG_LEVEL
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: api-config
              key: DB_HOST
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: webapp
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
```

### 4.3 Déployer l'API
```bash
kubectl apply -f api-deployment.yaml

# Vérifier le déploiement
kubectl get deployment api -n webapp
kubectl get pods -l app=api -n webapp
kubectl get svc api -n webapp
```

### 4.4 Tester l'API en interne
```bash
# Port forward pour tester
kubectl port-forward svc/api 8080:80 -n webapp

# Dans un autre terminal
curl http://localhost:8080
```

---

## Étape 5 : Déployer le Frontend (8 min)

### 5.1 Créer le fichier frontend-deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: webapp
data:
  default.conf: |
    server {
        listen 80;
        server_name _;
        
        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
        
        location /api/ {
            proxy_pass http://api.webapp.svc.cluster.local/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: webapp
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
```

### 5.2 Déployer le Frontend
```bash
kubectl apply -f frontend-deployment.yaml

# Vérifier le déploiement
kubectl get deployment frontend -n webapp
kubectl get svc frontend -n webapp -w
```

---

## Étape 6 : Configurer l'Ingress (5 min)

### 6.1 Installer NGINX Ingress Controller
```bash
# Ajouter le repo Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Installer l'ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

### 6.2 Créer le fichier ingress.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: webapp
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 80
```

### 6.3 Déployer l'Ingress
```bash
kubectl apply -f ingress.yaml

# Récupérer l'IP publique
kubectl get ingress webapp-ingress -n webapp

# Attendre que l'adresse IP soit assignée
kubectl get ingress webapp-ingress -n webapp -w
```

---

## Étape 7 : Tester l'application complète

### 7.1 Récupérer l'IP de l'Ingress
```bash
INGRESS_IP=$(kubectl get ingress webapp-ingress -n webapp -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application accessible à : http://$INGRESS_IP"
```

### 7.2 Tester les endpoints
```bash
# Tester le frontend
curl http://$INGRESS_IP/

# Tester l'API
curl http://$INGRESS_IP/api/

# Tester depuis un navigateur
echo "Ouvrez votre navigateur à : http://$INGRESS_IP"
```

### 7.3 Vérifier les logs
```bash
# Logs du frontend
kubectl logs -l app=frontend -n webapp --tail=50

# Logs de l'API
kubectl logs -l app=api -n webapp --tail=50

# Logs de PostgreSQL
kubectl logs postgres-0 -n webapp --tail=50
```

---

## Points de vérification

✅ Le cluster AKS est créé et accessible
✅ PostgreSQL est déployé avec un StatefulSet et PVC
✅ L'API backend est déployée avec 3 replicas
✅ Le frontend est déployé avec 2 replicas
✅ Les Services sont créés et fonctionnels
✅ L'Ingress est configuré et accessible
✅ L'application complète est accessible via HTTP

---

## Nettoyage (optionnel)

```bash
# Supprimer le namespace (supprime toutes les ressources)
kubectl delete namespace webapp

# Supprimer l'ingress controller
helm uninstall nginx-ingress -n ingress-nginx
kubectl delete namespace ingress-nginx

# Supprimer le cluster (si nécessaire)
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --yes --no-wait

# Supprimer le resource group
az group delete \
  --name $RESOURCE_GROUP \
  --yes --no-wait
```

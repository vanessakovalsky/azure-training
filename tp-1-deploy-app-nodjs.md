# TP 1 - Automatiser le déploiement d'une application Node JS

L'objectif de ce TP est d'automatiser le déploiement d'une application Web écrite en Node JS sur Azure à l'aide d'Azure CLI

L'application se trouve ici :   https://github.com/Azure-Samples/nodejs-docs-hello-world.git

Les ressources à crée sont les suivantes :
* Groupe de ressource az cli, nommé tp1-$myname (en remplaçant $myname par votre nom)
* Une VM Linux avec Nginx et NodeJs installé et le port 80 ouvert sur cette VM

Une fois la VM créé il faudra déployer le code depuis le dépôt Github et lancer les commandes suivantes pour que l'application soit utilisable
```bash
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2
sudo apt-get install -y nginx
```

* Puis il faudra remplacer le contenu du fichier /etc/nginx/sites-available/default par le contenu suivant 
```
server {
        listen 80;
        location / {
          proxy_pass http://localhost:1337;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection keep-alive;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Host $host;
          proxy_cache_bypass $http_upgrade;
        }
      }
```
* Une fois le contenu remplacer la commande : sudo nginx service restart

Votre application devrait alors afficher "Hello World" à l'adresse IP de votre VM


## Rendu

Vous devez produire un script qui effectue les différentes actions nécessaires pour arriver au résultat attendue 
Le script est à rendre sur Teams (soit directement dans les fichiers soit sous forme d'un lien vers un dépôt git public)

## Pour aller plus loin 

* Ajouter un pipeline Azure qui va builder l'application (faire les actions du script deployapp.sh) et déployer le site à chaque push sur le depôt git.
* Ajouter la mise à l'échelle automatique sur la machine virtuelle depuis Azure Cli

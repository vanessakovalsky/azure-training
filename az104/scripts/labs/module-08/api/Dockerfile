# Dockerfile — API de suivi des colis Arvéo, version conteneur (lab 08.4)
# Construite dans Azure par ACR Tasks : az acr build -r <REGISTRE> -t arveo/api-suivi-colis:2.0 .
# Image de base Microsoft (MCR) : évite les limites de téléchargement anonyme de Docker Hub.
# Image de base [À VÉRIFIER] au J-1 ; repli : --build-arg IMAGE_BASE=nginx:1.27-alpine
ARG IMAGE_BASE=mcr.microsoft.com/azurelinux/base/nginx:1.25
FROM ${IMAGE_BASE}

LABEL org.opencontainers.image.title="arveo-api-suivi-colis" \
      org.opencontainers.image.version="2.0"

# Configuration complète : remplace celle de l'image (indépendante de la distribution)
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]

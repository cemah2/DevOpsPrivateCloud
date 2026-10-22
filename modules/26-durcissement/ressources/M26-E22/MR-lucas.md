# MR !3 — plateforme/inventaire-images : « Premier déploiement de MédiInventaire »

**Auteur** : Lucas Martin · **Branche** : `lucas/premier-deploiement` · **Cible** : `main`

Salut,

Voilà MédiInventaire, le petit outil que Sophie m'a demandé : il liste toutes les images qui
tournent dans `k8s-par1`, demande à Harbor leurs vulnérabilités (API `/api/v2.0/…/additions/vulnerabilities`)
et affiche un tableau HTML sur le port 8080, rafraîchi toutes les 10 minutes. Le code Python est
dans `app/` (pas dans cette MR, il ne change pas).

Ce que j'ai fait pour que ça marche du premier coup :

- l'image part de `python:latest`, comme ça on a toujours la dernière version de Python ;
- j'ai mis `curl`, `vim`, `netcat` et `tcpdump` dans l'image pour pouvoir déboguer dans le pod ;
- le jeton du robot Harbor est passé au build (`--build-arg HARBOR_TOKEN=…`) et aussi dans
  `values.yaml`, au cas où ;
- pour lister les images plus vite, je lis directement le socket de containerd des nœuds ; il faut
  `privileged` et `hostNetwork` sinon ça ne marche pas (j'ai essayé sans) ;
- j'ai donné `*` au rôle parce qu'avec seulement `pods` j'avais des `Forbidden` sur d'autres choses ;
- la NetworkPolicy autorise tout pour ne pas avoir de problème avec Harbor ;
- le Service est en `LoadBalancer` pour que Sophie puisse ouvrir la page depuis son poste.

J'ai testé dans `default` sur le cluster, ça marche. Fichiers : `Dockerfile`, `values.yaml`,
`manifestes/` (rendu du chart : `deployment.yaml`, `service.yaml`, `rbac.yaml`, `networkpolicy.yaml`).
Je peux fusionner ?

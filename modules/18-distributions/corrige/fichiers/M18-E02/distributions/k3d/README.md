# k3d — clusters de développement (M18-E02)

Fichier : `dev.yaml` (1 serveur + 2 agents k3s v1.36.5+k3s1, Traefik désactivé, miroirs Harbor).

    k3d cluster create --config ~/src/distributions/k3d/dev.yaml     # ≈ 30 s à 1 min
    kubectl --context k3d-dev get nodes
    k3d image import medisphere/essai:local --cluster dev
    k3d cluster delete dev

## Différences avec kind

- Les nœuds sont des conteneurs `rancher/k3s` : un binaire k3s, SQLite sur le serveur unique,
  flannel, CoreDNS, local-path, metrics-server, et **ServiceLB** (klipper-lb) : un Service
  `LoadBalancer` reçoit l'adresse des nœuds (conteneurs) ; k3d ajoute un conteneur `k3d-dev-serverlb`
  (nginx) devant l'API.
- `kubectl top nodes` fonctionne (metrics-server de k3s).
- Plus léger que kind (≈ deux fois moins de mémoire au repos sur `m18-dev01`, voir `mesures.md`),
  mais ce n'est pas kubeadm : ce qu'on y valide (fichiers de kubeadm, manifestes statiques) ne
  ressemble pas à `k8s-par1`.
- k3d 5.9.0 démarre un k3s **1.35** si on ne fixe pas l'image : toujours `image:`.

## Limites

Mêmes que kind : un seul noyau, pas de vrai réseau ni de vrai stockage. Au redémarrage de l'hôte,
`k3d cluster start dev` relance les conteneurs.

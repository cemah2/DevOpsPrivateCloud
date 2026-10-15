# k3s — fiche de l'essai `k3s01` (agence LYO1 simulée)

> M18-E03 (PLAT-1903). Code : rôle `k3s` (`plateforme/ansible`), `k3s/` (`plateforme/distributions`).

## Composants embarqués et choix

| Composant | Rôle | À l'agence |
|---|---|---|
| containerd, runc | runtime | gardé (embarqué, piloté par k3s) |
| flannel (VXLAN) | réseau des pods | gardé |
| CoreDNS | DNS du cluster | gardé |
| kine + SQLite | base de l'API (nœud unique) | gardé : un seul serveur, pas de quorum |
| local-path-provisioner | volumes sur le disque du nœud | gardé (services locaux sans stockage partagé) |
| metrics-server | `kubectl top` | gardé |
| Helm controller | objets `HelmChart` | gardé (installations par manifeste) |
| Traefik | Ingress | **désactivé** (`disable: [traefik]`) : pas d'Ingress à l'agence pour l'instant |
| ServiceLB (klipper-lb) | Services `LoadBalancer` sur les ports des nœuds | **désactivé** : rien à publier ; il ouvrirait des ports sur l'hôte sans que personne ne le voie |

Un composant désactivé par `--disable` est **désinstallé** s'il existait, et son manifeste retiré
de `/var/lib/rancher/k3s/server/manifests/`.

## Où sont les données

- base : `/var/lib/rancher/k3s/server/db/state.db` (SQLite, avec `-wal` et `-shm`) ;
- PKI et jeton : `/var/lib/rancher/k3s/server/tls/`, `/var/lib/rancher/k3s/server/token` ;
- images et conteneurs : `/var/lib/rancher/k3s/agent/containerd/` ;
- volumes local-path : `/var/lib/rancher/k3s/storage/` ;
- configuration : `/etc/rancher/k3s/` (`config.yaml`, `registries.yaml`, `jeton`, `k3s.yaml`).

Sauvegarder l'agence = sauvegarder `/var/lib/rancher/k3s/server/` (base **et** tls, à l'arrêt ou
par instantané cohérent ; palier 3) et `/etc/rancher/k3s/`.

## Accès

`~/.config/workbook/m18/k3s01.kubeconfig` sur `adm01` (600), contexte `k3s01`, serveur
`https://k3s01.par1.medisphere.internal:6443` (nom dans `tls-san`). Identité : administrateur du
cluster (le kubeconfig de k3s) : à remplacer par des identités nominatives avant toute production.

## Désinstaller

`/usr/local/bin/k3s-uninstall.sh` (efface binaire, services, données et règles réseau) ; dans
le module, on détruit plutôt la VM (`groupes` sans `k3s`).

# Mesures des essais de distributions (M18)

> Une section par essai, mêmes rubriques, mesurées de la même façon (introduction du module).
> Alimente le tableau comparatif et l'ADR-0180 (palier 3). Les valeurs ci-dessous sont des
> **exemples d'ordre de grandeur** : remplace-les par TES mesures.

| Rubrique | Méthode |
|---|---|
| Temps d'installation | de la commande de création (`tofu apply` ou `kind/k3d create`) à « tous les nœuds Ready » (`kubectl wait --for=condition=Ready nodes --all`) |
| Mémoire au repos | 10 min après l'installation, sans charge : `free -m` (colonne *used*) sur chaque nœud ; Talos : `talosctl memory` ; conteneurs : `docker stats --no-stream` |
| Fichiers et commandes | fichiers versionnés nécessaires, commandes manuelles restantes |
| Version obtenue | `kubectl version`, `kubectl get nodes -o wide` |

## k8s-par1 (référence, M14)

- État avant arrêt : `lab/bin/check 14 46` vert le <DATE>.

## kind (`dev`, 3 nœuds)

- Temps : ≈ 1 min 30 · mémoire : ≈ 1,5 Go pour les trois conteneurs · fichiers : 1 + 4 `hosts.toml` · version v1.36.4.

## k3d (`dev`, 1 + 2)

- Temps : ≈ 40 s · mémoire : ≈ 0,8 Go · fichiers : 1 · version v1.36.5+k3s1.

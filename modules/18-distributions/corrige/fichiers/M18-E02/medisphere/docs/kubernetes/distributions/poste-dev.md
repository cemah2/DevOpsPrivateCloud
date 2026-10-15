# Poste de développement Kubernetes (référence `m18-dev01`)

> Fiche M18-E02 (DEV-1902). Code : `plateforme/distributions` (`kind/`, `k3d/`), rôles Ansible
> `docker_engine`, `outils_k8s`, `outils_distributions`, playbook `m18.yml`.

## Ce qu'on installe

| Outil | Version | Source |
|---|---|---|
| Docker Engine | 29.8 | dépôt download.docker.com (rôle `docker_engine`) |
| kubectl, Helm | 1.36, 4.3 | pkgs.k8s.io, dépôt Helm (rôle `outils_k8s`) |
| kind | 0.33.0 | binaire amont, empreinte fixée |
| k3d | 5.9.0 | binaire amont, empreinte fixée |
| clusterctl, talosctl | 1.12.11, 1.14.2 | binaires amont, empreintes fixées |

## Créer et jeter un cluster

| | kind | k3d |
|---|---|---|
| Créer | `kind create cluster --config kind/dev.yaml` | `k3d cluster create --config k3d/dev.yaml` |
| Contexte | `kind-dev` | `k3d-dev` |
| Image locale | `kind load docker-image <img> --name dev` | `k3d image import <img> --cluster dev` |
| Jeter | `kind delete cluster --name dev` | `k3d cluster delete dev` |

Les nœuds tirent les images publiques par le cache Harbor (`registry.par1.medisphere.internal`),
et font confiance à la racine MédiSphère.

## Ce qu'on n'y teste pas

Réseau réel (BGP, MTU, politiques réseau entre nœuds réels), stockage (ceph-csi, Velero), perte de
nœud, montée de version du cluster, performances : tout cela se teste sur un cluster de VMs.
kind sert à tester ce qui ressemble à `k8s-par1` (kubeadm), k3d ce qui doit être rapide et léger.

## Règles

- Un cluster de poste est **jetable** : rien d'important n'y vit, aucune donnée réelle.
- Le compte `admin` est dans le groupe `docker` : c'est l'équivalent de root sur `m18-dev01`
  (M12-E26). Le poste n'a aucun secret de production.

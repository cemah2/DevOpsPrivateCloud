# RB-184 — Diagnostiquer un nœud Talos (sans SSH)

| | |
|---|---|
| Portée | Cluster `talos-essai` (et tout cluster Talos 1.14 de MédiSphère) |
| Outils | `talosctl` (contexte de `~/.config/workbook/m18/talosconfig`), console Proxmox, code `plateforme/distributions/talos/`, paquet de secrets (Vault `lab`) |
| Rédigé par | Équipe Plateforme — M18-E20 (INC-4520) |

## 1. Situer l'étage

```
talosctl config info                                     # contexte, points d'accès, rôles, fin de validité
for ip in 10.10.99.85 10.10.99.86 10.10.99.87; do talosctl -n $ip version --short || echo "$ip KO"; done
kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig get nodes -o wide
```

| Constat | Étage | Aller à |
|---|---|---|
| Tous les nœuds refusent (erreur TLS), Kubernetes sain | **client** | §2 |
| Un nœud refuse, il a quitté Kubernetes, il répond à `--insecure get disks` | **nœud** (maintenance) | §3 |
| Tout répond, l'application d'un correctif est refusée | **configuration** | §4 |
| Un nœud ne répond ni authentifié ni en `--insecure` | **réseau / VM** | console Proxmox, `qm config`, VNet, adresse |

## 2. Client

- Comparer la CA du contexte (`yq -r '.contexts[.context].ca' $TALOSCONFIG | base64 -d | openssl x509 -noout -fingerprint -sha256`) avec celle du paquet de secrets.
- Régénérer depuis le paquet : `talosctl gen config <cluster> <point d'accès> --with-secrets talos-secrets.yaml --output-types talosconfig`, `config endpoint`, installation en 600.
- Jamais `gen config` sans `--with-secrets` dans le dossier de travail.

## 3. Nœud en maintenance

1. Vérifier que l'adresse est bien la VM attendue (console Proxmox, MAC, VMID).
2. `talos/generer.sh` puis `talos/appliquer.sh <nœud> --maintenance`.
3. `talosctl -n <IP> health`, `kubectl get nodes`.
4. Chercher qui a réinitialisé le nœud (accès `os:admin`).

## 4. Configuration refusée

- `talos/appliquer.sh <nœud> --essai` et lire le refus : document, ligne, champ.
- En 1.14 : champs `v1alpha1` remplacés par des documents (`KubeNodeConfig.labels`, `KubeletConfig.extraArgs`, `HostnameConfig`…), et un champ `v1alpha1` exclut son document de remplacement.
- Corriger dans le dépôt, nouveau commit, `--essai` vide, puis application.

## 5. Ce qu'on ne fait jamais

- `--insecure` vers une adresse non vérifiée.
- `talosctl reset` du nœud de contrôle (c'est une restauration : RB-181).
- `talosctl edit mc` en dehors d'un essai (la configuration diverge du code).
- Donner `os:admin` à l'astreinte de premier niveau (`os:operator` suffit).

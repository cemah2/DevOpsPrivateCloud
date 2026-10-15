# Restaurations réelles par distribution (M18-E14)

> Compte rendu à remplir avec tes mesures. RTO : de la décision de restaurer au témoin relu. RPO : écart entre l'instantané et l'incident simulé (passage du témoin à `apres-instantane`).

| Distribution | Date | Instantané (nom, taille) | RPO | RTO | Étapes manuelles | Écarts avec la doc |
|---|---|---|---|---|---|---|
| k3s01 (SQLite, archive à froid) | | | | | | |
| k3s etcd (`k3s-ha01` + agent) | | | | | | |
| RKE2 (3 serveurs) | | | | | | |
| Talos (`talos-essai`) | | | | | | |
| *kubeadm (`k8s-par1`, M14-E24, pour mémoire)* | | | | | | |

## Interruption du cluster de gestion pendant la sauvegarde à froid

- Durée mesurée (arrêt → `readyz`) :
- Effet sur `capi-essai` : aucun sur les charges ; contrôleurs CAPI interrompus pendant la durée.

## Comparaison avec kubeadm (RB-141)

| | kubeadm | k3s | RKE2 | Talos |
|---|---|---|---|---|
| Commande de restauration | `etcdutl snapshot restore` sur chaque membre + manifeste etcd | `k3s server --cluster-reset --cluster-reset-restore-path` | `rke2 server --cluster-reset …` | `talosctl bootstrap --recover-from` |
| Nœuds touchés | les 3 nœuds de contrôle | 1 serveur réinitialisé, les autres vidés | idem | 1 nœud de contrôle |
| Révision etcd, identifiants de membres | à la main (`--bump-revision`, `--mark-compacted`) | gérés | gérés | gérés |
| Certificats et PKI | fichiers `/etc/kubernetes/pki` à sauvegarder à part | dans la base, chiffrés par le jeton | idem | dans la configuration des machines (`talos-secrets.yaml`) |
| À sauvegarder **en plus** de l'instantané | PKI, configuration kubeadm, clés de chiffrement des Secrets | jeton du serveur | jeton du serveur | secrets Talos, configurations des machines |
| Planification et envoi hors machine | minuterie maison (M14-E24) | intégrés | intégrés | à faire (script, CronJob) |

## Ce que j'en retiens pour l'ADR-0180

- 

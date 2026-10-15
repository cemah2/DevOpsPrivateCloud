# CHG-1608 — Remplacer kube-proxy par Cilium sur `k8s-par1`

| | |
|---|---|
| Demandeur | Karim Benali (PLAT-1608) |
| Exécutant | `<MOI>` |
| Relecteur de la MR | Karim Benali |
| Fenêtre | `<DATE>`, 30 min, hors démonstration de MédiAgenda (annoncée la veille à Julien Petit et Nadia Roussel) |
| Impact annoncé | coupure brève des connexions vers les Services (quelques secondes par nœud, connexions établies rompues), aucune perte de données |
| MR | `plateforme/k8s` !`<NUMÉRO>` : `composants/cilium/values.yaml` (`kubeProxyReplacement: true`, serveur de santé 10256), `cluster/kubeadm-config.yaml` (`proxy.disabled: true`, document `KubeProxyConfiguration` retiré), `outils/nettoyer-regles-kube-proxy.sh` |

## Pourquoi

Deux plans de données traduisaient les Services (règles iptables de kube-proxy, tables eBPF de Cilium pour les ClusterIP) ; un seul doit rester. Prérequis de la Gateway API de Cilium (M15-E07), du LB IPAM annoncé en BGP (M15-E10, E11) et de la lecture d'un seul jeu de tables en diagnostic.

## Avant

- [ ] Instantané etcd vérifié (`outils/etcd-instantane.sh`, M14-E24) ; sauvegarde PBS récente des nœuds.
- [ ] `cilium status --wait` : tout `OK` ; 6 nœuds `Ready` ; `kube-proxy` 6/6.
- [ ] Mesure témoin lancée depuis `adm01` (boucle `curl` sur le NodePort `echo-np`, et depuis `sonde-w01a` vers le Service `echo`).
- [ ] Ancien fichier de *values* conservé (`git show HEAD~1:composants/cilium/values.yaml > ~/m15/e08/values-avant.yaml`).

## Étapes

1. `cilium upgrade --version <VERSION-CILIUM> --reset-values --values composants/cilium/values.yaml`, puis redémarrage de l'opérateur et des agents, `cilium status --wait`, `cilium-dbg status` : `KubeProxyReplacement: True` sur les 6 agents.
2. `kubectl -n kube-system delete daemonset kube-proxy` puis `kubectl -n kube-system delete configmap kube-proxy`.
3. `outils/nettoyer-regles-kube-proxy.sh` (un nœud à la fois, vérifié).
4. ConfigMap `kubeadm-config` mise à jour (`proxy.disabled: true`) par `kubeadm init phase upload-config kubeadm` sur `k8s-cp01` ; contrôle par `kubeadm upgrade apply --dry-run`.

## Retour arrière

Avant l'étape 2 : `cilium upgrade` avec `values-avant.yaml` et redémarrage des agents (kube-proxy n'a jamais cessé de tourner). Après l'étape 2 : remettre `kubeadm-config` (`proxy.disabled: false`), recréer kube-proxy (`kubeadm init phase addon kube-proxy --config <FICHIER>` sur `k8s-cp01`, qui recrée la ConfigMap et le DaemonSet), attendre 6/6, puis revenir aux anciennes *values* de Cilium. Dans les deux cas, connexions établies rompues une seconde fois.

## Résultat

| Mesure | Valeur |
|---|---|
| Plus longue interruption vue par la boucle de `adm01` (NodePort) | `<SECONDES>` |
| Plus longue interruption vue depuis `sonde-w01a` (ClusterIP) | `<SECONDES>` |
| Règles `KUBE-*` restantes sur les nœuds | 0 |
| `kubeadm upgrade apply --dry-run` | « Skipping the addon/kube-proxy phase. The addon is disabled. » |

Écarts constatés : `<…>`. Clôture : `<DATE>`, `<MOI>`.

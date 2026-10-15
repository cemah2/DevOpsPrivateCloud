## Réseau du cluster `k8s-par1` (ms-verif-k8s-reseau)

La sonde tourne toutes les 5 minutes sur `adm01` ; une alerte `ms-alerte` donne la ligne `KO` en cause.

| Ligne KO | Gravité | Trois premières commandes | Réveiller ? |
|---|---|---|---|
| `api` | critique | `kubectl get --raw /readyz` ; `curl -k https://10.10.40.200:8443/readyz` ; RB-140/RB-141 (M14) | oui |
| `composant` cilium / cilium-envoy | haute | `kubectl -n kube-system get pod -o wide -l k8s-app=cilium` ; `kubectl -n kube-system logs <POD> --previous` ; `cilium status` | oui si plus d'un nœud |
| `composant` cert-manager / external-dns | basse | `kubectl -n cert-manager get pod` ; `kubectl -n external-dns logs deploy/external-dns` | non (les certificats durent 30 jours) |
| `bgp` (un nœud) | moyenne | `kubectl get ciliumbgpnodeconfigs` ; `cilium bgp peers` ; RB-152 | non : le multichemin sert |
| `bordure` (maître : aucune session, adresse absente) | critique | `ssh gw01 sudo vtysh -c 'show bgp summary'` ; `ip route get 10.10.41.10` ; RB-152 | **oui** |
| `wireguard` | moyenne | `kubectl get ciliumnodes -o yaml | grep wg-pub-key` ; `cilium-dbg status` dans l'agent | non |
| `certificat` (< 10 jours ou non prêt) | moyenne | `kubectl describe certificate -n <ESPACE> <NOM>` ; `cmctl status certificate …` ; RB-151 | non |
| `nom` | haute si l'application est en recette | `dig @10.10.20.10 <NOM>` ; `curl -v https://<NOM>/` ; RB-150 | selon l'application |
| `metriques` | moyenne | `curl -s http://<IP>:9962/metrics | head` ; `kubectl -n kube-system get pod -o wide` | non |

Règle : un `KO` qui revient à chaque passage depuis plus d'une heure et qui n'a pas de ticket est un incident.

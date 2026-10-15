# RB-149 — Le DNS du cluster

| | |
|---|---|
| Cluster | `k8s-par1`, CoreDNS 1.14 (installé par kubeadm), Service `kube-dns` 10.96.0.10, domaine `cluster.local` |
| Transfert | `forward . /etc/resolv.conf` (récurseurs `dns01`/`dns02`) ; explicite au module 15 |
| Rédigé | M14-E42 (INC-4142) |

## Chemin d'une requête

```
pod (/etc/resolv.conf écrit par le kubelet selon dnsPolicy)
  └─ nameserver 10.96.0.10 (Service kube-dns) ── kube-proxy (iptables) ──> pods coredns (×2)
        ├─ *.cluster.local   → greffon kubernetes (lit l'API)
        └─ le reste          → greffon forward → 10.10.20.10 / 10.10.20.16 (dns01, dns02)
```

`ndots:5` : un nom de moins de cinq points est d'abord essayé avec chaque domaine de recherche (`<espace>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`, `par1.medisphere.internal`), puis tel quel. Un nom terminé par un point (`registry.par1.medisphere.internal.`) part directement.

## Un test par maillon

```
admin@adm01:~$ kubectl -n wb-pannes exec deploy/sonde-dns -- cat /etc/resolv.conf
admin@adm01:~$ for n in postgres kubernetes.default.svc.cluster.local registry.par1.medisphere.internal; do
  kubectl -n wb-pannes exec deploy/sonde-dns -- nslookup $n >/dev/null 2>&1 && echo "ok $n" || echo "ÉCHEC $n"; done
admin@adm01:~$ kubectl -n kube-system get deploy,pods,endpointslices -l k8s-app=kube-dns -o wide
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
admin@adm01:~$ kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
admin@adm01:~$ kubectl -n wb-pannes exec deploy/sonde-dns -- nslookup registry.par1.medisphere.internal <IP-D-UN-POD-COREDNS>
admin@k8s-w01:~$ dig +short registry.par1.medisphere.internal @10.10.20.10
```

| Symptôme | Maillon |
|---|---|
| tout expire, aucun point d'accès derrière `kube-dns` | pods CoreDNS absents ou pas prêts |
| pods CoreDNS en `CrashLoopBackOff`, `Error during parsing` | Corefile invalide |
| interne ok, externe en `SERVFAIL` ou délai | greffon `forward` ou récurseurs |
| un seul pod n'y arrive pas | `dnsPolicy` / `dnsConfig` du pod |
| `loop` détecté, CoreDNS s'arrête | boucle de transfert (le résolveur du nœud renvoie vers CoreDNS) |

## Pièges

- `dnsPolicy: Default` = résolveur du **nœud**, pas « par défaut » (`ClusterFirst`).
- Le greffon `reload` garde l'ancienne configuration si la nouvelle est invalide : une erreur ne se révèle qu'au prochain redémarrage des pods. Toujours tester un Corefile modifié par un redémarrage contrôlé (`kubectl -n kube-system rollout restart deploy/coredns`) et regarder les journaux.
- Le cache (`cache 30`) prolonge une réponse fausse jusqu'à 30 s ; une réponse négative aussi.
- Ne jamais supprimer ni recréer le déploiement `coredns` : le corriger (`scale`, `patch`, `rollout restart`).

## Par le code

Le Corefile voulu (transfert vers `dns01`/`dns02` au module 15) vit dans `plateforme/k8s/composants/coredns/` et s'applique par `task appliquer` ; le nombre de réplicas (2 minimum) aussi. Vérifier après chaque `kubeadm upgrade` que la configuration et le nombre de réplicas sont toujours ceux du code (kubeadm gère ce module).

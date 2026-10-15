# Le DNS de `k8s-par1`

> Fiche de l'équipe Plateforme — PLAT-1604 (M15-E04). Source de la configuration : `plateforme/k8s`, `composants/coredns/configmap-coredns.yaml`.

## Qui répond à quoi

| Nom demandé par un pod | Qui répond | Comment |
|---|---|---|
| `<service>.<espace>.svc.cluster.local` | CoreDNS (greffon `kubernetes`) | adresse du Service (ClusterIP), ou des pods prêts pour un Service *headless* |
| `<pod>.<service>.<espace>.svc.cluster.local` | CoreDNS | pod d'un Service *headless* dont la spécification porte `hostname` et `subdomain` (StatefulSet) |
| `<a-b-c-d>.<espace>.pod.cluster.local` | CoreDNS (`pods insecure`) | l'adresse écrite dans le nom, sans vérifier qu'un pod la porte (compatibilité kube-dns) |
| `_<port>._<proto>.<service>.<espace>.svc.cluster.local` (SRV) | CoreDNS | port nommé du Service |
| `*.medisphere.internal` | CoreDNS → `dns01` (10.10.20.10), puis `dns02` (10.10.20.16) | bloc `medisphere.internal:53` ; DNSSEC validé par les récurseurs du socle |
| tout le reste (Internet) | CoreDNS → `dns01`, puis `dns02` | bloc `.:53`, `forward` |

Service du DNS du cluster : `kube-system/kube-dns`, 10.96.0.10 (UDP et TCP 53, métriques 9153). Deployment `coredns`, 2 réplicas (réécrit par kubeadm à chaque montée de version ; le Corefile modifié, lui, est conservé ou migré).

## Le `resolv.conf` d'un pod (`dnsPolicy: ClusterFirst`, le défaut)

```
search wb-essais.svc.cluster.local svc.cluster.local cluster.local par1.medisphere.internal
nameserver 10.96.0.10
options ndots:5
```

- Les trois premiers domaines de recherche viennent de Kubernetes ; le dernier est hérité du `resolv.conf` du nœud.
- `ndots:5` : un nom qui contient **moins de cinq points** est d'abord essayé avec **chaque** suffixe, puis tel quel. `ca01.par1.medisphere.internal` (trois points) coûte donc jusqu'à cinq questions (quatre suffixes puis le nom seul), chacune en A **et** en AAAA.
- Remèdes, du plus simple au plus fin : écrire les noms externes **complets avec un point final** (`ca01.par1.medisphere.internal.`) dans la configuration des applications ; baisser `ndots` par pod (`dnsConfig.options`) quand l'application appelle surtout des noms externes ; ne jamais changer le comportement de tout le cluster pour une application.

## `dnsPolicy`

| Valeur | Résolveur du pod | Usage |
|---|---|---|
| `ClusterFirst` (défaut) | CoreDNS | presque tout |
| `ClusterFirstWithHostNet` | CoreDNS, pour un pod en `hostNetwork` | agents réseau qui doivent quand même résoudre les Services |
| `Default` | le `resolv.conf` du nœud | pods qui ne doivent pas dépendre de CoreDNS (rare) |
| `None` | uniquement `dnsConfig` | cas particuliers, essais |

Un pod `hostNetwork` avec `ClusterFirst` se comporte comme `Default` : c'est le cas des agents Cilium, qui résolvent `k8s-api.par1.medisphere.internal` par le DNS du socle.

## Diagnostic rapide

```
admin@adm01:~$ kubectl -n kube-system get deploy coredns ; kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +search +showsearch ca01.par1.medisphere.internal
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig @10.10.20.10 ca01.par1.medisphere.internal +short
```

Si le dernier répond et pas l'avant-dernier : CoreDNS (ou une politique réseau qui bloque le port 53 vers `kube-dns`). Si aucun ne répond : le chemin vers le socle (masquage du nœud, bordure, récurseurs).

## Flux

Les pods ne parlent qu'à `kube-dns` ; CoreDNS (pods de `kube-system`, masqués derrière l'adresse de leur nœud) parle à `dns01`/`dns02` en UDP/TCP 53. Flux de bordure : VLAN 40 → `dns01`, `dns02` port 53 (existant depuis M00 : DNS ouvert depuis tous les VLAN).

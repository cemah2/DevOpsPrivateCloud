# Sous le capot : comment Chaos Mesh injecte une panne

> Rédigé au M29-E24 (PLAT-3024), Chaos Mesh 2.8, Kubernetes 1.36, containerd 2.3, Debian 13. Les sorties de nœud sont **représentatives** (lab de référence) : remplace-les par celles de **ton** cluster. Références de code : dépôt `chaos-mesh/chaos-mesh`, étiquette `v2.8.6`.

## 1. Le chemin d'une expérience

```
kubectl apply (NetworkChaos dans chaos-experiences)
   │
   ▼
webhook de validation/défaut (chaos-controller-manager, port 10250 du pod) ──► refus si champ invalide
   │                                                                          (ex. duration dans un Workflow)
   ▼
contrôleur (chaos-controller-manager)
   ├─ finaliseur « chaos-mesh/records » posé sur l'expérience
   ├─ sélection des pods (selector + mode ; filtre d'espaces annotés chaos-mesh.org/inject=enabled)
   ├─ status.experiment.containerRecords[] : un enregistrement par pod/conteneur visé (phase « Not Injected »)
   ├─ réseau : fusion de TOUTES les expériences qui visent un même pod dans l'objet intermédiaire
   │          PodNetworkChaos <pod> (espace du pod) : spec.tcs, spec.ipsets, spec.iptables
   │
   ▼  gRPC + TLS mutuel (port 31767) vers le chaos-daemon DU NŒUD qui porte le pod
chaos-daemon (DaemonSet, privilégié, hostPID, socket de containerd monté en /host-run)
   ├─ PID du conteneur demandé à containerd (socket /run/containerd/containerd.sock)
   ├─ « bpm » (gestionnaire de processus d'arrière-plan) lance la commande à travers nsexec,
   │   qui entre dans les espaces de noms du conteneur (/proc/<pid>/ns/net, pid, mnt…)
   └─ commande : tc, ipset, iptables(-legacy), stress-ng, memStress, toda…
   │
   ▼
noyau du nœud, DANS l'espace réseau / le cgroup du conteneur visé
```

Retour : chaque enregistrement passe `Injected` (`injectedCount` +1). À la pause ou à la suppression, la phase désirée devient `Stop`, le contrôleur demande au daemon de **retirer**, chaque enregistrement repasse `Not Injected` (`recoveredCount` +1), et seulement alors le finaliseur est levé.

## 2. Latence (`delay`) vers une cible

```
admin@adm01:~$ kubectl -n wb-essais get podnetworkchaos client-e24 -o yaml | yq '.spec'
ipsets:
  - name: latence-e24_tgt_…        # adresses des pods de la cible (nom abrégé par le contrôleur)
    ipsetType: …
    cidrs: [10.240.2.37/32]
    source: chaos-experiences/latence-e24
tcs:
  - type: netem
    device: eth0
    ipset: latence-e24_tgt_…
    delay: {latency: 100ms, correlation: "0", jitter: 0ms}
    source: chaos-experiences/latence-e24
admin@k8s-w02:~$ id=$(sudo crictl pods --namespace wb-essais --name '^client-e24$' -q); pid=$(sudo crictl inspectp "$id" | jq .info.pid)
admin@k8s-w02:~$ sudo nsenter -t "$pid" -n tc qdisc show dev eth0
qdisc prio 1: root refcnt 2 bands 4 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1
qdisc sfq 2: parent 1:1 limit 127p quantum 1514b depth 127 divisor 1024
qdisc sfq 3: parent 1:2 limit 127p quantum 1514b depth 127 divisor 1024
qdisc sfq 4: parent 1:3 limit 127p quantum 1514b depth 127 divisor 1024
qdisc netem 5: parent 1:4 limit 1000 delay 100ms
admin@k8s-w02:~$ sudo nsenter -t "$pid" -n iptables-legacy -S | grep -E 'CHAOS|TC-TABLES'
-N CHAOS-OUTPUT
-N TC-TABLES-0
-A OUTPUT -j CHAOS-OUTPUT
-A CHAOS-OUTPUT -j TC-TABLES-0
-A TC-TABLES-0 -o eth0 -m set --match-set latence-e24_tgt_… dst -j CLASSIFY --set-class 0001:0004
```

Lecture : la racine est une file à priorités `prio` à 4 bandes ; les trois premières (trafic normal) ont une `sfq` ; la 4ᵉ porte le `netem`. Aucun filtre `tc` : c'est **iptables** qui classe (`CLASSIFY --set-class 1:4`) les paquets **sortants** dont la destination est dans l'`ipset` de la cible. Le reste ne subit aucun délai. Sans `target`, le `netem` est posé directement à la racine (`qdisc netem 1: root`) : tout ce qui sort du pod est retardé.

Pourquoi `iptables-legacy` : l'image du daemon force la variante *legacy* (`update-alternatives --set iptables /usr/sbin/iptables-legacy`, `images/chaos-daemon/Dockerfile`) ; sur Debian 13, `iptables` du nœud est la variante *nft* : `iptables -S` dans l'espace du pod **ne montre rien**. Cilium, lui, n'est pas concerné : ses règles sont en eBPF sur l'interface de l'hôte, celles-ci sont dans l'espace réseau du pod.

## 3. Partition

```
admin@k8s-w02:~$ sudo nsenter -t "$pid" -n iptables-legacy -S | grep CHAOS
-N CHAOS-INPUT
-N CHAOS-OUTPUT
-A INPUT -j CHAOS-INPUT
-A OUTPUT -j CHAOS-OUTPUT
-A CHAOS-INPUT -j partition-e24-…
-A CHAOS-OUTPUT -j partition-e24-…
-A partition-e24-… -i eth0 -m set --match-set partition-e24_tgt_… src -j DROP -w 5
admin@k8s-w02:~$ kubectl -n chaos-mesh exec <chaos-daemon-du-nœud> -- nsenter -t "$pid" -n ipset list   # ipset absent du nœud
Name: partition-e24_tgt_…
Type: hash:net
Members:
10.240.2.37
```

`hubble observe -n wb-essais --from-pod wb-essais/client-e24` montre les SYN **émis** par le client (Cilium les voit sur l'interface de l'hôte) sans réponse : le paquet est jeté **dans** le pod (sortie) ou **avant** le processus (entrée), pas par une politique Cilium (aucun verdict `DROPPED` de politique).

## 4. Stress CPU

```
admin@k8s-w01:~$ ps -eo pid,ppid,cgroup:80,cmd | grep -E 'stress-ng|nsexec' | grep -v grep
 41210  41190 0::/kubepods.slice/…/cri-containerd-<id-cible>.scope   stress-ng --cpu 1 --cpu-load 50
admin@k8s-w01:~$ cat /proc/41210/cgroup
0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod<uid>.slice/cri-containerd-<id-cible>.scope
admin@k8s-w01:~$ ps -o ppid= -p 41190 | xargs ps -o cmd= -p        # parent : le chaos-daemon (hostPID)
/usr/local/bin/chaos-daemon --runtime containerd …
```

Le daemon lance `stress-ng` par `nsexec` dans l'espace de **PID** du conteneur (le processus y est visible), puis **rattache** le processus au **cgroup** du conteneur (`cgroups.GetAttacherForPID`, `pkg/chaosdaemon/stress_server_linux.go`). Conséquences : la consommation est comptée dans `container_cpu_usage_seconds_total` du conteneur visé et dans `kubectl top pod` ; la **limite CPU** du conteneur s'applique au stress (étranglement : `container_cpu_cfs_throttled_periods_total` monte) ; l'HPA voit la charge. Le stress mémoire (`memStress`) suit le même chemin : il peut déclencher l'**OOM** du conteneur, pas du nœud.

## 5. Cycle de vie et finaliseur

```
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos latence-e24 -o yaml | yq '.metadata.finalizers, .status.experiment'
- chaos-mesh/records
desiredPhase: Run
containerRecords:
  - id: wb-essais/client-e24
    selectorKey: .
    phase: Injected
    injectedCount: 1
    recoveredCount: 0
    events:
      - {type: Succeeded, operation: Apply, timestamp: "…"}
```

- Suppression : `desiredPhase: Stop`, retrait par le daemon, `phase: Not Injected`, `recoveredCount: 1`, finaliseur levé, objet supprimé. Le `PodNetworkChaos` du pod est vidé de cette source (et supprimé quand plus rien ne le référence).
- Pod visé supprimé **pendant** l'expérience : l'enregistrement ne peut plus être retiré (le pod n'existe plus) ; le contrôleur le constate et le marque retiré (il n'y a plus rien à retirer) — vérifier que l'objet part bien ; sinon `chaos-mesh.chaos-mesh.org/cleanFinalizer=forced` (RB-297).
- Daemon injoignable : le retrait échoue, le finaliseur **reste** (c'est voulu : il garantit qu'on ne « perd » pas une panne posée). RB-297.

## 6. Privilèges et sécurité

| Élément | Pourquoi | Risque |
|---|---|---|
| `privileged: true` (chart, défaut) | entrer dans les espaces de noms, `tc`, `iptables`, cgroups | conteneur = root du nœud |
| `hostPID: true` | voir les processus des conteneurs (`/proc/<pid>/ns/*`) | voit et peut signaler tout processus du nœud |
| socket containerd (`/run/containerd` monté) | retrouver les conteneurs, `container-kill` | contrôle total du runtime (créer un conteneur privilégié) |
| API gRPC 31767 | ordres du contrôleur | quiconque la joint **avec un certificat client valide** fait exécuter des commandes sur le nœud |

Le TLS mutuel du gRPC est actif par défaut (`chaosDaemon.mtls.enabled: true`, certificats générés par le chart au rendu). Barrière réseau ajoutée : `plateforme/k8s/espaces/chaos-mesh/30-politiques-reseau.yaml` (seul le contrôleur joint 31767 ; Prometheus joint 31766). Exceptions PSA `privileged` et règles Falco du registre du M26 : ce daemon est **le** composant le plus puissant du cluster après le plan de contrôle ; il ne se justifie que par l'usage réel du chaos (revue annuelle, ADR-0290).

## 7. Trois questions pour un candidat

1. Une latence de 100 ms posée sur un pod vers une seule cible : pourquoi `tc filter show` ne montre rien, et où se fait le tri des paquets ?
2. Pourquoi une expérience peut-elle rester indéfiniment « en suppression », et pourquoi est-ce une protection plutôt qu'un bogue ?
3. Un `StressChaos` CPU fait monter le nombre de réplicas d'un HPA : pourquoi, et pourquoi ne fait-il pas monter la charge des autres pods du nœud au-delà de la limite du conteneur ?

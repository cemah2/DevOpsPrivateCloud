# Du `kubectl apply` au conteneur — analyse sur `k8s-par1`

> Compte rendu de M14-E44 (PLAT-1544). Les valeurs relevées (versions de ressources, PID, adresses,
> identifiants) sont celles de la séance du 2026-10-23 ; elles changent à chaque essai. Aucune clé,
> aucun jeton, aucun contenu de certificat ne figure ici.

## L'API : list, watch et resourceVersion

Requêtes faites avec `curl` et le certificat client personnel (`--cacert`, `--cert`, `--key`), vers `https://k8s-api.par1.medisphere.internal:8443`.

| Étape | Requête | Résultat |
|---|---|---|
| liste | `GET /api/v1/namespaces/wb-essais/configmaps` | `metadata.resourceVersion` de la liste : `1843211` |
| watch | `GET …/configmaps?watch=1&resourceVersion=1843211&allowWatchBookmarks=true` | `ADDED` (1843390), `MODIFIED` (1843402), `BOOKMARK` (1843466), `DELETED` (1843471) |
| écriture périmée | `PUT …/configmaps/capot` avec l'ancienne `resourceVersion` | `409 Conflict` : *the object has been modified* |
| watch trop ancien | `?watch=1&resourceVersion=1843211`, 25 min et de nombreuses écritures plus tard | `200`, puis un événement `ERROR` portant `410 Expired` (*too old resource version*) |

`kubectl get configmaps -n wb-essais -w -v=6` fait exactement la même chose : une liste (`?limit=500`), puis un *watch* à partir de la version de la liste. Les contrôleurs (Deployment, ReplicaSet…) et le kubelet fonctionnent ainsi, par des *informers* qui gardent un cache local à jour et relistent sur `410`.

## L'ordonnanceur

- Pod `capot` créé avec `schedulerName: ordonnanceur-manuel` : resté `Pending`, **aucun** événement (l'ordonnanceur par défaut ignore les pods qui ne lui sont pas destinés).
- Bail de l'ordonnanceur par défaut (`kube-system/kube-scheduler`) détenu par `k8s-cp02` (un seul ordonnanceur actif, les deux autres en attente).
- Liaison manuelle : `POST /api/v1/namespaces/wb-essais/pods/capot/binding` (objet `Binding` vers le nœud `k8s-w02`) → `201 Success`. `spec.nodeName` est passé à `k8s-w02` ; le kubelet a tiré l'image et démarré le conteneur (événements `Pulling`, `Pulled`, `Created`, `Started`, sans `Scheduled`).

## Le kubelet et le CRI

Sur `k8s-w02` :

| Objet | Outil | Valeur relevée |
|---|---|---|
| *sandbox* du pod | `crictl pods --name capot`, `crictl inspectp` | `3b1c…`, adresse 10.240.2.88, espace réseau `/var/run/netns/cni-…`, gestionnaire `runc` par défaut |
| conteneur | `crictl ps --pod 3b1c…`, `crictl inspect` | PID 24517, `cgroupsPath` `kubepods-burstable-pod5d2e….slice:cri-containerd:<id>` |
| vue containerd | `ctr -n k8s.io containers ls` | deux conteneurs : `pause:3.10.2` (le *sandbox*) et `busybox:1.37` |
| processus | `ps -ef --forest` | `containerd-shim-runc-v2 -namespace k8s.io -id 3b1c…` → `/pause` (UID 65535) et `sleep 1000000` (UID 65534) |

Le kubelet ne lance rien lui-même : il demande au runtime par le CRI (`RunPodSandbox`, `CreateContainer`, `StartContainer`). containerd confie chaque pod à un shim, qui appelle runc et reste le parent des processus : c'est pourquoi les conteneurs survivent à un arrêt de containerd ou du kubelet.

## Cgroups et espaces de noms

Nœud : `k8s-w02`. Classe QoS du pod : `Burstable`.

| Fichier (cgroup v2) | Valeur | Origine |
|---|---|---|
| `…/kubepods-burstable-pod5d2e….slice/cri-containerd-<id>.scope/cpu.max` | `20000 100000` | `limits.cpu: 200m` (20 ms par période de 100 ms) |
| `…/cpu.weight` | `4` | `requests.cpu: 100m` → 102 parts → poids cgroup v2 |
| `…/memory.max` | `67108864` | `limits.memory: 64Mi` |
| `…/memory.current` | quelques centaines de Kio | usage réel de `sleep` |

Espaces de noms (`ls -l /proc/<pid>/ns`) : `net`, `ipc` et `uts` identiques pour `pause` et `sleep` ; `pid`, `mnt` et `cgroup` différents. `nsenter -t 24517 -n ip -br addr` montre `eth0` en 10.240.2.88, l'adresse du pod.

## Réponses aux questions

1. *List + watch* donne un état complet une fois puis les seuls changements, dans l'ordre : pas d'interrogation en boucle, charge minimale pour l'API et etcd. Sur `410 Gone`, l'*informer* reliste et repart de la version de la nouvelle liste.
2. `resourceVersion` ordonne les événements d'un *watch* et détecte les écritures concurrentes ; c'est une valeur **opaque** (aujourd'hui issue de la révision d'etcd) qu'on ne compare pas comme un nombre ni entre types d'objets.
3. L'API a vérifié l'authentification, le droit `create` sur `pods/binding` et que le pod n'était pas déjà lié. Un ordonnanceur a besoin de lire pods et nœuds, de créer des liaisons et des événements, de mettre à jour le statut des pods et, s'il est redondé, d'un bail.
4. Le conteneur `pause` tient les espaces partagés du pod (réseau, IPC, UTS) et survit aux redémarrages des autres conteneurs : l'adresse du pod ne change pas. Les PID ne sont pas partagés par défaut ; `shareProcessNamespace: true` les partage (signaux, `/proc` communs).
5. `requests.cpu` → `cpu.weight` (partage en cas de contention), `limits.cpu` → `cpu.max` (ralentissement au-delà, jamais de mise à mort) ; au-delà de `limits.memory`, le noyau tue (OOM).
6. containerd arrêté : les conteneurs continuent mais plus rien ne démarre, le nœud devient `NotReady` (runtime en panne). Kubelet arrêté : les conteneurs continuent sans surveillance, le bail du nœud n'est plus renouvelé, `Unknown`, puis éviction côté API après 5 minutes.
7. `crictl inspectp` donne l'espace réseau réel, l'adresse vue par le runtime, le gestionnaire, les montages et les cgroups : de quoi vérifier sur le nœud ce que l'API ou le CNI affirment.

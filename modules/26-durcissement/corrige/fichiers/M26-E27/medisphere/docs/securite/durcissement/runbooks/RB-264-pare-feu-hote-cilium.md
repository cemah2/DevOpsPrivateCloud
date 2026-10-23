# RB-264 — Pare-feu d'hôte de Cilium : observer, appliquer, revenir en arrière

| | |
|---|---|
| Ticket | SEC-2727 (M26-E27) |
| Propriétaire | Équipe Plateforme ; astreinte : Nadia Roussel |
| Gravité si mal appliqué | un nœud injoignable (SSH, API, kubelet), voire l'API du cluster |
| Dernier exercice de retour arrière | <DATE> (`k8s-w03`, étapes 1 à 3 chronométrées : <MESURES>) |

## 1. Ce qui est en place

- `hostFirewall.enabled: true` et `enable-extended-ip-protocols: "true"` (VRRP) dans les values de la release Helmfile `cilium` (`composants/cilium/values.yaml`).
- Trois `CiliumClusterwideNetworkPolicy` d'**entrée** (`composants/cilium/hote/`) : `hote-commun`, `hote-plan-controle`, `hote-travailleurs`. Elles ne sélectionnent **que** les nœuds étiquetés `medisphere.internal/pare-feu-hote: "oui"` (`cluster/noeuds.yaml`, étiquette gérée).
- Sur chaque nœud, l'agent Cilium porte un point de terminaison d'hôte (identité 1, `reserved:host`) : mode **audit** (on journalise ce qui serait refusé) ou **application**.
- Flux autorisés : `docs/kubernetes/reseau/matrice-flux-cluster.md`, section « Entrées des nœuds ».

## 2. Avant tout changement (politique, étiquette, version de Cilium)

1. Console Proxmox de chaque nœud concerné ouverte et testée (`admin` local).
2. Sauvegarde PBS `par1/k8s` de moins de 24 h ; instantané etcd vérifié (RB-141).
3. `admin.conf` disponible (bris de glace, M24) dans un fichier 600 temporaire.
4. Un seul nœud à la fois ; les nœuds de contrôle après une nuit sans incident sur les travailleurs ; le nœud qui porte la VIP 10.10.40.200 en dernier (`ip -br addr | grep 10.10.40.200` sur les trois).

## 3. Mettre un nœud sous pare-feu

```
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh audit k8s-w03          # D'ABORD l'audit
admin@adm01:~/src/k8s$ git switch -c pare-feu-k8s-w03                  # étiquette dans cluster/noeuds.yaml, MR
admin@adm01:~/src/k8s$ outils/etiqueter-noeuds.sh                      # après fusion, depuis main
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh etat k8s-w03            # étiquette oui, audit Enabled
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh verdicts k8s-w03 1h     # flux qui SERAIENT refusés
```

Observation d'au moins 24 h, avec une journée normale (collecte, sauvegarde Velero, synchronisation d'Argo CD, `kubectl logs`/`exec`, `ssh`). Chaque verdict `audit` : flux légitime oublié → MR sur la politique ; flux illégitime → noté (ticket SEC). **Si l'agent redémarre pendant l'observation, le nœud applique aussitôt** : `outils/pare-feu-hote.sh etat` le montre (`Disabled`), le repasser en audit.

Passage en application, seulement avec zéro verdict inexpliqué sur 24 h :

```
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh applique k8s-w03
admin@adm01:~$ kubectl get nodes ; kubectl -n <espace> logs <pod du nœud> --tail=1
admin@adm01:~$ cilium bgp peers                     # CLI cilium d'adm01 : deux sessions « established » par travailleur
admin@adm01:~$ ssh k8s-w03 true ; nc -vz -w 3 10.10.40.63 10255     # 10255 : doit être refusé
```

Puis Prometheus : `up{instance="k8s-w03"} == 0` vide ; Watchdog et témoin de `mon01` verts.

## 4. Retour arrière, du plus doux au plus fort

| Étape | Quand | Commande | Durée mesurée |
|---|---|---|---|
| 1. Audit | un flux légitime est refusé, l'API répond | `outils/pare-feu-hote.sh audit <nœud>` | <MESURE> |
| 2. Désélection | la politique est fausse pour ce nœud | `kubectl label node <nœud> medisphere.internal/pare-feu-hote-` puis retrait de `cluster/noeuds.yaml` (MR) | <MESURE> |
| 3. Console | l'API ne répond plus, ou le nœud est injoignable | console Proxmox du nœud, puis ci-dessous | <MESURE> |
| 4. Désactivation | plusieurs nœuds touchés, cause inconnue | `hostFirewall.enabled: false` (values, MR, `helmfile apply`), redémarrage des agents | <MESURE> |

Étape 3 (procédure *Emergency Recovery* de la documentation Cilium), sur la console du nœud :

```
admin@k8s-w03:~$ sudo crictl ps --name cilium-agent -q
admin@k8s-w03:~$ C=$(sudo crictl ps --name cilium-agent -q)
admin@k8s-w03:~$ sudo crictl exec "$C" sh -c \
    'cilium-dbg endpoint config $(cilium-dbg endpoint get -l reserved:host -o jsonpath="{[0].id}") PolicyAuditMode=Enabled'
```

Le nœud cesse de jeter ; l'agent retrouve l'API et ses politiques. **Puis** l'étape 2 (sinon le prochain redémarrage de l'agent réapplique). Si c'est un nœud de contrôle et que l'API répond encore par les deux autres, passe par l'API (étape 1) : la VIP bascule seule si keepalived ne reçoit plus d'annonces.

## 5. Symptômes et pistes

| Symptôme | Piste |
|---|---|
| Deux ou trois nœuds de contrôle portent 10.10.40.200 | VRRP jeté : `enable-extended-ip-protocols` absent de `cilium-config`, ou VRRP absent de `hote-plan-controle` ; `cilium-dbg monitor --type drop` (`DROP_CT_UNKNOWN_PROTO` ou `Policy denied`) |
| Après le redémarrage d'un serveur d'API, son membre etcd est isolé (le serveur d'API ne revient pas), ou la VIP se dédouble | etcd 2379-2380 ou VRRP autorisés depuis `kube-apiserver` seulement : cette identité vient des Endpoints du Service `kubernetes` et disparaît pendant le redémarrage ; les autoriser depuis `remote-node` (`hote-plan-controle`) |
| Nœud `NotReady`, kubelet sans API | 8443 refusé depuis `remote-node` (travailleur) ou 6443 depuis `cluster` (nœud de contrôle) |
| `kubectl logs`/`exec` en erreur vers un nœud | 10250 refusé depuis `kube-apiserver` |
| Cibles Prometheus d'un nœud à 0 | ports de `supervision` (9100, 9962, 9964, 9965, 10250, 2112 ; 2381, 10257, 10259, 8405 sur les nœuds de contrôle) |
| `cilium status` : nœuds injoignables par la santé | 4240 ou ICMP depuis `remote-node`/`health` |
| Sessions BGP tombées | 179 depuis 10.10.40.2/.3 ; vérifier aussi la bordure |
| OpenBao refuse les connexions des pods (`k8s-par1`) | 8443 depuis `vault01-03` |

## 6. Limites connues (documentation « Host Policies known issues », Cilium 1.20)

- Les politiques d'hôte ne s'appliquent pas au trafic qui arrive par l'interface WireGuard de l'hôte : entre deux **travailleurs**, avec le chiffrement nœud à nœud (M26-E26), les flux d'hôte à hôte ne sont pas filtrés par ces politiques. Les nœuds de contrôle (exclus du chiffrement nœud à nœud) le sont.
- Au premier passage en application, des réponses à des connexions légitimes peuvent être jetées quelques secondes.
- Les Services `LoadBalancer`/`NodePort` sont filtrés au niveau des pods de destination (remplacement de kube-proxy), pas par ces politiques.

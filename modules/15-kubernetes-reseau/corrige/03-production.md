# Module 15 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- **Support de la Gateway API par Cilium 1.20.2** (E33) : établi par la lecture de la documentation 1.20 et du code d'ingestion de l'opérateur au tag `v1.20.2` (`operator/pkg/model/ingestion/gateway.go`), pas par un essai. Ce qui en ressort : `BackendTLSPolicy`, `TLSRoute` (v1), `ReferenceGrant`, `ListenerSet` sont pris en charge ; `listeners[].tls.options`, `spec.tls.frontend` (validation du certificat client, GEP-91) et `spec.tls.backend` ne sont **pas lus**. Les versions de TLS observées seraient donc les défauts d'Envoy (TLS 1.2 minimum, 1.3 maximum) : à confirmer par `openssl s_client` sur ton lab ;
- comportement de FRR 10.7, en aide au redémarrage en douceur, quand le *hold time* d'un pair qui a annoncé la capacité GR **expire** (routes conservées comme « périmées » pendant le temps de redémarrage, ou retirées) : c'est l'objet d'une mesure de E25 ;
- multichemin par défaut de FRR (« maximum compilé » d'après le rôle `frr` de M07) : le corrigé l'écrit explicitement (`maximum_paths: 8`) ;
- noms et formats exacts de certaines sorties de Cilium 1.20 utilisées par les checks et la sonde : annotation `network.cilium.io/wg-pub-key` des `CiliumNode`, clé `enable-wireguard` de `cilium-config`, statut `bgpInstances[].peers[].peeringState` (« established ») et `timers.appliedHoldTimeSeconds` des `CiliumBGPNodeConfig`, métrique `cilium_unreachable_nodes` (documentation 1.20) ; ligne `Encryption:` de `cilium-dbg status` ;
- options de la CLI `cilium` : `cilium upgrade --dry-run-helm-values`, `cilium connectivity test --test-namespace`, `cilium bgp routes advertised ipv4 unicast` (à confirmer par `--help` de ta version) ;
- ExternalDNS 0.23 : publication d'un Service `LoadBalancer` créé par Cilium pour une Gateway à partir de l'annotation `external-dns.alpha.kubernetes.io/hostname` recopiée depuis `spec.infrastructure.annotations` (E33) ;
- MTU des routes des pods de 1355 octets en tunnel VXLAN + WireGuard (1500 − 50 − 95 : constantes `TunnelOverheadIPv4` et `WireguardOverhead` de `pkg/mtu` au tag `v1.20.2`, vérifiées dans le code mais pas mesurées ; l'interface `eth0` des pods reste à 1500, Cilium pose la MTU sur les routes du pod) ;
- *vérifié hors lab, dans des conteneurs* : `outils/ca-partenaires.sh` (step 0.28 : autorité, certificat client `clientAuth` seul de 30 jours, fichiers en 600) et le `nginx.conf` du relais dans `nginxinc/nginx-unprivileged:1.30-alpine` (nginx 1.30.2, utilisateur 101, racine en lecture seule) : 400 sans certificat client et avec un certificat d'une autre autorité, 200 avec `centre-test-01`, en-tête `X-Partenaire` envoyé par le client écrasé, TLS 1.1 refusé. Reste à vérifier sur le lab : le passage par `gw-partenaires` (Envoy en *passthrough*) et step 0.31 ;
- toutes les **mesures** chiffrées des fiches (chiffrement, performances, convergence) sont des ordres de grandeur attendus, **pas** des mesures du workbook : remplace-les par les tiennes.

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M15-E24/` à `M15-E30/`, `M15-E32/` à `M15-E34/`. Le fichier `composants/cilium/values.yaml` complet de fin de palier est dans `M15-E27/` (rendu validé par `helm template` du chart 1.20.2).

---

### M15-E24 — Chiffrer le trafic entre nœuds

**Solution**

Fichiers : [extrait de *values*](fichiers/M15-E24/k8s/composants/cilium/values.yaml.extrait), [fiche `chiffrement.md`](fichiers/M15-E24/medisphere/docs/kubernetes/reseau/chiffrement.md). Instrument de mesure : [`ressources/E24-mesure-iperf3.yaml`](../ressources/E24-mesure-iperf3.yaml).

*1. Lecture.* Chaque agent génère sa paire de clés WireGuard, publie la clé publique dans l'annotation `network.cilium.io/wg-pub-key` de son `CiliumNode` ; les autres agents la lisent et ajoutent le nœud comme pair de `cilium_wg0` (UDP 51871), avec en *allowed-ips* les adresses des pods de ce nœud. Mode par défaut : chiffrement des flux **pod → pod d'un autre nœud** (y compris derrière un Service ClusterIP, et Envoy → pod). Rien n'est chiffré pour un pod du même nœud (voulu). `nodeEncryption` (beta) ajoute nœud ↔ nœud et nœud ↔ pod, mais exclut par défaut les nœuds portant `node-role.kubernetes.io/control-plane` (sinon un travailleur qui change de clé ne pourrait plus joindre l'API pour publier la nouvelle). En tunnel : double encapsulation (VXLAN puis WireGuard), d'où une MTU des pods plus basse. IPsec : clés symétriques à créer et faire tourner soi-même (Secret `cilium-ipsec-keys`, `keyRotationDuration`), plus d'en-têtes, seul avantage l'accélération matérielle (AES-NI la rend aussi rapide) et l'existence de modules FIPS.

*2. Mesure avant.*

```
admin@adm01:~$ kubectl apply -f ~/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources/E24-mesure-iperf3.yaml
admin@adm01:~$ kubectl -n wb-perf get pod -o wide
admin@adm01:~$ B=$(kubectl -n wb-perf get pod mesure-b -o jsonpath='{.status.podIP}')
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- iperf3 -c $B -t 30
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- iperf3 -c $B -t 30 -P 4
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- ping -c 100 -i 0.2 -q $B
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- ip link show eth0          # mtu 1500 : Cilium ne réduit pas l'interface du pod
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- ip route                   # « … mtu 1450 » : la MTU utile est sur les routes (1500 − 50 de VXLAN)
admin@adm01:~$ kubectl top node k8s-w01 k8s-w02                             # pendant le débit
admin@k8s-w02:~$ ip -br address                                               # interface du VLAN 40 (eth0 : nommée par cloud-init, M14)
admin@k8s-w02:~$ sudo tcpdump -ni eth0 -A -c 40 'udp port 8472'
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- curl -s "http://$B:8080/echo?msg=donnees-de-test"
```

Dans la capture, la ligne `GET /echo?msg=donnees-de-test HTTP/1.1` apparaît en clair à l'intérieur des paquets UDP 8472 : VXLAN encapsule, il ne chiffre pas.

*3. Décision* : chiffrement entre pods, sans `nodeEncryption` ni mode strict (justification dans la fiche). Les flux entre nœuds de contrôle (etcd 2379/2380, API 6443) sont déjà en TLS mutuel : `nodeEncryption` ne les toucherait d'ailleurs pas (exclusion par défaut).

*4. Activation.* L'extrait dans `composants/cilium/values.yaml`, MR, puis :

```
admin@adm01:~/src/k8s$ task cilium:appliquer          # ou : cilium upgrade --version <VERSION-CILIUM> --reset-values --values composants/cilium/values.yaml
admin@adm01:~$ kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard}'   # true
admin@adm01:~$ kubectl -n kube-system get pod -l k8s-app=cilium -o wide        # âge des pods
```

Le chart a `rollOutCiliumPods: false` : si seule la ConfigMap change, les pods de l'agent ne redémarrent pas et l'option reste lettre morte. On redémarre dans le respect de la stratégie du DaemonSet :

```
admin@adm01:~$ kubectl -n kube-system rollout restart ds/cilium
admin@adm01:~$ kubectl -n kube-system rollout status ds/cilium
admin@adm01:~$ cilium status --wait
```

*5. Preuve.*

```
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep Encryption
Encryption: Wireguard [cilium_wg0 (Pubkey: …, Port: 51871, Peers: 5)]
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg encrypt status
admin@adm01:~$ kubectl get ciliumnodes -o custom-columns='NOEUD:.metadata.name,CLE:.metadata.annotations.network\.cilium\.io/wg-pub-key'
admin@k8s-w02:~$ ip -d link show cilium_wg0
admin@k8s-w02:~$ sudo tcpdump -ni eth0 -c 20 'udp port 51871 or udp port 8472'
admin@k8s-w02:~$ sudo tcpdump -ni cilium_wg0 -A -c 20 'udp port 8472'      # le paquet VXLAN, avant chiffrement
```

Cinq pairs (six nœuds moins soi). Sur `eth0`, plus d'UDP 8472 entre pods : seulement de l'UDP 51871, illisible. Sur `cilium_wg0`, la requête est en clair, dans son enveloppe VXLAN (UDP 8472 entre les adresses des nœuds : en mode tunnel, c'est le paquet VXLAN que Cilium confie à WireGuard, d'où le filtre `udp port 8472` et non `tcp port 8080`) : c'est l'interface **avant** chiffrement (le noyau chiffre en sortie de cette interface).

*6. Mesure après* : mêmes commandes ; MTU des routes des pods 1355 (1500 − 50 VXLAN − 95 réservés par Cilium pour WireGuard, en-tête et bourrage compris), `eth0` toujours à 1500 ; `cilium_wg0` est à 1405 (1500 − 95). Tableau dans la fiche.

*7.* Aucune règle de bordure : les nœuds sont tous dans le VLAN 40, aucun paquet 51871 ne traverse `gw01`/`gw02`. Le flux est inscrit dans la matrice du cluster (E32).

**Explications**

WireGuard est un tunnel point à point par nœud : une seule interface, une clé par pair, un état minimal, des primitives fixes (ChaCha20-Poly1305, Curve25519). Cilium s'en sert sans démon supplémentaire : l'agent programme l'interface du noyau (`wireguard` intégré depuis Linux 5.6) et les routes. Le coût est surtout **processeur** : chiffrement logiciel de chaque paquet, sur des VMs sans déchargement réseau. Le débit chute, la latence augmente peu.

**Alternatives**

IPsec de Cilium (clés à gérer, accélérable) ; chiffrement applicatif (TLS entre l'API et PostgreSQL : protège aussi les flux du même nœud, mais demande à chaque application de le faire) ; *service mesh* mTLS (Istio ambient, Linkerd) ou ztunnel de Cilium (`encryption.type: ztunnel`, nouveauté à surveiller) : identité par charge de travail, au prix d'un composant de plus. Pour HDS, un chiffrement transparent entre nœuds **plus** TLS sur les flux qui portent des données de santé est la défense en profondeur raisonnable.

**Pièges classiques**
- Croire le fichier : ConfigMap modifiée mais agents non redémarrés, `cilium-dbg status` dit `Encryption: Disabled`.
- Conclure sur une capture faite sur `cilium_wg0` (en clair, normal) au lieu de l'interface physique.
- Oublier que deux pods du même nœud ne sont jamais chiffrés : un test avec les deux pods sur le même nœud « prouve » à tort que rien ne change.
- Activer le mode strict sans avoir prévu la reconstruction d'un nœud (nouvelle clé) : coupure du nœud jusqu'à la propagation.
- Laisser des captures `.pcap` sur un nœud.

**En production chez MédiSphère**

Contrôle continu de la présence des clés (sonde E26), alerte si `Peers` ≠ nombre de nœuds − 1, revue annuelle de l'option `nodeEncryption` et du mode strict, et TLS applicatif vers PostgreSQL (M27) pour les données de santé.

---

### M15-E25 — Haute disponibilité de l'entrée : perdre un nœud, une passerelle

**Solution**

Fichiers : [`frr.yml`](fichiers/M15-E25/ansible/inventories/lab/group_vars/role_routeur/frr.yml) (multichemin explicite, route de rejet, plafond de préfixes), [`composants/cilium/bgp/bordure.yaml`](fichiers/M15-E25/k8s/composants/cilium/bgp/bordure.yaml) (redémarrage en douceur), [`echo-lb.yaml`](fichiers/M15-E25/manifestes/echo-lb.yaml), [RB-152](fichiers/M15-E25/medisphere/docs/kubernetes/reseau/runbooks/RB-152-bgp.md). Sonde : [`ressources/E25-sonde-http.sh`](../ressources/E25-sonde-http.sh).

*1. Le chemin.*

```
admin@adm01:~$ cilium bgp routes advertised ipv4 unicast
admin@gw01:~$ sudo vtysh -c 'show ip bgp 10.10.41.10/32'
admin@gw01:~$ ip route show 10.10.41.10
10.10.41.10 nhid 63 proto bgp metric 20
	nexthop via 10.10.40.61 dev ens19.40 weight 1
	nexthop via 10.10.40.62 dev ens19.40 weight 1
	nexthop via 10.10.40.63 dev ens19.40 weight 1
```

Les trois travailleurs (label `bgp=par1`) annoncent toutes les adresses `LoadBalancer` (annonce `services-lb`), avec `externalTrafficPolicy: Cluster` (défaut de la Gateway, `gatewayAPI.externalTrafficPolicy`) : chaque nœud peut servir. FRR installe un chemin par nœud si le multichemin est permis (trois chemins eBGP du même AS, même longueur : chemins égaux). Le corrigé écrit `maximum_paths: 8` dans `frr.yml` pour que ce soit une exigence et non un défaut. Dans le nœud qui reçoit, le programme eBPF de Cilium reconnaît l'adresse du Service de la Gateway et remet la connexion à l'Envoy **local** par TPROXY (documentation *Ingress and Gateway API reference*), qui termine le TLS et choisit un pod de l'application (éventuellement sur un autre nœud, chiffré par WireGuard).

*2. Référence.* `E25-sonde-http.sh https://mediagenda-recette.apps.par1.medisphere.internal` 5 minutes : 0 échec.

*3. Perte brutale.*

```
root@pve01:~# qm stop 2145          # k8s-w02, arrêt « électrique »
admin@gw01:~$ sudo journalctl -u frr -f | grep -i -E 'hold|down'
```

Avec le *hold* de 9 s posé en E11 : environ un tiers des **nouvelles** connexions (celles que le hachage envoie vers 10.10.40.62) échouent pendant ≈ 9 s, puis la session tombe (`Hold Timer Expired`) et le chemin disparaît. Les connexions TCP établies vers ce nœud sont perdues de toute façon (leur état, et l'Envoy qui les termine, sont sur le nœud éteint). Avec le défaut (90 s, lu dans la CRD), ce serait 90 s. Le *hold time* négocié est le minimum des deux propositions (FRR propose 180 s en profil « traditional »).

Redémarrage d'un **agent** seul (`kubectl -n kube-system delete pod cilium-xxxxx` sur `k8s-w02`) : l'agent ferme sa session, la bordure retire le chemin aussitôt, puis le remet quand l'agent revient (10 à 20 s). Le plan de données du nœud, lui, n'a jamais cessé de fonctionner : retirer le chemin était inutile, et quelques connexions hachées vers ce nœud au moment du retrait se perdent.

*4. Redémarrage en douceur.* `gracefulRestart.enabled: true`, `restartTimeSeconds: 30` dans `bordure.yaml`, MR, `task appliquer`. FRR est en aide au redémarrage par défaut : il conserve les routes d'un pair qui a annoncé la capacité, pendant le temps de redémarrage annoncé, quand la session se ferme. Le redémarrage d'agent ne retire plus rien (0 échec à la sonde). Le revers : si FRR traite aussi l'expiration du *hold time* d'un nœud **mort** comme un redémarrage, il garde ses routes jusqu'à 30 s : c'est la mesure à faire (refaire l'étape 3) ; d'où un temps de redémarrage court, à peine plus long qu'un redémarrage d'agent mesuré.

```
admin@adm01:~$ kubectl get ciliumbgpnodeconfigs -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.bgpInstances[*].peers[*]}{.peerAddress}={.peeringState}/{.timers.appliedHoldTimeSeconds}s {end}{"\n"}{end}'
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors 10.10.40.61' | grep -i -A3 'graceful'
```

*5. La bordure.*
(a) `sudo systemctl stop frr` sur **`gw02`** : la sonde ne voit rien (seule la table du maître sert les clients) ; les nœuds voient leurs sessions vers 10.10.40.3 passer en `active`/`connect`. Sur `gw02`, `ip route get 10.10.41.10` répond… via la route par défaut, vers le WAN : si `gw02` devenait maître dans cet état, les paquets vers les adresses de service partiraient vers le LAN maison (et Internet), traduits par le NAT de sortie. Correctif : route de rejet `10.10.41.0/24 blackhole` de distance 250 (`frr_routes_statiques`), qui ne sert que quand BGP ne dit rien (les /32 appris sont plus spécifiques). Application par le rôle, `gw02` d'abord ; `ip route get 10.10.41.10` sur `gw02` FRR arrêté répond ensuite `blackhole` (ou `RTNETLINK answers: Invalid argument`, qui signale aussi une route de rejet). `sudo systemctl start frr`.
(b) Bascule par RB-071 (M07) : 1 à 3 s d'interruption (le temps du VRRP), parce que `gw02` avait **déjà** ses sessions et ses chemins : aucun calcul BGP au moment de la bascule. Retour sur `gw01` de même.
(c) FRR arrêté sur le **maître** : plus aucune route vers 10.10.41.0/24 sur la passerelle qui reçoit le trafic ; avec la route de rejet, tout est jeté (au lieu de fuir) ; toutes les adresses de service sont injoignables jusqu'au retour de FRR ou à la bascule manuelle ; la sonde E26 le voit en 5 minutes au plus (contrôle `bordure` sur le maître). Faire surveiller FRR par keepalived (`track_script`) : avec `nopreempt`, seul un passage en `FAULT` fait basculer, et dans le groupe `BORDURE` c'est **toute** la bordure (tunnels, NAT, tous les VLAN) qui bascule ; un faux positif du script coûterait plus cher qu'une panne de FRR, rare. Décision du corrigé : alerte + bascule manuelle (RB-152). Les deux décisions sont défendables si elles sont écrites.

*6. `externalTrafficPolicy`.*

```
admin@adm01:~$ kubectl apply -f corrige/fichiers/M15-E25/manifestes/echo-lb.yaml
admin@adm01:~$ IP=$(kubectl -n wb-essais get svc echo-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
admin@adm01:~$ curl -s http://$IP/clientip                    # Cluster : adresse d'un nœud (masquage) ou 10.10.10.10 selon le nœud
admin@adm01:~$ kubectl -n wb-essais patch svc echo-lb -p '{"spec":{"externalTrafficPolicy":"Local"}}'
admin@adm01:~$ kubectl -n wb-essais scale deploy/echo --replicas=1
admin@adm01:~$ cilium bgp routes advertised ipv4 unicast | grep $IP   # un seul nœud annonce
admin@adm01:~$ curl -s http://$IP/clientip                    # 10.10.10.10:… : adresse du client préservée
admin@adm01:~$ kubectl -n wb-essais delete svc echo-lb ; kubectl -n wb-essais scale deploy/echo --replicas=2
```

En `Cluster`, tous les nœuds annoncent ; un nœud sans pod local renvoie vers un pod d'un autre nœud et **masque** la source (le pod voit l'adresse du nœud) ; en `Local`, seuls les nœuds qui ont un pod prêt annoncent, la source est préservée, mais la répartition dépend du nombre de pods par nœud. La Gateway voit l'adresse du client dans les deux cas : le trafic arrive toujours à l'Envoy **local** par TPROXY, sans traduction, et Envoy pose `X-Forwarded-For`.

*7.* RB-152 complété (tableau des temps, constat, décision sur keepalived).

**Explications**

La haute disponibilité de l'entrée repose sur trois mécanismes indépendants : le multichemin de la bordure (répartition et survie à la perte d'un chemin), la détection de la perte d'un pair (*hold time*, ou BFD qui manque dans Cilium 1.20) et la conservation des routes pendant un redémarrage prévu (GR). Les deux derniers tirent en sens contraire : l'un veut oublier vite un pair silencieux, l'autre veut s'en souvenir. Le VRRP de la bordure, lui, est indépendant de BGP parce que **les deux** passerelles sont toujours pairs de tous les nœuds.

**Alternatives**

Annonces L2 de Cilium (un seul nœud répond à l'ARP pour une adresse : pas de répartition, bascule par ARP gratuit, aucune dépendance à la bordure) ; MetalLB en BGP (même logique, BFD disponible avec le mode FRR-K8s) ; `externalTrafficPolicy: Local` partout avec un pod par nœud (DaemonSet) pour préserver la source sans Gateway ; BFD sur un futur plan de contrôle qui le supporte.

**Pièges classiques**
- Tester sur la passerelle maître, ou modifier les deux passerelles d'un coup.
- Croire qu'un seul chemin installé est normal : `show ip bgp` montre trois chemins reçus mais un seul `multipath`/installé.
- Oublier la route de rejet : la panne de BGP devient une **fuite** vers le WAN.
- Activer le GR avec un long temps de redémarrage (120 s par défaut de la CRD) : la perte d'un nœud se paie en minutes.
- Mesurer avec `curl` « à la main » : une interruption de 2 s ne se voit pas ; il faut une sonde horodatée.

**En production chez MédiSphère**

BFD dès qu'il est disponible ; hachage L4 à la bordure ; alerte sur le nombre de chemins installés sur le maître (sonde E26, puis Prometheus) ; test de bascule de la bordure et de perte de nœud deux fois par an (exercice de PRA, F5).

---

### M15-E26 — Superviser le réseau du cluster

**Solution**

Fichiers : *values* ([extrait](fichiers/M15-E26/k8s/composants/cilium/values.yaml.extrait)) ; Hubble UI ([route](fichiers/M15-E26/k8s/composants/reseau/hubble-ui/httproute.yaml), [ReferenceGrant](fichiers/M15-E26/k8s/composants/reseau/hubble-ui/referencegrant.yaml), [politique](fichiers/M15-E26/k8s/composants/reseau/hubble-ui/cnp-hubble-ui.yaml)) ; identité ([`rbac/supervision/supervision.yaml`](fichiers/M15-E26/k8s/rbac/supervision/supervision.yaml), [`outils/kubeconfig-supervision.sh`](fichiers/M15-E26/k8s/outils/kubeconfig-supervision.sh)) ; sonde dans `plateforme/outils` ([`bin/ms-verif-k8s-reseau`](fichiers/M15-E26/outils/bin/ms-verif-k8s-reseau), [configuration](fichiers/M15-E26/outils/etc/ms-verif-k8s-reseau.conf), [tests bats](fichiers/M15-E26/outils/tests/bats/ms-verif-k8s-reseau.bats) : 17 tests, sans réseau, [unités systemd](fichiers/M15-E26/outils/systemd/), [extrait du Taskfile](fichiers/M15-E26/outils/Taskfile-install-extrait.yml), [section d'astreinte](fichiers/M15-E26/outils/docs/astreinte-extrait.md)) ; bordure : [extrait d'`etat-reseau`](fichiers/M15-E26/ansible/roles/sonde_reseau/files/etat-reseau.extrait) (champ `routes_service`) ; [fiche `supervision.md`](fichiers/M15-E26/medisphere/docs/kubernetes/reseau/supervision.md).

*1. Métriques.* Après application (et redémarrage des agents, comme en E24) :

| Question | Métrique (documentation *Monitoring & Metrics* 1.20) |
|---|---|
| un agent ne joint plus d'autres nœuds | `cilium_unreachable_nodes`, `cilium_node_health_connectivity_status` |
| paquets refusés par une politique | `cilium_drop_count_total{reason="Policy denied",…}`, `hubble_drop_total{reason=…}` |
| table eBPF presque pleine | `cilium_bpf_map_pressure{map_name=…}` (≥ 1 : pleine) |
| point de terminaison en erreur | `cilium_endpoint_state{endpoint_state="invalid"}` / `not-ready` |
| sessions BGP | `cilium_bgp_control_plane_session_state` (1 = établie) — et le statut des `CiliumBGPNodeConfig` |

*2.*

```
admin@adm01:~$ kubectl get certificate -A
admin@adm01:~$ kubectl get certificate -A -o custom-columns='ESPACE:.metadata.namespace,NOM:.metadata.name,PRET:.status.conditions[?(@.type=="Ready")].status,EXPIRE:.status.notAfter,RENOUVELLE:.status.renewalTime'
admin@adm01:~$ kubectl get ciliumbgpnodeconfigs -o yaml | grep -E 'name:|peerAddress|peeringState'
```

*3. Identité.* `kubectl apply -f rbac/supervision/supervision.yaml` (par la MR et `task appliquer`), puis `outils/kubeconfig-supervision.sh`. Preuve : `kubectl --kubeconfig ~/.config/workbook/k8s-supervision.kubeconfig auth can-i get secrets -n kube-system` → `no` ; `get nodes` → liste.

*4-5. La sonde.* Elle lit des **statuts** (DaemonSets, Deployments, `CiliumNode`, `CiliumBGPNodeConfig`, `Certificate`), les métriques des agents en HTTP, l'état de la bordure par le compte `supervision` (commande forcée `etat-reseau` étendue d'un champ `routes_service`) et teste chaque nom publié (DNS de `dns01`, HTTPS vérifié contre la racine). Installation et test d'alerte :

```
admin@adm01:~/src/outils$ task test:bats && task install:systeme
admin@adm01:~$ sudo systemctl enable --now ms-verif-k8s-reseau.timer
admin@adm01:~$ ms-verif-k8s-reseau ; echo $?                  # 0
admin@adm01:~$ kubectl label node k8s-w03 bgp-                # geste de test, noté au journal
admin@adm01:~$ journalctl -t ms-alerte -f                     # alerte « bgp » (le nœud n'a plus d'instance) et « bordure » (2 sauts au lieu de 3 : toujours ≥ 2, donc OK)
admin@adm01:~/src/k8s$ task etiquettes                  # remet le label depuis cluster/noeuds.yaml
```

Remarque sur le message : un nœud **désélectionné** n'a plus d'instance BGP du tout (son `CiliumBGPNodeConfig` disparaît) : la sonde le voit par le **compte** des sessions établies (4 au lieu de 6), pas par un état « non établi ». Délai : au plus 5 minutes (timer) + la durée d'un passage.

*6. Hubble UI.* Ordre : politique `hubble-ui-entree` (identité `ingress` seule, port 8081), puis activation de l'UI, puis route et `ReferenceGrant`. Vérifications :

```
admin@adm01:~$ curl -sI https://hubble.apps.par1.medisphere.internal/ | head -1                                # HTTP/1.1 200
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- curl -s -m 3 http://hubble-ui.kube-system.svc         # délai dépassé
admin@adm01:~$ curl -s -m 5 --resolve hubble.apps.par1.medisphere.internal:443:10.10.70.200 https://hubble.apps.par1.medisphere.internal/ ; echo $?   # échec
```

Pour le deuxième essai, vérifie **où** le paquet est refusé : `hubble observe --to-namespace kube-system --to-label k8s-app=hubble-ui --verdict DROPPED` doit montrer un refus en **entrée** de `hubble-ui` ; si `wb-essais` refuse déjà en sortie (politiques de E06), autorise temporairement la sortie de la sonde vers `kube-system` pour que l'essai prouve bien la politique de `hubble-ui`.

*7.* Section d'astreinte (fichier fourni).

**Explications**

Sans Prometheus, la supervision se fait par **sondes de service** qui lisent ce que les composants disent d'eux-mêmes (statuts de l'API) et ce qu'ils exposent (métriques en texte). La sonde vérifie aussi ce que voit l'utilisateur (nom → HTTPS) : un cluster dont tous les composants sont verts peut ne rien servir. La vue de la bordure est indispensable : un nœud peut croire sa session établie quand la passerelle maître n'a pas installé la route (filtre, plafond de préfixes).

**Alternatives**

`cilium status --output json` dans la sonde (exige `exec` dans les pods : droits bien plus larges) ; `cmctl` pour les certificats ; le *Hubble Timescape* ou l'export des flux pour l'historique ; kube-prometheus-stack (M21) qui remplacera la plupart de ces contrôles par des règles d'alerte.

**Pièges classiques**
- Une sonde qui répond 0 quand elle ne peut rien lire (kubeconfig expiré, API injoignable) : « rien vu » doit être rouge.
- Un ClusterRole de lecture « `*` » qui inclut les Secrets.
- Publier Hubble UI avant la politique, ou par un nom que les répartiteurs relaient vers l'extérieur.
- Activer la famille Hubble `http` sur les espaces de MédiAgenda : des URL avec des identifiants de patients dans les métriques.
- `grep` sur une sortie tabulaire de `kubectl` au lieu de `jq` sur le JSON : la sonde casse au premier changement de colonnes.

**En production chez MédiSphère**

Prometheus et Alertmanager (M21) avec les tableaux de bord de Cilium et de Hubble ; authentification OIDC devant Hubble UI (M24) ; rotation du jeton de `ms-supervision` ; la sonde reste comme contrôle « de bout en bout » indépendant de la pile de supervision.

---

### M15-E27 — Mettre à jour Cilium sans coupure

**Solution**

Fichiers : [*values* complet de fin de palier](fichiers/M15-E27/k8s/composants/cilium/values.yaml), [extrait du Taskfile](fichiers/M15-E27/k8s/Taskfile-cilium-extrait.yml) (`CILIUM_VERSION`, aperçu, vérification préalable, application), [RB-153](fichiers/M15-E27/medisphere/docs/kubernetes/reseau/runbooks/RB-153-mise-a-jour-cilium.md), [CHG-1627](fichiers/M15-E27/medisphere/docs/kubernetes/changements/CHG-1627.md).

*1. Lecture.* La vérification préalable **tire les images** de la nouvelle version sur chaque nœud (DaemonSet `cilium-pre-flight-check`) et valide les politiques existantes pour la nouvelle version (Deployment du même nom) ; sans kube-proxy, elle doit recevoir `k8sServiceHost` et `k8sServicePort` (elle ne peut pas joindre l'API par le ClusterIP `kubernetes`). Pendant le redémarrage d'un agent : les politiques existantes, l'équilibrage et la connectivité continuent (programmes eBPF chargés) ; les politiques L7 (proxy) coupent les connexions concernées, les nouvelles politiques attendent, la surveillance (`cilium-dbg monitor`, Hubble) a un trou. `upgradeCompatibility` garde des valeurs par défaut de l'ancienne version lors d'une montée de **mineure** ; inutile pour un correctif. Matrice : 1.20.x testé de Kubernetes 1.33 à 1.36.

*2. Préparation.* Défauts du chart : `updateStrategy.rollingUpdate.maxUnavailable: 2` pour `cilium` **et** pour `cilium-envoy`. Avec trois travailleurs qui portent l'entrée, deux à la fois retireraient deux chemins sur trois et deux Envoy sur trois : on passe à 1. `operator.podDisruptionBudget.enabled: true` (deux réplicas, un drain ne les prend pas ensemble). GR actif (E25).

*3-4.*

```
admin@adm01:~/src/k8s$ task cilium:preflight
admin@adm01:~$ kubectl -n kube-system get ds,deploy | grep pre-flight        # DESIRED = READY, 1/1, puis supprimés par la tâche
admin@adm01:~/src/k8s$ task cilium:apercu > /tmp/apres.yaml && helm -n kube-system get values cilium -o yaml > /tmp/avant.yaml
admin@adm01:~$ diff <(yq -P 'sort_keys(..)' /tmp/avant.yaml) <(yq -P 'sort_keys(..)' /tmp/apres.yaml)
```

Si ta version est déjà la dernière (1.20.2 à la rédaction) : `CILIUM_VERSION=1.20.1`, MR, application (c'est la répétition du retour arrière par le code), puis `1.20.2`.

*5.*

```
admin@adm01:~/src/k8s$ task cilium:appliquer
admin@adm01:~$ kubectl -n kube-system rollout status ds/cilium ; kubectl -n kube-system rollout status ds/cilium-envoy
admin@adm01:~$ cilium version ; cilium status --wait ; cilium bgp peers
admin@adm01:~$ cilium connectivity test --test-namespace wb-cilium-test
admin@adm01:~$ cilium connectivity test --cleanup --test-namespace wb-cilium-test    # ou kubectl delete ns wb-cilium-test-1 …
```

Le test de connectivité déploie des pods clients et serveurs dans son espace, **toujours suffixé** d'un numéro (`wb-cilium-test-1` ; aide de `--test-namespace`, CLI 0.20), en tirant des images de `quay.io` (par le cache Harbor) ; avec les politiques de cluster de E28 (proxy DNS sans refus), il reste vert ; supprime tout ce qu'il laisse (`kubectl get ns | grep cilium-test`).

*6. Retour arrière.* `helm -n kube-system history cilium`, `helm -n kube-system rollback cilium <N> --wait`, contrôles, puis MR qui remet `CILIUM_VERSION` en accord, puis remontée par le code. La sonde E25 mesure chaque étape (RB-153).

**Explications**

La CLI `cilium` est une enveloppe de Helm : la release `cilium` porte l'historique, `helm rollback` y revient. Le seul état qui fait foi reste le dépôt : un retour arrière non reporté serait défait à la prochaine application. Le redémarrage en douceur BGP et `maxUnavailable: 1` transforment une mise à jour « qui coupe un tiers du trafic deux fois » en une mise à jour quasi invisible ; Envoy reste le seul point de coupure (connexions en cours sur son nœud).

**Alternatives**

`helm upgrade` direct (même chose, sans l'aide de la CLI) ; GitOps (Argo CD, M20) avec vagues de synchronisation ; nœud par nœud avec `cordon`/`drain` avant chaque agent (inutile pour Cilium, dont le plan de données survit au redémarrage).

**Pièges classiques**
- `--reuse-values` entre deux versions du chart (valeurs nouvelles ignorées) ; et son cousin implicite : sans option, la CLI `cilium` 0.20 applique `--reset-then-reuse-values` (values de la release précédente fusionnées sous celles du fichier), d'où `--reset-values` dans la tâche : le fichier du projet est la seule source.
- Mettre à jour l'agent par `kubectl set image` sans l'opérateur.
- Oublier la vérification préalable : chaque agent attend son image, et une erreur de tirage bloque le déploiement au milieu.
- Lancer le test de connectivité sans savoir ce qu'il crée, ou le laisser traîner.
- `helm rollback` sans MR de remise en accord.

**En production chez MédiSphère**

Suivi des avis de sécurité de Cilium et d'Envoy (Renovate, M13), fenêtre mensuelle, mise à jour d'un cluster de recette avant la production (F4), tests de bout en bout automatiques après chaque mise à jour.

---

### M15-E28 — Segmenter un cluster multi-équipes

**Solution**

Fichiers : [`base-dns.yaml`](fichiers/M15-E28/k8s/composants/reseau/politiques/base-dns.yaml), [`isolement-mediagenda-dev.yaml`](fichiers/M15-E28/k8s/composants/reseau/politiques/isolement-mediagenda-dev.yaml) (et `-recette`, `medidoc-dev`), [`sortie-mediagenda.yaml`](fichiers/M15-E28/k8s/composants/reseau/politiques/sortie-mediagenda.yaml), [labels des espaces](fichiers/M15-E28/k8s/espaces/labels-equipes.extrait.yaml), [sondes de test](fichiers/M15-E28/manifestes/sondes-segmentation.yaml), [fiche `segmentation.md`](fichiers/M15-E28/medisphere/docs/kubernetes/reseau/segmentation.md) (matrice de tests).

*1. Lecture.* Un pod passe en refus par défaut dans une direction dès qu'une politique qui le **sélectionne** a une section de cette direction ; `enableDefaultDeny: {ingress: false, egress: false}` fait qu'une politique est ignorée pour ce calcul (elle ajoute des règles sans fermer le reste). Un **refus** l'emporte toujours sur une autorisation, d'où qu'elle vienne (CNP, CCNP, NetworkPolicy). Labels de l'espace : `io.cilium.k8s.namespace.labels.<clé>` dans `fromEndpoints`/`toEndpoints` ; nom de l'espace : `io.kubernetes.pod.namespace`. `toFQDNs` : le proxy DNS de l'agent voit les réponses aux requêtes qu'une règle DNS L7 lui fait intercepter, et autorise pour **ce pod** les adresses des noms qui correspondent, pour la durée du TTL (avec un minimum réglable).

*2-3.* Labels : rien à poser, `medisphere.internal/equipe` est sur les trois espaces depuis le M14 ([rappel](fichiers/M15-E28/k8s/espaces/labels-equipes.extrait.yaml)) ; `kubectl get ns -L medisphere.internal/equipe` le confirme et montre qu'aucun espace de plateforme ne le porte. Puis `base-dns` : aucun pod ne change d'état (vérifier `hubble observe -n wb-essais --verdict DROPPED` vide avant/après) ; `hubble observe -n mediagenda-recette --protocol dns` montre les noms demandés.

*4.* Les cloisons sont des **refus** (`ingressDeny`/`egressDeny`), une politique par espace (le modèle « pas mon espace » n'existe pas en générique), sélection des pairs par `Exists` sur le label d'équipe **et** `NotIn` sur le nom de l'espace. `enableDefaultDeny` à `false` : elles ne ferment rien d'autre.

*5. Preuve.*

```
admin@adm01:~$ kubectl apply -f corrige/fichiers/M15-E28/manifestes/sondes-segmentation.yaml   # sans la politique de test (commente-la)
admin@adm01:~$ kubectl -n mediagenda-dev exec sonde -- nc -zv -w 3 postgresql.mediagenda-recette.svc 5432   # échec
admin@adm01:~$ kubectl -n medidoc-dev exec sonde -- curl -s -m 3 http://mediagenda-api.mediagenda-recette.svc/sante  # échec
admin@adm01:~$ hubble observe --from-namespace mediagenda-dev --verdict DROPPED -o compact | tail -3   # « Policy denied by denylist »
```

Règle 2 : pose `tout-autoriser-test` (`fromEntities: [all]`) dans `mediagenda-recette`, refais le test depuis `mediagenda-dev` : toujours refusé, raison « denylist » ; supprime-la aussitôt.

*6. Sortie.* `sortie-mediagenda` (sélection par le label d'équipe, autorisation `toFQDNs` `calendrier.api.gouv.fr` en 443). Depuis l'**API** de recette (les sondes, elles, n'ont que le DNS dans les politiques de E17) :

```
admin@adm01:~$ kubectl -n mediagenda-recette exec deploy/mediagenda-api -- python -c "import urllib.request as u; print(u.urlopen('https://calendrier.api.gouv.fr/jours-feries/metropole.json', timeout=5).status)"   # 200
admin@adm01:~$ kubectl -n mediagenda-recette exec deploy/mediagenda-api -- python -c "import urllib.request as u; u.urlopen('https://example.com', timeout=5)"    # délai dépassé
```

Si l'API publique change d'adresse : la prochaine résolution apprend la nouvelle, rien à modifier. À l'expiration d'une entrée, les connexions ouvertes ne sont pas coupées ; les nouvelles vers une adresse non réapprise sont refusées.

*7.* Fiche fournie.

**Explications**

Les politiques Cilium sont une **union** d'autorisations avec des refus prioritaires. Une cloison robuste est donc un refus posé par la plateforme, et la liberté des équipes se limite à ouvrir **à l'intérieur** de leur espace. La sortie Internet par noms ne peut pas être un refus (pas de `toFQDNs` dans les refus) : elle repose sur le refus par défaut des espaces et sur le fait que les équipes ne peuvent pas écrire de politiques (RBAC, puis Kyverno au M26).

**Alternatives**

`AdminNetworkPolicy`/`BaselineAdminNetworkPolicy` (API SIG Network, priorités explicites) : non retenues tant que Cilium 1.20 ne les implémente pas (à vérifier) ; `policyEnforcementMode: always` (tout est refusé par défaut, partout, y compris `kube-system` : à préparer longtemps à l'avance) ; un cluster par équipe (vCluster, M28 ; ou des clusters séparés) ; Egress Gateway pour une sortie à adresse fixe.

**Pièges classiques**
- Une CCNP avec `endpointSelector: {}` et une section `egress` : tout le cluster passe en refus par défaut en sortie.
- Écrire la cloison comme une autorisation : la première CNP permissive l'ouvre.
- `matchExpressions` : les expressions d'un même sélecteur sont un **ET** ; deux sélecteurs dans la liste sont un **OU**.
- `toFQDNs` sans règle DNS L7 : rien n'est jamais autorisé.
- Oublier de tester la sortie depuis le **bon** pod (la sonde n'a pas les autorisations de l'API).

**En production chez MédiSphère**

Politiques générées depuis le registre des espaces (une ligne par équipe), contrôle d'admission qui interdit les politiques Cilium aux équipes (M26), revue trimestrielle de la matrice (E32), alertes sur les refus inattendus (M21).

---

### M15-E29 — Mesurer les performances réseau

**Solution**

Fichiers : [fiche `performances.md`](fichiers/M15-E29/medisphere/docs/kubernetes/reseau/performances.md) (protocole, tableau, lecture), [extrait de la MR brouillon](fichiers/M15-E29/k8s/composants/cilium/values-natif.yaml.extrait) (routage natif).

*1.* Protocole dans la fiche. Référence sans Kubernetes :

```
admin@k8s-w02:~$ iperf3 -s -1
admin@k8s-w01:~$ iperf3 -c 10.10.40.62 -t 30 -P 4
```

(`iperf3` est déjà sur les nœuds : playbook des outils de diagnostic de M15-E02, service arrêté. `-s -1` sert une seule mesure puis s'arrête : rien ne reste à l'écoute.)

*2.* Commandes de E24 ; pour « même nœud », change le `nodeSelector` de `mesure-a` en `k8s-w02`. Requêtes courtes :

```
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- sh -c 'for i in $(seq 1000); do curl -s -o /dev/null -w "%{time_total}\n" http://'$B':8080/hostname; done' | sort -n | awk '{a[NR]=$1} END {print "médiane", a[int(NR/2)], "p99", a[int(NR*0.99)]}'
```

*3. MTU.* `kubectl -n wb-perf exec mesure-a -- ping -c 3 -M do -s 1327 $B` passe, `-s 1328` échoue (`message too long, mtu=1355`) : 1327 + 8 (ICMP) + 20 (IP) = 1355 = MTU des routes du pod (`ip route` dans le pod). Empilement : 1500 sur le VLAN − 95 (WireGuard, réservés par Cilium 1.20, bourrage compris) − 50 (VXLAN).

*4. Natif.* La MR brouillon (`routingMode: native`, `ipv4NativeRoutingCIDR: 10.240.0.0/16`, `autoDirectNodeRoutes: true`) est appliquée depuis sa branche dans la fenêtre :

```
admin@adm01:~/src/k8s$ git switch m15-e29-natif && task cilium:appliquer && kubectl -n kube-system rollout restart ds/cilium && kubectl -n kube-system rollout status ds/cilium
admin@k8s-w01:~$ ip route | grep 10.240                 # 10.240.<N>.0/24 via 10.10.40.6x dev eth0 pour chaque autre nœud
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -E 'Routing|Masquerading'
```

Mesures, puis retour : `git switch main && task cilium:appliquer`, redémarrage des agents, `cilium status --wait`, sonde, `cilium bgp peers`, `cilium-dbg status | grep Encryption`, et `helm -n kube-system get values cilium | grep -E 'autoDirectNodeRoutes|ipv4NativeRoutingCIDR'` **vide**. Ce dernier contrôle n'est pas une formalité : sans `--reset-values`, la CLI `cilium` reprend par défaut les values de la release précédente (`--reset-then-reuse-values`, CLI 0.20) ; `autoDirectNodeRoutes: true`, absent du fichier de `main`, survivrait au retour, et l'agent refuse de démarrer en mode tunnel avec cette option (`auto-direct-node-routes cannot be used with tunneling`, `daemon/cmd/daemon_main.go` au tag `v1.20.2`) : le premier agent redémarré resterait en erreur et son nœud perdrait le réseau des pods. Si c'est arrivé : réapplique avec `--reset-values` (la tâche du corrigé de E27 le fait). Le masquage reste actif : la sortie hors de 10.240.0.0/16 est traduite en adresse du nœud (la bordure ne connaît pas les adresses des pods).

*5. BBR* : `bandwidthManager.enabled` et `bbr: true` exigent un noyau récent (≥ 5.18 pour BBR des pods, à vérifier dans la page *Bandwidth Manager*) et ne valent que pour des liens longs ou avec pertes : sans intérêt mesurable dans le lab.

*6.* Fiche ; `kubectl delete namespace wb-perf`.

**Explications**

Sur un seul hyperviseur, tout est **processeur** : chaque couche (veth, VXLAN, WireGuard) ajoute du travail par paquet. Le chiffrement coûte bien plus que l'encapsulation ; le routage natif ne gagne « que » l'encapsulation VXLAN et 50 octets de MTU. Une comparaison n'a de sens qu'à protocole identique et avec la dispersion : un écart de 5 % entre deux séries d'un lab virtuel n'est souvent que du bruit.

**Alternatives**

`cilium connectivity perf` (mesures intégrées, pods et options standard) ; netperf (TCP_RR, TCP_CRR pour les petites requêtes) ; `fortio` ou `k6` (M29) pour des requêtes HTTP réalistes ; mesures sur un vrai matériel avant toute décision de production.

**Pièges classiques**
- Comparer une série « même nœud » à une série « inter-nœuds ».
- Une seule mesure de 10 s, sans répétition.
- Oublier que le retour en VXLAN redémarre aussi les agents : la fenêtre doit couvrir l'aller **et** le retour.
- Laisser un serveur `iperf3` à l'écoute sur un nœud (`-1` l'évite).

**En production chez MédiSphère**

Mesures de référence refaites après chaque changement de version ou de mode, publiées dans la fiche ; suivi des métriques de débit et de pertes par Prometheus (M21) ; tests de charge applicatifs (M29).

---

### M15-E30 — ADR : le réseau et l'entrée de `k8s-par1`

**Solution**

Exemple d'ADR : [`ADR-0150-reseau-entree-cluster.md`](fichiers/M15-E30/medisphere/docs/kubernetes/reseau/adr/ADR-0150-reseau-entree-cluster.md). Ta décision peut différer (par exemple MetalLB en BGP, ou un autre contrôleur Gateway API) si elle est argumentée par des faits.

**Grille d'auto-évaluation** (chaque ligne vaut 1 point ; 8/10 attendu)

| # | Critère |
|---|---|
| 1 | Le contexte cite les contraintes réelles : un site, bordure VRRP + FRR, données de santé, petite équipe, ingress-nginx retiré, versions |
| 2 | Les sept décisions sont présentes, chacune avec au moins deux options réellement envisagées |
| 3 | Les dépendances entre décisions sont écrites (Gateway de Cilium ⇒ remplacement de kube-proxy ; natif ⇒ L2 commun ou annonce des PodCIDR) |
| 4 | Chaque option rejetée l'est pour une raison vérifiable (exercice, mesure, documentation), pas un goût |
| 5 | Les chiffres viennent de **tes** mesures (E24 coût du chiffrement, E25 convergence, E29 natif vs VXLAN) |
| 6 | ingress-nginx est écarté pour la bonne raison (plus de correctifs de sécurité) et les conditions où il resterait acceptable sont dites |
| 7 | Les conséquences négatives sont honnêtes (dépendance à un projet, limites de la Gateway 1.20, Hubble sans authentification, FRR du maître) |
| 8 | Les actions sont rattachées à un module ou à une date |
| 9 | Les conditions de révision sont concrètes et observables |
| 10 | Trois pages au plus, gabarit MADR, sur `main`, au chemin imposé |

**Pièges classiques** : un ADR qui raconte l'installation au lieu de décider ; « Cilium, parce que c'est le meilleur » ; des options de paille (une option que personne n'envisagerait) ; des chiffres sans conditions de mesure.

---

### M15-E31 — Questions de production : réseau Kubernetes

1. **Flux en clair sur le VLAN 40.** Pod → pod d'un autre nœud : **chiffré** (mode par défaut). Kubelet → pod d'un autre nœud : le kubelet ne sonde que les pods de **son** nœud (aucun flux sur le VLAN) ; un flux hôte → pod distant ne serait chiffré qu'avec `nodeEncryption`. `adm01` → Gateway : TLS de la Gateway (WireGuard ne couvre jamais l'extérieur) ; Envoy → pod d'un autre nœud : chiffré (ligne « L7 Proxy / Ingress » du tableau). Pod → `s3-01` : sort du cluster, en clair pour WireGuard, protégé par le TLS de S3. etcd : TLS mutuel de kubeadm, pas WireGuard (hôte à hôte, et nœuds de contrôle exclus de `nodeEncryption` par défaut).
2. **b.** La clé est créée par l'agent et publiée dans son `CiliumNode` ; les autres agents surveillent ces objets et mettent leurs pairs à jour ; quelques paquets peuvent se perdre pendant la transition (problème connu). a) faux : rien n'est copié à la main ; c) faux : la clé est aléatoire ; d) faux : il n'y a pas de repli en clair « jusqu'au prochain redémarrage » (sans mode strict, du trafic non chiffré peut passer pendant la transition, mais par construction du chemin, pas par repli). `nodeEncryption` exclut les nœuds de contrôle pour qu'un travailleur qui change de clé puisse toujours joindre l'API et publier la nouvelle.
3. Défauts : *hold* de 90 s côté Cilium (180 s côté FRR, minimum négocié : 90 s). Le hachage envoie environ **1/3** des nouveaux flux vers le nœud mort pendant 90 s. Les connexions établies ne survivent pas : leur état TCP, leur session TLS et l'Envoy qui les termine étaient sur ce nœud ; une fois la route retirée, leurs paquets arrivent sur un autre nœud qui ne les connaît pas (RST).
4. FRR garde les routes du pair comme « périmées » pendant le temps de redémarrage annoncé (120 s) si la fermeture est traitée comme un redémarrage — selon le traitement de l'expiration du *hold time* (RFC 8538), il peut donc continuer d'envoyer un tiers du trafic vers un nœud mort pendant 2 minutes. Il fallait **raccourcir** le temps de redémarrage (≈ durée d'un redémarrage d'agent) et mesurer le comportement réel, en même temps que l'on raccourcissait le *hold time*.
5. **b.** Le plan de données eBPF reste chargé : flux établis, Services, politiques déjà programmées continuent ; ce qui vit dans le processus de l'agent s'arrête (nouvelles politiques, BGP sans GR, Hubble, DNS proxy — les requêtes DNS soumises à une règle L7 échouent pendant ce temps, à vérifier). a) faux ; c) faux : depuis la 1.16, Envoy tourne dans le DaemonSet `cilium-envoy`, séparé : il **survit** au redémarrage de l'agent, mais son propre redémarrage (mise à jour) coupe les connexions L7 du nœud ; d) faux : le DNS est CoreDNS.
6. L'agent et l'opérateur partagent des CRD et des formats (identités, IPAM, état BGP, CiliumNodes) ; une version d'opérateur qui écrit un champ ou un format que l'ancien agent ne comprend pas (ou l'inverse) peut, par exemple, casser l'attribution des plages de pods à un nouveau nœud ou la synchronisation des identités. La procédure garantit qu'ils sont testés ensemble.
7. Tous les pods du cluster (sauf ce que l'agent exempte) passent en **refus par défaut en sortie** : seul le DNS reste permis, tout le reste tombe (API, bases, sorties) — y compris dans `kube-system` si le sélecteur l'inclut. Il fallait `enableDefaultDeny: {egress: false}` (politique `base-dns`), et exclure `kube-system`.
8. **b.** Un refus l'emporte toujours sur une autorisation, quel que soit le type de politique (documentation *Deny Policies*). a, c, d faux : il n'y a ni spécificité, ni priorité par portée, ni ordre de création. Empêcher une équipe de la supprimer : la CCNP est une ressource de cluster ; une équipe n'a des droits que dans ses espaces (RBAC) ; seuls les administrateurs peuvent la supprimer, et l'audit de l'API (M14-E27) et Git tracent leurs actions.
9. Le proxy DNS a appris l'adresse pour 60 s (ou le minimum configuré) ; au-delà, si l'adresse n'est plus « vivante » pour ce pod (aucune connexion ouverte), elle sort de la politique : la prochaine connexion de l'application, qui n'a pas re-résolu, est **refusée**. Réglages : le TTL minimum du proxy (`dnsProxy.minTtl` du chart, option `tofqdns-min-ttl` ; 0 par défaut en 1.20, c'est-à-dire le TTL de l'amont respecté) et le délai de grâce des connexions inactives (`dnsProxy.idleConnectionGracePeriod`, 0 s par défaut). La bonne correction est côté application : respecter le TTL. Augmenter le minimum élargit la fenêtre d'une adresse réattribuée à autre chose.
10. Refus : `*.amazonaws.com` couvre des milliers de services de tiers et rend la sortie de données incontrôlable (n'importe quel compartiment S3 public). Proposer : les noms précis des points d'accès utilisés (région, service), mieux encore un point d'accès interne (le S3 de MédiSphère n'est d'ailleurs pas chez AWS : MédiDoc utilise `s3-01` ou RGW) ; ou un mandataire de sortie journalisé ; et un ticket de la RSSI pour toute exception.
11. **b.** Le trafic vers une Gateway Cilium est toujours remis à l'Envoy **local** par TPROXY, sans traduction : Envoy voit 10.10.10.10 et l'écrit dans `X-Forwarded-For` (0 saut de confiance). a) c'est le cas d'un Service `LoadBalancer` ordinaire en `Cluster` ; c) la VIP de la bordure n'apparaît jamais comme source (pas de NAT sur la bordure entre MGMT et le VLAN 41) ; d) faux. En *passthrough* : Envoy relaie un flux TCP, l'application voit l'adresse d'Envoy (du nœud), pas celle du client.
12. Relais applicatif derrière une `TLSRoute` *passthrough* (E33 : simple, l'application ou un relais termine le TLS, mais la Gateway ne voit plus le HTTP : pas de filtres, pas de journaux L7) ; `CiliumEnvoyConfig` pour configurer Envoy directement (puissant, hors de l'API standard, dette à chaque mise à jour) ; une autre implémentation Gateway API qui supporte `spec.tls.frontend` (un composant de plus) ; attendre une version de Cilium qui l'implémente ; mTLS fait par les répartiteurs `lb01`/`lb02` (HAProxy sait vérifier un certificat client), au prix d'un TLS de plus vers le cluster.
13. Le gain est faible (15 %), mesuré sur un lab où le processeur limite tout, et il coûte une hypothèse forte : tous les nœuds dans un même domaine L2 (ou l'annonce des plages de pods à la bordure, que sa politique refuse). Le chiffrement, lui, coûte 60 % : c'est lui qui dimensionne. Ce qui changerait : un débit entre pods devenu goulot **mesuré** en production, des nœuds physiques avec déchargement matériel, ou une vraie fabric BGP qui accepterait les PodCIDR.
14. Bordure : 15 annonceurs × 2 passerelles = 30 sessions ; `bgp listen limit 16` (voisins dynamiques **par passerelle**) : 15 annonceurs passent encore, sans marge (au-delà de 16 voisins, les suivants sont refusés) : à relever, plafond `maximum-prefix` à revoir, `maximum-paths 8` limite à 8 chemins égaux (ou ne pas faire annoncer tous les nœuds : un sous-ensemble dédié à l'entrée). WireGuard : 14 pairs par nœud, sans difficulté (WireGuard passe à l'échelle de centaines de pairs), mais une clé de plus à propager à chaque nœud. DNS : CoreDNS à 2 réplicas devient un point de contention et un risque (perte d'un nœud) : plus de réplicas, `NodeLocal DNSCache`, anti-affinité. Prévoir aussi des nœuds dédiés à l'entrée (Envoy) et le dimensionnement de la mémoire d'Envoy.
15. Toute personne sur MGMT ou sur le VPN d'administration, et tout pod du cluster qui joint la Gateway. Ils y voient tous les flux : espaces, pods, ports, verdicts, requêtes DNS (noms demandés) — pas d'URL ni d'en-têtes tant qu'aucune visibilité L7 n'est active. Premier changement : authentification OIDC (OAuth2 Proxy, M24) avec un groupe autorisé ; ensuite, filtrage des pods qui peuvent joindre la Gateway pour ce nom.
16. Par ordre de valeur : les **tests** (matrice de E28 rejouée et datée, idéalement automatisée et rejouée régulièrement) et les **journaux** de refus (Hubble : refus `denylist` entre espaces sur une période), qui prouvent le comportement ; la **configuration** versionnée (politiques de refus, historique Git, revue) qui prouve l'intention ; les captures d'écran, qui ne prouvent presque rien. Un auditeur préfère une preuve rejouable devant lui.

---

### M15-E32 — La matrice des flux du cluster

**Solution**

Exemple : [`matrice-flux-cluster.md`](fichiers/M15-E32/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.md). Requêtes de vérification dans sa section 6.

**Grille d'auto-évaluation** (1 point par ligne ; 7/9 attendu)

| # | Critère |
|---|---|
| 1 | Les quatre familles sont couvertes, y compris ce qu'Hubble ne voit pas (réseau de l'hôte : etcd, kubelet, VRRP des nœuds de contrôle) |
| 2 | Chaque ligne a source, destination, protocole et port, chiffrement, besoin |
| 3 | « Autorisé par » nomme une politique qui **autorise** (ou une ligne de `pare_feu.yml`, ou « même VLAN ») ; jamais `refus-par-defaut` |
| 4 | Les flux sortants passent par la bordure et y retrouvent leur ligne (`ca01`, `reg01`, `s3-01`, `dns01`, Internet) |
| 5 | Les flux refusés exprès sont listés avec la politique qui les refuse et une preuve |
| 6 | La vérification cite des requêtes Hubble réelles, une période, et au moins un écart traité |
| 7 | WireGuard (UDP 51871) et VXLAN (UDP 8472) apparaissent, avec l'explication « même VLAN » |
| 8 | La tenue à jour est décrite (qui, quand, lien avec les MR) |
| 9 | Document sur `main`, au chemin imposé |

**Pièges classiques** : recopier les politiques sans confronter au trafic réel ; oublier le plan de contrôle (invisible dans Hubble) ; noter « autorisé » un flux qui passe sans savoir par quelle règle (c'est un écart à traiter, pas une ligne).

---

### M15-E33 — Durcir l'entrée : TLS, en-têtes et authentification mutuelle

**Solution**

Fichiers : partenaires dans `plateforme/k8s` ([`gateway.yaml`](fichiers/M15-E33/k8s/composants/reseau/partenaires/gateway.yaml), [`tlsroute.yaml`](fichiers/M15-E33/k8s/composants/reseau/partenaires/tlsroute.yaml), [`certificate.yaml`](fichiers/M15-E33/k8s/composants/reseau/partenaires/certificate.yaml), [`nginx.conf`](fichiers/M15-E33/k8s/composants/reseau/partenaires/nginx.conf), [`relais.yaml`](fichiers/M15-E33/k8s/composants/reseau/partenaires/relais.yaml), [`politiques.yaml`](fichiers/M15-E33/k8s/composants/reseau/partenaires/politiques.yaml)), [`outils/ca-partenaires.sh`](fichiers/M15-E33/k8s/outils/ca-partenaires.sh), [en-têtes de la route `mediagenda`](fichiers/M15-E33/k8s/espaces/mediagenda-recette/httproute-mediagenda.extrait.yaml), [fiche `durcissement-entree.md`](fichiers/M15-E33/medisphere/docs/kubernetes/reseau/durcissement-entree.md).

*1. État des lieux.*

```
admin@adm01:~$ N=mediagenda-recette.apps.par1.medisphere.internal
admin@adm01:~$ for v in tls1 tls1_1 tls1_2 tls1_3; do printf '%s : ' $v; openssl s_client -connect $N:443 -servername $N -$v </dev/null 2>&1 | grep -E -m1 'Protocol|alert|no protocols'; done
admin@adm01:~$ openssl s_client -connect $N:443 -servername $N -tls1_2 -cipher 'ALL' </dev/null 2>/dev/null | grep -E 'Cipher|Verify'
admin@adm01:~$ openssl s_client -connect $N:443 -servername $N -showcerts </dev/null 2>/dev/null | grep -E '^ [0-9] s:|i:'
```

(Selon la compilation d'`openssl` sur `adm01`, `-tls1` et `-tls1_1` peuvent être refusés **par le client** lui-même : `openssl s_client -tls1_1 -cipher 'DEFAULT@SECLEVEL=0'` force l'essai.) Résultat attendu : 1.0 et 1.1 refusés, 1.2 et 1.3 acceptés, suites ECDHE : ce sont les défauts d'Envoy, que Cilium ne modifie pas.

*2. Support.* Essai dans `wb-essais` sur `gw-essai` : une option dans `listeners[].tls.options` et un bloc `spec.tls.frontend.default.validation` (avec une `ConfigMap` de CA) : les objets sont **acceptés** par l'API (schéma valide), mais rien ne change dans le comportement (aucun certificat client demandé, mêmes versions de TLS). Lire `kubectl get gatewayclass cilium -o yaml` (`status.supportedFeatures`) et la documentation : `BackendTLSPolicy` et `TLSRoute` sont listés, la validation client non. Conclusion dans la fiche (tableau). Supprime les essais.

*3. En-têtes.* Filtre `ResponseHeaderModifier` sur chaque règle de la route `mediagenda`, `max-age=300` d'abord puis un an :

```
admin@adm01:~$ curl -sI https://$N/sante | grep -i -E 'strict|nosniff|referrer|frame'
admin@adm01:~$ curl -sI http://$N/sante | head -3          # 301 + Location: https://… (E12), sans HSTS
```

*4. Autorité.* Phrase de passe dans `~/.config/workbook/ca-partenaires.pass` (600) et Vault `critique`, puis :

```
admin@adm01:~/src/k8s$ outils/ca-partenaires.sh init
admin@adm01:~/src/k8s$ outils/ca-partenaires.sh emettre centre-test-01
```

Retrait : pas de liste de révocation ; certificats de 30 jours non renouvelés, rotation de l'autorité en urgence.

*5-6.* Relais et Gateway par MR (`task appliquer` crée les ConfigMap `relais-mtls-conf` et `ca-partenaires` depuis les fichiers). Le certificat du relais est délivré par DNS-01 : le solveur de `step-ca-acme` qui a le sélecteur `dnsZones: [apps.par1.medisphere.internal]` est plus spécifique que le solveur HTTP-01 sans sélecteur, cert-manager le choisit. Le nom est publié par la source `service` d'ExternalDNS grâce à l'annotation recopiée par Cilium sur le Service de la Gateway (le filtre `--gateway-name=gw-par1` ne concerne que la source `gateway-httproute`). Annonce BGP : `services-lb` sélectionne tous les Services `LoadBalancer`.

```
admin@adm01:~$ kubectl -n passerelles get gateway gw-partenaires
admin@adm01:~$ kubectl -n mediagenda-recette get tlsroute mediagenda-partenaires -o jsonpath='{.status.parents[0].conditions}' | jq
admin@adm01:~$ dig +short @10.10.20.10 mediagenda-partenaires.apps.par1.medisphere.internal        # 10.10.41.11
admin@gw01:~$ ip route show 10.10.41.11
```

*7.* Commandes de la fiche (section 6) : 400 sans certificat (nginx termine la négociation puis refuse), 200 avec le certificat de test (l'API reçoit `X-Partenaire: centre-test-01`), 400 avec un certificat de `ca01`. Ajoute `10.10.41.11` à `MS_K8S_ADRESSES_SERVICE` de la sonde (E26) et la Gateway à la matrice (E32).

**Explications**

Une Gateway Cilium accepte des champs qu'elle n'implémente pas : la validation du schéma est faite par l'API, pas par l'implémentation. C'est pourquoi le comportement observé fait foi. Le *passthrough* garde la négociation TLS du client de bout en bout jusqu'au relais : le relais est le seul à pouvoir demander et vérifier un certificat client. Une autorité **dédiée** évite le piège d'un certificat serveur de `ca01` qui, portant aussi l'usage client, ouvrirait l'API à toute machine de MédiSphère. L'en-tête d'identité est fiable parce que le relais l'**écrase** et que seule l'identité du relais peut joindre l'API (politiques).

**Alternatives**

Validation client par `lb01`/`lb02` (HAProxy `verify required`) puis TLS vers la Gateway (le cluster ne voit plus le client) ; MédiAgenda qui termine lui-même le mTLS (uvicorn sait le faire : `--ssl-ca-certs`, `--ssl-cert-reqs`), sans relais mais avec des clés dans l'application ; Vault PKI (M25) pour l'autorité des partenaires, avec révocation et durées très courtes ; `CiliumEnvoyConfig` pour configurer la validation client dans Envoy (hors API standard) ; une autre implémentation Gateway API qui supporte GEP-91.

**Pièges classiques**
- Croire qu'un `kubectl apply` sans erreur veut dire « supporté ».
- `ssl_client_certificate` vers la racine MédiSphère : tout certificat de `ca01` devient un badge d'accès.
- `proxy_set_header` oublié : un client envoie lui-même `X-Partenaire: centre-concurrent`.
- HSTS d'un an posé avant les essais, ou avec `preload` sur un domaine interne.
- Un écouteur TLS *passthrough* et un écouteur HTTPS sur le même port de la même Gateway avec des noms qui se recouvrent : choix du chaînage selon le SNI difficile à prévoir (d'où une Gateway séparée).
- Certificat du relais en HTTP-01 : le nom pointe vers 10.10.41.11, que l'écouteur HTTP de `gw-par1` ne sert pas.

**En production chez MédiSphère**

Autorité des partenaires dans Vault PKI (M25) avec liste de révocation, CSR fournie par le partenaire, registre des partenaires, journal d'accès par partenaire envoyé vers Loki (M22), test d'intrusion de l'entrée après chaque mineure de Cilium.

---

### M15-E34 — Publier une nouvelle application en temps limité

**Solution de référence** (à lire **après** le chrono)

Fichiers : [`service.yaml`](fichiers/M15-E34/k8s/applications/medidoc-dev/service.yaml), [`httproute.yaml`](fichiers/M15-E34/k8s/applications/medidoc-dev/httproute.yaml), [`politiques.yaml`](fichiers/M15-E34/k8s/applications/medidoc-dev/politiques.yaml), [labels de l'espace](fichiers/M15-E34/k8s/espaces/medidoc-dev.extrait.yaml), [extrait du Taskfile](fichiers/M15-E34/k8s/Taskfile-medidoc-extrait.yml) (Secret S3 depuis le fichier local, ConfigMap de la racine, ordre d'application), [feuille de temps et retour d'expérience](fichiers/M15-E34/medisphere/docs/kubernetes/reseau/chrono/E34-medidoc.md). Le Deployment est celui du dossier, copié dans `applications/medidoc-dev/deployment.yaml` avec la version de l'image.

Déroulé efficace :
1. (T0 → T1) Labels de l'espace (`medisphere.internal/exposition: oui`, et `medisphere.internal/equipe: medidoc` déjà là depuis le M14-E33) ; politiques **d'abord** (refus par défaut + autorisations) ; Secret et ConfigMap par la tâche ; Deployment ; Service.
2. (T1 → T2) Route sur `gw-par1`, écouteur `https` : le joker `apps-joker` couvre le nom, aucun certificat à demander ; `kubectl -n medidoc-dev get httproute medidoc -o yaml` : `Accepted` et `ResolvedRefs` à `True` ; ExternalDNS publie en moins de 2 minutes (`dig @10.10.20.10` et `@10.10.20.16`).
3. (T2 → T3) `curl https://medidoc-dev.apps.par1.medisphere.internal/readyz` → 200 (le pod joint `s3-01` : sinon `/readyz` répond 503 et le pod n'est jamais prêt) ; dépôt et relecture d'un document de test ; `hubble observe -n medidoc-dev --verdict DROPPED` vide pour les flux légitimes.
4. (T3 → T4) Matrice des flux (lignes MédiDoc) et feuille de temps ; `lab/bin/check 15 34`.

**Pièges classiques**
- Oublier le label d'exposition : route `Accepted: False`, raison `NotAllowedByListeners`.
- Poser le refus par défaut **après** le Deployment : pendant quelques minutes, MédiDoc sort où il veut.
- Autoriser `s3-01` par l'adresse 10.10.20.14 sans le noter, ou ne pas autoriser du tout : `/readyz` à 503, aucune réplique prête, la Gateway répond 503.
- Créer le Secret S3 avec `--from-literal` (clés dans l'historique du shell) ou le versionner.
- Écrire l'enregistrement DNS à la main « pour gagner du temps » : ExternalDNS ne le possède pas (enregistrement TXT de propriété absent) et il restera orphelin.

**En production chez MédiSphère**

Un modèle d'application (route, politiques, en-têtes) dans `plateforme/k8s`, appliqué par GitOps (M20) ; un contrôle d'admission qui n'autorise que `<espace>.apps…` comme nom d'hôte dans un espace (M26) ; un catalogue en libre-service (M28) : l'équipe ouvre une MR, la plateforme publie.

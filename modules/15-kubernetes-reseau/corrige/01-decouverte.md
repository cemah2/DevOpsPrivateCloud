# Module 15 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé (E08 se **réalise** avant E07, voir l'introduction). Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `ansible/` celle de `plateforme/ansible`, `medisphere/` celle de la documentation, `manifestes/` les objets d'essai de `wb-essais` (à ranger dans `~/m15/eXX/`). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été vérifié à la rédaction** :
- les clés de *values* utilisées (`kubeProxyReplacement`, `kubeProxyReplacementHealthzBindAddr`, `k8sServiceHost`, `k8sServicePort`, `ipam.*`, `routingMode`, `tunnelProtocol`, `operator.replicas`, `gatewayAPI.enabled`, `l7Proxy`, `hubble.relay.enabled`, `hubble.ui.enabled`, `hubble.redact.*`, `rollOutCiliumPods`) dans le `values.yaml` du chart **1.20.2** ; les trois versions du fichier de *values* (E05, E08, E07) passent `helm template cilium/cilium --version 1.20.2 --kube-version 1.36.0` (schéma du chart compris), et la ConfigMap rendue contient les clés lues par les vérifications (`kube-proxy-replacement`, `kube-proxy-replacement-healthz-bind-address`, `enable-gateway-api`, `hubble-redact-*`, `routing-mode`, `tunnel-protocol`) ; avec la CRD `GatewayClass` présente, le chart rend la GatewayClass `cilium` ;
- la documentation de Cilium au tag v1.20.2 : prérequis de la Gateway API (**`kubeProxyReplacement=true` obligatoire**, `l7Proxy`, TPROXY par iptables tant que `bpf.tproxy=false`), liste des sept CRD exigées et version **v1.6.1** de Gateway API, exemple officiel de GatewayClass paramétrée en `NodePort` (`CiliumGatewayClassConfig` `cilium.io/v2alpha1`, `spec.service.type`), identité réservée `ingress` du trafic d'Envoy, procédure « Kubernetes Without kube-proxy » (suppression du DaemonSet et de la ConfigMap, `iptables-save | grep -v KUBE | iptables-restore`, avertissements sur les connexions rompues), notes de mise à jour 1.20 ;
- le code de l'opérateur (`gateway.go`) : les nœuds sont surveillés pour renseigner les adresses d'une Gateway dont le Service est en `NodePort` ;
- le code de kubeadm **1.36.5** : champ `ClusterConfiguration.proxy.disabled` (v1beta4) ; `kubeadm upgrade` saute la phase `addon/kube-proxy` quand il vaut `true` (« The addon is disabled ») et ne regarde **pas** si la ConfigMap `kube-proxy` existe ; `kubeadm init` relie `--skip-phases=addon/kube-proxy` et `proxy.disabled` (l'un implique l'autre) ; le champ `skipPhases` de `UpgradeConfiguration` est **ignoré** par `kubeadm upgrade apply` ; Corefile par défaut de kubeadm 1.36 (cache désactivé pour `cluster.local`) ; à la montée de version, un Corefile modifié est conservé ou migré, le Deployment `coredns` est réécrit ;
- les filtres de `hubble observe` (`--from-pod`, `--to-pod`, `--pod`, `--namespace`, `--verdict`, `--type`, `--port`, `--to-port`, `--protocol`, `--node-name`, `--to-label`, `--last`) dans le code de la CLI au tag v1.20.2 ;
- les CRD Gateway API v1.6.1 du canal standard (annotations `bundle-version` et `channel`, empreintes SHA-256 de `SHA256SUMS-v1.6.1`) ; le script `telecharger-crd.sh` a été exécuté et vérifie les empreintes ;
- les chemins de `agnhost netexec` (`/hostname`, `/clientip`, `/echo`, `/healthz`, `/readyz`, et les dangereux `/shell`, `/exit`) et l'étiquette 2.66.1 du registre `registry.k8s.io` ; l'étiquette `v0.16` de `nicolaka/netshoot` ;
- tous les manifestes passent `kubeconform -strict` (Kubernetes 1.36, schémas générés depuis les CRD Gateway API v1.6.1 et Cilium 1.20.2) et `yamllint` ; ce `kubeconform` a trouvé une description de GatewayClass trop longue (64 caractères au plus), corrigée ;
- les scripts (`telecharger-crd.sh`, `nettoyer-regles-kube-proxy.sh`, checks) passent `shellcheck -x` et `bash -n` ; les checks E04, E06 et E07 ont été exécutés contre des réponses simulées de l'API construites à partir des fichiers de solution (et E04 contre le Corefile par défaut de kubeadm, qui doit échouer).

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- tout ce qui suppose le cluster : l'environnement de rédaction n'avait pas de `k8s-par1` ; les sorties montrées sont **représentatives**, pas copiées ;
- l'état `Programmed: True` d'une Gateway dont le Service est en `NodePort` (le code renseigne ses adresses à partir des nœuds ; si ta Gateway reste `Programmed: False` avec un message d'adresse, signale-le : le check E07 l'exige) ;
- la raison exacte affichée par Hubble pour un Service sans pod (`Service backend not found` attendu) et celle de l'HTTPRoute dont le port est faux (`ResolvedRefs: False`, raison `BackendNotFound` ou proche) ;
- `cilium upgrade --reset-values` et l'option de simulation `--dry-run-helm-values` de la CLI `cilium` : présentes dans les versions récentes de la CLI, à confirmer par `cilium upgrade --help` ;
- `kubeadm upgrade apply <VERSION-ACTUELLE> --dry-run` : kubeadm peut refuser une « montée » vers la même version ; dans ce cas, la lecture de la ConfigMap et du code suffit (énoncé, étape 10) ;
- la réponse de Cilium 1.20 à un `ping` vers une ClusterIP (E01, question 15) ;
- la ligne *Host Routing* (attendue `Legacy` avant **et** après E08, faute de masquage eBPF) ;
- le décodage du port 8472 par `tcpdump` (affiché comme OTV par les versions de Debian 13, à vérifier).

---

### M15-E01 — Test de positionnement : réseau Kubernetes

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E02 ; les questions 1 à 8 sont mobilisées dès E02, 9 et 10 en E04, 14 à 18 en E03 et E06, 19 en E07, 20 en E08 et E44.

**Réponses argumentées — Linux et réseau**

**1. Espace de noms réseau.** Une instance séparée de la pile réseau du noyau : interfaces, adresses, tables de routage, règles de filtrage (iptables/nftables), table de suivi des connexions, sockets, `/proc/net`, ports. Il partage tout le reste avec le système : le noyau lui-même, ses modules, les programmes eBPF attachés, la mémoire. Un conteneur obtient « sa » carte quand le runtime (ici par le greffon CNI) crée une interface et la **déplace** dans l'espace du conteneur (`ip link set … netns …`), puis lui donne une adresse et des routes.

**2. Paire veth.** Deux interfaces virtuelles reliées comme par un câble : une trame émise par l'une sort par l'autre. Une extrémité est déplacée dans l'espace du pod (où elle devient `eth0`), l'autre reste sur l'hôte (`lxc…` chez Cilium) : c'est le seul lien entre le pod et le nœud. Depuis le pod, `ip -o link show eth0` affiche `eth0@ifNN` : `NN` est l'**index** de l'interface paire dans l'espace de l'hôte (`ip -o link | grep "^NN:"`). Autres moyens : `ethtool -S eth0` (champ `peer_ifindex`), ou `cilium-dbg endpoint list` qui donne directement l'interface.

**3. Réponse B.** Cilium (comme la plupart des CNI) **masque** derrière l'adresse du nœud ce qui sort de 10.240.0.0/16 vers une destination hors du cluster. A confond deux règles : le modèle interdit la traduction **entre pods**, pas vers l'extérieur ; `dns01` ne saurait d'ailleurs pas répondre à 10.240.1.15, que la bordure ne route pas. C est faux : la bordure ne fait de NAT que vers le WAN ; entre VLAN, elle route. D n'a pas de sens : CoreDNS n'est pas sur le chemin d'un `dig @10.10.20.10`.

**4. conntrack.** Le noyau enregistre chaque flux (5-uplet d'origine et 5-uplet de réponse attendu) et, s'il a été traduit, la traduction appliquée. Les paquets de réponse sont reconnus et **dé-traduits** grâce à cette entrée, sans repasser par les règles. Si la table est vidée en cours de connexion, la réponse du serveur n'est plus rattachée à rien : elle part avec l'adresse réelle du serveur au lieu de l'adresse que le client attend (le client l'ignore ou répond RST), ou elle crée une nouvelle entrée « au milieu » sans traduction. La connexion est rompue. C'est pour cela que basculer d'un plan de données de Services à un autre rompt les connexions établies (avertissement de Cilium, E08).

**5. DNAT et SNAT dans iptables.** DNAT : table `nat`, chaînes `PREROUTING` (paquets qui arrivent) et `OUTPUT` (paquets émis localement). SNAT/MASQUERADE : table `nat`, chaîne `POSTROUTING` (et `INPUT` pour le SNAT vers un processus local). Un processus de l'hôte émet ses paquets par `OUTPUT`, jamais par `PREROUTING` : c'est pourquoi kube-proxy accroche sa chaîne `KUBE-SERVICES` **aux deux** (sinon un processus du nœud ne pourrait pas joindre une ClusterIP).

**6. VXLAN.** Une trame Ethernet complète transportée dans de l'UDP : Ethernet externe (14 octets) + IP externe (20) + UDP (8) + en-tête VXLAN (8) = **50 octets** de plus par paquet (sans étiquette VLAN). Port standard IANA : 4789 ; port historique du noyau Linux : **8472** (celui de Cilium et de flannel par défaut). Le VNI (24 bits) identifie normalement un segment de niveau 2 ; Cilium s'en sert autrement (E02). Avec un réseau à 1500, les interfaces intérieures doivent être à **1450**.

**7. Réponse B.** C'est le « trou noir » de la découverte du MTU : la poignée de main TCP (petits paquets) passe, puis le premier gros segment est jeté sans que l'émetteur le sache (l'ICMP qui le lui dirait est filtré). A est faux (l'établissement passe), C aussi (le DNS en UDP fait souvent moins de 512 octets ; il souffre seulement des grosses réponses DNSSEC), D aussi (ce n'est pas un ralentissement, c'est un blocage). Panne M15-E42.

**8. Routage natif ou tunnel.** Natif : chaque nœud route les plages de pods des autres, et le réseau sous-jacent doit les connaître (routes annoncées en BGP, routes statiques, ou nœuds tous sur le même segment avec routes directes) ; avantages : pas de surcoût d'encapsulation ni de réduction du MTU, adresses de pods visibles sur le réseau (traçabilité) ; inconvénient : le réseau doit transporter et filtrer des plages de pods, le plan d'adressage en consomme. Tunnel : seul le joignabilité entre nœuds (et un port UDP) est exigée ; avantage : indépendant du réseau ; inconvénients : 50 octets et un peu de CPU par paquet, MTU réduit, trafic opaque pour les équipements du réseau. `k8s-par1` commence en tunnel ; M15-E29 compare.

**Réponses argumentées — DNS et répartition**

**9. `search` et `ndots`.** `search` : suffixes ajoutés aux noms « relatifs ». `ndots:N` : un nom qui contient **moins de N points** est d'abord essayé avec chaque suffixe, puis tel quel ; un nom qui en a N ou plus est essayé tel quel d'abord. `ca01.par1.medisphere.internal` a 3 points (< 5) : `ca01.par1.medisphere.internal.a.example`, puis `….b.example`, puis `ca01.par1.medisphere.internal` ; chaque essai en A **et** en AAAA (souvent en parallèle). Un nom terminé par un point (`ca01.par1.medisphere.internal.`) est absolu : une seule question par type.

**10. Boucle de résolution.** Un résolveur qui se transmet ses propres questions (directement ou par un tiers) les fait tourner jusqu'à épuisement (délai, `SERVFAIL`, saturation). Exemple classique dans Kubernetes : CoreDNS configuré en `forward . /etc/resolv.conf` sur un nœud dont `/etc/resolv.conf` pointe vers un résolveur local (`127.0.0.53` de systemd-resolved). Le pod CoreDNS reprend ce fichier, mais dans **son** espace réseau, `127.0.0.53` est sa propre interface de bouclage, où CoreDNS écoute lui-même sur le port 53 : il se transmet ses propres questions. Autre variante : un nœud dont le `resolv.conf` pointe vers la ClusterIP du DNS du cluster. Le greffon `loop` de CoreDNS envoie une question témoin au démarrage, la voit revenir, et **arrête** CoreDNS (pods en `CrashLoopBackOff`, message « Loop … detected »).

**11. L4 et L7.** L4 : voit adresses, ports, état TCP ; décide **par connexion** ; ne lit ni le nom d'hôte ni le chemin ; en TLS, il transmet sans déchiffrer (au mieux il lit le SNI). L7 : analyse la requête (méthode, en-têtes, chemin), décide **par requête**, peut réécrire, rediriger, réessayer, répartir par poids ; pour le HTTPS, il doit **terminer** le TLS (donc détenir le certificat et la clé), ou se contenter du SNI.

**12. Réponse B.** La traduction est faite à l'ouverture de la connexion ; toutes les requêtes d'une même connexion persistante vont au même serveur. A serait vrai pour 100 connexions, pas pour 100 requêtes ; C et D n'ont aucun fondement. Conséquence pratique : des clients à connexions longues (gRPC, HTTP/2, réserves de connexions) déséquilibrent un répartiteur L4 ; un répartiteur L7 (Envoy) répartit par requête.

**13. SNI.** Le client écrit le nom du serveur visé **en clair** dans son premier message TLS (`ClientHello`). Un répartiteur peut lire ce nom sans rien déchiffrer et choisir où envoyer tout le flux TCP (*TLS passthrough*) ; le certificat et la clé restent chez le serveur final. C'est ce que feront `lb01`/`lb02` vers la Gateway en M15-E20. (ECH, qui chiffre le `ClientHello`, change la donne ; peu déployé en interne.)

**Réponses argumentées — Kubernetes**

**14. Modèle réseau.** (1) Chaque pod a sa propre adresse ; (2) tout pod peut joindre tout pod, sur tous les nœuds, **sans NAT** ; (3) les agents d'un nœud peuvent joindre tous les pods de ce nœud. La règle (2) exclut le modèle Docker par défaut, où les conteneurs ont des adresses privées propres à chaque hôte et sortent masqués : un conteneur d'un autre hôte ne peut pas les joindre par leur adresse.

**15. ClusterIP.** Son adresse n'appartient à **aucune** interface : c'est une clé dans des règles (iptables) ou des tables (eBPF) qui traduisent « adresse du Service + port » vers « adresse d'un pod + port cible ». Un `ping` n'est traduit que si le plan de données le prévoit : avec kube-proxy en iptables, seuls les protocoles et ports déclarés sont traduits, l'ICMP n'a pas de destination et le `ping` reste sans réponse. Certains plans de données répondent eux-mêmes à l'ICMP vers une adresse de Service : vérifie sur Cilium 1.20 après E08 (et ne te sers jamais du `ping` pour tester un Service : `curl` ou `nc` sur le port).

**16. Endpoints et EndpointSlice.** Endpoints : l'ancien objet unique qui liste toutes les adresses d'un Service (lourd à mettre à jour pour un gros Service : chaque changement réécrit tout l'objet ; l'API est dépréciée depuis Kubernetes 1.33). EndpointSlice : des tranches d'au plus 100 adresses par défaut, avec pour chacune l'état (`ready`, `serving`, `terminating`), le nœud, la zone, la famille d'adresses. Un pod `Running` n'est pas dans les adresses **prêtes** si sa sonde de disponibilité échoue (ou pas encore réussi), s'il est en cours d'arrêt, ou si une *readiness gate* n'est pas satisfaite ; il n'y est pas du tout si ses labels ne correspondent pas au sélecteur.

**17. Types de Services.** `NodePort` : en plus de la ClusterIP, un port (30000-32767) ouvert sur **tous** les nœuds. `LoadBalancer` : en plus du NodePort (le plus souvent), une adresse externe attribuée par **un tiers** : un contrôleur de nuage public, ou chez soi MetalLB, le LB IPAM de Cilium (avec annonce BGP ou L2), kube-vip… Sans lui, l'adresse reste `<pending>` (E07). `externalIPs` : des adresses écrites à la main dans le Service, que le plan de données accepte ; c'est à l'administrateur de faire arriver le trafic, et n'importe qui pouvant créer un Service peut s'en servir pour détourner une adresse (CVE-2020-8554) : à interdire par admission.

**18. Réponse B.** La politique ne déclare (implicitement) que le type `Ingress` ; la sortie des pods `app=api` n'est pas concernée et reste libre. A est la confusion la plus fréquente : la mise en refus par défaut se fait **par direction déclarée**. C et D inventent des exceptions que l'API n'a pas (les **réponses** d'une connexion autorisée passent toujours, par le suivi de connexion, mais ce n'est pas ce que demande la question).

**19. Ingress et Gateway API.** Ingress : un seul objet, HTTP(S) seulement, correspondance par hôte et préfixe de chemin, tout le reste (réécriture, poids, en-têtes, délais) par **annotations** propres à chaque contrôleur, donc non portables ; pas de séparation entre ce que fixe la plateforme et ce qu'écrit l'équipe d'application. Gateway API : ressources **par rôle** (GatewayClass pour le fournisseur, Gateway pour l'équipe plateforme, routes pour les équipes d'application) avec des règles d'attachement explicites ; plusieurs protocoles (HTTP, gRPC, TLS, TCP/UDP) ; correspondances et filtres **typés** et standardisés (en-têtes, méthodes, paramètres, poids, redirections, réécritures) ; références entre espaces contrôlées (`ReferenceGrant`) ; états détaillés sur chaque objet ; tests de conformité par implémentation.

**20. eBPF.** Un mécanisme du noyau Linux qui exécute de petits programmes, chargés depuis l'espace utilisateur, à des points d'accroche (réception d'un paquet sur une interface, appel `connect()`, événement d'un cgroup…), avec des tables partagées entre noyau et espace utilisateur. Le vérificateur analyse chaque programme avant de l'accepter : terminaison garantie (boucles bornées), accès mémoire contrôlés, types des pointeurs, appels limités aux fonctions autorisées. Un programme accepté ne peut pas planter ni bloquer le noyau : c'est ce qui permet d'y mettre un plan de données sans écrire de module noyau.

---

### M15-E02 — Suivre un paquet de pod à pod

**Solution**

*A. Outiller.* [`ansible/playbooks/k8s-outils-diagnostic.yml`](fichiers/M15-E02/ansible/playbooks/k8s-outils-diagnostic.yml) : un module `apt` pour la liste, le service `iperf3` éventuel arrêté et désactivé, une vérification que les outils répondent, `serial: 1`. Un playbook à part plutôt qu'une tâche du rôle `k8s_noeud` : ces outils ne servent pas à faire tourner Kubernetes ; ils peuvent être retirés ou absents en production sans toucher au rôle qui construit les nœuds (et sans relancer ses tests Molecule) ; le jour où l'ADR-0150 dira « pas d'outil de capture sur les nœuds de production », on supprime un playbook. `iptables` y figure parce que le nettoyage de E08 et la lecture des règles de kube-proxy en ont besoin : le paquet Debian n'installe que les outils (backend nft par défaut), il n'ajoute aucune règle.

*B. Sondes.* [`manifestes/sondes.yaml`](fichiers/M15-E02/manifestes/sondes.yaml) : trois pods placés par `nodeSelector` sur `kubernetes.io/hostname`.

```
admin@adm01:~$ kubectl -n wb-essais get pods -l app.kubernetes.io/name=sonde -o wide
NAME         READY   STATUS    IP             NODE
sonde-w01a   1/1     Running   10.240.3.112   k8s-w01
sonde-w01b   1/1     Running   10.240.3.57    k8s-w01
sonde-w02    1/1     Running   10.240.4.201   k8s-w02
admin@adm01:~$ kubectl get ciliumnodes -o custom-columns=NOEUD:.metadata.name,PODS:.spec.ipam.podCIDRs
NOEUD      PODS
k8s-cp01   [10.240.0.0/24]
k8s-cp02   [10.240.1.0/24]
…
k8s-w01    [10.240.3.0/24]
k8s-w02    [10.240.4.0/24]
```

C'est l'**opérateur Cilium** qui découpe `clusterPoolIPv4PodCIDRList` (10.240.0.0/16) en tranches de `clusterPoolIPv4MaskSize` (/24, soit 254 adresses de pods par nœud, 256 nœuds au plus) et les écrit dans la ressource `CiliumNode` de chaque nœud ; l'agent attribue ensuite les adresses de sa tranche. Ce n'est **pas** le `podCIDR` de l'objet `Node` (celui du contrôleur de kube-controller-manager), qui n'est pas utilisé en mode `cluster-pool`.

*Dans le pod* (question 3) :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- ip route
default via 10.240.3.31 dev eth0 mtu 1450
10.240.3.31 dev eth0 scope link
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- ip -o link show eth0
14: eth0@if15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 …
```

La passerelle est l'adresse de `cilium_host` du nœud (le « routeur » de sa tranche). La route par défaut porte un **MTU de 1450** (l'interface reste à 1500) : Cilium règle le MTU par route pour tenir compte des 50 octets du tunnel. `eth0@if15` : l'interface paire est l'index 15 de l'espace de l'hôte.

*Sur le nœud* (question 4) :

```
admin@k8s-w01:~$ ip -o link | grep -E "^15:|cilium"
4: cilium_net@cilium_host: … mtu 1500 …
5: cilium_host@cilium_net: … mtu 1500 …
6: cilium_vxlan: … mtu 1500 …
15: lxc8d2f61a0c3b4@if14: … mtu 1500 …
admin@k8s-w01:~$ ip -d link show cilium_vxlan | grep vxlan
    vxlan external id 0 srcport 0 0 dstport 8472 nolearning ttl auto ageing 300 …
admin@k8s-w01:~$ ip route
default via 10.10.40.1 dev ens18 proto static
10.10.40.0/24 dev ens18 proto kernel scope link src 10.10.40.61
10.240.0.0/24 via 10.240.3.31 dev cilium_host proto kernel src 10.240.3.31 mtu 1450
10.240.1.0/24 via 10.240.3.31 dev cilium_host proto kernel src 10.240.3.31 mtu 1450
10.240.3.0/24 via 10.240.3.31 dev cilium_host proto kernel src 10.240.3.31
10.240.3.31 dev cilium_host proto kernel scope link
10.240.4.0/24 via 10.240.3.31 dev cilium_host proto kernel src 10.240.3.31 mtu 1450
…
```

Les tranches des autres nœuds sont routées vers `cilium_host`, avec un MTU de 1450 : la table de routage du nœud ne connaît **pas** le tunnel ; ce sont les programmes eBPF (attachés à `cilium_host` et aux `lxc…`) qui choisissent l'encapsulation et le nœud de destination. `cilium_vxlan` est en mode `external` (« collecte ») : pas de VNI ni de destination fixes, chaque paquet porte les siennes.

*L'agent* (question 5) :

```
admin@adm01:~$ CIL=$(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=k8s-w01 -o name)
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg endpoint list
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                         IPv6   IPv4           STATUS
           ENFORCEMENT        ENFORCEMENT
211        Disabled           Disabled          38712      k8s:app.kubernetes.io/name=sonde                           10.240.3.112   ready
                                                           k8s:app.kubernetes.io/part-of=m15
                                                           k8s:io.kubernetes.pod.namespace=wb-essais
                                                           …
1842       Disabled           Disabled          38712      (mêmes labels)                                             10.240.3.57    ready
…          …                  …                 1          reserved:host                                                             ready
…          …                  …                 4          reserved:health                                            10.240.3.140   ready
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg identity get 38712
```

Les deux sondes ont **la même identité** : l'identité est calculée à partir des labels de **sécurité** du pod (labels du pod, espace de noms, compte de service…), pas de son nom ni de son adresse. Deux pods aux mêmes labels sont interchangeables pour les politiques. `POLICY ENFORCEMENT: Disabled` : aucune politique ne les sélectionne encore (E06 le changera).

*C. Même nœud* (question 6) : capture sur `lxc…` de `sonde-w01b`, `ping` depuis `sonde-w01a`. Rien sur `ens18`. Le programme de sortie de `lxc…` de `sonde-w01a` trouve la destination dans la table des points de terminaison **locaux** et redirige le paquet vers l'interface de `sonde-w01b`. *Host Routing* : `Legacy` (état du module 14) ; dans ce mode, la capture sur `lxc…` de la destination voit le paquet. Avec le routage d'hôte eBPF, le paquet serait remis directement dans l'espace de noms du pod (`bpf_redirect_peer`) et la capture côté nœud ne verrait pas l'entrée.

*D. Deux nœuds* (questions 7 à 9) :

```
admin@k8s-w01:~$ sudo tcpdump -ni ens18 -c 6 udp port 8472
IP 10.10.40.61.53812 > 10.10.40.62.8472: OTV, flags [I] (0x08), overlay 0, instance 38712
IP 10.240.3.112 > 10.240.4.201: ICMP echo request, id 7, seq 1, length 64
IP 10.10.40.62.41275 > 10.10.40.61.8472: OTV, flags [I] (0x08), overlay 0, instance 38712
IP 10.240.4.201 > 10.240.3.112: ICMP echo reply, id 7, seq 1, length 64
```

`tcpdump` décode le port 8472 comme **OTV** (un autre protocole qui utilise ce port) : la « *instance* » affichée est le VNI. En-tête externe : 10.10.40.61 → 10.10.40.62, UDP vers 8472 (port source variable : il sert à répartir les flux sur des liens agrégés) ; en-tête interne : les adresses des **pods**, sans aucune traduction. Pour un décodage VXLAN explicite : `tcpdump -ni ens18 -T vxlan udp port 8472` (option à vérifier dans ta version de `tcpdump`).

Le VNI vaut **38712** : l'identité de `sonde-w01a` (`cilium-dbg identity get 38712`). Cilium transporte l'**identité de sécurité de la source** dans l'en-tête du tunnel : le nœud d'arrivée applique la politique d'entrée de `sonde-w02` sans avoir à déduire l'émetteur de son adresse. Dans le sens retour, le VNI est l'identité de `sonde-w02` (ici la même, puisque les trois sondes ont les mêmes labels : vérifie avec un autre pod).

```
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg bpf ipcache get 10.240.4.201
10.240.4.201 maps to identity identity=38712 encryptkey=0 tunnelendpoint=10.10.40.62 flags=<none>
```

L'**ipcache** (table eBPF alimentée par l'agent à partir des ressources `CiliumEndpoint` et `CiliumNode` de tout le cluster) associe chaque adresse de pod à son identité et à l'adresse du nœud qui l'héberge : c'est là que `k8s-w01` trouve à qui envoyer le paquet.

*MTU* (question 10) :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- ping -c 1 -M do -s 1422 10.240.4.201
1430 bytes from 10.240.4.201: icmp_seq=1 ttl=63 time=0.61 ms
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- ping -c 1 -M do -s 1423 10.240.4.201
ping: local error: message too long, mtu=1450
```

1422 octets de données + 8 (ICMP) + 20 (IP) = 1450, le MTU de la route du pod ; + 50 octets VXLAN = 1500 sur `ens18`. Le refus est **local** (le noyau du pod connaît le MTU de sa route) : c'est le bon comportement. Si le MTU de la route était faux (1500), le paquet partirait et serait perdu plus loin.

*E. Sortie* (question 11) :

```
admin@k8s-w01:~$ sudo tcpdump -ni ens18 -c 2 port 53 and host 10.10.20.10
IP 10.10.40.61.47121 > 10.10.20.10.53: 51234+ [1au] A? git01.par1.medisphere.internal. (59)
IP 10.10.20.10.53 > 10.10.40.61.47121: 51234* 1/0/1 A 10.10.20.12 (75)
```

L'adresse source est celle du **nœud** : Cilium masque (SNAT) ce qui sort du réseau des pods vers l'extérieur du cluster (à ce stade par une règle iptables qu'il installe lui-même ; `cilium-dbg status --verbose`, ligne *Masquerading*). Conséquence pour la bordure : la matrice des flux raisonne en **nœuds** (10.10.40.0/24), jamais en pods ; et `dns01` ne peut pas distinguer deux pods d'un même nœud dans ses journaux.

*F. Fiche* : [`medisphere/docs/kubernetes/reseau/chemin-paquet.md`](fichiers/M15-E02/medisphere/docs/kubernetes/reseau/chemin-paquet.md).

Le check vérifie les sondes (nœud, adresse, deux /24 différents), les tranches de chaque nœud dans `CiliumNode`, le mode tunnel VXLAN (ConfigMap et `cilium_vxlan` en 8472 sur `k8s-w01`), les outils sur les six nœuds, le playbook et la fiche sur `main`.

**Explications**

- **Pourquoi le nœud n'a pas de route « par le tunnel ».** En tunnel, Cilium garde la table de routage du nœud simple (tout vers `cilium_host`) et fait la décision dans les programmes eBPF : ils lisent l'ipcache, encapsulent et envoient. C'est pour cela que `ip route get 10.240.4.201` sur le nœud est trompeur : il dit `cilium_host`, pas « vers 10.10.40.62 ».
- **L'identité dans le VNI.** C'est un choix de Cilium, pas une propriété de VXLAN : le VNI est un champ de 24 bits que le récepteur lit de toute façon. En routage natif (sans en-tête de tunnel), le nœud d'arrivée retrouve l'identité de la source dans son propre ipcache à partir de l'adresse source ; d'où l'importance que l'ipcache soit à jour partout.
- **Le masquage n'est pas une règle Kubernetes.** C'est une décision du CNI (`enable-ipv4-masquerade`), indispensable ici parce que la bordure ne connaît pas 10.240.0.0/16. En routage natif avec annonce des plages de pods, on pourrait s'en passer (et voir les pods dans les journaux de `dns01`).

**Alternatives**

- **`kubectl debug node/k8s-w01`** pour capturer sans installer `tcpdump` sur le nœud : le conteneur de débogage partage l'espace réseau du nœud. Mais il crée un pod `hostNetwork` (refusé par la PSA `baseline` de `wb-essais` : il faudrait un espace dédié en `privileged`) et tire une image ; l'installation par Ansible est plus simple et traçable.
- **`cilium-dbg monitor`** dans l'agent (Pour aller plus loin) : il montre les événements du plan de données eBPF (`trace`, `drop`, `policy-verdict`) sans capture ; c'est souvent plus parlant que `tcpdump` pour savoir **où** un paquet a été arrêté.
- **`pwru`** (*packet, where are you?*, projet Cilium) suit un paquet fonction par fonction dans le noyau : outil d'expert, hors du cours.

**Pièges classiques**

- Capturer sur `cilium_vxlan` en s'attendant à voir l'en-tête VXLAN : cette interface voit les trames **avant** encapsulation (ou après décapsulation). L'en-tête externe se voit sur `ens18`.
- Lire `ip route` du nœud et conclure que le trafic inter-nœuds passe par `cilium_host` « et puis c'est tout » : sans l'ipcache, on ne comprend pas le chemin.
- Prendre l'« OTV » de `tcpdump` pour un problème : c'est seulement le nom que `tcpdump` donne au port 8472.
- Oublier que le MTU est porté par la **route** du pod, pas par l'interface : `ip link` dans le pod affiche 1500, `ip route` affiche 1450.
- Chercher l'interface d'un pod par son nom (`lxc` + empreinte du nom) : passe par l'index `@ifNN` ou par `cilium-dbg endpoint list`.

**En production chez MédiSphère**

La fiche `chemin-paquet.md` est la première page du runbook RB-150 (M15-E22) : chaque incident réseau commence par situer le paquet (même nœud, autre nœud, sortie). Les outils de capture sur les nœuds sont un écart à la règle « pas d'outil inutile en production » ; il est assumé, consigné dans l'ADR-0150, et les captures ne sont faites que par l'astreinte (journal de diagnostic), jamais conservées au-delà de l'incident : une capture sur un nœud de production contient potentiellement des données de santé.

---

### M15-E03 — Services : ClusterIP, NodePort, headless et EndpointSlices

**Solution**

[`manifestes/echo.yaml`](fichiers/M15-E03/manifestes/echo.yaml) : Deployment (3 réplicas, tolérance du taint `dedie=bdd` de `k8s-w03`, `topologySpreadConstraints` avec `nodeTaintsPolicy: Honor`, sondes `/readyz` et `/healthz`) et les quatre Services dans leur état final.

*A. EndpointSlices* (questions 1 et 2) :

```
admin@adm01:~$ kubectl -n wb-essais get endpointslices -l kubernetes.io/service-name=echo -o yaml
…
addressType: IPv4
endpoints:
- addresses: [10.240.3.88]
  conditions: {ready: true, serving: true, terminating: false}
  nodeName: k8s-w01
  targetRef: {kind: Pod, name: echo-6c9f7d5b8-4xk2p, namespace: wb-essais}
  zone: par1-baie-a
- …
ports:
- name: http
  port: 8080
  protocol: TCP
```

L'adresse, le nœud (`nodeName`), la zone (`zone`, issue du label `topology.kubernetes.io/zone` posé au M14-E14) et l'état (`conditions`) de chaque pod ; le port est celui du **pod** (8080). C'est le contrôleur d'EndpointSlices de `kube-controller-manager` qui l'écrit, à partir du sélecteur du Service et de l'état des pods. kube-proxy et Cilium ne lisent que les EndpointSlices (et non les pods).

*Répartition* (question 3) : `for i in $(seq 20); do curl -s http://echo/hostname; echo; done | sort | uniq -c` : à peu près 7/7/6 sur les trois pods (chaque `curl` est une nouvelle connexion, donc un nouveau tirage).

*Déploiement* (question 4) : pendant un `rollout restart`, l'EndpointSlice voit passer les nouveaux pods en `ready: false` (démarrage) puis `true`, et les anciens en `terminating: true`, `ready: false`, `serving: true` puis disparaître. Avec la sonde cassée : les nouveaux pods sont `Running` mais pas `Ready`, restent `ready: false` dans l'EndpointSlice et ne reçoivent **aucun** trafic ; le déploiement s'arrête (stratégie par défaut : `maxUnavailable: 25 %`, arrondi à 0 sur 3 réplicas, `maxSurge: 25 %` arrondi à 1) et les anciens pods continuent de servir. `kubectl rollout undo` rétablit.

**Réponse au point « un »** : les « connexion refusée » d'un déploiement viennent de pods qui reçoivent du trafic alors qu'ils ne savent pas (encore ou plus) le traiter : pas de sonde de disponibilité (le pod est annoncé dès que le conteneur démarre), ou un arrêt brutal : le pod reçoit SIGTERM **en même temps** que son retrait des EndpointSlices se propage aux nœuds ; s'il ferme sa socket tout de suite, les connexions qui arrivent encore pendant ces quelques centaines de millisecondes sont refusées. Remèdes : sonde de disponibilité, arrêt progressif dans l'application (MédiAgenda attend 20 s sur SIGTERM), éventuellement un `preStop` qui attend quelques secondes, et `maxUnavailable: 0`.

*B. Affinité* (question 5) : avec `sessionAffinity: ClientIP`, les 20 appels de `sonde-w01a` vont au **même** pod ; ceux de `sonde-w02` vont à un pod (peut-être un autre). L'affinité est par **adresse source** : entre pods, il n'y a pas de masquage, chaque pod est un client distinct ; mais derrière un répartiteur, un NAT ou un NodePort en `externalTrafficPolicy: Cluster` (adresse du nœud), des clients différents ont la même adresse et tombent tous sur le même pod. Pour la visio de Julien, une affinité L4 par adresse est fragile (téléphones qui changent de réseau) : une affinité applicative (cookie, en-tête) au niveau de la Gateway est plus juste.

*C. NodePort* (questions 6 et 7) :

```
admin@adm01:~$ curl -s http://10.10.40.61:30880/clientip; echo
10.10.40.61:39612
admin@adm01:~$ curl -s http://10.10.40.51:30880/hostname; echo
echo-6c9f7d5b8-r7wq2
```

En `externalTrafficPolicy: Cluster` (défaut), le nœud qui reçoit peut choisir un pod d'un **autre** nœud ; il doit alors masquer l'adresse source derrière la sienne, sinon la réponse du pod partirait directement vers `adm01`, qui l'ignorerait (asymétrie). Le pod voit donc l'adresse d'un nœud. Un nœud de contrôle sans pod `echo` sert quand même le NodePort.

Après passage en `Local` :

```
admin@adm01:~$ curl -s http://10.10.40.61:30880/clientip; echo
10.10.10.10:52004
admin@adm01:~$ curl -s -m 3 http://10.10.40.51:30880/hostname; echo $?
28
```

Le nœud n'envoie qu'à ses **propres** pods : pas de second saut, pas de masquage, le pod voit `adm01`. Un nœud sans pod ne sert pas le NodePort (délai dépassé ou refus). Avantage : adresse du client conservée (journaux, politiques par adresse, E06), un saut de moins. Piège : un répartiteur qui envoie à tous les nœuds perd les requêtes des nœuds sans pod, et la répartition suit le nombre de pods **par nœud**, pas par pod ; il faut que le répartiteur interroge la santé de chaque nœud (port 10256, E08). C'est le réglage des Gateway quand l'adresse source compte (M15-E25).

*D. internalTrafficPolicy et headless* (questions 8 et 9) : `echo-local` depuis `sonde-w01a` répond toujours avec le pod de `k8s-w01`, depuis `sonde-w02` avec celui de `k8s-w02`. Depuis un nœud sans pod `echo`, la connexion échoue : `Local` **ne se replie pas** sur les autres nœuds (usage : un agent par nœud, comme un collecteur de journaux en DaemonSet).

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +short echo.wb-essais.svc.cluster.local
10.96.141.27
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +short echo-sans-tete.wb-essais.svc.cluster.local
10.240.3.88
10.240.4.19
10.240.5.203
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +short SRV _http._tcp.echo-sans-tete.wb-essais.svc.cluster.local
0 33 8080 10-240-3-88.echo-sans-tete.wb-essais.svc.cluster.local.
…
```

**Réponse au point « trois »** : un Service *headless* n'a pas d'adresse virtuelle ; le DNS rend directement les adresses des pods prêts, et c'est le **client** qui choisit (et qui doit gérer la liste). Usage : des membres qui doivent se joindre **chacun** par son nom (StatefulSet avec `serviceName` : `postgres-0.postgres.<espace>.svc.cluster.local`), des clients qui font leur propre répartition (pilotes de bases réparties, gRPC côté client). Pour la base de MédiAgenda, c'est ce qu'utilisera l'opérateur PostgreSQL au module 16, avec en plus des Services « lecture-écriture » classiques.

*E. Sous le capot* (questions 10 et 11) :

```
admin@adm01:~$ KP=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy --field-selector spec.nodeName=k8s-w01 -o name)
admin@k8s-w01:~$ sudo iptables-save -t nat | grep -E "wb-essais/echo:http" | head
-A KUBE-SERVICES -d 10.96.141.27/32 -p tcp -m comment --comment "wb-essais/echo:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-QZB3…
-A KUBE-SVC-QZB3… ! -s 10.240.0.0/16 -d 10.96.141.27/32 -p tcp … -j KUBE-MARK-MASQ
-A KUBE-SVC-QZB3… -m comment --comment "wb-essais/echo:http -> 10.240.3.88:8080" -m recent --name KUBE-SEP-5LQ… --mask 255.255.255.255 --rsource --rcheck --seconds 300 --reap -j KUBE-SEP-5LQ…
…
-A KUBE-SVC-QZB3… -m comment --comment "wb-essais/echo:http -> 10.240.3.88:8080" -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-5LQ…
-A KUBE-SVC-QZB3… -m comment --comment "wb-essais/echo:http -> 10.240.4.19:8080" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-H2D…
-A KUBE-SVC-QZB3… -m comment --comment "wb-essais/echo:http -> 10.240.5.203:8080" -j KUBE-SEP-TY7…
-A KUBE-SEP-5LQ… -s 10.240.3.88/32 -j KUBE-MARK-MASQ
-A KUBE-SEP-5LQ… -p tcp -m recent --set --name KUBE-SEP-5LQ… --rsource -m tcp -j DNAT --to-destination 10.240.3.88:8080
admin@k8s-w01:~$ sudo iptables-save -t nat | wc -l
412
```

(Si `iptables-save` manque sur le nœud, lis les règles depuis le pod kube-proxy du nœud : `kubectl -n kube-system exec $KP -- iptables-save -t nat`.) Le choix entre trois pods : un tirage en cascade (1/3, puis 1/2 du reste, puis le dernier) ; l'affinité ajoute des règles `recent` qui renvoient un client connu vers le même pod pendant 300 s. Chaque Service coûte une entrée dans `KUBE-SERVICES` (parcourue **séquentiellement** pour chaque nouvelle connexion) et quelques règles par pod.

```
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg service list | grep -A3 10.96.141.27
42   10.96.141.27:80/TCP     ClusterIP      1 => 10.240.3.88:8080/TCP (active)
                                            2 => 10.240.4.19:8080/TCP (active)
                                            3 => 10.240.5.203:8080/TCP (active)
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg status --verbose | sed -n '/KubeProxyReplacement Details/,/^[A-Z]/p'
```

Cilium connaît déjà les **ClusterIP** (et aucun NodePort) : avec `kubeProxyReplacement: false`, il traduit par paquet, en eBPF, les ClusterIP pour le trafic **des pods** (documentation : « only enables per-packet in-cluster load-balancing of ClusterIP services »). Aujourd'hui, les deux traduisent : Cilium pour les pods vers les ClusterIP (le paquet arrive déjà traduit dans le noyau, les règles de kube-proxy ne voient qu'une adresse de pod), kube-proxy pour les NodePort et pour les processus des nœuds. C'est exactement la redondance que E08 supprime.

Le check vérifie le Deployment (3 prêts, sonde de disponibilité, un pod par travailleur), les quatre Services et leurs réglages, l'EndpointSlice (3 adresses prêtes, nœuds, port 8080), et depuis `adm01` le NodePort sur chaque travailleur, l'adresse source conservée et le refus sur un nœud de contrôle.

**Explications**

- **Sélecteur → EndpointSlice → plan de données.** Le Service ne « contient » pas de pods : un contrôleur écrit la liste des adresses, et chaque nœud la traduit en règles ou en tables. Une panne de Service se diagnostique dans cet ordre (RB-150) : le sélecteur trouve-t-il des pods, ces pods sont-ils prêts, l'EndpointSlice les liste-t-il, le nœud a-t-il les bonnes entrées (`cilium-dbg service list`), la politique laisse-t-elle passer ?
- **Pourquoi `targetPort: http`.** Le port nommé suit le conteneur : si l'application change de port, le Service suit sans modification. Les politiques, elles, voient le **numéro** (E06).
- **`trafficDistribution`** (Pour aller plus loin) : préférence de proximité (zone) **avec** repli, là où `internalTrafficPolicy: Local` est une contrainte stricte sans repli.

**Alternatives**

- Affinité de session par **cookie** à la Gateway (Envoy) plutôt que par adresse au Service : plus juste pour des clients mobiles ; à voir avec la Gateway principale (M15-E16, filtres et politiques de la Gateway).
- Mode **nftables** de kube-proxy (GA depuis 1.33) : tables d'adresses (`map`) au lieu de listes, mises à jour incrémentales ; c'est le successeur d'iptables pour qui garde kube-proxy. MédiSphère choisit de ne garder aucun des deux (E08).

**Pièges classiques**

- Tester un Service avec `ping` (aucune réponse, quel que soit l'état du Service).
- Confondre `port`, `targetPort` et `nodePort` ; écrire le port du Service dans une NetworkPolicy (E06).
- Un Service dont le sélecteur a une faute de frappe : il existe, a une ClusterIP, et n'a **aucune** adresse dans son EndpointSlice ; les clients reçoivent un refus immédiat. Toujours regarder l'EndpointSlice (panne M15-E35).
- `externalTrafficPolicy: Local` derrière un répartiteur qui ne teste pas la santé des nœuds : une partie des requêtes se perd.
- Oublier le taint de `k8s-w03` : la contrainte de répartition ne peut pas être satisfaite, le troisième pod reste `Pending` (« didn't match pod topology spread constraints »).
- L'image `agnhost netexec` expose `/shell` : à ne jamais publier (la route de E07 ne laisse passer que deux chemins exacts).

**En production chez MédiSphère**

Chaque Service applicatif a une sonde de disponibilité honnête (MédiAgenda : `/pret` vérifie PostgreSQL et Valkey) ; les déploiements sont en `maxUnavailable: 0` avec un arrêt progressif ; les PDB protègent les évictions (M14-E16). Les Services exposés sont en `externalTrafficPolicy: Local` derrière la Gateway quand l'adresse du client compte (journaux, politiques), avec des répartiteurs qui testent la santé des nœuds. Les réponses à DEV-1603 deviennent la section « Service » de RB-150.

---

### M15-E04 — CoreDNS : résolution interne et DNS de MédiSphère

**Solution**

*A. Lire* (questions 1 et 2). Le Corefile de kubeadm 1.36 :

| Greffon | Rôle |
|---|---|
| `errors` | journalise les erreurs (réponses `SERVFAIL`, échecs de transfert) |
| `health { lameduck 5s }` | `/health` sur 8080 ; à l'arrêt, continue de répondre 5 s pour laisser le temps au retrait du Service |
| `ready` | `/ready` sur 8181 : prêt quand tous les greffons le sont (sonde de disponibilité du pod) |
| `kubernetes cluster.local in-addr.arpa ip6.arpa` | répond pour les Services et les pods à partir de l'API ; `pods insecure` : répond pour `a-b-c-d.<espace>.pod.cluster.local` sans vérifier qu'un pod porte l'adresse (compatibilité kube-dns) ; `fallthrough in-addr.arpa ip6.arpa` : une question inverse qu'il ne connaît pas passe au greffon suivant (`forward`) au lieu de `NXDOMAIN` ; `ttl 30` |
| `prometheus :9153` | métriques |
| `forward . /etc/resolv.conf` | tout ce qui n'est pas traité est transmis aux résolveurs du `resolv.conf` **du pod CoreDNS**, c'est-à-dire du nœud (`dnsPolicy: Default`) |
| `cache 30 { disable success cluster.local; disable denial cluster.local }` | cache de 30 s, **sauf** pour `cluster.local` (ajout récent de kubeadm : une réponse sur un Service reflète l'API immédiatement) |
| `loop` | détecte une boucle de transfert et arrête CoreDNS |
| `reload` | relit le Corefile quand il change |
| `loadbalance` | mélange l'ordre des enregistrements A/AAAA d'une réponse |

`/etc/resolv.conf` d'une sonde :

```
search wb-essais.svc.cluster.local svc.cluster.local cluster.local par1.medisphere.internal
nameserver 10.96.0.10
options ndots:5
```

Les trois premiers suffixes viennent du kubelet (`<espace>.svc.<domaine>`, `svc.<domaine>`, `<domaine>`), le dernier du `resolv.conf` du nœud. `ndots:5` : choisi par Kubernetes pour que `service.espace.svc` (deux points) se résolve en nom relatif.

*B. Ce que CoreDNS répond* (questions 3 et 4). `echo` se résout depuis `wb-essais` seulement (suffixe `wb-essais.svc.cluster.local`) ; `echo.wb-essais` et le nom complet depuis n'importe quel espace ; `kubernetes.default` → 10.96.0.1 ; `10-240-3-112.wb-essais.pod.cluster.local` → 10.240.3.112 ; SRV `_http._tcp.echo.wb-essais.svc.cluster.local` → `0 100 80 echo.wb-essais.svc.cluster.local.`.

Coût de `ndots` (capture sur `lxc…` de `sonde-w01a`, port 53) :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +search +showsearch ca01.par1.medisphere.internal | grep -E "^;; (QUESTION|->>)|status"
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN …   ← ca01.par1.medisphere.internal.wb-essais.svc.cluster.local
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN …   ← ….svc.cluster.local
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN …   ← ….cluster.local
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN …   ← ….par1.medisphere.internal
;; ->>HEADER<<- opcode: QUERY, status: NOERROR …    ← ca01.par1.medisphere.internal
```

Le `curl` (résolveur de la glibc) pose **cinq** questions A et **cinq** AAAA, soit dix questions et quatre allers-retours inutiles par type avant la bonne réponse ; trois d'entre elles sont traitées par CoreDNS lui-même (`cluster.local`), la quatrième part jusqu'à `dns01` (`….par1.medisphere.internal.par1.medisphere.internal`, `NXDOMAIN` signé). Avec le nom terminé par un point : une seule question par type. **Réponse à Julien** : la demi-seconde au démarrage, c'est cette cascade (multipliée par chaque nom externe, sans cache côté client) ; remède : noms complets avec point final dans la configuration de MédiAgenda (`MEDIAGENDA_DB_URL`, URL de `ca01`), ou `ndots` réduit pour ce pod.

*C. Régler un pod* (questions 5 et 6). [`manifestes/sonde-ndots.yaml`](fichiers/M15-E04/manifestes/sonde-ndots.yaml) : avec `ndots:2`, `ca01.par1.medisphere.internal` (3 points ≥ 2) part tel quel d'abord : une question par type. Perte : `echo.wb-essais` (1 point < 2) se résout toujours par les suffixes, mais `postgres.mediagenda-dev.svc` (2 points) part d'abord tel quel vers Internet, échoue, puis se résout par les suffixes : un nom court de Service à deux points coûte désormais un aller-retour vers `dns01`. On règle `ndots` **par pod**, pour une application qui appelle surtout des noms externes et dont on maîtrise les noms internes ; jamais pour tout le cluster : on casserait (ou ralentirait) les noms relatifs de toutes les équipes.

Un pod `hostNetwork` sans `dnsPolicy` explicite reçoit `ClusterFirst`, que le kubelet traite comme **`Default`** (le `resolv.conf` du nœud) : les agents Cilium (DaemonSet en `hostNetwork`, sans `dnsPolicy` dans le chart 1.20) résolvent donc `k8s-api.par1.medisphere.internal` par `dns01`/`dns02`, sans dépendre de CoreDNS ni des Services : c'est voulu (un agent qui démarre ne sait pas encore traduire 10.96.0.10).

*D. Raccorder* (questions 7 à 11). Le `resolv.conf` du nœud :

```
admin@k8s-w01:~$ cat /etc/resolv.conf
search par1.medisphere.internal
nameserver 10.10.20.10
nameserver 10.10.20.16
```

Aujourd'hui, CoreDNS transmet donc déjà à `dns01`/`dns02`… **par hasard** : parce que l'image dorée et cloud-init l'ont écrit ainsi. Si une future image active systemd-resolved, le `resolv.conf` du nœud devient `nameserver 127.0.0.53` ; dans l'espace réseau du pod CoreDNS, 127.0.0.53 est l'interface de bouclage du pod, où CoreDNS écoute lui-même : il boucle, et `loop` l'arrête (« Loop (127.0.0.1:…) -> :53 detected for zone "." »). kubeadm prévient ce cas en réglant le kubelet sur `/run/systemd/resolve/resolv.conf` quand il détecte systemd-resolved, mais seulement à l'installation du nœud. D'où l'exigence d'adresses explicites, indépendantes des nœuds.

[`k8s/composants/coredns/configmap-coredns.yaml`](fichiers/M15-E04/k8s/composants/coredns/configmap-coredns.yaml) : bloc `medisphere.internal:53` (erreurs, métriques, cache, transfert séquentiel vers `dns01` puis `dns02`) et bloc général identique à celui de kubeadm sauf le `forward`. `policy sequential` : toujours `dns01` d'abord, `dns02` si `dns01` est marqué en panne par le contrôle de santé intégré (par défaut toutes les 0,5 s) ; le cache de `dns01` est mieux utilisé qu'avec un tirage aléatoire. `random` (défaut) est aussi défendable : charge partagée, chaque récurseur a son cache.

```
admin@adm01:~$ kubectl -n kube-system get configmap coredns -o yaml > ~/m15/e04/coredns-avant.yaml
admin@adm01:~/src/k8s$ kubectl apply --server-side --force-conflicts --field-manager=plateforme-k8s \
    -f composants/coredns/configmap-coredns.yaml
configmap/coredns serverside-applied
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=5
[INFO] Reloading
[INFO] plugin/reload: Running configuration SHA512 = 4c1f…
[INFO] Reloading complete
```

Sans `--force-conflicts`, l'application côté serveur refuse : le champ `data.Corefile` appartient au gestionnaire de champs de kubeadm, et `--force-conflicts` en transfère la propriété à `plateforme-k8s`, ce qui est voulu. (Un `kubectl apply` classique marche aussi, avec un avertissement sur l'annotation `last-applied-configuration` manquante.) Si ton `Taskfile.yml` du module 14 applique déjà `composants/*`, ajoute la ConfigMap à la tâche plutôt que de lancer la commande à la main. La prise en compte demande jusqu'à une minute ou deux (propagation du volume de la ConfigMap, puis vérification de `reload`).

Tests :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +short git01.par1.medisphere.internal
10.10.20.12
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig par1.medisphere.internal SOA | grep -E "flags|SOA"
;; flags: qr rd ra ad; …
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig +short deb.debian.org
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- dig nexistepas.par1.medisphere.internal | grep status
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN …
```

Le drapeau `ad` (données validées) vient du récurseur, qui valide DNSSEC pour `par1` ; CoreDNS le transmet tel quel.

*Montées de version* (question 11) : dans le code de kubeadm (`phases/addons/dns`), un Corefile **par défaut** est remplacé par le nouveau défaut ; un Corefile **modifié** est migré s'il le faut (outil `corefile-migration`) ou **conservé** ; le Deployment `coredns`, lui, est réécrit (nombre de réplicas, ressources, image). À ajouter à RB-142 : après `kubeadm upgrade apply`, `lab/bin/check 15 04` (le Corefile du cluster doit être identique à celui du dépôt) et vérification du nombre de réplicas de CoreDNS.

*E. Fiche* : [`medisphere/docs/kubernetes/reseau/dns-du-cluster.md`](fichiers/M15-E04/medisphere/docs/kubernetes/reseau/dns-du-cluster.md).

Le check vérifie le Corefile du cluster (bloc général vers les deux récurseurs sans `/etc/resolv.conf`, greffons de kubeadm conservés, bloc `medisphere.internal:53` distinct), son identité avec le fichier du dépôt (commentaires et espaces ignorés), CoreDNS (2 réplicas prêts, `kube-dns` en 10.96.0.10), `sonde-ndots` et la fiche.

**Explications**

- **Blocs de serveur.** Une question va au bloc dont la zone est la plus longue qui correspond : `git01.par1.medisphere.internal` va au bloc `medisphere.internal`, `echo.wb-essais.svc.cluster.local` et `deb.debian.org` au bloc `.`. Avoir un bloc à part pour nos noms permet d'y mettre des réglages propres (cache, journalisation), et garantit qu'ils partent toujours vers nos récurseurs, même si un jour le bloc général transmet ailleurs.
- **Pourquoi pas directement l'autoritaire.** CoreDNS transmet aux **récurseurs** (port 53), qui valident DNSSEC et ont l'ancre de `par1` ; l'autoritaire (5300) n'est jamais exposé au cluster.

**Alternatives**

- **NodeLocal DNSCache** : un cache DNS sur chaque nœud, qui absorbe la cascade `ndots` et protège CoreDNS ; avec Cilium et sans kube-proxy, il s'installe avec une `CiliumLocalRedirectPolicy`. Pas nécessaire à notre échelle ; à reconsidérer si les métriques de CoreDNS (M21) montrent une charge.
- **`autopath`** de CoreDNS : CoreDNS devine le suffixe de recherche du client et répond directement au bon nom ; exige `pods verified` (plus de mémoire, CoreDNS surveille tous les pods). Non retenu.

**Pièges classiques**

- Modifier la ConfigMap avec `kubectl edit` : la prochaine application depuis le dépôt écrase la modification, ou l'inverse ; le dépôt est la seule source.
- Oublier `loop` ou `reload` en réécrivant le Corefile : plus de détection de boucle, ou plus de prise en compte sans redémarrage.
- Mettre `ndots:1` sur tout le cluster pour « accélérer » : les noms courts de Services d'un autre espace partent sur Internet.
- Croire que la modification est immédiate : attendre la ligne `Reloading complete` dans les journaux avant de tester.
- Une politique réseau qui autorise UDP 53 mais pas TCP 53 : les grosses réponses (DNSSEC, nombreux enregistrements) échouent par intermittence (E06, M15-E36).

**En production chez MédiSphère**

CoreDNS est un composant de plateforme comme les autres : Corefile dans `plateforme/k8s`, appliqué par `task`, contrôlé après chaque montée de version ; ses métriques (`coredns_dns_requests_total`, `coredns_forward_healthcheck_failures_total`) seront suivies au module 21. Les noms externes appelés par les applications sont écrits avec un point final dans les configurations (règle de revue des MR de déploiement).

---

### M15-E05 — Cilium et Hubble : observer les flux

**Solution**

*A. Se connecter et filtrer* (questions 1 à 3) :

```
admin@adm01:~$ cilium hubble port-forward &
admin@adm01:~$ hubble status
Healthcheck (via localhost:4245): Ok
Current/Max Flows: 24,570/24,570 (100.00%)
Flows/s: 41.2
Connected Nodes: 6/6
```

Chaque agent garde **4095** flux dans un tampon circulaire (24 570 = 6 × 4095) ; à 40 flux par seconde, c'est moins de dix minutes d'historique **pour tout le cluster**, beaucoup moins sur un nœud chargé. Pour un incident, on observe pendant la reproduction (`-f`) ou tout de suite après ; Hubble n'est pas une archive (l'export des flux vers une base viendra avec la supervision).

```
admin@adm01:~$ hubble observe -n wb-essais -f
admin@adm01:~$ hubble observe --from-pod wb-essais/sonde-w01a --to-label app=echo -f
admin@adm01:~$ hubble observe -n wb-essais --port 53 -f
Oct  8 14:02:11.311: wb-essais/sonde-w01a:41322 (ID:38712) -> wb-essais/echo-6c9f7d5b8-4xk2p:8080 (ID:11935) to-endpoint FORWARDED (TCP Flags: SYN)
Oct  8 14:02:11.311: wb-essais/sonde-w01a:41322 (ID:38712) <- wb-essais/echo-6c9f7d5b8-4xk2p:8080 (ID:11935) to-endpoint FORWARDED (TCP Flags: SYN, ACK)
```

Une requête produit plusieurs lignes : une par paquet significatif (SYN, SYN-ACK, données, FIN) et par **point d'observation** (sortie du pod source, envoi dans le tunnel `to-overlay`, remise au pod destination `to-endpoint`, passage à la pile du nœud `to-stack`). Les identités (`ID:…`) se lisent avec `cilium-dbg identity get`.

*B. Un refus* (questions 4 et 5). [`manifestes/essais-hubble.yaml`](fichiers/M15-E05/manifestes/essais-hubble.yaml), premier document :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- curl -sv -m 3 http://vide/
*   Trying 10.96.77.140:80...
* connect to 10.96.77.140 port 80 failed: Connection refused
admin@adm01:~$ hubble observe -n wb-essais --verdict DROPPED --last 5
Oct  8 14:05:02.880: wb-essais/sonde-w01a:50114 (ID:38712) <> 10.96.77.140:80 (world) Service backend not found DROPPED (TCP Flags: SYN)
```

Cilium rejette (réglage `serviceNoBackendResponse: reject` par défaut : un ICMP « inaccessible » qui donne au client un refus **immédiat**, plutôt qu'un délai dépassé) et Hubble donne la raison. Question 5 : non, Hubble ne voit qu'un flux TCP vers le port 8080 : aucun composant n'analyse le HTTP tant qu'aucune politique L7 ne fait passer le trafic par le proxy.

*C. Visibilité L7 et rédaction* (questions 6 à 11). Dans Cilium 1.20, la visibilité L7 s'obtient par une **politique L7** (l'ancienne annotation de visibilité sur les pods a été retirée). Second document de `essais-hubble.yaml` : `visibilite-l7-echo`, entrée depuis toutes les entités sur 8080 avec `rules.http: [{}]` (toute requête acceptée, mais par le proxy).

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- curl -s -H "Authorization: Bearer secret-de-test" \
    -H "Cookie: session=abc" "http://echo/echo?msg=patient-123"
admin@adm01:~$ hubble observe -n wb-essais --protocol http --last 2 -o json | jq '.flow.l7.http'
{
  "method": "GET",
  "url": "http://echo/echo?msg=patient-123",
  "protocol": "HTTP/1.1",
  "headers": [
    {"key": "Authorization", "value": "Bearer secret-de-test"},
    {"key": "Cookie", "value": "session=abc"},
    …
```

Tout est lisible par quiconque a accès à Hubble : c'est la fuite que décrit Sophie. Rédaction dans [`k8s/composants/cilium/values.yaml`](fichiers/M15-E05/k8s/composants/cilium/values.yaml) (`hubble.redact` : `enabled`, `http.urlQuery`, `http.userInfo`, `http.headers.deny`) :

```
admin@adm01:~/src/k8s$ cilium upgrade --version <VERSION-CILIUM> --reset-values \
    --values composants/cilium/values.yaml --dry-run-helm-values | grep -A12 redact
admin@adm01:~/src/k8s$ cilium upgrade --version <VERSION-CILIUM> --reset-values --values composants/cilium/values.yaml
admin@adm01:~$ kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.hubble-redact-enabled}'; echo
true
admin@adm01:~$ kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium
admin@adm01:~$ kubectl -n kube-system rollout status daemonset/cilium --timeout=10m
admin@adm01:~$ cilium status --wait
```

`--reset-values` : le fichier est l'unique source ; sans lui, des valeurs passées autrefois (au module 14, par `--set`) pourraient survivre en silence. La ConfigMap change, mais `rollOutCiliumPods` vaut `false` : les agents gardent leur configuration de démarrage jusqu'au redémarrage. Le DaemonSet se redémarre par vagues (`maxUnavailable` du chart) ; pendant le redémarrage d'un agent, les programmes eBPF déjà chargés continuent de traiter les paquets : le trafic établi n'est pas coupé, seuls les nouveaux pods de ce nœud attendent.

Après :

```
admin@adm01:~$ hubble observe -n wb-essais --protocol http --last 2 -o json | jq '.flow.l7.http'
{
  "method": "GET",
  "url": "http://echo/echo?msg=HIDDEN",
  "headers": [
    {"key": "Authorization", "value": "HIDDEN"},
    {"key": "Cookie", "value": "HIDDEN"},
    …
```

Restent visibles : la méthode, l'hôte, le **chemin** (`/echo`), le code de réponse, les adresses et identités. Limite : une API qui met un identifiant dans le chemin (`/patients/123/dossier`) le laisse voir ; MédiAgenda (`/api/v1/rendez-vous/{rdv_id}`) expose un identifiant de rendez-vous, pas de patient : à noter pour la revue de Sophie. Puis `kubectl -n wb-essais delete -f essais-hubble.yaml`.

*D. Fiche* : [`medisphere/docs/kubernetes/reseau/hubble.md`](fichiers/M15-E05/medisphere/docs/kubernetes/reseau/hubble.md).

Le check vérifie Hubble (activé, relay prêt), les agents (prêts partout, redémarrés après la dernière modification de `cilium-config`), la rédaction telle que les agents la lisent (ConfigMap) et dans le dépôt, la suppression des objets d'essai et la fiche.

**Explications**

- **D'où viennent les flux L7.** Le proxy (Envoy, DaemonSet `cilium-envoy`) analyse les requêtes des ports soumis à une règle L7 et remonte un enregistrement par requête à l'agent, qui le place dans le tampon de Hubble. La rédaction est appliquée **par l'agent** avant de conserver le flux : rien de sensible n'est ni stocké ni servi par le relay.
- **Pourquoi « tout autoriser » change quand même quelque chose.** Une politique qui sélectionne un pod en entrée active l'application des politiques pour ce pod : tout ce qu'elle n'autorise pas est refusé. `fromEntities: [all]` sur 8080 n'enlève rien à `echo` (qui n'a que ce port) ; un pod qui aurait d'autres ports les verrait se fermer.

**Alternatives**

- Liste `allow` d'en-têtes (seuls ceux-là restent visibles) plutôt que `deny` : plus sûr (un nouvel en-tête sensible est masqué par défaut), plus coûteux à maintenir ; à envisager quand les flux seront exportés (M21-M22).
- Interface web de Hubble : M15-E26, publiée par la Gateway et protégée.

**Pièges classiques**

- Appliquer les *values* et oublier de redémarrer les agents : la ConfigMap dit `true`, les flux montrent encore les jetons. Le check le détecte (date de démarrage des agents contre date de modification de la ConfigMap).
- Une politique de visibilité qui ne liste que le trafic des pods (`fromEndpoints`) : le NodePort depuis `adm01` (identité `world`) est coupé.
- Lire `hubble observe` sans filtre : les flux de santé noient tout.
- Confondre `--port` (source **ou** destination) et `--to-port`.

**En production chez MédiSphère**

Hubble est l'outil de première intention de l'astreinte pour « c'est le réseau ou pas ? » (RB-150). La rédaction fait partie de la configuration de référence de Cilium et de l'ADR-0150 ; Sophie la contrôle à chaque revue de l'ADR. L'accès à Hubble (relay, puis interface web) est réservé à l'équipe Plateforme et à l'astreinte : ce sont des journaux d'accès au sens HDS.

---

### M15-E06 — Premières politiques réseau : tout interdire par défaut

**Solution**

[`manifestes/politiques-wb-essais.yaml`](fichiers/M15-E06/manifestes/politiques-wb-essais.yaml) : les quatre politiques, commentées.

```
admin@adm01:~$ kubectl -n wb-essais label pod sonde-w01a sonde-w02 role=client
admin@adm01:~$ hubble observe -n wb-essais --type policy-verdict -f
```

Question 1 : avant toute politique, tout passe et `policy-verdict` ne montre **rien** (aucun pod n'est soumis à une politique, il n'y a pas de verdict à rendre).

Question 3, après `refus-par-defaut` (sélection : **tous** les pods de `wb-essais`, entrée et sortie) :

```
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- curl -s -m 3 http://echo/hostname; echo " rc=$?"
 rc=6
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- curl -s -m 3 http://10.96.141.27/hostname; echo " rc=$?"
 rc=28
Oct  8 14:31:10.204: wb-essais/sonde-w01a:43122 (ID:38712) -> kube-system/coredns-…:53 (ID:…) policy-verdict:none EGRESS DENIED (UDP)
Oct  8 14:31:13.511: wb-essais/sonde-w01a:57010 (ID:38712) -> wb-essais/echo-…:8080 (ID:11935) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
```

`rc=6` : le **nom** ne se résout plus (le DNS est une sortie comme une autre) ; `rc=28` : par l'adresse, délai dépassé (un refus de politique jette le paquet en silence, réglage `policyDenyResponse: none`). Hubble montre des refus en **sortie** (`EGRESS DENIED`) sur le nœud du client. `kubernetes.default`, `dns01` et Internet échouent de la même façon.

Question 4 : `autoriser-dns`. Le point délicat : `namespaceSelector` **et** `podSelector` dans le **même** élément de `to` (« les pods `k8s-app=kube-dns` de l'espace `kube-system` »). Écrits en deux éléments, la règle autoriserait « tout l'espace `kube-system` OU les pods `k8s-app=kube-dns` de `wb-essais` ». Après : les noms se résolvent (`echo`, `git01.par1.medisphere.internal`), mais les connexions restent refusées.

Questions 5 et 6 : `clients-vers-echo` (sortie des `role=client` vers `app=echo`, **8080**) et `echo-entree` (entrée de `echo` depuis `role=client`, 8080 ; puis depuis 10.10.10.0/24, 8080). Le port est celui du **pod** : la traduction du Service (80 → 8080) a déjà eu lieu quand la politique est évaluée ; une règle sur le port 80 n'autoriserait rien. Une connexion passe si la **sortie du client** et l'**entrée du serveur** l'autorisent toutes les deux :

| Source → `echo` | Sortie du client | Entrée de `echo` | Résultat | Hubble |
|---|---|---|---|---|
| `sonde-w01a` (`role=client`) | `clients-vers-echo` | `echo-entree` | passe | `EGRESS ALLOWED` puis `INGRESS ALLOWED` |
| `sonde-w02` (`role=client`, autre nœud) | `clients-vers-echo` | `echo-entree` | passe | idem, `INGRESS` vu sur le nœud de `echo` |
| `sonde-w01b` (sans label) | refusée | (jamais atteinte) | refusé | `EGRESS DENIED` sur `k8s-w01` |
| `adm01` par `echo-np` | (hors cluster) | `echo-entree` (ipBlock) | passe | `INGRESS ALLOWED` depuis `world` |

Question 6 : on peut raisonner sur l'adresse de `adm01` parce que `echo-np` est en `externalTrafficPolicy: Local` (E03) : le pod reçoit le paquet avec l'adresse source **réelle** (10.10.10.10). En `Cluster`, un nœud qui transmet à un pod d'un autre nœud masque l'adresse derrière la sienne : il faudrait autoriser les nœuds (en standard, un `ipBlock` 10.10.40.0/24 ; en Cilium, l'entité `remote-node`/`host`), c'est-à-dire n'importe qui passant par n'importe quel nœud : bien moins précis.

Question 7 : les sondes du kubelet partent du nœud lui-même (identité `host`) ; Cilium autorise toujours le trafic du nœud local vers ses pods (réglage par défaut, conforme à l'API NetworkPolicy qui prévoit que les sondes de santé ne soient pas bloquées). Les pods restent `Ready`.

Le check vérifie, sur le **contenu** des politiques (pas leurs noms) : un refus par défaut complet, l'autorisation DNS exacte (kube-system/kube-dns, UDP et TCP 53, sélecteurs combinés), l'absence de sortie « tout ouverte », les autorisations clients → `echo` sur 8080 (numéro ou port nommé), l'autorisation du VLAN 10.10.10.0/24 et aucune plage plus large qu'un /24, les labels des sondes, et le NodePort depuis `adm01`.

**Explications**

- **Union, pas d'ordre.** Les politiques d'un pod s'additionnent ; il n'y a ni priorité ni règle « refuser » dans l'API standard. Le refus vient de la **sélection** : un pod sélectionné dans une direction n'accepte plus que ce qu'au moins une politique autorise. C'est pourquoi `refus-par-defaut` ne contient rien.
- **Les réponses passent.** Une connexion autorisée dans un sens voit ses paquets de réponse acceptés (suivi de connexion de Cilium) : on n'écrit jamais de règle « retour ».
- **Pourquoi TCP 53.** Une réponse DNS trop grande pour UDP revient tronquée (drapeau TC) et le client recommence en TCP ; DNSSEC et les grosses listes d'adresses (Service *headless*) le déclenchent.

**Alternatives**

- **Politique de base à l'échelle du cluster** (`CiliumClusterwideNetworkPolicy`) qui pose le refus par défaut et le DNS pour tous les espaces d'applications d'un coup : c'est M15-E28. L'API standard n'a pas d'objet de portée cluster (les `AdminNetworkPolicy` du groupe de travail réseau ne sont pas encore une API stable).
- **CiliumNetworkPolicy** pour le DNS avec `rules.dns` (`matchPattern`) : en plus d'autoriser le port 53, elle fait passer le DNS par le proxy DNS de Cilium, ce qui permet les politiques `toFQDNs` (sortie vers des noms, M15-E17, E28).

**Pièges classiques**

- Écrire le port du Service (80) au lieu du port du pod (8080).
- Séparer `namespaceSelector` et `podSelector` en deux éléments : on ouvre beaucoup plus que voulu.
- Oublier le DNS dans un refus par défaut en sortie : tout « tombe en panne » d'un coup, avec des erreurs de résolution qui font chercher du côté de CoreDNS (panne M15-E36, E37).
- Chercher le refus côté serveur alors qu'il est côté client : Hubble dit `EGRESS` ou `INGRESS`.
- Autoriser `0.0.0.0/0` en entrée « pour le NodePort » : c'est tout ce qui n'est pas un pod du cluster.

**En production chez MédiSphère**

Le modèle s'applique aux espaces `mediagenda-*` (M15-E17) : refus par défaut, DNS, API → PostgreSQL et Valkey, Gateway → API, avec un label de rôle par composant plutôt que des noms de pods. Toute politique est relue en MR avec le tableau « source, destination, port, attendu » de la question 8, et testée dans Hubble avant fusion ; la matrice des flux du cluster (M15-E32) en est le résumé.

---

### M15-E07 — Gateway API : premières routes HTTP

**Solution**

*A. Prérequis et CRD* (questions 1 à 3). Prérequis de la documentation de Cilium 1.20 : `kubeProxyReplacement=true` (fait en E08), `l7Proxy=true` (défaut), un Service `LoadBalancer` disponible **ou** le mode réseau de l'hôte, et, avec `bpf.tproxy=false` (défaut), iptables et les modules netfilter de TPROXY sur les nœuds (le noyau Debian 13 les fournit en modules ; à vérifier si une connexion à la Gateway expire sans jamais atteindre Envoy).

```
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -E "KubeProxyReplacement|Proxy Status"
KubeProxyReplacement:    True   [ens18   10.10.40.61 (Direct Routing)]
Proxy Status:            OK, ip 10.240.3.171, 0 redirects active on ports 10000-20000, Envoy: external
admin@adm01:~$ cilium config view | grep -E "^enable-l7-proxy|^kube-proxy-replacement "
```

[`k8s/composants/gateway-api/telecharger-crd.sh`](fichiers/M15-E07/k8s/composants/gateway-api/telecharger-crd.sh) et [`SHA256SUMS-v1.6.1`](fichiers/M15-E07/k8s/composants/gateway-api/SHA256SUMS-v1.6.1) :

```
admin@adm01:~/src/k8s$ composants/gateway-api/telecharger-crd.sh
empreintes conformes à SHA256SUMS-v1.6.1
CRD v1.6.1 (canal standard) dans composants/gateway-api/v1.6.1
admin@adm01:~/src/k8s$ kubectl apply --server-side -f composants/gateway-api/v1.6.1/
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
…
admin@adm01:~$ kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations}' | jq
{
  "api-approved.kubernetes.io": "https://github.com/kubernetes-sigs/gateway-api/pull/4530",
  "gateway.networking.k8s.io/bundle-version": "v1.6.1",
  "gateway.networking.k8s.io/channel": "standard"
}
```

Les CRD sont **versionnées dans le dépôt** : la MR montre ce qui change à chaque montée de version, l'application ne dépend pas de GitHub ce jour-là, et les empreintes prouvent que les fichiers sont ceux du projet. Les annotations `bundle-version` et `channel` répondent dans un an à « qu'est-ce qui est installé ». `--server-side` : les CRD de la Gateway API dépassent la taille de l'annotation `last-applied-configuration` d'un `kubectl apply` classique.

*B. Le contrôleur* (question 4). [`k8s/composants/cilium/values.yaml`](fichiers/M15-E07/k8s/composants/cilium/values.yaml) (version E07 : `gatewayAPI.enabled: true`, `l7Proxy: true` écrit explicitement), `cilium upgrade`, redémarrage de l'opérateur et des agents, `cilium status --wait` :

```
admin@adm01:~$ kubectl get gatewayclass
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       1m
```

La GatewayClass `cilium` est rendue **par le chart** (`gatewayAPI.gatewayClass.create: auto` : seulement si la CRD `GatewayClass` existe au moment de l'application) : d'où « CRD d'abord ». Dans l'autre ordre, l'opérateur journalise « Required GatewayAPI resources are not found » et le contrôleur ne démarre pas ; il faut réappliquer après les CRD et redémarrer l'opérateur.

*C. Une Gateway sans adresse* (questions 5 à 7). [`manifestes/gw-attente.yaml`](fichiers/M15-E07/manifestes/gw-attente.yaml) :

```
admin@adm01:~$ kubectl -n wb-essais get gateway,svc
NAME                                           CLASS    ADDRESS   PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/gw-attente   cilium             False        20s
NAME                                 TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/cilium-gateway-gw-attente    LoadBalancer   10.96.201.14   <pending>     80:31944/TCP   20s
```

Cilium crée un Service `LoadBalancer` `cilium-gateway-<nom>` ; personne ne fournit d'adresse (le LB IPAM arrive en E10) : `EXTERNAL-IP <pending>`, et la Gateway n'est pas programmée (le message de l'état `Programmed` parle de l'adresse). `kubectl -n wb-essais delete gateway gw-attente` (le Service est supprimé avec elle : il lui appartient).

[`manifestes/gw-essai.yaml`](fichiers/M15-E07/manifestes/gw-essai.yaml), dans l'ordre : `CiliumGatewayClassConfig` `nodeport` (`spec.service.type: NodePort`, d'après l'exemple officiel « GatewayClass Parameters Support »), GatewayClass `cilium-nodeport` (`parametersRef` vers elle), politique, Gateway, route.

```
admin@adm01:~$ kubectl get gatewayclass cilium-nodeport
NAME              CONTROLLER                     ACCEPTED   AGE
cilium-nodeport   io.cilium/gateway-controller   True       30s
admin@adm01:~$ kubectl -n wb-essais get gateway gw-essai ; kubectl -n wb-essais get svc cilium-gateway-gw-essai
NAME       CLASS             ADDRESS       PROGRAMMED   AGE
gw-essai   cilium-nodeport   10.10.40.51   True         40s
NAME                      TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
cilium-gateway-gw-essai   NodePort   10.96.18.203   <none>        80:30412/TCP   40s
admin@adm01:~$ kubectl -n wb-essais get ciliumenvoyconfigs
NAME                      AGE
cilium-gateway-gw-essai   40s
admin@adm01:~$ kubectl -n kube-system get ds cilium-envoy
NAME           DESIRED   CURRENT   READY   …
cilium-envoy   6         6         6
```

Avec un Service `NodePort`, l'opérateur renseigne l'adresse de la Gateway à partir des adresses des nœuds (`ADDRESS` : un nœud, ou plusieurs). La `CiliumEnvoyConfig` est la traduction de la Gateway et de ses routes en configuration Envoy ; le proxy qui la sert est **Envoy du DaemonSet `cilium-envoy`**, un par nœud : chaque nœud qui reçoit une requête la traite localement.

*D. Une route* (questions 8 à 11). Avec `port: 8080` dans `backendRefs` :

```
admin@adm01:~$ kubectl -n wb-essais describe httproute echo | sed -n '/Conditions/,/Controller/p'
    Conditions:
      Message:  Accepted HTTPRoute
      Reason:   Accepted
      Status:   True
      Type:     Accepted
      Message:  Service "wb-essais/echo" does not have a port 8080
      Reason:   BackendNotFound
      Status:   False
      Type:     ResolvedRefs
```

La route est acceptée par la Gateway, mais sa référence ne se résout pas : une route vise un Service par son **port de Service** (80), pas par le port du pod. Corrigée :

```
admin@adm01:~$ curl -s -H "Host: echo.wb-essais.internal" http://10.10.40.61:30412/hostname; echo
upstream connect error or disconnect/reset before headers. reset reason: connection timeout
admin@adm01:~$ hubble observe -n wb-essais --verdict DROPPED --last 3
… ingress-ingress (ID:8) -> wb-essais/echo-…:8080 (ID:11935) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
```

Envoy répond **503** : il n'arrive pas à joindre le pod. La source refusée a l'identité réservée **`ingress`** (ID 8) : le trafic qui sort d'Envoy vers un pod est émis par Cilium sous cette identité, ni pod, ni espace, ni adresse stable ; aucune NetworkPolicy standard ne sait la désigner. `echo-depuis-gateway` (CiliumNetworkPolicy, `fromEntities: [ingress]`, port 8080) l'autorise, et elle seule.

```
admin@adm01:~$ GW=http://10.10.40.61:30412; H="Host: echo.wb-essais.internal"
admin@adm01:~$ curl -s -H "$H" $GW/hostname; echo
echo-6c9f7d5b8-4xk2p
admin@adm01:~$ curl -s -H "$H" $GW/clientip; echo
10.240.3.171:40682
admin@adm01:~$ for p in "/shell?cmd=id" "/"; do curl -s -o /dev/null -w "%{http_code} $p\n" -H "$H" "$GW$p"; done
404 /shell?cmd=id
404 /
admin@adm01:~$ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: autre.wb-essais.internal" $GW/hostname
404
admin@adm01:~$ curl -sI -H "$H" $GW/hostname | grep -i ^server
server: envoy
```

`/clientip` : le pod voit l'adresse d'**Envoy** (l'adresse du proxy de Cilium sur le nœud, prise dans la tranche de pods du nœud) : c'est Envoy qui ouvre la connexion vers le pod ; l'adresse du client est dans l'en-tête `X-Forwarded-For`. `/shell`, `/` : aucune règle de la route ne correspond (chemins **exacts**) → 404 d'Envoy, le pod n'est jamais atteint. Autre nom : aucune route n'a ce nom pour cet écouteur → 404. C'est Envoy qui répond quand rien ne correspond.

```
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list | grep -A1 ":30412"
71   0.0.0.0:30412/TCP       NodePort       1 => 192.192.192.192:9999/TCP (active)
```

Le Service de la Gateway n'a pas de vrais pods : Cilium y met un point de terminaison fictif et marque le Service comme « répartiteur L7 » ; le programme eBPF du NodePort détourne alors chaque connexion vers l'Envoy **local** par TPROXY (d'où l'exigence du remplacement de kube-proxy : c'est le plan de données des Services de Cilium qui fait ce détournement). La forme exacte de la ligne (`L7 load balancer`, adresse fictive) dépend de la version : à vérifier sur ta sortie.

*E. Code* (question 12). MR des *values* et de `composants/gateway-api/` ; les objets d'essai restent dans `~/m15/e07/`. Réponse à Julien :

> Quatre objets. La **GatewayClass** (`cilium`) : fournie par la plateforme, c'est Cilium. La **Gateway** : écrite par la plateforme, c'est le point d'entrée (adresse, ports, noms, certificats, quels espaces peuvent s'y attacher). Les **HTTPRoute** : écrites par vous, dans votre espace : quels noms, quels chemins, vers quels Services. Et une **politique** qui laisse Envoy joindre vos pods. En cas de panne, lisez dans l'ordre : `kubectl get gateway` (programmée ?), `kubectl describe httproute` (`Accepted`, `ResolvedRefs`), `hubble observe --verdict DROPPED` (politique), puis le Service et ses EndpointSlices. Pas d'annotations magiques : tout est dans les champs, et les erreurs sont dans les états.

Le check vérifie les sept CRD (v1.6.1, canal standard) et l'absence de CRD expérimentale, le contrôleur (ConfigMap, remplacement de kube-proxy, agents redémarrés), les deux GatewayClass acceptées et la `CiliumGatewayClassConfig`, `gw-essai` (acceptée, programmée, écouteur, route attachée), l'HTTPRoute (nom, parent, états), l'absence de `gw-attente`, la politique `ingress` et son étroitesse, le Service NodePort, trois requêtes de bout en bout depuis `adm01` (200, 404, 404), et les CRD et *values* sur `main`.

**Explications**

- **Qui fait quoi.** L'opérateur Cilium lit Gateway et routes et écrit une `CiliumEnvoyConfig` et un Service ; les agents programment le détournement vers Envoy ; Envoy applique la correspondance et la répartition entre les pods (il lit lui-même les EndpointSlices, transmis par l'agent). Le Service `echo` n'est utilisé que pour trouver les pods : Envoy ne passe pas par sa ClusterIP.
- **Pourquoi une GatewayClass paramétrée.** C'est l'outil prévu par la Gateway API pour qu'une même implémentation propose plusieurs « profils » d'entrée. Ici, il remplace l'adresse manquante ; plus tard (E12), la Gateway principale utilisera la classe `cilium` avec une vraie adresse.
- **Chemins exacts.** `PathPrefix: /` aurait aussi publié `/shell` et `/exit` : une route publie ce qu'elle dit, pas ce qu'on voulait dire.

**Alternatives**

- **Mode réseau de l'hôte** (`gatewayAPI.hostNetwork.enabled`) : Envoy écoute directement sur les ports des nœuds ; plus de Service, mais **toutes** les Gateway passent dans ce mode (exclusif du mode LoadBalancer), et les ports privilégiés demandent une capacité supplémentaire. Utile sans fournisseur d'adresses ; nous aurons le LB IPAM.
- **`kubectl port-forward` vers le Service de la Gateway** : ne fonctionne pas, ce Service n'a pas de vrais pods derrière lui.
- **Envoy Gateway, Istio, NGINX Gateway Fabric** : autres implémentations de la Gateway API ; on garderait Cilium pour le reste, avec un composant de plus à exploiter. ADR-0150.

**Pièges classiques**

- Installer les CRD du canal *experimental* « pour avoir TLSRoute » : les CRD standard du même nom sont remplacées, et une montée de version ultérieure peut rendre des objets illisibles (note de Cilium 1.20 sur `TLSRoute`).
- Activer `gatewayAPI.enabled` avant d'installer les CRD : pas de GatewayClass, contrôleur inactif.
- Oublier le redémarrage des agents et de l'opérateur après `cilium upgrade`.
- `backendRefs` sur le port du pod ; route dont `hostnames` ne correspond pas au `hostname` de l'écouteur (route non attachée : `attachedRoutes: 0`).
- Chercher pourquoi Envoy renvoie 503 dans Envoy alors que Hubble montre un refus de politique de l'identité `ingress`.

**En production chez MédiSphère**

La Gateway principale `gw-par1` (E12) vit dans l'espace `passerelles`, géré par la plateforme ; les équipes n'écrivent que des routes dans leurs espaces, et seuls les espaces étiquetés `medisphere.fr/exposition: oui` peuvent s'y attacher. L'autorisation de l'identité `ingress` fait partie du modèle de politiques de chaque application (E17). Les CRD de la Gateway API sont montées de version comme un composant à part, avant Cilium, avec relecture des notes des deux projets (E27).

---

### M15-E08 — Remplacer kube-proxy par Cilium

**Solution**

*A. Préparer* (questions 1 à 6). Procédure de la documentation de Cilium pour une installation existante : (1) Cilium avec `kubeProxyReplacement=true` (et `k8sServiceHost`/`k8sServicePort`) ; (2) suppression du DaemonSet `kube-proxy` et de sa ConfigMap ; (3) sur chaque nœud, `iptables-save | grep -v KUBE | iptables-restore`. L'ordre « Cilium d'abord » évite toute période sans traduction des Services ; la suppression de kube-proxy rompt les connexions établies dont la traduction était tenue par lui.

`k8sServiceHost` et `k8sServicePort` : l'agent doit parler à l'API pour apprendre les Services ; s'il l'appelait par 10.96.0.1 (le Service `kubernetes`), il lui faudrait déjà savoir traduire cette adresse. Avec kube-proxy, c'était kube-proxy qui la traduisait ; sans lui, au premier redémarrage d'un nœud (ou d'un agent qui a perdu ses tables), l'agent ne joindrait jamais l'API : nœud sans réseau de pods. Chez nous, ils valent la VIP du plan de contrôle depuis le M14 (`k8s-api.par1.medisphere.internal:8443`, résolue par le DNS du socle).

État initial (question 2), à reporter dans la fiche :

```
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg status --verbose | grep -A3 "KubeProxyReplacement"
KubeProxyReplacement:   False
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg service list | wc -l
38
admin@k8s-w01:~$ sudo iptables-save -t nat | wc -l ; sudo iptables-save -t nat | grep -c "^:KUBE-SVC-"
412
19
```

kubeadm (question 3) : la recommandation de Cilium (supprimer la ConfigMap `kube-proxy` « pour éviter une réinstallation ») ne suffit **pas** avec kubeadm 1.36 : `kubeadm upgrade` ne regarde pas si la ConfigMap existe, il réinstalle l'extension kube-proxy (ConfigMap et DaemonSet) à chaque `upgrade apply`… sauf si `ClusterConfiguration.proxy.disabled` vaut `true` (code de la phase `addon/kube-proxy` : « Skipping the addon/kube-proxy phase. The addon is disabled. »). `kubeadm init --skip-phases=addon/kube-proxy` et `proxy.disabled: true` sont liés : l'un implique l'autre, et c'est le champ qui est enregistré dans la ConfigMap `kubeadm-config`. (Le champ `skipPhases` de `UpgradeConfiguration` est, lui, ignoré par `kubeadm upgrade apply` en 1.36.)

Modifications de `cluster/kubeadm-config.yaml` (le reste du fichier du module 14 ne change pas) :

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
# …
# CHG-1608 : Cilium remplace kube-proxy. kubeadm init ne l'installe pas, kubeadm upgrade ne le
# réinstalle pas (équivalent de --skip-phases=addon/kube-proxy, enregistré dans kubeadm-config).
proxy:
  disabled: true
```

et suppression du document `kind: KubeProxyConfiguration` (le mode `iptables` explicite du M14) : il ne configure plus rien, et le laisser ferait croire qu'il s'applique.

Fiche : [`medisphere/docs/kubernetes/changements/CHG-1608-remplacement-kube-proxy.md`](fichiers/M15-E08/medisphere/docs/kubernetes/changements/CHG-1608-remplacement-kube-proxy.md). Script : [`k8s/outils/nettoyer-regles-kube-proxy.sh`](fichiers/M15-E08/k8s/outils/nettoyer-regles-kube-proxy.sh) (préalables : DaemonSet absent, `kube-proxy-replacement=true` dans `cilium-config`, agent prêt sur le nœud ; quatre jeux de règles ; vérification ; `--simuler`). *Values* : [`k8s/composants/cilium/values.yaml`](fichiers/M15-E08/k8s/composants/cilium/values.yaml) (version E08).

```
admin@adm01:~/src/k8s$ outils/nettoyer-regles-kube-proxy.sh --simuler k8s-w01
== k8s-w01
  iptables : 287 ligne(s) KUBE
  ip6tables : 9 ligne(s) KUBE
terminé
admin@adm01:~/src/k8s$ git show main:composants/cilium/values.yaml > ~/m15/e08/values-avant.yaml
```

*B. La fenêtre* (questions 7 à 11) :

```
admin@adm01:~$ ~/src/k8s/outils/etcd-instantane.sh            # M14-E24, puis vérification de l'instantané
admin@adm01:~$ while true; do printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" \
    "$(curl -s -o /dev/null -m 1 -w '%{http_code}' http://10.10.40.61:30880/hostname)"; sleep 0.2; done \
    | tee ~/m15/e08/mesure-nodeport.log
admin@adm01:~$ kubectl -n wb-essais exec sonde-w01a -- sh -c 'while true; do printf "%s %s\n" "$(date +%T)" \
    "$(curl -s -o /dev/null -m 1 -w "%{http_code}" http://echo/hostname)"; sleep 0.2; done' | tee ~/m15/e08/mesure-clusterip.log
```

(`sonde-w01a` porte `role=client` : les politiques de E06 la laissent joindre `echo`.)

```
admin@adm01:~/src/k8s$ cilium upgrade --version <VERSION-CILIUM> --reset-values --values composants/cilium/values.yaml
admin@adm01:~$ kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium
admin@adm01:~$ kubectl -n kube-system rollout status daemonset/cilium --timeout=10m && cilium status --wait
admin@adm01:~$ for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    kubectl -n kube-system exec $p -c cilium-agent -- cilium-dbg status | grep KubeProxyReplacement; done
KubeProxyReplacement:    True   [ens18   10.10.40.51 (Direct Routing)]
…
admin@adm01:~$ kubectl -n kube-system exec $CIL -c cilium-agent -- cilium-dbg service list | awk '{print $3}' | sort | uniq -c
     18 ClusterIP
     12 NodePort
      2 HostPort
      …
```

Cilium sert maintenant **tous** les types : ClusterIP, NodePort (une ligne par adresse du nœud, plus `0.0.0.0`), `LoadBalancer` et `externalIPs` le jour où il y en aura, `hostPort`.

```
admin@adm01:~$ kubectl -n kube-system delete daemonset kube-proxy
admin@adm01:~$ kubectl -n kube-system delete configmap kube-proxy
admin@adm01:~/src/k8s$ outils/nettoyer-regles-kube-proxy.sh
== k8s-cp01
  iptables : 287 ligne(s) KUBE
  iptables : nettoyé, reste 0
  …
terminé
admin@k8s-w01:~$ sudo iptables-save -t nat | wc -l ; sudo iptables-save -t nat | grep -c "^:KUBE-SVC-"
31
0
```

Les 31 lignes restantes sont les chaînes `CILIUM_*` (masquage, TPROXY pour le proxy L7) et l'ossature des tables.

ConfigMap `kubeadm-config` (question 10) : la page « Reconfiguring a kubeadm cluster » propose de modifier la ConfigMap (`kubectl -n kube-system edit cm kubeadm-config`) ; nous préférons la réécrire **à partir du fichier du dépôt**, sur `k8s-cp01` (là où le rôle du plan de contrôle dépose `kubeadm-config.yaml`) :

```
root@k8s-cp01:~# kubeadm init phase upload-config kubeadm --config /etc/kubernetes/kubeadm-config.yaml
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
root@k8s-cp01:~# kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get cm kubeadm-config \
    -o jsonpath='{.data.ClusterConfiguration}' | grep -A1 '^proxy'
proxy:
  disabled: true
root@k8s-cp01:~# kubeadm upgrade plan
root@k8s-cp01:~# kubeadm upgrade apply v1.36.<CORRECTIF-ACTUEL> --dry-run 2>&1 | grep -i kube-proxy
[upgrade/addon] Skipping the addon/kube-proxy phase. The addon is disabled.
```

(Chemin du fichier sur `k8s-cp01` : celui de ton rôle `k8s_plan_controle` au module 14 ; adapte. Si la simulation refuse la même version, la lecture de la ConfigMap et le code cité suffisent.)

Mesures (question 11), représentatives : côté ClusterIP (`sonde-w01a`), une série de `000` de 1 à 2 s pendant le redémarrage de l'agent de `k8s-w01` (connexions en cours rompues au changement de table) ; côté NodePort (`adm01`), une coupure de même ordre au redémarrage de l'agent de `k8s-w01`, puis quelques requêtes perdues à la suppression de kube-proxy et au nettoyage du nœud. Total : quelques secondes, conforme à l'annonce.

*C. Vérifier et clore* (questions 12 à 14). Les tests de E03 donnent les mêmes résultats (le nœud de contrôle ne sert toujours pas `echo-np` : `Local` est respecté par Cilium). `curl http://10.10.40.61:10256/healthz` répond (JSON avec `lastUpdated` et l'état) : c'est le serveur de santé compatible kube-proxy, que les répartiteurs interrogent pour savoir si un nœud est sain (et, pour un Service en `externalTrafficPolicy: Local`, si le nœud a un pod du Service, sur le port `healthCheckNodePort` du Service).

*Host Routing* : toujours `Legacy`. Le routage d'hôte eBPF exige le remplacement de kube-proxy **et** le masquage en eBPF (`bpf.masquerade: true`), que nous n'avons pas activé ; c'est un des sujets de M15-E29 (performances), à peser : il contourne netfilter du nœud (règles iptables locales ignorées pour le trafic des pods).

Rejeu du playbook du plan de contrôle en `--check --diff` : aucune tâche ne recrée kube-proxy (kubeadm n'est relancé que sur un nœud non initialisé) ; le fichier `kubeadm-config.yaml` déposé est celui du dépôt.

Le check vérifie l'absence du DaemonSet, de la ConfigMap et des pods kube-proxy, la configuration des agents (remplacement, serveur de santé, VIP de l'API), les agents prêts, à jour et redémarrés après la dernière modification de leur configuration, `/healthz` sur le port 10256 de chaque travailleur, l'absence de chaînes `KUBE-*` de kube-proxy (et la présence des chaînes `CILIUM`) sur les six nœuds, `proxy.disabled` dans la ConfigMap `kubeadm-config` et dans le fichier du dépôt (sans `KubeProxyConfiguration`), les *values*, le script et la fiche sur `main`, et le NodePort.

**Explications**

- **Pourquoi des connexions sont rompues.** Une connexion vers un Service est traduite au premier paquet, et la traduction vit dans une table de suivi : celle du noyau (conntrack) pour kube-proxy, celle de Cilium (tables CT et NAT en eBPF) pour Cilium. Changer de traducteur en cours de connexion, c'est perdre la traduction : les paquets suivants ne correspondent plus à rien.
- **Pourquoi la ConfigMap compte.** `kubeadm upgrade apply` reconstruit l'extension kube-proxy à partir de la `ClusterConfiguration` **du cluster** (ConfigMap `kubeadm-config`), pas de ton fichier ; corriger seulement le fichier du dépôt ne suffit pas, corriger seulement la ConfigMap non plus (un nœud reconstruit depuis le dépôt réinstallerait kube-proxy).
- **Serveur de santé 10256.** Les répartiteurs externes (et le M15-E25) s'en servent ; sans lui, rien n'écoute plus sur ce port une fois kube-proxy parti.

**Alternatives**

- **Reconstruire le cluster sans kube-proxy** (`kubeadm init` avec `proxy.disabled`) : la voie propre pour un nouveau cluster, et ce que fera la reconstruction de M15-E23 ; impossible ici sans arrêt complet.
- **Garder kube-proxy en mode nftables** et Cilium sans remplacement : un composant de plus, deux plans de données, et pas de Gateway API Cilium.
- **Nettoyer par redémarrage des nœuds** (drain, reboot, uncordon, un par un) : les règles de kube-proxy ne sont pas persistantes ; plus long, mais sans manipuler iptables à la main. Défendable si l'outil `iptables` est absent des nœuds.

**Pièges classiques**

- Supprimer kube-proxy **avant** que les agents tournent avec le remplacement (ConfigMap modifiée mais agents non redémarrés) : plus aucun Service, CoreDNS compris, sur tout le cluster.
- Croire la ConfigMap `cilium-config` (`true`) sans regarder `cilium-dbg status` dans les agents.
- Oublier `k8sServiceHost` : tout fonctionne… jusqu'au premier redémarrage d'un nœud.
- Ne nettoyer que `iptables` (IPv4, nft) : des chaînes restent dans `ip6tables` ou dans le backend `legacy`, et réapparaissent dans les diagnostics.
- Laisser `proxy.disabled` hors de la ConfigMap : la prochaine montée de version (E27, M14-E25 pour la suivante) réinstalle kube-proxy, qui recrée ses règles **à côté** de Cilium.
- Ne pas mesurer : sans chiffres, la prochaine fenêtre sera annoncée « à l'instinct ».

**En production chez MédiSphère**

Le remplacement de kube-proxy fait partie de la configuration de référence de tout cluster MédiSphère (ADR-0150) ; un nouveau cluster est créé sans kube-proxy. Les changements de plan de données (Cilium, kube-proxy, CNI) passent par une fiche CHG avec instantané etcd, fenêtre annoncée, mesure de l'interruption et retour arrière écrit **avant** de commencer. RB-142 (montée de version) gagne une vérification : `kubeadm upgrade plan` ne doit lister aucune action sur kube-proxy.

---

### M15-E09 — Questions : CNI, eBPF et Services

**Barème** : 2 points par question (30 au total) ; une réponse qui ne s'appuie sur aucune observation des exercices plafonne à 1. En dessous de 18, refais E02 et E03 avant le palier 2.

**1. De la création du pod au premier paquet.** Le kubelet demande au runtime (containerd, par CRI) de créer le bac à sable du pod : containerd crée l'espace de noms réseau (tenu par le conteneur `pause`) et appelle le greffon CNI désigné par `/etc/cni/net.d/` (`cilium-cni`) avec la commande `ADD`. Le greffon demande à l'**agent Cilium** local une adresse dans la tranche du nœud (tranche attribuée par l'**opérateur** dans `CiliumNode`), crée la paire veth, configure `eth0` et ses routes dans le pod. L'agent crée le point de terminaison, calcule son **identité** à partir des labels (en l'allouant au besoin dans une ressource `CiliumIdentity`), compile et attache les programmes eBPF de l'interface `lxc…`, calcule ses politiques, publie une ressource `CiliumEndpoint`. Les agents des autres nœuds la voient et ajoutent l'adresse à leur ipcache (identité, nœud). Tant que ce n'est pas fait, le premier paquet vers ce pod peut être refusé ou traité comme une identité inconnue : quelques centaines de millisecondes en général.

**2. Réponse B.** L'espace de noms fait partie des labels de **sécurité** (`io.kubernetes.pod.namespace`) : deux pods aux mêmes labels dans deux espaces ont deux identités, sinon une politique de l'un s'appliquerait à l'autre. A oublie ce label ; C est faux (l'identité est la même sur tout le cluster, c'est ce qui la rend utile entre nœuds) ; D décrit justement ce que Cilium évite.

**3. Identité ou adresse.** Les pods changent d'adresse à chaque recréation ; une politique par adresse devrait être recalculée et reprogrammée sur tous les nœuds à chaque changement. Par identité, seule l'ipcache change (« telle adresse a maintenant telle identité ») ; les tables de politique, indexées par identité, restent les mêmes. Cilium raisonne quand même en adresses pour ce qui n'est pas un pod du cluster : clients extérieurs (`ipBlock` de E06, qui devient une identité de **plage** d'adresses), destinations par nom (`toFQDNs` : les adresses apprises par le proxy DNS), nœuds.

**4. L'identité à l'arrivée.** En tunnel, dans le **VNI** de l'en-tête VXLAN (observé en E02 : VNI = identité de `sonde-w01a`). En routage natif, sans en-tête de tunnel, le nœud d'arrivée cherche l'adresse source dans son **ipcache** : il faut qu'elle soit à jour, et qu'une adresse ne puisse pas être usurpée (le réseau sous-jacent doit empêcher un tiers d'émettre avec une adresse de pod).

**5. MTU.** 1500 (VLAN 40) − 50 (VXLAN) = 1450. Avec WireGuard, l'en-tête de chiffrement s'ajoute (Cilium recalcule le MTU des routes des pods : il baisse encore ; mesuré en M15-E24). Si le VLAN passait à 9000 sans prévenir : Cilium détecte le MTU de l'interface au démarrage de l'agent (`MTU: 0`, détection automatique) ; les nœuds redémarrés passeraient à 8950 et les autres resteraient à 1450, et tout ce qui sort du VLAN 40 (bordure à 1500) dépendrait de la découverte du MTU : grosses réponses figées si un ICMP manque. Un changement de MTU est un changement coordonné (M07-E15).

**6. Coût des règles.** Pour un Service de 3 pods sur un port : une règle dans `KUBE-SERVICES`, une chaîne `KUBE-SVC` de 3 règles (plus 1 de marquage), 3 chaînes `KUBE-SEP` de 2 règles, plus les règles NodePort et d'affinité : une quinzaine (E03). Avec 2 000 Services, des dizaines de milliers de règles ; `KUBE-SERVICES` est parcourue **séquentiellement** à chaque nouvelle connexion (coût proportionnel au nombre de Services en mode iptables), et chaque changement réécrit de grands morceaux de la table. Avec les tables eBPF : une recherche dans une table de hachage par connexion (coût constant), et une mise à jour **par entrée** quand un pod change. (Le mode nftables de kube-proxy règle aussi le parcours séquentiel, par des tables d'adresses.)

**7. Socket LB.** Des programmes eBPF attachés aux appels système de socket du cgroup des pods (`connect`, `sendmsg`, `recvmsg`, `getpeername`) : au `connect()` vers 10.96.141.27:80, Cilium remplace la destination par l'adresse d'un pod (10.240.4.19:8080) **dans la socket** ; le noyau émet directement vers le pod, `getpeername()` rend encore l'adresse du Service à l'application. Aucun paquet ne porte donc l'adresse du Service, et aucune traduction par paquet n'est nécessaire. Une capture sur l'interface du pod ne montre que l'adresse du pod de destination.

**8. Réponse B.** En `Local`, un nœud sans pod du Service n'a aucune destination : la requête est refusée ou perdue. Le répartiteur doit interroger le port de santé (pour un Service `LoadBalancer`, `healthCheckNodePort`, servi par le serveur de santé de Cilium) et retirer ce nœud. A décrit `Cluster`. C et D n'existent pas.

**9. Erreurs pendant un `rollout restart`.** (1) Pods annoncés avant d'être prêts : sonde de disponibilité honnête. (2) Pods arrêtés pendant que leur retrait se propage aux nœuds : arrêt progressif de l'application sur SIGTERM, `preStop` d'attente, `terminationGracePeriodSeconds` suffisant. (3) Trop de pods remplacés à la fois : `maxUnavailable: 0`, `maxSurge`, PDB pour les évictions. On peut ajouter les connexions persistantes vers un pod qui s'arrête (le client doit savoir rouvrir) et l'affinité de session vers un pod disparu.

**10. CoreDNS vers `dns01`.** `dns01` voit l'adresse des **nœuds** qui hébergent les pods CoreDNS (masquage, E02). Si `dns01` tombe : avec `policy sequential`, CoreDNS continue d'envoyer à `dns01` jusqu'à ce que son contrôle de santé (toutes les 0,5 s par défaut, `max_fails` 2) le marque en panne, puis passe à `dns02` ; pendant ce temps, les questions en cours attendent le délai de `forward`, et le client (glibc : `timeout:5`, `attempts:2` par défaut) peut attendre plusieurs secondes et réessayer. Le temps vu par les pods dépend donc de `health_check`, `max_fails`, des délais de `forward`, du cache de CoreDNS (les noms déjà en cache répondent), et des options `timeout`/`attempts` du `resolv.conf`.

**11. TCP 53 et sortie de CoreDNS.** TCP : réponses tronquées en UDP (drapeau TC, au-delà de la taille annoncée par EDNS), DNSSEC, grosses réponses. Pas besoin d'autoriser la sortie de CoreDNS : les politiques sont dans `wb-essais` ; les pods CoreDNS (`kube-system`) ne sont sélectionnés par aucune politique et sortent librement. (Une politique de base sur `kube-system`, M15-E28, devra l'autoriser explicitement.)

**12. Réponse B.** L'entrée de `echo` accepte maintenant `sonde-w01b` (union des autorisations), mais `sonde-w01b` est elle-même en refus par défaut **en sortie** : la connexion s'arrête sur son nœud. A suppose un ordre qui n'existe pas ; C oublie la sortie ; D : rien ne refuse une politique valide.

**13. Gateway et remplacement de kube-proxy.** L'entrée de la Gateway est un Service (ici NodePort) que Cilium marque comme « répartiteur L7 » : c'est son plan de données des Services (eBPF, au niveau du NodePort) qui détourne les connexions vers l'Envoy local par TPROXY ; sans le remplacement, ces Services seraient traduits par kube-proxy, qui ne sait rien d'Envoy. Chemin : `adm01` → `ens18` de `k8s-w01`, port 30412 → programme eBPF du NodePort (Service L7) → TPROXY vers l'écouteur d'Envoy (`cilium-envoy`) → Envoy lit `Host` et le chemin, choisit la route, puis un pod `echo` dans les adresses que l'agent lui transmet → Envoy ouvre une connexion vers le pod avec l'identité `ingress` → politique d'entrée de `echo` (`echo-depuis-gateway`) → pod. La réponse revient par Envoy.

**14. Visibilité L7.** Seul le proxy lit le HTTP : il faut qu'une politique L7 fasse passer le trafic par Envoy (ou le DNS par le proxy DNS). Coût : un saut de plus par connexion (latence, CPU et mémoire d'Envoy sur chaque nœud), une connexion TCP terminée et rouverte par le proxy (le pod voit Envoy), un composant de plus sur le chemin de toutes les requêtes du pod (un incident d'Envoy devient un incident de l'application), et des données de requête collectées (confidentialité). On l'active là où on en a besoin : politiques L7 réelles (E17), diagnostic ponctuel.

**15. Pour Claire.** « Un seul plan de données traduit maintenant les Services du cluster : Cilium, en eBPF ; kube-proxy et ses milliers de règles iptables ont disparu, kubeadm ne le réinstallera pas. Coût : quelques secondes de coupure mesurées pendant la fenêtre (CHG-1608), et une dépendance plus forte à Cilium (sa mise à jour devient un changement à part entière, M15-E27). Gains : diagnostic dans un seul jeu de tables, NodePort et adresses de service servis en eBPF, serveur de santé pour les répartiteurs. Et c'est le prérequis de la suite : Gateway API, adresses de service annoncées en BGP, publication de MédiAgenda. »

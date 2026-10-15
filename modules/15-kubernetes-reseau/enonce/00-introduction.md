# Module 15 — Introduction : le réseau de Kubernetes

## Personne n'entre sans `port-forward`

Lundi, 9 h 05. `k8s-par1` tourne depuis la fin du module 14 : trois nœuds de contrôle, trois travailleurs, une API haute disponibilité, MédiAgenda déployé dans `mediagenda-recette`. Julien Petit a passé son vendredi à faire des démonstrations avec `kubectl port-forward` ouvert dans un terminal. Il a perdu la connexion trois fois. Claire Morel envoie ce message.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Kubernetes — des adresses, des noms, des certificats, et des murs
>
> Bonjour,
>
> Le cluster est solide, mais il est fermé : rien n'en sort proprement, rien n'y entre sans un tunnel ouvert à la main. Le module 15 le relie au reste de MédiSphère. Ce que je veux à la fin :
> 1. **comprendre avant d'exposer** : chaque membre de l'équipe doit savoir suivre un paquet d'un pod à un autre, d'un client à un Service, et lire ce que Cilium en dit ;
> 2. **Cilium seul** dans le chemin des Services : on retire kube-proxy, on ne garde qu'un plan de données ;
> 3. des **adresses de service** dans 10.10.41.0/24, annoncées en **BGP** à la bordure, pour que tout le lab les joigne sans route statique ;
> 4. une **entrée unique** par la **Gateway API** : une Gateway `gw-par1`, un nom par application sous `apps.par1.medisphere.internal`, des certificats délivrés **automatiquement** par notre ACME, des noms publiés **automatiquement** dans notre DNS ;
> 5. des **politiques réseau** : tout est refusé par défaut dans les espaces des applications, et on n'ouvre que ce qui est écrit ;
> 6. l'exploitation : chiffrement entre nœuds, haute disponibilité de l'entrée, supervision, mise à jour de Cilium sans coupure, runbooks.
>
> Karim rappelle deux choses. ingress-nginx, que le prestataire posait partout, a été **retiré par son projet** en mars 2026 : on ne le déploie pas, on apprend à en sortir. Et rien ne s'applique au cluster sans passer par `plateforme/k8s`. Sophie veut une matrice des flux du cluster et des journaux de flux qui ne contiennent aucune donnée de patient. Nadia veut savoir, à 3 h du matin, si c'est le DNS, la politique, le Service, la Gateway ou le certificat.
>
> Premier jalon : le modèle réseau observé de près, CoreDNS raccordé à notre DNS, Hubble, les premières politiques, kube-proxy remplacé et une première route HTTP. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 15, MédiSphère a le réseau **v1** de son cluster (étiquette `k8s-reseau-v1` du dépôt `plateforme/medisphere`), consommé par tous les modules suivants :

- **Cilium 1.20** en remplacement complet de kube-proxy (`kubeProxyReplacement: true`), en mode tunnel VXLAN, avec **Hubble** (relay, puis interface web publiée et protégée) ;
- des **IP de service** attribuées par le **LB IPAM** de Cilium (pool `lb-par1`, 10.10.41.10-10.10.41.199) et annoncées en **BGP** (plan de contrôle v2, AS 65040) aux deux passerelles `gw01`/`gw02` (AS 65000) ;
- la **Gateway API v1.6** (canal standard) servie par Cilium : Gateway principale **`gw-par1`** (espace `passerelles`, 10.10.41.10), écouteur HTTPS pour `*.apps.par1.medisphere.internal` ;
- **cert-manager 1.21** et le ClusterIssuer `step-ca-acme` (ACME de `ca01`, défis HTTP-01 et DNS-01) ; la zone **`apps.par1.medisphere.internal`** sur PowerDNS, mise à jour en **RFC 2136** signée TSIG ; **ExternalDNS 0.23** qui publie les noms des routes ;
- des **politiques réseau** : NetworkPolicy standard, CiliumNetworkPolicy L7 et `toFQDNs`, politique de base à l'échelle du cluster ;
- le chiffrement **WireGuard** entre nœuds, la publication de MédiAgenda hors du lab par `lb01`/`lb02`, une comparaison avec **MetalLB** sur une VM jetable, la migration des Ingress d'InfoGér ;
- l'ADR-0150, les runbooks RB-150 (service injoignable), RB-151 (certificat non délivré), RB-152 (BGP), RB-153 (mise à jour de Cilium), la matrice des flux du cluster.

Le **palier 1** (ce fichier et `01-decouverte.md`) observe le modèle réseau tel que le module 14 l'a laissé (pods, Services, DNS, Hubble), pose les premières politiques, remplace kube-proxy et ouvre une première route HTTP par la Gateway API. Rien n'est encore annoncé à la bordure : tout se teste depuis `adm01` (VLAN 10, qui joint tout le lab) ou depuis des pods de sonde.

## Architecture du module

```
                        adm01 (1001) 10.10.10.10 — VLAN 10 MGMT
       kubectl · cilium · hubble · helm · ~/src/k8s (plateforme/k8s) · ~/src/ansible · checks
                                        │
   ═══════════ gw01 (.2) / gw02 (.3), VIP .1 — routage, filtrage, FRR AS 65000 (BGP, palier 2) ═══════════
        │                         │                               │                         │
 VLAN 20 INFRA            VLAN 70 DMZ                     VLAN 41 K8S-LB (non porté     VLAN 99 SANDBOX
 dns01 .10  dns02 .16     lb01 .10  lb02 .11              par une interface : annoncé   m15-essai (2151)
 (récurseurs, autoritaire VIP .200 → 10.10.41.10:443      en BGP, palier 2)             MetalLB (E19)
  zone apps, RFC 2136)    (E20)                           10.10.41.10 gw-par1
 ca01 .11 (ACME)                                          10.10.41.11-199 pool lb-par1
        │                                                         ▲ annonces /32
  ──────┴──────────── VLAN 40 K8S 10.10.40.0/24 · passerelle 10.10.40.1 · MTU 1500 ───┴──────────────────
     │ .51        │ .52        │ .53          VIP API .200 (8443)     │ .61        │ .62        │ .63
 ┌───┴──────┐ ┌───┴──────┐ ┌───┴──────┐                         ┌───┴──────┐ ┌───┴──────┐ ┌───┴──────┐
 │k8s-cp01  │ │k8s-cp02  │ │k8s-cp03  │                         │k8s-w01   │ │k8s-w02   │ │k8s-w03   │
 │etcd, API │ │etcd, API │ │etcd, API │                         │cilium    │ │cilium    │ │cilium    │
 │cilium    │ │cilium    │ │cilium    │                         │envoy     │ │envoy     │ │envoy     │
 └──────────┘ └──────────┘ └──────────┘                         └──────────┘ └──────────┘ └──────────┘
   pods : 10.240.0.0/16 (un /24 par nœud, IPAM cluster-pool) · Services : 10.96.0.0/16 (kube-dns 10.96.0.10)
   entre nœuds : tunnel VXLAN (UDP 8472), puis chiffré WireGuard (UDP 51871, palier 3)
```

Points structurants :

- **Deux réseaux virtuels sur un réseau réel.** Les pods (10.240.0.0/16) et les Services (10.96.0.0/16) n'existent que dans le cluster. Les pods d'un nœud se parlent par le noyau de ce nœud ; ceux de nœuds différents passent dans un **tunnel VXLAN** entre les adresses des nœuds (VLAN 40). La bordure ne voit jamais une adresse de pod : en sortie du cluster, Cilium masque l'adresse du pod derrière celle du nœud.
- **Les Services sont des règles, pas des machines.** Une adresse de Service n'appartient à aucune interface : c'est une entrée de table que kube-proxy (règles iptables) ou Cilium (tables eBPF) traduit vers l'adresse d'un pod. Ce module remplace le premier par le second (E08).
- **Une entrée par la Gateway API.** Les requêtes HTTP(S) entrent par une Gateway : Cilium lui donne une adresse de 10.10.41.0/24, l'annonce en BGP, et confie le trafic au proxy **Envoy** de chaque nœud, qui applique les routes (`HTTPRoute`) et le TLS.
- **Le DNS de MédiSphère reste la source.** CoreDNS répond pour `cluster.local` et transmet le reste à `dns01`/`dns02`. Les noms publiés (`*.apps.par1.medisphere.internal`) sont écrits par ExternalDNS dans une zone dédiée de l'autoritaire, jamais à la main.

### Hôtes et objets du module

| Élément | Valeur | Exercice |
|---|---|---|
| Cluster | `k8s-par1` (M14) : `k8s-cp01-03` 10.10.40.51-53, `k8s-w01-03` 10.10.40.61-63, API `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200) | entrée |
| Gateway d'essai | `gw-essai` (espace `wb-essais`), classe `cilium-nodeport`, Service NodePort | E07 |
| Pool LB IPAM | `lb-par1` : 10.10.41.10-10.10.41.199 | E10 |
| BGP | `CiliumBGPClusterConfig` `bgp-par1`, `CiliumBGPPeerConfig` `bordure`, AS 65040 ↔ `gw01` (10.10.40.2) et `gw02` (10.10.40.3), AS 65000 | E11 |
| Gateway principale | `gw-par1` (espace `passerelles`), 10.10.41.10, HTTP 80 (redirection) et HTTPS 443 `*.apps.par1.medisphere.internal`, certificat `apps-joker` | E12 |
| Zone DNS | `apps.par1.medisphere.internal` (primaire `dns01`, secondaire `dns02`), clés TSIG `externaldns-k8s` et `certmanager-k8s` | E14-E15 |
| `m15-essai` | VMID 2151, VNet `vsandbox`, kubeadm mononœud (MetalLB, adresses L2 10.10.99.230-10.10.99.238), détruite en fin de module | E19 |

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → VIP de l'API | TCP 8443 | tout le module | existant (MGMT joint tout le lab) |
| `adm01` → nœuds (SSH, NodePort de test) | TCP 22, 30000-32767 | E02-E08 | existant (MGMT joint tout le lab) |
| nœuds ↔ nœuds : tunnel VXLAN de Cilium, santé Cilium | UDP 8472, TCP 4240, ICMP | E02 | même VLAN 40 : ne traverse pas la passerelle |
| agents Cilium → relay Hubble, relay → agents | TCP 4244, 4245 | E05 | même VLAN 40 |
| pods (masqués derrière le nœud) → `dns01`/`dns02` | UDP/TCP 53 | E04 | existant (DNS depuis tous les VLAN) |
| nœuds → Internet (CRD de la Gateway API, images par le cache Harbor) | TCP 443 | E07 | existant (VLAN 40 → `reg01` 443 et Internet, M14) |

Aucun flux nouveau sur la bordure au palier 1. Les flux du module (BGP TCP 179, RFC 2136 vers `dns01`, DMZ → 10.10.41.0/24, WireGuard entre nœuds) arrivent aux paliers 2 et 3, par la matrice des flux (`group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`).

---

## Le chemin imposé

1. **`plateforme/k8s`** : tout ce qui configure le cluster y est versionné et relu en MR, puis appliqué depuis `adm01` (`task appliquer` du module 14, ou la commande d'installation donnée par l'exercice tant que la tâche n'existe pas). Pour ce module : `composants/cilium/values.yaml` (le **seul** endroit où vivent les réglages de Cilium), `composants/coredns/`, `composants/gateway-api/`, puis `composants/cert-manager/`, `composants/external-dns/`, `composants/reseau/` (pools, BGP, Gateway principale, politiques de base). L'exercice M15-E23 rend l'ensemble reproductible par `task`.
2. **Helm** reste un installateur : les commandes sont données (le packaging est enseigné au module 17). Cilium s'installe et se met à jour par la CLI `cilium`, comme au module 14, avec le fichier de *values* du projet ; on ne passe jamais un réglage par `--set` sans l'écrire dans le fichier.
3. **Ansible** pour ce qui vit hors du cluster : la bordure (rôle `frr`, `group_vars/role_routeur/`), les répartiteurs (rôle `haproxy`), la zone DNS (rôle `powerdns_auth`), et les outils des nœuds.
4. **Essais** dans l'espace **`wb-essais`** (brouillons dans `~/m15/eXX/` sur `adm01`, non versionnés, sans secret) ; ce qui sert la plateforme ou les applications va dans le code.
5. **Secrets** : clés TSIG en Ansible Vault `lab` et en Secret Kubernetes, jamais en clair dans un dépôt ; inscrits au registre des secrets. Pas de Vault ni d'External Secrets avant les modules 25.
6. **Documentation** : dans `plateforme/medisphere`, dossier **`docs/kubernetes/reseau/`** (fiches, ADR-0150, runbooks RB-150 à RB-153 dans `docs/kubernetes/reseau/runbooks/`, matrice des flux du cluster) ; fiches de changement dans `docs/kubernetes/changements/`.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Le modèle réseau de Kubernetes.** Trois règles : chaque pod a sa propre adresse IP ; tout pod peut joindre tout autre pod **sans traduction d'adresse** ; les agents d'un nœud (kubelet) peuvent joindre tous les pods de ce nœud. Kubernetes ne dit pas **comment** : c'est le rôle du **CNI**.

**CNI.** Une spécification (et des greffons) que le runtime appelle à la création et à la destruction de chaque pod : créer l'interface du pod, lui donner une adresse, la router. Cilium est un CNI ; il ajoute un agent par nœud (DaemonSet `cilium`) et un opérateur (Deployment `cilium-operator`) qui distribue les plages d'adresses (IPAM `cluster-pool` : un /24 de 10.240.0.0/16 par nœud).

**eBPF.** Des programmes chargés dans le noyau, vérifiés avant exécution, attachés à des points précis (interface, socket, cgroup). Cilium y implémente le routage, la traduction des Services, le filtrage et l'observation, avec des **tables** (*maps*) partagées entre le noyau et l'agent. Plus de longues chaînes iptables parcourues règle par règle : une recherche dans une table de hachage.

**Identités.** Cilium ne filtre pas par adresse IP mais par **identité** : un numéro attribué à chaque combinaison de labels de pod (plus quelques identités réservées : `host`, `remote-node`, `world`, `ingress`, `kube-apiserver`…). Une politique dit « l'identité A peut joindre l'identité B sur le port P » ; l'adresse du pod peut changer, l'identité reste.

**Services.** Une adresse virtuelle stable (ClusterIP) devant un ensemble de pods choisi par **sélecteur** ; les **EndpointSlices** listent les adresses prêtes. Types : `ClusterIP` (interne), `NodePort` (un port sur chaque nœud), `LoadBalancer` (une adresse externe fournie par un tiers : ici le LB IPAM de Cilium), *headless* (pas d'adresse virtuelle, le DNS rend les pods). Réglages : `sessionAffinity`, `externalTrafficPolicy`, `internalTrafficPolicy`.

**kube-proxy et son remplacement.** kube-proxy surveille Services et EndpointSlices et programme le noyau de chaque nœud (iptables, nftables ou IPVS). Cilium sait faire le même travail en eBPF, dès l'appel `connect()` du pod (*socket LB*) : il n'y a alors plus de traduction par paquet pour le trafic interne, et une seule source de vérité.

**DNS du cluster.** CoreDNS (Deployment `coredns`, Service `kube-dns` en 10.96.0.10) répond pour `<service>.<espace>.svc.cluster.local` et transmet le reste. Le `resolv.conf` des pods contient des domaines de recherche et `ndots:5` : un nom court est d'abord essayé avec chaque suffixe.

**NetworkPolicy.** Par défaut, tout est permis. Dès qu'une politique **sélectionne** un pod dans une direction (entrée ou sortie), tout ce qui n'est pas explicitement autorisé dans cette direction est refusé. Les politiques s'additionnent (union des autorisations), il n'y a pas de règle « refuser » dans l'API standard. Cilium ajoute ses propres ressources (`CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`) : L7 (HTTP), noms DNS (`toFQDNs`), entités réservées.

**Hubble.** L'observabilité de Cilium : chaque agent garde les derniers flux vus (source, destination, identités, verdict, raison d'un refus), le **relay** les agrège pour tout le cluster, la CLI `hubble` et l'interface web les interrogent.

**Gateway API.** Le successeur de l'objet `Ingress`, découpé par rôle : la **GatewayClass** (l'implémentation, fournie par Cilium), la **Gateway** (un point d'entrée : adresses, écouteurs, TLS, qui a le droit de s'y attacher), les **routes** (`HTTPRoute`, `GRPCRoute`, `TLSRoute`) écrites par les équipes d'application, et **ReferenceGrant** pour les références entre espaces. Les ressources sont des CRD, publiées en deux **canaux** : *standard* (stable) et *experimental*.

**BGP et LB IPAM.** Le LB IPAM donne une adresse aux Services `LoadBalancer` ; le plan de contrôle BGP de Cilium annonce ces adresses (en /32) aux routeurs de la bordure, qui savent alors vers quels nœuds envoyer le trafic. C'est le palier 2.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Kubernetes **1.36.x** ; Cilium et Hubble **1.20.x** (1.20.2 à la rédaction ; testé de Kubernetes 1.33 à 1.36) ; Gateway API **v1.6.1** (canal standard ; Cilium 1.20 exige au moins v1.6.1) ; cert-manager **1.21.x** ; ExternalDNS **0.23.x** (fournisseur `rfc2136`) ; MetalLB **0.16.x** ; ingress-nginx **1.15.1** (dernière version, projet retiré : étudié en migration seulement) ; CoreDNS de kubeadm 1.36 (1.14.x) |
| Changements de version | voir [`annexes/versions-bloc-C.md`](../../../annexes/versions-bloc-C.md) : Gateway API ≥ v1.6.1 et `TLSRoute` passée en `v1` ; Gateway API de Cilium **exige** `kubeProxyReplacement: true` ; BGP control plane **v2** seulement (`CiliumBGPPeeringPolicy` absente de la documentation 1.20) ; `cilium-dbg bgp …` marqué déprécié dans l'agent (lis plutôt l'état par la CLI `cilium bgp …` depuis `adm01` ou par le statut des `CiliumBGPNodeConfig` ; le remplaçant dans l'agent, `cilium-dbg shell -- bgp/…`, est à vérifier sur ta version) ; CiliumNetworkPolicy vides refusées à l'admission ; options `--node-port-mode`/`--node-port-algorithm` supprimées (`loadBalancer.mode`, `loadBalancer.algorithm`) ; *mutual auth* de Cilium déprécié ; `enableGatewayAPI` de cert-manager remplacé par `config.gatewayAPI.enabled` |
| État d'entrée (M14) | `k8s-par1` en 1.36, Cilium 1.20 installé par `cilium install --version 1.20.x --values plateforme/k8s/composants/cilium/values.yaml` : IPAM `cluster-pool` 10.240.0.0/16 (/24 par nœud), `k8sServiceHost: k8s-api.par1.medisphere.internal`, `k8sServicePort: 8443`, `kubeProxyReplacement: false`, Hubble relay activé ; kube-proxy en mode `iptables` ; metrics-server ; Helm 4.3, cilium et hubble CLI sur `adm01` |
| Mode réseau de Cilium | tunnel **VXLAN** (défaut : `routingMode: tunnel`, `tunnelProtocol: vxlan`, UDP 8472) ; la comparaison avec le routage natif est l'objet de M15-E29 |
| Espaces de noms | `wb-essais` (essais, PSA `baseline`), `mediagenda-dev`, `mediagenda-recette` (PSA `restricted`), `medidoc-dev` (M14-E33) ; créés dans ce module : `passerelles` (Gateway principale), `cert-manager`, `external-dns` |
| Images d'essai | par le cache Harbor : `registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16` (sondes réseau), `registry.par1.medisphere.internal/k8s/e2e-test-images/agnhost:2.66.1` (application `echo`) |
| Projet `plateforme/k8s` | clone `~/src/k8s` ; `composants/cilium/values.yaml`, `composants/coredns/`, `composants/gateway-api/` (palier 1), puis `composants/cert-manager/`, `composants/external-dns/`, `composants/reseau/` ; `cluster/kubeadm-config.yaml` |
| Documentation | `plateforme/medisphere` (clone `~/medisphere`) : `docs/kubernetes/reseau/` (fiches du palier 1 : `chemin-paquet.md`, `dns-du-cluster.md`, `hubble.md`), ADR-0150, runbooks `runbooks/RB-150` (service injoignable), `RB-151` (certificat non délivré), `RB-152` (BGP), `RB-153` (mise à jour de Cilium), `matrice-flux-cluster.md` ; `docs/kubernetes/changements/` (fiches CHG) |
| Tickets | PLAT-16xx, SEC-16xx, DEV-16xx, CHG-16xx, INC-42xx |
| Brouillons | `~/m15/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton identité dans `~/.kube/config` (M14-E06) |
| `<VERSION-CILIUM>` | Le correctif de Cilium 1.20 installé au module 14 (`cilium version`, ligne *cilium image (running)*), par exemple `1.20.2` |
| `<NOEUD>` | Un nœud du cluster (`k8s-w01`, `k8s-w02`…) |
| `<NODEPORT>` | Un port de la plage 30000-32767 attribué par Kubernetes à un Service |

### Variables de `lab/lab.env`

Le module n'ajoute que des variables facultatives : `WB_M15_ESSAI_KUBECONFIG` (kubeconfig de `m15-essai`, défaut `~/.kube/m15-essai.conf`, E19) et `WB_M15_IMAGE_SONDE` (image des témoins du palier 4, défaut netshoot v0.16 du cache Harbor). Le palier 1 n'en ajoute aucune : il utilise celles du module 14 (`WB_K8S_KUBECONFIG`, `WB_K8S_ADMIN_KUBECONFIG`, `WB_K8S_CP`, `WB_K8S_WORKERS`), `WB_SRC` et les jetons en lecture de GitLab. Les vérifications lisent le cluster avec le compte de service `wb-checks` (lecture seule, sans accès aux Secrets ; M15-E07 lui ajoute la lecture des objets de la Gateway API et de cert-manager par une ClusterRole agrégée, `wb-checks-reseau`) et les nœuds en SSH (`admin`, `sudo -n` pour lire les règles du noyau).

---

## Règles du module

1. **Un changement de Cilium est un changement du cluster entier.** Un `cilium upgrade` redémarre les agents de tous les nœuds ; une erreur dans les *values* peut couper tout le réseau des pods. Toujours : MR relue, aperçu des *values* effectives, puis application, puis `cilium status --wait` et un test de bout en bout. Garde la version précédente du fichier sous la main pour revenir en arrière.
   > ⚠️ **Attention** : ne lance jamais `cilium uninstall` sur `k8s-par1`. Sans CNI, plus aucun pod ne démarre, CoreDNS compris, et tout ce qui a besoin du réseau des pods s'arrête.
2. **Les politiques réseau se testent dans `wb-essais` d'abord.** Une politique `deny` mal placée dans `kube-system`, `cert-manager` ou `passerelles` coupe le DNS ou l'entrée du cluster pour tout le monde. Avant d'appliquer une politique, dis à voix haute quels pods elle **sélectionne** (`kubectl get pods -l …`).
3. **La bordure est partagée.** Les changements côté `gw01`/`gw02` (BGP, pare-feu) passent par le rôle Ansible et la matrice des flux, une passerelle à la fois, jamais par `vtysh` en configuration. Les annonces BGP du cluster sont filtrées par la bordure (10.10.41.0/24 seulement) : n'élargis jamais ce filtre.
4. **Pas de vérification TLS désactivée** (`curl -k`, `insecureSkipVerify`) ni de secret en argument de commande ou dans un manifeste versionné. La racine MédiSphère est installée sur `adm01` : sers-t'en (`--cacert` si besoin).
5. **Journaux de flux et données de santé.** Hubble peut voir des URL et des en-têtes HTTP. Tant que la rédaction des champs sensibles n'est pas en place (M15-E05), n'active pas de visibilité L7 sur les espaces de MédiAgenda.
6. **Mémoire.** Profil k8s : socle v3 (≈ 37 Go) + `k8s-par1` (3 × 4 Go + 3 × 8 Go ≈ 36 Go). `ceph-par1` et les profils lourds du bloc B restent arrêtés. `m15-essai` (4 Go, E19) se crée et se détruit dans la même séance.

---

## Préparer `adm01`

Les outils viennent du module 14. Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 14 46
admin@adm01:~$ kubectl get nodes -o wide
admin@adm01:~$ cilium status --wait
admin@adm01:~$ cilium version
admin@adm01:~$ hubble version
admin@adm01:~$ kubectl -n kube-system get ds kube-proxy cilium
admin@adm01:~$ kubectl get ns wb-essais mediagenda-recette
admin@adm01:~$ cd ~/src/k8s && git pull && ls composants/cilium/values.yaml
```

Le premier contrôle (mini-projet du module 14) doit être vert. Les six nœuds sont `Ready` en 1.36 ; `cilium status` affiche `OK` pour l'agent, l'opérateur et Hubble Relay ; kube-proxy tourne encore (il disparaît en E08). Note la version de l'image de Cilium en cours : c'est `<VERSION-CILIUM>`.

Crée le dossier des brouillons : `mkdir -p ~/m15`.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 15 <XX>`. Elles sont en lecture seule : objets du cluster lus avec le compte `wb-checks`, configuration des nœuds lue en SSH, requêtes HTTP de test vers les NodePort et les adresses publiées, fichiers des projets GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M15-EXX/` : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `ansible/` celle de `plateforme/ansible`, `medisphere/` celle de la documentation, `manifestes/` les objets d'essai de `wb-essais`. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

Palier 1 :

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E08 ─ E07 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E06** — dans l'ordre : chaque exercice réutilise les sondes et l'application `echo` du précédent.
3. **E08 avant E07** — la Gateway API de Cilium 1.20 **exige** le remplacement de kube-proxy (`kubeProxyReplacement: true`) : remplace kube-proxy d'abord, ouvre ta première route ensuite. Les numéros suivent la logique du cours (« qu'est-ce qu'une route » avant « qui la programme ») ; l'ordre de réalisation suit la dépendance technique.
4. **E09** — en dernier : il demande d'avoir pratiqué.

Paliers suivants : l'ordre conseillé est donné en tête de chaque fichier. En résumé : adresses et annonces (E10-E11), puis l'entrée HTTPS complète (Gateway principale, certificats, zone `apps`, noms publiés), le routage avancé, les politiques de MédiAgenda, puis la production (chiffrement, haute disponibilité, supervision, mise à jour), les pannes et le mini-projet.

Durée indicative du palier 1 : 12 à 15 heures.

## Pour aller plus loin

- Le modèle réseau de Kubernetes : <https://kubernetes.io/docs/concepts/services-networking/>
- Services, EndpointSlices, politiques de trafic : <https://kubernetes.io/docs/concepts/services-networking/service/> · <https://kubernetes.io/docs/reference/networking/virtual-ips/>
- DNS des Services et des pods : <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>
- NetworkPolicy : <https://kubernetes.io/docs/concepts/services-networking/network-policies/>
- Documentation de Cilium 1.20 : <https://docs.cilium.io/en/v1.20/> (en particulier « Kubernetes Without kube-proxy », « Gateway API Support », « Network Policy », « Hubble »)
- Gateway API : <https://gateway-api.sigs.k8s.io/>
- Retrait d'ingress-nginx : <https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/>
- *Life of a Packet* (exposés de la communauté Cilium) et le livre *Learning eBPF* (Liz Rice, O'Reilly) pour les mécanismes du noyau.

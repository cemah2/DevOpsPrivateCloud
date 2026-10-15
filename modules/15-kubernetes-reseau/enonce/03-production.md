# Module 15 — Palier 3 : Production

L'entrée du cluster fonctionne : des adresses de service annoncées en BGP, une Gateway `gw-par1` qui sert `*.apps.par1.medisphere.internal` en HTTPS avec un certificat délivré par l'ACME de `ca01`, des noms publiés sans ticket, des politiques réseau dans les espaces de MédiAgenda, et un projet `plateforme/k8s` qui décrit le tout. Mais le trafic entre les nœuds circule en clair sur le VLAN 40, personne ne sait combien de temps l'entrée met à se remettre de la perte d'un nœud ou d'une passerelle, aucune sonde ne regarde le réseau du cluster, Cilium n'a jamais été mis à jour, et l'équipe MédiDoc attend son tour sans savoir si elle pourra voir les bases de MédiAgenda. Sophie Laurent veut du chiffrement, des cloisons et une entrée durcie ; Nadia Roussel veut des chiffres et des alertes ; Claire Morel veut une décision écrite et une plateforme qui publie une application en une heure. Ce palier fait passer le réseau du cluster en production.

> ⚠️ **Rappel** : `k8s-par1` est le cluster de référence de tous les modules suivants. Avant toute intervention qui redémarre les agents Cilium (chiffrement, mise à jour, mode de routage) ou qui touche la bordure (FRR, VRRP) : `cilium status --wait` vert, `lab/bin/check 15 23` vert, une sonde HTTP qui tourne vers `https://mediagenda-recette.apps.par1.medisphere.internal` (E25 la fournit), la version précédente de `composants/cilium/values.yaml` sous la main, et la commande de retour arrière notée. **Une passerelle à la fois**, jamais la passerelle maître pour un essai. Ne lance jamais `cilium uninstall`.

**Chemin imposé** (introduction du module) : tout ce qui configure le cluster passe par `plateforme/k8s` (MR, puis `task appliquer` depuis `~/src/k8s`) ; les réglages de Cilium n'existent que dans `composants/cilium/values.yaml` ; la bordure passe par le rôle `frr` (`group_vars/role_routeur/frr.yml`) et la matrice des flux (`group_vars/role_routeur/pare_feu.yml`) de `plateforme/ansible` ; les sondes vont dans `plateforme/outils` ; la documentation dans `docs/kubernetes/reseau/` de `plateforme/medisphere` (sous-dossiers `adr/` et `runbooks/`), les fiches de changement dans `docs/kubernetes/changements/`.

**Hôtes de ce palier** : `k8s-par1` (`k8s-cp01-03`, `k8s-w01-03`), `gw01`/`gw02`, `lb01`/`lb02`, `adm01`. Aucune nouvelle VM. Espace d'essai de mesure **`wb-perf`** (créé en E24, supprimé en fin de E29). Les images d'essai viennent du cache Harbor (`registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16`).

**Ordre conseillé** : E24 → E29 → E25 → E27 → E26 → E28 → E33 → E31 → E32 → E30 → E34. Les mesures de performance (E29) suivent le chiffrement (E24) sans attendre ; la haute disponibilité (E25) règle le redémarrage en douceur des sessions BGP dont la mise à jour (E27) a besoin ; la segmentation (E28) précède le durcissement (E33) et le chrono (E34), qui s'appuient sur elle ; l'ADR (E30) s'écrit quand tout est mesuré. **Durée totale indicative** : 30 à 36 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 15 XX`).

---

### M15-E24 — Chiffrer le trafic entre nœuds  `LAB` `★★★`

> **Ticket SEC-1624** — *De : Sophie Laurent*
> J'ai fait l'essai avec Karim : un `tcpdump` sur l'interface d'un travailleur, et on lit en clair les requêtes de MédiAgenda vers PostgreSQL quand l'API et la base ne sont pas sur le même nœud. Le VLAN 40 est à nous, mais l'hébergeur HDS nous demandera ce qui protège les données de santé **en transit**, partout, pas seulement à l'entrée.
> Je veux le trafic entre pods chiffré d'un nœud à l'autre, la preuve qu'il l'est, et ce que ça coûte.

**Objectifs pédagogiques**
- Comprendre le chiffrement transparent de Cilium par WireGuard : ce qui est chiffré, ce qui ne l'est pas, où se trouvent les clés.
- L'activer sur un cluster en service, par le fichier de *values*, et en mesurer l'effet (débit, latence, processeur, MTU).
- Prouver le chiffrement par l'observation du réseau, pas par la configuration.

**Prérequis** : M15-E02 (chemin d'un paquet, VXLAN, `tcpdump`), M15-E08 (remplacement de kube-proxy), M15-E23 (réseau du cluster décrit par le code), M14-E20 (`kubectl debug node/`).
**Durée indicative** : 3 h.

**Contexte technique**
- Nœuds : Debian 13 (noyau 6.12, WireGuard intégré au noyau). Cilium 1.20 en tunnel VXLAN (UDP 8472). WireGuard de Cilium écoute en **UDP 51871** sur chaque nœud.
- Les six nœuds sont dans le même VLAN 40 : le trafic entre eux ne traverse pas la bordure. Aucun pare-feu local n'est posé sur les nœuds au module 14.
- Mesure : espace **`wb-perf`** (PSA `baseline`, aucune politique réseau), deux pods de mesure fournis dans [`ressources/E24-mesure-iperf3.yaml`](../ressources/E24-mesure-iperf3.yaml), l'un épinglé sur `k8s-w01`, l'autre sur `k8s-w02`. Garde cet espace jusqu'à la fin de E29.
- Documentation attendue : `docs/kubernetes/reseau/chiffrement.md` de `plateforme/medisphere`.

> ⚠️ **Attention** : (1) l'activation redémarre tous les agents Cilium ; pendant le déploiement, des nœuds chiffrent et d'autres pas encore, et la documentation signale des pertes de paquets à la reconfiguration de l'interface WireGuard : annonce une fenêtre de 15 minutes à Julien et garde ta sonde HTTP ouverte ; (2) le retour arrière consiste à remettre `encryption.enabled: false` dans le fichier et à réappliquer, avec le même redémarrage ; (3) `tcpdump` sur un nœud voit des données de test, jamais de vraies données : ne capture que pendant tes essais, avec un filtre, et supprime les captures.

**Travail demandé**
1. **Lecture.** Dans la documentation de Cilium 1.20 (*WireGuard Transparent Encryption*), relève : comment les clés sont créées et distribuées, ce qui est chiffré dans le mode par défaut et avec `nodeEncryption` (tableau *Which traffic is encrypted*), ce que deviennent les nœuds de contrôle avec `nodeEncryption`, ce qui se passe en mode tunnel (double encapsulation) et l'effet sur la MTU. Compare avec IPsec (gestion des clés, rotation, accélération matérielle) en cinq lignes.
2. **Mesure avant.** Applique le manifeste de mesure. Mesure le débit TCP entre les deux pods (`iperf3`, 30 s, un flux puis quatre flux en parallèle), la latence (`ping` de 100 paquets) et la MTU de l'interface `eth0` des pods. Pendant le débit, relève la charge processeur des deux nœuds (`kubectl top node`, et `top` sur le nœud). Puis prouve le problème de Sophie : sur `k8s-w02`, capture le trafic VXLAN pendant une requête HTTP du pod de `k8s-w01` vers un serveur HTTP du pod de `k8s-w02` (le pod de mesure en sert un, voir le manifeste), et retrouve la requête **en clair** dans la capture.
   ```
   admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- iperf3 -c <IP-POD-B> -t 30
   admin@k8s-w02:~$ sudo tcpdump -ni <INTERFACE-VLAN40> -A -c 40 'udp port 8472'
   ```
   `<IP-POD-B>` : l'adresse du pod `mesure-b` (`kubectl -n wb-perf get pod -o wide`) ; `<INTERFACE-VLAN40>` : l'interface du nœud dans le VLAN 40 (`ip -br address`).
3. **Décision.** Avant de toucher au cluster, décide (et écris dans la fiche) : chiffrement des seuls flux entre pods, ou aussi entre nœuds (`nodeEncryption`, encore en *beta*) ; ce que tu fais des flux entre nœuds de contrôle (etcd, API) ; si tu actives le mode strict en entrée (`encryption.strictMode`, à lire dans le fichier de *values* du chart 1.20) ou non, et pourquoi.
4. **Activation.** Modifie `composants/cilium/values.yaml` par MR, puis applique par le chemin habituel. Vérifie que **tous** les agents ont redémarré avec la nouvelle configuration (âge des pods, `cilium status --wait`) ; s'ils ne l'ont pas fait, c'est un comportement à comprendre (option `rollOutCiliumPods` du chart) avant de forcer le redémarrage.
5. **Preuve.** Dans un agent : `cilium-dbg status | grep Encryption` (nombre de pairs attendu ?) et `cilium-dbg encrypt status`. Sur l'API : l'annotation de clé publique de chaque `CiliumNode`. Sur un nœud : l'interface `cilium_wg0`. Refais la capture de l'étape 2 : que vois-tu maintenant sur le VLAN 40, et sur quel port ? Capture aussi sur `cilium_wg0` d'un nœud et explique pourquoi la requête y apparaît en clair.
6. **Mesure après.** Refais exactement les mesures de l'étape 2. Consigne avant/après dans un tableau (débit 1 et 4 flux, latence, MTU des pods, processeur), avec la réserve qui s'impose (nœuds virtuels sur un seul hyperviseur).
7. **Flux et documentation.** Dis pourquoi aucune règle n'est à ajouter à `pare_feu.yml` pour WireGuard, et ce qui changerait si un nœud était un jour dans un autre VLAN ou sur un autre site. Écris `docs/kubernetes/reseau/chiffrement.md` : décision, mesures, ce qui n'est **pas** chiffré (à l'entrée du cluster, vers la bordure, vers `s3-01`…) et ce qui le protège à la place.

**Critères de réussite**
- [ ] Le chiffrement WireGuard est actif dans la configuration de Cilium et décrit dans `composants/cilium/values.yaml` sur `main` de `plateforme/k8s`.
- [ ] Chaque nœud (six) a publié sa clé publique dans son `CiliumNode` et porte une interface `cilium_wg0`.
- [ ] Une capture sur le VLAN 40 pendant une requête entre pods de nœuds différents ne montre plus que de l'UDP 51871 chiffré.
- [ ] `docs/kubernetes/reseau/chiffrement.md` est sur `main` de `plateforme/medisphere` : décision argumentée, tableau de mesures avant/après, liste de ce qui n'est pas chiffré.
- [ ] Tous les agents Cilium sont prêts et `cilium status` est vert.

**Vérification** : `lab/bin/check 15 24`

<details><summary>Indice 1</summary>

Le chiffrement transparent ne change rien pour les pods : leur adresse, leur route et leur `eth0` restent les mêmes (sauf la MTU). Ce qui change se voit sous le pod : une nouvelle interface sur chaque nœud, des routes qui y envoient le trafic destiné aux pods des autres nœuds, et un port UDP qui écoute. Cherche ces trois choses avant et après.
</details>

<details><summary>Indice 2</summary>

Un fichier de *values* modifié change la ConfigMap `cilium-config` ; un agent ne relit sa configuration qu'au démarrage. Regarde si le chart redémarre les agents tout seul quand la ConfigMap change (une option du chart le décide, désactivée par défaut), et s'il ne le fait pas, fais-le toi-même de la façon qui respecte la stratégie de mise à jour du DaemonSet.
</details>

<details><summary>Indice 3</summary>

En mode tunnel, un paquet entre pods est d'abord encapsulé en VXLAN, puis le paquet VXLAN est confié à WireGuard : chaque couche coûte des octets d'en-tête. Compare la MTU des pods avant et après, et calcule ce que coûte chaque couche (IP + UDP + VXLAN + Ethernet interne pour l'une, IP + UDP + en-tête WireGuard pour l'autre).
</details>

**Pour aller plus loin** (facultatif) : le chiffrement entre nœuds (`nodeEncryption`) et son interaction avec le BGP de la bordure ; IPsec dans Cilium et la rotation de ses clés ; la conformité « tout chiffré » d'un cluster (mTLS applicatif, *service mesh*) ; [WireGuard Transparent Encryption](https://docs.cilium.io/en/v1.20/security/network/encryption-wireguard/), [WireGuard](https://www.wireguard.com/papers/wireguard.pdf).

---

### M15-E25 — Haute disponibilité de l'entrée : perdre un nœud, une passerelle  `LAB` `★★★`

> **Ticket PLAT-1625** — *De : Nadia Roussel* — *Copie : Claire Morel*
> On me dit que l'entrée du cluster est « hautement disponible » parce qu'il y a trois travailleurs et deux passerelles. Je veux des **chiffres** : si un travailleur s'éteint d'un coup, combien de secondes MédiAgenda ne répond plus ? Et si on bascule la bordure sur `gw02` pour une maintenance ? Et quand on mettra Cilium à jour ? Mets les chiffres dans le runbook BGP, avec ce qu'on fait pendant ces secondes-là.

**Objectifs pédagogiques**
- Suivre le chemin d'une requête vers l'adresse de la Gateway : annonces BGP par nœud, multichemin à la bordure, proxy Envoy du nœud qui reçoit.
- Mesurer la convergence après la perte d'un nœud, d'une session BGP, d'une passerelle, et identifier ce qui la détermine (temporisateurs, redémarrage en douceur).
- Régler ces paramètres en connaissant leurs compromis, côté Cilium et côté FRR.
- Comprendre `externalTrafficPolicy` sur un Service `LoadBalancer` annoncé en BGP, et le cas particulier de la Gateway.

**Prérequis** : M15-E10 à E12 (LB IPAM, BGP, `gw-par1`), M07-E16 et E25 (FRR de la bordure, VRRP), RB-071 (bascule de la bordure, M07), M15-E03 (`externalTrafficPolicy`).
**Durée indicative** : 4 h.

**Contexte technique**
- Bordure : `gw01` (maître VRRP, `nopreempt`) et `gw02`, FRR 10.7 AS 65000, groupe `K8S` en écoute sur 10.10.40.0/24 (M07, ouvert en E11) ; les nœuds annoncent les adresses de service en /32. La VIP `.1` de chaque VLAN suit le maître : c'est la table de routage du **maître** qui compte pour `adm01`.
- Cilium : `CiliumBGPClusterConfig` `bgp-par1` (travailleurs portant le label `bgp=par1`, géré par `cluster/noeuds.yaml`) et `CiliumBGPPeerConfig` `bordure` (`composants/cilium/bgp/`), avec les temporisateurs posés en E11 (*hold* 9 s, *keepalive* 3 s) et **sans** redémarrage en douceur. Les deux passerelles sont des pairs de chaque nœud annonceur ; l'annonce `services-lb` couvre toutes les adresses `LoadBalancer`.
- Sonde fournie : [`ressources/E25-sonde-http.sh`](../ressources/E25-sonde-http.sh) — une requête HTTPS toutes les 200 ms depuis `adm01`, horodatée, et le bilan des interruptions. Elle te sert dans tout le palier.
- Service d'essai : un Service `LoadBalancer` `echo-lb` dans `wb-essais` (application `echo` de E03), adresse **demandée** 10.10.41.23 (plage des essais de `lb-par1`, M15-E10).
- Runbook : `docs/kubernetes/reseau/runbooks/RB-152-bgp.md`, créé ici (la fiche `docs/kubernetes/reseau/bgp.md` d'E11 en reste la description ; RB-152 dit quoi faire).

> ⚠️ **Attention** : (1) l'arrêt brutal d'un travailleur (`qm stop` sur `pve01`) le prive de ses pods pendant plusieurs minutes : vérifie avant que MédiAgenda a deux réplicas sur deux nœuds différents et que les PDB le permettent ; (2) **aucun essai sur la passerelle maître** : on arrête FRR sur la passerelle de secours seulement, et la bascule de la bordure se fait par RB-071, aller et retour, hors des fenêtres de sauvegarde ; (3) une modification de FRR passe par le rôle, une passerelle à la fois, la secours d'abord.

**Travail demandé**
1. **Le chemin.** Pour 10.10.41.10 : quels nœuds l'annoncent (`cilium bgp routes advertised ipv4 unicast`, et la raison de ce choix), combien de chemins voit chaque passerelle (`vtysh -c 'show ip bgp 10.10.41.10/32'`), lesquels sont installés dans le noyau (`ip route show 10.10.41.10`) ? Si un seul chemin est installé, trouve pourquoi (multichemin de FRR, valeur par défaut à vérifier sur ta version) et corrige-le dans `frr.yml` pour que la bordure répartisse sur tous les nœuds annonceurs. Explique ce qui se passe ensuite dans le nœud qui reçoit le paquet.
2. **Référence.** Lance la sonde vers `https://mediagenda-recette.apps.par1.medisphere.internal` pendant 5 minutes sans rien toucher : aucune interruption attendue.
3. **Perte brutale d'un travailleur, puis d'un agent.** Sonde lancée, éteins brutalement **un** travailleur annonceur (`qm stop <VMID>` sur `pve01`). Mesure la durée de l'interruption (s'il y en a une) et la proportion de requêtes perdues ; relève dans FRR à quel moment la session tombe et pourquoi à ce moment-là ; calcule ce qu'aurait donné le *hold time* par défaut (lis-le dans la CRD `CiliumBGPPeerConfig`). Rallume le nœud, attends le retour complet (nœud `Ready`, session `Established`, pods revenus). Puis redémarre seulement l'**agent** Cilium d'un travailleur (`kubectl -n kube-system delete pod <AGENT-DU-NŒUD>`) : que voient la bordure et la sonde ?
4. **Redémarrage en douceur.** Lis le *graceful restart* de `CiliumBGPPeerConfig` (CRD `cilium.io/v2`) et ce qu'en fait FRR (aide au redémarrage, active par défaut : à vérifier dans la documentation de FRR 10.7). Il sert le redémarrage d'un agent (mise à jour E27) mais peut desservir la perte d'un nœud : explique comment, choisis un temps de redémarrage, applique par MR, puis refais les deux essais de l'étape 3. Lis les temporisateurs et capacités **appliqués** (statut des `CiliumBGPNodeConfig`, `show bgp neighbors` côté FRR).
5. **La bordure.** (a) Arrête FRR sur **`gw02`** (secours) : effet sur la sonde ? sur les sessions des nœuds ? Avant de le redémarrer, demande à `gw02` où il enverrait un paquet pour 10.10.41.10 (`ip route get`) : la réponse est un problème de sécurité, explique lequel et corrige-le par le rôle `frr` sur les deux passerelles. (b) Bascule la bordure sur `gw02` par RB-071, sonde lancée, puis reviens sur `gw01` : durée de chaque interruption, et pourquoi elle est courte. (c) Raisonne (sans le faire) sur la perte de FRR sur la passerelle **maître** : que se passe-t-il, combien de temps, qui s'en aperçoit (E26), et faut-il que keepalived surveille FRR ? Écris ta décision.
6. **`externalTrafficPolicy`.** Expose `echo` par `echo-lb` en `Cluster`, puis en `Local` avec un seul réplica : quels nœuds annoncent l'adresse dans chaque cas, quelle adresse source voit `echo` (`/clientip` de `agnhost netexec`) ? Pourquoi la Gateway, elle, voit l'adresse du client dans les deux cas (documentation *Ingress and Gateway API reference*, section *Source IP Visibility*) ? Supprime `echo-lb` à la fin.
7. **Runbook.** Complète RB-152 : temps mesurés pour chaque scénario, ce qui les règle, ce que l'astreinte fait pendant et après (commandes de constat côté nœud et côté bordure), et le cas de la passerelle maître.

**Critères de réussite**
- [ ] Sur `gw01` **et** `gw02`, la route vers 10.10.41.10 est installée dans le noyau avec un saut par nœud annonceur (au moins deux).
- [ ] Sur les deux passerelles, une route de rejet (*blackhole*) couvre 10.10.41.0/24, décrite dans `group_vars/role_routeur/frr.yml`.
- [ ] `CiliumBGPPeerConfig` `bordure` porte des temporisateurs explicites (*hold* de 30 s au plus) et le redémarrage en douceur activé ; le *hold time* appliqué aux sessions (statut des `CiliumBGPNodeConfig`) correspond ; toutes les sessions sont `established`.
- [ ] RB-152 est sur `main` de `plateforme/medisphere` avec les temps mesurés de chaque scénario.
- [ ] `echo-lb` n'existe plus.

**Vérification** : `lab/bin/check 15 25`

<details><summary>Indice 1</summary>

Un pair BGP qui disparaît sans rien dire (machine éteinte) n'est déclaré mort qu'à l'expiration du *hold time*, négocié à l'ouverture de la session : c'est la **plus petite** des deux valeurs proposées. Un pair qui ferme proprement sa session (agent redémarré) est retiré tout de suite… sauf si le redémarrage en douceur a été négocié, auquel cas l'autre côté garde ses routes un certain temps.
</details>

<details><summary>Indice 2</summary>

Quand une passerelle n'a plus aucune route BGP vers 10.10.41.0/24, il lui reste sa route par défaut. Où mène-t-elle, et que devient le paquet au passage du NAT de sortie ? Cherche une route qui ne servirait **que** lorsque BGP ne dit rien (pense à la distance administrative), et ce que le rôle `frr` sait déjà écrire.
</details>

<details><summary>Indice 3</summary>

Avec `nopreempt`, une baisse de priorité du maître ne fait pas basculer la bordure : seul un passage en état `FAULT` le fait, et dans le groupe `BORDURE` (M07), c'est **tout** le groupe qui bascule. Pèse ce que coûterait un faux positif de la surveillance de FRR contre ce que coûte une panne de FRR sur le maître.
</details>

**Pour aller plus loin** (facultatif) : BFD (absent du plan de contrôle BGP de Cilium 1.20 : à vérifier) et ce qu'il apporterait ; le réglage `maxUnavailable` du DaemonSet `cilium-envoy` ; la répartition par hachage L4 à la bordure (`fib_multipath_hash_policy`, M07-E14) ; [BGP Control Plane](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/), [FRR BGP Graceful Restart](https://docs.frrouting.org/en/stable-10.7/bgp.html).

---

### M15-E26 — Superviser le réseau du cluster  `LAB` `★★`

> **Ticket PLAT-1626** — *De : Nadia Roussel*
> La semaine dernière, une session BGP est restée tombée une nuit entière sur un nœud : personne ne l'a vu, parce que les deux autres annonçaient l'adresse. Et je n'ai aucun moyen de savoir si un certificat de `*.apps` est sur le point d'expirer, à part attendre qu'il expire.
> Je veux la même chose que pour Ceph : une sonde qui tourne seule, qui alerte, et qui dit en une ligne ce qui ne va pas. Et je veux voir les flux du cluster dans un navigateur, mais pas n'importe qui.

**Objectifs pédagogiques**
- Exposer et lire les métriques de l'agent, de l'opérateur, d'Envoy et de Hubble (sans Prometheus, qui arrive au module 21).
- Publier l'interface de Hubble par la Gateway et la protéger avec ce que la plateforme sait faire aujourd'hui, en connaissant les limites.
- Lire l'état des certificats cert-manager et des sessions BGP dans l'API.
- Écrire une sonde de service `ms-verif-k8s-reseau`, testée, planifiée, branchée sur l'alerte, avec une identité de lecture dédiée.

**Prérequis** : M15-E05 (Hubble), M15-E11 (BGP), M15-E13 à E15 (certificats, noms), M15-E16 (ReferenceGrant), M15-E25 (sessions et temporisateurs), M08-E24 (modèle de sonde `ms-verif-ceph`), M06-E29 (`ms-alerte@`), M14-E06 (compte de service des checks, jeton lié).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Ports de métriques (chart 1.20) : agent **9962** (`prometheus.enabled`, désactivé par défaut), opérateur **9963**, Envoy **9964**, Hubble **9965** (`hubble.metrics.enabled` : une liste, vide par défaut). Ces ports écoutent sur l'adresse des nœuds ; `adm01` (MGMT) les joint.
- Interface de Hubble : `hubble.ui.enabled` ; Service `hubble-ui` (port 80) dans `kube-system` ; nom publié **`hubble.apps.par1.medisphere.internal`** ; route `hubble-ui` dans l'espace `passerelles` (l'espace porte le label d'exposition, il ne reçoit que les routes d'administration de la plateforme).
- Seuls `adm01` (MGMT), le VPN d'administration et la DMZ joignent 10.10.41.0/24 (matrice des flux, E11) ; `lb01`/`lb02` ne relaient vers l'extérieur que les noms listés en E20.
- Identité de la sonde : compte de service **`ms-supervision`** dans un espace **`supervision`** (créé ici, sans pod), ClusterRole de lecture **sans** les Secrets, kubeconfig `~/.config/workbook/k8s-supervision.kubeconfig` (600) sur `adm01`.
- Sonde **`ms-verif-k8s-reseau`** dans `plateforme/outils` : `bin/ms-verif-k8s-reseau`, `etc/ms-verif-k8s-reseau.conf` (installé sous `/usr/local/etc`), tests `tests/bats/ms-verif-k8s-reseau.bats`, unités `ms-verif-k8s-reseau.service` (utilisateur `admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (toutes les 5 minutes, `Persistent=true`). Codes retour : 0 tout va bien, 1 anomalie **ou contrôle impossible**, 2 usage.

> ⚠️ **Attention** : (1) les métriques d'Hubble par flux peuvent porter des noms d'espaces, de pods et, pour certaines familles (HTTP), des chemins d'URL : n'active aucune famille L7 sur les espaces de MédiAgenda (règle 5 de l'introduction) ; (2) l'interface de Hubble montre **tous** les flux du cluster à qui l'ouvre : elle n'est pas publiée tant que sa protection n'est pas en place et vérifiée.

**Travail demandé**
1. **Métriques.** Active les métriques de l'agent et une sélection de familles Hubble (au minimum `dns`, `drop`, `tcp`, `flow`, `icmp`) dans le fichier de *values*, applique, puis depuis `adm01` :
   ```
   admin@adm01:~$ curl -s http://10.10.40.61:9962/metrics | grep -E '^cilium_(drop_count_total|unreachable_nodes|endpoint_state|bpf_map_pressure)' | head -20
   admin@adm01:~$ curl -s http://10.10.40.61:9965/metrics | grep -E '^hubble_(drop_total|flows_processed_total)' | head -20
   ```
   Repère les métriques qui disent : un agent qui ne joint plus d'autres nœuds, des paquets refusés par une politique (et par quelle raison), une table eBPF presque pleine, un point de terminaison en erreur. Cherche s'il existe une métrique de l'état des sessions BGP dans ta version ; sinon, où lire cet état.
2. **Certificats et sessions dans l'API.** Liste les certificats de la plateforme avec leur date d'expiration et leur date de renouvellement prévue (`kubectl get certificate -A`, les champs de `status`, et `cmctl status certificate` si tu installes `cmctl`). Liste l'état de chaque session BGP de chaque nœud (statut des `CiliumBGPNodeConfig`).
3. **L'identité de la sonde.** Crée par le code (`plateforme/k8s`, dossier `rbac/`) l'espace `supervision`, le compte `ms-supervision`, un ClusterRole qui lit exactement ce dont la sonde a besoin (pas de Secrets), et un jeton long par Secret de type `kubernetes.io/service-account-token` (même exception documentée que `wb-checks`). Construis le kubeconfig sur `adm01` et prouve qu'il ne lit pas un Secret.
4. **La sonde.** Écris `ms-verif-k8s-reseau` sur le modèle de `ms-verif-ceph` (bibliothèque `ms-commun.sh`, configuration séparée, aucune valeur en dur). Elle signale au minimum : un agent Cilium ou un Envoy non prêt (DaemonSet incomplet), l'opérateur indisponible ; un nœud dont les métriques sont injoignables ou qui voit des nœuds injoignables ; une session BGP qui n'est pas `established` (nœud et pair dans le message) ; une adresse de la configuration non installée dans la table d'une passerelle (lu par le compte `supervision` des passerelles, M07-E29, ou par `ms-verif-reseau`) ; un Certificate non prêt, ou qui expire dans moins de 10 jours ; un nom publié qui ne résout pas ou ne répond pas en HTTPS avec un certificat valide pour lui. Écris les tests `bats` (sans réseau, outils simulés), au moins un test « rouge » par contrôle.
5. **Planification et alerte.** Installe par `task install:systeme`, crée le service et le timer, puis prouve la chaîne d'alerte : désactive les sessions d'**un** nœud en lui retirant à la main le label `bgp=par1` (geste de test, à noter dans ton journal : `cluster/noeuds.yaml` le remettra au prochain `task etiquettes`), attends le passage de la sonde, constate l'alerte, remets le label par la tâche, vérifie le retour au vert. Note le délai.
6. **Hubble UI, protégée.** Active l'interface dans les *values*. Avant de la publier, pose une politique Cilium sur les pods `hubble-ui` qui n'accepte en entrée que le trafic venant de la Gateway (identité réservée). Puis publie : route `hubble-ui` dans `passerelles`, autorisation de référence dans `kube-system`, nom publié par ExternalDNS. Vérifie : la page s'ouvre depuis `adm01` en HTTPS ; un pod de `wb-essais` n'atteint pas `hubble-ui` directement ; le nom n'est **pas** servi par la VIP des répartiteurs (10.10.70.200). Écris dans `docs/kubernetes/reseau/supervision.md` qui peut voir quoi, et ce qui manque (authentification : module 24).
7. **Astreinte.** Ajoute à `docs/astreinte.md` de `plateforme/outils` une section « Réseau du cluster » : lire le message de la sonde, les trois premières commandes, quand réveiller quelqu'un.

**Critères de réussite**
- [ ] Les métriques de l'agent (9962) et de Hubble (9965) répondent sur chaque travailleur ; les familles Hubble choisies sont décrites dans les *values* sur `main`.
- [ ] `ms-verif-k8s-reseau` est installé sous `/usr/local/bin`, sa configuration sous `/usr/local/etc` ; il rend 0 sur le cluster sain ; une option inconnue donne 2 ; ses tests `bats` sont sur `main` de `plateforme/outils` et passent dans le pipeline.
- [ ] Le timer passe toutes les 5 minutes, le service déclenche `ms-alerte@` en cas d'échec, et une alerte a été reçue pendant le test.
- [ ] Le compte `ms-supervision` existe, ne peut pas lire les Secrets, et son kubeconfig est en 600.
- [ ] `https://hubble.apps.par1.medisphere.internal` répond depuis `adm01` avec un certificat valide ; une politique limite l'entrée des pods `hubble-ui` à la Gateway ; le nom n'est pas servi par 10.10.70.200.

**Vérification** : `lab/bin/check 15 26`

<details><summary>Indice 1</summary>

Une sonde qui interroge l'API doit lire des **statuts**, pas des spécifications : un DaemonSet dit combien de pods sont prévus et combien sont prêts ; un `CiliumBGPNodeConfig` dit l'état de chaque pair ; un `Certificate` dit s'il est prêt et quand il expire. `kubectl get … -o json | jq` suffit, et un `jq` qui renvoie un code d'erreur est plus sûr qu'un `grep` sur un tableau.
</details>

<details><summary>Indice 2</summary>

Une route Gateway API ne peut viser un Service d'un autre espace que si l'espace **cible** l'autorise (`ReferenceGrant`, M15-E16). Pour la politique de `hubble-ui`, relis ce que dit la documentation de Cilium sur l'identité attribuée au trafic qui sort d'Envoy pour une Gateway : c'est elle qu'il faut autoriser, et rien d'autre.
</details>

<details><summary>Indice 3</summary>

Un nœud qui n'est plus sélectionné par `CiliumBGPClusterConfig` `bgp-par1` ferme ses sessions : vérifie pendant le test que l'adresse de la Gateway reste annoncée par les deux autres, et que la sonde voit bien l'écart côté nœuds **et** côté bordure (deux contrôles différents).
</details>

**Pour aller plus loin** (facultatif) : les métriques par contexte de Hubble (`sourceContext`, `destinationContext`) et leur cardinalité ; l'export des flux de Hubble vers un fichier (`hubble.export`) pour le module 22 ; [Monitoring & Metrics](https://docs.cilium.io/en/v1.20/observability/metrics/), [Hubble UI](https://docs.cilium.io/en/v1.20/observability/hubble/hubble-ui/), [cmctl](https://cert-manager.io/docs/reference/cmctl/).

---

### M15-E27 — Mettre à jour Cilium sans coupure  `LAB` `★★★`

> **Ticket CHG-1627** — *De : Karim Benali*
> Cilium a sorti un correctif de la 1.20 avec des corrections de sécurité dans Envoy. On n'a jamais mis à jour le CNI de `k8s-par1`, et ce n'est pas le jour où il y aura une faille critique qu'on apprendra. Je veux une procédure écrite, répétée, avec la vérification avant, la vérification après et le retour arrière **testé**, et je veux savoir ce que les utilisateurs ont vu pendant ce temps.

**Objectifs pédagogiques**
- Suivre la procédure officielle de mise à jour de Cilium : vérification préalable (*pre-flight*), application, contrôle, retour arrière.
- Comprendre ce qui redémarre (agents, opérateur, Envoy), ce qui continue de fonctionner (plan de données eBPF) et ce qui est coupé (proxy L7, sessions BGP).
- Limiter l'impact : stratégie de déploiement du DaemonSet, budget de perturbation de l'opérateur, redémarrage en douceur BGP (E25).

**Prérequis** : M15-E23 (installation par le code), M15-E25 (sonde, redémarrage en douceur), M14-E16 (PDB, déploiements progressifs), M14-E25 (montée de version de Kubernetes, compatibilités), M08-E26 (modèle d'une mise à jour sans interruption).
**Durée indicative** : 3 h.

**Contexte technique**
- Version installée : `<VERSION-CILIUM>` (introduction du module, `cilium version`). Version cible `<VERSION-CIBLE>` : le **dernier correctif 1.20.y publié** (notes de version sur GitHub, `helm search repo cilium/cilium --versions`). Si ta version est déjà la dernière, l'exercice se fait en deux temps : un **retour arrière volontaire** d'un correctif (vers le correctif précédent, à lire dans les notes), puis la montée vers le dernier ; c'est aussi la répétition du retour arrière.
- La CLI `cilium` installe par Helm (release `cilium` dans `kube-system`) : `cilium upgrade` est un `helm upgrade` avec le fichier de *values* du projet.
- Images : par le cache Harbor `quay` (`quay.io` → `registry.par1.medisphere.internal/quay`, `hosts.toml` du M14).
- Runbook : `docs/kubernetes/reseau/runbooks/RB-153-mise-a-jour-cilium.md` ; fiche de changement `docs/kubernetes/changements/CHG-1627.md`.

> ⚠️ **Attention** : (1) ne mets **jamais** à jour un seul composant (agent sans opérateur, ou l'inverse) : la documentation exige la même version partout ; (2) n'utilise pas `--reuse-values` entre deux versions du chart (documentation *Upgrade Guide*) : les *values* viennent du fichier du projet ; (3) le redémarrage d'Envoy coupe les connexions HTTP en cours sur le nœud concerné : préviens Julien et fais-le hors de ses démonstrations ; (4) garde dans un terminal la commande de retour arrière avant de lancer la mise à jour.

**Travail demandé**
1. **Lecture.** Lis le guide de mise à jour de Cilium 1.20 (*Upgrade Guide*, *Upgrade Impact*) et les notes du correctif cible. Réponds : pourquoi la vérification préalable, et ce qu'elle exige en mode sans kube-proxy ; ce qui continue de fonctionner pendant le redémarrage d'un agent et ce qui s'arrête ; à quoi sert `upgradeCompatibility` et s'il te concerne pour un changement de correctif ; ce que dit la matrice de compatibilité de Kubernetes pour `<VERSION-CIBLE>`.
2. **Préparation.** Vérifie la stratégie de déploiement du DaemonSet `cilium` (combien de nœuds à la fois ? est-ce acceptable avec trois travailleurs qui portent l'entrée ?) et celle de `cilium-envoy` ; active le budget de perturbation de l'opérateur (deux réplicas) ; vérifie que le redémarrage en douceur BGP de E25 est actif. Décide la valeur de `maxUnavailable` des deux DaemonSets et écris-la dans le fichier de *values*. Prépare la fiche de changement (fenêtre, impact attendu, critères d'arrêt, retour arrière).
3. **Vérification préalable.** Déploie la vérification préalable de la documentation pour `<VERSION-CIBLE>` (avec l'adresse et le port de l'API, puisque kube-proxy n'est plus là), attends qu'elle soit prête sur tous les nœuds, lis ce qu'elle a vérifié, puis retire-la.
4. **Aperçu.** Compare les *values* effectives actuelles et celles que produirait la mise à jour (option d'aperçu de `cilium upgrade`, à trouver dans `cilium upgrade --help`) : aucune différence inattendue ?
5. **Mise à jour.** Sonde de E25 lancée, et `hubble observe --verdict DROPPED -f` dans un second terminal, applique la mise à jour par MR et par le chemin habituel. Suis le déploiement nœud par nœud. À la fin : `cilium status --wait`, versions de tous les composants, sessions BGP, `cilium connectivity test` (lis d'abord ce qu'il crée et où, et supprime ensuite ce qu'il laisse).
6. **Retour arrière.** Teste-le pour de vrai : `helm history`, retour à la révision précédente (ou à la version précédente par la CLI), contrôles, puis remonte à `<VERSION-CIBLE>` par le code. Mesure chaque étape avec la sonde.
7. **Runbook.** Écris RB-153 : déclencheurs (correctif de sécurité, mineure), lecture des notes, vérification préalable, ordre, contrôles, critères d'arrêt, retour arrière, durées et interruptions **mesurées**, et la règle « Kubernetes d'abord ou Cilium d'abord » pour une montée de Kubernetes (lien avec RB-142).

**Critères de réussite**
- [ ] Agents, opérateur et Envoy tournent tous dans la même version, au moins le dernier correctif 1.20 connu du workbook (1.20.2) ; tous prêts.
- [ ] Il ne reste aucun objet de vérification préalable ni d'espace de test de connectivité.
- [ ] Le budget de perturbation de l'opérateur existe ; `maxUnavailable` des DaemonSets est explicite dans les *values* ; la version cible est écrite dans `plateforme/k8s` (sur `main`).
- [ ] RB-153 et la fiche CHG-1627 sont sur `main` de `plateforme/medisphere`, avec les interruptions mesurées pendant la mise à jour et pendant le retour arrière.

**Vérification** : `lab/bin/check 15 27`

<details><summary>Indice 1</summary>

La vérification préalable n'est pas un test fonctionnel : elle **tire les images** de la nouvelle version sur chaque nœud (un DaemonSet) et vérifie que les politiques existantes sont valides pour la nouvelle version (un Deployment). Sans elle, chaque agent redémarré attend le téléchargement de son image avant de reprendre : c'est là que se perdent des secondes, voire plus si le registre est lent.
</details>

<details><summary>Indice 2</summary>

Pendant le redémarrage d'un agent, le plan de données eBPF reste chargé dans le noyau : les connexions établies et les Services continuent. Ce qui vit dans un **processus** s'arrête : le proxy L7, l'agent BGP (et donc ses sessions), la collecte de Hubble. Relie chacun à ce que tu as vu dans la sonde et dans `hubble observe`.
</details>

<details><summary>Indice 3</summary>

Avec Helm, un retour arrière se fait à une **révision** (`helm history`, `helm rollback`). Mais un retour arrière qui n'est pas dans le code sera défait par la prochaine `task appliquer` : décide ce qui fait foi après un retour arrière, et écris-le dans le runbook.
</details>

**Pour aller plus loin** (facultatif) : la montée de mineure 1.20 → 1.21 (notes « Upgrade Notes », `upgradeCompatibility`, CRD retirées) quand elle sera publiée et compatible avec 1.36 ; les tests de connectivité en continu pendant une mise à jour (`cilium connectivity perf`) ; [Upgrade Guide](https://docs.cilium.io/en/v1.20/operations/upgrade/).

---

### M15-E28 — Segmenter un cluster multi-équipes  `LAB` `★★★`

> **Ticket SEC-1628** — *De : Sophie Laurent* — *Copie : Julien Petit*
> MédiDoc arrive sur le cluster (`medidoc-dev`). Ce qui me fait peur : les politiques de MédiAgenda sont écrites par espace, et il suffit d'une politique trop large dans un espace pour qu'un pod de `mediagenda-dev` atteigne la base de `mediagenda-recette`, ou qu'un pod de MédiDoc parle à MédiAgenda. Et aujourd'hui, une fois le DNS autorisé, on ne sait pas vraiment vers où les pods sortent sur Internet.
> Je veux des cloisons que **personne** ne peut ouvrir depuis un espace d'équipe, et une sortie vers Internet limitée à des noms précis.

**Objectifs pédagogiques**
- Utiliser `CiliumClusterwideNetworkPolicy` pour des règles de plateforme qui s'appliquent à tous les espaces d'équipe.
- Comprendre comment Cilium combine les politiques (union des autorisations, priorité des refus, entrée en refus par défaut, `enableDefaultDeny`) et s'en servir pour des cloisons qui ne s'ouvrent pas.
- Contrôler la sortie vers Internet par noms DNS (`toFQDNs`) et comprendre le rôle du proxy DNS de Cilium.

**Prérequis** : M15-E06 (NetworkPolicy), M15-E17 (politiques de MédiAgenda, CiliumNetworkPolicy L7, `toFQDNs`), M15-E05 (Hubble), M14-E11 (RBAC des équipes), M14-E33 (espace `medidoc-dev`).
**Durée indicative** : 4 h.

**Contexte technique**
- Équipes et espaces : `mediagenda` → `mediagenda-dev`, `mediagenda-recette` ; `medidoc` → `medidoc-dev`. Chaque espace d'équipe porte le label **`medisphere.internal/equipe: <équipe>`**, posé par le code de `plateforme/k8s` depuis le M14 (E10, E33) et déjà utilisé par l'admission (M14-E18) : c'est la seule source de l'appartenance à une équipe, ne crée pas d'autre label.
- Règles de Sophie (SEC-1628) :
  1. aucun pod d'un espace d'équipe ne reçoit de connexion d'un pod d'un **autre** espace d'équipe, ni n'en ouvre vers lui — même entre deux espaces de la même équipe (le développement ne touche jamais la recette) ;
  2. cette règle ne peut pas être levée par une politique posée dans un espace d'équipe ;
  3. la sortie vers Internet des pods de MédiAgenda est limitée à l'API publique des jours fériés, **`calendrier.api.gouv.fr`** (HTTPS), utilisée par la prise de rendez-vous ; MédiDoc ne sort pas sur Internet ;
  4. les composants de plateforme (`kube-system`, `passerelles`, `cert-manager`, `external-dns`, `supervision`) ne sont pas concernés par la règle 1.
- Les politiques de plateforme vivent dans `plateforme/k8s`, `composants/reseau/politiques/`. Les équipes n'ont pas le droit d'écrire des politiques Cilium (RBAC du M14 : à vérifier).
- Documentation : `docs/kubernetes/reseau/segmentation.md`.

> ⚠️ **Attention** : une `CiliumClusterwideNetworkPolicy` s'applique à tout le cluster. Une politique dont la section `ingress` ou `egress` sélectionne trop large met ces pods en **refus par défaut** dans cette direction : `kube-system`, CoreDNS, la Gateway ou cert-manager peuvent s'arrêter de fonctionner pour tout le monde. Avant chaque application : liste les pods sélectionnés, applique d'abord à `wb-essais` (copie de la politique restreinte à cet espace), garde `kubectl delete ccnp <NOM>` prêt, et sonde lancée.

**Travail demandé**
1. **Lecture.** Dans la documentation de Cilium 1.20 (*Policy Enforcement Modes*, *Endpoint default policy*, *Layer 3 Examples*, *Deny Policies*, *DNS based*), réponds : quand un pod passe-t-il en refus par défaut, et qu'est-ce que `enableDefaultDeny` change ? Qu'est-ce qui l'emporte entre une autorisation et un refus ? Comment sélectionner les pods d'un espace par les **labels de l'espace** ? Comment fonctionne `toFQDNs` (qui résout, qui apprend les adresses, combien de temps) et pourquoi il faut une règle DNS L7 ?
2. **Labels.** Vérifie que les trois espaces portent le label d'équipe (dans le cluster **et** dans `espaces/` sur `main`), et qu'aucun espace de plateforme ni d'essai ne le porte : tes cloisons vont s'y fier.
3. **Proxy DNS de base.** Écris une politique de cluster qui fait passer les requêtes DNS de tous les pods (hors `kube-system`) par le proxy DNS de Cilium, **sans** mettre aucun pod en refus par défaut. Vérifie dans Hubble que les requêtes DNS de `mediagenda-recette` apparaissent avec le nom demandé.
4. **Cloisons.** Écris les politiques de cluster qui appliquent les règles 1 et 2 aux trois espaces d'équipe. Elles ne doivent changer **que** cela : aucun flux autorisé aujourd'hui à l'intérieur d'un espace, depuis la Gateway ou vers le DNS ne doit tomber (sonde de E25 lancée).
5. **Preuve.** Construis une matrice de tests (source × destination × attendu × obtenu) avec des pods de sonde `netshoot` : `mediagenda-dev` → PostgreSQL de `mediagenda-recette` ; `medidoc-dev` → API de `mediagenda-recette` ; `mediagenda-recette` → son propre PostgreSQL ; Gateway → API ; `wb-essais` → API de `mediagenda-recette`. Puis la preuve de la règle 2 : pose **temporairement** dans `mediagenda-recette` une politique qui autorise toute entrée, constate que `mediagenda-dev` n'entre toujours pas, et retire-la. Lis les refus dans Hubble (raison affichée).
6. **Sortie vers Internet.** Écris la politique de sortie de MédiAgenda (règle 3). Depuis un pod de `mediagenda-recette` : `calendrier.api.gouv.fr` répond, un autre nom (`example.com`) non, une adresse IP en dur non plus. Explique ce qui se passe si l'API publique change d'adresse, et ce que deviennent les connexions ouvertes quand l'enregistrement DNS expire.
7. **Documentation.** `docs/kubernetes/reseau/segmentation.md` : les règles, les politiques qui les portent, la matrice de tests, comment une nouvelle équipe est ajoutée (une MR), et les limites (ce qui n'est pas couvert : trafic du réseau de l'hôte, pods `hostNetwork`, flux vers la bordure).

**Critères de réussite**
- [ ] Les trois espaces d'équipe portent le label `medisphere.internal/equipe` ; les politiques de cluster sont sur `main` de `plateforme/k8s` (`composants/reseau/politiques/`).
- [ ] Une politique de cluster fait passer le DNS de tous les pods par le proxy, sans refus par défaut.
- [ ] Chaque espace d'équipe est couvert par des règles de **refus** en entrée et en sortie vers les autres espaces d'équipe ; aucune politique « tout autoriser » de test ne reste.
- [ ] La sortie de MédiAgenda vers Internet est limitée par `toFQDNs` à `calendrier.api.gouv.fr`.
- [ ] `docs/kubernetes/reseau/segmentation.md` est sur `main`, avec la matrice de tests remplie.

**Vérification** : `lab/bin/check 15 28`

<details><summary>Indice 1</summary>

Les politiques Cilium s'additionnent : une autorisation de plus ouvre, elle ne ferme jamais. Une cloison qui doit résister à une autorisation posée ailleurs ne peut donc pas être une autorisation : relis la section sur les politiques de **refus** et leur priorité.
</details>

<details><summary>Indice 2</summary>

Cilium expose les labels de l'espace d'un pod comme des labels du pod, avec un préfixe (`io.cilium.k8s.namespace.labels.`) ; et le nom de l'espace sous `io.kubernetes.pod.namespace`. Avec `matchExpressions`, tu peux dire « un pod d'un espace qui porte un label d'équipe **et** qui n'est pas mon espace ». Une seule politique générique ne peut pas dire « mon espace » : une politique par espace, générée par le code, le peut.
</details>

<details><summary>Indice 3</summary>

`toFQDNs` ne connaît que les noms **résolus à travers le proxy DNS** de Cilium : sans règle DNS L7 sur le chemin vers CoreDNS, la politique ne voit jamais la réponse et ne peut rien autoriser. Une politique de base qui intercepte le DNS sans rien refuser existe dans la documentation (`enableDefaultDeny`).
</details>

**Pour aller plus loin** (facultatif) : l'**Egress Gateway** de Cilium (sortie vers Internet par un nœud et une adresse source fixes, que le partenaire peut filtrer) et ses prérequis (`bpf.masquerade`, remplacement de kube-proxy) ; le mode d'application `always` (`policyEnforcementMode`) et ce qu'il casserait ; les politiques de nœud (`nodeSelector`, pare-feu de l'hôte) ; [Deny policies](https://docs.cilium.io/en/v1.20/security/policy/language/#deny-policies), [DNS based](https://docs.cilium.io/en/v1.20/security/policy/language/#dns-based), [Egress Gateway](https://docs.cilium.io/en/v1.20/network/egress-gateway/egress-gateway/).

---

### M15-E29 — Mesurer les performances réseau  `LAB` `★★★`

> **Ticket PLAT-1629** — *De : Claire Morel*
> Karim pense qu'on paie cher le tunnel VXLAN plus le chiffrement, et qu'il faudrait passer en routage natif puisque tous les nœuds sont sur le même VLAN. Julien voudrait savoir ce qu'il peut attendre entre son API et sa base. Moi, je veux des chiffres reproductibles avant l'ADR, pas des impressions.

**Objectifs pédagogiques**
- Mesurer proprement débit, latence et taux de requêtes entre pods (méthode, répétitions, conditions, réserves).
- Comparer le mode tunnel VXLAN et le routage natif de Cilium sur le même cluster, chiffrement compris, et comprendre ce que le routage natif exige du réseau.
- Relier les résultats à la MTU, au processeur et à la topologie du lab.

**Prérequis** : M15-E24 (mesures, WireGuard, `wb-perf`), M15-E02 (VXLAN, routes), M07-E15 (MTU), M08-E28 (méthode de mesure et ses réserves).
**Durée indicative** : 4 h.

**Contexte technique**
- Pods de mesure de E24 (espace `wb-perf`, `k8s-w01` et `k8s-w02`). `iperf3` est dans l'image ; `netperf`, s'il n'y est pas, se remplace par des requêtes HTTP courtes chronométrées (`curl -w`).
- Routage natif de Cilium : `routingMode: native`, `ipv4NativeRoutingCIDR` (la plage des pods), et soit des routes vers les plages des autres nœuds posées par Cilium (`autoDirectNodeRoutes`, nœuds dans le même domaine L2), soit un routeur qui les connaît.
- L'essai en routage natif se fait sur `k8s-par1`, dans une fenêtre annoncée, et **le cluster revient en VXLAN à la fin** : la décision est l'objet de l'ADR (E30).
- Documentation : `docs/kubernetes/reseau/performances.md`.

> ⚠️ **Attention** : changer le mode de routage redémarre tous les agents ; pendant le déploiement, un nœud passé en natif et un nœud encore en tunnel ne se comprennent plus : **les flux entre pods de ces deux nœuds sont coupés** jusqu'à la fin du déploiement. Annonce une fenêtre de 30 minutes, fais l'aller et le retour dans la même fenêtre, sonde lancée, et garde le fichier de *values* d'origine à portée de main. Sur `pve01`, aucune autre charge lourde pendant les mesures (`ceph-par1` arrêté).

**Travail demandé**
1. **Méthode.** Écris d'abord le protocole dans la fiche : grandeurs mesurées (débit TCP 1 et 4 flux, débit UDP à débit imposé et pertes, latence au repos, latence sous charge, requêtes HTTP courtes par seconde), durée et nombre de répétitions, ce qui doit être identique entre deux séries, comment tu présentes la dispersion. Mesure aussi **une référence sans Kubernetes** : `iperf3` entre `k8s-w01` et `k8s-w02` en direct, sur leurs adresses du VLAN 40.
2. **Série A — VXLAN + WireGuard** (l'état actuel) : toutes les grandeurs, pods sur deux nœuds différents ; puis la même chose avec les deux pods sur **le même** nœud. Relève la MTU des pods et la charge processeur.
3. **MTU.** Prouve la MTU utile de bout en bout entre deux pods de nœuds différents (`ping -M do -s <TAILLE>` en cherchant la plus grande taille qui passe) et explique la valeur trouvée par l'empilement des en-têtes. Que se passerait-il si un nœud avait une MTU différente des autres ?
4. **Série B — routage natif + WireGuard.** Prépare le fichier de *values* (MR en brouillon, non fusionnée), vérifie ce que le routage natif exige (adresses des pods qui sortent du cluster : masquage), applique dans la fenêtre, vérifie (`cilium-dbg status`, routes vers les plages des autres nœuds sur un nœud, MTU des pods), mesure la série complète, puis **reviens en VXLAN** par le fichier d'origine et vérifie le retour (`cilium status`, sonde, BGP, chiffrement).
5. **Facultatif — BBR.** Lis ce qu'exigent `bandwidthManager.enabled` et `bandwidthManager.bbr` dans le chart 1.20, et pour quels flux BBR aide (lien long, pertes) ; dis s'il a un intérêt dans le lab. Ne l'active que si tu as le temps de refaire une série complète.
6. **Résultats.** `docs/kubernetes/reseau/performances.md` : protocole, tableau des séries (moyenne et dispersion), écarts relatifs à la référence, explication de chaque écart (encapsulation, chiffrement, copies, processeur), réserves (un seul hyperviseur, pas de vraie carte réseau, nœuds virtuels), et ce que tu recommandes **pour l'ADR**. Supprime l'espace `wb-perf`.

**Critères de réussite**
- [ ] Le cluster est revenu au mode tunnel VXLAN avec le chiffrement WireGuard actif, tous les agents prêts ; les *values* sur `main` décrivent cet état.
- [ ] `docs/kubernetes/reseau/performances.md` est sur `main` : protocole, référence sans Kubernetes, séries A et B, MTU mesurée et expliquée, réserves, recommandation.
- [ ] L'espace `wb-perf` n'existe plus.

**Vérification** : `lab/bin/check 15 29`

<details><summary>Indice 1</summary>

Sur un seul hyperviseur, deux VMs « sur le réseau » échangent en réalité par la mémoire de `pve01` à travers un pont Linux : la référence sans Kubernetes est donc probablement bien plus haute qu'un vrai lien 1 Gbit/s, et c'est le **processeur** qui limite. Une différence entre deux modes se lit alors davantage dans la charge processeur que dans le débit seul.
</details>

<details><summary>Indice 2</summary>

En routage natif, un paquet de pod sort du nœud avec l'adresse du pod comme source : il faut que le nœud de destination ait une route vers la plage de l'émetteur (les routes directes entre nœuds le font si tous les nœuds partagent le même réseau L2), et que ce qui sort **vers l'extérieur** du cluster soit encore masqué derrière l'adresse du nœud. Relis la page *Routing* de la documentation et ce que vaut `ipv4NativeRoutingCIDR`.
</details>

**Pour aller plus loin** (facultatif) : `cilium connectivity perf` ; netkit à la place des paires veth (noyau ≥ 6.8, à vérifier pour Cilium 1.20) ; le mode XDP de l'équilibrage de charge ; [Routing](https://docs.cilium.io/en/v1.20/network/concepts/routing/), [Bandwidth Manager](https://docs.cilium.io/en/v1.20/network/kubernetes/bandwidth-manager/), [Tuning Guide](https://docs.cilium.io/en/v1.20/operations/performance/tuning/).

---

### M15-E30 — ADR : le réseau et l'entrée de `k8s-par1`  `RED` `★★`

> **Ticket PLAT-1630** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Le comité d'architecture veut une décision écrite sur le réseau du cluster avant d'y mettre la production : pourquoi Cilium, pourquoi la Gateway API et pas un contrôleur Ingress, pourquoi du BGP plutôt que de l'ARP, pourquoi un tunnel alors que Karim veut du routage natif, et ce que coûtent nos choix de sécurité. Écris l'ADR-0150 avec les chiffres que tu as mesurés.

**Objectifs pédagogiques**
- Structurer une décision d'architecture qui en regroupe plusieurs liées (CNI, entrée, annonce des adresses, mode de routage, chiffrement, certificats et noms).
- Appuyer chaque option sur des faits **mesurés ou vérifiés** dans le module.
- Écrire les conséquences négatives et les conditions qui feraient revoir la décision.

**Prérequis** : tout le module jusqu'ici, en particulier M15-E08 (kube-proxy), E11 (BGP), E12 (Gateway), E18 (migration ingress-nginx), E19 (MetalLB), E24 (chiffrement), E25 (convergence), E29 (performances).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/kubernetes/reseau/adr/ADR-0150-reseau-entree-cluster.md` (gabarit MADR de M00-E33, trois pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Poser le **contexte** : un cluster kubeadm sur un seul site, VLAN 40 et 41, bordure FRR en VRRP, répartiteurs en DMZ, données de santé, une petite équipe, ingress-nginx retiré par son projet, l'écosystème des versions (Cilium 1.20, Gateway API v1.6).
2. Lister les **décisions** couvertes et, pour chacune, les **options** réellement envisagées : CNI (Cilium, et au moins une autre) ; Services (kube-proxy iptables/nftables ou remplacement eBPF) ; entrée (Gateway API de Cilium, un autre contrôleur Gateway API, ingress-nginx figé) ; annonce des adresses (BGP de Cilium, annonces L2 de Cilium, MetalLB) ; mode de routage (VXLAN, natif) ; chiffrement (aucun, WireGuard, IPsec) ; certificats et noms (cert-manager + ACME interne, ExternalDNS RFC 2136, ou à la main).
3. Pour chaque décision, des **critères** explicites (sécurité, exploitation, dépendance à la bordure, performance mesurée, maturité, compétences) et un **fait** à l'appui par option (exercice, mesure, page de documentation).
4. **Trancher**, en disant ce que chaque choix coûte (mémoire d'Envoy sur chaque nœud, dépendance à un seul projet, convergence BGP mesurée, perte de débit mesurée…).
5. Les **conséquences** et actions rattachées à un module (supervision M21, authentification de Hubble M24, politiques d'admission M26, montée 1.21, chiffrement de bout en bout…), et les **conditions de révision** (par exemple : second site, vraie fabric de commutateurs, mesure de E29 qui changerait d'ordre de grandeur).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en trois pages, et couvre au moins les sept décisions listées.
- [ ] Chaque option rejetée l'est pour une raison vérifiable ; les chiffres cités sont ceux de E24, E25 et E29.
- [ ] Les conséquences négatives et les conditions de révision sont écrites, avec des actions rattachées à un module.
- [ ] L'ADR est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Plusieurs décisions sont **liées** : la Gateway API de Cilium exige le remplacement de kube-proxy ; les annonces L2 n'auraient pas besoin de la bordure mais ne répartissent pas le trafic ; le routage natif sans BGP des plages de pods suppose un seul domaine L2. Écris ces dépendances : elles empêchent de changer une décision sans revoir les autres.
</details>

<details><summary>Indice 2</summary>

Une option « figée mais qui marche » (ingress-nginx 1.15.1) n'est pas fausse par principe : dis précisément ce qui la rend inacceptable **ici** (correctifs de sécurité, données de santé, durée de vie du cluster), et ce qui la rendrait acceptable ailleurs (cluster jetable, isolé).
</details>

**Pour aller plus loin** (facultatif) : une décision sur le maillage de services (*service mesh*) et le mTLS entre applications, à revoir après le module 24 ; [Gateway API implementations](https://gateway-api.sigs.k8s.io/implementations/).

---

### M15-E31 — Questions de production : réseau Kubernetes  `Q` `★★★`

> **Ticket PLAT-1631** — *De : Karim Benali*
> Avant de te confier l'astreinte sur le réseau de `k8s-par1`, je veux t'entendre sur ces questions. Argumente, chiffre quand tu peux, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production du réseau du cluster : chiffrement, haute disponibilité, mise à jour, politiques, entrée, DNS.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M15-E24 à E29.
**Durée indicative** : 1 h 30.

**Questions**

1. Le chiffrement WireGuard de Cilium est actif dans son mode par défaut. Parmi ces flux, lesquels traversent le VLAN 40 **en clair** : un pod de `k8s-w01` vers un pod de `k8s-w02` ; le kubelet de `k8s-w01` vers un pod de `k8s-w02` (sonde) ; un client de `adm01` vers la Gateway, puis Envoy vers un pod d'un autre nœud ; un pod vers `s3-01` ; etcd entre les nœuds de contrôle ? Pour chacun, qu'est-ce qui le protège (ou pas) ?
2. QCM — Un nœud redémarre et régénère sa clé WireGuard. Que se passe-t-il ?
   a) plus aucun pod du nœud ne joint les autres tant qu'un administrateur n'a pas copié la clé ;
   b) l'agent publie sa nouvelle clé publique dans son `CiliumNode`, les autres agents la reprennent, des paquets peuvent se perdre pendant la transition ;
   c) rien, la clé est dérivée du nom du nœud et ne change jamais ;
   d) le nœud repasse en clair jusqu'au prochain redémarrage des autres agents.
   Justifie, et dis pourquoi `nodeEncryption` exclut par défaut les nœuds de contrôle.
3. La bordure reçoit 10.10.41.10/32 de trois travailleurs et répartit en multichemin. Un travailleur s'éteint brutalement. Combien de temps, avec les temporisateurs par défaut de Cilium et de FRR, une partie des requêtes est-elle perdue ? Quelle proportion ? Pourquoi les connexions TCP établies vers ce nœud ne survivent-elles pas, même une fois la route retirée ?
4. Le redémarrage en douceur BGP est actif avec un temps de redémarrage de 120 s. Un travailleur s'éteint brutalement. Que fait FRR de ses routes, et pendant combien de temps ? Qu'aurais-tu dû régler en même temps que le redémarrage en douceur ?
5. QCM — Pendant la mise à jour de Cilium, l'agent de `k8s-w02` redémarre. Qu'est-ce qui continue de fonctionner sur ce nœud ?
   a) rien : le réseau des pods est coupé jusqu'au retour de l'agent ;
   b) les flux déjà établis et les Services (plan de données eBPF), mais pas l'application des nouvelles politiques, ni les sessions BGP (sauf redémarrage en douceur), ni la collecte de Hubble ;
   c) tout, y compris le proxy L7, qui est un processus séparé ;
   d) seulement le DNS, servi par l'agent.
   Justifie, et dis ce que change le fait qu'Envoy tourne dans son propre DaemonSet.
6. Pourquoi la documentation demande-t-elle de ne jamais mettre à jour l'agent sans l'opérateur ? Donne un exemple de ce qui peut mal tourner.
7. Une `CiliumClusterwideNetworkPolicy` sélectionne `endpointSelector: {}` et n'a qu'une section `egress` qui autorise le DNS vers `kube-dns`. Que vient-il de se passer dans le cluster ? Comment l'éviter tout en interceptant le DNS ?
8. QCM — Dans `mediagenda-recette`, une CiliumNetworkPolicy autorise l'entrée depuis tous les espaces. Une CiliumClusterwideNetworkPolicy refuse l'entrée depuis `mediagenda-dev`. Un pod de `mediagenda-dev` se connecte à l'API de recette :
   a) la connexion passe, la politique la plus spécifique (celle de l'espace) l'emporte ;
   b) la connexion est refusée, un refus l'emporte toujours sur une autorisation ;
   c) la connexion passe, les politiques d'espace sont prioritaires sur celles du cluster ;
   d) le résultat dépend de l'ordre de création des politiques.
   Justifie, puis dis ce qui empêcherait une équipe de **supprimer** la politique de cluster.
9. La politique `toFQDNs` de MédiAgenda autorise `calendrier.api.gouv.fr`. Le pod met en cache la résolution DNS dans son application pendant une heure, alors que l'enregistrement a un TTL de 60 s. Que se passe-t-il au bout de quelques minutes ? Quel réglage de Cilium intervient, et quelle est la bonne correction ?
10. Un développeur demande d'autoriser `*.amazonaws.com` en sortie « pour le SDK ». Que réponds-tu, et que proposes-tu à la place ?
11. QCM — La Gateway `gw-par1` a `externalTrafficPolicy: Cluster`. Quelle adresse source voit l'API de MédiAgenda dans l'en-tête `X-Forwarded-For` pour une requête de `adm01` ?
    a) l'adresse du nœud qui a reçu le paquet, à cause du masquage ;
    b) 10.10.10.10 : Cilium remet le trafic à l'Envoy local par TPROXY sans changer l'adresse source ;
    c) l'adresse de la VIP de la bordure ;
    d) aucune, l'en-tête n'est pas posé par Envoy.
    Justifie, et dis ce qui change pour une `TLSRoute` en *passthrough*.
12. Cilium 1.20 ignore les options TLS d'un écouteur de Gateway et ne sait pas valider un certificat client à l'entrée (E33). Quelles sont les options pour exiger un certificat client d'un partenaire, et leurs compromis ?
13. Le routage natif a donné 15 % de débit en plus en E29. Pourquoi n'est-ce pas, à lui seul, une raison de l'adopter chez MédiSphère ? Qu'est-ce qui changerait la réponse ?
14. Le cluster compte trois travailleurs ; demain il en aura quinze. Qu'est-ce qui change pour la bordure (sessions BGP, `bgp listen limit`, nombre de chemins), pour WireGuard (nombre de pairs) et pour le DNS (CoreDNS) ? Que faudrait-il prévoir ?
15. Hubble est publié sur `hubble.apps…` sans authentification, protégé par le réseau. Énumère qui peut le voir aujourd'hui, ce qu'il y voit, et ce que tu changerais en premier.
16. L'auditeur demande la preuve que « les flux entre environnements sont interdits ». Quelles preuves peux-tu fournir (configuration, tests, journaux), et lesquelles valent mieux que les autres ?

Les réponses argumentées sont dans le corrigé.

---

### M15-E32 — La matrice des flux du cluster  `RED` `★★`

> **Ticket SEC-1632** — *De : Sophie Laurent*
> La matrice des flux de la bordure (`docs/socle/matrice-flux.md`) s'arrête à la porte du cluster. L'auditeur HDS voudra savoir qui parle à qui **dans** `k8s-par1`, par quel port, pourquoi, et ce qui l'impose. Je veux la matrice des flux du cluster, rattachée aux politiques qui la font respecter, et à jour.

**Objectifs pédagogiques**
- Inventorier les flux d'un cluster Kubernetes : plan de contrôle, nœuds, CNI, entrée, applications, sorties.
- Rattacher chaque flux à ce qui l'autorise ou le refuse (politique réseau, politique de cluster, matrice de la bordure) et à un besoin.
- Vérifier l'inventaire contre l'observation (Hubble) plutôt que contre la mémoire.

**Prérequis** : M15-E06, E17, E28 (politiques), E05 et E26 (Hubble), M14-E09 (architecture), M07-E30 (matrice de la bordure v2), M15-E24 (WireGuard).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/kubernetes/reseau/matrice-flux-cluster.md` dans `plateforme/medisphere`, par MR. Elle doit au minimum :
1. Couvrir quatre familles : **plan de contrôle et nœuds** (API, etcd, kubelet, keepalived/HAProxy de la VIP, SSH) ; **réseau du cluster** (VXLAN, WireGuard, santé de Cilium, Hubble relay, métriques) ; **entrée et sortie** (bordure → Gateway, Gateway → applications, BGP, RFC 2136, ACME, registre, `s3-01`, Internet par noms) ; **applications** (MédiAgenda : API, PostgreSQL, Valkey ; MédiDoc ; DNS).
2. Pour chaque flux : source, destination, protocole et port, chiffré ou non, besoin (pourquoi), ce qui l'autorise (nom de la politique, ligne de `pare_feu.yml`, ou « même VLAN, non filtré »), exercice d'origine.
3. Lister les flux **refusés exprès** qui comptent (entre environnements, MédiDoc → MédiAgenda, sortie Internet hors liste, accès direct à `hubble-ui`) et la politique qui les refuse.
4. Décrire la **vérification** : comment tu as confronté la matrice aux flux réels (requêtes Hubble utilisées, période), les écarts trouvés et leur traitement (flux inconnu → ticket ou politique).
5. Dire comment la matrice reste à jour (qui la modifie, à quelle occasion, lien avec les MR de `plateforme/k8s`).

**Critères de réussite**
- [ ] Les quatre familles sont couvertes ; chaque ligne a sa source, sa destination, son port, son besoin et ce qui l'autorise.
- [ ] Les flux refusés exprès sont listés avec la politique qui les refuse.
- [ ] La section de vérification cite des requêtes Hubble réelles et au moins un écart traité.
- [ ] Le document est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

`hubble observe` filtre par espace, par verdict, par port et par identité (`--from-namespace`, `--to-identity`, `--verdict`, `--port`…), et sait sortir du JSON : quelques minutes de flux d'un espace, réduits à « source → destination:port » et dédupliqués, font un bon premier jet de matrice. Ce qui n'apparaît pas (réseau de l'hôte, flux entre nœuds de contrôle) se complète par la documentation de kubeadm et de Cilium.
</details>

<details><summary>Indice 2</summary>

Une ligne « autorisé par : `refus-par-defaut` » ne veut rien dire : une politique de refus par défaut n'autorise rien. Nomme la politique qui **autorise** chaque flux ; si tu n'en trouves pas et que le flux passe, tu viens de trouver un écart.
</details>

**Pour aller plus loin** (facultatif) : générer la partie « applications » de la matrice à partir des politiques versionnées (script dans `plateforme/outils`) pour qu'elle ne puisse plus diverger ; l'éditeur de politiques de Cilium (*Network Policy Editor*) pour visualiser.

---

### M15-E33 — Durcir l'entrée : TLS, en-têtes et authentification mutuelle  `LAB` `★★★`

> **Ticket SEC-1633** — *De : Sophie Laurent* — *Copie : Julien Petit*
> Le test d'intrusion de l'an dernier sur l'ancienne plateforme avait trois remarques sur l'entrée : versions de TLS anciennes acceptées, pas de HSTS, et l'API des **centres partenaires** (les logiciels de cabinets qui prennent des rendez-vous chez nous) protégée par une simple clé dans l'URL. Je veux l'entrée de `k8s-par1` irréprochable sur les deux premiers points, et pour les partenaires, un **certificat client** obligatoire.

**Objectifs pédagogiques**
- Évaluer la configuration TLS réelle d'une Gateway (protocoles, suites, chaîne) par l'observation.
- Ajouter des en-têtes de sécurité (HSTS et autres) par les filtres de la Gateway API.
- Savoir ce que l'implémentation Gateway API de Cilium 1.20 supporte vraiment (options TLS des écouteurs, validation des certificats clients, `BackendTLSPolicy`) et contourner ce qui manque proprement : authentification mutuelle par TLS *passthrough* vers un relais applicatif.

**Prérequis** : M15-E12 (`gw-par1`, TLS), M15-E13/E14 (cert-manager, DNS-01), M15-E15 (ExternalDNS, source `service`), M15-E16 (TLSRoute, ReferenceGrant), M15-E17 et E28 (politiques), M06 (step CLI).
**Durée indicative** : 4 h.

**Contexte technique**
- Cible TLS (politique M06-E33) : TLS 1.2 et 1.3 seulement, suites à confidentialité persistante, chaîne complète vers la racine MédiSphère.
- En-têtes demandés sur toutes les réponses HTTPS de MédiAgenda : `Strict-Transport-Security` (un an, sous-domaines), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`.
- Partenaires : nom **`mediagenda-partenaires.apps.par1.medisphere.internal`**, servi par une Gateway distincte **`gw-partenaires`** (espace `passerelles`, adresse **10.10.41.11**, écouteur TLS *passthrough* sur 443) ; le TLS est terminé par un relais **`relais-mtls`** (nginx non privilégié, `registry.par1.medisphere.internal/dockerhub/nginxinc/nginx-unprivileged:1.30-alpine`) dans `mediagenda-recette`, qui exige un certificat client et transmet à l'API. Certificat serveur du relais : cert-manager, ClusterIssuer `step-ca-acme`. Certificats clients : une petite autorité **« MédiSphère Partenaires »** dédiée, créée avec `step` sur `adm01` (clé privée en Vault `critique`, copie de travail `~/.config/workbook/ca-partenaires.key` en 600), et un certificat de test `centre-test-01` (`~/.config/workbook/partenaire-centre-test-01.{crt,key}`).
- Documentation : `docs/kubernetes/reseau/durcissement-entree.md`.

> ⚠️ **Attention** : (1) une modification de `gw-par1` reconfigure Envoy sur tous les nœuds : sonde lancée, une modification à la fois ; (2) le HSTS est mémorisé par les navigateurs pour sa durée : commence avec `max-age=300` le temps des essais, puis passe à un an quand tout est vérifié ; n'ajoute `preload` en aucun cas (domaine interne) ; (3) la clé de l'autorité des partenaires ne quitte jamais `adm01` et Vault.

**Travail demandé**
1. **État des lieux TLS.** Depuis `adm01`, teste `gw-par1` : TLS 1.0, 1.1, 1.2 et 1.3 (`openssl s_client -tls1_1 …`, etc.), suites proposées en 1.2, chaîne présentée, ALPN. Compare à la cible. Si l'écart est nul, dis d'où viennent ces valeurs ; s'il ne l'est pas, cherche comment le corriger.
2. **Ce que Cilium supporte.** Dans la spécification Gateway API v1.6 et la documentation de Cilium 1.20, repère trois mécanismes : les options TLS d'un écouteur (`listeners[].tls.options`), la validation des certificats clients (`spec.tls.frontend`) et `BackendTLSPolicy`. Pour chacun : à quoi il sert, dans quel canal il est, et si Cilium 1.20 l'implémente (documentation, statut des objets après un essai dans `wb-essais` sur `gw-essai`, comportement observé). Consigne ce que tu trouves, preuves à l'appui.
3. **En-têtes.** Ajoute les en-têtes demandés à la route `mediagenda` par un filtre de la Gateway API. Vérifie avec `curl -sI`. Explique pourquoi le HSTS ne se pose que sur les réponses HTTPS, et vérifie que la redirection HTTP → HTTPS de E12 est toujours là.
4. **L'autorité des partenaires.** Crée l'autorité et le certificat de test (durée courte, usage client). Écris dans la fiche comment un nouveau partenaire reçoit son certificat, et comment on lui **retire** l'accès (pas de liste de révocation dans ce montage : quelle durée de validité en découle ?).
5. **Le relais.** Dans `mediagenda-recette` (PSA `restricted`) : certificat serveur par cert-manager, configuration nginx (TLS 1.2+, certificat client exigé et vérifié contre la seule autorité des partenaires, identité du client transmise à l'API dans un en-tête que l'API ne peut pas recevoir d'ailleurs), Deployment à deux réplicas, Service. Mets-le dans le code de MédiAgenda ou de la plateforme (choisis et justifie).
6. **La Gateway des partenaires.** Crée `gw-partenaires` (adresse 10.10.41.11, écouteur TLS *passthrough*), la `TLSRoute` vers le relais, et la publication du nom (la source `gateway-httproute` d'ExternalDNS ne voit pas les `TLSRoute` : trouve un autre moyen parmi les sources configurées en E15). Vérifie que l'adresse est annoncée en BGP. Ajoute les politiques réseau nécessaires (Gateway → relais, relais → API) dans le respect de E28.
7. **Preuve.** Depuis `adm01` : sans certificat client → refus (lis comment, et à quel moment, nginx refuse) ; avec le certificat de test → 200 et l'API reçoit l'identité du centre ; avec un certificat émis par `ca01` (autorité MédiSphère, pas celle des partenaires) → refus. Rédige `docs/kubernetes/reseau/durcissement-entree.md` : constat TLS, ce que Cilium 1.20 supporte ou non, en-têtes, architecture des partenaires, procédures d'émission et de retrait.

**Critères de réussite**
- [ ] `gw-par1` refuse TLS 1.0 et 1.1 et accepte 1.2 et 1.3 ; la réponse HTTPS de MédiAgenda porte `Strict-Transport-Security` (`max-age` d'au moins un an) et les trois autres en-têtes.
- [ ] `gw-partenaires` a l'adresse 10.10.41.11, un écouteur TLS *passthrough* et une `TLSRoute` acceptée ; le nom `mediagenda-partenaires.apps.par1.medisphere.internal` résout vers 10.10.41.11.
- [ ] Sans certificat client, la connexion à `mediagenda-partenaires` échoue ; avec le certificat de test, l'API répond ; la clé de l'autorité et du certificat de test sont en 600 sur `adm01`.
- [ ] `docs/kubernetes/reseau/durcissement-entree.md` est sur `main`, avec le constat de support de Cilium 1.20 argumenté.

**Vérification** : `lab/bin/check 15 33`

<details><summary>Indice 1</summary>

Une ressource Gateway API peut être **acceptée** par l'API (le schéma la valide) sans que l'implémentation en fasse quoi que ce soit : le statut (`conditions`, champ `supportedFeatures` de la GatewayClass) et le comportement observé disent la vérité, pas l'absence d'erreur au `kubectl apply`. Pour les versions de TLS, Envoy a des valeurs par défaut documentées : compare-les à ce que tu observes.
</details>

<details><summary>Indice 2</summary>

`BackendTLSPolicy` concerne le trajet **Gateway → application** (la Gateway vérifie le certificat du Service), pas le trajet client → Gateway. Pour exiger un certificat du client sans que la Gateway le sache faire, il faut que la négociation TLS du client arrive **intacte** à un composant qui sait le faire : c'est exactement ce que fait une `TLSRoute` en *passthrough*.
</details>

<details><summary>Indice 3</summary>

Cilium recopie les labels et annotations de `spec.infrastructure` d'une Gateway sur le Service `LoadBalancer` qu'il crée pour elle ; ExternalDNS sait publier un Service à partir d'une annotation de nom d'hôte. Pour l'en-tête d'identité, pense à **écraser** tout en-tête de même nom venu du client, sinon n'importe qui peut se faire passer pour un centre.
</details>

**Pour aller plus loin** (facultatif) : `BackendTLSPolicy` pour chiffrer le trajet Gateway → MédiAgenda (certificat de l'API émis par cert-manager, `ConfigMap` de la racine) ; `CiliumEnvoyConfig` pour des réglages d'Envoy non exposés par la Gateway API (et pourquoi c'est une dette) ; la mise à jour de la validation client attendue dans une version future de Cilium ; [GEP-91](https://gateway-api.sigs.k8s.io/geps/gep-91/), [BackendTLSPolicy dans Cilium](https://docs.cilium.io/en/v1.20/network/servicemesh/gateway-api/backendtlspolicy/), [HSTS (RFC 6797)](https://www.rfc-editor.org/rfc/rfc6797).

---

### M15-E34 — Publier une nouvelle application en temps limité  `CHRONO` `★★★`

> **Ticket DEV-1634** — *De : Julien Petit* — *Copie : Claire Morel*
> L'équipe MédiDoc a son espace (`medidoc-dev`) et son image signée dans Harbor. Il lui faut maintenant ce que MédiAgenda a mis un module entier à obtenir : un Service, un nom sous `apps`, un certificat, et des politiques réseau. Claire veut savoir combien de temps il faut à la Plateforme pour le faire **proprement**.
> Le dossier est prêt. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks, ton code (`plateforme/k8s`), tes fiches `docs/kubernetes/reseau/` et la documentation officielle.
- Durée cible : **60 minutes** entre l'ouverture du dossier (T0) et la livraison vérifiée (T4).
- Tout passe par le code et les MR (`plateforme/k8s`, `plateforme/medisphere`). Une commande manuelle est permise pour **constater** (`kubectl get`, `curl`, `hubble observe`), jamais pour créer ; s'il t'en faut une pour avancer, note-la dans la feuille de temps : c'est un défaut de ton outillage.
- MédiDoc reste publié après l'exercice (le module 16 lui donnera son stockage définitif).

**Prérequis** : M15-E12 à E15 (Gateway, certificats, noms), M15-E17 et E28 (politiques, segmentation), M15-E22 (RB-150), M14-E33 (espace `medidoc-dev`).
**Durée** : 60 minutes chronométrées + 30 minutes de retour d'expérience.

**Préparation (hors chrono, la veille)** : le compartiment `medidoc-dev` et son identité S3 existent sur `s3-01` (méthode de M05), leurs clés sont dans `~/.config/workbook/s3-medidoc-dev.env` (600) et en Vault `lab` ; l'image `registry.par1.medisphere.internal/medisphere/medidoc:<VERSION-MEDIDOC>` (M13) est signée ; le Secret de tirage `harbor-pull` existe dans `medidoc-dev` (M14-E33).

**Dossier** : [`ressources/E34-dossier-chrono.md`](../ressources/E34-dossier-chrono.md) (le besoin, les exigences, la feuille de temps) et [`ressources/E34-medidoc/`](../ressources/E34-medidoc/) (le Deployment livré par l'équipe). Lis-les à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T4), avec les gestes manuels éventuels et leur raison ; le temps total est inférieur à 60 minutes (sinon, améliore ton outillage et refais l'exercice sur une application fictive dans `wb-essais`, supprimée ensuite).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et ta procédure de publication d'une application mise à jour par MR.

**Vérification** : `lab/bin/check 15 34` (à lancer à T4).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 20 minutes, puis demande-toi ce qu'il faudrait pour que l'équipe MédiDoc le fasse **seule** : modèle de route et de politique, droits limités sur `HTTPRoute`, contrôle d'admission qui vérifie le nom d'hôte (module 26), GitOps (module 20).

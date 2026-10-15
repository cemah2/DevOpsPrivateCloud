# Module 15 — Palier 1 : Découverte

Avant d'exposer quoi que ce soit, il faut savoir ce qui se passe entre deux pods. Ce palier suit des paquets sur le fil (même nœud, nœuds différents, sortie du cluster), décortique les Services et ce que kube-proxy programme dans le noyau, raccorde CoreDNS au DNS de MédiSphère, apprend à lire les flux avec Hubble, pose les premières politiques réseau, remplace kube-proxy par Cilium et ouvre une première route HTTP par la Gateway API. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 14 terminé (`lab/bin/check 14 46` vert : `k8s-par1` en 1.36, Cilium 1.20 avec kube-proxy conservé, Hubble relay, compte `wb-checks`, espace `wb-essais`, cache Harbor). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques, les règles du module et l'**ordre conseillé** : E08 se fait **avant** E07.

---

### M15-E01 — Test de positionnement : réseau Kubernetes  `Q` `★★`

> **Ticket PLAT-1601** — *De : Karim Benali*
> Le rituel : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Tout ce que le réseau de Kubernetes suppose acquis : espaces de noms réseau, routage, NAT, filtrage, tunnels, DNS, répartition de charge. Tu as monté la bordure au module 07, tu as déjà presque tout ; on vérifie que ça tient quand on ajoute des pods. Réponds même là où tu hésites : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis réseau Linux et Kubernetes avant d'aborder Cilium.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Linux et réseau*

1. Qu'est-ce qu'un **espace de noms réseau** (*network namespace*) ? Que contient-il en propre, et que partage-t-il avec le reste du système ? Comment un conteneur obtient-il « sa » carte réseau ?

2. Une paire **veth** : comment fonctionne-t-elle, et pourquoi en faut-il une par pod dans la plupart des CNI ? Comment retrouves-tu, depuis l'hôte, l'extrémité qui correspond à l'interface `eth0` d'un conteneur ?

3. *(QCM)* Un paquet sort d'un pod (10.240.1.15) vers `dns01` (10.10.20.10), à travers le nœud (10.10.40.61) et la bordure. Quelle adresse source `dns01` voit-il, dans un cluster configuré comme `k8s-par1` ?
   - A. 10.240.1.15, parce que le modèle Kubernetes interdit toute traduction d'adresse
   - B. 10.10.40.61, parce que le nœud masque (SNAT) ce qui sort du réseau des pods vers l'extérieur du cluster
   - C. 10.10.40.1, l'adresse de la passerelle du VLAN 40
   - D. L'adresse du Service de CoreDNS

4. Explique ce que fait **conntrack** pour une connexion TCP traduite (DNAT puis réponse). Que se passe-t-il pour les paquets de réponse si la table de suivi est vidée au milieu d'une connexion ?

5. Dans iptables, dans quelles tables et quelles chaînes une règle de **DNAT** et une règle de **SNAT** s'appliquent-elles ? Pourquoi un DNAT dans `PREROUTING` ne voit-il pas les paquets émis par un processus de l'hôte lui-même ?

6. Qu'est-ce que **VXLAN** ? Décris l'encapsulation (couches, port UDP standard et port historique de Linux), le rôle du VNI, et le coût en octets par paquet. Quel MTU donner aux interfaces « intérieures » si le réseau physique est à 1500 ?

7. *(QCM)* Le MTU des pods est trop grand pour le tunnel et l'ICMP « fragmentation nécessaire » est filtré. Quel est le symptôme typique ?
   - A. Aucune connexion ne s'établit
   - B. Les connexions s'établissent, les petites requêtes passent, les grosses réponses se figent
   - C. Le DNS cesse de fonctionner, le reste passe
   - D. Le débit est divisé par deux mais tout fonctionne

8. Routage natif contre tunnel (*overlay*) pour un réseau de pods : ce que chacun exige du réseau sous-jacent, un avantage et un inconvénient de chacun.

*DNS et répartition*

9. Dans un `resolv.conf`, que font `search` et `options ndots:N` ? Avec `search a.example b.example` et `ndots:5`, quelles questions part-il pour le nom `ca01.par1.medisphere.internal`, et dans quel ordre ?

10. Pourquoi un résolveur **ne doit-il pas** transmettre ses questions à lui-même, même indirectement ? Donne un exemple de configuration qui crée cette boucle sans qu'on le voie.

11. Compare la répartition de charge **L4** et **L7** : ce que chacune voit d'une requête HTTP, ce qu'elle peut décider, et une conséquence pour le TLS.

12. *(QCM)* Un répartiteur L4 qui fait du DNAT vers trois serveurs, sans affinité. Un client ouvre une connexion TCP persistante (HTTP *keep-alive*) et envoie 100 requêtes. Combien de serveurs les reçoivent ?
    - A. Les trois, à peu près à parts égales
    - B. Un seul : la décision est prise par connexion, pas par requête
    - C. Deux, à cause du *keep-alive*
    - D. Cela dépend du nombre de cœurs du client

13. Qu'est-ce que l'**indication du nom de serveur** (SNI) en TLS, et pourquoi permet-elle à un répartiteur de router du TLS **sans** le déchiffrer ?

*Kubernetes*

14. Énonce les trois règles du **modèle réseau** de Kubernetes. Laquelle rend impossible un réseau de pods « en NAT » comme celui de Docker par défaut ?

15. Un **Service** de type `ClusterIP` : à quelle interface appartient son adresse ? Que se passe-t-il si tu fais `ping` sur cette adresse depuis un pod, et pourquoi ?

16. Quelle est la différence entre un **Endpoints** et un **EndpointSlice** ? Quand un pod n'est-il **pas** dans les adresses prêtes d'un Service, alors qu'il est `Running` ?

17. `NodePort`, `LoadBalancer`, `externalIPs` : qu'ajoute chacun au précédent ? Qui fournit l'adresse d'un `LoadBalancer` dans un cluster installé sur ses propres serveurs ?

18. *(QCM)* Dans un espace de noms sans aucune NetworkPolicy, tu crées une politique qui sélectionne `app=api` et autorise l'entrée depuis `app=web` sur le port 8000. Que devient le trafic **sortant** des pods `app=api` ?
    - A. Il est bloqué : une politique met le pod en refus par défaut dans les deux sens
    - B. Il reste libre : la politique ne déclare que le type `Ingress`
    - C. Seules les réponses vers `app=web` sont permises
    - D. Il est bloqué sauf le DNS

19. Qu'est-ce qu'un **Ingress** Kubernetes, et qu'apporte la **Gateway API** par rapport à lui (au moins trois différences) ?

20. Qu'est-ce que **eBPF**, en deux ou trois phrases ? Pourquoi un vérificateur (*verifier*) examine-t-il chaque programme avant son chargement ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque question de chemin de paquet, dessine les boîtes (pod, nœud, passerelle, serveur) et écris, à chaque traversée, les adresses source et destination du paquet **à ce point précis**.
</details>

<details><summary>Indice 2</summary>

Pour les questions de politiques réseau, retiens une seule règle : une politique ne change rien pour un pod qu'elle ne sélectionne pas, ni pour une direction qu'elle ne déclare pas.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M15-E46), sans relire le corrigé, et compare.

---

### M15-E02 — Suivre un paquet de pod à pod  `LAB` `★★`

> **Ticket PLAT-1602** — *De : Karim Benali*
> Au prochain incident réseau sur le cluster, je ne veux pas qu'on « redémarre Cilium pour voir ». Je veux que chacun sache où passe un paquet entre deux pods, sur le même nœud et entre deux nœuds, et ce qu'il devient en sortant du cluster. Mets des sondes, capture sur le fil, lis ce que Cilium sait de chaque pod, et écris-le dans une fiche d'une page. Et installe-nous enfin `tcpdump` sur les nœuds, proprement, par Ansible.

**Objectifs pédagogiques**
- Relier ce que montrent `ip`, `tcpdump` et `cilium-dbg` sur un nœud au chemin réel d'un paquet.
- Observer l'encapsulation VXLAN entre nœuds, l'identité de sécurité portée dans l'en-tête, et le MTU qui en découle.
- Observer le masquage (SNAT) en sortie du cluster.
- Outiller les nœuds pour le diagnostic sans toucher aux rôles qui les construisent.

**Prérequis** : M14-E46 ; M14-E19 (cache Harbor).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Sondes | pods `sonde-w01a` et `sonde-w01b` sur `k8s-w01`, `sonde-w02` sur `k8s-w02`, espace `wb-essais`, label `app.kubernetes.io/name: sonde` ; image `registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16`, commande `sleep infinity`, requêtes et limites modestes ; manifeste dans `~/m15/e02/` |
| Outils des nœuds | playbook `playbooks/k8s-outils-diagnostic.yml` de `plateforme/ansible`, groupe `k8s_par1`, un nœud à la fois : `tcpdump`, `conntrack`, `iptables`, `bpftool`, `bind9-dnsutils`, `iperf3` (paquets Debian 13 ; le service `iperf3` éventuel reste arrêté) |
| Agent Cilium d'un nœud | `kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=<NOEUD>` ; commandes de l'agent : `kubectl -n kube-system exec <POD> -c cilium-agent -- cilium-dbg …` |
| Fiche | `docs/kubernetes/reseau/chemin-paquet.md` de `plateforme/medisphere` |

**Travail demandé**

*A. Outiller*

1. Écris le playbook `k8s-outils-diagnostic.yml` (idempotent, `serial: 1`). Pourquoi un playbook à part plutôt qu'une tâche de plus dans le rôle `k8s_noeud` ? MR, application par le pipeline ; second passage : `changed=0`.

*B. Les sondes et leurs adresses*

2. Écris et applique le manifeste des trois sondes. Relève leurs adresses (`kubectl -n wb-essais get pods -o wide`) et les plages de pods de chaque nœud :
   ```
   admin@adm01:~$ kubectl get ciliumnodes -o custom-columns=NOEUD:.metadata.name,PODS:.spec.ipam.podCIDRs
   ```
   Qui a attribué ces plages, et d'où vient la taille de chacune ?
3. Dans `sonde-w01a` : `ip -4 addr`, `ip route`, `ip -o link show eth0`. Quelle est la passerelle du pod, quel est le MTU de sa route, et que veut dire `eth0@ifNN` ?
4. Sur `k8s-w01` (en SSH) : `ip -o link | grep -E "lxc|cilium"`, `ip -4 addr show cilium_host`, `ip route`, `ip -d link show cilium_vxlan`. Retrouve l'interface `lxc…` de `sonde-w01a`. Quelles routes le nœud a-t-il vers les plages de pods des **autres** nœuds, et par quelle interface ?
5. Lis ce que l'agent Cilium de `k8s-w01` sait de ses pods : `cilium-dbg endpoint list`, puis `cilium-dbg identity get <ID>` pour l'identité de `sonde-w01a`. Pourquoi `sonde-w01a` et `sonde-w01b` ont-elles la **même** identité ?

*C. Même nœud*

6. Lance une capture sur `k8s-w01`, sur l'interface `lxc…` de `sonde-w01b`, puis un `ping -c 3` de `sonde-w01a` vers `sonde-w01b`. Le paquet passe-t-il par `eth0` ? Note la ligne *Host Routing* de `cilium-dbg status --verbose` : tu la reliras en E08.

*D. Deux nœuds*

7. Capture sur `eth0` de `k8s-w01` le trafic UDP 8472 (`tcpdump -ni eth0 -c 6 udp port 8472`), puis `ping -c 3` de `sonde-w01a` vers `sonde-w02`. Pour un paquet capturé, écris les adresses et ports de l'en-tête **externe**, le VNI, et les adresses de l'en-tête **interne**.
8. Le VNI n'est pas un identifiant de réseau ici : `cilium-dbg identity get <VNI>`. Que transporte-t-il, et à quoi cela sert-il au nœud d'arrivée ?
9. `cilium-dbg bpf ipcache list` (ou `bpf ipcache get <IP-DE-SONDE-W02>`) : comment `k8s-w01` sait-il à quel nœud envoyer un paquet pour `sonde-w02` ?
10. MTU : dans `sonde-w01a`, envoie des `ping` non fragmentables vers `sonde-w02` (`ping -M do -s <TAILLE>`). Trouve la plus grande taille qui passe et explique-la à l'octet près.

*E. Sortie du cluster*

11. Depuis `sonde-w01a`, interroge `dns01` (`dig @10.10.20.10 git01.par1.medisphere.internal`) pendant une capture sur `eth0` de `k8s-w01` (port 53). Quelle adresse source part sur le VLAN 40 ? Qui fait la traduction, et qu'en déduis-tu pour la matrice des flux de la bordure ?

*F. Écrire*

12. Rédige `docs/kubernetes/reseau/chemin-paquet.md` : adresses, interfaces d'un nœud, les trois chemins (même nœud, deux nœuds, sortie) avec ce qu'on voit à chaque point, le MTU, et les commandes qui répondent à chaque question. MR, fusion.

**Critères de réussite**
- [ ] Les trois sondes tournent dans `wb-essais` sur les nœuds prévus, avec des adresses de 10.240.0.0/16 ; `sonde-w01a` et `sonde-w02` sont dans des /24 différents.
- [ ] Chaque nœud a son /24 de pods ; Cilium est en mode tunnel VXLAN (`cilium_vxlan`, port 8472).
- [ ] `tcpdump`, `conntrack`, `iptables` et `bpftool` sont installés sur les six nœuds par le playbook, qui est sur `main` de `plateforme/ansible`.
- [ ] La fiche `chemin-paquet.md` est sur `main` et décrit le tunnel (port, VNI et identité) et le MTU des pods.

**Vérification** : `lab/bin/check 15 02`

<details><summary>Indice 1</summary>

Pour trouver l'interface d'un pod sur le nœud : le nombre après `eth0@if` est l'**index** de l'interface paire dans l'espace de noms de l'hôte. `ip -o link` affiche les index en tête de ligne. Pour lancer `cilium-dbg` sur le bon nœud, choisis le pod `cilium-…` par `--field-selector spec.nodeName=`.
</details>

<details><summary>Indice 2</summary>

`tcpdump` décode VXLAN sur le port 4789 par défaut. Sur un autre port, demande-lui de le faire (`-T vxlan` dans les versions récentes, à vérifier dans `man tcpdump`), ou lis l'en-tête interne à la main. Pour l'en-tête, compte : Ethernet externe, IP externe, UDP, VXLAN.
</details>

<details><summary>Indice 3</summary>

Pour le MTU : `ping -s` donne la taille des **données** ICMP ; ajoute 8 octets d'en-tête ICMP et 20 d'en-tête IP pour obtenir la taille du paquet, et compare-la au MTU de la route du pod. Pour le masquage, compare la capture sur `lxc…` (adresse du pod) et celle sur `eth0` du **même** paquet.
</details>

**Pour aller plus loin** (facultatif) : refais la question 7 avec `cilium-dbg monitor --type trace` lancé dans l'agent de `k8s-w01` pendant le `ping` : chaque ligne est un point d'observation du plan de données eBPF. Compare avec ta capture.

---

### M15-E03 — Services : ClusterIP, NodePort, headless et EndpointSlices  `LAB` `★★`

> **Ticket DEV-1603** — *De : Julien Petit* — *Copie : Karim Benali*
> Trois questions qu'on se pose dans l'équipe depuis le module précédent. Un : pendant un déploiement, certains appels finissent en « connexion refusée » ; d'où viennent-ils ? Deux : pour le module de visio, on veut qu'un même client tombe toujours sur le même pod pendant quelques minutes. Trois : le prestataire parlait de Services « headless » pour la base ; à quoi ça sert ? On aimerait comprendre avant que tu nous donnes des adresses publiques.

**Objectifs pédagogiques**
- Relier un Service à ses EndpointSlices et comprendre le rôle de la disponibilité (*readiness*).
- Manipuler les types et réglages de Service : `ClusterIP`, `NodePort`, *headless*, `sessionAffinity`, `externalTrafficPolicy`, `internalTrafficPolicy`.
- Lire ce que kube-proxy programme dans iptables, et ce que Cilium programme déjà de son côté.

**Prérequis** : M15-E02.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Application de test | Deployment `echo`, espace `wb-essais`, 3 réplicas, label `app: echo`, image `registry.par1.medisphere.internal/k8s/e2e-test-images/agnhost:2.66.1`, arguments `netexec --http-port=8080`, port nommé `http` ; chemins `/hostname` (nom du pod), `/clientip` (adresse source vue par le pod), `/healthz`, `/readyz` ; **un pod par travailleur** (contrainte de répartition ; `k8s-w03` porte le taint `dedie=bdd:NoSchedule` du M14-E14) |
| Services | `echo` (ClusterIP, port 80 → `http`), `echo-np` (NodePort **30880**), `echo-local` (ClusterIP), `echo-sans-tete` (*headless*, port 8080) |
| État final attendu | `echo` avec affinité de session par adresse client ; `echo-np` en `externalTrafficPolicy: Local` ; `echo-local` en `internalTrafficPolicy: Local` |
| kube-proxy | mode `iptables` (M14) ; pod kube-proxy d'un nœud : `kubectl -n kube-system get pods -l k8s-app=kube-proxy --field-selector spec.nodeName=<NOEUD>` |

> ⚠️ **Attention** : `netexec` expose aussi `/shell` et `/exit` (exécution de commandes dans le pod). Ce n'est acceptable que dans `wb-essais`, sur le réseau du lab ; ne publie jamais cette image hors du cluster.

**Travail demandé**

*A. Service et EndpointSlices*

1. Écris le Deployment `echo` et le Service `echo` (manifeste dans `~/m15/e03/`), applique, vérifie la répartition (`kubectl -n wb-essais get pods -l app=echo -o wide`).
2. Lis le Service et ses EndpointSlices :
   ```
   admin@adm01:~$ kubectl -n wb-essais get endpointslices -l kubernetes.io/service-name=echo -o yaml
   ```
   Quels champs portent l'adresse, le nœud, la zone, et l'état de chaque pod ? Qui écrit cet objet ?
3. Depuis `sonde-w01a`, appelle 20 fois `http://echo/hostname` (boucle `for` et `curl -s`). Répartition ?
4. Lance une boucle d'appels depuis `sonde-w01a` (une requête toutes les 0,2 s, en affichant le code HTTP), puis, dans un autre terminal, `kubectl -n wb-essais rollout restart deployment echo`. Observe la boucle et `kubectl -n wb-essais get endpointslices -l kubernetes.io/service-name=echo -w`. Puis change temporairement le chemin de la sonde de disponibilité du Deployment vers un chemin qui n'existe pas : que deviennent les nouveaux pods (`Running` mais pas `Ready`), les anciens, et leurs lignes dans l'EndpointSlice ? Reviens en arrière (`kubectl rollout undo`). Réponds au point « un » du ticket.

*B. Affinité*

5. Passe `echo` en `sessionAffinity: ClientIP` (300 s) et refais la question 3. Que se passe-t-il pour `sonde-w02` ? Et pour deux connexions venant de deux pods différents ? Lis la limite de cette affinité dans la documentation (que voit le Service quand le client est derrière un répartiteur ?).

*C. NodePort et politique de trafic externe*

6. Crée `echo-np` en NodePort 30880, d'abord **sans** préciser `externalTrafficPolicy`. Depuis `adm01`, appelle `http://10.10.40.61:30880/clientip` et `http://10.10.40.51:30880/hostname` (un nœud de contrôle, qui n'a pas de pod `echo`). Quelle adresse source le pod voit-il ? Pourquoi ?
7. Passe `echo-np` en `externalTrafficPolicy: Local`. Refais les deux appels. Qu'est-ce qui a changé, et pour qui est-ce un avantage ou un piège ?

*D. Politique de trafic interne et headless*

8. Crée `echo-local` (`internalTrafficPolicy: Local`) et appelle-le 10 fois depuis `sonde-w01a` puis depuis `sonde-w02`. Que se passerait-il depuis un pod d'un nœud sans pod `echo` ?
9. Crée `echo-sans-tete`. Depuis `sonde-w01a` : `dig +short echo.wb-essais.svc.cluster.local` et `dig +short echo-sans-tete.wb-essais.svc.cluster.local`, puis `dig SRV _http._tcp.echo-sans-tete.wb-essais.svc.cluster.local`. Réponds au point « trois » du ticket : à qui sert un Service sans adresse, et qui fait alors la répartition ?

*E. Sous le capot*

10. Sur `k8s-w01`, lis les règles de kube-proxy pour `echo` : `sudo iptables-save -t nat | grep -E "echo|KUBE-SVC|KUBE-SEP|KUBE-NODEPORTS" | head -40`. Suis le chemin d'un paquet vers la ClusterIP de `echo` : `KUBE-SERVICES` → `KUBE-SVC-…` → `KUBE-SEP-…`. Comment le choix entre trois pods est-il fait ? Combien de lignes `nat` au total (`iptables-save -t nat | wc -l`) ?
11. Dans l'agent Cilium de `k8s-w01` : `cilium-dbg service list`. Quels Services y figurent, et de quels types ? Qui, aujourd'hui, traduit l'adresse d'un Service pour un pod : kube-proxy, Cilium, ou les deux ? (Relis `cilium-dbg status --verbose`, section *KubeProxyReplacement*.)
12. Garde les quatre Services dans l'état final du contexte technique. Note tes réponses aux trois questions de Julien dans `~/m15/e03/reponse-dev-1603.md` : elles serviront au runbook RB-150 (M15-E22).

**Critères de réussite**
- [ ] `echo` : 3 pods prêts, un sur chaque travailleur ; une sonde de disponibilité ; l'EndpointSlice de `echo` liste 3 adresses prêtes avec leur nœud.
- [ ] Les quatre Services existent avec les types et réglages de l'état final.
- [ ] Depuis `adm01`, le NodePort 30880 répond sur chaque travailleur, le pod voit l'adresse de `adm01`, et un nœud sans pod `echo` ne sert pas le NodePort.

**Vérification** : `lab/bin/check 15 03`

<details><summary>Indice 1</summary>

La répartition « un pod par travailleur » s'écrit avec `topologySpreadConstraints` sur la clé `kubernetes.io/hostname`. Lis le champ `nodeTaintsPolicy` : sans lui, les nœuds de contrôle (non ordonnançables) comptent comme des domaines vides.
</details>

<details><summary>Indice 2</summary>

Dans un EndpointSlice, regarde `endpoints[].conditions` : `ready`, `serving`, `terminating`. Une connexion refusée pendant un déploiement vient souvent d'un pod qui reçoit encore du trafic alors qu'il s'arrête, ou d'un pod annoncé avant d'être prêt.
</details>

<details><summary>Indice 3</summary>

Les règles de choix de kube-proxy utilisent le module `statistic` en mode `random` avec des probabilités dégressives (1/3, puis 1/2, puis le reste). Pour l'adresse source vue sur un NodePort, demande-toi ce que le nœud doit faire si le pod choisi est sur **un autre** nœud, et comment la réponse revient.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Virtual IPs and Service Proxies » de Kubernetes, section *Traffic distribution* (`trafficDistribution: PreferClose`) : en quoi est-ce différent de `internalTrafficPolicy: Local` ?

---

### M15-E04 — CoreDNS : résolution interne et DNS de MédiSphère  `LAB` `★★`

> **Ticket PLAT-1604** — *De : Nadia Roussel*
> Deux remontées cette semaine. Julien trouve que MédiAgenda met parfois une demi-seconde à joindre `ca01` au démarrage. Et l'audit de la configuration du cluster note que CoreDNS transmet tout « à `/etc/resolv.conf` du nœud » : personne ne sait dire vers quoi ça part vraiment, ni ce qui se passerait si l'image des nœuds changeait. Je veux un DNS du cluster qui parle explicitement à nos deux récurseurs, décrit dans `plateforme/k8s`, et une fiche qui explique à l'astreinte qui répond à quoi.

**Objectifs pédagogiques**
- Lire le Corefile de kubeadm et comprendre chaque greffon.
- Observer les enregistrements de Service et de pod, les domaines de recherche et l'effet de `ndots`.
- Raccorder CoreDNS aux récurseurs de MédiSphère par le code, et vérifier que kubeadm ne l'écrasera pas.
- Régler la résolution d'un pod (`dnsPolicy`, `dnsConfig`).

**Prérequis** : M15-E03 ; M06 (récurseurs `dns01`/`dns02`, DNSSEC de `par1`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| CoreDNS | Deployment `kube-system/coredns` (2 réplicas, kubeadm 1.36, CoreDNS 1.14.x), ConfigMap `coredns`, Service `kube-dns` 10.96.0.10 |
| Cible | bloc général `.:53` : transfert vers **10.10.20.10 puis 10.10.20.16** (plus de `/etc/resolv.conf`) ; bloc distinct `medisphere.internal:53` vers les mêmes récurseurs ; greffons de kubeadm conservés (`kubernetes`, `cache`, `loop`, `reload`, `health`, `ready`, `prometheus`…) |
| Code | `composants/coredns/configmap-coredns.yaml` de `plateforme/k8s` |
| Sonde | pod `sonde-ndots` (`wb-essais`, même image que les sondes, sur `k8s-w01`), `dnsPolicy: ClusterFirst`, option `ndots` à **2** |
| Fiche | `docs/kubernetes/reseau/dns-du-cluster.md` de `plateforme/medisphere` |

**Travail demandé**

*A. Lire*

1. Affiche le Corefile (`kubectl -n kube-system get configmap coredns -o yaml`). Pour chaque greffon, une ligne dans ton journal : ce qu'il fait. Que font `fallthrough`, `pods insecure`, et la section `cache` qui désactive le cache pour `cluster.local` ?
2. Dans `sonde-w01a`, lis `/etc/resolv.conf`. D'où vient chaque domaine de recherche ? Que signifie `ndots:5` ?

*B. Ce que CoreDNS répond*

3. Depuis `sonde-w01a` : résous `echo`, `echo.wb-essais`, `echo.wb-essais.svc.cluster.local`, `kubernetes.default`, puis le nom DNS d'un pod (`<A-B-C-D>.wb-essais.pod.cluster.local`) et l'enregistrement SRV du port `http` de `echo`. Lesquels marchent depuis un autre espace de noms ?
4. Mesure le coût de `ndots` : lance sur `k8s-w01` une capture DNS sur l'interface `lxc…` de `sonde-w01a` (port 53), puis, dans la sonde, `dig +search +showsearch ca01.par1.medisphere.internal` et `curl -so /dev/null https://ca01.par1.medisphere.internal/health` (racine MédiSphère non installée dans la sonde : peu importe la réponse, compte les **questions** DNS). Combien de questions pour un seul nom ? Recommence avec le nom terminé par un point. Réponds à la remarque de Julien.

*C. Régler un pod*

5. Crée `sonde-ndots` et refais la mesure de la question 4. Qu'as-tu gagné, et qu'as-tu perdu (pense aux noms courts de Services d'un autre espace) ? Dans quels cas réglerais-tu `ndots` par pod, et pourquoi jamais pour tout le cluster ?
6. Lis la documentation de `dnsPolicy` : `ClusterFirst`, `ClusterFirstWithHostNet`, `Default`, `None`. Quelle politique applique un pod `hostNetwork` qui ne précise rien, et qu'en déduis-tu pour les agents Cilium, qui doivent résoudre `k8s-api.par1.medisphere.internal` ?

*D. Raccorder CoreDNS au DNS de MédiSphère*

7. Sur `k8s-w01`, lis `/etc/resolv.conf` du **nœud** : vers quoi CoreDNS transmet-il aujourd'hui ? Dans quel cas un `forward . /etc/resolv.conf` crée-t-il une boucle, et quel greffon la détecte ?
8. Écris `composants/coredns/configmap-coredns.yaml` selon le contexte technique (partir du Corefile actuel, commenter chaque changement). Lis la documentation du greffon `forward` pour choisir une politique de choix entre les deux récurseurs et un contrôle de santé.
9. Avant d'appliquer, prépare le retour arrière : `kubectl -n kube-system get configmap coredns -o yaml > ~/m15/e04/coredns-avant.yaml`. Applique par MR puis depuis `adm01` : la ConfigMap a été créée par kubeadm, lis la documentation de l'application côté serveur (*server-side apply*) sur les conflits de propriété des champs avant de choisir ta commande.
10. Vérifie la prise en compte sans redémarrage : journaux de CoreDNS (`kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20`), puis depuis une sonde : `git01.par1.medisphere.internal`, `par1.medisphere.internal SOA`, un nom d'Internet, un nom inexistant de `medisphere.internal` (réponse `NXDOMAIN` rapide ?).
11. Lis le code ou la documentation de `kubeadm upgrade` pour CoreDNS : que devient un Corefile modifié à la prochaine montée de version ? Et le Deployment `coredns` ? Note la vérification à faire après chaque montée de version dans RB-142 (montée de version, M14).

*E. Écrire*

12. Rédige `docs/kubernetes/reseau/dns-du-cluster.md` : qui répond à quoi, le `resolv.conf` d'un pod, `ndots`, `dnsPolicy`, diagnostic rapide en quatre commandes, flux. MR, fusion.

**Critères de réussite**
- [ ] Le Corefile du cluster transmet le bloc général et un bloc `medisphere.internal:53` distinct à 10.10.20.10 et 10.10.20.16, sans `/etc/resolv.conf`, en gardant les greffons de kubeadm.
- [ ] Le Corefile du cluster est identique à celui de `composants/coredns/configmap-coredns.yaml` sur `main` de `plateforme/k8s`.
- [ ] CoreDNS a au moins deux réplicas prêts ; `kube-dns` est toujours en 10.96.0.10.
- [ ] `sonde-ndots` tourne avec `ndots` à 2 ; la fiche `dns-du-cluster.md` est sur `main`.

**Vérification** : `lab/bin/check 15 04`

<details><summary>Indice 1</summary>

Un Corefile peut contenir plusieurs **blocs de serveur** ; une question va au bloc dont la zone est la plus longue qui correspond au nom. Les commentaires commencent par `#`. Le greffon `reload` relit le Corefile quand la ConfigMap change, après un délai de propagation du volume.
</details>

<details><summary>Indice 2</summary>

Dans la documentation de `forward`, cherche `policy` (`random`, `round_robin`, `sequential`) et `health_check`. Pour la propriété des champs, cherche `--force-conflicts` et `--field-manager` dans `kubectl apply --help`.
</details>

<details><summary>Indice 3</summary>

Dans le code de kubeadm (phase `addons/dns`), la fonction qui crée la ConfigMap distingue trois cas : Corefile par défaut, Corefile à migrer, Corefile modifié. Pour la capture de la question 4, le pod `sonde-w01a` pose chaque question en A **et** en AAAA.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Using NodeLocal DNSCache in Kubernetes clusters ». Qu'apporterait un cache DNS sur chaque nœud à `k8s-par1`, et pourquoi son intégration avec Cilium demande-t-elle une politique de redirection locale (`CiliumLocalRedirectPolicy`) ?

---

### M15-E05 — Cilium et Hubble : observer les flux  `LAB` `★★`

> **Ticket SEC-1605** — *De : Sophie Laurent*
> Avant qu'on pose la moindre politique réseau, je veux qu'on sache **voir** les flux : qui parle à qui, ce qui est refusé, pourquoi. Hubble est installé depuis le module 14 ; personne ne s'en sert. Deux exigences. Une fiche que l'astreinte peut suivre sans connaître Cilium. Et aucune donnée de santé ni aucun secret dans les flux observés : un identifiant de patient dans une URL ou un jeton dans un en-tête qui s'affiche dans un terminal, c'est une fuite, même en interne.

**Objectifs pédagogiques**
- Se connecter au relay Hubble et filtrer les flux (espace, pod, port, verdict, type d'événement).
- Lire une ligne de flux : identités, point d'observation, verdict, raison d'un refus.
- Comprendre ce que Hubble voit en L3/L4 et ce qu'il ne voit qu'avec une politique L7.
- Configurer la rédaction des champs sensibles par le fichier de *values* de Cilium, et vérifier qu'elle s'applique.

**Prérequis** : M15-E03 (application `echo`, sondes).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Hubble | relay `kube-system/hubble-relay` (M14) ; CLI `hubble` et `cilium` sur `adm01` ; interface web **pas encore** (M15-E26) |
| Réglages de Cilium | `composants/cilium/values.yaml` de `plateforme/k8s`, appliqué par `cilium upgrade --version <VERSION-CILIUM>` (même version : aucune montée de version ici) |
| Rédaction exigée | paramètres de requête des URL, informations d'utilisateur, en-têtes `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key` |
| Objets d'essai | Service `vide` (sélecteur qui ne désigne aucun pod) et politique `visibilite-l7-echo` dans `wb-essais`, **supprimés** en fin d'exercice |
| Fiche | `docs/kubernetes/reseau/hubble.md` de `plateforme/medisphere` |

**Travail demandé**

*A. Se connecter et filtrer*

1. `cilium hubble port-forward &`, puis `hubble status` et `hubble list nodes`. Combien de flux chaque nœud garde-t-il, et qu'est-ce que cela implique pour un diagnostic d'incident ?
2. Pendant une boucle d'appels de `sonde-w01a` vers `echo`, observe : tous les flux de `wb-essais` ; seulement ceux de `sonde-w01a` vers `echo` ; seulement le DNS. Lis `hubble observe --help` pour trouver les filtres. Pourquoi une même requête produit-elle plusieurs lignes ?
3. Sur une ligne, identifie : identités source et destination (et retrouve-les avec `cilium-dbg identity get`), type d'événement, verdict. Que signifient `to-endpoint`, `to-stack`, `to-overlay` ?

*B. Voir un refus*

4. Crée le Service `vide`, appelle-le depuis `sonde-w01a`, et retrouve le refus dans Hubble (`--verdict DROPPED`). Quelle raison est donnée ? Que voit le client (`curl -v`) ?
5. Peux-tu voir, à ce stade, la méthode et le chemin d'une requête HTTP vers `echo` ? Pourquoi ?

*C. Visibilité L7 et rédaction*

6. Lis les pages de Cilium « Layer 7 Protocol Visibility » et « Hubble » (section sur la rédaction des champs sensibles, *redact*). Comment obtient-on des flux HTTP dans Cilium 1.20 ?
7. Crée la politique `visibilite-l7-echo` : une CiliumNetworkPolicy qui sélectionne `echo` en entrée, **autorise tout** (toutes les entités) sur le port 8080, et fait inspecter le HTTP par le proxy, sans filtrer aucune requête. Vérifie que `echo` répond toujours à `sonde-w01a` **et** au NodePort depuis `adm01`.
   > ⚠️ **Attention** : une politique qui sélectionne un pod en entrée le fait passer en refus par défaut pour ce qu'elle n'autorise pas. Relis la tienne avant de l'appliquer : un oubli coupe `echo` pour tout le monde.
8. Depuis `sonde-w01a` : `curl -s -H "Authorization: Bearer secret-de-test" -H "Cookie: session=abc" "http://echo/echo?msg=patient-123"`. Lis le flux HTTP en JSON (`hubble observe --protocol http --last 5 -o json | jq '.flow.l7'`) : que vois-tu de l'URL et des en-têtes ?
9. Ajoute la rédaction au fichier `composants/cilium/values.yaml` (lis les clés `hubble.redact` dans les *values* du chart 1.20, `helm show values cilium/cilium --version <VERSION-CILIUM>`). Aperçu des *values* effectives avant toute application (`cilium upgrade --help` : cherche l'option de simulation qui affiche les *values*), MR, puis application avec `cilium upgrade`. La ConfigMap `cilium-config` change ; est-ce suffisant pour que les agents appliquent la rédaction ? Lis la valeur `rollOutCiliumPods` du chart et agis en conséquence, un nœud à la fois si tu le peux, puis `cilium status --wait`.
10. Refais la question 8. Qu'est-ce qui est masqué, qu'est-ce qui reste visible ? Note la limite qui concerne les **chemins** d'URL.
11. Supprime `visibilite-l7-echo` et le Service `vide`.

*D. Écrire*

12. Rédige `docs/kubernetes/reseau/hubble.md` : connexion, une table « je cherche → commande », lecture d'une ligne, ce que Hubble voit et ne voit pas, la rédaction et ses limites, trois pièges. MR, fusion.

**Critères de réussite**
- [ ] Hubble relay est prêt ; les agents Cilium sont prêts sur les six nœuds et ont redémarré après la dernière modification de leur configuration.
- [ ] La configuration des agents rédige les paramètres d'URL, les informations d'utilisateur et au moins les en-têtes `Authorization` et `Cookie` ; le fichier de *values* sur `main` porte les mêmes réglages.
- [ ] Les objets d'essai (`vide`, `visibilite-l7-echo`) sont supprimés.
- [ ] La fiche `hubble.md` est sur `main`.

**Vérification** : `lab/bin/check 15 05`

<details><summary>Indice 1</summary>

Les filtres de `hubble observe` se combinent : `-n` (espace), `--from-pod`/`--to-pod` (`espace/nom`), `--port`, `--protocol`, `--verdict`, `--type`, `-f` (suivre), `--last N`. Un même paquet est observé à la sortie du pod source, éventuellement au tunnel, et à l'entrée du pod destination.
</details>

<details><summary>Indice 2</summary>

Dans une CiliumNetworkPolicy, une règle `toPorts` peut porter une section `rules.http` ; une liste qui contient une seule règle vide accepte toute requête HTTP mais oblige le passage par le proxy. Les entités (`fromEntities`) couvrent ce que les sélecteurs de pods ne savent pas désigner.
</details>

<details><summary>Indice 3</summary>

`rollOutCiliumPods` vaut `false` par défaut : le chart ne redémarre pas les agents quand la ConfigMap change. `kubectl -n kube-system rollout restart` puis `rollout status` sur le DaemonSet et l'opérateur. La rédaction des en-têtes se fait par une liste `allow` **ou** une liste `deny`, pas les deux.
</details>

**Pour aller plus loin** (facultatif) : `hubble observe --type policy-verdict` ne montre rien tant qu'aucune politique ne s'applique. Garde la commande pour E06.

---

### M15-E06 — Premières politiques réseau : tout interdire par défaut  `LAB` `★★`

> **Ticket SEC-1606** — *De : Sophie Laurent*
> Aujourd'hui, n'importe quel pod du cluster peut ouvrir une connexion vers n'importe quel autre, et vers Internet. Avant d'appliquer ça à MédiAgenda (ce sera pour plus tard, avec Julien), je veux le modèle sur l'espace d'essai : tout refusé par défaut, dans les deux sens, puis seulement ce qui est écrit. Et que tu me montres, dans Hubble, un refus et une autorisation.

**Objectifs pédagogiques**
- Appliquer la sémantique des NetworkPolicy : sélection, types, union des autorisations, absence de règle « refuser ».
- Construire un refus par défaut en entrée et en sortie, puis les autorisations minimales (DNS, client → serveur, administration → serveur).
- Comprendre sur quel port s'applique une politique devant un Service, et ce que devient l'adresse source d'un NodePort.
- Observer les verdicts de politique dans Hubble.

**Prérequis** : M15-E05.
**Durée indicative** : 2 h.

**Contexte technique**

| Politique (espace `wb-essais`) | Intention |
|---|---|
| `refus-par-defaut` | tous les pods, entrée et sortie, aucune autorisation |
| `autoriser-dns` | tous les pods peuvent interroger `kube-dns` (espace `kube-system`, label `k8s-app: kube-dns`), UDP et TCP 53, et rien d'autre par cette règle |
| `clients-vers-echo` | les pods `role: client` peuvent joindre `echo` |
| `echo-entree` | `echo` accepte les pods `role: client`, et le VLAN d'administration (10.10.10.0/24) par le NodePort `echo-np` |

Clients : `sonde-w01a` et `sonde-w02` reçoivent le label `role=client` ; `sonde-w01b` et `sonde-ndots`, non (témoins).

**Travail demandé**

1. Avant toute politique, vérifie ce qui passe aujourd'hui depuis `sonde-w01b` : `echo`, `kubernetes.default` (443), `dns01` (53), un site d'Internet. Lance `hubble observe -n wb-essais --type policy-verdict -f` dans un terminal à part : que montre-t-il ?
2. Pose les labels `role=client`.
3. Écris `refus-par-defaut` (manifeste dans `~/m15/e06/`). Avant de l'appliquer, dis quels pods elle sélectionne et dans quelles directions. Applique. Refais les tests de la question 1 depuis `sonde-w01b` **et** depuis `sonde-w01a` : qu'est-ce qui échoue, et comment (délai, refus immédiat, erreur DNS) ? Que montre Hubble, et dans quel sens ?
4. Écris `autoriser-dns`. Attention à la combinaison des sélecteurs d'espace et de pods dans un même élément de `to` : relis la documentation (« Behavior of to and from selectors »). Teste la résolution de `echo` et d'un nom de `medisphere.internal` depuis `sonde-w01b`. Le nom se résout ; la connexion ?
5. Écris `clients-vers-echo` et `echo-entree` (partie clients). Quel port faut-il écrire : celui du Service ou celui du pod ? Teste depuis `sonde-w01a` (doit passer), `sonde-w02` (doit passer), `sonde-w01b` (doit être refusé : par quelle politique, côté client ou côté serveur ? Hubble te le dit).
6. Depuis `adm01`, appelle le NodePort `http://10.10.40.61:30880/hostname` : refusé. Ajoute à `echo-entree` l'autorisation du VLAN d'administration. Pourquoi peux-tu raisonner sur l'adresse de `adm01` **ici** (relis l'état final de `echo-np` en E03), et que faudrait-il faire si `echo-np` était en `externalTrafficPolicy: Cluster` ?
7. Vérifie que les sondes de vivacité et de disponibilité de `echo` passent toujours (pods `Ready`) : d'où viennent-elles, et pourquoi la politique ne les bloque-t-elle pas ?
8. Fais un relevé dans ton journal : pour chaque test (source, destination, port), verdict attendu, verdict observé, ligne Hubble. Garde les politiques en place : la suite du palier vit avec.

**Critères de réussite**
- [ ] `wb-essais` a un refus par défaut en entrée et en sortie pour tous ses pods.
- [ ] Tous les pods de `wb-essais` peuvent joindre `kube-dns` en UDP et TCP 53, et aucune règle de sortie n'ouvre « tout ».
- [ ] Les pods `role=client` peuvent joindre `echo` sur le port du pod ; `echo` accepte ces clients et le seul VLAN 10.10.10.0/24, pas une plage plus large.
- [ ] `sonde-w01a` et `sonde-w02` portent `role=client`, `sonde-w01b` non ; `adm01` joint toujours `echo` par le NodePort.

**Vérification** : `lab/bin/check 15 06`

<details><summary>Indice 1</summary>

Un `podSelector: {}` sélectionne tous les pods de l'espace de la politique. Une politique qui déclare `Egress` sans aucune règle `egress` refuse toute sortie. Dans un élément de `to`, `namespaceSelector` et `podSelector` **ensemble** veulent dire « ces pods de ces espaces » ; dans deux éléments séparés, « ces espaces OU ces pods de mon espace ».
</details>

<details><summary>Indice 2</summary>

La traduction du Service (80 → 8080) a lieu avant l'application de la politique : la politique voit le port de destination du **pod**. Le label `kubernetes.io/metadata.name` est posé automatiquement sur chaque espace de noms.
</details>

<details><summary>Indice 3</summary>

Pour savoir quel côté refuse : un refus en sortie apparaît sur le nœud du client avec `policy-verdict:none EGRESS DENIED` (ou équivalent), un refus en entrée sur le nœud du serveur avec `INGRESS DENIED`. Les sondes du kubelet partent du nœud lui-même (identité `host`).
</details>

**Pour aller plus loin** (facultatif) : lis la page « Network Policy Editor » de Cilium (editor.networkpolicy.io) et dessine-y tes quatre politiques : vois-tu une ouverture que tu n'avais pas voulue ?

---

> **Ordre de réalisation** : fais **M15-E08** maintenant, puis reviens à M15-E07 (la Gateway API de Cilium exige le remplacement de kube-proxy).

### M15-E07 — Gateway API : premières routes HTTP  `LAB` `★★`

> **Ticket DEV-1607** — *De : Julien Petit*
> On nous a dit qu'il n'y aurait pas d'ingress-nginx ici. D'accord, mais alors comment on publie ? Montre-nous une première route HTTP sur l'application de test, avec un nom d'hôte, quelques chemins, et ce qu'on voit quand ça ne marche pas. Pas besoin d'adresse publique pour l'instant : on veut comprendre les objets avant de les écrire pour MédiAgenda.

**Objectifs pédagogiques**
- Installer les CRD de la Gateway API du canal **standard**, à une version figée et versionnée dans le dépôt.
- Activer le contrôleur Gateway API de Cilium et comprendre ses prérequis.
- Écrire une Gateway et une HTTPRoute, lire leurs états (`Accepted`, `Programmed`, `ResolvedRefs`) et les objets que Cilium en déduit.
- Exposer une Gateway sans fournisseur d'adresses (paramètres de GatewayClass), et autoriser Envoy dans un espace en refus par défaut.

**Prérequis** : M15-E08 (kube-proxy remplacé), M15-E06 (politiques de `wb-essais`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| CRD | Gateway API **v1.6.1**, canal **standard** : `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `ReferenceGrant`, `BackendTLSPolicy`, `TLSRoute` (liste exigée par Cilium 1.20) ; fichiers versionnés dans `composants/gateway-api/v1.6.1/` de `plateforme/k8s`, récupérés par un script avec vérification d'empreintes (`SHA256SUMS-v1.6.1`) |
| Cilium | `gatewayAPI.enabled: true` dans `composants/cilium/values.yaml` |
| GatewayClass d'essai | `cilium-nodeport` : contrôleur de Cilium, paramètres dans une `CiliumGatewayClassConfig` `nodeport` (espace `wb-essais`) qui donne au Service de la Gateway le type `NodePort` |
| Gateway | `gw-essai`, espace `wb-essais`, écouteur `http` HTTP 80, noms `*.wb-essais.internal`, routes du même espace seulement |
| Route | HTTPRoute `echo` : nom `echo.wb-essais.internal`, chemins **exacts** `/hostname` et `/clientip` vers le Service `echo` ; rien d'autre |
| Gateway d'observation | `gw-attente`, classe `cilium`, supprimée en fin d'exercice |
| Vérifications | le compte `wb-checks` (M14-E06) ne lit pas encore les objets `gateway.networking.k8s.io` ni, plus tard (E13), ceux de cert-manager : sa ClusterRole est **agrégée** (étiquette `workbook.medisphere.internal/checks: "true"`) ; ClusterRole de lecture `wb-checks-reseau` dans `rbac/wb-checks-reseau.yaml` de `plateforme/k8s`, sans Secrets |
| Tests | depuis `adm01`, `curl -H "Host: echo.wb-essais.internal" http://10.10.40.61:<NODEPORT>/hostname` (aucun nom DNS : la zone `apps` arrive en E14) |

> ⚠️ **Attention** : n'installe **jamais** les CRD du canal *experimental* sur `k8s-par1` sans décision écrite. Elles remplacent les CRD standard du même nom ; et Cilium 1.20 a changé la version de `TLSRoute` (v1alpha2 → v1) : des objets `TLSRoute` stockés dans une version que la CRD ne sert plus deviennent illisibles. Depuis v1.6.1, `TLSRoute` est servie en `v1` par le canal **standard** : M15-E16 s'en sert sans rien installer de plus.

**Travail demandé**

*A. Prérequis et CRD*

1. Lis la page « Gateway API Support » de la documentation de Cilium 1.20 (prérequis, installation) et la note de mise à jour sur Gateway API v1.6.1. Note les prérequis et vérifie chacun sur le cluster (`cilium-dbg status`, `cilium config view`).
2. Écris `composants/gateway-api/telecharger-crd.sh` : il récupère les sept CRD du canal standard à la version demandée, refuse un fichier qui ne serait pas du canal standard ou d'une autre version, vérifie les empreintes contre `SHA256SUMS-<VERSION>` (et l'écrit au premier téléchargement), puis les range dans `composants/gateway-api/<VERSION>/`. Lance-le, relis ce qu'il a rangé, MR.
3. Applique les CRD (`kubectl apply --server-side -f composants/gateway-api/v1.6.1/`). Lis les annotations d'une CRD (`kubectl get crd gateways.gateway.networking.k8s.io -o yaml | head -20`) : comment saurais-tu, dans un an, quelle version et quel canal sont installés ?

*B. Le contrôleur de Cilium*

4. Active `gatewayAPI.enabled` dans le fichier de *values*, aperçu, MR, `cilium upgrade`, redémarrage de l'opérateur et des agents (même raison qu'en E05), `cilium status --wait`. Vérifie : `kubectl get gatewayclass`. Qui a créé la GatewayClass `cilium`, et pourquoi la documentation insiste-t-elle sur l'ordre « CRD d'abord » ? Écris aussi `rbac/wb-checks-reseau.yaml` (lecture seule des groupes de la Gateway API et de cert-manager, rien d'autre) et prouve qu'il suffit : `kubectl auth can-i list gateways.gateway.networking.k8s.io -A --as=system:serviceaccount:wb-system:wb-checks`, puis la même question pour `secrets` (réponse attendue : `no`).

*C. Une Gateway sans adresse*

5. Crée `gw-attente` (classe `cilium`, un écouteur HTTP 80). Lis `kubectl -n wb-essais get gateway,svc` et `kubectl -n wb-essais describe gateway gw-attente`. Quel Service Cilium a-t-il créé, de quel type, et pourquoi reste-t-il sans adresse ? Lis l'état `Programmed`. Supprime `gw-attente`.
6. Lis la page « GatewayClass Parameters Support » de Cilium. Crée la `CiliumGatewayClassConfig` `nodeport` et la GatewayClass `cilium-nodeport`. Vérifie qu'elle est acceptée.
7. Crée `gw-essai` selon le contexte technique. Lis son état, son Service, son port de nœud (`<NODEPORT>`), et les objets créés dans `wb-essais` (`kubectl -n wb-essais get ciliumenvoyconfigs`). Où tourne le proxy qui servira les requêtes (`kubectl -n kube-system get ds cilium-envoy -o wide`) ?

*D. Une route*

8. Écris l'HTTPRoute `echo` selon le contexte technique, **mais** avec volontairement `port: 8080` dans la référence au Service. Lis son état (`kubectl -n wb-essais describe httproute echo`) : quelle condition est fausse, avec quelle raison ? Corrige (port du **Service**).
9. Depuis `adm01`, appelle `/hostname` avec le bon en-tête `Host`. Réponse ? Lis Hubble (`hubble observe -n wb-essais --verdict DROPPED`) : qui est refusé, avec quelle identité source ? Pourquoi aucune NetworkPolicy standard ne peut-elle autoriser ce trafic ?
10. Écris la politique `echo-depuis-gateway` qui autorise **seulement** cette source vers `echo` sur 8080 (lis « Ingress and Network Policy » dans la documentation de Cilium). Quel est le nom de cette entité réservée ? Teste `/hostname`, `/clientip` (quelle adresse le pod voit-il ?), `/shell?cmd=id`, `/`, et un autre nom d'hôte. Explique chaque code de réponse.
11. Lis ce que Cilium a programmé : `cilium-dbg service list` dans un agent (repère le Service de la Gateway), et l'en-tête `server:` des réponses. Qui répond quand aucune route ne correspond ?

*E. Code*

12. MR des *values* et des CRD (la Gateway d'essai et ses objets restent dans `~/m15/e07/` : ce sont des essais). Réponds au ticket de Julien en dix lignes : les quatre objets, qui écrit quoi (plateforme ou équipe d'application), et ce qu'on lira en cas de panne.

**Critères de réussite**
- [ ] Les sept CRD de la Gateway API sont installées en v1.6.1, canal standard, et aucune CRD `gateway.networking.k8s.io` du canal experimental ; les fichiers sont sur `main` de `plateforme/k8s`.
- [ ] Le contrôleur Gateway API de Cilium est actif (configuration des agents et *values* sur `main`) ; la GatewayClass `cilium` et la GatewayClass paramétrée `cilium-nodeport` sont acceptées.
- [ ] Le compte `wb-checks` lit les objets de la Gateway API et de cert-manager, toujours pas les Secrets ; `rbac/wb-checks-reseau.yaml` est sur `main`.
- [ ] `gw-essai` est acceptée et programmée, exposée par un Service NodePort, avec au moins une route attachée ; l'HTTPRoute `echo` est acceptée avec ses références résolues ; `gw-attente` n'existe plus.
- [ ] Une CiliumNetworkPolicy autorise l'entité d'Envoy vers `echo` sur 8080, et rien de plus large.
- [ ] Depuis `adm01` : `/hostname` répond 200 avec le bon nom d'hôte, 404 pour `/shell` et pour un autre nom d'hôte.

**Vérification** : `lab/bin/check 15 07`

<details><summary>Indice 1</summary>

Les annotations `gateway.networking.k8s.io/bundle-version` et `gateway.networking.k8s.io/channel` de chaque CRD disent ce qui est installé. Le chart de Cilium crée la GatewayClass `cilium` si la CRD `GatewayClass` existe au moment où il est appliqué (`gatewayAPI.gatewayClass.create`).
</details>

<details><summary>Indice 2</summary>

Une `CiliumGatewayClassConfig` est un objet d'espace de noms (`cilium.io/v2alpha1`), référencé par `spec.parametersRef` de la GatewayClass (groupe, type, nom, espace). Le Service d'une Gateway s'appelle `cilium-gateway-<NOM-DE-LA-GATEWAY>`. Une HTTPRoute vise un Service par son **port de Service**.
</details>

<details><summary>Indice 3</summary>

Le trafic qui sort d'Envoy vers un pod porte une identité réservée de Cilium, la même pour les Ingress et les Gateway. Elle se désigne par `fromEntities` dans une CiliumNetworkPolicy. Pour l'adresse vue par le pod, pense à qui ouvre la connexion vers lui.
</details>

**Pour aller plus loin** (facultatif) : lis la section « Host network mode » de la documentation : quels seraient les avantages et les risques d'exposer Envoy directement sur les ports des nœuds, plutôt que par un Service ?

---

### M15-E08 — Remplacer kube-proxy par Cilium  `LAB` `★★★`

> **Ticket PLAT-1608** — *De : Karim Benali* — *Copie : Claire Morel, Nadia Roussel*
> Deux plans de données traduisent nos Services : les règles iptables de kube-proxy et les tables eBPF de Cilium. C'est un de trop, et la Gateway API de Cilium ne fonctionne pas sans le remplacement. On retire kube-proxy. C'est un changement du cluster entier : fiche CHG-1608, fenêtre annoncée, coupure brève assumée et **mesurée**, retour arrière écrit avant de commencer. Et je ne veux pas qu'un `kubeadm upgrade` le réinstalle en douce dans trois mois.

**Objectifs pédagogiques**
- Suivre la procédure officielle de remplacement de kube-proxy sur un cluster **existant**.
- Comprendre pourquoi l'agent Cilium doit joindre l'API sans passer par un Service.
- Retirer kube-proxy et ses règles de chaque nœud, un nœud à la fois, et vérifier que tous les types de Services sont servis par Cilium.
- Empêcher kubeadm de réinstaller kube-proxy, dans le cluster et dans le code.
- Conduire un changement : fiche, mesure de l'interruption, retour arrière.

**Prérequis** : M15-E03, M15-E06 ; M14-E24 (instantané etcd) ; M14-E25 (montée de version, `kubeadm upgrade`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Procédure de référence | documentation de Cilium 1.20, « Kubernetes Without kube-proxy » (cas d'une installation existante avec kube-proxy en DaemonSet) |
| Réglages de Cilium | `kubeProxyReplacement: true` ; serveur de santé compatible kube-proxy sur `0.0.0.0:10256` ; `k8sServiceHost`/`k8sServicePort` (VIP de l'API) **déjà** présents depuis le M14 |
| kubeadm | ClusterConfiguration v1beta4 : le champ qui désactive l'extension kube-proxy est à trouver dans la référence de l'API ; à appliquer à `cluster/kubeadm-config.yaml` **et** à la ConfigMap `kube-system/kubeadm-config` ; document `KubeProxyConfiguration` retiré du fichier |
| Nettoyage | `outils/nettoyer-regles-kube-proxy.sh` de `plateforme/k8s` : depuis `adm01`, en SSH, un nœud à la fois, règles iptables IPv4 et IPv6 (backends nft et legacy), avec un mode simulation |
| Fiche | `docs/kubernetes/changements/CHG-1608-remplacement-kube-proxy.md` de `plateforme/medisphere` |

> ⚠️ **Attention** : la documentation de Cilium prévient que retirer kube-proxy **rompt les connexions établies** vers les Services, et qu'ajouter ou retirer le remplacement sur un cluster qui sert du trafic rompt aussi des connexions (les deux tables de traduction s'ignorent). Annonce la fenêtre, fais l'instantané etcd, et ne commence pas si un agent Cilium n'est pas prêt. Ne supprime jamais kube-proxy **avant** que Cilium n'ait le remplacement actif : pendant l'intervalle, plus aucun Service ne fonctionnerait.

**Travail demandé**

*A. Préparer*

1. Lis la procédure de référence en entier. Dans ton journal : l'ordre des étapes, ce que chaque étape casse, et comment tu sais qu'elle a réussi. Pourquoi l'agent doit-il connaître `k8sServiceHost` et `k8sServicePort`, et que se passerait-il au premier redémarrage d'un nœud s'ils valaient l'adresse du Service `kubernetes` (10.96.0.1) ?
2. État initial, à garder pour la fiche : `cilium-dbg status --verbose` (section *KubeProxyReplacement*, ligne *Host Routing*), `cilium-dbg service list | wc -l`, et sur `k8s-w01` le nombre de règles `nat` (`sudo iptables-save -t nat | wc -l`) et de chaînes `KUBE-SVC-`.
3. Lis la référence de l'API de configuration de kubeadm v1beta4 (`ClusterConfiguration`) et le comportement de `kubeadm upgrade apply` pour l'extension kube-proxy. La recommandation de la documentation de Cilium (« supprimer la ConfigMap kube-proxy pour éviter une réinstallation ») suffit-elle avec kubeadm 1.36 ? Trouve le champ qui garantit que kube-proxy n'est plus réinstallé, et comment `kubeadm init` le relie à `--skip-phases`.
4. Écris la fiche CHG-1608 : demandeur, fenêtre, impact annoncé, étapes, **retour arrière** avant et après la suppression de kube-proxy, mesures prévues. Fais-la relire (MR) avant la fenêtre.
5. Écris `outils/nettoyer-regles-kube-proxy.sh` (préalables vérifiés : DaemonSet absent, remplacement actif, agent prêt sur le nœud ; un nœud à la fois ; vérification après nettoyage ; mode simulation). `shellcheck`, MR. Lance-le en simulation sur `k8s-w01`.
6. Modifie `composants/cilium/values.yaml` et `cluster/kubeadm-config.yaml`. Garde la version actuelle des *values* hors du dépôt pour le retour arrière (`git show`). Aperçu des *values* effectives, MR relue.

*B. La fenêtre*

7. Instantané etcd (`outils/etcd-instantane.sh`, M14), et vérifie-le. Lance deux mesures qui tournent pendant toute la fenêtre : depuis `adm01`, une boucle sur le NodePort `echo-np` d'un travailleur (une requête toutes les 0,2 s, horodatée, code HTTP) ; depuis `sonde-w01a`, la même chose vers le Service `echo`.
8. `cilium upgrade` avec les nouvelles *values*, redémarrage de l'opérateur et des agents, `cilium status --wait`. Dans chaque agent : `cilium-dbg status | grep KubeProxyReplacement`. Que montre maintenant `cilium-dbg service list` (types de Services, nombre de lignes) ?
9. Supprime le DaemonSet `kube-proxy`, puis sa ConfigMap. Lance le nettoyage, nœud par nœud. Sur `k8s-w01`, recompte les règles `nat` et les chaînes `KUBE-SVC-`.
10. Mets à jour la ConfigMap `kubeadm-config` à partir du fichier du dépôt : lis la page « Reconfiguring a kubeadm cluster » pour choisir entre la modification directe de la ConfigMap et la phase `upload-config` de `kubeadm init`. Puis, sur `k8s-cp01`, `sudo kubeadm upgrade plan` et un `kubeadm upgrade apply` **en simulation** vers la version actuelle : que dit kubeadm à propos de kube-proxy ? (Si ta version refuse la simulation vers la même version, lis la ConfigMap et le code de la phase `addon/kube-proxy` de `kubeadm upgrade`, et note-le.)
11. Arrête les mesures. Quelle a été la plus longue interruption, vue de chaque côté, et à quelle étape ?

*C. Vérifier et clore*

12. Refais les tests de E03 : ClusterIP, affinité, NodePort sur chaque nœud, `externalTrafficPolicy: Local` (le nœud de contrôle ne sert toujours pas le NodePort ?), `internalTrafficPolicy`, *headless*. Depuis `adm01`, `curl http://10.10.40.61:10256/healthz` : qui répond, et à quoi sert ce point ?
13. Relis la ligne *Host Routing* de `cilium-dbg status --verbose` : a-t-elle changé ? Lis les conditions du routage d'hôte eBPF dans la documentation (« eBPF Host-Routing ») et note ce qu'il faudrait encore pour l'obtenir (sujet de M15-E29).
14. Fusion des MR, puis rejoue le playbook du plan de contrôle (M14) en mode vérification (`--check --diff`) : il ne doit vouloir ni recréer kube-proxy ni remettre l'ancien fichier de configuration de kubeadm. Clos la fiche CHG-1608 avec les mesures.

**Critères de réussite**
- [ ] Le DaemonSet et la ConfigMap `kube-proxy` n'existent plus ; aucun pod kube-proxy.
- [ ] La configuration des agents Cilium a le remplacement de kube-proxy et le serveur de santé sur 10256 ; tous les agents sont prêts et ont redémarré après la dernière modification de leur configuration ; `/healthz` répond sur le port 10256 de chaque travailleur.
- [ ] Aucun nœud n'a plus de chaîne `KUBE-SERVICES`, `KUBE-SVC-`, `KUBE-SEP-`, `KUBE-NODEPORTS`, `KUBE-EXT-` ; les chaînes de Cilium sont présentes.
- [ ] La ConfigMap `kubeadm-config` et `cluster/kubeadm-config.yaml` sur `main` désactivent l'extension kube-proxy ; le fichier ne contient plus de `KubeProxyConfiguration`.
- [ ] Les *values* (`kubeProxyReplacement: true`), le script de nettoyage et la fiche CHG-1608 sont sur `main` ; le NodePort `echo-np` répond.

**Vérification** : `lab/bin/check 15 08`

<details><summary>Indice 1</summary>

Sans kube-proxy, l'adresse 10.96.0.1 n'est traduite que par Cilium ; or l'agent doit parler à l'API **avant** d'avoir chargé ses tables. Pour kubeadm, lis la structure `Proxy` de `ClusterConfiguration` dans la référence v1beta4, et cherche dans le code de `kubeadm upgrade` la phase `addon/kube-proxy` et la condition qui la saute.
</details>

<details><summary>Indice 2</summary>

Debian 13 utilise le backend nft d'iptables, mais un binaire `iptables-legacy` peut exister : kube-proxy choisit son backend au démarrage. Le nettoyage officiel (`iptables-save | grep -v KUBE | iptables-restore`) garde les chaînes `CILIUM_*`. Le playbook de E02 a installé `iptables` sur les nœuds.
</details>

<details><summary>Indice 3</summary>

`cilium upgrade` modifie la ConfigMap `cilium-config` ; `rollOutCiliumPods` vaut `false` : sans redémarrage des agents, la ConfigMap dit `true` et les agents tournent encore sans remplacement. Pour la ConfigMap de kubeadm, `kubeadm init phase upload-config kubeadm --config <FICHIER>` réécrit la `ClusterConfiguration` à partir du fichier.
</details>

**Pour aller plus loin** (facultatif) : lis la section « Socket LoadBalancer Bypass in Pod Namespace » : dans quels cas (maillage de services, certains agents de sécurité) faut-il désactiver la traduction au niveau des sockets dans les pods, et qu'est-ce que cela change pour les politiques réseau (note de mise à jour de Cilium 1.20 sur les NodePort) ?

---

### M15-E09 — Questions : CNI, eBPF et Services  `Q` `★★`

> **Ticket PLAT-1609** — *De : Karim Benali*
> Fin du premier palier. Avant d'attaquer les adresses publiques et le BGP, je veux savoir si tu sais **expliquer** ce que tu as fait, pas seulement le refaire. Par écrit, sans rien exécuter ; appuie-toi sur tes relevés des exercices.

**Objectifs pédagogiques**
- Consolider les mécanismes vus au palier 1 : CNI, identités, datapath eBPF, Services, DNS, politiques, Gateway.
- Savoir argumenter un choix d'architecture réseau de cluster.

**Prérequis** : M15-E02 à M15-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 15 questions, en t'appuyant sur ce que tu as observé.

1. Décris dans l'ordre ce qui se passe, du point de vue réseau, entre le moment où le kubelet crée le bac à sable (*sandbox*) d'un pod et celui où le pod peut joindre un autre pod d'un autre nœud. Qui fait quoi : kubelet, runtime, greffon CNI, agent Cilium, opérateur ?

2. *(QCM)* Deux pods de deux espaces différents ont exactement les mêmes labels. Dans Cilium, ils ont :
   - A. la même identité, puisque l'identité dépend des labels
   - B. deux identités différentes, parce que l'espace de noms fait partie des labels de sécurité
   - C. la même identité seulement s'ils sont sur le même nœud
   - D. une identité par adresse IP

3. Pourquoi filtrer par **identité** plutôt que par adresse IP, dans un cluster où les pods sont recréés toutes les heures ? Donne un cas où Cilium **doit** quand même raisonner en adresses.

4. En mode tunnel, le nœud d'arrivée applique la politique d'entrée sans connaître l'émetteur autrement que par le paquet. Où trouve-t-il l'identité de la source ? Que se passerait-il en routage natif ?

5. Le MTU des pods de `k8s-par1` est de 1450. D'où vient ce chiffre, que deviendrait-il avec le chiffrement WireGuard (M15-E24), et que se passe-t-il si quelqu'un passe le VLAN 40 à 9000 sans rien dire à Cilium ?

6. Avec kube-proxy en mode iptables, combien de règles la traduction d'un Service de 3 pods coûte-t-elle, et comment ce coût évolue-t-il avec 2 000 Services ? Qu'est-ce qui change avec les tables eBPF de Cilium (recherche, mise à jour) ?

7. Qu'est-ce que le *socket LB* de Cilium ? Pour une connexion d'un pod vers la ClusterIP de `echo`, à quel moment l'adresse est-elle traduite, et pourquoi un `tcpdump` sur l'interface du pod ne montre-t-il **jamais** l'adresse 10.96.x.y ?

8. *(QCM)* `echo-np` est en `externalTrafficPolicy: Local`. Un répartiteur externe envoie du trafic aux six nœuds. Que se passe-t-il pour les requêtes qui arrivent sur un nœud sans pod `echo`, et comment le répartiteur peut-il l'éviter ?
   - A. Elles sont transmises à un autre nœud, l'adresse source est perdue
   - B. Elles sont refusées ou perdues ; le répartiteur doit interroger le serveur de santé du nœud (port 10256) et retirer ce nœud
   - C. Elles sont mises en file d'attente jusqu'à ce qu'un pod démarre
   - D. kube-proxy (ou Cilium) crée un pod sur ce nœud

9. Pendant un `rollout restart`, des clients reçoivent des erreurs. Cite trois causes possibles côté Kubernetes (pas côté application) et le réglage qui traite chacune.

10. CoreDNS transmet maintenant à `dns01` puis `dns02`. Que voit `dns01` comme adresse source des questions ? Si `dns01` tombe, combien de temps les pods attendent-ils avant d'obtenir une réponse de `dns02`, et de quels réglages cela dépend-il ?

11. Ta politique `autoriser-dns` autorise UDP et TCP 53 vers `kube-dns`. Pourquoi TCP ? Et pourquoi n'as-tu pas eu besoin d'autoriser la sortie de CoreDNS vers `dns01` ?

12. *(QCM)* Tu ajoutes dans `wb-essais` une seconde politique qui sélectionne `echo` et autorise l'entrée depuis `sonde-w01b`. Le refus par défaut est toujours là. Résultat ?
    - A. `sonde-w01b` reste refusée : le refus par défaut l'emporte
    - B. `sonde-w01b` est acceptée par `echo`, mais sa propre sortie vers `echo` reste refusée tant qu'aucune politique de sortie ne l'autorise
    - C. `sonde-w01b` est acceptée dans les deux sens
    - D. La seconde politique est rejetée à l'admission

13. Pourquoi la Gateway API de Cilium exige-t-elle le remplacement de kube-proxy ? Décris le chemin d'une requête de `adm01` vers `/hostname` par `gw-essai`, du NodePort au pod `echo`, en nommant les composants.

14. Hubble a montré une requête HTTP avec sa méthode et son chemin seulement quand une politique L7 s'appliquait. Pourquoi ? Quel est le coût de cette visibilité, et pourquoi ne pas l'activer partout « pour voir » ?

15. Résume en cinq lignes, pour Claire, ce que le remplacement de kube-proxy a apporté, ce qu'il a coûté (pendant la fenêtre et en exploitation), et ce qu'il rend possible au palier suivant.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 15 questions avant d'ouvrir le corrigé, en citant au moins cinq observations de tes relevés (sorties de commandes, captures).
- [ ] Tu as noté chaque réponse avec la grille du corrigé et listé ce que tu dois revoir.

<details><summary>Indice 1</summary>

Pour les questions de chemin, reprends ta fiche `chemin-paquet.md` et ajoute ce qui a changé avec E08 : où la traduction des Services se fait maintenant.
</details>

<details><summary>Indice 2</summary>

Pour les politiques, raisonne toujours en deux moitiés : la sortie du client (sur son nœud) et l'entrée du serveur (sur le sien). Une connexion passe si **les deux** l'autorisent.
</details>

**Pour aller plus loin** (facultatif) : lis l'article « eBPF-based Networking, Observability, Security » de la documentation de Cilium (*Concepts*, *eBPF Datapath*), et reprends ta réponse à la question 7.

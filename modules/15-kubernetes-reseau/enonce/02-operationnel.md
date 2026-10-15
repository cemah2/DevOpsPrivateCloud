# Module 15 — Palier 2 : Opérationnel

Le palier 1 t'a fait suivre les paquets dans `k8s-par1`, écrire tes premières politiques, découvrir la Gateway API et retirer kube-proxy. Le cluster sait maintenant **router**, mais personne d'extérieur ne le joint : les Services `LoadBalancer` restent en `<pending>`, aucune adresse n'est annoncée à la bordure, aucun nom n'est publié, aucun certificat n'est délivré automatiquement. Ce palier construit **l'entrée du cluster**, telle qu'elle restera jusqu'aux finaux : des adresses de service attribuées par Cilium (LB IPAM) et annoncées en BGP à `gw01`/`gw02`, une Gateway principale `gw-par1` en HTTPS, des certificats émis par l'ACME de `ca01` grâce à cert-manager, des noms publiés tout seuls dans une zone DNS dédiée, puis les politiques réseau de MédiAgenda, la migration des Ingress d'InfoGér, une comparaison avec MetalLB, la publication hors du lab par les répartiteurs. Tu termines en relisant le travail de Lucas, en écrivant le runbook « service injoignable » et en décrivant tout le réseau du cluster dans `plateforme/k8s`.

> **Rappels du module** (introduction) : toute configuration du cluster passe par le projet `plateforme/k8s` (clone `~/src/k8s` sur `adm01`), une MR relue puis `task appliquer` (GitOps n'arrive qu'au M20) ; toute configuration d'hôte (bordure, DNS, répartiteurs) par un rôle Ansible de `plateforme/ansible` et son pipeline ; tout nouveau flux traversant la bordure par la matrice des flux (`group_vars/role_routeur/pare_feu.yml`) **et** `docs/socle/matrice-flux.md` ; tout secret par Ansible Vault (identité `lab`) et le registre des secrets, jamais en clair dans un dépôt ni sur une ligne de commande. Helm 4 est utilisé ici comme **simple installateur** : les commandes sont données, le packaging s'apprend au M17. `kubectl` se lance depuis `adm01` avec ton identité personnelle (`admin@adm01:~$`). Les vérifications se lancent depuis `adm01`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Cluster | `k8s-par1` 1.36, Cilium 1.20.x (CLI `cilium`, values `composants/cilium/values.yaml`), `kubeProxyReplacement: true` (M15-E08), tunnel VXLAN, Gateway API v1.6 canal standard et `gatewayAPI.enabled: true` (M15-E07) |
| Pool LB IPAM (E10) | `CiliumLoadBalancerIPPool` **`lb-par1`** : 10.10.41.10-10.10.41.199 ; **10.10.41.10 réservée à `gw-par1`** ; adresses d'essai 10.10.41.20-10.10.41.49 demandées explicitement |
| BGP (E11) | `CiliumBGPClusterConfig` **`bgp-par1`** (nœuds étiquetés `bgp=par1` : `k8s-w01` à `k8s-w03`), instance AS **65040** ; `CiliumBGPPeerConfig` **`bordure`** ; `CiliumBGPAdvertisement` **`services-lb`** (étiquette `bgp.medisphere.internal/annonce: services`) ; voisins `gw01` 10.10.40.2 et `gw02` 10.10.40.3, AS 65000, groupe `K8S` de la bordure (plage d'écoute 10.10.40.0/24, M07-E16) |
| Gateway principale (E12) | `gw-par1`, espace **`passerelles`**, `spec.addresses` 10.10.41.10 (nom `gw-par1.par1.medisphere.internal` dans NetBox), écouteurs `http` (80) et `https` (443, `*.apps.par1.medisphere.internal`, Secret **`apps-joker`**), routes admises depuis les espaces étiquetés **`medisphere.internal/exposition: oui`** ; route `redirection-https` (80 → 443) |
| Application publiée | MédiAgenda (`mediagenda-recette`, M14-E46) : HTTPRoute **`mediagenda`**, nom **`mediagenda-recette.apps.par1.medisphere.internal`**, Service `mediagenda-api` (port **80**, `targetPort: http` = 8000 du conteneur), PostgreSQL `postgresql` (5432), Valkey `valkey` (6379) — si tes objets du M14 portent d'autres noms, garde les tiens et adapte |
| cert-manager (E13, E14) | 1.21.x (chart OCI `quay.io/jetstack/charts/cert-manager`), espace `cert-manager` ; ClusterIssuer **`step-ca-acme`** (`https://ca01.par1.medisphere.internal/acme/acme/directory`) |
| Zone `apps` (E14) | **`apps.par1.medisphere.internal`** sur l'autoritaire primaire `dns01` (**10.10.20.10:5300**), secondaire `dns02` (AXFR/NOTIFY, clé `axfr-par1`), signée DNSSEC, DS dans `par1` ; clés TSIG **`certmanager-k8s`** et **`externaldns-k8s`** (hmac-sha256) |
| ExternalDNS (E15) | 0.23.x (chart 1.23.0), espace `external-dns`, fournisseur `rfc2136`, propriétaire `k8s-par1` |
| Espaces d'essai | `wb-essais` (étiqueté `medisphere.internal/exposition: oui` en E12), `wb-essais-2` (E16, jetable). Les politiques d'essai de M15-E06 ne doivent plus s'y trouver (`kubectl -n wb-essais get netpol,cnp` vide) : sinon, retire-les avant ce palier |
| Images d'essai | `registry.par1.medisphere.internal/k8s/e2e-test-images/agnhost:2.66.1` (cache Harbor de `registry.k8s.io`) |
| VM d'essai (E19) | `m15-essai` (VMID 2151, `vsandbox`, 10.10.99.51, 2 vCPU, 4 Go, état OpenTofu `m15-essai`) ; adresses MetalLB 10.10.99.230-10.10.99.238 |
| Documentation | `plateforme/medisphere` : `docs/kubernetes/reseau/`, runbooks `docs/kubernetes/reseau/runbooks/RB-15N-*.md` ; brouillons et journaux dans `~/m15/eXX/` sur `adm01` |

Durée indicative du palier : 26 à 32 heures. Ordre conseillé :

```
E10 ─ E11 ─ E12 ─ E13 ─ E14 ─ E15 ─┬─ E16
                                    ├─ E17
                                    ├─ E18
                                    └─ E20
E19 (indépendant, dès E10 compris)
E21 (dès E17 fait)    E22 (dès E15 fait)    E23 (en dernier : il reprend tout)
```

---

### M15-E10 — LB IPAM : des adresses de service en 10.10.41.0/24  `LAB` `★★`

> **Ticket PLAT-1610** — *De : Karim Benali*
> Depuis qu'on a branché la Gateway API, les Services `LoadBalancer` restent en `<pending>` : il n'y a pas de fournisseur de nuage pour leur donner une adresse. Le plan d'adressage a réservé le VLAN 41 pour ça. Je veux un seul pool, documenté, dont personne ne peut sortir, et une règle claire : l'adresse `.10` est celle de la future Gateway principale, personne d'autre n'y touche.

**Objectifs pédagogiques**
- Comprendre qui fait quoi pour un Service `LoadBalancer` hors nuage : attribution de l'adresse (LB IPAM), programmation du chemin de données (eBPF), annonce de l'adresse (BGP, palier suivant).
- Déclarer un `CiliumLoadBalancerIPPool`, lire son état et les conditions posées sur les Services.
- Demander une adresse précise, partager une adresse entre Services, observer un conflit de pools.

**Prérequis** : M15-E03 (Services), M15-E07 (Gateway d'essai `gw-essai`), M15-E08 (`kubeProxyReplacement: true`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- LB IPAM est intégré à l'opérateur Cilium, actif mais dormant tant qu'aucun pool n'existe. Il ne fait **que** l'attribution : sans BGP (E11), l'adresse n'est joignable que depuis les nœuds et les pods du cluster.
- Pool `lb-par1` : 10.10.41.10 à 10.10.41.199 (un bloc `start`/`stop`). Les adresses 10.10.41.200-254 restent hors pool (PLAN §4.2 : VIP futures, tests).
- LB IPAM n'a pas de notion d'adresse réservée : une adresse libre du pool part au premier Service qui en demande une sans préciser laquelle. Avant de créer le pool, aucun Service `LoadBalancer` ne doit attendre une adresse « au hasard » : la première libre serait `.10`, celle de `gw-par1` (E12). (Au palier 1, `gw-essai` passe par un Service `NodePort` et `gw-attente` a été supprimée : vérifie-le.)
- Fichiers : `composants/cilium/lb-ipam/lb-par1.yaml` dans `plateforme/k8s`, appliqué par `task appliquer` ; essais dans `~/m15/e10/` et l'espace `wb-essais`.

**Travail demandé**
1. Lis la page *Networking → LoadBalancer IP Address Management (LB IPAM)* de la documentation Cilium 1.20. Note dans `~/m15/e10/journal.md` : que se passe-t-il pour un Service dont `loadBalancerClass` vaut une classe inconnue de Cilium ? Que fait `allowFirstLastIPs` et pourquoi ne te concerne-t-il pas ici ? Que dit l'avertissement sur la modification d'un pool ?
2. Fais l'inventaire : liste tous les Services de type `LoadBalancer` du cluster (tous espaces) et leur état.
   ```
   admin@adm01:~$ kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | [.metadata.namespace, .metadata.name, (.status.loadBalancer.ingress // [] | map(.ip) | join(","))] | @tsv'
   ```
   Pour chacun, décide : supprimé, ou adresse explicite de la plage 10.10.41.11-10.10.41.19. Pour une Gateway, consulte la page *Gateway API Addresses Support* : l'adresse se demande par le champ prévu de la Gateway, pas sur son Service (qui appartient à Cilium).
3. Écris `lb-par1.yaml` (MR dans `plateforme/k8s`, puis `task appliquer`). Lis l'état du pool (`kubectl get ippools`, puis ses conditions en JSON).
4. Dans `wb-essais`, déploie `agnhost` (`netexec --http-port=8080`, 2 réplicas) et crée trois Services `LoadBalancer` port 80 → 8080 :
   - `essai-lb` qui **demande** 10.10.41.20 (annotation documentée par Cilium) ;
   - `essai-lb-a` et `essai-lb-b`, qui **partagent** l'adresse 10.10.41.22 (ports 80 et 8081).
   Relève les adresses obtenues. Jusqu'à E12, ne laisse **aucun** Service prendre une adresse automatique : la première adresse libre du pool est 10.10.41.10.
5. Teste depuis un nœud (`curl http://10.10.41.20/hostname` sur `k8s-w01`) et depuis un pod. Puis depuis `adm01` : explique dans le journal pourquoi ça échoue (route, annonce), avec la sortie de `ip route get 10.10.41.20` sur `adm01` et sur `gw01`.
6. Lis comment le chemin de données traite l'adresse : `kubectl -n kube-system exec ds/cilium -- cilium-dbg service list | grep 10.10.41.20`. Note le type de frontal affiché et les *backends*.
7. Provoque deux erreurs et lis les conditions : (a) un Service qui demande 10.10.41.250 (hors pool) ; (b) un second pool `essai-conflit` (10.10.41.150-10.10.41.160). Lis les messages (Service `status.conditions`, pool `cilium.io/PoolConflict`), puis supprime ces deux objets. Garde `essai-lb` (il sert en E11).

**Critères de réussite**
- [ ] Le pool `lb-par1` couvre exactement 10.10.41.10-10.10.41.199, il est actif et sans conflit ; c'est le seul pool du cluster.
- [ ] `essai-lb` a l'adresse 10.10.41.20 et répond depuis un nœud ; `essai-lb-a` et `essai-lb-b` ont la même adresse.
- [ ] Aucun Service n'occupe 10.10.41.10.
- [ ] `lb-par1.yaml` est sur `main` de `plateforme/k8s` ; le journal répond aux questions des étapes 1, 4, 5 et 6.

**Vérification** : `lab/bin/check 15 10`

<details><summary>Indice 1</summary>

La documentation montre deux formes de bloc : `cidr`, ou `start` et `stop` dans **un même** élément de la liste `blocks`. Attention aux tirets YAML : deux tirets font deux blocs.
</details>

<details><summary>Indice 2</summary>

Le partage d'adresse et la demande d'adresse précise passent par des annotations `lbipam.cilium.io/…` sur le Service. Deux Services ne partagent une adresse que si leurs ports ne se chevauchent pas, et (par défaut) s'ils sont dans le même espace.
</details>

<details><summary>Indice 3</summary>

Sur `adm01`, la route vers 10.10.41.0/24 est la route par défaut (la bordure) ; sur `gw01`, regarde si une route plus précise existe. Le réseau 10.10.41.0/24 n'est porté par aucune interface (PLAN §4.2 : « annoncé en BGP »).
</details>

**Pour aller plus loin** (facultatif) : lis la page *L2 Announcements* : pourquoi ce mode, qui répond aux requêtes ARP pour une adresse de service, ne conviendrait pas ici (10.10.41.0/24 n'est pas le réseau des nœuds) ?

---

### M15-E11 — BGP : annoncer les services à la bordure  `LAB` `★★★`

> **Ticket PLAT-1611** — *De : Claire Morel*
> La bordure attend Kubernetes depuis le module 7 : la plage d'écoute est prête, la politique d'entrée aussi, mais le groupe est fermé. On l'ouvre. Je veux que chaque adresse de service soit joignable depuis tout le lab, que la bordure n'accepte **que** le 10.10.41.0/24 et ne renvoie rien vers le cluster, et que la perte d'un travailleur ne coupe rien. Karim relit la MR côté bordure : c'est un changement sur un équipement partagé.

**Objectifs pédagogiques**
- Configurer le plan de contrôle BGP v2 de Cilium (`CiliumBGPClusterConfig`, `CiliumBGPPeerConfig`, `CiliumBGPAdvertisement`) et comprendre la sélection des nœuds et des annonces.
- Ouvrir côté FRR une session eBGP dynamique sous politique explicite, par MR Ansible, et en vérifier les effets avec `vtysh`.
- Lire l'état des sessions et des routes des deux côtés, et comprendre l'ECMP vers les nœuds.

**Prérequis** : M15-E10, M07-E16 et M07-E24 (FRR et groupe `K8S` de la bordure), M07-E29 (`ms-verif-reseau`).
**Durée indicative** : 3 h.

**Contexte technique**
- Bordure : FRR 10.7, AS 65000, `bgp ebgp-requires-policy` actif. `group_vars/role_routeur/frr.yml` décrit déjà le groupe `K8S` (AS 65040, `RM-K8S-IN` qui n'accepte que 10.10.41.0/24 jusqu'aux /32, `RM-K8S-OUT` qui refuse tout) et, dans `frr_config_supplementaire`, la plage d'écoute 10.10.40.0/24 **et** `neighbor K8S shutdown`. Le pare-feu des passerelles accepte déjà TCP 179 depuis 10.10.40.0/24 (`pare_feu_entree`).
- Une plage d'écoute est **passive** : la bordure attend. Côté Cilium, l'agent **initie** les sessions (il n'écoute pas, sauf `localPort`). Chaque travailleur parle à `gw01` (10.10.40.2) **et** à `gw02` (10.10.40.3), jamais à la VIP .1.
- Seuls les travailleurs portent les sessions : étiquette de nœud `bgp=par1` sur `k8s-w01..03`. Les nœuds de contrôle n'annoncent rien.
- Cilium : `bgpControlPlane.enabled: true` dans `composants/cilium/values.yaml`, appliqué par `cilium upgrade --version 1.20.<PATCH> --values …` (même commande que M14-E05, `<PATCH>` = ta version). Les CRD BGP vont dans `composants/cilium/bgp/`.
- Pas de mot de passe TCP-MD5 sur ces sessions : le M07 n'en a pas mis sur le groupe `K8S` (les sessions de la fabric en avaient). Le corrigé discute ce choix.
- La CLI `cilium` lit l'état BGP des agents (`cilium bgp peers`, `cilium bgp routes`).

> ⚠️ **Attention** : la MR touche la configuration FRR des **deux** passerelles, qui routent tout le lab. Le rôle `frr` valide la configuration (`vtysh --dryrun`) avant de l'installer, et le pipeline l'applique passerelle par passerelle. Avant d'appliquer, note la sortie de `sudo vtysh -c 'show bgp summary'` sur `gw01` et `gw02` ; retour arrière : réverter la MR et relancer le pipeline (le groupe `K8S` se referme, les autres sessions ne sont pas touchées).

**Travail demandé**
1. Lis *Networking → BGP Control Plane* (*Resources* et *Operation*) de Cilium 1.20. Dans `~/m15/e11/journal.md`, dessine qui parle à qui (nœud, AS, adresses) et réponds : pourquoi la session ne peut-elle pas s'établir tant que `neighbor K8S shutdown` existe, même si Cilium est configuré ? Que se passe-t-il si une `CiliumBGPPeerConfig` ne sélectionne **aucune** annonce ?
2. Bordure (MR sur `plateforme/ansible`, relue par Karim) : ouvre le groupe `K8S`, borne le nombre de préfixes acceptés par voisin (le pool en compte 190 au plus), et rends explicite le nombre de chemins égaux installés (ECMP) plutôt que de dépendre d'une valeur par défaut. Ajoute les trois travailleurs à la liste des voisins attendus de `ms-verif-reseau` (`plateforme/outils`). Pipeline, puis `sudo vtysh -c 'show bgp peer-group K8S'` sur les deux passerelles.
3. Étiquette les travailleurs (`bgp=par1`) de façon reproductible (dans `plateforme/k8s`, pas seulement par une commande) et active le plan de contrôle BGP dans les values de Cilium. Applique, puis vérifie `cilium status` et la présence des CRD `ciliumbgp*`.
4. Écris les trois objets dans `composants/cilium/bgp/` : `bgp-par1` (instance AS 65040, deux voisins), `bordure` (temporisateurs 3/9 s, nouvel essai de connexion rapide, famille IPv4 unicast qui sélectionne les annonces par étiquette), `services-lb` (adresses `LoadBalancerIP` de **tous** les Services). MR, `task appliquer`.
5. Côté Cilium : `cilium bgp peers`, `cilium bgp routes advertised ipv4 unicast`, et l'état d'un `CiliumBGPNodeConfig` (`kubectl get ciliumbgpnodeconfigs`). Côté bordure : `show bgp summary`, `show bgp ipv4 unicast 10.10.41.20/32`, `show ip route 10.10.41.20`. Combien de chemins, et lesquels sont installés ?
6. Depuis `adm01` : `curl http://10.10.41.20/hostname` en boucle (20 fois). Tous les pods répondent-ils ? Par quel nœud entre le trafic ? (`hubble observe --ip 10.10.41.20` ou `tcpdump` sur un nœud.)
7. Politique : prouve que la bordure refuse ce qu'elle ne doit pas accepter. Crée un Service `essai-hors-pool` avec `spec.externalIPs: [10.10.42.10]` et ajoute temporairement `ExternalIP` aux adresses de `services-lb`. Que voit Cilium (annoncé) et que voit la bordure (`show bgp neighbors 10.10.40.61 received-routes` est-il possible ? sinon `show bgp ipv4 unicast 10.10.42.10/32`) ? Retire l'essai et le type `ExternalIP`.
8. Panne d'un travailleur : `cordon` puis `drain` de `k8s-w02`, retire-lui l'étiquette `bgp=par1` et mesure, depuis `adm01`, la perte pendant la boucle de l'étape 6. Remets tout en place. Note le temps de retrait de la route sur `gw01`.
9. Documente le flux et la décision dans `docs/kubernetes/reseau/bgp.md` (`plateforme/medisphere`).

**Critères de réussite**
- [ ] Les trois travailleurs ont une session `established` avec `gw01` et avec `gw02` (six sessions) ; les nœuds de contrôle n'en ont aucune.
- [ ] `gw01` et `gw02` ont une route 10.10.41.20/32 avec plusieurs prochains sauts (ECMP) ; le groupe `K8S` n'est plus fermé et garde ses politiques d'entrée et de sortie.
- [ ] `curl http://10.10.41.20/hostname` répond depuis `adm01`.
- [ ] Les objets BGP et l'étiquetage des nœuds sont dans `plateforme/k8s`, la MR FRR est fusionnée dans `plateforme/ansible` ; le journal contient les mesures des étapes 6 et 8.

**Vérification** : `lab/bin/check 15 11`

<details><summary>Indice 1</summary>

Le rôle `frr` de M07 rend `frr_config_supplementaire` tel quel, et il sait déjà rendre `maximum_paths` à partir des données structurées de `frr_bgp`. Une borne de préfixes s'écrit par voisin ou par groupe dans `address-family ipv4 unicast`.
</details>

<details><summary>Indice 2</summary>

Une `CiliumBGPPeerConfig` relie une famille d'adresses à des annonces **par sélecteur d'étiquettes** : l'étiquette doit être portée par la `CiliumBGPAdvertisement` elle-même. Pour annoncer tous les Services, la documentation propose une expression `NotIn` sur une clé factice.
</details>

<details><summary>Indice 3</summary>

Si les sessions restent en `active`/`idle` : vérifie dans l'ordre l'étiquette des nœuds (`kubectl get ciliumbgpclusterconfig bgp-par1 -o yaml`, conditions), les journaux de l'agent (`subsys=bgp-control-plane`), `ss -tn dport = :179` sur un travailleur, le compteur de la règle 179 dans `nft list ruleset` sur la passerelle, puis `show bgp neighbors` côté FRR.
</details>

**Pour aller plus loin** (facultatif) : lis la section *Graceful Restart* : quel compromis fait-il entre redémarrage d'agent sans coupure et détection d'une vraie panne ? (Le palier 3, E25, le mesure.)

---

### M15-E12 — La Gateway principale `gw-par1` et le TLS  `LAB` `★★★`

> **Ticket DEV-1612** — *De : Julien Petit*
> J'ai une recette MédiAgenda qui tourne, mais il faut un `port-forward` pour la voir. Il me faut une vraie adresse en HTTPS, avec un nom en `*.apps`, et que mes développeurs puissent ajouter leurs routes sans vous demander de toucher à l'entrée. Et que le HTTP renvoie vers le HTTPS, toujours.

**Objectifs pédagogiques**
- Concevoir une Gateway partagée : écouteurs, noms, certificats, et délégation des routes aux équipes (`allowedRoutes`).
- Comprendre la répartition des rôles de la Gateway API (exploitant de l'infrastructure, opérateur de cluster, équipe applicative).
- Publier une application en HTTPS et rediriger le HTTP.

**Prérequis** : M15-E07, M15-E11, M14-E46 (MédiAgenda en `mediagenda-recette`), M06-E18 (step-ca).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Gateway `gw-par1`, espace `passerelles` (nouvel espace, à décrire dans `espaces/` de `plateforme/k8s`, PSA `restricted`), classe `cilium`, adresse **10.10.41.10** par `spec.addresses`.
- Écouteurs : `http` (port 80, sans nom d'hôte : il servira aussi aux défis ACME HTTP-01 d'E13 pour des noms hors `apps`) et `https` (port 443, `*.apps.par1.medisphere.internal`, terminaison TLS, Secret `apps-joker` du même espace). Routes admises sur les deux depuis les seuls espaces étiquetés `medisphere.internal/exposition: oui`.
- Le certificat définitif `apps-joker` sera émis par cert-manager en E14 (défi DNS-01, seul possible pour un nom joker). **Pour ce ticket**, tu l'émets à la main avec le provisioner JWK `admin` de `ca01` (7 jours au plus, `~/.config/workbook/step-admin.pass`), et tu le ranges dans le Secret sans laisser la clé sur un disque.
- La zone `apps` n'existe pas encore (E14) : les essais se font avec `curl --resolve <nom>:443:10.10.41.10`. L'adresse 10.10.41.10 est déclarée dans NetBox (préfixe 10.10.41.0/24, rôle VIP, `dns_name` `gw-par1.par1.medisphere.internal`) : `medictl dns sync` (M06-E15) publie son A et son PTR.
- Flux : MGMT joint déjà tout le lab (dont 10.10.41.0/24) ; rien à ouvrir pour ce ticket.

**Travail demandé**
1. Lis *Gateway API → Concepts → Security model* et *API Overview* sur gateway-api.sigs.k8s.io, puis la page *Gateway API Support* de Cilium 1.20 (sections *Addresses*, *Source IP Visibility*). Dans `~/m15/e12/journal.md` : qui, chez MédiSphère, possède la GatewayClass, la Gateway, les HTTPRoute ? Que garantit `allowedRoutes` et que ne garantit-il pas ?
2. Crée l'espace `passerelles` et étiquette `passerelles`, `mediagenda-recette` et `wb-essais` pour l'exposition (dans `espaces/` de `plateforme/k8s`).
3. Émets le certificat joker :
   ```
   admin@adm01:~$ T=/run/user/$(id -u)/joker && install -d -m 700 "$T"    # tmpfs : en mémoire
   admin@adm01:~$ step ca certificate '*.apps.par1.medisphere.internal' "$T/joker.crt" "$T/joker.key" \
       --provisioner admin --provisioner-password-file ~/.config/workbook/step-admin.pass --not-after 168h
   ```
   Crée le Secret `apps-joker` (type `kubernetes.io/tls`) dans `passerelles` à partir de ces deux fichiers, puis efface le répertoire. Note l'empreinte et l'échéance du certificat.
4. Écris `composants/passerelles/gw-par1.yaml` (Gateway) et `composants/passerelles/redirection-https.yaml` (HTTPRoute attachée au seul écouteur `http`, pour les noms `*.apps…`, réponse 301 vers `https`). MR, `task appliquer`. Lis les conditions de la Gateway (`Accepted`, `Programmed`) et de chaque écouteur (`ResolvedRefs`), et le Service créé par Cilium.
5. Crée la HTTPRoute `mediagenda` dans `mediagenda-recette` (nom `mediagenda-recette.apps.par1.medisphere.internal`, écouteur `https`, Service `mediagenda-api`). Où la ranges-tu ? Justifie dans le journal.
6. Teste depuis `adm01` sans contourner TLS :
   ```
   admin@adm01:~$ curl -sS --resolve mediagenda-recette.apps.par1.medisphere.internal:443:10.10.41.10 \
       https://mediagenda-recette.apps.par1.medisphere.internal/sante
   admin@adm01:~$ curl -sSI --resolve mediagenda-recette.apps.par1.medisphere.internal:80:10.10.41.10 \
       http://mediagenda-recette.apps.par1.medisphere.internal/sante
   ```
   Puis `openssl s_client -connect 10.10.41.10:443 -servername mediagenda-recette.apps.par1.medisphere.internal` : émetteur, nom, échéance. Que se passe-t-il avec `-servername essai.ailleurs.internal` ?
7. Délégation : crée dans `mediagenda-dev` (non étiqueté) une HTTPRoute vers `gw-par1`. Lis son état et explique le refus. Supprime-la.
8. Adresse : déclare 10.10.41.10 dans NetBox, lance `medictl dns sync` et vérifie A et PTR de `gw-par1.par1.medisphere.internal`.
9. Note dans le journal ce que voit MédiAgenda de l'adresse du client (journal de l'API, en-tête `X-Forwarded-For`).

**Critères de réussite**
- [ ] `gw-par1` est `Programmed` avec l'adresse 10.10.41.10, deux écouteurs conformes, routes admises par étiquette d'espace.
- [ ] `https://mediagenda-recette.apps.par1.medisphere.internal/sante` répond 200 via 10.10.41.10 avec un certificat de la PKI MédiSphère vérifié ; le HTTP répond 301 vers `https`.
- [ ] Une route d'un espace non étiqueté n'est pas acceptée par `gw-par1`.
- [ ] `gw-par1.par1.medisphere.internal` résout en 10.10.41.10 (et inversement) depuis NetBox ; la clé du certificat n'est sur aucun disque de `adm01`.

**Vérification** : `lab/bin/check 15 12`

<details><summary>Indice 1</summary>

`allowedRoutes.namespaces.from` accepte `Same`, `All` et `Selector` ; avec `Selector`, c'est un sélecteur d'étiquettes **d'espaces de noms**. Chaque écouteur a le sien.
</details>

<details><summary>Indice 2</summary>

`kubectl create secret tls` lit des fichiers ; `--dry-run=client -o yaml` produit le manifeste sans rien envoyer, et `kubectl apply -f -` le lit sur l'entrée standard. Un Secret ne se versionne pas : seul l'objet qui le produit (ici, en E14, un `Certificate`) le sera.
</details>

<details><summary>Indice 3</summary>

Une HTTPRoute choisit son écouteur par `parentRefs[].sectionName`. Le nom d'hôte d'une route doit **recouper** celui de l'écouteur (`*.apps…` recouvre `mediagenda-recette.apps…`, pas `apps…` lui-même). La redirection est un filtre `RequestRedirect` d'une règle sans `backendRefs`.
</details>

**Pour aller plus loin** (facultatif) : lis *Gateway API → Guides → HTTP redirects and rewrites* et la GEP sur `ListenerSet` : en quoi changerait-elle la délégation des noms aux équipes ?

---

### M15-E13 — cert-manager et l'ACME de step-ca  `LAB` `★★`

> **Ticket SEC-1613** — *De : Sophie Laurent*
> Un certificat de 7 jours émis à la main par un humain, c'est une panne programmée. Je veux que les certificats du cluster soient émis et renouvelés par la PKI MédiSphère, par ACME comme les serveurs du socle, avec 30 jours de validité et un renouvellement automatique. Et je veux pouvoir lire qui a demandé quoi.

**Objectifs pédagogiques**
- Installer cert-manager et comprendre ses objets (`ClusterIssuer`, `Certificate`, `CertificateRequest`, `Order`, `Challenge`).
- Configurer un émetteur ACME privé (adresse, autorité de confiance, compte) et un solveur HTTP-01 par la Gateway API.
- Suivre une émission de bout en bout et diagnostiquer chaque étape.

**Prérequis** : M15-E12, M06-E18 (provisioner `acme` de `ca01`), M06-E27 (durées).
**Durée indicative** : 2 h.

**Contexte technique**
- cert-manager 1.21.x, chart OCI `oci://quay.io/jetstack/charts/cert-manager`, version `v1.21.<PATCH>`, espace `cert-manager`, CRD installées par le chart. Le support de la Gateway API **doit être activé** explicitement dans la configuration du contrôleur (en 1.21, le champ s'est déplacé : lis les notes de version). Values : `composants/cert-manager/values.yaml`.
- Émetteur : ClusterIssuer `step-ca-acme`, serveur `https://ca01.par1.medisphere.internal/acme/acme/directory` ; la racine « MédiSphère Root CA » n'est pas dans les images de cert-manager : elle doit être fournie à l'émetteur. Clé de compte ACME : Secret `step-ca-acme-compte` (créé par cert-manager dans `cert-manager`).
- Solveur HTTP-01 : HTTPRoute temporaire créée par cert-manager et attachée à l'écouteur `http` de `gw-par1`. `ca01` vient chercher la réponse sur `http://<nom>/.well-known/acme-challenge/…`, donc sur 10.10.41.10:80 : **flux à ouvrir** à la bordure (INFRA → 10.10.41.10 TCP 80, source `ca01` seulement).
- Nom d'essai : `gw-par1.par1.medisphere.internal` (E12, déjà publié). Certificate `essai-http01` dans `wb-essais`.

**Travail demandé**
1. Lis *cert-manager → Concepts* (*Issuer*, *Certificate*, *CertificateRequest*, *ACME Orders and Challenges*) et *Configuration → ACME → HTTP01* (section *Gateway API*). Dans `~/m15/e13/journal.md`, dessine la chaîne d'objets d'une émission ACME et dis qui crée chacun.
2. Ouvre le flux `ca01` → 10.10.41.10:80 (matrice des flux et documentation, MR, pipeline). Teste depuis `ca01` avec `curl -sI http://gw-par1.par1.medisphere.internal/` (une 404 de la Gateway prouve que le chemin est ouvert).
3. Écris les values (CRD gérées par le chart, Gateway API activée, deux réplicas du contrôleur et du webhook, PodDisruptionBudget) et installe :
   ```
   admin@adm01:~/src/k8s$ helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
       --version v1.21.<PATCH> --namespace cert-manager --create-namespace \
       --values composants/cert-manager/values.yaml --wait
   ```
   Vérifie les trois Deployments, les CRD, et la configuration lue par le contrôleur (journaux au démarrage).
4. Écris `composants/cert-manager/clusterissuer-step-ca-acme.yaml` : serveur, autorité de confiance (racine en base64), Secret de compte, un solveur `http01.gatewayHTTPRoute` qui vise `gw-par1` et son écouteur `http`. MR, `task appliquer`. Lis l'état de l'émetteur (`kubectl describe clusterissuer step-ca-acme`) : compte enregistré ?
5. Demande `essai-http01` (Secret `essai-http01-tls`) pour `gw-par1.par1.medisphere.internal`. Pendant l'émission, observe dans l'ordre `certificaterequest`, `order`, `challenge`, la HTTPRoute temporaire (dans quel espace ?), puis le journal de `ca01` (`journalctl -u step-ca`). Relève la durée du certificat obtenu.
6. Renouvellement : lis `status.renewalTime`, force un renouvellement (`cmctl renew`, ou à défaut l'annotation documentée), et vérifie que le numéro de série du Secret change. (`cmctl` : binaire du projet cert-manager, à installer sur `adm01` ; épingle sa version.)
7. Erreur volontaire : retire temporairement `caBundle` de l'émetteur (sur une copie, `step-ca-acme-essai`), demande un certificat avec elle, et note le message obtenu. Supprime ensuite la copie et le certificat.
8. Note dans le journal ce qui manque encore pour un nom `*.apps` et pourquoi HTTP-01 ne suffira jamais pour lui.

**Critères de réussite**
- [ ] cert-manager 1.21 tourne dans `cert-manager` (contrôleur et webhook à deux réplicas), avec la Gateway API activée.
- [ ] `step-ca-acme` est `Ready` ; il fait confiance à la seule racine MédiSphère fournie et résout HTTP-01 par `gw-par1`.
- [ ] `essai-http01` est `Ready`, émis par l'intermédiaire MédiSphère, valable 30 jours au plus, et a été renouvelé une fois.
- [ ] Le flux `ca01` → 10.10.41.10:80 est dans la matrice des flux (dépôt et documentation) ; les values et l'émetteur sont sur `main` de `plateforme/k8s`.

**Vérification** : `lab/bin/check 15 13`

<details><summary>Indice 1</summary>

Le champ `caBundle` de l'émetteur ACME attend le PEM **encodé en base64** (pas un nom de ConfigMap). Le Secret de compte est désigné par `privateKeySecretRef` : tu ne le crées pas, cert-manager le fait.
</details>

<details><summary>Indice 2</summary>

Le solveur `gatewayHTTPRoute` prend des `parentRefs` comme une route ordinaire (nom, espace, `sectionName`) ; la route temporaire est créée dans l'espace du **Certificate** : cet espace doit donc être admis par l'écouteur.
</details>

<details><summary>Indice 3</summary>

Si l'`Order` reste `pending` : `kubectl describe challenge` dit si l'autocontrôle de cert-manager (il interroge lui-même l'URL avant de prévenir `ca01`) a échoué ; s'il passe et que `ca01` échoue, cherche du côté du flux ou de la résolution du nom **depuis `ca01`**.
</details>

**Pour aller plus loin** (facultatif) : lis la page sur ACME ARI (fonctionnalité `ACMEUseARI` de cert-manager 1.21) : step-ca 0.30 expose-t-il `renewalInfo` ? Que changerait ARI pour la PKI ?

---

### M15-E14 — Défis DNS-01 par RFC 2136 : la zone `apps`  `LAB` `★★★`

> **Ticket PLAT-1614** — *De : Karim Benali*
> Pour le joker `*.apps`, pas le choix : DNS-01. Je ne veux pas que cert-manager ait la clé d'API PowerDNS, qui peut réécrire tout le DNS du site. On crée une zone dédiée aux applications du cluster, on y autorise des mises à jour RFC 2136 signées par des clés qui ne valent **que** pour elle, depuis le seul VLAN des nœuds. Elle est signée comme `par1`, et répliquée sur `dns02`.

**Objectifs pédagogiques**
- Créer et déléguer une zone signée par le code (rôle `powerdns_auth`, OpenTofu), avec la chaîne de confiance DNSSEC.
- Autoriser des mises à jour dynamiques par zone, par clé TSIG et par adresse (PowerDNS 5.0).
- Résoudre un défi DNS-01 par cert-manager et obtenir un certificat joker.

**Prérequis** : M15-E13, M06-E17 (mises à jour dynamiques, clé `ddns-kea`), M06-E24 (secondaire), M06-E26 (DNSSEC), M06-E30 (pare-feu local).
**Durée indicative** : 3 h 30.

**Contexte technique**
- L'autoritaire écoute sur **10.10.20.10:5300** (et 10.10.20.16:5300 pour le secondaire) ; le port 53 est celui des récurseurs, qui ne relaient pas les mises à jour. cert-manager et ExternalDNS enverront donc leurs messages UPDATE à 10.10.20.10:5300.
- Zone `apps.par1.medisphere.internal` : ajoutée à `powerdns_auth_zones` (contenu piloté par mises à jour, comme `par1`) et à `powerdns_auth_zones_signees` ; le rôle crée la zone, ses NS, la réplication et la signature. Délégation dans `par1` (NS et DS) : `par1` est pilotée par l'API, donc par OpenTofu (`plateforme/infra`, état `k8s`, fournisseur `mmianl/powerdns` comme en M08). Les ancres de confiance des récurseurs ne changent pas (`par1` signée, DS publié).
- Autorisations de la zone (et d'elle seule) : clés `certmanager-k8s` et `externaldns-k8s` (hmac-sha256), source 10.10.40.0/24 (les pods sortent avec l'adresse de leur nœud), NOTIFY après chaque mise à jour. Le rôle `powerdns_auth` ne sait pas encore poser ces métadonnées : tu l'étends (nouvelles variables, nouveau fichier de tâches, scénario Molecule). PowerDNS 5.0 a changé la syntaxe de `pdnsutil` et la façon d'ajouter **plusieurs** clés à `TSIG-ALLOW-DNSUPDATE` : lis la page *Dynamic DNS Update* de la version 5.0.
- Secrets : les deux secrets TSIG dans le Vault `lab` (`group_vars/role_dns/vault-lab.yml`), inscrits au registre des secrets ; côté Kubernetes, Secret `tsig-certmanager-k8s` (espace `cert-manager`) et `tsig-externaldns-k8s` (espace `external-dns`, pour E15), créés depuis le Vault par un petit outil de `plateforme/k8s` (`outils/secret-tsig.sh`), sans fichier en clair.
- Flux : 10.10.40.0/24 → 10.10.20.10 TCP/UDP 5300 à la bordure **et** dans le pare-feu local de `dns01` (M06-E30).

> ⚠️ **Attention** : tu modifies l'autoritaire de **tout** le site et la zone signée `par1`. Une délégation avec un DS faux rend `apps` injoignable (SERVFAIL) ; un changement raté du rôle peut redémarrer PowerDNS. Avant le pipeline : `sudo -u pdns pdnsutil zone list-all` et `dig @10.10.20.10 -p 5300 par1.medisphere.internal SOA` sur `dns01` (à garder). Retour arrière : réverter la MR (la zone `apps` reste, inerte), et `tofu destroy -target` des enregistrements NS/DS de la délégation.

**Travail demandé**
1. Lis *Dynamic DNS Update (RFC 2136)* (PowerDNS 5.0), *cert-manager → ACME → DNS01 → RFC2136* et la section *Setting Nameservers for DNS01 Self Check*. Dans `~/m15/e14/journal.md` : quelles conditions PowerDNS vérifie-t-il, dans quel ordre, avant d'accepter une mise à jour ? Que peut faire la clé `certmanager-k8s` dans la zone (sois honnête) ? Pourquoi l'autocontrôle de cert-manager doit-il interroger l'autoritaire plutôt que les récurseurs, et quel prix paie-t-on ?
2. Génère les deux secrets TSIG directement dans le Vault (aucune trace en clair), inscris-les au registre des secrets.
3. Étends le rôle `powerdns_auth` : clés TSIG de mise à jour, et, par zone, clés autorisées, réseaux sources, NOTIFY, et clés autorisées à transférer la zone (ExternalDNS lira la zone par AXFR en E15). Idempotence et `no_log` comme dans `replication.yml`. Scénario Molecule mis à jour.
4. Ajoute la zone et ses autorisations à l'inventaire, ouvre les flux (bordure et `dns01`), MR, pipeline. Vérifie sur les deux serveurs (`dig @10.10.20.10 -p 5300`, `@10.10.20.16 -p 5300`) : SOA, NS, DNSKEY, numéros de série égaux.
5. Délégation : écris `envs/k8s/dns-apps.tf` (NS et DS de `apps` dans `par1`). Récupère le DS par la sortie du rôle ou par `pdnsutil zone export-ds`. `tofu plan`, MR, `apply`. Vérifie par les récurseurs : `dig @10.10.20.10 apps.par1.medisphere.internal SOA +dnssec` doit montrer le bit `ad`.
6. Essai à la main depuis le cluster : un pod jetable dans `wb-essais` (image `registry.par1.medisphere.internal/dockerhub/internetsystemsconsortium/bind9:9.20`, clé montée depuis un Secret d'essai) envoie avec `nsupdate` un TXT `essai.apps.par1.medisphere.internal`. Vérifie-le sur les deux serveurs, supprime-le. Refais le même envoi depuis `adm01` : refus attendu. Pourquoi ?
7. Crée le Secret `tsig-certmanager-k8s` par l'outil, ajoute à `step-ca-acme` un solveur DNS-01 `rfc2136` réservé à la zone `apps`, et règle l'autocontrôle DNS-01 de cert-manager (values). MR, applications.
8. Remplace le certificat manuel d'E12 : `Certificate` `apps-joker` dans `passerelles` (Secret `apps-joker`, noms `*.apps.par1.medisphere.internal`). Pendant l'émission, regarde l'enregistrement `_acme-challenge` apparaître puis disparaître sur l'autoritaire, et le journal de `ca01`. La Gateway sert-elle le nouveau certificat sans redémarrage ?

**Critères de réussite**
- [ ] La zone `apps.par1.medisphere.internal` est servie par `dns01` et `dns02` (même numéro de série), signée, et validée (`ad`) par les récurseurs.
- [ ] Les mises à jour de la zone exigent `certmanager-k8s` ou `externaldns-k8s` et viennent de 10.10.40.0/24 ; une mise à jour depuis `adm01` est refusée ; aucune autre zone n'accepte ces clés.
- [ ] `apps-joker` est émis par cert-manager (ACME, DNS-01), valable 30 jours au plus, et présenté par `gw-par1`.
- [ ] Secrets dans le Vault `lab` et au registre ; rôle, inventaire, flux et délégation fusionnés ; journal complet.

**Vérification** : `lab/bin/check 15 14`

<details><summary>Indice 1</summary>

`pdnsutil tsigkey import` installe une clé, `pdnsutil metadata add` **ajoute** une valeur à une métadonnée (`set` remplace la liste entière). `NOTIFY-DNSUPDATE` vaut `1` pour être actif. Le transfert de zone autorisé par clé, tu l'as déjà rencontré dans `replication.yml` (`pdnsutil tsigkey activate`).
</details>

<details><summary>Indice 2</summary>

Les deux réglages d'autocontrôle de cert-manager (`dns01RecursiveNameservers`, `dns01RecursiveNameserversOnly`) acceptent une adresse **avec port**. Le sélecteur `dnsZones` d'un solveur s'applique au nom demandé **et à ses sous-domaines**.
</details>

<details><summary>Indice 3</summary>

`nsupdate -y hmac-sha256:<nom>:<secret>` mettrait le secret dans `ps` : préfère `-k <fichier>` avec un fichier de clé au format `key "<nom>" { algorithm hmac-sha256; secret "<base64>"; };` monté dans le pod. Le message `REFUSED` sans autre détail vient d'une adresse non autorisée ; `NOTAUTH` d'une signature absente ou fausse ; regarde aussi `journalctl -u pdns` sur `dns01`.
</details>

**Pour aller plus loin** (facultatif) : PowerDNS 5.0 accepte une politique de mise à jour en Lua (`lua-dnsupdate-policy-script`) : esquisse celle qui limiterait `certmanager-k8s` aux seuls TXT `_acme-challenge.*`. Quel est l'effet de bord annoncé par la documentation sur les autres autorisations ?

---

### M15-E15 — ExternalDNS : publier les noms automatiquement  `LAB` `★★`

> **Ticket DEV-1615** — *De : Julien Petit*
> Le certificat joker règle le HTTPS, mais il me faut toujours un ticket pour chaque nom. Je voudrais que créer une route dans mon espace crée le nom, et que la supprimer le retire. Sans que mes équipes puissent écrire dans le DNS du reste de l'entreprise.

**Objectifs pédagogiques**
- Déployer ExternalDNS avec le fournisseur `rfc2136` et comprendre sa boucle (sources → plan → registre TXT → fournisseur).
- Limiter ce qu'il publie : domaine, sources, Gateways, objets exclus, propriétaire.
- Vérifier le cycle de vie complet d'un nom.

**Prérequis** : M15-E14.
**Durée indicative** : 1 h 30.

**Contexte technique**
- ExternalDNS 0.23.x, chart `external-dns/external-dns` 1.23.0 (dépôt `https://kubernetes-sigs.github.io/external-dns`), espace `external-dns`, values `composants/external-dns/values.yaml`.
- Fournisseur `rfc2136` vers 10.10.20.10:5300, zone `apps.par1.medisphere.internal`, clé `externaldns-k8s` (Secret `tsig-externaldns-k8s` d'E14, lu par variable d'environnement, jamais en argument). Lecture de la zone par AXFR signé (autorisé en E14).
- Sources : routes HTTP de la Gateway API et Services `LoadBalancer` ; seulement les routes attachées à `gw-par1` ; politique `sync` (création **et** suppression) ; registre TXT, propriétaire `k8s-par1`.
- ExternalDNS 0.23 lit ses annotations sous le préfixe `external-dns.kubernetes.io/` ; l'ancien préfixe `external-dns.alpha.kubernetes.io/` n'est plus lu par défaut. Vérifie dans `--help` de la version déployée.
- La route `redirection-https` d'E12 porte le nom `*.apps…` : publiée telle quelle, elle créerait un **joker DNS** qui ferait résoudre n'importe quel nom. Elle doit être exclue.

**Travail demandé**
1. Lis le *README* d'ExternalDNS, *Gateway API Route Sources* et le tutoriel *RFC2136* de la version 0.23. Dans `~/m15/e15/journal.md` : pourquoi la politique `sync` exige-t-elle l'AXFR avec ce fournisseur ? À quoi sert le registre TXT, et que se passe-t-il si deux clusters écrivent dans la même zone avec le même propriétaire ?
2. Écris les values (fournisseur, arguments `rfc2136`, secret par variable d'environnement, sources, filtre de domaine, Gateway visée, filtre d'exclusion, propriétaire, journal JSON) et installe :
   ```
   admin@adm01:~/src/k8s$ helm repo add external-dns https://kubernetes-sigs.github.io/external-dns
   admin@adm01:~/src/k8s$ helm upgrade --install external-dns external-dns/external-dns --version 1.23.0 \
       --namespace external-dns --values composants/external-dns/values.yaml --wait
   ```
   (Crée d'abord l'espace et le Secret par l'outil d'E14.) Lis le journal du pod : zone lue, plan calculé, mises à jour envoyées.
3. Exclus `redirection-https` de la publication (étiquette posée dans `plateforme/k8s`), puis vérifie : `mediagenda-recette.apps…` résout en 10.10.41.10 par les récurseurs, et `inexistant.apps…` ne résout **pas**.
4. Cycle de vie : crée dans `wb-essais` une HTTPRoute `essai-dns` (`essai-dns.apps.par1.medisphere.internal`) vers `agnhost`, attends sa publication, teste-la en HTTPS **sans** `--resolve`, supprime-la, vérifie que le nom disparaît. Mesure les délais.
5. Service : annote `essai-lb` (E10) pour publier `essai-lb.apps.par1.medisphere.internal`. Quelle adresse est publiée ?
6. Garde-fous : (a) une route avec un nom hors zone (`essai.par1.medisphere.internal`) ; (b) une route attachée à `gw-essai`. Que fait ExternalDNS dans chaque cas ? Supprime ces essais.
7. Lis les enregistrements TXT de propriété dans la zone (`dig @10.10.20.10 -p 5300 … AXFR` avec la clé, depuis un nœud, ou `TXT` ciblés) et explique leur contenu.
8. Mets à jour `docs/kubernetes/reseau/entree-du-cluster.md` (`plateforme/medisphere`) : comment une équipe publie une application (espace étiqueté, route, nom), ce qu'elle ne peut pas faire.

**Critères de réussite**
- [ ] ExternalDNS 0.23 tourne dans `external-dns`, fournisseur `rfc2136` vers 10.10.20.10:5300, propriétaire `k8s-par1`, filtre `apps.par1.medisphere.internal`, politique `sync`, secret absent des arguments.
- [ ] `mediagenda-recette.apps.par1.medisphere.internal` résout en 10.10.41.10 avec un TXT de propriété `k8s-par1` ; aucun joker n'est publié.
- [ ] Une route créée puis supprimée fait apparaître puis disparaître son nom (mesures dans le journal).
- [ ] Values et étiquette d'exclusion sur `main` de `plateforme/k8s` ; documentation à jour.

**Vérification** : `lab/bin/check 15 15`

<details><summary>Indice 1</summary>

Les options du fournisseur passent par `extraArgs` du chart ; la liste exacte est dans `docs/flags.md` de la version (`--rfc2136-host`, `--rfc2136-port`, `--rfc2136-zone`, `--rfc2136-tsig-keyname`, `--rfc2136-tsig-secret-alg`, `--rfc2136-axfr`…). Le tutoriel montre comment remplacer `--rfc2136-tsig-secret` par une variable d'environnement.
</details>

<details><summary>Indice 2</summary>

Pour exclure un objet, cherche dans les drapeaux un filtre **par étiquette** des sources (le chart l'expose sous un nom proche). Pour ne suivre qu'une Gateway, il y a des drapeaux `--gateway-…`.
</details>

<details><summary>Indice 3</summary>

Si rien n'est publié et que le journal parle de `NOTAUTH` ou de `REFUSED`, relis les autorisations d'E14 (clé, adresse) ; s'il ne parle pas de la route, regarde son état (`Accepted` ?) et la Gateway à laquelle elle est attachée ; s'il publie mais que `dig` ne voit rien, pense au cache négatif du récurseur (TTL négatif du SOA).
</details>

---

### M15-E16 — Routage avancé : poids, en-têtes, réécritures, gRPC et TLS  `LAB` `★★★`

> **Ticket DEV-1616** — *De : Julien Petit*
> Avant de passer MédiAgenda en production, je veux savoir ce que l'entrée sait faire sans toucher au code : envoyer 10 % du trafic sur une nouvelle version, forcer la nouvelle version pour les testeurs, renommer un préfixe d'URL, rediriger les anciennes adresses, ajouter un en-tête. L'équipe MédiDoc parle aussi de gRPC, et d'un service qui veut garder son propre TLS.

**Objectifs pédagogiques**
- Écrire des règles HTTPRoute avancées (poids, correspondances d'en-têtes, filtres `URLRewrite`, `RequestRedirect`, `RequestHeaderModifier`) et comprendre leur ordre de priorité.
- Publier un service gRPC (`GRPCRoute`) et un service en TLS de bout en bout (`TLSRoute` en *passthrough*).
- Référencer un objet d'un autre espace (`ReferenceGrant`).

**Prérequis** : M15-E15.
**Durée indicative** : 3 h.

**Contexte technique**
- Charges d'essai dans `wb-essais` : deux Deployments `agnhost-v1` et `agnhost-v2` (`netexec --http-port=8080`) et leurs Services ; `/hostname` renvoie le nom du pod, `/header?key=<NOM>` la valeur d'un en-tête reçu, `/echo?msg=…` le message.
- Route principale `essai-avance`, nom `essai.apps.par1.medisphere.internal`, écouteur `https` de `gw-par1` (publiée par ExternalDNS).
- gRPC : `agnhost grpc-health-checking` (port 5000, service standard `grpc.health.v1.Health`, sans réflexion) ; nom `grpc-essai.apps.par1.medisphere.internal` (la source `gateway-grpcroute` n'est pas activée dans ExternalDNS : essais par adresse). Client : `grpcurl` 1.9.x sur `adm01` (binaire épinglé) avec la définition [`ressources/E16-health.proto`](../ressources/E16-health.proto).
- TLS de bout en bout : `TLSRoute` est passée en **v1 dans le canal standard** en Gateway API v1.6 (elle était `v1alpha2` dans le canal expérimental). Cilium 1.20 exige la v1. ⚠️ Si une `TLSRoute` `v1alpha2` existait déjà dans un cluster, installer la CRD standard v1.6 la rendrait illisible : ce n'est pas notre cas (installation neuve en E07), vérifie-le quand même. Gateway dédiée `gw-essai-tls` dans `wb-essais` (adresse 10.10.41.21, écouteur `TLS` en mode `Passthrough`, port 443), backend `agnhost netexec` en HTTPS avec un certificat `tls-essai.apps.par1.medisphere.internal` émis par cert-manager (DNS-01).
- Référence croisée : espace jetable `wb-essais-2` portant un Service `agnhost-v3`.

**Travail demandé**
1. Lis *Gateway API → HTTPRoute* (référence de l'API v1.6 : `matches`, `filters`, `backendRefs[].weight`, ordre de priorité des règles) et les exemples Cilium *Traffic splitting* et *HTTP header modifier*. Dans `~/m15/e16/journal.md`, écris l'ordre dans lequel la Gateway choisit une règle quand plusieurs correspondent.
2. Déploie les charges d'essai et écris `essai-avance` avec, dans des règles distinctes :
   - 90 % / 10 % entre `agnhost-v1` et `agnhost-v2` par défaut ;
   - 100 % vers `agnhost-v2` si l'en-tête `X-Canari: oui` est présent ;
   - `/v2/…` réécrit en `/…` vers `agnhost-v2` ;
   - `/ancien/…` redirigé (301) vers `/…` ;
   - un en-tête `X-Medisphere-Env: essai` ajouté à toutes les requêtes transmises.
3. Mesure : 200 requêtes `/hostname` sans en-tête (compte les réponses par version), 20 avec `X-Canari: oui`, et vérifie la réécriture, la redirection et l'en-tête (`/header?key=X-Medisphere-Env`). Écart à 90/10 : normal ?
4. gRPC : déploie le serveur de santé, écris la `GRPCRoute` `essai-grpc` (méthode `grpc.health.v1.Health/Check`), et interroge-la depuis `adm01` en HTTPS vers 10.10.41.10 en fixant le nom TLS et l'`:authority`. Quel protocole applicatif est négocié ?
5. TLS : vérifie la version de la CRD `tlsroutes` installée, crée le Certificate du backend, le backend, `gw-essai-tls` et la `TLSRoute` `essai-tls`. Avec `openssl s_client`, montre que le certificat présenté est celui du **backend** et non le joker. Que voit le backend comme adresse source ? Pourquoi cert-manager ne peut-il pas gérer le certificat d'un écouteur `Passthrough` ?
6. Référence croisée : crée `wb-essais-2` et `agnhost-v3`, puis une route `croise` dans `wb-essais` vers ce Service. Lis la condition `ResolvedRefs`, ajoute le `ReferenceGrant` minimal, relis.
7. Nettoie : supprime `wb-essais-2`, `gw-essai-tls` (libère 10.10.41.21) ; garde `essai-avance` jusqu'à E21.

**Critères de réussite**
- [ ] `essai-avance` est acceptée, et la mesure montre la répartition, le forçage par en-tête, la réécriture, la redirection 301 et l'en-tête ajouté.
- [ ] `essai-grpc` est acceptée et `grpc.health.v1.Health/Check` répond `SERVING` à travers `gw-par1`.
- [ ] La `TLSRoute` (v1) a été acceptée et `openssl s_client` a montré le certificat du backend (sortie dans le journal).
- [ ] La route croisée n'a été résolue qu'avec un `ReferenceGrant` limité à ce Service.

**Vérification** : `lab/bin/check 15 16`

<details><summary>Indice 1</summary>

Une règle avec `matches` sur un en-tête est plus spécifique qu'une règle sans en-tête au même chemin : tu n'as pas besoin de jouer sur l'ordre d'écriture. Les poids sont relatifs (90 et 10, ou 9 et 1).
</details>

<details><summary>Indice 2</summary>

`URLRewrite` et `RequestRedirect` ont chacun un `path` de type `ReplacePrefixMatch` qui suppose une correspondance `PathPrefix` sur la règle. `grpcurl` sans réflexion a besoin de `-import-path`/`-proto` ; `-servername` fixe le nom TLS, `-authority` l'en-tête `:authority`.
</details>

<details><summary>Indice 3</summary>

Un `ReferenceGrant` vit dans l'espace de la **cible** ; il nomme le type et l'espace de la **source** (`from`) et le type, éventuellement le nom, de la cible (`to`).
</details>

---

### M15-E17 — Les politiques réseau de MédiAgenda  `LIBRE` `★★★`

> **Ticket SEC-1617** — *De : Sophie Laurent*
> MédiAgenda traite des rendez-vous de patients. Aujourd'hui, n'importe quel pod du cluster peut ouvrir la base de données de la recette. Je veux le principe du moindre privilège sur `mediagenda-dev` et `mediagenda-recette` : rien n'entre ni ne sort par défaut, chaque flux nécessaire est écrit et justifié, et l'entrée publique ne laisse passer que les appels prévus de l'API. Les métriques ne sont pas publiques.

**Objectifs pédagogiques**
- Concevoir un jeu de politiques complet (L3/L4 et L7) à partir des flux réels d'une application.
- Combiner `NetworkPolicy` standard et `CiliumNetworkPolicy`, et savoir ce que chacune exprime.
- Prouver l'effet des politiques par l'observation (Hubble) et par des essais négatifs.

**Prérequis** : M15-E05 (Hubble), M15-E06 (premières politiques), M15-E12.
**Durée indicative** : 3 h.

**Contexte technique**
- Flux de MédiAgenda (code dans `apps/mediagenda`) : l'API écoute sur 8000 dans le pod (Service `mediagenda-api` en 80 ; une politique voit le port du **pod**) (`/sante`, `/pret`, `/metrics`, `/api/v1/rendez-vous` en `GET`/`POST`, `/api/v1/rendez-vous/{id}` en `GET`/`DELETE`, `/api/v1/creneaux` en `GET`) ; elle joint PostgreSQL (5432) et Valkey (6379) ; tout le monde résout des noms par CoreDNS. N'oublie pas ce qui ne tourne pas en permanence ou ne se voit pas dans un parcours de l'API : les manifestes du M14 (`mediagenda/api`, `k8s/dev/`, `k8s/recette/`) contiennent aussi des Jobs et un StatefulSet à trois répliques.
- Le trafic qui sort de l'Envoy de la Gateway Cilium porte l'identité réservée **`ingress`** (page *Reference* de la Gateway API dans la doc Cilium) ; les sondes du kubelet arrivent de l'identité `host`.
- Personne n'a besoin d'atteindre MédiAgenda depuis un autre espace, sauf la Gateway ; `/metrics` sera lu par Prometheus au M21 (espace pas encore connu) : aujourd'hui, personne.
- Politiques rangées sous `espaces/` de `plateforme/k8s` (organisation à ton choix, avec un seul jeu de fichiers pour les deux espaces : voir les contraintes).

**Travail demandé**
1. Écris la matrice des flux de MédiAgenda (source, destination, port, protocole, méthode et chemin HTTP s'il y a lieu, justification) dans `docs/kubernetes/reseau/flux-mediagenda.md`.
2. Traduis-la en politiques pour les deux espaces : tout refuser par défaut en entrée **et** en sortie, puis autoriser exactement la matrice. Pour l'entrée publique, ne laisse passer que les méthodes et chemins de l'API prévus.
3. Prouve : MédiAgenda fonctionne en recette à travers `gw-par1` ; un pod de `wb-essais` ne joint plus PostgreSQL de la recette ; `/metrics` et une méthode non prévue sont refusés depuis l'extérieur ; aucune chute (*drop*) inattendue dans Hubble pendant un parcours complet de l'API. Garde les sorties de Hubble dans `~/m15/e17/`.
4. Livre par MR, avec dans la description la liste des essais faits et leurs résultats.

**Contraintes**
- Aucun `allow-all` déguisé (pas de sélecteur vide en source ou destination d'une autorisation, pas de `toEntities: [all]`, pas de bloc `0.0.0.0/0`).
- Les mêmes manifestes servent aux deux espaces (seul l'espace change).
- Les sondes du kubelet continuent de passer ; la résolution DNS ne vise que CoreDNS.

**Critères de réussite**
- [ ] Les deux espaces ont une politique de refus par défaut en entrée et en sortie.
- [ ] `https://mediagenda-recette.apps.par1.medisphere.internal/pret` répond 200 (base et cache joignables) ; `/metrics` et une méthode non prévue sont refusés par la politique L7.
- [ ] Un pod hors de l'espace ne joint pas PostgreSQL de la recette (essai consigné, *drop* visible dans Hubble).
- [ ] Les répliques de Valkey suivent toujours le primaire (`valkey-cli info replication` dans `valkey-1` : `master_link_status:up`) et un Job de migration rejoué se termine.
- [ ] Matrice des flux et politiques sur `main` ; MR avec la liste des essais.

**Vérification** : `lab/bin/check 15 17`

<details><summary>Indice 1</summary>

Une `NetworkPolicy` standard ne sait pas désigner l'identité `ingress` de Cilium ; une `CiliumNetworkPolicy` le sait (`fromEntities`). Les deux types de politiques se cumulent : une connexion passe si au moins une politique qui sélectionne le pod l'autorise.
</details>

<details><summary>Indice 2</summary>

Une règle L7 HTTP se pose sur le port de destination du pod, dans une politique d'**entrée** du pod qui reçoit ; quand une règle L7 existe sur un port, tout ce qui ne lui correspond pas sur ce port est refusé par le proxy (réponse 403), pas jeté.
</details>

<details><summary>Indice 3</summary>

Avec le remplacement de kube-proxy, les politiques de sortie voient l'adresse du **pod** de destination, pas celle du Service. Pour CoreDNS, sélectionne ses pods par leur étiquette dans `kube-system`, sur UDP **et** TCP.
</details>

---

### M15-E18 — Migrer les Ingress d'InfoGér vers la Gateway API  `LAB` `★★★`

> **Ticket PLAT-1618** — *De : Claire Morel*
> InfoGér nous livre les manifestes `Ingress` de leurs anciens clusters, tous écrits pour ingress-nginx. Ce projet a été arrêté en mars : plus aucun correctif, même de sécurité. On ne le déploiera pas. Je veux savoir, Ingress par Ingress et annotation par annotation, ce qui se traduit, ce qui se traduit mal et ce qui ne se traduit pas, avant qu'on promette une date de migration aux équipes.

**Objectifs pédagogiques**
- Lire des Ingress ingress-nginx réels et identifier ce que portent leurs annotations.
- Utiliser `ingress2gateway` et critiquer sa sortie.
- Produire une migration réaliste vers `gw-par1`, et un plan pour ce qui ne se traduit pas.

**Prérequis** : M15-E16.
**Durée indicative** : 3 h.

**Contexte technique**
- Manifestes fournis : [`ressources/E18-ingress-infoger/`](../ressources/E18-ingress-infoger/) (sept Ingress pour cinq applications, avec un `README.md` d'InfoGér, incomplet comme d'habitude).
- `ingress2gateway` (projet `kubernetes-sigs`), version 1.2.x : binaire de la page des publications, épinglé par empreinte, dans `~/.local/bin` de `adm01`. Il lit des fichiers (`--input-file`) ou le cluster, ne recopie jamais une annotation et signale ce qu'il ne sait pas traduire.
- ingress-nginx 1.15.1 est la dernière version publiée (mars 2026). ⚠️ Ne le déploie **pas** sur `k8s-par1`. Pour comparer les comportements, tu pourras l'essayer sur `m15-essai` après E19 (facultatif).
- Cible : `gw-par1`, espace `wb-essais` pour les essais, noms `<application>-infoger.apps.par1.medisphere.internal`, backends `agnhost-v1`/`agnhost-v2` d'E16 à la place des applications d'InfoGér.

**Travail demandé**
1. Lis le README d'`ingress2gateway` (fournisseur `ingress-nginx`, annotations prises en charge) et la page *Migrating from Ingress* de gateway-api.sigs.k8s.io. Installe l'outil (empreinte vérifiée).
2. Pour chaque Ingress fourni, liste ses annotations et ce qu'elles font dans ingress-nginx (tableau dans `~/m15/e18/migration.md`).
3. Lance la conversion :
   ```
   admin@adm01:~$ R=~/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources/E18-ingress-infoger
   admin@adm01:~$ ingress2gateway print --providers=ingress-nginx -A --no-color \
       --input-file "$(ls "$R"/*.yaml | paste -sd, -)" > ~/m15/e18/sortie-brute.yaml 2> ~/m15/e18/avertissements.txt
   ```
   (`--input-file` prend une liste de fichiers séparés par des virgules, pas un dossier.) Compare sortie et avertissements à ton tableau : qu'a-t-il traduit, fidèlement ou non ? Qu'a-t-il ignoré en silence ?
4. Adapte : pas de nouvelle Gateway (tout s'accroche à `gw-par1`), noms dans `apps`, certificats déjà fournis par le joker. Pour chaque fonction non traduite, propose l'équivalent MédiSphère (fonction de la Gateway API, politique Cilium, application, ou « on ne le fait plus ») ou un risque à accepter.
5. Déploie dans `wb-essais` les routes de **trois** applications au choix dont `portail` et `api-rdv`, et prouve par des requêtes que leur comportement correspond à celui de l'Ingress d'origine (redirections, réécritures, poids, limites).
6. Rédige la conclusion pour Claire en tête de `migration.md` : nombre d'annotations, part traduite automatiquement, part traduite à la main, part sans équivalent, et ce qu'il faut demander aux équipes.

**Critères de réussite**
- [ ] `~/m15/e18/` contient la sortie brute, les avertissements et `migration.md` (tableau des annotations des sept Ingress, conclusion chiffrée).
- [ ] Les routes de `portail` et `api-rdv` (et d'une troisième application) sont acceptées par `gw-par1` dans `wb-essais` et répondent sous leur nom `apps`.
- [ ] La redirection permanente de `portail` et la réécriture de préfixe d'`api-rdv` se comportent comme dans l'Ingress d'origine.
- [ ] Aucun contrôleur ingress-nginx ne tourne sur `k8s-par1`.

**Vérification** : `lab/bin/check 15 18`

<details><summary>Indice 1</summary>

Une annotation qui contient du code de configuration nginx (`*-snippet`) n'a, par construction, aucun équivalent portable ; une annotation de réécriture avec groupe de capture (`$2`) n'a pas d'équivalent exact dans la Gateway API (préfixe ou chemin complet seulement).
</details>

<details><summary>Indice 2</summary>

Pour les limites de débit, l'authentification externe et les listes d'adresses, regarde ce que Cilium offre **hors** Gateway API (politiques, Envoy) et ce que la Gateway API v1.6 a dans son canal standard. Sois prêt à écrire « pas d'équivalent aujourd'hui ».
</details>

---

### M15-E19 — MetalLB en comparaison  `LAB` `★★`

> **Ticket PLAT-1619** — *De : Karim Benali*
> Le prestataire d'une filiale ne jure que par MetalLB, et la moitié des tutoriels aussi. Avant que quelqu'un propose de le mettre sur `k8s-par1`, je veux une comparaison faite par nous : sur une VM jetable, pas sur le cluster ni sur la bordure.

**Objectifs pédagogiques**
- Installer MetalLB 0.16 et le faire fonctionner en mode L2 (ARP).
- Comparer attribution, annonce, bascule et intégration avec LB IPAM + BGP de Cilium.
- Comprendre les changements de MetalLB 0.16 (FRR-K8s par défaut pour BGP, métriques en HTTPS).

**Prérequis** : M15-E10, M14-E02 à E05 (rôles et `kubeadm`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM `m15-essai` : VMID 2151, `vsandbox`, adresse fixe 10.10.99.51, 2 vCPU, 4 Go, image dorée Debian 13 `current`, étiquettes `env-m15` et `role-k8s-essai`, état OpenTofu **`m15-essai`** (`envs/m15-essai/` de `plateforme/infra`). Elle est détruite en fin de module (mini-projet).
- Préparation par les rôles du M14 `containerd` et `k8s_noeud` (playbook dédié `m15-essai.yml`), puis `kubeadm init` **à la main** sur un seul nœud (pas de VIP, `controlPlaneEndpoint` = l'adresse de la VM), taint du plan de contrôle retiré, Cilium 1.20 installé par la CLI avec ses valeurs par défaut (kube-proxy conservé, aucun pool LB IPAM). Kubeconfig dans `~/.kube/m15-essai.conf` sur `adm01` (600).
- MetalLB 0.16.x, chart `metallb/metallb` (dépôt `https://metallb.github.io/metallb`), espace `metallb-system` ; adresses L2 10.10.99.230-10.10.99.238 (`IPAddressPool` `essai-l2`, `L2Advertisement` `essai-l2`).
- ⚠️ MetalLB ne fait **aucune** session BGP vers `gw01`/`gw02` : la bordure n'a pas de voisin prévu pour la sandbox et ses politiques le refuseraient.

**Travail demandé**
1. Lis *MetalLB → Concepts* (*Layer 2 mode*, *BGP mode*) et les notes de version 0.16. Dans `~/m15/e19/journal.md` : qui répond à l'ARP pour une adresse de service en mode L2 ? Que se passe-t-il quand ce nœud tombe ? Qu'est-ce qui a changé pour le BGP en 0.16 ?
2. Crée la VM par OpenTofu (nouvel état), prépare-la par Ansible, initialise le cluster mononœud, installe Cilium. Vérifie que le nœud est `Ready`.
3. Installe MetalLB :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.kube/m15-essai.conf
   admin@adm01:~$ helm repo add metallb https://metallb.github.io/metallb
   admin@adm01:~$ helm upgrade --install metallb metallb/metallb --version 0.16.<PATCH> \
       --namespace metallb-system --create-namespace --wait
   ```
   Pourquoi l'espace `metallb-system` doit-il échapper au niveau `restricted` de PSA ?
4. Déclare le pool et l'annonce L2, déploie `agnhost` et un Service `LoadBalancer`. Teste depuis `adm01`, puis regarde la table ARP de la passerelle maître (`ip neigh show 10.10.99.230` sur `gw01`) et l'annonceur choisi (`kubectl describe svc`, événements).
5. Demande une adresse précise, puis une adresse hors pool : compare l'interface (annotations `metallb.io/…`) et les messages à ceux de LB IPAM (E10).
6. Remplis dans `~/m15/e19/comparaison.md` un tableau MetalLB (L2, BGP) / Cilium (LB IPAM + BGP, L2 announcements) : attribution, annonce, bascule et sa durée, ECMP, intégration au chemin de données, objets à maintenir, fonctionnement avec kube-proxy ou sans, observabilité, maturité. Conclus pour `k8s-par1`.
7. Laisse `m15-essai` en place (E18 facultatif, mini-projet) mais **arrête-la** quand tu ne t'en sers pas.

**Critères de réussite**
- [ ] `m15-essai` existe (VMID 2151, état OpenTofu `m15-essai`), son cluster mononœud est `Ready`.
- [ ] MetalLB 0.16 tourne, le pool `essai-l2` couvre 10.10.99.230-10.10.99.238, un Service y a une adresse qui répond depuis `adm01`.
- [ ] MetalLB n'a aucun voisin BGP déclaré.
- [ ] Le tableau de comparaison et sa conclusion sont dans `~/m15/e19/`.

**Vérification** : `lab/bin/check 15 19`

<details><summary>Indice 1</summary>

Le `kubeadm init` d'un essai n'a pas besoin du fichier HA du M14 : `--apiserver-advertise-address`, `--pod-network-cidr` et `--kubernetes-version` suffisent (ou un fichier `ClusterConfiguration` minimal). Le taint à retirer s'appelle `node-role.kubernetes.io/control-plane`.
</details>

<details><summary>Indice 2</summary>

Le speaker de MetalLB a besoin du réseau de l'hôte et de capacités réseau : regarde les étiquettes PSA posées sur l'espace par le chart, ou pose-les. Une adresse L2 n'est joignable que si l'adresse est **dans** le réseau du nœud (ici 10.10.99.0/24) : c'est une limite du mode, pas un défaut de configuration.
</details>

---

### M15-E20 — Publier une application hors du lab par `lb01`/`lb02`  `LAB` `★★★`

> **Ticket PLAT-1620** — *De : Claire Morel*
> La direction veut montrer la recette de MédiAgenda à une clinique pilote, depuis l'extérieur du lab. L'entrée publique, ce sont les répartiteurs `lb01`/`lb02` et rien d'autre. Je veux que seuls les noms qu'on décide soient publiés dehors, pas tout `*.apps`, et que GitLab et NetBox continuent de marcher pendant et après le changement.

**Objectifs pédagogiques**
- Aiguiller du TLS par nom (SNI) sans le déchiffrer, à côté de services terminés localement, sur une même adresse et un même port.
- Faire évoluer une configuration HAProxy de production par le rôle Ansible, sans coupure des services existants.
- Ouvrir le flux nécessaire et seulement lui.

**Prérequis** : M15-E14, M07-E12, M07-E13, M07-E28 (répartiteurs en production).
**Durée indicative** : 3 h.

**Contexte technique**
- `lb01`/`lb02` (HAProxy 3.2, VIP 10.10.70.200, rôle `haproxy`, `group_vars/role_lb/haproxy.yml` de M07-E28) terminent le TLS de GitLab et NetBox sur `:443` (frontal `fe_publication`). La VIP WAN redirige déjà 443 vers la VIP des répartiteurs (M07-E13).
- Décision de Karim : **passage TLS de bout en bout** pour Kubernetes. Les répartiteurs lisent le nom demandé dans le `ClientHello` (SNI) et relaient le flux chiffré vers 10.10.41.10:443 pour les noms publiés ; tout le reste continue vers la terminaison locale. Le certificat vu par le client est donc le joker `apps-joker` du cluster.
- Noms publiés à l'extérieur : liste explicite (variable d'inventaire), aujourd'hui `mediagenda-recette.apps.par1.medisphere.internal` seulement. Un autre nom en `*.apps` arrivant aux répartiteurs est refusé.
- Flux à ouvrir : `lb01`, `lb02` → 10.10.41.10 TCP 443 (bordure). Le chemin retour passe par la bordure (routes BGP d'E11).
- Les clients extérieurs n'ont pas le DNS interne : essais avec `curl --resolve` vers `<IP-GW-WAN-VIP>` depuis le LAN maison, ou vers 10.10.70.200 depuis `adm01`.

> ⚠️ **Attention** : `lb01`/`lb02` publient GitLab et NetBox. Le rôle `haproxy` valide la configuration (`haproxy -c`) avant de recharger, et le pipeline passe d'abord sur le répartiteur de **secours** (celui qui n'a pas la VIP). Avant : `curl -sS https://gitlab.par1.medisphere.internal/-/readiness` (à garder). Retour arrière : réverter la MR et relancer le pipeline.

**Travail demandé**
1. Lis dans la documentation de HAProxy 3.2 : *4. Proxies → mode tcp*, `tcp-request inspect-delay`, `tcp-request content`, l'échantillon `req.ssl_sni`, les adresses `abns@` et le protocole PROXY (`send-proxy-v2`, `accept-proxy`). Dans `~/m15/e20/journal.md`, dessine le chemin d'une requête pour GitLab et pour MédiAgenda **après** le changement.
2. Conçois la nouvelle configuration : un frontal TCP sur `:443` qui aiguille par SNI ; la terminaison TLS existante déplacée derrière lui, en conservant l'adresse des clients ; un backend TCP vers 10.10.41.10:443 avec contrôle de santé ; refus de tout autre nom `*.apps`. Écris-la dans `group_vars/role_lb/haproxy.yml` (liste des noms publiés en variable).
3. Ouvre le flux à la bordure (matrice et documentation). MR, relecture, pipeline.
4. Vérifie depuis `adm01` :
   ```
   admin@adm01:~$ curl -sS --resolve mediagenda-recette.apps.par1.medisphere.internal:443:10.10.70.200 \
       https://mediagenda-recette.apps.par1.medisphere.internal/sante
   admin@adm01:~$ curl -sS https://gitlab.par1.medisphere.internal/-/readiness
   ```
   Puis un nom non publié (`essai.apps.par1.medisphere.internal`) par les répartiteurs : que se passe-t-il ? Et le même nom en direct sur 10.10.41.10 ?
5. Depuis le LAN maison (ton poste), refais l'essai MédiAgenda vers `<IP-GW-WAN-VIP>`.
6. Bascule : arrête keepalived sur le répartiteur maître pendant une boucle de requêtes MédiAgenda et GitLab. Mesure. Relance.
7. Que voit MédiAgenda de l'adresse du client ? Compare avec GitLab. Note la limite et les options (PROXY vers la Gateway, terminaison sur les répartiteurs) avec leurs coûts.
8. Mets à jour `docs/kubernetes/reseau/entree-du-cluster.md` : chemin externe, liste des noms publiés, procédure pour en publier un nouveau.

**Critères de réussite**
- [ ] `mediagenda-recette.apps…` répond 200 en HTTPS par la VIP des répartiteurs, avec le certificat joker du cluster (TLS de bout en bout).
- [ ] Un nom `*.apps` non publié est refusé par les répartiteurs ; GitLab et NetBox répondent comme avant (adresse client conservée dans leurs journaux).
- [ ] Le flux répartiteurs → 10.10.41.10:443 est la seule ouverture ajoutée (matrice et documentation) ; la configuration des répartiteurs est sur `main` de `plateforme/ansible`.
- [ ] Le journal contient la mesure de bascule et l'analyse de l'adresse client.

**Vérification** : `lab/bin/check 15 20`

<details><summary>Indice 1</summary>

HAProxy ne peut pas lire le SNI tant que le `ClientHello` n'est pas arrivé : un `tcp-request inspect-delay` suivi d'une acceptation conditionnée au type de message TLS. Un frontal HTTP peut écouter sur une adresse abstraite (`abns@…`) ; un backend TCP peut l'avoir pour serveur.
</details>

<details><summary>Indice 2</summary>

Le `log-format` des `defaults` est un format HTTP : un frontal TCP a besoin du sien (sinon HAProxy l'avertit). Une liste de noms publiés se teste avec `-m str` sur une liste, ou avec un fichier de correspondances (`-f`), générés depuis la variable.
</details>

<details><summary>Indice 3</summary>

Si GitLab voit l'adresse du répartiteur au lieu du client après le changement, le protocole PROXY manque d'un côté (`send-proxy-v2` sur le serveur du backend local, `accept-proxy` sur l'écoute du frontal HTTP).
</details>

---

### M15-E21 — Revue : politiques et routes du stagiaire  `REV` `★★`

> **Ticket PLAT-1621** — *De : Karim Benali*
> Lucas a préparé l'exposition de MédiDoc en `medidoc-dev` : Gateway, routes, politiques, certificat. Il est fier, il voudrait que ça parte demain. Relis, s'il te plaît, comme tu relirais une MR de prod. Je veux une liste numérotée, chaque défaut avec sa gravité et sa correction.

**Objectifs pédagogiques**
- Relire des manifestes réseau Kubernetes et repérer les défauts de sécurité, de fonctionnement et d'exploitation.
- Justifier chaque remarque (doc, comportement observé) et proposer une correction.

**Prérequis** : M15-E12 à M15-E17.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : [`ressources/E21-medidoc-lucas/`](../ressources/E21-medidoc-lucas/) (Gateway, HTTPRoute, ReferenceGrant, Certificate, NetworkPolicy, CiliumNetworkPolicy et la description de MR de Lucas).
- MédiDoc (`apps/medidoc`) écoute sur 8080 (`/healthz`, `/readyz`, `/metrics`, API `POST /documents`, `GET /documents`, `GET /documents/{id}`), stocke dans S3 (`s3-01.par1.medisphere.internal:8333`) et doit être publié en `medidoc-dev.apps.par1.medisphere.internal`.
- Tu peux valider la syntaxe sans cluster (`kubeconform` avec les schémas des CRD, `kubectl apply --dry-run=server` dans `wb-essais` en changeant l'espace) : ne déploie **pas** ces fichiers tels quels.

**Travail demandé**
1. Lis les fichiers et la description de MR. Écris `~/m15/e21/revue.md` : une ligne par défaut (numéro, fichier, ligne, gravité **bloquant**/**majeur**/**mineur**, explication, correction).
2. Pour au moins trois défauts, prouve-les (commande, condition d'objet lue après un `--dry-run=server`, extrait de documentation).
3. Écris la version corrigée dans `~/m15/e21/corrige/` (mêmes noms de fichiers).
4. Rédige la réponse à Lucas : ce qui est bien, les trois défauts à corriger d'abord, comment éviter la même chose la prochaine fois.

**Critères de réussite**
- [ ] `revue.md` relève au moins 12 défauts, chacun avec gravité et correction.
- [ ] `~/m15/e21/corrige/` contient les fichiers corrigés, valides pour leurs schémas.
- [ ] Les défauts bloquants (exposition, secrets, politiques ouvertes) sont tous corrigés.

**Vérification** : `lab/bin/check 15 21`

<details><summary>Indice 1</summary>

Lis chaque fichier trois fois : une fois pour la **sécurité** (qui peut joindre quoi, qui peut publier quoi, où sont les secrets), une fois pour le **fonctionnement** (noms, ports, références, espaces), une fois pour l'**exploitation** (durées, étiquettes, conventions MédiSphère).
</details>

---

### M15-E22 — Runbook : un service n'est plus joignable  `RED` `★★`

> **Ticket PLAT-1622** — *De : Nadia Roussel*
> La semaine prochaine, l'astreinte prend en charge les applications du cluster. Mes collègues savent diagnostiquer un serveur web sur une VM, pas une chaîne Gateway → Service → pods → politique. Il me faut le runbook RB-150 : « une application du cluster ne répond plus », du symptôme jusqu'à la bonne équipe à réveiller.

**Objectifs pédagogiques**
- Rédiger une procédure de diagnostic par couches, utilisable de nuit par quelqu'un qui n'a pas construit l'entrée.
- Choisir des commandes sûres (lecture seule) et des critères de décision clairs.

**Prérequis** : M15-E10 à M15-E17.
**Durée indicative** : 2 h.

**Travail demandé**
1. Rédige `docs/kubernetes/reseau/runbooks/RB-150-service-injoignable.md` (`plateforme/medisphere`) selon le modèle des runbooks du socle (portée, symptômes, prérequis et accès, étapes, décisions, escalade, retour à la normale, historique).
2. Couvre au moins : résolution du nom (récurseurs, zone `apps`, ExternalDNS), annonce de l'adresse (BGP, bordure), Gateway et écouteurs, certificat, route, Service et EndpointSlices, pods, politiques (Hubble), et pour l'accès extérieur les répartiteurs.
3. Pour chaque couche : une commande de lecture, la sortie attendue, ce que signifie un écart, qui appeler. Mets en tête un arbre de décision qui tient sur un écran.
4. Teste-le : demande à quelqu'un (ou fais-le toi-même dans deux semaines) avec une panne que tu provoques dans `wb-essais` (Service au mauvais sélecteur, par exemple), et note dans l'historique ce qui manquait.

**Critères de réussite** (auto-évaluation avec la grille du corrigé)
- [ ] Le runbook suit le modèle du socle et commence par un arbre de décision.
- [ ] Chaque couche a une commande en lecture seule, la sortie attendue, l'interprétation d'un écart et l'escalade.
- [ ] Un essai réel est consigné dans l'historique.

---

### M15-E23 — Le réseau du cluster décrit par le code  `LIBRE` `★★★`

> **Ticket PLAT-1623** — *De : Karim Benali*
> On a empilé beaucoup de choses en deux semaines : values de Cilium, pool, BGP, Gateway, cert-manager, ExternalDNS, CoreDNS, zones, flux. Si demain on reconstruit `k8s-par1`, je veux qu'une commande remette tout le réseau d'aplomb, dans le bon ordre, et qu'une autre me dise si le cluster a dérivé du dépôt.

**Objectifs pédagogiques**
- Organiser les composants réseau d'un cluster comme du code (versions épinglées, ordre, dépendances, secrets).
- Rendre une installation reproductible et détecter la dérive.

**Prérequis** : M15-E10 à M15-E20, M14-E23 (cluster reconstructible).
**Durée indicative** : 3 h.

**Contexte technique**
- Projet `plateforme/k8s` (`composants/`, `espaces/`, `outils/`, `Taskfile.yml`). Les composants côté hôtes (FRR, PowerDNS, HAProxy, pare-feu) restent dans `plateforme/ansible`, la délégation DNS dans `plateforme/infra` : `plateforme/k8s` les **cite** (prérequis), ne les duplique pas.
- Les releases Helm de cert-manager et d'ExternalDNS existent déjà : la reprise ne doit pas les réinstaller.

**Travail demandé**
1. Range dans `plateforme/k8s` tout ce qui fait le réseau du cluster : values de Cilium et leur version, CRD de la Gateway API et leur version, pool, BGP, Gateway et routes de plateforme, cert-manager (values, émetteur, certificat joker), ExternalDNS, CoreDNS, étiquettes des nœuds et des espaces, outil des secrets TSIG.
2. Ajoute au `Taskfile.yml` une tâche qui installe ou remet à niveau tout le réseau dans l'ordre (et s'arrête au premier échec), et une tâche qui affiche la dérive entre le dépôt et le cluster sans rien modifier.
3. Ajoute à la CI du projet une validation des manifestes (schémas des CRD comprises) et des versions épinglées.
4. Écris `docs/kubernetes/reseau/reconstruction.md` : prérequis hors cluster, ordre, durée mesurée, vérifications.
5. Prouve la reproductibilité sans casser `k8s-par1` (à toi de choisir comment : `m15-essai`, essai à blanc, suppression et recréation d'un composant non critique…), et consigne la preuve.

**Contraintes**
- Aucune version flottante (`latest`, mineure sans correctif, chart sans version).
- Aucun secret dans le dépôt ; les secrets se recréent depuis le Vault par l'outil.
- La tâche de dérive ne modifie rien et sort en erreur s'il y a une dérive.

**Critères de réussite**
- [ ] Le dépôt contient chaque composant listé, avec ses versions épinglées.
- [ ] La tâche d'installation et la tâche de dérive existent ; la dérive est nulle sur `k8s-par1` (sortie consignée).
- [ ] La CI valide les manifestes ; le document de reconstruction existe ; une preuve de reproductibilité est consignée.

**Vérification** : `lab/bin/check 15 23`

<details><summary>Indice 1</summary>

kubectl sait comparer un manifeste à l'objet du cluster et le signaler par son code de sortie ; Helm sait restituer les valeurs appliquées d'une release. Pense à ce qui est **généré** par les contrôleurs (Service de la Gateway, Secrets de cert-manager) : il ne doit pas être dans le dépôt.
</details>

<details><summary>Indice 2</summary>

L'ordre compte : CRD avant objets, Cilium avant tout, cert-manager avant ses émetteurs, la Gateway avant les routes, les Secrets TSIG avant cert-manager et ExternalDNS. Une tâche peut en appeler d'autres (`deps`, `cmds: - task: …`).
</details>

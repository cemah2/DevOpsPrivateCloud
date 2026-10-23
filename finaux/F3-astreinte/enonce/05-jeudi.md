# Final F3 — Phase 5 : jeudi

Jeudi, Nadia rentre de formation à midi ; d'ici là, tu es seul·e. Les incidents du jour ont un point commun : **rien n'est en panne**, au sens où chaque composant, interrogé seul, répond. Le coffre est descellé et sa grappe a son quorum ; les récurseurs DNS tournent ; les passerelles routent ; BGP est configuré. Et pourtant les secrets ne suivent plus, et une partie des noms ne répond pas. Ce sont des pannes **de chemin** et **de redondance** : un client qui ne trouve plus le service, un exemplaire malade que son jumeau masque la moitié du temps. Elles se diagnostiquent en interrogeant chaque exemplaire séparément, et en distinguant le service du chemin qui y mène.

Deux pièges propres à la journée :
- **Le symptôme est en retard sur la cause.** Un identifiant dynamique vit une heure ; quand l'application tombe, la cause a parfois une heure d'avance. Ce qui « a l'air d'aller » (la production, par exemple) peut être sur la même pente.
- **La redondance masque.** Deux récurseurs, deux passerelles, trois annonceurs BGP par adresse : un exemplaire malade donne un symptôme intermittent, différent selon le client. Ne conclus jamais « ça marche » sur un seul essai depuis un seul poste.

> **Rappels de la semaine** (détail dans [`00-introduction.md`](00-introduction.md) et ta procédure de S02) : chaque incident s'ouvre, se suit et se clôt dans la main courante (`docs/exploitation/journal/<AAAA-MM-JJ>.md`, une ligne `- HH:MM INC-59XX [type] texte`) ; tu qualifies la gravité, tu envoies les messages d'état au rythme de la procédure (courriel, objet avec `[INC-59XX]`) ; toute correction passe **par le code et la CI** (sauf geste d'exception écrit dans la main courante) ; une fois réparé : `lab/bin/check F3 <XX>`, puis `lab/bin/break F3 <XX> --annuler` pour clore l'injection (l'annulation ne défait jamais ta réparation). Lance les incidents dans l'ordre, sans lire `corrige/`.

---

### F3-S10 — Jeudi : les secrets ne suivent plus  `BF` `★★★★`

> **Ticket INC-5910** — *De : Julien Petit, jeudi 9 h 40*
> « En recette, Argo CD montre `mediagenda-recette` en *Degraded* à cause d'un `ExternalSecret`, et nos tests de bout en bout commencent à tomber avec `password authentication failed for user "v-…"`. Pas tout le temps, et de plus en plus. On n'a rien livré depuis hier. La prod a l'air d'aller, mais elle utilise le même coffre, non ? »

**Objectifs pédagogiques**
- Remonter la chaîne d'un identifiant dynamique, de l'application au coffre : Secret, `ExternalSecret`, générateur `VaultDynamicSecret`, `SecretStore`, méthode `k8s-par1` et rôle `eso-<espace>`, politique, moteur `db-mediagenda`, bail, VIP keepalived, nœuds de la grappe Raft.
- Raisonner sur le **temps** d'un incident à baux : ce qui est déjà cassé, ce qui cassera dans l'heure, et ce que cela change à la gravité.
- Corriger par le code (OpenTofu de `plateforme/secrets`, Ansible, `plateforme/k8s`) et empêcher la récidive.

**Prérequis** : S01-S02 ; modules 25 (OpenBao, ESO, identifiants dynamiques, grappe et VIP), 20 (Argo CD), 07 (keepalived). Jeton OpenBao `plateforme-admin` valide au moment de l'injection (`bao login -method=oidc`) : certaines variantes en ont besoin.
**Durée indicative** : 1 h 30 à 2 h, communication et prévention comprises.

**Contexte technique**
- Coffre : `vault01-03` (10.10.20.21-23), VIP 10.10.20.200 `openbao.par1.medisphere.internal:8200` (keepalived, VRID 120), `kms01` pour l'auto-descellement. ⚠️ **Ne scelle jamais** un nœud ni `kms01`, ne redémarre pas `kms01`, n'arrête jamais deux nœuds de la grappe.
- MédiAgenda (recette et prod) reçoit ses identifiants PostgreSQL du moteur `db-mediagenda` (bail d'une heure), par le générateur `mediagenda-api` et l'`ExternalSecret` `mediagenda-db-api` (rafraîchi toutes les 30 min) ; Reloader redémarre l'API quand le Secret change.
- La production, la CI (`id_tokens` + `bao`) et Ansible passent aussi par la VIP.

**Injection** : `lab/bin/break F3 10` (3 variantes, une ou deux causes). Temps cible : **60 min** jusqu'au rétablissement.

**Travail demandé**
1. Ouvre l'incident, qualifie-le et communique selon ta procédure. Réévalue la gravité dès que tu sais ce que l'incident menace **dans l'heure**, et dis-le dans un message d'état.
2. Diagnostique en partant du client : où la chaîne se coupe-t-elle ? Sépare l'état du coffre (grappe, nœuds) de l'état du **chemin** vers le coffre, et l'authentification de l'autorisation.
3. Rétablis la recette **et** protège les autres environnements exposés à la même cause. Toute correction passe par le dépôt qui fait foi (`plateforme/secrets`, `plateforme/ansible`, `plateforme/k8s`) et sa CI ; un geste manuel urgent est permis s'il est consigné, puis rattrapé par le code.
4. Vérifie que les identifiants se renouvellent de nouveau (un bail neuf, un `ExternalSecret` rafraîchi après ta réparation) et que l'API répond.
5. **Prévention** : ce qui aurait détecté la cause avant Julien, et ce qui l'empêcherait (politique, alerte, procédure) ; au moins une action concrète, en MR ou en ticket `PLAT-3310…` daté. Écris **RB-336** « Les secrets ne suivent plus » (`docs/exploitation/runbooks/`).

**Critères de réussite**
- [ ] La VIP du coffre répond (nœud actif, descellé) ; un seul nœud la porte ; un nœud actif et deux en attente.
- [ ] Le rôle `eso-mediagenda-recette` et sa politique sont ceux de `plateforme/secrets` ; le magasin et les générateurs de `mediagenda-recette` visent la VIP.
- [ ] L'`ExternalSecret` `mediagenda-db-api` est prêt et a été rafraîchi depuis moins d'un cycle ; `/pret` de la recette répond 200.
- [ ] INC-5910 est ouvert, suivi (au moins deux messages d'état) et clos dans la main courante ; un courriel d'état au moins est parti ; RB-336 est publié.

**Vérification** : `lab/bin/check F3 10`

<details><summary>Indice 1</summary>

Interroge le coffre de trois façons : par la VIP, par le nom de chaque nœud (`/v1/sys/health` répond sans jeton : 200 actif, 429 en attente), et comme le fait ESO (adresse lue dans le `SecretStore` et dans le générateur de l'espace). Si les trois réponses ne racontent pas la même histoire, la panne est entre elles.
</details>

<details><summary>Indice 2</summary>

`kubectl describe externalsecret` donne le message exact d'OpenBao. « permission denied » n'est pas une panne réseau ; un délai d'attente n'est pas un problème de politique. Compare ce que la configuration **vivante** d'OpenBao dit du rôle d'ESO avec ce que `tofu plan` de `plateforme/secrets` voudrait y mettre.
</details>

<details><summary>Indice 3</summary>

Sur les nœuds du coffre, la VIP est l'affaire de keepalived et d'un script de suivi qui ne rend éligible que le nœud **actif**. Un client peut aussi se passer de la VIP s'il vise un nœud par son nom : est-ce le cas ici, et ce nœud est-il en service ?
</details>

**Pour aller plus loin** (facultatif) : chiffre la marge restante de la production au moment de ta réparation (heure d'émission de son dernier bail, durée du bail), et propose dans un ADR une architecture où la perte de la VIP ne coupe pas les clients (plusieurs adresses dans le client, VIP portée aussi par un nœud en attente avec transfert des requêtes, ou répartiteur) ; liste ce que chaque option coûte.

---

### F3-S11 — Jeudi : la moitié des noms ne répond plus  `BF` `★★★★`

> **Ticket INC-5911** — *De : Nadia Roussel, jeudi 14 h 05*
> « La moitié des noms ne répond plus, et pas toujours les mêmes. » *(Le détail de ce que voient les utilisateurs s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer un symptôme intermittent dans une architecture redondante : interroger chaque exemplaire séparément (récurseurs, passerelles, annonceurs BGP), depuis plusieurs sources.
- Distinguer une panne de **résolution** (DNS, DNSSEC) d'une panne de **chemin** (routage, BGP, ECMP, pare-feu).
- Corriger par le code (rôles Ansible des récurseurs et de la bordure) et poser une supervision qui voit chaque exemplaire.

**Prérequis** : S01-S02, S10 close ; modules 06 (PowerDNS, DNSSEC, ancres), 07 (bordure, FRR, VRRP, pare-feu), 15 (BGP de Cilium, LB IPAM, `externalTrafficPolicy`, Gateway `gw-par1`), 21 (témoin de `mon01`).
**Durée indicative** : 1 h 30 à 2 h.

**Contexte technique**
- Récurseurs : `dns01` (10.10.20.10) et `dns02` (10.10.20.16), PowerDNS Recursor, `/etc/powerdns/recursor.yml` généré par le rôle `powerdns_recursor` ; `par1.medisphere.internal` est signée DNSSEC (ancre positive) ; CoreDNS relaie vers les deux récurseurs.
- Bordure : `gw01` (maître, porte les VIP `.1`), `gw02` ; FRR, AS 65000 ; nœuds du cluster en AS 65040, adresses de service 10.10.41.0/24 annoncées en /32 et réparties par ECMP ; route de rejet pour 10.10.41.0/24 (M15-E25). Pare-feu généré par le rôle `pare_feu` depuis `group_vars/role_routeur/pare_feu.yml`.
- ⚠️ Toute intervention sur une passerelle se fait **une passerelle à la fois**, la maître en dernier (M07) ; ne redémarre ni FRR ni keepalived sur la maître pour « voir si ça repart ».

**Injection** : `lab/bin/break F3 11` (3 variantes). Temps cible : **60 min**. Une variante attend jusqu'à 6 minutes que son effet se produise avant d'afficher le symptôme.

**Travail demandé**
1. Ouvre et qualifie l'incident ; communique. Note dans la main courante, pour chaque test, **d'où** tu l'as lancé et **quel exemplaire** a répondu.
2. Reproduis de façon déterministe : quels noms, quelles adresses, depuis quels clients, par quel récurseur, par quelle passerelle.
3. Trouve la cause et corrige-la par le code (rôle et pipeline Ansible). Si un geste manuel est inévitable, écris pourquoi aucun rôle ne le couvre, et rattrape-le par un contrôle.
4. Vérifie depuis au moins trois sources (`adm01`, `mon01`, un pod) et sur **les deux** exemplaires de chaque élément redondant.
5. **Prévention** : une sonde ou une alerte qui aurait vu l'exemplaire malade, et un contrôle de dérive pour ce qui a été modifié hors du code (tickets `PLAT-3311…`). Écris **RB-337** « Une partie des noms ne répond plus » (`docs/exploitation/runbooks/`).

**Critères de réussite**
- [ ] `dns01` et `dns02` résolvent **et valident** (drapeau `ad`) les noms de `par1` et de `apps.par1`.
- [ ] Sur `gw01` et `gw02`, toute route vers une adresse de service vient de BGP et ne passe que par des nœuds du cluster ; aucune règle de pare-feu ne jette le BGP des nœuds ; toutes les sessions BGP de Cilium sont établies.
- [ ] Les adresses de service principales (Gateway, Prometheus, Alertmanager, Loki) répondent depuis `adm01`.
- [ ] INC-5911 est ouvert, suivi (au moins deux messages d'état) et clos dans la main courante ; un courriel d'état au moins est parti ; RB-337 est publié.

**Vérification** : `lab/bin/check F3 11`

<details><summary>Indice 1</summary>

`dig @<serveur>` interroge un récurseur précis ; `+dnssec` montre le drapeau `ad`, `+cd` désactive la validation. Un nom qui répond avec `+cd` et `SERVFAIL` sans lui, c'est la validation qui échoue, pas la zone.
</details>

<details><summary>Indice 2</summary>

Sur la passerelle maître, `ip route get <ADRESSE>` dit par où **ce** paquet partirait, `ip -4 route show root 10.10.41.0/24` montre toutes les routes de la plage (protocole, métrique, prochains sauts), `vtysh -c 'show bgp summary'` l'état de chaque voisin. Compare avec `gw02` : la panne ne vit peut-être que sur l'une des deux.
</details>

<details><summary>Indice 3</summary>

Une adresse de service en `externalTrafficPolicy: Local` n'est annoncée que par les nœuds qui portent un de ses pods. Et une route posée à la main, avec une meilleure métrique, passe devant BGP sans que FRR la gère ni l'affiche comme sienne. Ce qui tourne (`nft list ruleset`, `ip route`) diffère-t-il de ce que les rôles génèrent ?
</details>

**Pour aller plus loin** (facultatif) : mesure, sur la passerelle maître, la politique de hachage ECMP (`sysctl net.ipv4.fib_multipath_hash_policy`) et explique pourquoi deux postes voisins n'avaient pas le même symptôme ; évalue BFD entre la bordure et les nœuds (FRR le prend en charge ; vérifie ce qu'en dit la documentation de ta version de Cilium) et ce qu'il changerait à la durée de cette panne.

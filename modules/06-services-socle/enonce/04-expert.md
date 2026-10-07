# Module 06 — Palier 4 : Expert

Les services socle sont en production : NetBox fait foi pour les adresses et l'inventaire, PowerDNS sépare autorité et récursion et sa zone interne est signée, Kea distribue les baux du VLAN 99 en haute disponibilité et les publie dans le DNS, step-ca délivre des certificats TLS par ACME et des certificats SSH. Claire Morel en tire la conséquence habituelle : « Désormais, quand le DNS, la PKI ou NetBox tombent, ce n'est plus une machine qui est en panne, c'est toute la plateforme. La forge, la CI, Ansible, OpenTofu et les sauvegardes en dépendent. » Karim Benali a préparé huit pannes, toutes de celles qu'on rencontre vraiment autour de ces services : un nom qui ne se résout plus, des VMs sans adresse, un certificat refusé, une connexion SSH par certificat rejetée, NetBox en erreur, un inventaire vide, une zone signée qui répond SERVFAIL, des baux absents du DNS. Une astreinte les combine. Puis tu descends sous le capot : le chemin exact d'une requête DNS et d'une émission ACME, et les questions qu'on pose en entretien sur ces protocoles.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres aux services d'infrastructure :
- **Interroge chaque étage séparément.** Un client, un récurseur, un serveur faisant autorité, une base : `dig @serveur -p port` sur chaque maillon vaut mieux que dix `ping nom`. Pour TLS, un `openssl s_client` vaut mieux que le message d'un navigateur. Pour SSH, `ssh -v` et le journal de `sshd` disent chacun la moitié de l'histoire.
- **Méfie-toi des caches et de la redondance.** Un récurseur garde une réponse négative, un navigateur garde un intermédiaire, un second serveur masque la panne du premier, une connexion SSH multiplexée survit à une configuration cassée. Avant de conclure « ça remarche », vide ce qui doit l'être et teste par un chemin neuf.
- **La source de vérité d'abord.** Si un enregistrement, une adresse ou un statut est faux, demande-toi d'abord **d'où** il vient (NetBox, OpenTofu, Ansible, Kea) et corrige là, pas à l'étage où tu l'as vu.

> **Rappels** : tout se lance depuis `adm01`. Les alias SSH de `~/.ssh/config` sont en **adresses IP** (M00-E15) : une panne DNS ne te coupe pas des hôtes. Projets : `~/src/ansible` (rôles et inventaires, dont l'inventaire NetBox de M06-E12), `~/src/infra` (OpenTofu), `~/src/outils` (`medictl netbox sync`, sondes `ms-verif-services`), documentation `~/medisphere` (variable `WB_DEPOT`). Tout correctif durable passe par une MR fusionnée et le pipeline de référence ; une réparation à chaud est permise pour rétablir le service, à condition d'être reportée ensuite dans le code (sinon la détection de dérive la signalera, et le prochain passage la défera).

## Règles du jeu des pannes (M06-E35 à M06-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 06 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix des paliers précédents : relais vers `dns02`, organisation de l'inventaire…), le script en essaie une autre. Certaines injections prennent quelques minutes (M06-E36 crée une VM de test).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 06 35`) : il doit être vert. Une panne posée sur un lab déjà malade fausse tout le diagnostic.
- **Ta copie de travail `~/src/ansible` doit être propre** (`git status` sans modification) pour M06-E40 et l'astreinte : l'injection le vérifie.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 06 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque la suivante, l'astreinte M06-E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes agissent sur les hôtes du socle (fichiers sauvegardés avant modification sous `/var/lib/workbook/`, règles nftables posées à chaud et retirées à l'annulation), sur les données de NetBox (avec le jeton d'automatisation `~/.config/workbook/netbox-auto.token` et, pour les gestes « humains », ton jeton personnel `netbox-moi.token` : renouvelle-le avant le palier s'il a expiré ; valeurs d'origine conservées), sur ta copie de travail `~/src/ansible` (sauvegardée, jamais de commit) et sur la VM jetable 2064 (`m06-sonde-dhcp`, pool `lab`, étiquette `env-m06`). Jamais sur `pve01`, son réseau ou son pare-feu, jamais sur une VM hors du pool `lab`. Aucune donnée n'est détruite : en particulier, **aucune clé de zone DNSSEC** n'est supprimée sans avoir été exportée, et aucune clé de la PKI n'est touchée.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M06-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : M06-E37 (une variante) et M06-E38 peuvent te fermer la porte SSH d'un hôte. Tu as alors l'agent QEMU depuis `pve01` (`qm guest exec <VMID> -- <commande>`, sortie JSON, champ `out-data` ; `--timeout` pour les commandes longues) et le compte console `secours` du rôle `base` (M04), avec sa clé de bris de glace documentée au registre des secrets. **Vérifie ces deux chemins avant d'en avoir besoin** : `qm guest cmd 1005 ping` doit répondre, et tu dois savoir où est la clé de `secours` sans la chercher. Toute utilisation de la clé de bris de glace est consignée dans ton journal (heure, raison, ce qui a été fait) : c'est une exigence de Sophie Laurent.

> ⚠️ **Avant de « corriger en rejouant »** : un `site.yml` ou un `tofu apply` lancé pendant une panne de NetBox, du DNS ou de la PKI peut propager l'erreur (inventaire vide, enregistrements supprimés, certificats redemandés en boucle). Diagnostique d'abord, puis `--check --diff --limit` ou `tofu plan`, et lis ce qui serait changé.

---

### M06-E35 — Panne : un nom interne ne se résout plus  `BF` `★★★`

> **Ticket INC-3341** — *De : Nadia Roussel*
> Depuis 6 h 50, la sonde DNS de supervision (depuis `adm01`, vers `dns01`) est rouge : « `git01.par1.medisphere.internal` ne se résout pas ». Plusieurs jobs de CI ont échoué avec `Could not resolve host: git01.par1.medisphere.internal`, d'autres sont passés. Les noms d'Internet se résolvent normalement. Personne n'a touché au DNS, paraît-il.

**Objectifs pédagogiques**
- Découper une résolution interne en maillons testables séparément : client (deux résolveurs), récurseur de `dns01` (zones relayées, cache), autoritaire local (port 5300, base, données de la zone), secondaire `dns02`, source des données (NetBox, OpenTofu).
- Lire une réponse `dig` comme un instrument : statut (`NXDOMAIN`, `SERVFAIL`), section d'autorité (quel SOA ?), drapeaux, serveur qui a répondu.
- Comprendre le cache négatif d'un récurseur et pourquoi une panne « réparée » peut continuer de se voir.

**Prérequis** : M06-E06, M06-E07, M06-E08, M06-E15, M06-E24 ; `lab/bin/check 06 35` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : sur `dns01`, le récurseur (`pdns-recursor`, `/etc/powerdns/recursor.yml`) écoute en 10.10.20.10:53 et 127.0.0.1:53 ; l'autoritaire (`pdns`, `/etc/powerdns/pdns.conf` et ses inclusions) écoute en 127.0.0.1:5300 et 10.10.20.10:5300. Les clients du lab ont deux résolveurs (10.10.20.10 puis 10.10.20.16). La commande `rec_control` (sur `dns01`, en root) pilote le récurseur à chaud.

**Injection** : `lab/bin/break 06 35` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme **sans** passer par le résolveur système : interroge explicitement chaque résolveur du lab pour `git01.par1.medisphere.internal`, pour un autre nom interne et pour un nom d'Internet. Note le statut exact de chaque réponse et sa section d'autorité. Pourquoi certains jobs de CI passent-ils encore ?
2. Remonte la chaîne sur `dns01` : l'autoritaire local répond-il pour ce nom sur son port ? Le secondaire `dns02` aussi ? Que dit le journal de chaque démon (`journalctl -u pdns -u pdns-recursor`) ?
3. Trouve la cause racine et corrige-la **à l'endroit où elle a été introduite** : fichier de configuration (puis rôle Ansible qui le gère), données de la zone (puis source de vérité qui les produit), droits d'un fichier…
4. Quand l'étage fautif est réparé, vérifie que le récurseur sert la bonne réponse **maintenant**. Si ce n'est pas le cas, explique pourquoi dans ton journal et agis de la façon la plus ciblée possible.
5. Indique dans ton journal ce que la redondance (`dns02`) a masqué ou non pour la variante rencontrée, et quelle sonde aurait vu la panne plus tôt.

**Critères de réussite**
- [ ] `dig @10.10.20.10 git01.par1.medisphere.internal` répond `10.10.20.12`, comme les autres noms du socle, en UDP et en TCP ; idem sur `dns02`.
- [ ] L'autoritaire local de `dns01` sert la zone sur 127.0.0.1:5300 (celui de `dns02` aussi, sur 10.10.20.16:5300), sa base est lisible par le compte du service, et le récurseur relaie la zone interne vers lui.
- [ ] Ton journal contient les réponses `dig` initiales commentées (statut, autorité), la cause racine et l'endroit de la correction durable.

**Vérification** : `lab/bin/check 06 35`

<details><summary>Indice 1</summary>

Trois statuts, trois histoires : `NXDOMAIN` avec dans la section d'autorité le SOA de **ta** zone (le nom n'existe pas chez toi), `NXDOMAIN` avec le SOA d'une **autre** zone (la question est partie ailleurs), `SERVFAIL` (le récurseur n'a pas obtenu de réponse exploitable). `dig +norecurse` et `dig -p 5300 @127.0.0.1` sur `dns01` séparent récurseur et autoritaire.
</details>

<details><summary>Indice 2</summary>

`rec_control get-parameter` (section `recursor`) et le journal du récurseur au démarrage disent quelles zones il relaie et vers où. Côté autoritaire, `systemctl status pdns` et `pdnsutil zone list-all` disent s'il tourne et ce qu'il sert ; `ls -l` sur sa base dit s'il peut la lire.
</details>

<details><summary>Indice 3</summary>

Si l'autoritaire répond juste et que le récurseur répond encore faux, ce n'est plus une question de configuration mais de mémoire : `rec_control` sait vider le cache d'**un seul** nom (ou d'une zone entière), et `recordcache.max_negative_ttl` borne la durée de vie d'une réponse négative.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-services` une sonde qui interroge **chaque** maillon (récurseur de `dns01`, de `dns02`, autoritaire de `dns01` et `dns02` sur 5300) et compare les réponses : elle aurait localisé chacune des quatre variantes en une ligne.

---

### M06-E36 — Panne : les VMs sandbox n'obtiennent plus d'adresse  `BF` `★★`

> **Ticket INC-3342** — *De : Julien Petit*
> Mes VMs de test sur le VLAN sandbox démarrent sans adresse IPv4 depuis ce matin : seule une adresse `fe80::` apparaît sur `ens18`. Les VMs démarrées hier gardent leur adresse. Pour que tu puisses reproduire, une VM de test `m06-sonde-dhcp` (VMID 2064, VNet `vsandbox`) vient d'être démarrée : elle n'a pas d'adresse non plus.

**Objectifs pédagogiques**
- Suivre un échange DHCP relayé de bout en bout : client (VLAN 99) → relais `gw01` (`giaddr` 10.10.99.1) → Kea sur `dns01`/`dns02` → retour vers le relais → client.
- Utiliser `tcpdump` aux bons endroits et dans le bon ordre (côté client, côté serveur, sur le relais), et les journaux de Kea et de dnsmasq.
- Distinguer configuration en fichier, configuration chargée et règles posées à chaud (`nft list ruleset` contre le fichier généré par le rôle `pare_feu`).

**Prérequis** : M00-E14 (relais), M06-E16, M06-E25 ; `lab/bin/check 06 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la VM 2064 est une VM jetable (clone lié de l'image dorée `current`, étiquette `env-m06`) ; pour retester après une correction, redémarre-la (`qm reboot 2064`) puis lis ses adresses par l'agent (`qm guest cmd 2064 network-get-interfaces`). Les baux de Kea sont dans `/var/lib/kea/` (fichier `memfile`). Le relais de `gw01` est la configuration dnsmasq de M00-E14, gérée depuis M06-E25 par le code Ansible ; le pare-feu de `gw01` est celui du rôle `pare_feu`.

**Injection** : `lab/bin/break 06 36` (4 variantes ; l'injection crée la VM 2064 et prend 2 à 4 minutes).

**Travail demandé**
1. Reproduis le symptôme avec la VM 2064. Pendant un redémarrage de la VM, observe le trafic DHCP en deux points : là où le client émet (dans quel équipement le captures-tu ?) et là où le serveur devrait recevoir. Note jusqu'où le DISCOVER arrive.
2. Déduis l'étage en cause : relais, filtrage, serveur. Confirme par une seconde mesure (journal, compteurs, état du service) avant de toucher à quoi que ce soit.
3. Corrige à la racine. Si le défaut est dans un fichier géré par Ansible, la correction durable passe par le rôle ; si c'est une règle posée à chaud, explique comment la détection de dérive l'aurait (ou non) vue.
4. Prouve le retour à la normale : la VM 2064 obtient une adresse dans 10.10.99.100-199 après redémarrage, et le bail apparaît chez Kea.
5. Clos la panne (`--annuler` détruit aussi la VM 2064).

**Critères de réussite**
- [ ] La VM 2064 obtient une adresse du VLAN 99 après redémarrage.
- [ ] Kea est actif sur `dns01` et `dns02`, sa configuration passe `kea-dhcp4 -t`, il écoute sur UDP/67 ; le relais de `gw01` relaie le VLAN 99 et rien ne filtre ses réponses.
- [ ] Ton journal contient les deux captures (ou leurs extraits commentés) qui localisent la panne.

**Vérification** : `lab/bin/check 06 36` (avant `--annuler` : le contrôle regarde aussi l'adresse de la VM 2064).

<details><summary>Indice 1</summary>

Sur `pve01`, l'interface de la carte de la VM 2064 s'appelle `tap2064i0` ; sur `dns01`, `tcpdump -ni ens18 port 67 or port 68`. Le relais transforme un broadcast en unicast : ce que tu vois d'un côté ne ressemble pas à ce que tu vois de l'autre (adresse source, `giaddr`, ports).
</details>

<details><summary>Indice 2</summary>

Sur `gw01` : la ligne `dhcp-relay=` de dnsmasq indique l'adresse **locale** sur laquelle le relais écoute et le serveur vers lequel il relaie. `nft list chain inet filter input` montre aussi les compteurs : une règle qui jette quelque chose se voit à ses compteurs qui montent pendant un essai. Sur `dns01`, `journalctl -u isc-kea-dhcp4-server` et `kea-dhcp4 -t /etc/kea/kea-dhcp4.conf`.
</details>

**Pour aller plus loin** : écris une sonde DHCP qui n'a pas besoin de VM (par exemple `perfdhcp` de Kea, lancé depuis une machine du VLAN 99, ou une requête relayée forgée depuis `gw01`), et ajoute-la à `ms-verif-services`.

---

### M06-E37 — Panne : certificat refusé  `BF` `★★★`

> **Ticket INC-3343** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : il dit quel client refuse quel certificat, et ce qui fonctionne encore.)*

**Objectifs pédagogiques**
- Décomposer « certificat refusé » en questions séparées : quelle chaîne le serveur présente-t-il ? Le client a-t-il l'ancre de confiance ? Le nom correspond-il ? Les dates sont-elles valides **pour l'horloge du client** ?
- Utiliser `openssl s_client -showcerts`, `openssl x509 -noout -text`, `openssl verify -CAfile`, `curl -v` et `step certificate inspect` pour répondre à chacune.
- Comprendre pourquoi un navigateur et un client en ligne de commande peuvent rendre des verdicts différents sur le même serveur.

**Prérequis** : M06-E02, M06-E03, M06-E18, M06-E21, M06-E27 ; `lab/bin/check 06 37` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la racine « MédiSphère Root CA » est installée sous `/usr/local/share/ca-certificates/medisphere-root-ca.crt` sur tous les hôtes (rôle `ca_lab`) ; l'intermédiaire « MédiSphère Intermediate CA » n'est installé nulle part : c'est aux serveurs de le présenter. Les certificats de `git01` (dans `/etc/gitlab/ssl/`), `nbx01` (nginx) et `s3-01` sont délivrés par ACME (30 jours au plus). Les certificats SSH d'hôte et d'utilisateur sont aussi datés. GitLab Runner (programme Go) lit le magasin système **au démarrage** du service.

**Injection** : `lab/bin/break 06 37` (4 variantes).

**Travail demandé**
1. Reproduis le refus avec le client qui échoue, puis avec `openssl s_client` depuis la même machine. Note le code et le message de vérification exacts.
2. Réponds dans l'ordre, preuves à l'appui : quelle chaîne le serveur présente-t-il (combien de certificats, qui a émis quoi) ? Le client a-t-il la racine ? Le nom demandé est-il dans le SAN ? Quelle heure est-il pour le client ?
3. Explique pourquoi l'autre client du ticket (navigateur, autre machine) ne voit pas le même problème.
4. Corrige à la racine, sans désactiver la vérification nulle part (`-k`, `GIT_SSL_NO_VERIFY`, `verify: false` sont des refus d'exercice). Si la variante t'a fermé la porte SSH d'un hôte, entre par l'accès de secours et consigne-le.
5. Prévention : quelle sonde de `ms-verif-services` (M06-E29) aurait détecté ce cas, et que faudrait-il y ajouter si elle ne l'a pas vu ?

**Critères de réussite**
- [ ] Depuis `adm01`, les certificats de `nbx01`, `git01`, `ca01` et `s3-01` sont vérifiés sans option de contournement ; ceux de `nbx01` et `git01` sont émis par l'intermédiaire MédiSphère et présentés avec leur chaîne complète.
- [ ] Sur `runner01`, la racine MédiSphère est dans le magasin système, `curl https://git01.par1.medisphere.internal` aboutit, l'horloge est synchronisée par chrony et le runner est actif.
- [ ] Ton journal contient la sortie de vérification initiale et la réponse argumentée aux quatre questions de l'étape 2.

**Vérification** : `lab/bin/check 06 37`

<details><summary>Indice 1</summary>

`openssl s_client -connect <ip>:443 -servername <fqdn> -showcerts </dev/null` affiche ce que le **serveur** envoie, puis `Verify return code:` ce qu'en pense le **client** avec son magasin. Compte les blocs `BEGIN CERTIFICATE`, lis les lignes `s:` (sujet) et `i:` (émetteur) de chacun.
</details>

<details><summary>Indice 2</summary>

`unable to get local issuer certificate`, `self-signed certificate in certificate chain`, `certificate has expired` et `certificate is not yet valid` ne pointent pas vers le même étage. Les navigateurs complètent parfois une chaîne incomplète avec un intermédiaire déjà vu (cache) ; `curl` et Python ne le font jamais.
</details>

<details><summary>Indice 3</summary>

Si tout semble juste côté serveur et que seul un hôte refuse tout, regarde **cet** hôte : `ls -l /etc/ssl/certs | grep -i medisphere`, `timedatectl`, `chronyc tracking`. Et si tu ne peux plus y entrer en SSH, demande-toi pourquoi : la réponse est peut-être la même.
</details>

**Pour aller plus loin** : écris un contrôle CI qui, pour chaque service HTTPS du socle, vérifie la chaîne présentée **sans** l'intermédiaire dans le magasin (`openssl verify -CAfile racine.pem` sur la feuille seule doit échouer, sur feuille + chaîne doit réussir).

---

### M06-E38 — Panne : connexion SSH par certificat refusée  `BF` `★★★`

> **Ticket INC-3344** — *De : Karim Benali*
> Impossible d'entrer sur un hôte depuis le bastion : `admin@10.10.20.x: Permission denied (publickey)` *(l'hôte exact s'affiche à l'injection)*. Mon certificat SSH est frais (je l'ai renouvelé ce matin) et il passe sur les autres hôtes. Ne touche pas à la clé de bris de glace pour « dépanner » : Sophie veut savoir ce qui a changé sur cet hôte.

**Objectifs pédagogiques**
- Connaître les étapes qu'un serveur OpenSSH applique à un certificat d'utilisateur : algorithme accepté, signature par une CA de `TrustedUserCAKeys`, validité, principal autorisé (`AuthorizedPrincipalsFile`), révocation (`RevokedKeys`), options critiques.
- Faire parler les deux extrémités : `ssh -vvv` côté client, `journalctl -u ssh` (niveau `VERBOSE` ou `DEBUG` temporaire) côté serveur, `sshd -T` pour la configuration **effective**.
- Utiliser l'accès de secours proprement (agent QEMU, compte `secours`) et ne rien affaiblir pour s'en sortir.

**Prérequis** : M06-E19, M06-E20, M06-E27 ; M04 (rôle `base`, compte `secours`) ; `lab/bin/check 06 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : ton certificat d'utilisateur est sur `adm01` (`~/.ssh/*-cert.pub`), émis par step-ca pour 16 h, principal `admin`. Sur les hôtes, la configuration de `sshd` est éclatée dans `/etc/ssh/sshd_config.d/` (inclus **en tête** du fichier principal ; pour la plupart des directives, la **première** valeur lue l'emporte). La cible est l'un de `nbx01` (VMID 1005), `ca01` (1003) ou `dns02` (1008).

**Injection** : `lab/bin/break 06 38` (4 variantes).

**Travail demandé**
1. Reproduis le refus **sans multiplexage** (`-o ControlPath=none`) et avec `-vvv`. Relève ce que le client a proposé (clés, certificat) et ce que le serveur a répondu à chaque proposition.
2. Entre sur l'hôte par l'agent QEMU. Lis le journal de `sshd` au moment de ta tentative : il donne la raison du refus, à condition de savoir où regarder (et au besoin d'augmenter temporairement le niveau de journal, ce que tu consigneras et annuleras).
3. Établis la configuration **effective** de `sshd` (`sshd -T`) pour ce qui touche aux certificats, et compare-la à celle d'un hôte sain. Identifie le fichier et la ligne responsables.
4. Corrige à la racine, valide (`sshd -t`), recharge. Si le défaut vient d'un fichier que le code Ansible ne gère pas, explique pourquoi la détection de dérive ne l'a pas vu et ce qu'il faudrait changer pour qu'elle le voie.
5. Prouve le retour : nouvelle connexion par certificat, et explique dans ton journal pourquoi tu n'as **pas** eu besoin de la clé de bris de glace (ou, si tu l'as utilisée, pourquoi c'était nécessaire).

**Critères de réussite**
- [ ] Une nouvelle connexion SSH (sans multiplexage) aboutit avec ton certificat vers chaque hôte du socle.
- [ ] Sur chaque hôte, `TrustedUserCAKeys` contient la CA qui a signé ton certificat, et `sshd` accepte les algorithmes de certificats.
- [ ] Le compte `secours` est intact ; ton journal contient le message d'erreur côté serveur et la ligne de configuration fautive.

**Vérification** : `lab/bin/check 06 38`

<details><summary>Indice 1</summary>

Côté client, `ssh -vvv` montre `Offering public key: … ED25519-CERT …` puis la réponse du serveur. `ssh-keygen -Lf ~/.ssh/<clé>-cert.pub` affiche la CA signataire (empreinte), les principaux et la validité de ton certificat : c'est ta référence pour comparer.
</details>

<details><summary>Indice 2</summary>

Par l'agent : `qm guest exec <VMID> -- journalctl -u ssh -n 30 --no-pager` et `qm guest exec <VMID> -- sshd -T`. Les directives à regarder : `trustedusercakeys`, `authorizedprincipalsfile`, `pubkeyacceptedalgorithms`, `revokedkeys`. `ssh-keygen -lf <fichier>` donne l'empreinte des clés d'un fichier ; `ssh-keygen -Q -f <krl> <clé.pub>` dit si une clé est révoquée.
</details>

**Pour aller plus loin** : ajoute au scénario Molecule du rôle `ssh_ca_utilisateur` un test qui se connecte **avec un certificat** (et seulement avec lui) et un test qui vérifie qu'aucun fichier de `sshd_config.d/` non géré par le rôle n'existe.

---

### M06-E39 — Panne : NetBox en erreur  `BF` `★★`

> **Ticket INC-3345** — *De : Claire Morel*
> NetBox ne répond plus correctement : la page d'accueil affiche une erreur, l'API aussi. La synchronisation Proxmox → NetBox de cette nuit a échoué, et la MR de Karim attend un plan OpenTofu qui interroge NetBox. InfoGér a « fait une passe d'audit » sur la VM hier. Rétablis le service, et dis-moi ce qui a été touché.

**Objectifs pédagogiques**
- Lire une architecture applicative en couches (nginx → gunicorn → Django/NetBox → PostgreSQL et Valkey) et localiser l'étage défaillant par le **code HTTP** et le journal de chaque couche.
- Exploiter les journaux de NetBox (`journalctl -u netbox`), de nginx, de PostgreSQL et de Valkey, et les outils de chaque couche (`curl` local, `psql`, `valkey-cli`, `manage.py`).
- Retrouver « ce qui a été touché » sur une machine sans historique fiable : dates de modification, différences avec ce que produirait le rôle Ansible.

**Prérequis** : M06-E04, M06-E10, M06-E28, M06-E30 ; `lab/bin/check 06 39` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : installation native de M06-E04 : NetBox sous `/opt/netbox` (configuration `netbox/netbox/configuration.py`, `gunicorn.py`), services `netbox` (gunicorn) et `netbox-rq`, nginx en frontal, PostgreSQL 17, Valkey (`valkey-server`, `/etc/valkey/valkey.conf`). Le rôle Ansible `netbox` gère ces fichiers.

**Injection** : `lab/bin/break 06 39` (4 variantes).

**Travail demandé**
1. Note le **code HTTP** exact renvoyé par NetBox (page d'accueil et `/api/status/`). Ce seul code élimine déjà des couches : lesquelles ?
2. Descends couche par couche jusqu'à la première qui échoue, en interrogeant chacune directement (nginx, puis gunicorn en local, puis les dépendances de Django).
3. Trouve la modification responsable. Montre comment tu l'as trouvée (dates, différence avec le rôle : `--check --diff --limit nbx01`).
4. Corrige par la voie durable (rôle Ansible) ou, si tu rétablis d'abord à la main, fais converger le rôle ensuite et prouve qu'il ne change plus rien.
5. Vérifie la chaîne complète : interface, API, worker RQ, synchronisation Proxmox → NetBox, inventaire Ansible NetBox.

**Critères de réussite**
- [ ] `https://nbx01.par1.medisphere.internal/login/` répond 200 avec un certificat vérifié ; `/api/status/` indique NetBox 4.6 et au moins un worker RQ.
- [ ] `netbox`, `netbox-rq`, `nginx`, `postgresql` et `valkey-server` sont actifs ; `--check --diff` du rôle `netbox` sur `nbx01` ne montre aucune différence.
- [ ] Ton journal associe le code HTTP initial à la couche fautive et contient la preuve de la modification.

**Vérification** : `lab/bin/check 06 39`

<details><summary>Indice 1</summary>

`502` : nginx n'obtient pas de réponse de l'amont. `400` : Django refuse la requête avant même de la traiter. `500` : Django a planté en la traitant (le journal de `netbox` contient la pile d'appel, et sa dernière ligne nomme l'exception). Chaque code a son endroit où regarder.
</details>

<details><summary>Indice 2</summary>

Sur `nbx01` : `curl -sI http://127.0.0.1:8001/` interroge gunicorn sans nginx. `sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py check` et `… manage.py dbshell` testent la configuration et la base. `valkey-cli ping`, `ss -ltnp` et `find /etc /opt/netbox -newer <fichier-témoin>` font le reste.
</details>

**Pour aller plus loin** : ajoute au rôle `netbox` un *handler* de vérification (`/api/status/` en 200 après redémarrage) qui fait échouer le passage si NetBox ne revient pas, et un test Molecule qui le prouve.

---

### M06-E40 — Panne : l'inventaire NetBox ne renvoie plus d'hôtes  `BF` `★★`

> **Ticket INC-3346** — *De : Nadia Roussel*
> Le contrôle de dérive de cette nuit (`site.yml --check`, inventaire NetBox) a échoué en quelques secondes, sur le garde-fou de tête de `site.yml` : le groupe `socle` est vide. `ansible-inventory --graph` avec l'inventaire NetBox ne montre plus aucun hôte du socle ; avec l'inventaire Proxmox, tout est là. Personne n'a touché au projet Ansible, paraît-il.

**Objectifs pédagogiques**
- Comprendre comment le plugin `netbox.netbox.nb_inventory` construit un inventaire : requêtes à l'API, filtres (`query_filters`), objets inclus, regroupements (`group_by`, `keyed_groups`), variables composées.
- Rejouer à la main, avec `curl` et le jeton, les requêtes que fait le plugin pour savoir si le problème est dans les **données** de NetBox ou dans la **configuration** de l'inventaire.
- Retrouver qui a changé quoi dans NetBox (journal des modifications, `/api/core/object-changes/`).

**Prérequis** : M06-E05, M06-E10, M06-E11, M06-E12 ; M04-E39 (garde-fou) ; `lab/bin/check 06 40` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : l'inventaire NetBox est le fichier de `~/src/ansible/inventories/lab/` qui déclare `plugin: netbox.netbox.nb_inventory` (M06-E12) ; il lit son jeton dans l'environnement. NetBox garde l'historique de chaque modification d'objet (utilisateur, date, avant/après).

**Injection** : `lab/bin/break 06 40` (3 variantes).

**Travail demandé**
1. Reproduis avec `ansible-inventory -i <inventaire NetBox> --graph`, puis avec `-vvv` : quelles requêtes le plugin envoie-t-il, avec quels filtres ?
2. Rejoue ces requêtes avec `curl` (jeton en lecture). Les VMs du socle sont-elles renvoyées ? Avec quelles étiquettes, quel statut ? Conclus : données ou configuration ?
3. Trouve le changement responsable (dans `git status`/`git diff` du projet, ou dans le journal des modifications de NetBox : qui, quand, avant/après).
4. Corrige au bon endroit : une donnée de NetBox se corrige dans NetBox (et, si un script de synchronisation l'a produite, dans le script) ; une configuration d'inventaire se corrige dans le dépôt. Rejoue le contrôle de dérive.
5. Explique dans ton journal pourquoi le garde-fou de M04-E39 a transformé une panne silencieuse en échec visible, et ce qu'il se serait passé sans lui.

**Critères de réussite**
- [ ] Le groupe `socle` de l'inventaire NetBox contient au moins tous les hôtes que l'inventaire Proxmox y met ; `nbx01` a pour `ansible_host` 10.10.20.13.
- [ ] Dans NetBox, l'étiquette `socle` existe et toutes les VMs qui la portent sont au statut `active`.
- [ ] La copie de travail `~/src/ansible` est propre ; ton journal identifie l'auteur et l'heure du changement (ou le fichier modifié).

**Vérification** : `lab/bin/check 06 40`

<details><summary>Indice 1</summary>

`ansible-inventory -vvv` affiche les URL appelées. La même requête en `curl -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-checks.token)" "<url>" | jq '.count'` dit tout de suite si NetBox renvoie zéro objet ou si c'est le plugin qui les écarte ensuite.
</details>

<details><summary>Indice 2</summary>

Dans l'interface : *Other → Change Log* (ou `/api/core/object-changes/?time_after=…`). Côté dépôt : `git status` et `git diff`. Un filtre `tag`, `status` ou `virtual_machines` qui ne correspond plus à rien ne produit **aucune** erreur : seulement un inventaire vide.
</details>

**Pour aller plus loin** : ajoute au pipeline de `plateforme/ansible` une étape qui compare les groupes `socle` des deux inventaires (Proxmox et NetBox) et échoue s'ils diffèrent : c'est la traduction en test de l'ADR-0060.

---

### M06-E41 — Panne : SERVFAIL sur la zone signée  `BF` `★★★`

> **Ticket INC-3347** — *De : Nadia Roussel*
> Alerte P1 : plus aucun nom en `par1.medisphere.internal` ne se résout via `dns01` (SERVFAIL). La CI, Ansible et les sauvegardes échouent en cascade. Internet se résout normalement. Karim travaillait hier sur la signature de la zone (« préparation du roulement de clé »).
> ⚠️ Ne supprime aucune clé de zone sans l'avoir exportée : Sophie veut pouvoir tout rejouer.

**Objectifs pédagogiques**
- Distinguer une panne DNSSEC d'une panne DNS ordinaire en une commande (`+cd`), puis localiser le maillon de la chaîne de confiance qui casse : ancre (DS) → DNSKEY → RRSIG → données.
- Utiliser `dig +dnssec +multi`, `dig +cd`, `delv` (avec une ancre fournie), `pdnsutil zone show/check/export-ds`, `rec_control get-tas` et le journal du récurseur (`dnssec.log_bogus`).
- Mener un roulement de clé (ou son retour arrière) sans jamais perdre de clé ni casser la validation.

**Prérequis** : M06-E24, M06-E26 ; `lab/bin/check 06 41` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique** : la zone `par1.medisphere.internal` est signée par PowerDNS Authoritative (signature à la volée, clés dans la base) ; le récurseur de `dns01` (et celui de `dns02`) la valide grâce à une ancre de confiance déclarée dans `recursor.yml` (`dnssec.trustanchors`, `dnssec.validation: validate`). Les commandes `pdnsutil` de PowerDNS 5.0 suivent la forme `pdnsutil <objet> <action>` (`pdnsutil zone show`, `pdnsutil zone list-keys`, `pdnsutil metadata get`…).

> ⚠️ **Attention** : avant toute action sur les clés de la zone (`activate-key`, `deactivate-key`, `remove-key`, `add-key`), exporte **toutes** les clés (`pdnsutil zone export-key <zone> <id>`) dans un fichier en mode 600 hors de tout dépôt, et note leur état (`pdnsutil zone show`). Une clé supprimée sans export est perdue ; un retour arrière sans elle impose de changer l'ancre partout.

**Injection** : `lab/bin/break 06 41` (3 variantes).

**Travail demandé**
1. Prouve que la panne est une panne de **validation** et non de données : compare la réponse avec et sans contrôle DNSSEC désactivé côté client.
2. Lis la chaîne de confiance maillon par maillon : quelles clés la zone publie-t-elle (étiquette, algorithme, drapeaux) ? Leurs signatures sont-elles présentes et valides ? L'ancre configurée dans le récurseur correspond-elle à l'une d'elles ? Le journal du récurseur dit-il pourquoi la réponse est jugée *bogus* ?
3. Confirme avec un validateur indépendant (`delv` et une ancre extraite de la zone) pour ne pas dépendre du seul récurseur.
4. Corrige en choisissant **explicitement** entre deux stratégies quand elles existent (revenir à l'état précédent, ou terminer proprement l'opération interrompue), et justifie ce choix dans ton journal. Exporte les clés avant de toucher à l'une d'elles.
5. Vérifie la validation sur `dns01` **et** `dns02`, puis rédige dans ton journal la procédure de roulement de KSK qui aurait évité la panne (étapes, délais liés aux TTL, contrôle à chaque étape).

**Critères de réussite**
- [ ] Les réponses de `dns01` et `dns02` pour la zone portent le drapeau `ad` (validées).
- [ ] La zone n'est pas en mode *presigned* sur le primaire, a au moins une clé active, `pdnsutil zone check` ne signale rien, et l'ancre du récurseur correspond au DS d'une clé active.
- [ ] Les exports de clés faits pendant l'exercice existent hors de tout dépôt (mode 600) ; ton journal contient la stratégie retenue et la procédure de roulement.

**Vérification** : `lab/bin/check 06 41`

<details><summary>Indice 1</summary>

`dig @10.10.20.10 +cd git01.par1.medisphere.internal` : si la réponse arrive avec `+cd` (*checking disabled*) et pas sans, les données sont là et c'est la validation qui échoue. `dnssec.log_bogus: true` fait écrire au récurseur la raison exacte de chaque échec.
</details>

<details><summary>Indice 2</summary>

`dig @127.0.0.1 -p 5300 +dnssec +multi par1.medisphere.internal DNSKEY` (sur `dns01`) donne les clés publiées et leur *key tag* ; `pdnsutil zone export-ds par1.medisphere.internal` calcule leurs DS ; `rec_control get-tas` affiche l'ancre réellement chargée. Trois listes de nombres à rapprocher. Une zone sans DNSKEY ni RRSIG alors qu'elle a une ancre est, elle aussi, *bogus*.
</details>

<details><summary>Indice 3</summary>

`pdnsutil metadata get par1.medisphere.internal` liste toutes les métadonnées de la zone : certaines changent la façon dont PowerDNS signe (ou ne signe plus). Pour `delv`, un fichier `trust-anchors { … initial-ds … };` contenant le DS attendu, passé par `-a`.
</details>

**Pour aller plus loin** : écris la sonde « DNSSEC » de `ms-verif-services` : drapeau `ad` sur les deux récurseurs, correspondance ancre ↔ DS d'une clé active, et alerte J-7 si une clé est marquée pour un roulement non terminé.

---

### M06-E42 — Panne : les baux n'apparaissent plus dans le DNS  `BF` `★★`

> **Ticket INC-3348** — *De : Julien Petit*
> Mes VMs de test du VLAN sandbox obtiennent bien une adresse, mais depuis hier leur nom (`sbxNN.par1.medisphere.internal`) ne se résout plus : NXDOMAIN, et rien non plus en inverse. Les VMs plus anciennes ont toujours leur nom. Mes tests d'intégration s'appuient dessus.

**Objectifs pédagogiques**
- Suivre la chaîne DDNS : bail accordé par `kea-dhcp4` → requête de changement de nom (NCR) vers `kea-dhcp-ddns` → mise à jour RFC 2136 signée TSIG (RFC 8945) vers PowerDNS → autorisation par la zone.
- Lire les journaux de chaque maillon et reproduire la mise à jour à la main avec `nsupdate` et la même clé, pour isoler le côté qui refuse.
- Faire une rotation de clé TSIG cohérente des deux côtés, sans exposer le secret.

**Prérequis** : M06-E16, M06-E17, M06-E25 ; `lab/bin/check 06 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `kea-dhcp4` transmet les NCR à `kea-dhcp-ddns` (`/etc/kea/kea-dhcp-ddns.conf`, clé `ddns-kea`), qui met à jour la zone directe et la zone inverse sur l'autoritaire local (127.0.0.1:5300). Côté PowerDNS : réglage global `dnsupdate`, clé importée (`pdnsutil tsigkey list`), métadonnées de zone `TSIG-ALLOW-DNSUPDATE` et `ALLOW-DNSUPDATE-FROM`. Pour obtenir un bail neuf, crée (ou recrée) la VM de test 2065 `m06-client` sur `vsandbox`, comme en M06-E25 (ou redémarre une VM existante après avoir libéré son bail).

> ⚠️ **Attention** : un secret TSIG ne s'affiche ni dans un ticket, ni dans ton journal, ni dans une commande qui finit dans l'historique du shell. Pour `nsupdate`, préfère `-k <fichier de clé>` (mode 600) à `-y`.

**Injection** : `lab/bin/break 06 42` (4 variantes).

**Travail demandé**
1. Reproduis avec un bail neuf. Vérifie chaque maillon dans l'ordre : le bail existe-t-il chez Kea avec un nom ? Une NCR est-elle partie ? `kea-dhcp-ddns` l'a-t-il reçue, et qu'a répondu le serveur DNS ?
2. Rejoue la mise à jour à la main avec `nsupdate`, la même clé et le même serveur que `kea-dhcp-ddns`, sur un nom de test (que tu retireras). Le code de réponse DNS (`REFUSED`, `NOTAUTH`, `BADSIG`…) dit quel côté refuse et pourquoi.
3. Corrige la cause racine des deux côtés si nécessaire (configuration de Kea par son rôle, clé et métadonnées PowerDNS par le leur), sans jamais afficher le secret.
4. Rattrape les baux accordés pendant la panne : comment faire publier leurs noms sans attendre leur renouvellement ? Choisis et justifie.
5. Prévention : quelle sonde aurait vu la panne (bail sans nom dans le DNS, compteurs de `kea-dhcp-ddns`, journaux) ?

**Critères de réussite**
- [ ] `kea-dhcp-ddns` est actif, `kea-dhcp4` lui transmet les demandes, et PowerDNS accepte les mises à jour signées par la clé `ddns-kea`, autorisée sur la zone.
- [ ] Chaque bail actif nommé du VLAN 99 est résolu dans la zone directe (et inverse).
- [ ] Ton journal contient le code de réponse obtenu par `nsupdate` pendant la panne et l'explication de ce qu'il désigne ; aucun secret n'y figure.

**Vérification** : `lab/bin/check 06 42`

<details><summary>Indice 1</summary>

Les journaux de `kea-dhcp4` (messages `DHCP4_…` et `DHCP_DDNS_…`) disent si une NCR est envoyée ; ceux de `kea-dhcp-ddns` (`DHCP_DDNS_…`) disent ce que le serveur DNS a répondu ; ceux de `pdns` disent **pourquoi** il a refusé (avec le niveau de journal adapté). Commence par le maillon du milieu : il voit les deux autres.
</details>

<details><summary>Indice 2</summary>

Dans PowerDNS, une mise à jour doit passer plusieurs portes : le service doit les accepter (réglage global), l'adresse source ou la clé doit être autorisée pour la zone, et la signature doit être valide avec le secret connu de PowerDNS. Dans Kea, deux réglages distincts (connexion à D2, et envoi des mises à jour) doivent être vrais.
</details>

**Pour aller plus loin** : automatise la rotation de la clé `ddns-kea` (nouvelle clé importée dans PowerDNS, autorisée en plus de l'ancienne, Kea basculé, ancienne retirée) dans un playbook rejouable, et inscris son échéance au registre des secrets.

---

### M06-E43 — Astreinte : les services socle en panne  `BF` `★★★★`

> **Ticket INC-3350** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Jeudi, 7 h 10 : plusieurs remontées sur les services socle (le détail s'affiche à l'injection). Les équipes de MédiAgenda ont une mise en production à 14 h : la forge, la CI et le DNS doivent être sains d'ici là. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur des services dont tout dépend : trier, prioriser par dépendances (DNS et PKI avant le reste), éviter qu'une panne en masque une autre.
- Communiquer pendant l'incident (statut, impact, prochaine étape, prochaine communication).
- Rédiger un post-mortem sans recherche de coupable, centré sur les causes, la détection et les actions.

**Prérequis** : M06-E35 à M06-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M06-E35 à M06-E42 (variantes aléatoires) et les injecte ensemble. Les symptômes peuvent se recouvrir ou s'amplifier (un DNS cassé fait échouer un inventaire, une PKI cassée fait échouer une synchronisation). `--variante N` (1 à 27) force la paire, pas les variantes. `--annuler` retire les deux. La copie de travail `~/src/ansible` doit être propre.

**Injection** : `lab/bin/break 06 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact métier (qui ne peut plus faire quoi ?) et une hypothèse de regroupement. Vérifie d'abord tes instruments : SSH vers chaque hôte (par IP), agent QEMU, résolution DNS **explicite** (`dig @…`). Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances entre services. Tiens ton journal horodaté.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** tes tests de départ.
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem rédigé à partir de `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`, enregistré dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-3350.md` et publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M06-E35 à M06-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, contient une chronologie horodatée, les deux causes racines, l'analyse de la détection (qu'est-ce qui aurait dû alerter avant Nadia ?) et des actions correctives avec responsable et échéance.
- [ ] Le journal contient au moins trois communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 06 43`

<details><summary>Indice 1</summary>

L'ordre des dépendances du socle : réseau → DNS → PKI/temps → NetBox → ce qui consomme tout cela (inventaires, synchronisations, CI). Une panne plus bas dans la pile fausse les tests de tout ce qui est au-dessus.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 06 35` à `06 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), et chronomètre le temps jusqu'au **premier diagnostic juste** en plus du temps de rétablissement : c'est le chiffre que la supervision doit faire baisser.

---

### M06-E44 — Sous le capot : une résolution DNS et une émission ACME pas à pas  `LAB` `★★★`

> **Ticket PLAT-781** — *De : Karim Benali*
> Pendant les pannes, j'ai entendu « le DNS fait sa cuisine » et « ACME, c'est magique ». Je veux que tu saches **montrer** ce qui passe sur le fil : une requête d'un client jusqu'à l'autoritaire (interne et Internet, avec la validation DNSSEC), et une émission de certificat ACME de bout en bout, requête par requête. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Observer le travail d'un récurseur : relais d'une zone interne, récursion itérative depuis la racine, cache positif et négatif, validation DNSSEC (requêtes DS/DNSKEY supplémentaires).
- Connaître le déroulé d'ACME (RFC 8555) et le reconnaître dans les journaux du serveur : annuaire, *nonce*, compte, commande (*order*), autorisation, défi `http-01`, validation, finalisation par CSR, téléchargement du certificat.
- Relier chaque étape à une panne possible (et à une panne de M06-E35 à M06-E42).

**Prérequis** : M06-E07, M06-E18, M06-E26, M06-E27.
**Durée indicative** : 3 h.

**Contexte technique**
- Récurseur : `rec_control trace-regex '<expression>' <fichier>` (sur `dns01`, en root) écrit la trace détaillée des résolutions des noms correspondants (`-` comme fichier : la sortie standard) ; sans argument, il arrête la trace. L'autoritaire local écoute sur 127.0.0.1:5300, joint en interne par l'interface `lo`.
- ACME : provisioner `acme` de `ca01`, annuaire `https://ca01.par1.medisphere.internal/acme/acme/directory`. Pour l'essai, le client ACME tourne **sur `dns02`**, pour le nom `dns02.par1.medisphere.internal`, en mode autonome (`step ca certificate … --provisioner acme --standalone`, qui écoute sur le port 80 de `dns02` le temps du défi) : la validation `http-01` va de `ca01` vers `dns02:80`, flux déjà ouvert pour les certificats de Kea (M06-E25, filtrage local de M06-E30). Pas sur `ca01` lui-même : depuis M06-E27, son port 80 est pris par l'écouteur HTTP de la CRL. step-ca journalise chaque requête (`journalctl -u step-ca` sur `ca01`).
- Validateur indépendant : `delv` (paquet `bind9-dnsutils`).

> ⚠️ **Attention** : le certificat et la clé produits par l'essai ACME sont des fichiers **jetables** : génère-les dans un dossier temporaire en mode 700 sur `dns02`, ne les installe nulle part (surtout pas à la place de `/etc/kea/tls/kea.crt`), et supprime-les à la fin. Vérifie avant de lancer que l'unité `cert-renewer@kea` n'est pas en train de tourner (elle utilise le même port 80). Arrête toute capture `tcpdump` et toute trace du récurseur (`rec_control trace-regex` sans argument) avant de terminer : une trace oubliée remplit un disque.

**Travail demandé**
1. **Résolution d'un nom interne.** Sur `dns01`, vide du cache le nom `nbx01.par1.medisphere.internal`, active la trace du récurseur pour ce nom et capture le trafic de l'autoritaire (`tcpdump -ni lo port 5300`). Depuis `adm01`, résous le nom deux fois. Relève : la requête relayée (drapeaux, EDNS, bit DO), les requêtes DNSKEY/DS supplémentaires dues à la validation, et ce qui change à la seconde résolution.
2. **Résolution d'un nom d'Internet.** Même démarche pour un nom jamais demandé (par exemple un sous-domaine aléatoire d'un domaine signé connu). Relève la descente racine → TLD → domaine, et la réponse négative (NSEC/NSEC3) qui prouve l'absence du nom. Valide la même réponse avec `delv`.
3. **Cache négatif.** Mesure, avec `dig` et le TTL affiché, combien de temps une réponse `NXDOMAIN` de ta zone interne restera en cache. D'où vient ce nombre (SOA de la zone, plafond du récurseur) ?
4. **ACME, côté protocole.** Avec `curl` seulement, interroge l'annuaire ACME de `ca01`, obtiens un *nonce* (`newNonce`), et explique pourquoi tu ne peux pas aller plus loin avec `curl` seul (JWS).
5. **ACME, de bout en bout.** Sur `dns02`, lance l'émission ACME pour `dns02.par1.medisphere.internal` en mode autonome, en suivant en parallèle le journal de step-ca (sur `ca01`) et une capture du port 80 sur `dns02` (interface `ens18`). Associe chaque ligne de journal à une étape de RFC 8555 (`newAccount`, `newOrder`, autorisation, défi `http-01`, `finalize`, téléchargement). Inspecte le certificat obtenu (`step certificate inspect`) : durée, SAN, émetteur, extensions. Supprime-le.
6. **Compte rendu.** Rédige `docs/socle/analyses/resolution-et-acme.md` : une section `## Résolution DNS` (schéma et extraits annotés), une section `## Émission ACME` (séquence annotée), puis `## Réponses aux questions`.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi le récurseur envoie-t-il ses questions à l'autoritaire local avec le bit RD à 0 pour une zone de `forward_zones`, et que changerait `forward_zones_recurse` ?
2. Pour la zone interne, le récurseur n'a pas de DS dans une zone parente : d'où tient-il sa confiance, et que se passerait-il si on retirait l'ancre en gardant `validation: validate` ?
3. Dans la trace d'un nom d'Internet, combien de requêtes ont été nécessaires à froid ? Et à chaud ? Qu'est-ce que l'*aggressive NSEC caching* (RFC 8198) économise ?
4. Pourquoi ACME impose-t-il un *nonce* à chaque requête, et que protège la signature JWS du compte ?
5. Dans `http-01`, qui contacte qui, sur quel port, et pourquoi le défi exige-t-il la résolution DNS du nom **par le serveur ACME** ? Quel défi choisirais-tu pour un service qui n'écoute pas en HTTP, et pour un nom générique (`*.par1…`) ?
6. Pourquoi des certificats de 30 jours rendent-ils la révocation moins critique ? Que fait step-ca pour la révocation des certificats ACME (CRL, OCSP, renouvellement bloqué) ?
7. Cite une panne de M06-E35 à M06-E42 que chacune de tes deux traces aurait permis de localiser en moins de 5 minutes, et la ligne décisive.

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, et contient les trois sections avec des extraits annotés de trace du récurseur, de capture sur le port 5300, de journal de step-ca (dont `newOrder`, `http-01` et `finalize`).
- [ ] Les 7 questions sont traitées.
- [ ] Aucune capture, trace ou client ACME autonome ne reste actif ; aucun fichier de clé d'essai n'est resté sur `dns02` ni dans le dépôt.

**Vérification** : `lab/bin/check 06 44`

<details><summary>Indice 1</summary>

`rec_control wipe-cache <nom>` vide un nom précis ; `dig +norecurse @10.10.20.10 <nom>` interroge le cache sans déclencher de résolution. Dans une capture `tcpdump -vv`, les drapeaux DNS s'affichent entre crochets et l'enregistrement OPT (EDNS) montre la taille annoncée et le bit DO.
</details>

<details><summary>Indice 2</summary>

`curl -s https://ca01.par1.medisphere.internal/acme/acme/directory | jq` donne les URL de chaque opération ; `curl -sI <newNonce>` renvoie l'en-tête `Replay-Nonce`. `step ca certificate --help` décrit les options `--provisioner`, `--standalone`, `--webroot` et `--http-listen`.
</details>

**Pour aller plus loin** : refais l'étape 5 avec le défi `tls-alpn-01` (si ta version de step CLI le propose en client) ou avec `certbot --server <annuaire>` et compare ce que voit step-ca ; mesure le temps de chaque étape.

---

### M06-E45 — Questions expert : DNS, DHCP, PKI  `Q` `★★★`

> **Ticket PLAT-782** — *De : Karim Benali*
> Dernière étape avant la recette du socle v1 : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la doc et les RFC, et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module (DNS, DNSSEC, DHCP, DDNS, PKI, ACME, certificats SSH, source de vérité).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M06-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Explique la différence entre un serveur faisant autorité et un récurseur, puis pourquoi les faire tourner dans le même processus (comme dnsmasq ou un BIND « tout-en-un ») est déconseillé. Cite deux risques concrets.
2. QCM — Un client interroge `dns01` pour `nbx01.par1.medisphere.internal` ; la réponse est `NXDOMAIN` avec, en section d'autorité, le SOA de `.` (la racine). La cause la plus probable :
   a) l'enregistrement de `nbx01` a été supprimé de la zone ; b) le récurseur ne relaie plus la zone interne et a demandé à la racine ; c) l'autoritaire est arrêté ; d) la validation DNSSEC a échoué.
3. Qu'est-ce que le cache négatif (RFC 2308) ? Comment sa durée est-elle calculée, et pourquoi un administrateur qui « vient de créer l'enregistrement » peut-il continuer à voir `NXDOMAIN` ?
4. Pourquoi l'incrément du numéro de série est-il indispensable à un secondaire ? Décris NOTIFY, SOA, IXFR et AXFR, et ce qui se passe si le série du primaire **diminue**.
5. TSIG (RFC 8945) : qu'est-ce qui est signé, avec quoi, et contre quoi cela protège-t-il (et ne protège-t-il pas) ? Pourquoi l'horloge compte-t-elle (`fudge`) ?
6. QCM — Une mise à jour RFC 2136 signée vers PowerDNS échoue. Quelle combinaison de réglages PowerDNS suffit à l'accepter ?
   a) `dnsupdate=yes` seul ; b) `dnsupdate=yes` et la métadonnée `TSIG-ALLOW-DNSUPDATE` de la zone pointant vers une clé connue de PowerDNS, avec la bonne source d'adresse ; c) la clé TSIG importée suffit, quels que soient les autres réglages ; d) `ALLOW-DNSUPDATE-FROM` seul.
7. DNSSEC : explique KSK, ZSK et CSK, le rôle du DS dans la zone parente et celui d'une ancre de confiance locale. Pourquoi un domaine en `.internal` ne peut-il pas obtenir de chaîne de confiance depuis la racine ?
8. Décris un roulement de KSK sans interruption (méthode « double signature » ou « pré-publication ») en tenant compte des TTL. Quelle étape a été bâclée dans la variante « roulement raté » de M06-E41 ?
9. NSEC contre NSEC3 : que révèle chacun (énumération de zone) ? Pourquoi NSEC3 avec des itérations élevées est-il aujourd'hui déconseillé (RFC 9276) ?
10. DHCP relayé : décris les quatre messages DORA avec un relais, le rôle de `giaddr`, et comment Kea choisit le sous-réseau. Pourquoi un `subnet-id` stable est-il obligatoire en Kea 3 ?
11. Kea en haute disponibilité : compare `hot-standby`, `load-balancing` et `passive-backup`. Que se passe-t-il pendant une coupure réseau entre les deux serveurs (*partner down*), et quel risque de double attribution existe-t-il ?
12. QCM — Depuis Kea 3.0, le fichier de baux `memfile` est déclaré avec un chemin dans `/tmp`. Que se passe-t-il ?
    a) Kea démarre et écrit dans `/tmp` ; b) Kea refuse la configuration (chemin hors du dossier de données autorisé) ; c) Kea ignore le chemin et utilise `/var/lib/kea` en silence ; d) Kea démarre sans persistance des baux.
13. DDNS : pourquoi Kea utilise-t-il un enregistrement DHCID (ou TXT) à côté du A ? Quel problème la résolution de conflits (`ddns-conflict-resolution-mode`) traite-t-elle ?
14. PKI : pourquoi une racine hors ligne et un intermédiaire en ligne ? Que contraint `pathlen` (*basic constraints*) et que se passe-t-il si l'intermédiaire est compromis ?
15. Pourquoi un serveur TLS doit-il présenter l'intermédiaire, et pourquoi certains navigateurs acceptent-ils quand même une chaîne incomplète ? En quoi est-ce un piège pour l'exploitation ?
16. ACME : compare `http-01`, `dns-01` et `tls-alpn-01` (port, prérequis réseau, noms génériques, risques). Lequel choisirais-tu pour `s3-01` (HTTPS sur 8333 seulement) et pourquoi ?
17. Durée de vie courte (30 jours, 16 h pour SSH) contre révocation : arguments pour et contre. Que deviennent CRL et OCSP dans un tel modèle ?
18. Certificats SSH : différences avec `known_hosts`/`authorized_keys` classiques ; rôle des principaux ; pourquoi `@cert-authority` et `TrustedUserCAKeys` ne doivent-ils pas contenir la même clé ?
19. QCM — Un certificat d'utilisateur SSH valide et signé par la bonne CA est refusé ; `sshd -T` montre `pubkeyacceptedalgorithms ssh-ed25519,rsa-sha2-512`. Pourquoi ?
    a) l'algorithme `ssh-ed25519` est obsolète ; b) l'algorithme de certificat `ssh-ed25519-cert-v01@openssh.com` n'est pas dans la liste, donc le certificat n'est pas même examiné ; c) la CA doit être RSA ; d) `TrustedUserCAKeys` est ignoré quand `PubkeyAcceptedAlgorithms` est défini.
20. Source de vérité : NetBox dit qu'une VM est `active` avec 10.10.20.40, Proxmox dit qu'elle n'existe pas, le DNS la résout. Qui a raison, que fais-tu, et quelle règle de l'ADR-0060 s'applique ? Comment éviter que ce cas se produise ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 9, ta trace de M06-E44 et les RFC 1034/1035, 2308, 1996 (NOTIFY), 1995 (IXFR), 4033-4035, 5155 (NSEC3), 8945 (TSIG) et 9276 contiennent l'essentiel.
</details>

<details><summary>Indice 2</summary>

Pour 10 à 13, le manuel de Kea 3.0 (chapitres *DHCPv4*, *High Availability*, *DDNS*) ; pour 14 à 19, RFC 5280, RFC 8555 et `man sshd_config` ; pour 20, ton ADR-0060.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible), à présenter à Karim.

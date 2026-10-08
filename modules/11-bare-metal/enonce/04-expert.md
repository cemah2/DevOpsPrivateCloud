# Module 11 — Palier 4 : Expert

La chaîne de provisioning est en production : Kea distribue adresses et chargeurs sur le VLAN 60, `pxe01` sert en HTTPS un iPXE qui ne fait confiance qu'à la PKI MédiSphère, les installateurs reçoivent leur fichier de réponse par iPXE, NetBox décide de ce qui s'installe, et MAAS a été évalué. Nadia Roussel rappelle ce que tout le monde oublie : « Une chaîne de démarrage réseau, quand elle casse, ne dit presque rien. Un serveur qui reste sur un écran noir, un curseur qui clignote, un installateur qui attend une réponse sur une console que personne ne regarde. » Karim Benali a préparé quatre pannes de celles qu'on rencontre vraiment le jour où arrive une palette : un serveur qui ne démarre pas sur le réseau, un iPXE qui s'arrête en chemin, une installation figée, un MAAS qui ne pilote plus ses machines. Puis tu suis un démarrage PXE paquet par paquet, et tu réponds aux questions qu'on pose en entretien sur ces protocoles.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au démarrage réseau :
- **Regarde la console.** Le micrologiciel, iPXE et les installateurs écrivent sur l'écran de la machine, pas dans un journal. Ouvre la console de la VM (interface web de Proxmox, *noVNC*) **avant** de la démarrer, et lis chaque ligne : le dernier message avant l'arrêt dit à quel étage on est (DHCP, TFTP, iPXE, HTTP, noyau, installateur).
- **Une étape, un témoin.** DHCP : les journaux de Kea et une capture ; TFTP : le journal de `tftpd-hpa` ; HTTP : le journal d'accès de nginx ; installateur : sa console secondaire (Alt-F4 pour d-i, Alt-F2 et `/tmp/*.log` pour Anaconda). Une étape qui ne laisse **aucune** trace chez son serveur n'a pas eu lieu.
- **Le code d'abord, la machine ensuite.** Les fichiers servis sont rendus depuis `plateforme/provisioning` et la configuration de Kea et de `pxe01` vient de `plateforme/ansible` : un écart entre ce que le code produirait et ce qui est servi **est** souvent la panne. La correction durable passe par le code.

> **Rappels** : tout se lance depuis `adm01`. Projets : `~/src/provisioning`, `~/src/ansible`, `~/src/infra`, documentation `~/medisphere` (variable `WB_DEPOT`). Machines de test : `bm01` (2112, SeaBIOS, Debian) et `bm03` (2114, OVMF, Rocky). **Avant chaque injection**, mets-les en position d'installation : statut `staged` et `pxe_action` à `installer` dans NetBox, rendu déployé sur `pxe01` (job `deployer`), VMs éteintes. Pour reproduire un symptôme, démarre la machine toi-même (bouton *Start* ou `qm start`), console ouverte, sans relancer ni le rendu ni l'orchestrateur de M11-E15 : ils réécrivent ce que sert `pxe01` et changeraient les conditions de l'observation. Le rendu et l'orchestrateur reviennent **après** le diagnostic, pour valider ta correction de bout en bout. Quand tu as fini, remets les équipements à `planned` (VMs vides recréées). Console : interface web de `pve01`, VM concernée, « Console ».

## Règles du jeu des pannes (M11-E19 à M11-E22)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 11 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix des paliers précédents), le script en essaie une autre.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 11 19`) : il doit être vert. Une panne posée sur une chaîne déjà malade fausse tout le diagnostic.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 11 19 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes agissent sur `pxe01`, sur la configuration de Kea (`dns01`, `dns02`), sur le relais DHCP des passerelles (`gw01`, `gw02` : seulement les lignes du VLAN 60), sur `maas01`, et, pour M11-E22, sur `pve01` **limité** au compte `wb-maas@pve`, à son rôle `WBMaas` et aux noms des VMs 2112-2115. Fichiers sauvegardés avant modification sous `/var/lib/workbook/` de l'hôte touché. Jamais sur l'iLO de `hp01`, jamais sur `pbs01`, jamais sur le réseau de `pve01`.

> ⚠️ **Relais DHCP et Kea** : une variante de M11-E19 touche le relais des passerelles ou la configuration de Kea, qui servent **aussi** le VLAN 99. Les modifications de la panne ne portent que sur le VLAN 60, mais une erreur de ta part en réparant peut couper le DHCP de tout le lab : vérifie `kea-dhcp4 -t` avant tout redémarrage de Kea, garde une session ouverte sur la passerelle, et contrôle le VLAN 99 après ta correction (`lab/bin/check 06 36` reste vert).

> ⚠️ **M11-E22 et `pve01`** : le diagnostic se fait en **lecture** sur `pve01` (`pveum user token list`, `pveum role list`, `pveum acl list`, `qm config`). La correction touche seulement le compte `wb-maas@pve`, son jeton, le rôle `WBMaas` et le nom d'une VM `bm*` : rien d'autre. Si tu dois régénérer le jeton, son secret va dans MAAS et dans le registre des secrets (emplacement, jamais la valeur).

- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/provisioning/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Les pannes de ce palier alimentent **RB-111** « Diagnostiquer un démarrage réseau » (`docs/socle/runbooks/RB-111-diagnostiquer-demarrage-reseau.md`), à écrire au fil des exercices : un étage par section (DHCP, TFTP, iPXE, HTTP, installateur, contrôle d'alimentation), le symptôme visible à la console, le témoin à consulter, les causes rencontrées.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

---

### M11-E19 — Panne : le serveur ne démarre pas sur le réseau  `BF` `★★`

> **Ticket INC-3841** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : il dit ce que montre la console du serveur, et ce qui fonctionne encore.)*

**Objectifs pédagogiques**
- Découper le démarrage PXE du micrologiciel en étapes observables : DHCPDISCOVER/OFFER (avec ou sans nom de fichier et serveur suivant), relais, TFTP, exécution d'iPXE.
- Lire les messages de la ROM PXE (SeaBIOS) et du micrologiciel UEFI (OVMF), et les relier à un étage.
- Vérifier la configuration **chargée** de Kea (classes, options, réservations) plutôt que le fichier seul.

**Prérequis** : M11-E02, E03, E06 ; `lab/bin/check 11 19` vert avant l'injection ; `bm01` et `bm03` en position d'installation (voir les rappels).
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : Kea (`isc-kea-dhcp4-server`, `/etc/kea/kea-dhcp4.conf`) sur `dns01` (primaire) et `dns02` (attente), sous-réseau `id: 60` ; relais du VLAN 60 sur les passerelles (dnsmasq, rôle `relais_dhcp`) ; TFTP de `pxe01` (`tftpd-hpa`, `/etc/default/tftpd-hpa`, journal dans `journalctl -u tftpd-hpa`, plus bavard avec l'option `--verbose`). Sur `pve01`, l'interface de la carte de `bm01` s'appelle `tap2112i0` : une capture y est **en lecture** et sans effet sur la VM.

**Injection** : `lab/bin/break 11 19` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme avec `bm01` **et** `bm03`, console ouverte. Note le dernier message de chacune. Le comportement est-il le même en BIOS et en UEFI ? Qu'en déduis-tu sur l'étage en cause ?
2. Trouve jusqu'où la séquence progresse : une capture sur `tap2112i0` (ou `tap2114i0`) pendant un démarrage, les journaux de Kea sur `dns01`, le journal de `tftpd-hpa`. Une étape qui n'apparaît chez aucun serveur n'a pas eu lieu.
3. Confirme la cause par une seconde mesure avant de toucher à quoi que ce soit (configuration chargée, droits, compteurs).
4. Corrige à la racine, à l'endroit d'où vient l'erreur (rôle Ansible, gabarit, variables), puis prouve le retour à la normale : `bm01` et `bm03` arrivent au moins jusqu'au menu ou au script iPXE.
5. Vérifie que le VLAN 99 n'a pas été touché par ta correction.

**Critères de réussite**
- [ ] `bm01` (BIOS) et `bm03` (UEFI) chargent iPXE par TFTP puis leur script en HTTPS.
- [ ] Kea sert le VLAN 60 avec le bon serveur suivant et les bonnes classes sur `dns01` et `dns02` ; le relais du VLAN 60 est actif ; `pxe01` sert les deux chargeurs en TFTP.
- [ ] Ton journal contient la capture (ou son extrait commenté) qui localise la panne, et RB-111 a une section « DHCP et TFTP ».

**Vérification** : `lab/bin/check 11 19`

<details><summary>Indice 1</summary>

Les messages des ROM PXE sont très normés. « No DHCP or proxyDHCP offers were received » (ou un simple délai sans adresse) : rien n'est revenu. « No boot filename received » : une offre est revenue, mais sans fichier. « TFTP open timeout » ou « PXE-E32 » : le fichier est désigné mais le serveur TFTP ne répond pas à l'adresse donnée. « File not found » ou « Access violation » : le serveur TFTP répond, mais refuse.
</details>

<details><summary>Indice 2</summary>

`tcpdump -ni tap2112i0 -vv port 67 or port 68 or port 69` montre, dans l'OFFER, l'adresse du serveur suivant (`siaddr`) et le nom du fichier (`file`). Sur `dns01`, les journaux de Kea disent quelles classes ont été attribuées au client (`EVAL_RESULT`, `CLASSIFY`) si la journalisation est au niveau `DEBUG` : tu peux l'augmenter à chaud le temps du diagnostic, puis la remettre.
</details>

**Pour aller plus loin** : ajoute à RB-111 un tableau « message de la ROM → étage → première commande à lancer », et une sonde TFTP qui lit les deux chargeurs depuis le VLAN 60 toutes les 5 minutes.

---

### M11-E20 — Panne : iPXE s'arrête en chemin  `BF` `★★★`

> **Ticket INC-3842** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : il dit ce que montre la console du serveur, et ce qui fonctionne encore.)*

**Objectifs pédagogiques**
- Diagnostiquer iPXE de l'intérieur : shell iPXE (Ctrl-B), `ifstat`, `route`, `imgfetch`, `imgstat`, `show`, codes d'erreur et leur décodage sur `ipxe.org/err`.
- Relier un code d'erreur iPXE à son étage : script (syntaxe, format), HTTP (statut, droits), TLS (chaîne, nom, date, racine de confiance).
- Comparer ce que sert `pxe01` avec ce que rendraient les gabarits de `plateforme/provisioning`.

**Prérequis** : M11-E03, E06, E13 ; `lab/bin/check 11 20` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : nginx sur `pxe01` (`nginx -T`, journaux `/var/log/nginx/access.log` et `error.log`) ; arborescence servie sous `/srv/http` ; certificat de `pxe01` délivré par `ca01` (rôle `certificats_acme`). Le code d'erreur iPXE (8 chiffres hexadécimaux) se décode sur `https://ipxe.org/err/<code>` ; la page dit souvent quel module d'iPXE l'a émis.

**Injection** : `lab/bin/break 11 20` (3 variantes).

**Travail demandé**
1. Reproduis le symptôme sur `bm01` (console ouverte). Relève le code d'erreur exact et décode-le.
2. Entre dans le shell iPXE (Ctrl-B au démarrage), obtiens une adresse (`dhcp`), puis rejoue l'étape qui échoue à la main avec `imgfetch` ; compare avec la même requête depuis `adm01` (`curl -v` vers la même URL, vérification TLS active).
3. Côté `pxe01` : la requête est-elle arrivée ? avec quel statut ? Qu'est-ce qui a changé dans ce qui est servi par rapport au code ?
4. Corrige à la racine et prouve : `bm01` et `bm03` exécutent leur script iPXE jusqu'au démarrage du noyau de l'installateur.
5. Ajoute à RB-111 une section « iPXE et HTTPS » : codes rencontrés, signification, première commande.

**Critères de réussite**
- [ ] Le script `boot.ipxe` et les scripts par MAC servis par `pxe01` sont des scripts iPXE valides, lisibles en HTTPS, identiques au rendu du code.
- [ ] Le certificat présenté par `pxe01` est émis par l'intermédiaire MédiSphère, valide et au bon nom.
- [ ] `bm01` et `bm03` atteignent le noyau de l'installateur.
- [ ] Ton journal contient le code d'erreur, son décodage et l'essai `imgfetch` qui a localisé la panne.

**Vérification** : `lab/bin/check 11 20`

<details><summary>Indice 1</summary>

iPXE distingue « je n'ai pas pu télécharger » (erreur de connexion, de TLS, statut HTTP) et « j'ai téléchargé, mais je ne sais pas quoi en faire » (format d'image). `imgstat` après un `imgfetch` réussi montre le **type** reconnu de chaque image.
</details>

<details><summary>Indice 2</summary>

Une erreur TLS dans iPXE ne dit pas « certificat refusé » en toutes lettres : le code renvoie vers le module de validation X.509. Depuis `adm01`, `openssl s_client -connect 10.10.60.10:443 -servername pxe01.par1.medisphere.internal -showcerts` montre qui a émis ce que présente `pxe01` ; un navigateur qui accepte peut avoir des racines que ton binaire iPXE n'a pas.
</details>

**Pour aller plus loin** : une validation dans le pipeline de `plateforme/provisioning` qui vérifie que chaque script rendu commence par l'en-tête iPXE et ne contient que des URL `https://` vers `pxe01`, et une sonde qui compare les empreintes servies et rendues.

---

### M11-E21 — Panne : l'installation reste bloquée  `BF` `★★`

> **Ticket INC-3843** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : il dit quelle machine, quel système, et où l'installation s'arrête.)*

**Objectifs pédagogiques**
- Diagnostiquer un installateur automatique arrêté : question non préremplie (d-i), source d'installation injoignable, disque introuvable (Anaconda).
- Utiliser les consoles et journaux des installateurs : consoles virtuelles, `/var/log/syslog` de d-i, `/tmp/anaconda.log`, `/tmp/program.log`, `/tmp/storage.log` d'Anaconda.
- Valider un fichier de réponse avant de le servir (`debconf-set-selections -c`, `ksvalidator`) et comprendre les limites de cette validation.

**Prérequis** : M11-E04, E05, E06, E13 ; `lab/bin/check 11 21` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `bm01` (Debian 13, preseed) et `bm03` (Rocky 10, kickstart) ; les fichiers de réponse sont rendus depuis `plateforme/provisioning` et servis par `pxe01` ; iPXE les remet aux installateurs (M11-E13). Sur la console d'une VM Proxmox, les combinaisons de touches (Alt-F2…) s'envoient par le menu du clavier virtuel de *noVNC*.

**Injection** : `lab/bin/break 11 21` (3 variantes).

**Travail demandé**
1. Reproduis : démarre la machine désignée par le ticket, console ouverte, et attends le blocage. Relève l'écran exact.
2. Passe sur une console secondaire de l'installateur et trouve, dans ses journaux, la question, l'erreur ou la ressource en cause.
3. Compare le fichier de réponse servi par `pxe01` avec le rendu du gabarit (et l'historique du projet) ; passe-le aux validateurs. Le validateur aurait-il vu le défaut ?
4. Corrige à la racine, puis relance une installation complète et vérifie qu'elle va jusqu'au bout sans intervention.
5. Ajoute à RB-111 une section « Installateurs » (consoles, journaux, causes rencontrées) et au pipeline le contrôle qui aurait arrêté ce défaut, s'il en existe un.

**Critères de réussite**
- [ ] Le preseed et le kickstart servis sont identiques au rendu du code, passent leurs validateurs, et contiennent ce qu'il faut pour une installation sans question (confirmation du partitionnement, source joignable, disque existant).
- [ ] La machine du ticket s'installe jusqu'au bout sans intervention.
- [ ] Ton journal cite la ligne du journal de l'installateur qui désigne la cause.

**Vérification** : `lab/bin/check 11 21`

<details><summary>Indice 1</summary>

d-i en `priority=critical` ne pose **que** les questions critiques auxquelles le preseed n'a pas répondu. La question affichée à l'écran a un nom debconf : il apparaît dans `/var/log/syslog` de l'installateur, et la console Alt-F4 le montre en direct.
</details>

<details><summary>Indice 2</summary>

Anaconda attend souvent sur un écran texte qui ressemble à une simple pause. Sur la console Alt-F2 : `grep -iE 'error|warn' /tmp/anaconda.log /tmp/storage.log /tmp/packaging.log`, et `lsblk` pour voir quels disques existent réellement sous quel nom.
</details>

**Pour aller plus loin** : faire tourner une installation complète de chaque gabarit dans le pipeline (VM jetable sur le VLAN 60, démarrée et observée par l'orchestrateur de M11-E15), en plus des validateurs syntaxiques.

---

### M11-E22 — Panne : MAAS ne pilote plus les machines  `BF` `★★★`

> **Ticket INC-3844** — *De : Claire Morel*
> *(Le détail du ticket s'affiche à l'injection : il dit quelles machines, et ce que montre MAAS.)*

**Objectifs pédagogiques**
- Diagnostiquer un pilote d'alimentation : ce que MAAS envoie, à qui, avec quelle identité, et ce que répond l'API de Proxmox.
- Lire les droits effectifs d'un jeton Proxmox (utilisateur, jeton, séparation des privilèges, rôle, ACL, expiration) et la confiance TLS d'un service empaqueté en snap.
- Reproduire hors de MAAS, avec la même identité, la requête qui échoue.

**Prérequis** : M11-E08, E09, E10 ; MAAS **démarré** sur `maas01` pour la durée de l'exercice (sans réactiver son DHCP : le VLAN 60 reste servi par Kea) ; `lab/bin/check 11 22` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : MAAS 3.7 (snap) sur `maas01` (10.10.60.11) ; journaux du snap : `journalctl -u snap.maas.pebble` et les fichiers de `/var/snap/maas/common/log/` (`regiond.log`, `rackd.log`) ; CLI `maas` (profil de ton compte administrateur). Proxmox : compte `wb-maas@pve`, jeton `wb-maas@pve!maas`, rôle `WBMaas` sur `/vms/2112` à `/vms/2115`. Côté Proxmox, `/var/log/pveproxy/access.log` sur `pve01` montre chaque requête d'API, son identité et son statut. Les paramètres d'alimentation d'une machine se lisent par `maas <profil> machine power-parameters <id-système>`. L'injection et le contrôle interrogent MAAS par son API avec la clé de ton compte administrateur : `~/.config/workbook/maas-api.key` (600, sortie de `sudo maas apikey --username <TON-COMPTE-MAAS>` sur `maas01` ; variable `WB_MAAS_APIKEY_FILE` de `lab/lab.env`), à l'adresse `WB_MAAS_URL` (défaut `http://10.10.60.11:5240/MAAS`).

**Injection** : `lab/bin/break 11 22` (4 variantes ; l'injection vérifie d'abord que MAAS interroge correctement l'alimentation des machines `bm*`).

**Travail demandé**
1. Reproduis : depuis la CLI de MAAS, demande l'état d'alimentation de chaque machine `bm*` (`query-power-state`) ; note lesquelles échouent et le message.
2. Trouve où la requête s'arrête : journaux de MAAS (rack), journal d'accès de `pveproxy` sur `pve01` (la requête est-elle arrivée ? avec quel statut ?).
3. Reproduis la requête **hors de MAAS** depuis `maas01`, avec la même URL et la même confiance TLS (le secret du jeton ne passe pas en argument de commande : lis-le depuis un fichier temporaire 600, supprimé ensuite, ou dans une variable d'environnement de ta session).
4. Corrige à la racine (côté Proxmox, côté MAAS ou sur `maas01`, selon la cause) sans élargir les droits du compte au-delà du nécessaire, puis prouve : toutes les machines `bm*` répondent à `query-power-state`, et un cycle arrêt/démarrage par MAAS fonctionne sur `bm02`.
5. Clos la panne, puis **arrête MAAS** (`maas01` revient à son état de fin de M11-E10). Ajoute à RB-111 une section « Contrôle d'alimentation ».

**Critères de réussite**
- [ ] Les quatre machines `bm*` de MAAS ont un état d'alimentation connu (`on` ou `off`), interrogé avec succès.
- [ ] Le jeton `wb-maas@pve!maas` est valide, son rôle `WBMaas` contient exactement les privilèges nécessaires, sur les seules VMs 2112-2115 ; les VMs `bm*` portent leur nom d'origine.
- [ ] `maas01` vérifie le certificat de `pve01` (pas de *verify SSL* désactivé).
- [ ] Ton journal contient la ligne du journal de `pveproxy` (ou l'erreur TLS) qui désigne la cause.

**Vérification** : `lab/bin/check 11 22` (avant d'arrêter MAAS).

<details><summary>Indice 1</summary>

Un statut `401` dans `access.log` de `pveproxy` : l'identité n'est pas acceptée (jeton inconnu, expiré, secret faux). Un `403` : l'identité est acceptée, mais les droits manquent sur le chemin demandé. Aucune ligne du tout : la requête n'est pas partie, ou elle est partie ailleurs, ou la poignée de main TLS a échoué avant.
</details>

<details><summary>Indice 2</summary>

`pveum user token list wb-maas@pve` montre l'expiration et la séparation des privilèges ; `pveum user token permissions wb-maas@pve maas` montre les droits **effectifs** du jeton. Côté MAAS, regarde comment chaque machine désigne sa VM (nom ou identifiant) : les deux ne réagissent pas de la même façon à un renommage.
</details>

<details><summary>Indice 3</summary>

Le snap MAAS embarque ses propres bibliothèques : quel magasin de certificats utilise-t-il pour *verify SSL* ? Compare avec ce que voit `curl` lancé sur le système de `maas01`.
</details>

**Pour aller plus loin** : une sonde qui interroge chaque jour l'alimentation de toutes les machines par l'outil de provisioning retenu (ADR-0110) et alerte à la première erreur, avant qu'un déploiement n'en ait besoin.

---

### M11-E23 — Sous le capot : un démarrage PXE paquet par paquet  `LAB` `★★★`

> **Ticket PLAT-1240** — *De : Karim Benali*
> Tu as réparé des démarrages réseau ; maintenant je veux que tu saches **exactement** ce qui passe sur le fil, du premier DISCOVER au premier octet du noyau, avec les numéros de RFC à l'appui. Une capture complète d'un démarrage BIOS et d'un démarrage UEFI, annotée, avec la réponse à mes questions. C'est le document que je donnerai à la prochaine recrue.

**Objectifs pédagogiques**
- Lire un démarrage PXE complet dans une capture : DHCP relayé (deux fois : ROM PXE puis iPXE), options 93, 77, 60, 66/67, `siaddr`, `giaddr`, TFTP (RRQ, OACK, `blksize`, `tsize`), DNS, TLS (SNI, version, suite), HTTP.
- Placer chaque échange dans son étage et dans la RFC qui le décrit (RFC 2131/2132, 4578, 3004, 1350/2347/2348/2349, 8446/5246, 9110).
- Mesurer le temps passé dans chaque étage.

**Prérequis** : M11-E13 (chaîne HTTPS) ; M06-E44 (lecture de capture).
**Durée indicative** : 3 h.

**Contexte technique**
- Points de capture : sur `pve01`, l'interface de la carte de la machine (`tap2112i0` pour `bm01`, `tap2114i0` pour `bm03`) voit **tout** ce qu'émet et reçoit la machine ; sur `dns01`, `ens18` voit le DHCP relayé ; sur la passerelle maître, `ens19.60` et `ens19.20` montrent le relais des deux côtés. Toute capture est en **lecture**, limitée par un filtre et une durée, et arrêtée à la fin.
- Wireshark (sur ton poste) ou `tshark` (sur `adm01`) décodent DHCP, TFTP et TLS ; le contenu HTTPS reste chiffré, et c'est normal.
- Les captures contiennent des adresses MAC et IP du lab, et aucun secret : vérifie-le avant de les déplacer ; elles ne vont **pas** dans un dépôt.

**Travail demandé**
1. Capture un démarrage complet de `bm01` (BIOS) jusqu'au téléchargement du noyau de l'installateur, simultanément sur `tap2112i0` et sur `ens18` de `dns01`. Recommence pour `bm03` (UEFI).
2. Dans le compte rendu `docs/provisioning/analyses/demarrage-pxe.md` (`plateforme/medisphere`), décris chaque échange dans l'ordre, avec : horodatage relatif, émetteur et destinataire, protocole, ce qu'il apporte, champs significatifs (options DHCP 53, 60, 77, 93, 54, 66/67 ou champs `siaddr`/`file`, `giaddr` ; TFTP RRQ et OACK avec leurs options ; SNI et version TLS ; requêtes HTTP vues dans le journal de nginx, puisqu'elles sont chiffrées sur le fil).
3. Réponds dans le compte rendu (section « Réponses aux questions ») :
   a. Pourquoi y a-t-il **deux** échanges DHCP complets ? Qu'est-ce qui change dans la seconde requête, et comment Kea le sait-il ?
   b. Que fait le relais au paquet (adresse source, `giaddr`, ports, diffusion ou envoi direct) ? Pourquoi la réponse revient-elle par la passerelle ?
   c. Quelles options TFTP iPXE ou la ROM négocient-elles, et quel est l'effet de `blksize` sur la durée du transfert ? Mesure-le.
   d. Quelle version de TLS et quelle suite iPXE négocient-ils avec `pxe01` ? Quel est le premier message où le nom `pxe01.par1.medisphere.internal` apparaît en clair sur le fil ?
   e. Dans quel étage la machine passe-t-elle le plus de temps ? Que proposerais-tu pour gagner 30 % ?
   f. Différences entre BIOS et UEFI sur le fil (option 93, nom du fichier, taille du chargeur, autre ?).
4. Arrête toutes les captures, supprime les fichiers de capture des hôtes du lab (garde-les sur ton poste si tu veux), et publie le compte rendu par MR.

**Critères de réussite**
- [ ] Le compte rendu est sur `main` avec une section par démarrage (BIOS, UEFI) et la section « Réponses aux questions ».
- [ ] Il cite les champs et options attendus (option 93, user-class iPXE, `giaddr`, RRQ, OACK, `blksize`, SNI, version de TLS) avec les valeurs observées.
- [ ] Aucune capture n'est en cours sur `pve01`, `dns01`, `pxe01` ni sur les passerelles ; aucun fichier de capture n'est dans un dépôt.

**Vérification** : `lab/bin/check 11 23`

<details><summary>Indice 1</summary>

`tcpdump -ni tap2112i0 -s 0 -w /root/bm01.pcap 'port 67 or port 68 or port 69 or port 53 or port 443 or (udp and portrange 1024-65535)'` attrape aussi les données TFTP (ports éphémères). Ajoute `-G` et `-W 1`, ou un `timeout`, pour qu'une capture oubliée s'arrête seule.
</details>

<details><summary>Indice 2</summary>

Dans Wireshark : filtre `dhcp.option.dhcp == 1` (DISCOVER), colonne « option 93 » (`dhcp.option.client_system_architecture`), `tftp.opcode == 6` (OACK), `tls.handshake.extensions_server_name`. *Statistiques → Conversations* pour les durées par étage.
</details>

**Pour aller plus loin** : refaire la mesure avec un `blksize` différent imposé côté serveur (`tftpd-hpa --blocksize`), et comparer le chargement d'un initrd en HTTP et en HTTPS par iPXE.

---

### M11-E24 — Questions expert : provisioning  `Q` `★★★`

> **Ticket PLAT-1241** — *De : Karim Benali*
> Dernière étape avant la livraison de l'usine : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, sans recherche pendant la première passe ; vérifie ensuite dans la doc et les RFC, et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes du provisioning bare-metal : PXE, DHCP, TFTP, iPXE, UEFI, installateurs, contrôleurs de gestion.
- S'entraîner à argumenter une réponse technique comme en entretien.

**Prérequis** : paliers 1 à 3 du module, M11-E23.
**Durée indicative** : 2 h.

**Questions**

1. Décris la séquence PXE complète d'un micrologiciel UEFI, de la mise sous tension à l'exécution du noyau, en nommant chaque protocole et ce qui le déclenche.
2. QCM — Un client PXE BIOS reçoit une offre avec l'option 67 mais `siaddr` à 0.0.0.0 et sans option 66. Que se passe-t-il le plus probablement ?
   a) il télécharge le fichier depuis le serveur DHCP ; b) il télécharge depuis l'adresse du relais ; c) il échoue faute de serveur TFTP désigné, ou essaie le serveur DHCP selon la ROM ; d) il démarre en HTTP.
3. Pourquoi charger iPXE par TFTP puis tout le reste en HTTP(S), plutôt que tout en TFTP ? Donne trois raisons chiffrables.
4. Qu'est-ce que le *chainloading* d'iPXE, et pourquoi faut-il une classe (option 77) pour éviter une boucle ? Quelle autre méthode évite la boucle sans classe ?
5. UEFI HTTP Boot (sans TFTP) : comment le client annonce-t-il qu'il le veut (option 60, option 93), qu'attend-il dans l'offre, et pourquoi ne l'as-tu pas utilisé ici ?
6. QCM — `undionly.kpxe` contre `ipxe.pxe` : quelle affirmation est juste ?
   a) `undionly.kpxe` contient des pilotes pour toutes les cartes ; b) `undionly.kpxe` utilise le pilote UNDI de la ROM PXE de la carte, `ipxe.pxe` embarque ses propres pilotes ; c) les deux sont identiques ; d) `undionly.kpxe` ne fonctionne qu'en UEFI.
7. Secure Boot : quelle chaîne de signatures un serveur doit-il vérifier pour exécuter un iPXE, puis un noyau Linux ? Que change le shim, et qu'apporte iPXE 2.0 de ce point de vue ?
8. Pourquoi un preseed déposé à la racine de l'initrd est-il pris en compte plus tôt qu'un preseed téléchargé par `url=` ? Quelles questions ne peuvent être préremplies que de cette façon (ou par la ligne de commande du noyau) ?
9. Anaconda : différence entre `inst.repo`, `inst.stage2` et la commande `url` du kickstart. Que se passe-t-il si `inst.repo` pointe vers un miroir d'une autre version mineure que le noyau chargé ?
10. QCM — Kickstart : `ignoredisk --only-use=sdb` sur une machine qui n'a qu'un disque `sda`. Résultat ?
    a) Anaconda installe sur `sda` ; b) l'installation s'arrête sur une erreur de stockage (aucun disque utilisable, ou disque introuvable) ; c) Anaconda crée `sdb` ; d) l'installation réussit sans partitionner.
11. IPMI 2.0 : qu'est-ce que la faiblesse de l'échange RAKP et pourquoi un mot de passe IPMI doit-il être considéré comme exposé à quiconque joint le port UDP 623 ? Que change Redfish ?
12. Redfish : expliquez `@odata.id`, la navigation par liens, les `Actions` et `AllowableValues`, et pourquoi on lit `AllowableValues` avant un `ComputerSystem.Reset`.
13. Le pilote Proxmox de MAAS : que doit-il pouvoir faire sur l'API de Proxmox, et que se passe-t-il si un jeton a la séparation des privilèges activée sans ACL propre ?
14. Comment un outil comme MAAS découvre-t-il le matériel d'une machine inconnue (*enlistment*, *commissioning*) ? Que perd-on à ne pas avoir cette étape dans la chaîne maison, et comment la remplacerais-tu ?
15. Un serveur doit être effacé avant de quitter le datacenter (fin de vie, RMA). Quelles méthodes existent (écrasement, effacement sécurisé ATA/NVMe, effacement cryptographique), et comment l'intégrer à la chaîne ?

**Critères de réussite**
- [ ] Les 15 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 6 : ton compte rendu de M11-E23, les RFC 2131/2132, 4578, 3004 et la [documentation d'iPXE](https://ipxe.org/docs) (chainloading, UNDI). Pour 7 : les notes de version d'iPXE 2.0 sur [ipxe.org](https://ipxe.org/) et la documentation du shim.
</details>

<details><summary>Indice 2</summary>

Pour 8 à 10 : le [manuel d'installation de Debian](https://www.debian.org/releases/trixie/amd64/apb.fr.html) (annexe B) et la [documentation d'Anaconda](https://anaconda-installer.readthedocs.io/en/latest/boot-options.html). Pour 11 à 15 : les spécifications du DMTF (Redfish), la documentation des pilotes d'alimentation de MAAS, la documentation de `nvme-cli` et de `hdparm`.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible), à présenter à Karim.

# Module 07 — Palier 2 : Opérationnel

Le palier 1 t'a fait manipuler chaque brique à part, sur la maquette : un agrégat entre deux espaces de noms, un pont Open vSwitch, des routes statiques puis OSPF et BGP entre deux routeurs FRR, une adresse virtuelle VRRP partagée par `srv01` et `srv02`. Rien de tout cela ne sert encore MédiSphère. Ce palier fait passer ces briques en service : un répartiteur HAProxy d'abord sur la maquette, puis la paire **`lb01`/`lb02`** qui publie GitLab et NetBox dans le socle ; une fabric *leaf-spine* en BGP *unnumbered* ; les *jumbo frames* sur les réseaux de stockage, avant l'arrivée de Ceph ; FRR sur la bordure, prêt pour le BGP de Kubernetes ; l'agence de Lyon raccordée par WireGuard, puis par BGP. Tu termines par la méthode de diagnostic que l'astreinte appliquera, deux revues de configuration et le runbook de maintenance des répartiteurs.

> **Rappels du module** (introduction) : toute nouvelle VM passe par OpenTofu (état `socle` pour les hôtes permanents, état `m07-maquette` pour la maquette), toute configuration par un rôle Ansible testé et appliqué par le pipeline de `plateforme/ansible`, tout nouveau flux par une ligne de `host_vars/gw01/pare_feu.yml`. Les vérifications se lancent depuis `adm01`. La maquette (2070-2079, étiquette `env-m07`) est jetable : on peut y explorer à la main, à condition de reporter ensuite dans le code ce qui doit durer.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| `hap01` (E10, E11) | VMID 2079, maquette, 1 vCPU, 1 Go, une carte (`eth0` sur `vsandbox`, DHCP Kea, nom `hap01.par1.medisphere.internal` publié par DDNS), étiquette de fonction `m07-hap` ; HAProxy 3.2 (haproxy.debian.net, suite `trixie-backports-3.2`) |
| Serveurs web de test | `srv01` (2075, 10.10.99.252), `srv02` (2076, 10.10.99.253) : Nginx 1.26, rôle `nginx_web` de M07-E08 ; page qui affiche le nom du serveur, en-tête `X-Serveur`, point de santé `/sante` (200 « ok ») ; noms `srv01.par1.medisphere.internal`, `srv02…` (A créés par OpenTofu en E03) |
| Répartiteurs (E12, E13) | `lb01` 1010 10.10.70.10, `lb02` 1011 10.10.70.11, VLAN 70 (`vdmz`, interface `eth0`), 1 vCPU, 1 Go, 10 Go ; étiquettes `socle`, `role-lb` ; VIP 10.10.70.200 `lb.par1.medisphere.internal`, VRRP v3 unicast, VRID 170 ; groupe d'inventaire `role_lb` |
| Noms publiés (E13) | `gitlab.par1.medisphere.internal`, `netbox.par1.medisphere.internal` → 10.10.70.200 |
| Fabric (E14) | AS 65100 (`spine01`, `spine02`), 65101 (`leaf01`), 65102 (`leaf02`) ; boucles 10.10.255.1, .2, .11, .12 (équipements), .21, .22 (`srv01`, `srv02`) ; liens serveurs en /31 : `leaf01`–`srv01` 10.10.250.8/31 (`leaf01` .8), `leaf02`–`srv02` 10.10.250.10/31 (`leaf02` .10) |
| Interfaces de la maquette | `eth0` sur `vsandbox` pour toutes (administration) ; spines : `eth1`, `eth2` vers `leaf01`, `leaf02` ; leaves : `eth1` vers `spine01`, `eth2` vers `spine02`, `eth3` vers leur serveur, `eth4` sur `vfab7` ; serveurs : `eth1` vers leur leaf ; `lyo-gw01` et `lyo-pc01` : `eth1` sur `vfab8` (introduction du module, M07-E03) |
| Stockage (E15) | MTU 9000 sur les VLAN 30, 31, 51 seulement ; cartes ajoutées à `srv01` et `srv02` (`eth2` sur `vstopub`, `eth3` sur `vstoclu`) : `srv01` 10.10.30.250 et 10.10.31.250, `srv02` 10.10.30.251 et 10.10.31.251 (plage « tests » .250-.254) |
| Bordure (E16) | FRR 10.7 sur `gw01`, AS 65000, router-id 10.10.10.2 ; session de test avec `leaf01` (10.10.99.251) sur le VLAN 99 ; groupe `K8S` (AS 65040, écoute sur 10.10.40.0/24, fermé jusqu'au module 15) |
| Site LYO1 (E18, E19) | `lyo-gw01` (2077) : `eth0` 10.10.99.250 sur `vsandbox` (son « Internet »), `eth1` 10.30.10.1/24 sur `vfab8` ; `lyo-pc01` (2078) : `eth0` administration (DHCP), `eth1` 10.30.10.10/24 ; tunnel `wg2` UDP 51822 des deux côtés, `gw01` 10.255.2.1/24, `lyo-gw01` 10.255.2.2 ; AS 65030 ; réseaux de PAR1 ouverts à l'agence : 10.10.20.0/24 et 10.10.70.0/24 |
| Inventaires Ansible | socle : `inventories/lab/netbox.yml` (inventaire par défaut, M06-E12) ; maquette : `inventories/lab/proxmox.yml` (groupes `env_m07`, `m07_fabric`, `m07_leaf`, `m07_web`, `m07_lyo`, `m07_hap`…, M07-E03) ; les deux ensemble pour ce qui traverse (E18, E19) ; variables dans `inventories/lab/group_vars` et `host_vars` |
| Rôles réutilisés du palier 1 | `frr` (M07-E06/E07 : configuration décrite en variables, validée par `vtysh --dryrun`), `keepalived` et `nginx_web` (M07-E08) : ce palier change surtout leurs **données** |
| Molecule | instances 2046 (scénario `haproxy`) et 2049 (scénario `frr_bordure`) de la plage du projet (2045-2049) |
| Documentation | ADR-0071 (E12), RB-070 (E22), RB-072 (E20), fiche CHG-825 (E15) dans `plateforme/medisphere` |

Ordre conseillé : **E10 → E11 → E12 → E13** (les répartiteurs) ; **E14 → E16** (FRR) ; **E15** quand tu disposes d'une fenêtre calme (il touche `pve01` et `gw01`) ; **E17** à tout moment ; **E18 → E19** (Lyon) ; **E20** après avoir pratiqué ; **E21 à E23** en dernier. Durée indicative du palier : 22 à 28 heures.

---

### M07-E10 — Répartir un service HTTP avec HAProxy  `LAB` `★★`

> **Ticket PLAT-820** — *De : Karim Benali*
> Avant de mettre des répartiteurs dans le socle, je veux qu'on ait tous un HAProxy en main sur la maquette : comment il décide qu'un serveur est mort, comment il répartit, comment on retire un serveur pour maintenance sans couper personne, et ce qu'il écrit dans son journal. `hap01` devant `srv01` et `srv02`, configuration générée par un rôle, et tu me montres ce que voit le client quand on tue un Nginx.

**Objectifs pédagogiques**
- Écrire le rôle `haproxy` : dépôt vérifié, version LTS figée, configuration validée avant d'être posée, rechargement sans coupure.
- Comprendre les contrôles de santé actifs de niveau 7 et leurs temporisations (`inter`, `fall`, `rise`).
- Piloter HAProxy à chaud par sa socket d'administration (état, drain, maintenance).
- Lire un journal HTTP d'HAProxy (temps, codes de terminaison).

**Prérequis** : M07-E03 (maquette), M07-E08 (`srv01`, `srv02`, rôle `nginx_web`), M04-E24 (Molecule).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `hap01` n'existe pas encore : ajoute-le à la description de la maquette dans `envs/m07-maquette/` (VMID 2079, `eth0` sur `vsandbox` en DHCP, fonction `m07-hap`), comme les VMs de E03. Il apparaîtra dans l'inventaire Proxmox (groupe `m07_hap`).
- Dépôt : `https://haproxy.debian.net`, suite `trixie-backports-3.2`, composant `main`, clé publiée sur le site (`haproxy-archive-keyring.gpg`). Le paquet de Debian 13 est en 3.0 : vérifie que c'est bien la 3.2 qui s'installe.
- HAProxy joint les serveurs **par leur nom** ; la maquette se reconstruit souvent (`tofu destroy`/`apply`) : HAProxy doit suivre un changement d'adresse sans redémarrer.
- Le rôle `nginx_web` de E08 sert déjà une page nominative (en-tête `X-Serveur`) et un point de santé `/sante` : rien à y changer.

**Travail demandé**
1. Relève l'empreinte de la clé du dépôt (télécharge-la, `gpg --show-keys --with-fingerprint`) et compare-la à une seconde source. Note-la dans `group_vars/all/depots.yml` de l'inventaire de la maquette.
2. Écris le rôle `haproxy` : dépôt vérifié par l'empreinte de sa clé, branche 3.2 figée, `global` et `defaults` communs dans le modèle, sections propres à l'hôte en variable (une liste de sections et de lignes), configuration validée par `haproxy -c` **avant** d'être posée, rechargement (pas redémarrage) sur changement, contrôle final par la socket d'administration (version chargée). Journal vers la sortie standard (le journal de systemd), sans dépendre de rsyslog.
3. Écris le scénario Molecule `haproxy` (instance 2046) : un Nginx local comme serveur, un contrôle de santé qui le voit `UP`, et la preuve que `haproxy -c` refuse une directive inconnue.
4. Configure `hap01` (`host_vars/hap01/haproxy.yml`) : un frontend sur le port 80, un backend `be_web` (`srv01`, `srv02`) en *round-robin* avec un contrôle `GET /sante` toutes les 2 s (hors service après 3 échecs, de retour après 2 succès), une page de statistiques sur la seule boucle locale (port 8404). Applique par un playbook de la maquette (`-i inventories/lab/proxmox.yml`, groupe `m07_hap`).
5. Observe la répartition :
   ```
   admin@adm01:~$ for i in $(seq 6); do curl -s -o /dev/null -D - http://hap01.par1.medisphere.internal/ | grep -i x-serveur; done
   admin@hap01:~$ echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock | cut -d, -f1,2,18,19,37 | column -ts,
   ```
6. Panne : arrête Nginx sur `srv01` et relance la boucle de requêtes **pendant** l'arrêt. Combien de requêtes échouent, et pendant combien de temps ? Retrouve la transition dans `journalctl -u haproxy`. Relance Nginx : au bout de combien de temps `srv01` revient-il ?
7. Maintenance sans coupure : mets `srv02` en *drain* par la socket (`set server be_web/srv02 state drain`), observe (`show servers state`, `show stat`), puis remets-le en service (`state ready`). Recommence avec `state maint`. Quelle différence entre les deux pour un client déjà connecté, pour un nouveau client, et pour les contrôles de santé ?
8. Lis une ligne de journal : repère les cinq temps (`Tq/Tw/Tc/Tr/Ta` ou leurs équivalents), le code de terminaison (`----`, `sC--`, `SH--`…) et explique ce que signifierait `SC--`.

**Critères de réussite**
- [ ] `hap01` (2079) existe, étiqueté `env-m07`, déclaré dans l'état `m07-maquette`.
- [ ] HAProxy 3.2 du dépôt haproxy.debian.net tourne sur `hap01` ; sa configuration passe `haproxy -c`.
- [ ] Six requêtes successives sur `http://hap01.par1.medisphere.internal/` reçoivent des réponses des deux serveurs.
- [ ] Les deux serveurs sont `UP` par un contrôle HTTP sur `/sante` ; la page de statistiques n'écoute que sur 127.0.0.1.
- [ ] `/sante` répond 200 sur `srv01` et `srv02`.
- [ ] Le scénario Molecule `haproxy` est sur `main` de `plateforme/ansible`.

**Vérification** : `lab/bin/check 07 10`

<details><summary>Indice 1</summary>

Une configuration générée ne doit jamais remplacer une configuration valide par une invalide : le module `template` a un paramètre `validate`, qui reçoit le chemin du fichier **temporaire** (`%s`). Le rechargement d'HAProxy (mode maître-processus de systemd) démarre de nouveaux processus et laisse les anciens finir leurs connexions.
</details>

<details><summary>Indice 2</summary>

Une adresse DHCP peut changer : un `server` écrit avec un nom n'est résolu qu'au démarrage, sauf si le serveur est rattaché à une section `resolvers` (et à un `init-addr` qui lui permet de démarrer même si le nom ne se résout pas encore). Regarde aussi ce que `http-check send` permet d'envoyer comme en-tête `Host`.
</details>

<details><summary>Indice 3</summary>

Dans la sortie CSV de `show stat`, le champ 18 est l'état (`UP`, `DOWN`, `MAINT`, `DRAIN`, `NOLB`) et le champ 37 le dernier résultat de contrôle (`L7OK`, `L4CON`, `L7STS`…). Le journal est au format `httplog` : la documentation (*Logging → HTTP log format*) détaille chaque champ et les codes de terminaison.
</details>

**Pour aller plus loin** (facultatif) : compare `balance roundrobin`, `leastconn` et `source` ; ajoute un cookie de persistance (`cookie SRV insert indirect nocache`) et observe avec `curl -c/-b`. Documentation : <https://docs.haproxy.org/3.2/configuration.html> (sections 4 et 5, *Health checks*), <https://docs.haproxy.org/3.2/management.html> (*Unix Socket commands*).

---

### M07-E11 — Nginx en reverse proxy : TLS et comparaison  `LAB` `★★`

> **Ticket DEV-821** — *De : Julien Petit*
> Toute mon équipe connaît Nginx, personne ne connaît HAProxy. Avant que vous ne nous imposiez HAProxy devant MédiAgenda, j'aimerais qu'on compare les deux sur le même service, en HTTPS, avec un vrai certificat : ce que voit l'application derrière, ce qui se passe quand un serveur tombe, comment on recharge un certificat. Si Nginx fait aussi bien, je préfère qu'on reste sur ce qu'on connaît.

**Objectifs pédagogiques**
- Obtenir un certificat ACME pour un service dont le port 80 est déjà tenu par un mandataire (défi HTTP-01 relayé).
- Terminer TLS dans HAProxy et dans Nginx avec le même certificat, et transmettre au serveur l'adresse du client et le protocole d'origine.
- Comparer les contrôles de santé actifs (HAProxy) et passifs (Nginx libre), et en tirer une recommandation argumentée.

**Prérequis** : M07-E10, M06-E18 (rôle `certificats_acme`), M06-E21 (flux ACME dans `pare_feu.yml`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Certificat ACME pour `hap01.par1.medisphere.internal` (step-ca, provisioner `acme`, défi HTTP-01) : `ca01` doit joindre le port 80 de `hap01`, dans le VLAN 99. Aujourd'hui, ce flux ne traverse pas `gw01`.
- Le port 80 de `hap01` est tenu par HAProxy : le serveur de défi temporaire de `step` ne peut pas l'occuper. `step ca certificate` sait écouter ailleurs (lis `step ca certificate --help`, options du mode autonome) ; HAProxy peut relayer `/.well-known/acme-challenge/` vers lui.
- Le rôle `certificats_acme` (M06-E18) appelle `step` sans cette option : étends-le d'un champ **facultatif** par certificat, sans rien changer pour les hôtes existants.
- HAProxy en TLS sur 443 ; Nginx en mandataire TLS sur 8443, **posé à la main** sur `hap01` (exploration sur une VM de maquette : Nginx n'est qu'un point de comparaison, il ne restera pas) ; même certificat, mêmes serveurs amont.

**Travail demandé**
1. Ouvre dans `pare_feu.yml` le flux minimal du défi (ca01 → VLAN 99, port 80) et applique-le par le pipeline.
2. Étends `certificats_acme` (champ facultatif d'écoute du serveur de défi) et ajoute à HAProxy le relais du défi. Résous le problème d'amorçage : un frontend TLS qui pointe vers un certificat absent empêche HAProxy de démarrer, et sans HAProxy pas de défi, donc pas de certificat. Écris ta solution dans le rôle `haproxy`, de façon générale.
3. Émet le certificat, ajoute le frontend TLS d'HAProxy (443, `alpn h2,http/1.1`, en-têtes `X-Forwarded-For` et `X-Forwarded-Proto`), puis installe Nginx sur `hap01` et écris à la main un site mandataire TLS sur 8443 (sans toucher au port 80, qui est à HAProxy). Vérifie les deux avec `curl --cacert` sur la racine MédiSphère (jamais `-k`).
4. Comparaison, sur les deux mandataires, avec un tableau de résultats :
   - ce que reçoit `srv01` (journal Nginx du serveur : adresse source, `X-Forwarded-For`) ;
   - arrêt de Nginx sur `srv01` : erreurs vues par un client qui envoie une requête par seconde, avant que chaque mandataire ne cesse d'envoyer vers `srv01` ;
   - retour de `srv01` : quand chaque mandataire le réutilise-t-il ?
   - renouvellement du certificat (`systemctl start cert-renewer@hap01`) : qui recharge quoi, des connexions sont-elles coupées ?
   - ce qu'on sait de l'état des serveurs sans lire les journaux.
5. Rédige la réponse à Julien (quinze lignes) : recommandation, et ce qui resterait à Nginx dans l'architecture.

**Critères de réussite**
- [ ] `https://hap01.par1.medisphere.internal/` (443, HAProxy) et `:8443` (Nginx) présentent un certificat émis par « MédiSphère Intermediate CA » pour `hap01.par1.medisphere.internal`, validé par la seule racine MédiSphère.
- [ ] Les deux mandataires répondent avec la page d'un serveur de test.
- [ ] Le renouvellement du certificat de `hap01` est planifié (`cert-renewer@hap01`).
- [ ] Le flux du défi est dans `pare_feu.yml`, ciblé (source `ca01`, port 80, sortie VLAN 99) et commenté.
- [ ] Ta réponse à Julien contient le tableau de comparaison et une recommandation.

**Vérification** : `lab/bin/check 07 11`

<details><summary>Indice 1</summary>

L'amorçage se résout en deux passages : un premier rendu de la configuration **sans** les sections TLS tant qu'aucun certificat n'existe, l'émission, puis un second rendu. Le rôle peut le décider seul en regardant le dossier des certificats avant de rendre le modèle.
</details>

<details><summary>Indice 2</summary>

Avec `crt <dossier>/`, HAProxy charge tous les certificats du dossier et choisit par SNI. Pour qu'il trouve la clé dans un fichier séparé de même nom (`hap01.crt` + `hap01.key`), regarde `ssl-load-extra-del-ext` dans la section `global`.
</details>

<details><summary>Indice 3</summary>

Dans Nginx libre, un serveur amont n'est écarté qu'après des échecs de **vraies** requêtes (`max_fails`, `fail_timeout`) ; `proxy_next_upstream` décide si la requête qui a échoué est rejouée sur un autre serveur. Compte les erreurs vues par le client avec et sans cette directive.
</details>

**Pour aller plus loin** (facultatif) : HAProxy 3.2 embarque un client ACME en aperçu technique (section `acme`) ; lis ce qu'il propose et pourquoi le workbook garde `step` pour l'instant. Documentation Nginx : <https://nginx.org/en/docs/http/ngx_http_upstream_module.html>.

---

### M07-E12 — Déployer les répartiteurs `lb01` et `lb02`  `LAB` `★★★`

> **Ticket PLAT-822** — *De : Claire Morel*
> La comparaison est faite, on part sur HAProxy. Je veux deux répartiteurs dans la DMZ, avec une adresse unique qui survit à la perte de l'un des deux : c'est par là que passeront GitLab et NetBox, puis tout ce que la plateforme exposera. Mêmes règles que pour `dns02` : OpenTofu, NetBox, Ansible, ACME, pas de geste à la main. Et écris la décision (ADR-0071), Sophie la relira.

**Objectifs pédagogiques**
- Ajouter deux hôtes au socle en suivant RB-060, avec une adresse de service (VIP) modélisée dans NetBox.
- Généraliser le rôle `keepalived` (VRRP v3 unicast, script de suivi non privilégié, préemption choisie).
- Obtenir un certificat pour un nom porté par une VIP, sur **chacun** des deux répartiteurs.
- Documenter une décision d'architecture (ADR).

**Prérequis** : M07-E11, M07-E08 (rôle `keepalived`), M06-E23 (RB-060), M06-E24 (`dns02`, même chemin).
**Durée indicative** : 4 h.

**Contexte technique**
- VMs : `lb01` (1010, 10.10.70.10), `lb02` (1011, 10.10.70.11), état `socle`, module `vm-debian` v2 (adresse imposée), VNet `vdmz`, 1 vCPU, 1 Go, 10 Go, étiquettes `socle` et `role-lb` (groupe d'inventaire `role_lb`).
- VIP : 10.10.70.200/24, `lb.par1.medisphere.internal`, rôle « VIP » dans NetBox, VRID **170** (le VRID 70 sera celui de la passerelle du VLAN 70 en E25). Priorités 150 (`lb01`) et 100 (`lb02`).
- Le premier passage de `site.yml` (rôles `base`, `ssh_durci`, certificat SSH d'hôte) a besoin que `runner01` joigne les répartiteurs en SSH ; ACME a besoin que les répartiteurs joignent `ca01` (443) et que `ca01` joigne leur port 80.
- Défi HTTP-01 pour `lb.par1.medisphere.internal` : `ca01` interroge **la VIP**, donc le répartiteur maître, qui n'est pas forcément celui qui demande le certificat.
- Ce palier ne publie encore aucun service : la VIP répond `200 ok` sur `/sante` et 503 ailleurs.

**Travail demandé**
1. Réserve dans NetBox (si ce n'est fait) 10.10.70.10, .11 et .200 ; puis déclare les deux VMs, leurs noms et la VIP (adresse de rôle « VIP » avec son nom) dans l'état `socle`. `plan` relu en MR, `apply` par le pipeline.
2. Ouvre les flux nécessaires dans `pare_feu.yml` (et seulement eux) ; dresse-en la liste dans la MR.
3. Réutilise le rôle `keepalived` de E08 : seules les **données** changent (`group_vars/role_lb/keepalived.yml`, valeurs propres à chaque hôte en `host_vars`). Une instance VRRP v3 unicast sur `eth0`, un script de suivi d'HAProxy ; calcule la liste des pairs plutôt que de l'écrire deux fois. Décide : préemption ou non ? Justifie dans l'ADR.
4. Configure HAProxy sur `role_lb` : redirection HTTP → HTTPS (sauf le défi ACME), frontend TLS, `/sante`, relais du défi ACME vers le répartiteur qui le demande. Décide si HAProxy écoute la seule VIP ou toutes les adresses ; écris ce que cela implique (et le paramètre noyau qui entre en jeu dans un des deux cas).
5. Certificat de la VIP sur chaque répartiteur (rôle `certificats_acme`), noms : celui de la VIP et celui de l'hôte. Écris un playbook `repartiteurs.yml` (un répartiteur à la fois) et branche-le dans `site.yml`.
6. Démontre la bascule : depuis `adm01`, une boucle `curl` sur `https://lb.par1.medisphere.internal/sante` ; arrête HAProxy sur le maître ; mesure l'interruption. Redémarre-le : la VIP revient-elle ? Puis arrête la VM maître (`qm shutdown`) et recommence.
7. Rédige l'ADR-0071 (contexte, décision, raisons du choix d'HAProxy — reprends ta comparaison de E11 —, conséquences, alternatives écartées).

**Critères de réussite**
- [ ] `lb01` et `lb02` existent (1010, 1011), étiquetés `socle` et `role-lb`, joignables, avec leurs noms dans le DNS.
- [ ] 10.10.70.200 est dans NetBox avec le rôle « VIP » et se résout depuis `lb.par1.medisphere.internal`.
- [ ] keepalived tourne sur les deux ; **un seul** porte la VIP.
- [ ] `https://lb.par1.medisphere.internal/sante` répond 200 avec un certificat de la PKI valable pour ce nom ; chaque répartiteur répond aussi en direct.
- [ ] HAProxy est en 3.2 ; arrêter HAProxy sur le maître fait passer la VIP sur l'autre.
- [ ] Les flux ajoutés sont dans `pare_feu.yml` ; l'ADR-0071 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 07 12`

<details><summary>Indice 1</summary>

Dans `vm-debian` v2, une adresse imposée crée l'adresse dans NetBox rattachée à l'interface de la VM. Une VIP n'appartient à aucune VM : c'est une ressource NetBox à part (une adresse avec un `role`), et son nom DNS peut réutiliser le module `enregistrement-dns`.
</details>

<details><summary>Indice 2</summary>

Une instance keepalived qui suit un script **sans poids** passe en état FAULT quand le script échoue, et rend la VIP. Avec un poids, elle ne fait que changer de priorité : vérifie alors que l'écart de priorité suffit à provoquer la bascule. `enable_script_security` refuse un script que quelqu'un d'autre que root pourrait modifier.
</details>

<details><summary>Indice 3</summary>

Pour le défi ACME, mets **les deux** répartiteurs dans le backend du défi : seul celui qui demande un certificat écoute sur le port du serveur de défi, l'autre refuse la connexion. Lis `retry-on` et `option redispatch` : HAProxy peut réessayer ailleurs quand la connexion est refusée.
</details>

**Pour aller plus loin** (facultatif) : mesure la bascule avec `advert_int 1` puis avec un intervalle plus court (VRRP v3 accepte des fractions de seconde). Lis la RFC 5798 (§6.4.2, *Master_Down_Interval*) et calcule le délai théorique. Documentation keepalived : <https://keepalived.readthedocs.io/en/latest/configuration_synopsis.html>.

---

### M07-E13 — Publier GitLab et NetBox derrière les répartiteurs  `LIBRE` `★★★`

> **Ticket PLAT-823** — *De : Claire Morel* — *Copie : Sophie Laurent*
> On publie les deux premiers services par la VIP : GitLab sous `gitlab.par1.medisphere.internal`, NetBox sous `netbox.par1.medisphere.internal`. Exigences de Sophie : TLS de bout en bout (on termine sur les répartiteurs, on re-chiffre vers les serveurs, et on vérifie leurs certificats), rien d'autre que HTTPS exposé, le SSH de GitLab reste en direct. Je veux aussi pouvoir ouvrir GitLab depuis le LAN de la maison, sans VPN, en passant par la passerelle. Et rien ne doit casser pour ceux qui utilisent encore les anciens noms.

**Objectifs pédagogiques**
- Concevoir une publication par nom (SNI et en-tête `Host`) avec re-chiffrement vérifié vers les serveurs.
- Adapter des applications à un mandataire (URL publiée, adresse réelle du client, contrôles de santé, hôtes autorisés).
- Exposer un service vers un réseau externe par une traduction d'adresse de destination maîtrisée.

**Prérequis** : M07-E12, M01 (configuration de GitLab), M06-E04 (rôle `netbox`), M06-E18 (certificats de `git01` et `nbx01`).
**Durée indicative** : 4 h à 5 h.

**Contexte technique**
- Serveurs : `git01` (10.10.20.12:443, certificat ACME `git01.par1.medisphere.internal`, `gitlab.rb` géré à la main), `nbx01` (10.10.20.13:443, certificat ACME `nbx01.par1.medisphere.internal`, rôle `netbox`, variable `netbox_allowed_hosts`).
- Les répartiteurs n'ont aujourd'hui aucun flux vers INFRA autre que `ca01`.
- `gw01` ne fait pas encore de traduction de destination : son rôle `pare_feu` ne génère qu'une chaîne `postrouting`. Adresse WAN : `<IP-GW01-WAN>` (la VIP WAN de E26 la remplacera).
- GitLab expose des points de santé (`/-/health`, `/-/readiness`, `/-/liveness`) réservés à une liste d'adresses.
- `runner01` est enregistré sur `https://git01.par1.medisphere.internal` ; les checks du workbook utilisent aussi ce nom.

**Travail demandé**
Livre, par MR sur les projets concernés, la publication des deux services. Contraintes :
- noms publiés dans le DNS par le code, pointant vers la VIP ; un certificat par nom publié sur chaque répartiteur ;
- routage par nom vers le bon serveur ; un nom inconnu n'obtient ni certificat trompeur ni service ;
- re-chiffrement vers chaque serveur avec vérification de sa chaîne **et** de son nom ; aucune vérification désactivée nulle part ;
- un contrôle de santé applicatif par serveur, qui passe au rouge si l'application (pas seulement le port) ne répond plus ;
- les applications produisent des liens et journalisent l'adresse du client correctement derrière le mandataire ; les URL de clone SSH de GitLab gardent le nom de `git01` ;
- les anciens noms (`git01…`, `nbx01…`) continuent de fonctionner en accès direct ;
- depuis le LAN maison, `https://<IP-GW01-WAN>` mène à la VIP (et à elle seule, sur ce seul port) ; la procédure côté poste est documentée ;
- seuls HTTP (redirection) et HTTPS répondent sur la VIP ;
- chaque flux nouveau est dans la matrice ; un retour arrière est écrit.

**Critères de réussite**
- [ ] `gitlab.par1.medisphere.internal` et `netbox.par1.medisphere.internal` se résolvent vers 10.10.70.200.
- [ ] Chacun présente un certificat de la PKI à son nom et sert son application (page de connexion), sans option de contournement TLS côté client.
- [ ] Les serveurs publiés sont `UP` sur les deux répartiteurs ; aucune ligne `verify none` dans leur configuration.
- [ ] Le port 22 de la VIP est fermé ; `git@git01.par1.medisphere.internal` fonctionne toujours.
- [ ] `gw01` traduit son port 443 WAN vers la VIP, pour le seul LAN maison.
- [ ] `https://git01.par1.medisphere.internal` et `https://nbx01.par1.medisphere.internal` répondent toujours.

**Vérification** : `lab/bin/check 07 13`

<details><summary>Indice 1</summary>

GitLab n'a qu'une URL externe : tout ce qu'il génère en dépend. Changer `external_url` change aussi l'endroit où omnibus cherche son certificat ; et un mandataire n'est « de confiance » pour l'adresse réelle du client que si on le déclare (côté nginx d'omnibus **et** côté Rails).
</details>

<details><summary>Indice 2</summary>

Côté HAProxy, trois éléments par serveur re-chiffré : la racine qui valide sa chaîne, le nom attendu dans son certificat, et le SNI envoyé (pour la requête **et** pour le contrôle de santé, qui a son propre paramètre). Pour le routage par nom, l'en-tête `Host` peut contenir un port : normalise-le avant de comparer.
</details>

<details><summary>Indice 3</summary>

Une traduction de destination se fait **avant** la décision de routage (`prerouting`) ; le filtrage qui suit voit déjà la nouvelle destination. Il te faut donc deux choses dans la matrice : la traduction et l'autorisation de transit vers la VIP.
</details>

**Pour aller plus loin** (facultatif) : publie aussi le registre de conteneurs de GitLab (module 13) ou l'interface de `ca01` : qu'est-ce qui change (SNI, chemins, taille des requêtes) ? Lis la documentation GitLab « Configure a reverse proxy » : <https://docs.gitlab.com/omnibus/settings/nginx/>.

---

### M07-E14 — Fabric leaf-spine : BGP unnumbered et ECMP  `LAB` `★★★`

> **Ticket PLAT-824** — *De : Karim Benali*
> Au module 15, les nœuds Kubernetes annonceront leurs adresses de services en BGP, et le jour où PAR1 aura de vrais commutateurs ce sera une fabric *leaf-spine*. Je veux qu'on ait monté la nôtre sur la maquette : deux spines, deux leaves, BGP sans adresse sur les liens, deux chemins égaux entre chaque paire de leaves, et la preuve que le trafic les utilise tous les deux. Et quand un lien tombe, je veux savoir en combien de temps la fabric s'en remet.

**Objectifs pédagogiques**
- Comprendre l'architecture de Clos (rôles, plan d'AS, pourquoi les spines partagent un AS).
- Configurer BGP *unnumbered* (sessions sur l'adresse IPv6 lien-local, routes IPv4 avec un next-hop IPv6).
- Obtenir et prouver l'ECMP (multichemin à coût égal) dans le noyau, et répartir les flux.
- Mesurer la convergence après la perte d'un lien.

**Prérequis** : M07-E06, M07-E07 (FRR sur la maquette, rôle `frr`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Plan d'AS (PLAN §4.9) : spines 65100 (les deux), `leaf01` 65101, `leaf02` 65102. Boucles et liens serveurs : voir les faits communs du palier. Le lien `vfab7` (`leaf01`–`leaf02`) n'est pas utilisé.
- `srv01` et `srv02` ne parlent pas BGP : leur boucle est jointe par une route statique sur leur leaf, et ils joignent les boucles de la fabric par leur leaf (FRR sans protocole de routage, `zebra` et `staticd` seulement, sur les serveurs).
- `bgp ebgp-requires-policy` reste actif (PLAN §4.9) : aucune route ne circule sans politique d'entrée et de sortie.
- Ce que la fabric s'échange : les boucles (/32 seulement), les adresses de services Kubernetes (10.10.41.0/24) et, à partir de E16, ce que la bordure lui annonce (10.10.20.0/24).

**Travail demandé**
1. Explique dans ton journal (dix lignes) : pourquoi les deux spines partagent-ils un AS, et que se passerait-il s'ils en avaient chacun un ? Pourquoi les leaves ne se parlent-elles pas ?
2. Le rôle `frr` de E06 décrit déjà la configuration en variables et sait désigner un voisin par son interface : fais évoluer les **données** (`group_vars/m07_fabric/frr.yml`, `host_vars/<routeur>/frr.yml`). Il servira tel quel à la bordure (E16) et à Lyon (E19).
3. Configure les spines et les leaves en BGP *unnumbered* (voisins désignés par `eth1`, `eth2`) : boucles annoncées, politiques d'entrée et de sortie, multichemin, adresses de services K8s (10.10.41.0/24) et préfixe de la bordure (10.10.20.0/24) autorisés dans la fabric. Les /31 des liens, posés par cloud-init, restent en place : montre que les sessions n'en dépendent plus. Les serveurs : boucle (FRR sans protocole de routage), route vers 10.10.255.0/24 par leur leaf ; leur boucle est annoncée par leur leaf.
4. Lis le profil `frr defaults datacenter` dans la documentation FRR : quelles valeurs change-t-il ? Le rôle reste en profil `traditional` : explique pourquoi c'est plus sûr pour la politique eBGP obligatoire, et reprends explicitement ce qui t'intéresse de l'autre profil (temporisateurs).
5. Prouve l'ECMP : `ip route show 10.10.255.12` sur `leaf01` (combien de *nexthops*, via quoi ?), `show bgp ipv4 unicast 10.10.255.12` (chemins « multipath »). Fais passer des flux de `srv01` (source 10.10.255.21) vers `srv02` (10.10.255.22) — plusieurs connexions TCP, ports différents — et montre avec les compteurs des interfaces des spines que les deux sont utilisés. Quel paramètre noyau change la répartition ?
6. Convergence : pendant un `ping -i 0.2` de `srv01` vers la boucle de `srv02`, coupe un lien côté leaf (`ip link set eth1 down`), puis remets-le. Recommence en coupant le lien **sans** que l'interface ne tombe (règle nftables qui jette tout sur ce lien). Compare les pertes et explique la différence.

**Critères de réussite**
- [ ] Chaque équipement de la fabric a deux sessions BGP établies, avec des voisins désignés par l'interface (`eth1`, `eth2`), et plus aucun voisin désigné par une adresse /31.
- [ ] La route de `leaf01` vers 10.10.255.12 a deux next-hops (un par spine) ; idem de `leaf02` vers 10.10.255.11.
- [ ] `srv01` joint `srv02` de boucle à boucle (`ping -I 10.10.255.21 10.10.255.22`).
- [ ] `bgp ebgp-requires-policy` est actif sur tous les équipements ; sur les leaves, la répartition des flux ECMP tient compte des ports (`fib_multipath_hash_policy`).
- [ ] Ton journal répond aux questions des étapes 1, 4 et 6 (mesures à l'appui).

**Vérification** : `lab/bin/check 07 14`

<details><summary>Indice 1</summary>

Un voisin s'écrit `neighbor <interface> interface …` (avec un AS ou un *peer-group*) : FRR découvre l'adresse lien-local du voisin par les annonces de routeur IPv6 qu'il émet lui-même, et négocie la capacité *extended next-hop*. Il faut donc que l'IPv6 soit actif sur l'interface (adresse `fe80::` présente). Dans le rôle de E06, un voisin a soit une clé `adresse`, soit une clé `interface`.
</details>

<details><summary>Indice 2</summary>

Deux chemins ne sont « égaux » pour BGP que si tous les critères jusqu'à la longueur de l'AS_PATH sont égaux et que `maximum-paths` le permet. `bgp bestpath as-path multipath-relax` assouplit une condition : laquelle, et en as-tu besoin avec ce plan d'AS ?
</details>

<details><summary>Indice 3</summary>

Une interface qui tombe est vue immédiatement par zebra ; un lien qui ne transmet plus sans tomber n'est détecté qu'à l'expiration du *hold timer* BGP (lis la valeur du profil datacenter). BFD (`bfdd`) existe pour ce cas.
</details>

**Pour aller plus loin** (facultatif) : active BFD sur les sessions de la fabric (`neighbor … bfd`, démon `bfdd`) et mesure de nouveau la coupure silencieuse. Lis la RFC 7938 (*BGP in large-scale data centers*). Documentation FRR : <https://docs.frrouting.org/en/latest/bgp.html> (*Unnumbered BGP*, *Multipath*).

---

### M07-E15 — Jumbo frames sur les réseaux de stockage  `LAB` `★★`

> **Ticket CHG-825** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Ceph arrive au prochain module : réplication et accès des clients sur les VLAN 30 et 31, et OpenStack fera passer son overlay sur le 51. Les deux veulent du MTU 9000. Je valide le changement à une condition : seuls ces trois VLAN changent, et rien ne doit bouger ailleurs, ni dans le lab ni sur le LAN de la maison. Fiche de changement avant, retour arrière testé, Nadia prévenue.

**Objectifs pédagogiques**
- Comprendre où le MTU se décide sur une chaîne pont Proxmox → VNet → carte virtuelle → invité → sous-interface VLAN d'un routeur.
- Changer le MTU d'un réseau en production, par une fiche de changement, avec retour arrière.
- Vérifier un MTU de bout en bout (`ping -M do`, PMTUD) et reconnaître un trou noir.

**Prérequis** : M00 (`vmbr1`, zone SDN `lab`, `gw01`), M02-E11 (`ms-snapshot`), M07-E03, M07-E14 (adresses des serveurs portées par FRR).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `vmbr1` (pont VLAN-aware sans port physique) porte tous les VLAN du lab ; les VNets de la zone SDN `lab` sont construites dessus. Une zone SDN a une option `mtu` (lis la documentation SDN de Proxmox VE 9 : options communes des zones).
- Une carte virtio Proxmox a une option `mtu=` (valeur, ou `1` pour reprendre le MTU du pont). Sans elle, l'invité reste à 1500.
- `gw01` : `ens19` (trunk) et ses sous-interfaces `ens19.<VLAN>`, déclarées dans `/etc/network/interfaces` ; `gw01` est hors d'OpenTofu (ADR-0051). Les VLAN 31 et 51 ne sont pas routés.
- VMs de test : ajoute à `srv01` et `srv02`, **à la fin** de leurs cartes dans `envs/m07-maquette/` (pour ne pas renuméroter `eth1`), une carte sur `vstopub` (VLAN 30, `eth2`) et une sur `vstoclu` (VLAN 31, `eth3`), adresses dans les faits du palier. La description de la maquette ne sait pas encore donner un MTU à une carte : ajoute-le.
- Aucune VM du socle n'est aujourd'hui dans les VLAN 30, 31 ou 51.

> ⚠️ **Attention** : cet exercice modifie le réseau de `pve01` (`vmbr1`), la zone SDN qui porte **tout** le lab, et la carte trunk de `gw01`. Une erreur coupe le lab entier, VPN compris. Avant de commencer : instantané de `gw01` (`ms-snapshot --prefix avant-chg825 1000`), console de secours vérifiée (`qm terminal 1000`), copie de `/etc/network/interfaces` de `pve01` et de `gw01`, configuration de la zone relevée (`pvesh get /cluster/sdn/zones/lab`). Ne touche **jamais** à `vmbr0`. Retour arrière, dans l'ordre inverse : carte de `gw01` à 1500 et fichier d'origine ; option `mtu` retirée de la zone puis SDN appliqué ; copie du fichier de `pve01` et `ifreload -a`.

**Travail demandé**
1. Rédige la fiche CHG-825 (`docs/socle/changements/`) **avant** d'agir : objet, principe, pré-requis, étapes ordonnées avec contrôle et retour arrière de chacune, vérification, communication. Fais-la relire (MR).
2. Mesure l'état de départ : MTU de `vmbr1`, des ponts des VNets (`/sys/class/net/<vnet>/mtu`), des interfaces de `gw01` ; `ping -M do -s 1472` et `-s 1473` entre deux VMs d'un même VLAN : que se passe-t-il pour le second, et où l'erreur est-elle signalée ?
3. Déroule la fiche : `vmbr1`, zone `lab`, puis `gw01`. Avant de changer la carte de `gw01`, réponds : que deviennent les sous-interfaces si seul `ens19` passe à 9000 ? Selon la configuration *hotplug* de la VM, le changement de carte est-il appliqué à chaud ou en attente (`qm pending 1000`) ? Choisis ton moment en conséquence.
4. Ajoute les cartes de stockage de `srv01` et `srv02` (OpenTofu, MTU 9000, adresses posées par cloud-init comme les autres). Une carte ajoutée à une VM existante n'est configurée par cloud-init qu'au prochain démarrage (et peut régénérer ses clés d'hôte SSH) : reconstruis plutôt les deux serveurs (`tofu apply -replace`), puis rejoue les playbooks de E08 et E14. Vérifie le MTU dans l'invité.
5. Vérifie de bout en bout : `ping -M do -s 8972` de `srv01` vers `srv02` sur le VLAN 31, et vers 10.10.30.1. Puis, depuis `srv01`, pose temporairement une route vers 10.10.20.0/24 par 10.10.30.1 et envoie `ping -M do -s 8972 10.10.20.10` : quelle réponse, de qui ? Retire la route.
6. Vérifie que rien n'a bougé ailleurs : MTU de `adm01`, `dns01`, des sous-interfaces des autres VLAN de `gw01`, de `vmbr0`.
7. Réponds dans ton journal : dans quel cas un MTU différent ne produit-il **aucun** message d'erreur ? Que fait un client TCP de son MSS, et pourquoi l'overlay Geneve d'OpenStack (M10) a-t-il besoin de plus de 1500 sur le VLAN 51 ?

**Critères de réussite**
- [ ] `vmbr1` et la zone SDN `lab` sont à 9000 ; `vmbr0` est inchangé.
- [ ] Sur `gw01`, `ens19` et `ens19.30` sont à 9000, toutes les autres sous-interfaces à 1500.
- [ ] `srv01` et `srv02` ont une interface à 9000 dans les VLAN 30 et 31 ; `ping -M do -s 8972` passe entre eux (VLAN 31) et vers 10.10.30.1.
- [ ] `adm01` et `dns01` restent à 1500.
- [ ] La fiche CHG-825 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 07 15`

<details><summary>Indice 1</summary>

8972 + 8 (en-tête ICMP) + 20 (en-tête IPv4) = 9000. `ping -M do` interdit la fragmentation : si l'interface de sortie locale est plus petite, l'erreur est locale (« message too long ») ; si c'est un routeur plus loin, il renvoie un ICMP *fragmentation needed* avec son MTU.
</details>

<details><summary>Indice 2</summary>

Une sous-interface VLAN prend le MTU de son parent à sa création, et ne peut pas le dépasser. Écrire explicitement `mtu 1500` sur chaque sous-interface qui doit le rester rend l'intention visible et protège d'un redémarrage dans un ordre différent.
</details>

<details><summary>Indice 3</summary>

L'API Proxmox applique une zone SDN modifiée seulement après `pvesh set /cluster/sdn` (le bouton « Apply » de l'interface). Le MTU d'un pont est le **plafond** de ce qui le traverse ; ce sont les extrémités qui choisissent.
</details>

**Pour aller plus loin** (facultatif) : lis la RFC 4821 (*Packetization Layer Path MTU Discovery*) et regarde la valeur de `net.ipv4.tcp_mtu_probing` : quand l'activerais-tu ? Documentation SDN : <https://pve.proxmox.com/pve-docs/chapter-pvesdn.html>.

---

### M07-E16 — FRR sur la bordure : préparer le BGP de la plateforme  `LAB` `★★★`

> **Ticket PLAT-826** — *De : Karim Benali*
> Au module 15, les nœuds Kubernetes viendront annoncer 10.10.41.0/24 à la bordure, et la fabric de la maquette a déjà des choses à dire. Je veux FRR sur `gw01` dès maintenant, avec des politiques qui n'acceptent **que** ce qu'on attend, une session de test avec `leaf01`, et le groupe Kubernetes prêt mais fermé. C'est la passerelle de tout le lab : rien ne doit pouvoir y injecter une route vers MGMT ou une route par défaut.

**Objectifs pédagogiques**
- Configurer un routeur de bordure BGP avec des politiques d'entrée et de sortie strictes (listes de préfixes, route-maps).
- Préparer des voisins dynamiques (`bgp listen range`) sans les ouvrir.
- Ajouter un protocole de routage à un routeur de production sans risque (validation, contrôle des routes apprises, retour arrière).

**Prérequis** : M07-E14 (rôle `frr` v2, fabric), M04-E17 (rôle `pare_feu`).
**Durée indicative** : 3 h.

**Contexte technique**
- Bordure : AS 65000 ; router-id 10.10.10.2 (identifiant stable : `gw01` passera de .1 à .2 en E25, `gw02` prendra 10.10.10.3) ; configuration commune à `role_routeur` (`gw02` en héritera), router-id en `host_vars`.
- Session de test : `leaf01` (AS 65101) en 10.10.99.251 (`eth0`, adresse fixe de E03) sur le VLAN 99 ↔ `gw01` 10.10.99.1.
- Rôle `frr` de E06 : ce que son schéma de variables ne décrit pas (écoute passive d'un groupe, groupe fermé, adresse source d'une session, plafond de préfixes) s'écrit dans `frr_config_supplementaire`.
- À accepter de la fabric : 10.10.255.0/24 (des /32) et 10.10.41.0/24 ; à lui annoncer : 10.10.20.0/24. Groupe `K8S` : AS 65040, écoute passive sur 10.10.40.0/24, n'accepte que 10.10.41.0/24, n'annonce rien, fermé tant que M15 n'existe pas.
- Pare-feu de `gw01` : politique `drop` en entrée ; BGP = TCP 179.

> ⚠️ **Attention** : FRR sur `gw01` peut installer des routes dans la table du routeur de tout le lab. Avant d'appliquer : instantané (`ms-snapshot --prefix avant-m07e16 1000`), session ouverte sur `gw01` et console vérifiée (`qm terminal 1000`), table de routage relevée (`ip route > /root/routes.avant-m07e16`). Retour arrière : `systemctl stop frr` (zebra retire les routes qu'il a installées), puis `systemctl disable frr` et retrait du rôle de `role_routeur`.

**Travail demandé**
1. Dessine (dans ton journal) qui annonce quoi à qui : bordure, `leaf01`, spines, demain les nœuds K8s. Pour chaque flèche, la liste de préfixes qui la filtre.
2. Écris `group_vars/role_routeur/frr.yml` et le `host_vars` de `gw01` (router-id, adresse source de la session avec `leaf01`) : listes de préfixes, route-maps (un refus explicite là où rien ne doit sortir), voisin `leaf01`, groupe `K8S` en écoute fermée, réseau annoncé. Écris le scénario Molecule `frr_bordure` (instance 2049) qui applique **ces données** à une instance jetable et vérifie ce que FRR a chargé.
3. Ajoute à `leaf01` la session vers la bordure et ses politiques (et la propagation de 10.10.20.0/24 vers les spines). Pourquoi fixer dès maintenant, côté bordure, l'adresse source de la session, alors que `gw01` n'a qu'une adresse sur le VLAN 99 (pense à E25) ?
4. Ouvre le port 179 dans `pare_feu.yml` pour `leaf01` seulement. Applique pare-feu, puis FRR, par le pipeline (playbook `bordure-frr.yml`), après les précautions de l'avertissement.
5. Vérifie : session établie ; préfixes reçus et acceptés (`show bgp neighbors 10.10.99.251 received-routes` exige une option : laquelle, et pourquoi ne l'as-tu pas ?) ; routes installées dans le noyau de `gw01` (`ip route show proto bgp`) ; ping de `adm01` vers la boucle de `spine01`.
6. Expériences (sur `leaf01`, puis remise en état) : (a) annonce 10.10.10.0/24 et 0.0.0.0/0 vers la bordure ; (b) retire la route-map de sortie de `leaf01` ; (c) mets 64999 comme AS de la bordure côté `leaf01`. Que fait la bordure dans chaque cas (états, journal, routes) ?

**Critères de réussite**
- [ ] FRR 10.7 tourne sur `gw01`, AS 65000, router-id 10.10.10.2 ; `bgp ebgp-requires-policy` actif.
- [ ] La session avec 10.10.99.251 est établie ; `gw01` n'a appris que des préfixes de 10.10.255.0/24 ou 10.10.41.0/24, installés dans son noyau.
- [ ] Le groupe `K8S` existe (AS 65040, écoute sur 10.10.40.0/24), fermé.
- [ ] `adm01` joint 10.10.255.1 (boucle de `spine01`).
- [ ] Le port 179 n'est ouvert en entrée de `gw01` qu'à 10.10.99.251 ; le scénario Molecule `frr` est sur `main`.

**Vérification** : `lab/bin/check 07 16`

<details><summary>Indice 1</summary>

`network 10.10.20.0/24` n'annonce le préfixe que s'il existe **exactement** dans la table de routage (ici : réseau connecté). Une route-map dont aucune entrée ne correspond refuse ; une route-map qui n'existe pas, selon le contexte, peut tout refuser… ou tout accepter : nomme-les sans faute de frappe et vérifie avec `show route-map`.
</details>

<details><summary>Indice 2</summary>

Une session BGP « directe » (eBGP, TTL 1) part de l'adresse **principale** de l'interface de sortie : le jour où l'interface aura deux adresses (adresse propre et VIP, E25), ce ne sera peut-être pas celle que le voisin attend. `neighbor … update-source <adresse>` la fixe.
</details>

<details><summary>Indice 3</summary>

`show bgp summary` affiche, par voisin, l'état et le nombre de préfixes reçus et envoyés ; `show bgp ipv4 unicast neighbors <voisin> routes` ceux qui ont été acceptés. Garder une copie des routes **refusées** se configure (`soft-reconfiguration inbound`) et coûte de la mémoire.
</details>

**Pour aller plus loin** (facultatif) : ajoute une communauté BGP aux préfixes de la fabric (`set community 65000:100`) et filtre sur elle plutôt que sur les préfixes. Lis la RFC 8212 et la RFC 7454 (*BGP operations and security*).

---

### M07-E17 — Open vSwitch : bonds LACP, VLAN et miroir de port  `LAB` `★★`

> **Ticket PLAT-827** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Les hyperviseurs du cluster (M09) et les nœuds OpenStack (M10) auront des cartes agrégées en LACP vers des commutateurs, avec des VLAN étiquetés par-dessus, et Sophie voudra un jour brancher une sonde de détection d'intrusion sur un port miroir. Monte-moi ça dans `net01` : un serveur agrégé en LACP vers Open vSwitch, deux VLAN, deux postes, un miroir. Je veux voir la négociation LACP des deux côtés et ce qui se passe quand un lien tombe.

**Objectifs pédagogiques**
- Négocier LACP entre un bond Linux 802.3ad et un bond Open vSwitch (`lacp=active`, `balance-tcp`).
- Faire passer des VLAN étiquetés sur un agrégat et des ports d'accès dans Open vSwitch.
- Configurer un miroir de port et capturer le trafic copié.
- Rendre une construction en espaces de noms reproductible au démarrage.

**Prérequis** : M07-E04 (bonding), M07-E05 (Open vSwitch de base).
**Durée indicative** : 2 h.

**Contexte technique**
- Tout se passe **dans** `net01` (le pont Linux de `pve01` ne relaie pas LACP entre VMs, PLAN §4.9). Repars d'un `net01` propre : démonte les constructions de E04 et E05.
- `ovs-vswitchd` ne voit que les interfaces de **son** espace de noms (l'espace racine) : le côté « commutateur » des paires veth reste dans l'espace racine, les machines (serveur `ns-srv`, postes `ns-a10`, `ns-a20`) dans leurs espaces de noms.
- Plan : pont OVS `br-lab` ; serveur : bond `bond0` (802.3ad) sur deux paires veth, sous-interfaces `bond0.10` (172.16.10.1/24) et `bond0.20` (172.16.20.1/24) ; côté OVS : bond `bond-srv` en trunk 10, 20 ; postes : `ns-a10` 172.16.10.2 (accès VLAN 10), `ns-a20` 172.16.20.2 (accès VLAN 20) ; miroir `miroir-srv` du bond vers un port interne `mir0`. Adresses de laboratoire internes à `net01`, jamais routées.
- Construction en script idempotent (`monter`, `demonter`, `etat`) déposé dans `/usr/local/sbin/`, lancé au démarrage par une unité systemd. `net01` est une VM de maquette : pas de rôle Ansible exigé.

**Travail demandé**
1. Écris le script et l'unité ; monte la topologie. Relance `monter` une seconde fois : rien ne doit changer ni échouer.
2. LACP : lis l'état des deux côtés (`ovs-appctl lacp/show`, `/proc/net/bonding/bond0` dans `ns-srv`). Retrouve, de chaque côté, l'identifiant système et la clé du partenaire. Que signifient les drapeaux *activity*, *timeout*, *aggregation*, *synchronization*, *collecting*, *distributing* ?
3. VLAN : `ns-a10` joint 172.16.10.1, `ns-a20` joint 172.16.20.1, et `ns-a10` ne joint **pas** 172.16.20.0/24 (même s'il en avait la route). Capture sur `veth-w1` avec `tcpdump -e` : où vois-tu l'étiquette 802.1Q ?
4. Miroir : `tcpdump -ni mir0` pendant un ping de `ns-a10` : que vois-tu, et pourquoi pas le trafic de `ns-a20` vers… rien ? Que coûte un miroir en production ?
5. Panne : coupe `veth-w1` (`ip link set veth-w1 down`) pendant un ping continu, puis rétablis-la. Combien de paquets perdus ? Qui a détecté la panne, et par quel mécanisme ? Recommence en coupant le lien **côté serveur** dans `ns-srv`.
6. Redémarre `net01` : la topologie revient-elle seule ?

**Critères de réussite**
- [ ] `br-lab` porte un bond LACP `bond-srv` (deux membres actifs, LACP négocié) et deux ports d'accès étiquetés 10 et 20.
- [ ] Le bond Linux de `ns-srv` est en 802.3ad avec deux membres, agrégés avec le même partenaire.
- [ ] `ns-a10` joint 172.16.10.1, `ns-a20` joint 172.16.20.1 ; `ns-a10` ne joint pas 172.16.20.1.
- [ ] Un miroir copie le trafic du bond vers `mir0`.
- [ ] L'unité de construction est activée ; la topologie survit à un redémarrage.

**Vérification** : `lab/bin/check 07 17`

<details><summary>Indice 1</summary>

Un membre doit être **arrêté** avant d'être asservi à un bond Linux (`ip link set … down` puis `master bond0`). Côté OVS, `add-bond` crée le port et ses interfaces en une commande ; les options du port (`bond_mode`, `lacp`, `trunks`) se posent avec `set port`.
</details>

<details><summary>Indice 2</summary>

Un miroir OVS est un enregistrement de la table `Mirror`, référencé par le pont : il faut le créer **et** l'attacher (`set bridge … mirrors=@m`) dans la même transaction `ovs-vsctl`, avec des `--id=@nom get port …` pour désigner les ports.
</details>

<details><summary>Indice 3</summary>

La base d'OVS persiste (pont, ports, miroir) ; les paires veth et les espaces de noms, non. Au démarrage, OVS retrouve donc des ports sans interface : ton unité doit passer **après** `openvswitch-switch.service` et recréer ce qui manque.
</details>

**Pour aller plus loin** (facultatif) : remplace la sortie du miroir par un tunnel GRE vers une autre VM (`output_port` sur un port GRE) : c'est le principe d'un RSPAN/ERSPAN. Documentation : <https://docs.openvswitch.org/en/latest/faq/configuration/>, `man ovs-vswitchd.conf.db` (tables *Port* et *Mirror*).

---

### M07-E18 — Raccorder le site de Lyon en WireGuard  `LAB` `★★`

> **Ticket PLAT-828** — *De : Claire Morel*
> L'agence de Lyon ouvre le mois prochain : une dizaine de personnes du support et du commercial. Elles ont besoin du DNS interne et des services publiés (GitLab, NetBox), pas de l'administration. Le lien entre les deux sites passe par Internet, chiffré. Commence simple, en routes statiques : on verra le routage dynamique ensuite. Et les clés ne traînent nulle part.

**Objectifs pédagogiques**
- Écrire un rôle `wireguard` dont les clés privées viennent d'Ansible Vault et ne s'affichent jamais.
- Comprendre `AllowedIPs` (filtre d'entrée et table de routage du tunnel) et `Table = off`.
- Ouvrir à un site distant exactement ce qu'il doit joindre, et éviter le routage asymétrique d'un poste à deux interfaces.

**Prérequis** : M00-E16, M00-E21 (WireGuard à la main), M04 (Vault, identités `lab` et `critique`), M07-E03 (`lyo-gw01`, `lyo-pc01`), M07-E13 (services publiés).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Faits du site dans le tableau du palier. L'« Internet » de Lyon est le VLAN 99 : `lyo-gw01` joint `gw01` en 10.10.99.1. `lyo-gw01` initie (comme une agence derrière une box) ; `gw01` écoute sur UDP 51822.
- `wg0` et `wg1` de `gw01` ont été construits à la main (M00) : ce rôle ne doit **pas** y toucher (ils seront repris en E26).
- Clé privée de `wg2` côté `gw01` : Vault `critique` (PLAN §4.9), dans `group_vars/role_routeur/` (la configuration de `wg2` sera commune aux deux passerelles en E26) ; côté `lyo-gw01` : Vault `lab` (maquette). Inscris la première au registre des secrets.
- `lyo-pc01` a deux interfaces : `eth0` (administration, route par défaut DHCP) et `eth1` sur le LAN de l'agence (10.30.10.10/24). On l'administre depuis `adm01` (MGMT) par `eth0`.
- Accès voulus depuis 10.30.0.0/16 : DNS (`dns01`, `dns02`), HTTPS vers la VIP des répartiteurs, `ping` de diagnostic vers INFRA et DMZ. Rien vers MGMT, rien de PAR1 vers Lyon pour l'instant.

**Travail demandé**
1. Génère les deux paires de clés sans que les clés privées ne touchent le disque en clair ni l'écran (une commande par clé, sortie directement chiffrée par `ansible-vault encrypt_string`).
2. Écris le rôle `wireguard` : interfaces décrites en variables, fichier 0600, rien dans les journaux, unité `wg-quick@`, changement de pairs appliqué sans démonter l'interface, contrôle final (interface montée, port d'écoute). Prévois une interface « pilotée ailleurs » (fichier posé, unité ni activée ni lancée) : tu en auras besoin en E26.
3. Configure `wg2` des deux côtés en `Table = off`, avec des routes statiques posées au montage de l'interface ; `AllowedIPs` au plus juste de chaque côté. Les routes de `lyo-pc01` : seulement les réseaux autorisés, par le routeur de l'agence.
4. Matrice des flux : l'entrée du tunnel sur `gw01`, les flux de Lyon vers PAR1 (pense à la règle DNS existante). Applique.
5. Vérifie depuis `lyo-pc01` : résolution de `gitlab.par1.medisphere.internal` par 10.10.20.10, `curl --cacert` vers `https://gitlab.par1.medisphere.internal`, ping de 10.10.20.10. Et l'interdit : rien vers 10.10.10.10 par le tunnel.
6. Expériences : (a) retire 10.10.70.0/24 des `AllowedIPs` du pair PAR1 côté `lyo-gw01` seulement (la route posée au montage reste) : que voit `lyo-pc01`, que voit `lyo-gw01` lui-même, et pourquoi ? (b) sur `lyo-pc01`, remplace les routes ciblées par une route vers tout 10.10.0.0/16 : que devient ta session SSH depuis `adm01` ? Explique, puis remets en état.

**Critères de réussite**
- [ ] `wg2` est monté sur `gw01` (UDP 51822) et sur `lyo-gw01` ; la dernière poignée de main a moins de trois minutes.
- [ ] `gw01` route 10.30.0.0/16 par `wg2` ; `lyo-pc01` résout les noms internes par 10.10.20.10 et joint les services publiés.
- [ ] `lyo-pc01` ne joint pas MGMT par le tunnel ; sa session d'administration fonctionne.
- [ ] `/etc/wireguard/wg2.conf` est en 0600 sur les deux routeurs ; aucune clé privée en clair dans le dépôt ; le rôle `wireguard` est sur `main`.
- [ ] Les flux du site sont dans `pare_feu.yml`, ciblés et commentés.

**Vérification** : `lab/bin/check 07 18`

<details><summary>Indice 1</summary>

`wg genkey` écrit la clé privée sur sa sortie : un `tee` vers une substitution de processus (`>(wg pubkey > …)`) donne la clé publique au passage, et un tube vers `ansible-vault encrypt_string --stdin-name …` chiffre la clé privée avant qu'elle n'atteigne un fichier.
</details>

<details><summary>Indice 2</summary>

Un paquet reçu par le tunnel est jeté si sa **source** n'est pas dans les `AllowedIPs` du pair ; un paquet à émettre n'est envoyé à un pair que si sa **destination** y est. Avec `Table = off`, `wg-quick` n'ajoute aucune route : `PostUp` (avec `%i` pour le nom de l'interface) peut le faire.
</details>

<details><summary>Indice 3</summary>

Sur un hôte à deux interfaces, la réponse part selon **sa** table de routage, pas par l'interface d'arrivée de la question. Si la route vers l'adresse de `adm01` passe par le tunnel, la réponse SSH prend le tunnel… que le pare-feu de `gw01` ne connaît pas pour cette connexion.
</details>

**Pour aller plus loin** (facultatif) : mesure le débit du tunnel (`iperf3`) et le MTU effectif (`tracepath`) ; pourquoi `wg-quick` choisit-il 1420 par défaut ? Documentation : <https://www.wireguard.com/quickstart/>, `man wg-quick`.

---

### M07-E19 — Routage dynamique à travers le tunnel  `LIBRE` `★★★`

> **Ticket PLAT-829** — *De : Karim Benali*
> Les routes statiques de Lyon tiendront jusqu'au jour où l'agence ouvrira un second sous-réseau, ou jusqu'à ce que quelqu'un ajoute un VLAN à PAR1 en oubliant le tunnel. Passe l'agence en BGP : chacun annonce ce qu'il a, chacun filtre ce qu'il reçoit, et la liste de ce que Lyon a le droit de joindre ne doit exister qu'à **un** endroit du code. Bascule sans couper l'agence plus de quelques secondes.

**Objectifs pédagogiques**
- Concevoir une session eBGP entre deux sites à travers un tunnel, avec des politiques symétriques.
- Rendre cohérents trois endroits qui décident du même flux : la politique BGP, les `AllowedIPs` de WireGuard, la matrice des flux.
- Annoncer un agrégat proprement et migrer du statique au dynamique sans coupure longue.

**Prérequis** : M07-E16 (FRR sur la bordure), M07-E18.
**Durée indicative** : 3 h.

**Contexte technique**
- AS : bordure 65000, LYO1 65030 (PLAN §4.9). La session passe dans `wg2` (10.255.2.1 ↔ 10.255.2.2).
- Lyon annonce son site (10.30.0.0/16) ; PAR1 annonce à Lyon les seuls réseaux ouverts à l'agence (10.10.20.0/24, 10.10.70.0/24 aujourd'hui).
- Le rôle `frr` (E14) et sa configuration de bordure (E16) existent ; FRR n'est pas encore installé sur `lyo-gw01`.
- Les inventaires NetBox (socle) et Proxmox (maquette) peuvent être chargés ensemble ; une variable de `group_vars/all` est alors vue par tous les hôtes.

**Travail demandé**
Livre, par MR, le passage de Lyon en routage dynamique. Contraintes :
- une seule définition, dans le code, des réseaux de PAR1 ouverts à l'agence, utilisée par la politique de sortie de la bordure **et** par la configuration WireGuard de l'agence ;
- politiques d'entrée et de sortie des deux côtés, au plus juste ; un plafond du nombre de préfixes acceptés de l'agence ;
- l'agence annonce son agrégat, sans dépendre de l'existence d'une interface qui le couvre entièrement ;
- plus aucune route statique liée au tunnel sur les deux routeurs ; les `AllowedIPs` restent cohérents avec ce que BGP peut installer ;
- la session BGP est autorisée dans la matrice des flux, pour ce seul pair ;
- un plan de bascule écrit (ordre, coupure attendue, retour arrière), puis la bascule mesurée depuis `lyo-pc01` ;
- la preuve qu'un réseau ajouté à la liste unique devient joignable depuis Lyon sans autre modification, et qu'un préfixe de MGMT annoncé par erreur par l'agence est refusé.

**Critères de réussite**
- [ ] La session BGP `gw01` ↔ `lyo-gw01` est établie dans `wg2`.
- [ ] `gw01` a appris 10.30.0.0/16 de l'agence (installé par BGP) ; `lyo-gw01` n'a appris que les réseaux ouverts (pas 10.10.10.0/24).
- [ ] Aucune route statique vers le tunnel ne reste dans la configuration WireGuard des deux routeurs.
- [ ] `lyo-pc01` joint toujours le DNS et les services publiés de PAR1.
- [ ] Le port 179 est ouvert sur `wg2` pour 10.255.2.2 seulement.

**Vérification** : `lab/bin/check 07 19`

<details><summary>Indice 1</summary>

Une variable de `group_vars/all` est vue par tous les hôtes des inventaires chargés. Une liste de dictionnaires `{seq, prefixe}` se transforme en règles de liste de préfixes (`map('combine', …)`) comme en `AllowedIPs` (`map(attribute='prefixe')`).
</details>

<details><summary>Indice 2</summary>

`network` n'annonce qu'un préfixe présent exactement dans la table de routage. Une route « trou noir » vers l'agrégat le fait exister sans rien casser : les sous-réseaux plus précis gagnent toujours.
</details>

<details><summary>Indice 3</summary>

Si la session monte **avant** que les routes statiques ne disparaissent, les routes BGP s'installent à côté (ou à la place, selon la distance administrative) : la bascule ne coupe que le temps de remonter l'interface.
</details>

**Pour aller plus loin** (facultatif) : ajoute un second tunnel de secours (par `gw02`, en E24) et fais préférer le premier avec `local-preference` côté PAR1 et `as-path prepend` côté Lyon.

---

### M07-E20 — Méthode de diagnostic réseau  `LAB` `★★`

> **Ticket PLAT-830** — *De : Nadia Roussel*
> Depuis le début du module, chaque souci réseau finit chez Karim ou chez toi. L'astreinte ne peut pas fonctionner comme ça. Il me faut une méthode écrite, dans l'ordre, que n'importe qui de l'équipe peut suivre à trois heures du matin : par où commencer, quelle commande, comment lire le résultat, quand s'arrêter et appeler. Et si une partie peut être faite par un outil, encore mieux.

**Objectifs pédagogiques**
- Diagnostiquer couche par couche, de la source vers la destination, l'aller **et** le retour.
- Lire les outils de chaque couche : `ip`, `bridge`, `ovs-appctl`, `tcpdump`, `nft monitor trace`, `conntrack`, `vtysh`, `wg`.
- Outiller le premier relevé (script en lecture seule) et écrire le runbook RB-072.

**Prérequis** : M07-E10 à M07-E19 ; M02 (scripts `ms-*`, bibliothèque `ms-commun.sh`).
**Durée indicative** : 3 h.

**Contexte technique**
- Outil à écrire : `ms-diag-chemin` dans `bin/` de `plateforme/outils` : `ms-diag-chemin [--depuis HÔTE] [--mtu OCTETS] DESTINATION [PORT]`, en lecture seule, exécutable depuis `adm01` sur un hôte joint en SSH. Code retour 0 si la destination est jointe, 1 sinon, 2 en cas d'usage incorrect.
- Runbook : `docs/socle/runbooks/RB-072-diagnostic-reseau.md`.
- Trace nftables : `nft monitor trace` n'affiche que les paquets marqués `meta nftrace set 1` par une règle. La table `inet filter` de `gw01` appartient au rôle `pare_feu`.

**Travail demandé**
1. Dans ton journal, pour chacune des situations suivantes, écris l'outil et ce qu'il doit montrer : (a) une VM d'un VLAN n'obtient pas de réponse ARP de sa passerelle ; (b) un SYN part et rien ne revient ; (c) « connection refused » immédiat ; (d) petits échanges OK, gros transferts figés ; (e) ça marche depuis MGMT, pas depuis la sandbox ; (f) un agrégat a perdu un lien.
2. Rejoue trois cas concrets sur la maquette et note chaque commande et sa sortie :
   - de `adm01` vers `https://hap01.par1.medisphere.internal` : suis le paquet sur `gw01` (`tcpdump` sur `ens19.10` puis `ens19.99`) et dans le pont de `pve01` (`bridge fdb`, `tcpdump` sur l'interface `tap` de `hap01`) ;
   - de `lyo-pc01` vers 10.10.20.10 : la route sur chaque saut (`ip route get`, avec `from` et `iif` sur `gw01` pour le retour) ;
   - de `srv01` vers une adresse de 10.10.20.0/24 par le VLAN 30 avec `ping -M do -s 8972` : qui émet l'ICMP, avec quel MTU ?
3. Pose une trace nftables ciblée sur `gw01` (table temporaire **séparée**), lis le chemin d'un paquet accepté puis d'un paquet refusé, et retire la table.
4. Écris `ms-diag-chemin` : résolution, route choisie (interface, passerelle, source), voisin de niveau 2, ICMP, MTU sans fragmentation, `tracepath`, connexion TCP. Chaque section dit OK ou KO avec une phrase qui oriente. ShellCheck sans avertissement ; publication par la CI du projet.
5. Rédige RB-072 : cadrer (source, destination, symptôme, changement récent), relevé automatique, puis une section par couche avec les commandes et la lecture des résultats, capture aux bornes, correction **par le code**, clôture. Tableau « symptôme → piste prioritaire ». Fais-le relire par MR (Nadia).

**Critères de réussite**
- [ ] `ms-diag-chemin` est sur `main` de `plateforme/outils`, exécutable, sans avertissement ShellCheck, et renvoie 0 vers une destination jointe, 1 sinon.
- [ ] RB-072 est sur `main` de `plateforme/medisphere`, avec un tableau symptôme → piste, une section par couche (L2, L3 aller et retour, filtrage, MTU) et la trace nftables dans une table temporaire.
- [ ] Aucune table de trace ne reste sur `gw01`.
- [ ] Ton journal contient les trois cas rejoués avec leurs sorties.

**Vérification** : `lab/bin/check 07 20`

<details><summary>Indice 1</summary>

`ip route get <dest> from <src> iif <interface>` demande au noyau ce qu'il ferait d'un paquet **entrant** par cette interface : c'est la seule façon de vérifier un retour (et l'effet de `rp_filter`) sans l'envoyer.
</details>

<details><summary>Indice 2</summary>

Une chaîne de trace s'accroche au même crochet que les autres (`prerouting`) avec une priorité plus basse que tout le reste (un nombre plus petit) : elle voit le paquet en premier. `nft monitor trace` montre ensuite chaque règle évaluée et la décision finale.
</details>

<details><summary>Indice 3</summary>

Pour un outil de diagnostic, « rien vu » n'est pas « tout va bien » : une résolution vide, un `ip route get` en erreur, un `ping` absent sont des KO explicites. Et un outil d'astreinte ne modifie rien.
</details>

**Pour aller plus loin** (facultatif) : `pwru` (eBPF) suit un paquet à travers les fonctions du noyau ; essaie-le sur `gw01` et compare avec la trace nftables. Lis `man ip-route` (section `get`).

---

### M07-E21 — Revue : les répartiteurs du stagiaire  `REV` `★★`

> **Ticket PLAT-831** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas prépare la publication de MédiAgenda (prévue au bloc C) et m'a envoyé sa configuration des répartiteurs « testée sur deux VMs de la sandbox, tout marche ». Fais-lui une vraie revue avant qu'elle n'approche `lb01` et `lb02` : chaque défaut, sa gravité, ce qu'il casserait **chez nous**, la correction.

**Objectifs pédagogiques**
- Relire une configuration HAProxy et keepalived comme elle s'exécutera dans le socle.
- Repérer les défauts de sécurité (exposition, vérifications désactivées), de haute disponibilité (élection VRRP, suivi) et de fonctionnement (capacité, délais).
- Rédiger une revue utile à son destinataire.

**Prérequis** : M07-E10 à M07-E13.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M07-E21/` (`MR-lucas.md`, `haproxy.cfg`, `keepalived-lb01.conf`, `keepalived-lb02.conf`).
- Cible : `lb01`/`lb02`, VIP 10.10.70.200, publication de `agenda.par1.medisphere.internal` vers deux serveurs d'application (adresses prévues 10.10.40.21 et 10.10.40.22), en plus de GitLab et NetBox.
- Rappels : VRRP de la bordure à partir de E25 (VRID = numéro de VLAN, sur tous les VLAN routés) ; politique TLS de la PKI (M06-E33).

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : qui peut administrer ce HAProxy, et d'où ? Que se passe-t-il quand HAProxy s'arrête sur `lb01` ? Quand les deux répartiteurs démarrent en même temps ?
2. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, haute disponibilité, fonctionnement, exploitation), gravité (critique, élevée, moyenne, faible), impact concret dans **notre** lab, correction.
3. Classe les défauts par ordre de traitement et justifie le premier.
4. Propose les lignes corrigées des trois fichiers.
5. Trois lignes de conseils à Lucas sur sa façon de tester une haute disponibilité.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 9 défauts identifiés, dont tous les critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise (directive, valeur).
- [ ] Les conseils de test portent sur ce qui doit **échouer** ou **basculer**, pas seulement sur ce qui doit marcher.

<details><summary>Indice 1</summary>

Pour chaque `bind` et chaque socket : depuis quelles adresses, avec quels droits ? Pour chaque `server` : comment HAProxy sait-il qu'il est mort, et comment vérifie-t-il à qui il parle ?
</details>

<details><summary>Indice 2</summary>

Mets les deux fichiers keepalived côte à côte et compare ligne à ligne : ce qui doit être identique, ce qui doit différer. Calcule ensuite les priorités effectives quand HAProxy est arrêté sur le maître.
</details>

<details><summary>Indice 3</summary>

Regarde les nombres : délais, nombre de connexions, versions de TLS, numéro de routeur virtuel. Chacun a-t-il un sens pour le service et le réseau visés ?
</details>

**Pour aller plus loin** (facultatif) : écris le test (Molecule ou script) qui aurait attrapé les deux défauts les plus graves avant la MR.

---

### M07-E22 — Runbook : maintenance d'un répartiteur  `RED` `★★`

> **Ticket CHG-832** — *De : Nadia Roussel*
> Les répartiteurs portent maintenant GitLab et NetBox, et bientôt tout ce que la plateforme exposera. Il faudra les mettre à jour, les redémarrer, en reconstruire un. Écris **RB-070** : sortir un répartiteur du service sans couper personne, intervenir, le remettre, et revenir à la situation nominale. Je le jouerai sur `lb02`, puis sur `lb01` qui porte la VIP.

**Objectifs pédagogiques**
- Écrire une procédure de maintenance d'un service redondant, exécutable par quelqu'un d'autre.
- Rendre chaque étape vérifiable, et prévoir l'arrêt de la procédure si l'autre membre de la paire n'est pas sain.
- Distinguer drainer un service, déplacer une VIP et arrêter un hôte.

**Prérequis** : M07-E12, M07-E13, M06-E23 (RB-060, pour la reconstruction).
**Durée indicative** : 2 h.

**Contexte technique**
- Emplacement : `docs/socle/runbooks/RB-070-maintenance-repartiteur.md` dans `plateforme/medisphere`, sur le modèle de RB-060.
- Pas de préemption sur la VIP (ADR-0071) : un répartiteur qui revient ne reprend pas la VIP.
- Les connexions en cours sur le maître sont coupées quand la VIP se déplace (pas de synchronisation d'état entre répartiteurs). Les clients Git en HTTPS et les sessions WebSocket de GitLab sont les plus sensibles.
- Outils disponibles : socket d'administration d'HAProxy, `systemctl`, `journalctl`, `ms-snapshot`, playbook `repartiteurs.yml`, OpenTofu (état `socle`).

**Travail demandé**
Rédige RB-070 avec au moins : quand l'utiliser (mise à jour des paquets, redémarrage, changement de configuration, reconstruction ; et ce qui n'en relève pas), prérequis (accès, état de l'autre répartiteur, fenêtre, annonce), contrôles d'entrée qui **interdisent** de continuer, étapes numérotées pour le répartiteur en attente puis pour le maître (déplacement contrôlé de la VIP, attente de la fin des connexions, intervention, retour en service, contrôles), retour à la situation nominale (VIP sur `lb01`, au moment choisi), reconstruction d'un répartiteur (renvoi vers RB-060 et ce qui est propre aux répartiteurs : certificats, VIP), retour arrière par étape, pièges connus. Joue-le sur `lb02` puis sur `lb01`, mesure l'interruption vue par un client, corrige chaque hésitation, fais-le relire par MR (Nadia, Karim).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] La procédure ne peut pas laisser les deux répartiteurs hors service : un contrôle d'entrée bloque si l'autre n'est pas sain.
- [ ] Le maître n'est jamais arrêté brutalement : la VIP est déplacée de façon contrôlée, les connexions ont le temps de se terminer, la durée d'attente est justifiée.
- [ ] Chaque étape a un contrôle observable (commande et résultat attendu) et un retour arrière.
- [ ] Le retour sur `lb01` est une étape explicite, avec sa propre fenêtre.

**Pour aller plus loin** (facultatif) : quelles étapes un pipeline pourrait-il enchaîner seul (mise à jour hebdomadaire des répartiteurs) ? Esquisse le job et ses garde-fous.

---

### M07-E23 — Revue : la configuration BGP du prestataire  `REV` `★★★`

> **Ticket PLAT-833** — *De : Claire Morel*
> InfoGér nous a transmis la configuration du routeur de bordure qu'il exploitait pour notre ancien hébergement, avec la proposition de « la reprendre telle quelle sur `gw01` et `gw02`, ça marche depuis cinq ans ». Je veux ton avis écrit avant de répondre : ce qu'on garde, ce qu'on jette, ce qui serait dangereux chez nous. Sois précis, ce document partira chez eux.

**Objectifs pédagogiques**
- Relire une configuration FRR de bordure au regard de bonnes pratiques reconnues (RFC 8212, RFC 7454) et de la politique de MédiSphère.
- Évaluer le risque d'une fuite ou d'un détournement de routes, et la robustesse des sessions.
- Rédiger un avis destiné à un tiers : factuel, argumenté, sans jugement de personne.

**Prérequis** : M07-E07, M07-E16, M07-E19.
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers : `ressources/M07-E23/` (`frr-infogere.conf`, `notes-infogere.md`).
- Chez InfoGér, le routeur parlait à un opérateur de transit, à l'agence (déjà en AS 65030) et à des « clients » hébergés.
- Chez MédiSphère : bordure AS 65000, fabric et Kubernetes en eBGP, LYO1 dans un tunnel, politique « rien sans filtre » (PLAN §4.9), aucune annonce de MGMT hors de PAR1.

**Travail demandé**
1. Décris en dix lignes ce que fait ce routeur : avec qui il parle, ce qu'il accepte, ce qu'il annonce.
2. Rédige la revue en tableau (n°, ligne(s), défaut, catégorie — sécurité, stabilité, exploitation —, gravité, conséquence **si on le reprenait chez nous**, correction).
3. Dis ce qui mérite d'être **gardé** (il y en a).
4. Rédige l'avis à InfoGér (vingt lignes) : décision, raisons principales, ce qu'on attend d'eux pour la transition.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 8 défauts identifiés, dont tous les critiques et élevés du corrigé.
- [ ] Chaque défaut est relié à une conséquence concrète dans le réseau de MédiSphère.
- [ ] Les éléments à garder sont identifiés et justifiés ; l'avis est factuel.

<details><summary>Indice 1</summary>

Pour chaque voisin : y a-t-il une politique d'entrée, une de sortie, un plafond de préfixes ? Pour chaque `redistribute` et chaque `network` : qu'est-ce que cela fait sortir exactement ?
</details>

<details><summary>Indice 2</summary>

Une liste de préfixes `permit 10.0.0.0/8 le 32` laisse passer quoi, exactement ? Que fait un routeur qui reçoit un /32 plus précis qu'une route qu'il connaît ?
</details>

<details><summary>Indice 3</summary>

Regarde aussi les temporisateurs, l'identifiant du routeur, ce qui est journalisé, et ce qui est écrit en clair.
</details>

**Pour aller plus loin** (facultatif) : lis le guide MANRS (*Mutually Agreed Norms for Routing Security*) et dis lesquelles de ses actions s'appliqueraient à MédiSphère si elle avait un jour son propre AS public.

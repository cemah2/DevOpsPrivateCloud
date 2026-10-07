# Module 06 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`ansible/` pour `plateforme/ansible`, `infra/` pour `plateforme/infra`, `outils/` pour `plateforme/outils`, `medisphere/` pour `plateforme/medisphere`, `adm01/` pour des scripts personnels de `adm01`). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été testé à la rédaction** (Debian 13 dans des conteneurs systemd, ansible-core 2.21, OpenTofu 1.13) :
- `ca01.tf` et `nbx01.tf` passent `tofu validate` et `tofu fmt -check` avec le module `vm-debian` de M05 ;
- le rôle `step_ca` : phase 1 (CSR rapatriée, arrêt propre), cérémonie avec `ceremonie-pki.sh`, phase 2 (CA démarrée, `/health`, `/provisioners`, annuaire ACME, `/ssh/roots`), second passage `changed=0`, `verify.yml` de Molecule ; step-ca 0.30.2, step-cli 0.31.0 ;
- le rôle `netbox` complet (NetBox 4.6.9, PostgreSQL 17, Valkey 8.1, gunicorn, nginx, TLS vérifié), second passage `changed=0` ; le script `modeliser.py` contre un vrai NetBox 4.6.9 : 167 objets créés au premier passage, aucun changement au second ;
- les rôles `powerdns_auth` (5.0.7) et `powerdns_recursor` (5.4.7) : zones, numéro de série croissant, API (avec clé, sans clé, client non autorisé), relais des zones internes, validation de la configuration du Recursor ;
- la bascule de M06-E08 dans un conteneur : redémarrage naïf → **4 échecs « client »** ; avec la table nftables « silence » → **0 échec client** (1 échec « brut »), puis passage normal `changed=0` ;
- tous les scripts passent `shellcheck -x` et `bash -n` ; `ruff` sur `modeliser.py` ; `ansible-playbook --syntax-check` et `ansible-lint` (profil `production`) sur les rôles et playbooks.

**Points non testés en conditions réelles**, à vérifier sur ta version et à signaler s'ils diffèrent :
- la résolution d'Internet et la validation DNSSEC (drapeau `ad`, `dnssec-failed.org`) : l'environnement de rédaction bloquait le DNS sortant en TCP ; la configuration suit la documentation du Recursor 5.4, les comportements décrits en E07 sont ceux de cette documentation ;
- les commandes de GitLab pour son magasin de confiance (`/etc/gitlab/trusted-certs/`, `gitlab-ctl reconfigure`) et le rôle `seaweedfs` de M05 (noms de ses variables de certificat : reprends les tiens) ;
- le texte exact des messages d'erreur de step-ca (durée refusée) et des écrans de l'interface de NetBox (création des jetons) ;
- la référence du module `vm-debian` (`?ref=v1.0.0` dans les fichiers) : mets la dernière étiquette que tu as publiée en M05.

---

### M06-E01 — Test de positionnement : services d'infrastructure

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, lis attentivement les contextes techniques de E06 et E07 avant de commencer ; les questions 11 à 18 sont reprises en profondeur en E02, E03 et au palier 2 (E18 à E20).

**Réponses argumentées — DNS**

**1. Autorité et récursion.** Un serveur **faisant autorité** détient les données de ses zones (il est la source) et ne répond que pour elles ; il ne pose de questions à personne (sauf transferts de zone). Un **résolveur récursif** ne détient rien : il reçoit la question d'un client, interroge itérativement la racine, puis les serveurs du TLD, puis ceux de la zone, met les réponses en cache et rend le résultat. `aa` (*authoritative answer*) : la réponse vient d'un serveur qui fait autorité sur la zone. `rd` (*recursion desired*) : mis par le client, « fais le travail pour moi ». `ra` (*recursion available*) : mis par le serveur, « je sais faire de la récursion pour toi ». On sépare les deux rôles parce qu'ils n'ont ni la même exposition ni les mêmes risques : un résolveur ouvert sert aux attaques par amplification et subit l'empoisonnement de cache, un serveur faisant autorité qui fait aussi de la récursion peut servir une donnée de cache à la place d'une donnée de zone ; séparés, chacun a sa configuration, son contrôle d'accès, sa supervision, et on peut redémarrer ou remplacer l'un sans l'autre. dnsmasq mélange tout, ce qui suffit pour quelques noms mais pas pour des zones écrites par API, des secondaires, DNSSEC ou des vues.

**2. Réponse B.** Le nom existe (il a un `A`) : ce n'est donc pas `NXDOMAIN` (A), qui dirait « ce nom n'existe pas, pour aucun type », et effacerait à tort le `A` du cache négatif des clients. La réponse est `NOERROR` avec une section réponse vide et le SOA de la zone dans la section autorité (cas appelé *NODATA*, RFC 2308). C (`SERVFAIL`) signale une panne du serveur ; D (`REFUSED`) un refus de servir (zone non tenue, client non autorisé).

**3. SOA.** `MNAME` (serveur primaire), `RNAME` (adresse du responsable, le premier `.` remplace `@` : `hostmaster.medisphere.internal`), `SERIAL` (version de la zone), `REFRESH` (intervalle de vérification par les secondaires), `RETRY` (nouvel essai après un échec de vérification), `EXPIRE` (au-delà, un secondaire qui ne joint plus le primaire cesse de servir la zone), `MINIMUM` (depuis la RFC 2308 : TTL des réponses négatives). Le numéro de série dit aux secondaires s'il y a une nouvelle version : ils comparent le leur à celui du primaire (arithmétique de la RFC 1982) et ne transfèrent que s'il est **plus grand**. S'il diminue, les secondaires gardent l'ancienne version indéfiniment : le changement ne se propage pas, sans erreur visible. Pour réparer, on fait faire le tour au numéro (augmentations successives de moins de 2³¹) ou on force un transfert complet sur chaque secondaire. C'est pourquoi le rôle de E06 calcule le numéro à partir de celui en place, jamais d'une valeur fixe.

**4. Colle.** Le serveur de `par1.medisphere.internal` s'appelle `dns01.par1.medisphere.internal` : pour trouver son adresse, il faudrait interroger… le serveur de `par1`, qu'on ne sait pas joindre. La boucle est cassée par un enregistrement `A` de `dns01.par1…` placé **dans la zone parente**, à côté du NS de délégation : l'enregistrement de **colle** (*glue*). Il n'est pas autoritaire dans la parente (la donnée de référence est dans la fille) : il ne sert qu'à suivre la délégation.

**5. Réponse B.** RFC 2308 : la durée de cache d'une réponse négative est le minimum entre le TTL de l'enregistrement SOA renvoyé dans la section autorité et le champ `MINIMUM` du SOA. A est faux (le résolveur peut plafonner, mais la valeur vient de la zone) ; C est faux (le cache négatif existe précisément pour ne pas reposer la question à chaque fois) ; D confond avec un paramètre réservé aux secondaires. Conséquence pratique : un nom créé juste après qu'un client l'a demandé peut rester « inexistant » pour lui jusqu'à 300 s (notre TTL négatif).

**6. `ad` et zones internes.** `ad` (*authenticated data*) : le résolveur affirme avoir **validé** la réponse par la chaîne DNSSEC depuis une ancre de confiance (la clé de la racine). Pour `medisphere.internal`, la racine est signée et **prouve** (enregistrements NSEC signés) que `internal` n'est pas délégué ; un résolveur qui valide en conclut qu'une réponse positive pour `git01.par1.medisphere.internal` est impossible, donc falsifiée : réponse *bogus*, rendue en `SERVFAIL`. La documentation du Recursor le dit explicitement : un relais vers une zone non déléguée dont la parente est signée valide en *bogus*. Solutions : (a) une **ancre négative** (NTA) pour la zone : on désactive la validation sous ce nom ; (b) signer la zone interne et installer une **ancre de confiance** pour elle dans le résolveur (M06-E26). Ne pas valider du tout (mode `off`, `process-no-validate`) « marche » mais jette la protection pour Internet aussi.

**7. TCP.** Quand la réponse ne tient pas dans la taille UDP annoncée (EDNS, 1232 octets recommandés depuis le *DNS Flag Day* 2020) : le serveur renvoie une réponse tronquée (drapeau `TC`) et le client recommence en TCP ; pour les transferts de zone (AXFR, IXFR) ; pour DNS sur TLS (port 853). Si le pare-feu ne laisse passer que l'UDP 53, tout fonctionne… jusqu'à la première grosse réponse : réponses DNSSEC, enregistrements TXT longs, beaucoup d'adresses pour un nom. Le client reçoit la réponse tronquée puis échoue en TCP : panne intermittente, difficile à diagnostiquer. D'où l'exigence « UDP **et** TCP » des règles de `gw01` (M00-E13) et des contrôles de E08.

**Réponses argumentées — DHCP**

**8. DORA à travers un relais.** Le client diffuse `DISCOVER` ; le relais (sur `gw01`) le transmet en unicast au serveur en écrivant dans `giaddr` l'adresse de **son interface côté client** ; le serveur s'en sert pour choisir le sous-réseau (et donc la plage) et pour renvoyer `OFFER` au relais, qui le transmet au client ; puis `REQUEST` et `ACK` de la même façon. Mise à jour du DNS : soit le **serveur DHCP** (Kea avec son module D2, M06-E17) au nom du client, soit le client lui-même. Le client aide avec l'option **81** (*Client FQDN*, RFC 4702) — ou plus simplement l'option 12 (*Host Name*) — qui annonce le nom voulu et qui doit faire la mise à jour.

**9. Réponse B.** Sans coordination, chaque serveur ignore les baux de l'autre : deux clients peuvent recevoir la même adresse (conflit, coupures aléatoires). A est faux pour cette raison (le partage de charge exige un protocole entre serveurs : le *High Availability hook* de Kea, M06-E25, ou des plages disjointes) ; C est faux (un relais accepte plusieurs serveurs et les interroge tous) ; D est faux (le client n'accepte qu'une offre).

**10. T1 et T2.** T1 (par défaut 50 % de la durée du bail) : le client demande à **prolonger** le bail par un `REQUEST` en unicast au serveur qui l'a accordé (*renewing*). T2 (87,5 %) : s'il n'a toujours pas de réponse, il **diffuse** son `REQUEST` à n'importe quel serveur (*rebinding*). À l'expiration, il perd l'adresse et recommence par `DISCOVER`. Pour une panne du serveur DHCP, la marge est donc la moitié du bail.

**Réponses argumentées — PKI et TLS**

**11. Chaîne TLS.** Le serveur envoie son certificat **et** les intermédiaires nécessaires pour remonter jusqu'à une racine. Il n'envoie pas la racine : elle ne prouve rien (n'importe qui peut fabriquer un certificat auto-signé portant le même nom), la confiance vient de ce que le client la **possède déjà** dans son magasin. Le client doit donc avoir la racine ; l'oubli classique est l'inverse : un serveur qui n'envoie pas l'intermédiaire (« fonctionne avec mon navigateur, échoue avec `curl` »). D'où le fichier `.crt` « chaîne complète » de E03 et E04.

**12. Racine hors ligne.** La racine est l'élément le plus précieux : elle est dans le magasin de chaque machine, la remplacer veut dire toucher **tous** les clients. Elle ne sert presque jamais (signer un intermédiaire tous les quelques années) : on peut donc la garder hors ligne, là où aucune attaque réseau ne l'atteint. L'intermédiaire, lui, signe tous les jours, donc il est en ligne et exposé. Compromission de l'intermédiaire : on le révoque, on en signe un nouveau avec la racine, on réémet les certificats ; les clients ne changent rien (ils font confiance à la racine). Compromission de la racine : toute la PKI est à refaire, nouvelle racine à distribuer partout, y compris là où on ne gère rien (postes, appareils) ; et pendant la transition on ne peut plus distinguer les faux certificats des vrais.

**13. Réponse B.** Depuis la RFC 6125 (2011), remplacée par la RFC 9525 (2023), la vérification du nom se fait sur le *Subject Alternative Name* ; le repli sur le CN est abandonné par les clients récents (Chrome depuis 2017, Go depuis 1.15, Python, OpenSSL avec vérification de nom). A et C sont faux pour cette raison ; D confond deux vérifications distinctes : la signature (la chaîne) et le nom, qui doivent réussir **toutes les deux**.

**14. Révocation ou durée courte.** La **révocation** publie la liste des certificats à ne plus croire (CRL) ou répond à la demande (OCSP). En pratique : les clients vérifient mal (beaucoup ignorent l'échec de la vérification, *soft-fail*), OCSP fuit la navigation au répondeur et ajoute un point de panne, les CRL grossissent. Les **certificats courts** (jours ou semaines) limitent la fenêtre d'abus sans aucun mécanisme côté client : un certificat volé meurt de lui-même. Le prix est l'automatisation obligatoire du renouvellement (ACME). L'industrie s'y engage : le CA/Browser Forum a voté la réduction progressive de la durée maximale des certificats publics (jusqu'à 47 jours en 2029), et Let's Encrypt a arrêté OCSP. C'est notre politique : 30 jours en ACME.

**15. Défis ACME.** **HTTP-01** : prouver qu'on contrôle le serveur web du nom ; la CA télécharge un fichier sur `http://NOM/.well-known/acme-challenge/…` (port 80 de la CA vers le serveur). **DNS-01** : prouver qu'on contrôle la zone ; le client publie un TXT `_acme-challenge.NOM`, la CA le lit par le DNS (flux de la CA vers le DNS, rien vers le serveur). **TLS-ALPN-01** : prouver qu'on contrôle le port 443 ; la CA ouvre une connexion TLS avec le protocole ALPN `acme-tls/1` et le serveur présente un certificat spécial. Seul **DNS-01** permet un certificat générique (contrôler la zone prouve qu'on contrôle tous ses noms). On s'en servira en M06-E18, avec l'API de PowerDNS.

**16. Réponse B.** `CA:TRUE` : c'est une autorité, elle peut signer ; `pathlen:0` : **zéro** autorité possible sous elle. Elle signe donc des certificats finaux (serveurs, clients) et rien d'autre : c'est notre intermédiaire. `critical` impose aux clients de comprendre et respecter l'extension. A décrit `CA:TRUE` sans `pathlen` ; C décrit `CA:FALSE` ; D n'a pas de sens.

**Réponses argumentées — SSH**

**17. TOFU et certificats d'hôte.** À la première connexion, le client accepte la clé que présente le serveur et la mémorise (`known_hosts`) ; ensuite, il vérifie qu'elle n'a pas changé. La première connexion n'est donc **pas** vérifiée. Dans un parc où l'on recrée les VMs tous les jours, chaque recréation change la clé : on prend l'habitude de purger `known_hosts` et de répondre « yes » (ou on désactive la vérification), et une attaque de l'homme du milieu passe inaperçue. Un **certificat d'hôte** est la clé de l'hôte signée par une CA SSH, avec les noms de l'hôte et une durée : le client vérifie la signature au lieu de mémoriser des clés. La ligne `@cert-authority *.par1.medisphere.internal ssh-ed25519 AAAA…` dit : « pour tout hôte de ce motif, fais confiance à une clé d'hôte certifiée par cette CA ». M06-E19 le met en place.

**18. Certificats d'utilisateur.** Les *principals* sont les noms de compte (ou de rôle) pour lesquels le certificat est valable : `sshd` refuse la connexion à `admin` si `admin` n'est pas dans la liste (ou dans le fichier `AuthorizedPrincipalsFile`). La période de validité borne l'usage : 16 heures chez nous. Par rapport à `authorized_keys` : plus aucune clé à déposer ni à retirer sur chaque serveur (on fait confiance à la CA, `TrustedUserCAKeys`), un départ ou une clé volée cesse de fonctionner tout seul à l'expiration, et l'émission se fait après une authentification centrale (M06-E20).

**Réponses argumentées — source de vérité et temps**

**19. Source de vérité.** Le référentiel qui fait foi pour une donnée : quand deux systèmes divergent, c'est lui qu'on croit et c'est l'autre qu'on corrige. L'**intention**, c'est ce qui devrait exister (NetBox : « `nbx01` a 4 Go et l'adresse 10.10.20.13 ») ; la **réalité**, c'est ce qui tourne (Proxmox : la VM a 2 Go parce que quelqu'un l'a modifiée à la main). Pour l'adressage et la description du parc, l'intention l'emporte : on corrige Proxmox (par le code). Mais un désaccord peut aussi révéler que l'intention est périmée (une VM créée par OpenTofu absente de NetBox) : il faut alors un processus qui décide, pas un automatisme aveugle. Chez nous, le partage est explicite : OpenTofu fait foi pour les VMs déclarées, NetBox pour l'adressage et la documentation, et une synchronisation compare les deux (M06-E15).

**20. Horloge.** Cessent de fonctionner : la validation des certificats TLS (un certificat émis « dans le futur » est refusé : piège classique d'une CA dont l'horloge avance), Kerberos (5 minutes de tolérance), les codes TOTP, la validation DNSSEC (dates des signatures), les jetons à expiration (JWT, jetons de step-ca), la corrélation des journaux pendant un incident, certains algorithmes distribués (élection, baux). **NTS** (RFC 8915) **authentifie** le serveur de temps (par TLS) et protège l'**intégrité** des réponses NTP : un attaquant sur le chemin ne peut plus décaler l'horloge des clients en falsifiant les paquets. NTP classique n'a aucune authentification pratique (clés symétriques rarement déployées). M06-E21 le met en place.

---

### M06-E02 — Déployer `ca01` et initialiser step-ca

**Solution**

*A. Comprendre avant d'industrialiser.*

1. Le point d'entrée `client` du rôle installe le dépôt Smallstep (clé vérifiée par son empreinte) et le paquet `step-cli` figé : [`roles/step_ca/tasks/client.yml`](fichiers/M06-E02/ansible/roles/step_ca/tasks/client.yml), appliqué par [`playbooks/outils-pki.yml`](fichiers/M06-E02/ansible/playbooks/outils-pki.yml) au groupe `role_bastion`.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-pki.yml
   admin@adm01:~$ step version
   Smallstep CLI/0.31.0 (linux/amd64)
   Release Date: …
   ```
2. Un essai jetable :
   ```
   admin@adm01:~$ export STEPPATH=$(mktemp -d)
   admin@adm01:~$ step ca init --deployment-type standalone --name "Essai" --dns localhost \
       --address 127.0.0.1:8443 --provisioner essai@exemple --acme --ssh
   admin@adm01:~$ find "$STEPPATH" -type f | sort
   ```
   On obtient `certs/root_ca.crt`, `certs/intermediate_ca.crt`, `certs/ssh_host_ca_key.pub`, `certs/ssh_user_ca_key.pub`, `secrets/root_ca_key`, `secrets/intermediate_ca_key`, `secrets/ssh_host_ca_key`, `secrets/ssh_user_ca_key`, `config/ca.json`, `config/defaults.json`. Réponses du journal :
   - **quatre** clés privées (racine, intermédiaire, CA SSH des hôtes, CA SSH des utilisateurs), toutes chiffrées par **le même** mot de passe, celui saisi pendant `init` ; le provisioner JWK a sa propre clé, chiffrée par un mot de passe que `init` fait par défaut identique ;
   - la clé de la **racine** est dans `secrets/`, à côté de celle de l'intermédiaire, sur la machine qui fera tourner la CA ;
   - dans `ca.json`, le provisioner JWK porte `key` (la clé **publique**, qui vérifie les jetons signés par le client) et `encryptedKey` (la clé **privée**, chiffrée au format JWE compact) : la CA la publie sur `/provisioners`, et le client `step` la récupère et la déchiffre avec le mot de passe pour signer ses demandes ;
   - `defaults.json` est la configuration du **client** : URL de la CA, empreinte de la racine, chemin du certificat racine ; c'est ce qu'écrit `step ca bootstrap`.
3. Inadapté à la production : la racine est **en ligne** (sur le disque de la machine exposée), un seul mot de passe protège toutes les clés, il est en clair dans un fichier si on veut un démarrage automatique (`password.txt`), le service tourne sous l'utilisateur qui l'a lancé, sans unité systemd ni durées définies. `rm -rf "$STEPPATH"; unset STEPPATH`.

*B. La cérémonie.* Le script [`adm01/ceremonie-pki.sh`](fichiers/M06-E02/adm01/ceremonie-pki.sh) encapsule les commandes et les contrôles :
```
admin@adm01:~$ ceremonie-pki.sh racine
Phrase de passe de la racine : saisis-la deux fois ; range-la dans le gestionnaire de mots de passe.
…
Empreinte SHA-256 : 3c4a…e91f
admin@adm01:~$ ceremonie-pki.sh archiver
admin@adm01:~$ ceremonie-pki.sh verifier
OK  /home/admin/pki-racine en 700
OK  clé de la racine présente et chiffrée
OK  racine auto-signée valide
OK  au moins une archive chiffrée
```
Le cœur, sans le script :
```
umask 077; install -d -m 700 ~/pki-racine
step certificate create "MédiSphère Root CA" ~/pki-racine/medisphere-root-ca.crt \
  ~/pki-racine/medisphere-root-ca.key --profile root-ca --kty EC --curve P-384 --not-after 87600h
step certificate fingerprint ~/pki-racine/medisphere-root-ca.crt
tar -C ~/pki-racine --exclude=archives -cf - . | gpg --symmetric --cipher-algo AES256 \
  --output ~/pki-racine/archives/pki-racine-AAAAMMJJ.tar.gpg
cp ~/pki-racine/medisphere-root-ca.crt ~/src/ansible/pki/
```
Pas de `--password-file` ni de `--no-password` : la phrase de passe est demandée au terminal et ne touche jamais le disque. Le procès-verbal `docs/socle/pki/ceremonie-racine.md` reprend : date, participants (toi seul au lab ; deux personnes en production), version de `step`, commandes, empreinte, emplacements (dossier, archive, support amovible, PBS), détenteurs des deux phrases.

*C. La machine.* [`infra/socle/ca01.tf`](fichiers/M06-E02/infra/socle/ca01.tf) (VMID 1003, `role = "pki"`, protection, rang 3) ; nom dans le DNS du moment : [`group_vars/role_dns/dnsmasq-extrait.yml`](fichiers/M06-E02/ansible/inventories/lab/group_vars/role_dns/dnsmasq-extrait.yml). Puis `dig +short ca01.par1.medisphere.internal`, `dig +short -x 10.10.20.11`, `ssh-keyscan` vers le `known_hosts` du projet, `uv run ansible-inventory --graph role_pki`.

*D. Le provisioner `admin`.*
```
admin@adm01:~$ install -d -m 700 ~/.config/workbook
admin@adm01:~$ (umask 077; openssl rand -base64 24 > ~/.config/workbook/step-admin.pass)
admin@adm01:~$ cd "$(mktemp -d)"
admin@adm01:/tmp/tmp.X$ step crypto jwk create admin.pub.json admin.key.json --kty EC --crv P-256 \
    --use sig --password-file ~/.config/workbook/step-admin.pass
admin@adm01:/tmp/tmp.X$ step crypto jose format < admin.key.json     # forme compacte : eyJ…
```
Le contenu de `admin.pub.json` (`kty`, `crv`, `kid`, `x`, `y`, `use`, `alg`) va dans [`group_vars/role_pki/step_ca.yml`](fichiers/M06-E02/ansible/inventories/lab/group_vars/role_pki/step_ca.yml) ; la forme compacte dans `vault_step_ca_admin_cle_chiffree` ([modèle](fichiers/M06-E02/ansible/inventories/lab/group_vars/role_pki/vault-critique.yml.exemple)), chiffré avec `--encrypt-vault-id critique`. Puis suppression du dossier temporaire. Réponse : cette clé est **chiffrée** par un mot de passe qui n'est jamais sur `ca01`, et elle ne permet que de **demander** des certificats à la CA, dans les limites de ses *claims* (90 jours) ; la CA la publie d'ailleurs à qui la demande. La clé de la racine, elle, permet de **fabriquer** une autorité : elle ne doit être sur aucune machine en ligne, chiffrée ou non.

*E. Le rôle.* [`roles/step_ca/`](fichiers/M06-E02/ansible/roles/step_ca/) : `depot.yml`, `paquets.yml`, `arborescence.yml`, `pki.yml` (refus d'une clé de racine, clé et CSR de l'intermédiaire générées sur l'hôte, rapatriement de la CSR puis `meta: end_host`, correspondance clé/certificat, clés de la CA SSH), `configuration.yml` (`ca.json` produit par `to_nice_json`, unité systemd, redémarrage, contrôle de santé, `rescue` qui remet la configuration précédente). Scénario Molecule [`molecule/step_ca/`](fichiers/M06-E02/ansible/molecule/step_ca/) : `prepare.yml` joue la cérémonie en miniature avec des secrets jetables (racine de test, intermédiaire signé, clé JWK), rapatrie les pièces publiques dans le dossier éphémère du scénario et **supprime la clé de la racine de test** de l'instance ; `converge.yml` applique le rôle avec ces pièces ; `verify.yml` contrôle le service (sous `step`), l'absence de clé de racine, `/health`, l'annuaire ACME, `/ssh/roots`, une émission de 30 jours vérifiée jusqu'à la racine et le **refus** d'une durée de 100 jours. Le scénario ne rejoue pas l'arrêt de phase 1 (testé à la main à la rédaction) : c'est une piste d'amélioration (un second scénario `step_ca_phase1`).

Phase 1 sur `ca01` :
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ca01.yml
…
TASK [step_ca : Phase 1 — consigne] ***
ok: [ca01] => msg: CSR de l'intermédiaire prête : …/pki/medisphere-intermediate-ca.csr. Signe-la avec la racine hors ligne …
PLAY RECAP ***
ca01 : ok=… changed=… failed=0
admin@adm01:~/src/ansible$ step certificate inspect pki/medisphere-intermediate-ca.csr --short
admin@adm01:~/src/ansible$ ceremonie-pki.sh signer pki/medisphere-intermediate-ca.csr
admin@adm01:~/src/ansible$ step certificate inspect pki/medisphere-intermediate-ca.crt | grep -A1 "Basic Constraints"
            X509v3 Basic Constraints: critical
                CA:TRUE, pathlen:0
admin@adm01:~/src/ansible$ git add pki/ && git commit -m "feat(pki): intermédiaire signé par la racine"
```
Phase 2 (après MR et pipeline) : le rôle trouve le certificat, vérifie qu'il est signé par la racine et qu'il correspond à la clé de l'hôte, écrit `ca.json`, démarre `step-ca`.

*F. Vérifier en client.*
```
admin@adm01:~$ step ca bootstrap --ca-url https://ca01.par1.medisphere.internal \
    --fingerprint 3c4a…e91f
admin@adm01:~$ step ca health
ok
admin@adm01:~$ step certificate inspect https://ca01.par1.medisphere.internal --short --roots "$(step path)/certs/root_ca.crt"
admin@adm01:~$ curl -s --cacert ~/src/ansible/pki/medisphere-root-ca.crt \
    https://ca01.par1.medisphere.internal/provisioners | jq -r '.provisioners[] | "\(.type) \(.name)"'
JWK admin
ACME acme
SSHPOP sshpop
admin@adm01:~$ curl -s --cacert ~/src/ansible/pki/medisphere-root-ca.crt \
    https://ca01.par1.medisphere.internal/acme/acme/directory | jq .newOrder
"https://ca01.par1.medisphere.internal/acme/acme/new-order"
```
Le certificat TLS que présente la CA elle-même (sujet « Step Online CA », 24 heures) est émis par l'intermédiaire et renouvelé par step-ca : ne t'étonne pas de sa durée.

Certificat de test :
```
admin@adm01:~$ cd "$(mktemp -d)"
admin@adm01:/tmp/tmp.Y$ step ca certificate test.par1.medisphere.internal test.crt test.key \
    --provisioner admin --provisioner-password-file ~/.config/workbook/step-admin.pass --not-after 720h
admin@adm01:/tmp/tmp.Y$ step certificate inspect test.crt --short
admin@adm01:/tmp/tmp.Y$ step certificate verify test.crt --roots ~/src/ansible/pki/medisphere-root-ca.crt
admin@adm01:/tmp/tmp.Y$ step ca certificate test.par1.medisphere.internal test2.crt test2.key \
    --provisioner admin --provisioner-password-file ~/.config/workbook/step-admin.pass --not-after 2400h
```
La seconde demande est refusée : le message (sur la sortie d'erreur) indique que la durée (*duration*) demandée dépasse le maximum autorisé par le provisioner (2160 h) ; ⚠️ sa formulation exacte varie selon les versions. `step certificate verify` ne dit rien en cas de succès (code retour 0). Puis `rm -r` du dossier.

13. La matrice des flux ne change pas : `ca01` est dans `vinfra`, joint par `adm01` (VLAN ADMIN → INFRA, déjà ouvert pour les hôtes du socle en 443 et 22) et, plus tard, par les hôtes du socle (même VLAN). Si ta matrice ouvre hôte par hôte plutôt que par VLAN, ajoute les lignes 443 et 22 vers 10.10.20.11.

Le check vérifie la VM, la racine, l'intermédiaire, l'absence de clé de racine sur `ca01`, la santé, les provisioners et les durées.

**Explications**

- **Pourquoi deux passages.** La clé de l'intermédiaire naît sur `ca01` et n'en sort jamais ; seule la CSR (publique) voyage. La signature exige la racine, donc un humain et sa phrase de passe sur `adm01` : le rôle ne peut pas l'automatiser, et ne doit pas. `meta: end_host` arrête le rôle pour cet hôte sans le marquer en échec : le pipeline reste vert, la consigne s'affiche, et le passage suivant reprend où il s'était arrêté.
- **CSR et sujet accentué.** `step certificate create --csr NOM` met aussi `NOM` dans les SAN, qui sont de type *IA5String* (ASCII) : « MédiSphère Intermediate CA » est refusé. Le modèle [`csr-intermediaire.json.j2`](fichiers/M06-E02/ansible/roles/step_ca/templates/csr-intermediaire.json.j2) ne décrit que le sujet.
- **`ca.json` en structure.** Construit comme un dictionnaire Jinja et sérialisé par `to_nice_json` : pas de virgule oubliée, et les provisioners sont une liste de l'inventaire. La validation passe par le démarrage du service et `/health` (step-ca n'a pas de mode « vérifier la configuration »), d'où le `block`/`rescue` qui remet la sauvegarde.
- **Claims.** Les durées globales (`authority.claims`) bornent tout ; chaque provisioner peut les restreindre. `admin` : 90 jours au plus, 30 par défaut, CA SSH activée. `acme` : 30 jours. Les durées SSH (hôtes 720 h, utilisateurs 16 h) sont globales.
- **Commandes `step` en root, puis `chown`.** Lancer `step` sous `step` avec `become_user` fait écrire à Ansible ses fichiers temporaires dans le dossier personnel du compte de service (`/etc/step-ca`) : on exécute en root et on rend la propriété ensuite.

**Alternatives**

- **`step ca init` puis déplacer la racine** hors de la machine : plus simple, documenté par Smallstep, mais la racine a existé sur la machine en ligne (dans ses fichiers, peut-être ses sauvegardes) : refusé pour l'audit HDS.
- **Racine dans un HSM ou une YubiKey** (`step-kms-plugin`) : la clé n'existe jamais en fichier. C'est la cible en production ; au lab, une clé chiffrée hors ligne suffit.
- **OpenSSL seul** pour la cérémonie : tout à fait possible (fichier de configuration, `req`, `ca`), plus verbeux ; `step` produit des profils corrects par défaut.
- **HashiCorp Vault (moteur PKI)** à la place de step-ca : plus large (secrets, PKI, SSH), plus lourd à exploiter (déverrouillage, stockage, haute disponibilité). Smallstep est le choix du plan : ACME, SSH, provisioners, sobriété.

**Pièges classiques**

- Générer la racine **avant** d'avoir fixé `umask` et les droits du dossier : la clé existe un instant en 644.
- Oublier `--profile root-ca` : le certificat n'a pas `CA:TRUE` et rien ne peut être signé avec.
- Signer l'intermédiaire sans `--path-len 0` : il pourrait créer d'autres autorités.
- Mettre l'empreinte de l'intermédiaire au lieu de celle de la racine dans `step ca bootstrap`.
- Copier `secrets/` d'un `step ca init` d'essai : tu embarques une racine en ligne.
- Laisser `step-admin.pass` ailleurs que dans `~/.config/workbook/` en 600, ou l'afficher dans un journal de CI.

**En production chez MédiSphère**

Cérémonie à deux personnes (au moins), sur un poste dédié jamais connecté, racine dans deux HSM ou YubiKey, phrase partagée (Shamir), procès-verbal signé, archive dans deux coffres. Supervision de `ca01` (santé, échéance de l'intermédiaire, nombre d'émissions), journaux d'émission envoyés au SIEM, base de step-ca (`db/`) sauvegardée.

---

### M06-E03 — Faire confiance à la nouvelle PKI

**Solution**

1. **Inventaire** (exemple de résultat, à compléter avec ce que tu as trouvé) :

   | Endroit | Comment il apprend une autorité |
   |---|---|
   | Magasin système Debian (tous les hôtes, `adm01` compris) | `/usr/local/share/ca-certificates/*.crt` + `update-ca-certificates` (rôle `ca_lab`) |
   | `git`, `curl`, `apt`, OpenSSL, Go (OpenTofu, gitlab-runner, Packer) | magasin système (`/etc/ssl/certs/ca-certificates.crt`) |
   | Python `requests` (proxmoxer, tes scripts) | **son propre magasin** (`certifi`) sauf `REQUESTS_CA_BUNDLE` ou `verify=` ; nos scripts désignent le magasin système |
   | Node.js (commitlint, semantic-release) | son magasin intégré + `NODE_EXTRA_CA_CERTS` |
   | GitLab (services embarqués) | `/etc/gitlab/trusted-certs/` + `gitlab-ctl reconfigure` |
   | gitlab-runner, conteneurs des jobs | magasin du runner (rôle `gitlab_runner`), images de jobs (variables `CA_BUNDLE`, montage) |
   | Image dorée | `plateforme/images`, `fichiers/ca/` (M03-E09) |
   | Fournisseur `proxmox` d'OpenTofu, `ansible.cfg` | magasin système ou option `ca_path`/`insecure` à vérifier |

2. **Le rôle.** [`ca_lab`](fichiers/M06-E03/ansible/collections/ansible_collections/medisphere/socle/roles/ca_lab/) : `ca_lab_certificats` (par défaut la racine MédiSphère, depuis `pki/`), `ca_lab_retirer` (noms à enlever), `update-ca-certificates --fresh` quand on retire, vérification que chaque autorité voulue est dans le magasin consolidé et qu'aucune retirée n'y reste. Version **1.1.0** : on ajoute une fonction (retirer) et on change une valeur par défaut sans casser les appels existants (un appel avec `ca_lab_certificats` explicite fonctionne pareil) ; pas de suppression ni de renommage de variable. [`CHANGELOG.md`](fichiers/M06-E03/ansible/collections/ansible_collections/medisphere/socle/CHANGELOG.md), [`galaxy.yml`](fichiers/M06-E03/ansible/collections/ansible_collections/medisphere/socle/galaxy.yml). Le rôle est ajouté aux rôles communs ([`playbooks/socle-base.yml`](fichiers/M06-E03/ansible/playbooks/socle-base.yml), étiquette `pki`) avec [`group_vars/all/pki.yml`](fichiers/M06-E03/ansible/inventories/lab/group_vars/all/pki.yml) ; [`gitlab_runner/tasks/ca.yml`](fichiers/M06-E03/ansible/roles/gitlab_runner/tasks/ca.yml) suit. Pendant le recouvrement, `ca_lab_retirer` est vide et les deux autorités sont installées (la provisoire par l'ancien appel, la nouvelle par le rôle commun).

3. **Recouvrement.** Sur chaque hôte : `grep -c "$(sed -n 2p pki/medisphere-root-ca.crt)" /etc/ssl/certs/ca-certificates.crt` (ou `openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt pki/medisphere-intermediate-ca.crt`). Pour GitLab : copie de la racine dans `/etc/gitlab/trusted-certs/medisphere-root-ca.crt`, puis `gitlab-ctl reconfigure` dans le créneau annoncé, après l'instantané, puis `gitlab-ctl status` (⚠️ à vérifier sur ta version de GitLab : la documentation « Install custom public certificates » décrit ce dossier et l'effet de `reconfigure`).

4. **Bascule des certificats** avec [`adm01/emettre-certificat.sh`](fichiers/M06-E03/adm01/emettre-certificat.sh) :
   ```
   admin@adm01:~$ emettre-certificat.sh git01 10.10.20.12
   admin@adm01:~$ emettre-certificat.sh s3-01 10.10.20.14
   ```
   `git01` : copie de `git01.crt` (certificat + intermédiaire) et `git01.key` vers `/etc/gitlab/ssl/git01.par1.medisphere.internal.{crt,key}` (600 pour la clé), `gitlab-ctl hup nginx`. `s3-01` : certificat dans le dépôt Ansible, clé dans Vault, rôle `seaweedfs` par le pipeline. Vérification avec la seule nouvelle racine :
   ```
   admin@adm01:~$ openssl s_client -connect git01.par1.medisphere.internal:443 -servername git01.par1.medisphere.internal \
       -CAfile ~/src/ansible/pki/medisphere-root-ca.crt -verify_return_error </dev/null 2>&1 | grep -E "Verify return|issuer"
   admin@adm01:~$ curl -sS --cacert ~/src/ansible/pki/medisphere-root-ca.crt -o /dev/null -w '%{http_code}\n' https://s3-01.par1.medisphere.internal:8333/
   ```
   puis depuis `runner01` (même commande), un `tofu plan` de l'état `socle` et un pipeline. Supprime ensuite les clés de `~/m06/certs/`. Échéance notée dans l'inventaire (`# expire le …`).
5. **Images** : dans `plateforme/images`, remplace le fichier de `fichiers/ca/` par `medisphere-root-ca.crt` (et son nom dans le gabarit Packer), MR, pipeline, publication `current`. Contrôle sur une VM neuve : `ls /usr/local/share/ca-certificates/`.
6. **Retrait** : `ca_lab_retirer: [medisphere-provisoire]` (déjà prévu dans `group_vars/all/pki.yml`), suppression de l'appel « provisoire » de `gitlab_runner`, passage des rôles communs par le pipeline ; retrait du fichier de `/etc/gitlab/trusted-certs/` puis `gitlab-ctl reconfigure`. Archive :
   ```
   admin@adm01:~$ tar -C ~ -cf - pki-provisoire | gpg --symmetric --cipher-algo AES256 -o ~/pki-racine/archives/pki-provisoire-AAAAMMJJ.tar.gpg
   admin@adm01:~$ shred -u ~/pki-provisoire/*.key
   ```
7. **Documentation** : `docs/socle/pki/magasins-de-confiance.md`, le tableau ci-dessus à jour, avec pour chaque ligne le fichier de code qui le gère.

**Explications**

- **L'ordre fait tout.** Confiance d'abord (aucun client ne refuse les nouveaux certificats), puis certificats (les services basculent un par un, retour arrière simple : remettre l'ancien certificat), retrait enfin (quand plus rien ne présente l'ancienne chaîne). À l'envers : un service qui présente un certificat MédiSphère à un client qui ne connaît que la provisoire tombe.
- **`--fresh`.** Sans lui, `update-ca-certificates` ajoute les nouveaux fichiers et retire les liens des fichiers disparus ; le magasin consolidé est bien reconstruit, mais `--fresh` rend le résultat indépendant de l'historique (liens orphelins compris). Le rôle ne l'utilise que lorsqu'il retire quelque chose, pour rester idempotent.
- **Prouver avec la seule racine.** `curl` sans option réussirait aussi avec la CA provisoire tant qu'elle est dans le magasin : la preuve exige `--cacert`/`-CAfile` avec un seul fichier.
- **GitLab.** Ses services embarqués (Workhorse, Gitaly, Rails) utilisent le magasin du dossier `/opt/gitlab/embedded/ssl/certs`, alimenté depuis `trusted-certs` par `reconfigure`. Sans la racine, l'intégration de GitLab avec `s3-01` ou une future authentification OIDC échouerait.

**Alternatives**

- Déposer la racine par cloud-init plutôt que dans l'image : pas besoin de reconstruire l'image, mais une VM sans cloud-init (ou avant son exécution) n'a pas la confiance.
- Faire signer la nouvelle racine par la provisoire (*cross-signing*) : les anciens clients suivraient sans changement ; utile pour des clients qu'on ne gère pas, inutilement compliqué ici.

**Pièges classiques**

- Fichier sans extension `.crt` dans `/usr/local/share/ca-certificates/` : ignoré silencieusement.
- Certificat serveur sans l'intermédiaire : `curl` échoue, le navigateur (qui a l'intermédiaire en cache) réussit.
- Oublier `REQUESTS_CA_BUNDLE`/`verify` dans un script Python : il utilise `certifi` et refuse la racine interne.
- Retirer la CA provisoire avant d'avoir publié la nouvelle image : la prochaine VM n'a confiance en rien.

**En production chez MédiSphère**

La liste des magasins est un document vivant, revu à chaque nouveau composant (y compris les postes des équipes, gérés par l'informatique interne). Les échéances des certificats émis à la main sont supervisées (`blackbox_exporter`, M07) en attendant ACME.

---

### M06-E04 — Déployer NetBox sur `nbx01`

**Solution**

1. Réponses du journal. Écarts Debian 13 : Python 3.13 (pris en charge par NetBox 4.6), PostgreSQL 17 (paquet `postgresql`), Valkey 8 (`valkey-server`) à la place de Redis, compatible au niveau du protocole, configuré dans la section `REDIS` ; `python3-venv` et les en-têtes de compilation (`libpq-dev`, `libssl-dev`…) selon la liste de la documentation. Paramètres obligatoires : `ALLOWED_HOSTS`, `DATABASES` (forme actuelle de `configuration_example.py` ; les anciennes versions utilisaient `DATABASE`), `REDIS` (`tasks` et `caching`), `SECRET_KEY` (au moins 50 caractères), et `API_TOKEN_PEPPERS` pour les jetons v2. **Poivres** : un jeton v2 (`nbt_<clé>.<jeton>`) est stocké sous forme d'empreinte HMAC calculée avec un poivre ; seule la partie « clé » est en clair (pour retrouver la ligne). La base seule ne permet donc ni de lire ni de vérifier un jeton. Perdre les poivres : tous les jetons v2 deviennent invérifiables, il faut les réémettre.
2. [`infra/socle/nbx01.tf`](fichiers/M06-E04/infra/socle/nbx01.tf) (1005, 2 vCPU, 4096 Mo, 30 Go, rang 6), nom dans dnsmasq, `known_hosts`, `ansible-inventory --graph role_netbox`.
3. `emettre-certificat.sh nbx01 10.10.20.13` ; `nbx01.crt` → `pki/certs/nbx01.crt` du projet Ansible ; la clé → `vault_netbox_tls_cle` (`ansible-vault encrypt_string --encrypt-vault-id critique --stdin-name vault_netbox_tls_cle < ~/m06/certs/nbx01.key`), puis `shred -u ~/m06/certs/nbx01.key`.
4. Rôle [`roles/netbox/`](fichiers/M06-E04/ansible/roles/netbox/) :
   - `paquets.yml` : PostgreSQL, Valkey, nginx, dépendances de compilation ;
   - `postgresql.yml` : rôle et base créés par `psql` en `postgres`, mot de passe passé par `-v` et un script sur l'entrée standard (jamais en argument) ;
   - `application.yml` : clone Git de l'étiquette dans `/opt/netbox-4.6.9`, **refus** si `git rev-parse HEAD` ≠ `netbox_commit`, `configuration.py` (modèle [`configuration.py.j2`](fichiers/M06-E04/ansible/roles/netbox/templates/configuration.py.j2), `root:netbox` 640, validé par `python3 -m py_compile`), `upgrade.sh` lancé seulement si le venv de la version n'existe pas (`creates`), lien `/opt/netbox`, super-utilisateur créé une fois (`createsuperuser --no-input`, mot de passe dans `DJANGO_SUPERUSER_PASSWORD`, `no_log`) ;
   - `services.yml` : unités `netbox` (gunicorn sur 127.0.0.1:8001) et `netbox-rq`, contrôle que Valkey n'écoute que sur la boucle locale ;
   - `nginx.yml` : site TLS, redirection 80 → 443, `nginx -t` sur l'ensemble avant rechargement ;
   - `verifications.yml` : `/login/` en HTTPS **vérifié** par la racine MédiSphère, `/api/status/`.

   Inventaire : [`group_vars/role_netbox/netbox.yml`](fichiers/M06-E04/ansible/inventories/lab/group_vars/role_netbox/netbox.yml) et les deux modèles Vault ([critique](fichiers/M06-E04/ansible/inventories/lab/group_vars/role_netbox/vault-critique.yml.exemple), [lab](fichiers/M06-E04/ansible/inventories/lab/group_vars/role_netbox/vault.yml.exemple)). Pour générer les secrets : `python3 -c 'import secrets; print(secrets.token_urlsafe(50))'` pour `SECRET_KEY` (le script `netbox/generate_secret_key.py` du dépôt fait de même) et pour chaque poivre. Molecule : [`molecule/netbox/`](fichiers/M06-E04/ansible/molecule/netbox/) (CA de test fabriquée par `prepare.yml`, instance 4 Go).
5. Connexion `admin`, menu « Admin » → « Users » → ajout de ton compte (cases *staff*/*superuser*), déconnexion.
6. « Admin » → « Groups » : `lecture-seule` ; « Admin » → « Permissions » : `lecture-tout`, actions *view* seulement, tous les types d'objets, groupe `lecture-seule` ; utilisateur `wb-checks` dans ce groupe. Jeton : connecté en `admin` (ou ton compte), « Admin » → « API Tokens » → ajout pour `wb-checks`, version 2, **écriture désactivée**, expiration (par exemple 90 jours). La valeur `nbt_….…` n'est affichée qu'une fois :
   ```
   admin@adm01:~$ (umask 077; cat > ~/.config/workbook/netbox-checks.token)   # coller, Entrée, Ctrl+D
   admin@adm01:~$ curl -sS -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-checks.token)" \
       https://nbx01.par1.medisphere.internal/api/status/ | jq '{"netbox-version", "python-version", "rq-workers-running"}'
   {
     "netbox-version": "4.6.9",
     "python-version": "3.13.5",
     "rq-workers-running": 1
   }
   admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-checks.token)" \
       -H 'Content-Type: application/json' -d '{"name":"essai","slug":"essai"}' https://nbx01.par1.medisphere.internal/api/dcim/sites/
   403
   ```
   ⚠️ L'emplacement exact des menus peut varier selon la version 4.6.x : la documentation « REST API → Authentication » fait foi.

**Explications**

- **Installation par version.** `/opt/netbox-4.6.9` + lien `/opt/netbox` : la version suivante se prépare à côté (clone, venv, `collectstatic`), et la bascule est le changement du lien suivi des migrations et du redémarrage. Le venv de la version est le témoin d'installation (`upgrade.sh` le recrée à chaque exécution : on ne le relance pas inutilement).
- **Commit vérifié.** Une étiquette Git peut être déplacée (ou un miroir modifié) : comparer au commit attendu, relevé une fois par `git ls-remote`, rend l'installation reproductible et prouvée.
- **`postgresql.service` est un parapluie.** Sous Debian, c'est une unité *oneshot* ; le vrai serveur est `postgresql@17-main`. Le rôle et le check vérifient la seconde.
- **Pourquoi `configuration.py` en 640.** Il contient `SECRET_KEY` (signature des sessions : la connaître permet de fabriquer une session administrateur), les poivres et le mot de passe de la base.

**Alternatives**

- **netbox-docker** : déploiement rapide et montée de version par image, au prix d'une couche de plus (images, volumes, Compose) ; le ticket demande l'installation documentée.
- **Collection `community.postgresql`** pour la base : plus lisible que `psql`, une dépendance de plus (et `psycopg2` sur l'hôte).
- **Redis au lieu de Valkey** : NetBox l'utilise de la même façon ; le plan retient Valkey, *fork* sous licence BSD né du changement de licence de Redis en 2024.

**Pièges classiques**

- `ALLOWED_HOSTS` sans le FQDN : erreur 400 « Bad Request » derrière nginx.
- Oublier `proxy_set_header X-Forwarded-Proto` : redirections vers `http://` en boucle.
- Lancer `upgrade.sh` sous root : le venv appartient à root, le service `netbox` ne peut plus écrire ses fichiers statiques.
- Jeton copié avec un saut de ligne ou une espace : 403 « Invalid token ». Le check le lit avec `tr -d '[:space:]'`.
- Créer `wb-checks` super-utilisateur « pour aller plus vite » : le jeton sans écriture limite l'API, mais le compte reste dangereux.

**En production chez MédiSphère**

Sauvegarde PostgreSQL (`pg_dump` quotidien, chiffré, vers `s3-01`) et de `media/` ; montée de version rejouée d'abord sur un clone de la base ; authentification par l'annuaire (SSO, M10) ; supervision de `/api/status/` (nombre de *workers*) et de l'échéance du certificat.

---

### M06-E05 — Modéliser MédiSphère dans NetBox

**Solution**

1. Exploration : un site exige un nom, un slug et un statut ; un préfixe n'exige que `prefix` et `status`, mais son rattachement (site, VLAN, rôle, locataire) est ce qui le rend utile. Dans l'API, un champ lié se lit `{"id": 3, "url": …, "display": …, "name": "PAR1", "slug": "par1"}` mais s'écrit avec l'identifiant (`"site": 3`) ; un champ à choix se lit `{"value": "active", "label": "Active"}` et s'écrit `"active"` ; les étiquettes se lisent comme une liste d'objets et s'écrivent `[{"slug": "socle"}]` (ou leurs identifiants).
2. Données : [`outils/netbox/modele-medisphere.yml`](fichiers/M06-E05/outils/netbox/modele-medisphere.yml) — région, locataire, sites, baies, fabricants, types et rôles d'équipements, équipements, type de cluster, cluster (`scope_type: dcim.site`), champ personnalisé `vmid`, étiquettes, rôles IPAM, groupe et VLAN, préfixes (13 /24 de PAR1, PAR2, interconnexion, VPN), plages, VMs, interfaces, adresses. ⚠️ Remplace les ressources des VMs par celles relevées dans Proxmox si elles diffèrent.
3. Script : [`outils/netbox/modeliser.py`](fichiers/M06-E05/outils/netbox/modeliser.py) (PEP 723, `requests` et `pyyaml`). Une classe `NetBox` avec `assurer(point, cle, voulu)` : cherche par filtre de clé naturelle, crée (`+`), compare **seulement** les champs voulus après normalisation (objets imbriqués → identifiant, choix → `value`, étiquettes → ensemble de slugs) et envoie un `PATCH` des seuls champs différents (`~`), ou ne fait rien (`=`). L'IP primaire est posée en dernier.
4. Exécution :
   ```
   admin@adm01:~/src/outils/netbox$ export NETBOX_TOKEN_FILE=~/.config/workbook/netbox-moi.token
   admin@adm01:~/src/outils/netbox$ uv run modeliser.py --dry-run
   admin@adm01:~/src/outils/netbox$ uv run modeliser.py
   …
   Bilan : 167 créé(s), 0 modifié(s), 0 inchangé(s)
   admin@adm01:~/src/outils/netbox$ uv run modeliser.py
   …
   Bilan : 0 créé(s), 0 modifié(s), 167 inchangé(s)
   ```
   (Chiffres obtenus sur une base vide ; avec tes objets de l'étape 1, quelques `=` ou `~` remplacent des `+`.) Les objets faits à la main sont **repris**, pas dupliqués, si leur clé naturelle (slug, `vid` dans le groupe, préfixe) est celle du fichier ; un slug différent (`par-1` au lieu de `par1`) donne un doublon : supprime l'objet manuel.
   Le script lit par défaut `netbox-auto.token` : c'est le jeton du compte de service qui arrive en M06-E10 ; pour cet exercice, `NETBOX_TOKEN_FILE` désigne ton jeton personnel.
5. Contrôles dans l'interface : « IPAM → Prefixes » (colonne *Utilization*), chaque VM (onglet *Interfaces*, IP primaire), « IP Ranges » filtrées par rôle. MR dans `plateforme/outils` (pipeline : `ruff`, ShellCheck).

**Explications**

- **Clé naturelle** : ce qui identifie un objet pour un humain et ne change pas (slug, nom dans un parent, préfixe dans un VRF, VID dans un groupe). L'identifiant numérique de NetBox change d'une base à l'autre : il ne peut pas être une clé dans un fichier de données rejouable.
- **Comparer ce qu'on décrit, pas tout.** Un `PATCH` systématique serait idempotent sur l'état, mais rapporterait toujours « modifié » et effacerait le journal des modifications de NetBox (chaque écriture y laisse une entrée). Comparer seulement les champs décrits laisse un humain renseigner les autres (description, commentaires) sans que le script les écrase.
- **`scope_type`/`scope_id`.** Depuis NetBox 4.2, un cluster, un préfixe ou un groupe de VLAN se rattache à un site, une région, une localisation… par un couple type/identifiant générique, plus par un champ `site`.

**Alternatives**

- **Collection `netbox.netbox`** (modules Ansible `netbox_*`) : idempotence fournie, pas de code HTTP ; une tâche par type d'objet, moins souple pour les relations, et une dépendance de collection à suivre au rythme de NetBox.
- **pynetbox** : client Python de l'API, pratique, mais l'idempotence reste à écrire.
- **Import CSV/YAML de l'interface** (*bulk import*) : parfait pour un chargement initial, ne sait ni comparer ni corriger.
- **Data sources + scripts NetBox** : le code tourne **dans** NetBox (accès ORM, transactions) ; plus puissant, mais déployé avec l'application.

**Pièges classiques**

- Ordre de création : l'interface d'une VM avant la VM, l'IP primaire avant l'interface.
- Comparer `"active"` à `{"value": "active", …}` : le script croit à une différence à chaque passage.
- Mémoire en Go au lieu de Mo (`memory: 4` pour 4 Go) ; disque en Go dans les versions antérieures à 4.1, en Mo depuis.
- Couleurs d'étiquettes non quotées en YAML (`0f0f0f` reste une chaîne, mais `000000` devient l'entier 0) : d'où les guillemets.
- Jeton affiché en mode `--debug` ou dans un message d'exception.

**En production chez MédiSphère**

Le fichier de données devient un **amorçage** : à partir du palier 2, NetBox est alimenté par la synchronisation (OpenTofu → NetBox, M06-E15) et par ses utilisateurs ; un passage du script en `--dry-run` dans la CI sert de contrôle de dérive.

---

### M06-E06 — PowerDNS Authoritative sur `dns01`

**Solution**

1. Lecture. À l'installation, `pdns-server` installe `/etc/powerdns/pdns.conf` (minimal, `include-dir=/etc/powerdns/pdns.d`), **démarre** le service `pdns`, et ses recommandations installent `pdns-backend-bind`, qui dépose `pdns.d/bind.conf` (`launch+=bind`) : le serveur démarre sur le **port 53**, ce qui échoue (dnsmasq l'occupe) ou, pire, le prend si dnsmasq redémarre à ce moment. `api=yes` démarre aussi le serveur web (pas besoin de `webserver=yes`). `pdnsutil` 5.0 : forme objet-verbe (`pdnsutil zone create`, `zone list-all`, `zone show`, `zone load`, `zone rectify`, `zone check`, `metadata get|set`), les anciennes formes restant acceptées pour l'instant.
2. Liste unique : [`group_vars/role_dns/dns.yml`](fichiers/M06-E06/ansible/inventories/lab/group_vars/role_dns/dns.yml) (`dns_hotes`, avec `a: false` pour les PTR seuls de `gw01`) ; `dnsmasq_hotes` en est dérivé. `uv run ansible-playbook playbooks/dns01.yml --check --diff --tags dnsmasq` : aucune différence.
3. Rôle [`roles/powerdns_auth/`](fichiers/M06-E06/ansible/roles/powerdns_auth/) :
   - `paquets.yml` : clé téléchargée et empreinte comparée à la valeur attendue avant d'être déposée, source APT avec `signed-by`, épinglage `Pin-Priority: 600` ; `policy-rc.d` (code 101) posé **seulement** si les paquets ne sont pas encore installés et retiré aussitôt ; `install_recommends: false` ;
   - [`templates/medisphere.conf.j2`](fichiers/M06-E06/ansible/roles/powerdns_auth/templates/medisphere.conf.j2) dans `pdns.d/` : `launch+=gsqlite3`, base, `gsqlite3-dnssec=yes`, `local-address`, `api`, `api-key`, `webserver-address`, `webserver-allow-from`, `default-soa-content` ; pas de `bind.conf`, puisque le backend `bind` (recommandation du paquet) n'est jamais installé ;
   - base : `sqlite3 … < /usr/share/pdns-backend-sqlite3/schema/schema.sqlite3.sql` (`creates`), propriétaire `pdns`, dossier en `pdns` pour les fichiers `-journal`/`-wal` ;
   - `zones.yml` : `pdnsutil zone create` si la zone manque (puis redémarrage, voir Explications) ; pour les zones `contenu: fichier`, fichier BIND généré par [`zone.j2`](fichiers/M06-E06/ansible/roles/powerdns_auth/templates/zone.j2) avec `@SERIAL@`, chargé par [`files/pdns-charger-zone`](fichiers/M06-E06/ansible/roles/powerdns_auth/files/pdns-charger-zone) **seulement si le fichier a changé** ; `SOA-EDIT-API` à `DEFAULT` ;
   - `verifications.yml` : `dig +norec -p 5300` sur le SOA de chaque zone avec le drapeau `aa`, API avec la clé (200) et sans (401).

   Inventaire : [`powerdns_auth.yml`](fichiers/M06-E06/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml), clé d'API dans `vault-critique.yml` ([modèle](fichiers/M06-E06/ansible/inventories/lab/group_vars/role_dns/vault-critique.yml.exemple)). Playbook [`dns01.yml`](fichiers/M06-E06/ansible/playbooks/dns01.yml). Molecule : [`molecule/powerdns_auth/`](fichiers/M06-E06/ansible/molecule/powerdns_auth/).
4. Pipeline ; pendant le passage, une boucle `dig @10.10.20.10 dns01.par1.medisphere.internal` depuis `adm01` ne voit aucune coupure.
5. Exploration :
   ```
   admin@dns01:~$ sudo -u pdns pdnsutil zone list-all
   10.10.in-addr.arpa
   20.10.in-addr.arpa
   medisphere.internal
   par1.medisphere.internal
   par2.medisphere.internal
   admin@dns01:~$ sudo -u pdns pdnsutil zone check par1.medisphere.internal
   Checked 13 records of 'par1.medisphere.internal', 0 errors, 0 warnings.
   admin@dns01:~$ sudo -u pdns pdnsutil zone show par1.medisphere.internal
   This is a Native zone
   Zone is not actively secured
   …
   admin@adm01:~$ curl -sS -H "X-API-Key: $(… clé …)" http://10.10.20.10:8081/api/v1/servers/localhost/zones | jq -r '.[].name'
   admin@adm01:~$ dig +norec -p 5300 @10.10.20.10 git01.par1.medisphere.internal
   ;; flags: qr aa; …
   admin@adm01:~$ dig -p 5300 @10.10.20.10 deb.debian.org
   ;; ->>HEADER<<- opcode: QUERY, status: REFUSED, …
   ```
   (Le nombre d'enregistrements de `zone check` dépend de ton contenu.) dnsmasq répond `qr aa rd ra` pour ses noms locaux ; PowerDNS `qr aa` (pas de `ra` : il ne fait pas de récursion ; avec `rd` dans la question, `dig` signale « recursion requested but not available »). TTL : ceux de la zone (3600 s) contre ceux de dnsmasq (0 par défaut pour ses noms locaux, ou `local-ttl`). `REFUSED` pour `deb.debian.org` : un serveur faisant autorité ne répond que pour ses zones ; répondre autre chose (ou chercher la réponse) en ferait un résolveur ouvert.
6. Change par exemple l'adresse d'un nom de test dans `dns_hotes`, applique, compare `dig +short -p 5300 @10.10.20.10 par1.medisphere.internal SOA` avant et après : le numéro passe de `AAAAMMJJ00` à `AAAAMMJJ01` ; remets l'état initial (`…02`).

**Explications**

- **Cache des zones.** Depuis la 4.5, PowerDNS garde en mémoire la liste des zones (`zone-cache-refresh-interval`, 300 s par défaut) : une zone créée par `pdnsutil` (hors du serveur) est inconnue jusqu'au rafraîchissement suivant, d'où des `REFUSED` pendant quelques minutes. Une zone créée par l'**API** est ajoutée au cache immédiatement. Le rôle redémarre le service après une création (rare) ; `pdns_control rediscover` ne suffit pas pour le backend `gsqlite3`.
- **Cache des paquets.** Après `zone load`, les réponses déjà en cache (dont l'ancien SOA) restent servies jusqu'à `cache-ttl` (20 s) : le script de chargement vide le cache de la zone (`pdns_control purge 'zone$'`).
- **Numéro au chargement.** Le modèle porte `@SERIAL@` : le fichier généré ne change que si le **contenu** change, donc pas de rechargement inutile ; le script calcule le numéro (`max(AAAAMMJJ00, actuel+1)`), exactement la règle de `SOA-EDIT-API DEFAULT`, que l'API appliquera lors des écritures de M06-E14/E15.
- **Écoute de l'API.** Le serveur web n'écoute qu'une adresse (10.10.20.10) ; un client local passe par elle et se présente avec cette adresse : `webserver-allow-from` contient donc 10.10.20.10, pas seulement 127.0.0.1. Un client non autorisé voit sa connexion fermée sans réponse HTTP (`curl` : code `000`).

**Alternatives**

- **`gpgsql`** : réplication native par PostgreSQL, sauvegardes à chaud, mais une base à exploiter ; **`lmdb`** : rapide, sans dépendance, réplication par transferts de zone. Pour deux serveurs, le plan choisit des transferts de zone primaire → secondaire (M06-E24), indépendants du backend.
- **Zones entièrement par l'API** (module `uri` ou OpenTofu) au lieu de fichiers BIND : pas de `pdnsutil` local, mais plus d'appels et un état à comparer ; on y vient pour les zones écrites par OpenTofu et NetBox.
- **`api-key` hachée** : la 4.6+ accepte une valeur produite par `pdnsutil hash-password` ; ⚠️ vérifie la syntaxe dans la documentation 5.0 (`api-key`), c'est une bonne amélioration.

**Pièges classiques**

- Laisser le paquet démarrer `pdns` avec le backend `bind` sur le port 53.
- Écrire `launch=gsqlite3` dans un fichier de `pdns.d/` alors qu'un autre fichier (`bind.conf`) configure le backend `bind` : `bind-config` devient une option inconnue et le service refuse de démarrer. On n'installe pas `pdns-backend-bind` et on écrit `launch+=`.
- Base SQLite appartenant à root : `pdns` ne peut pas créer son fichier de journal, erreurs « readonly database » aux écritures.
- Comparer les zones avec un point final : `zone list-all` les affiche sans.
- Numéro de série dans le modèle avec `now()` : le rôle n'est plus jamais idempotent.

**En production chez MédiSphère**

Deux serveurs (M06-E24), supervision de chaque zone (SOA identique sur les deux, âge du numéro), API derrière TLS (proxy local) et clé hachée, sauvegarde de la base, alertes sur `pdnsutil zone check`.

---

### M06-E07 — PowerDNS Recursor et zones relayées

**Solution**

1. Lecture (Recursor 5.4) : `incoming.listen` vaut par défaut `[127.0.0.1, '::1']` ; `dnssec.validation` vaut `process` (validation seulement si le client met DO ou AD) ; `recursor.serve_rfc1918` vaut `true` (le Recursor répond lui-même `NXDOMAIN` pour les zones inverses privées, sauf celles qu'on relaie). La documentation des zones relayées prévient : avec la validation, une zone relayée non déléguée dont la parente est signée valide en *bogus* ; il faut une ancre négative (ou une ancre de confiance si la zone est signée).
2. Rôle [`roles/powerdns_recursor/`](fichiers/M06-E07/ansible/roles/powerdns_recursor/) :
   - même dépôt que l'Authoritative, suite `trixie-rec-54`, épinglage 600 (la 5.2 de Debian perd) ;
   - [`recursor.yml.j2`](fichiers/M06-E07/ansible/roles/powerdns_recursor/templates/recursor.yml.j2) construit une structure et la sérialise (`to_nice_yaml`) : `incoming.listen`, `incoming.allow_from`, `recursor.forward_zones` (ou `forward_zones_recurse` pour un amont), `dnssec.validation`, `dnssec.negative_trustanchors` ;
   - validation avant mise en place par [`files/pdns-recursor-verifier`](fichiers/M06-E07/ansible/roles/powerdns_recursor/files/pdns-recursor-verifier) : il copie le fichier temporaire sous le nom `recursor.yml` dans un dossier temporaire et lance `pdns_recursor --config-dir=… --config=check` ;
   - `powerdns_recursor_redemarrer` (vrai par défaut) : faux, le rôle écrit sans redémarrer (le handler ne fait rien) ;
   - redémarrage contrôlé : `block` (redémarrage, attente du port, question SOA sur la première zone relayée) / `rescue` (sauvegarde remise, redémarrage, échec explicite).

   Inventaire [`powerdns_recursor.yml`](fichiers/M06-E07/ansible/inventories/lab/group_vars/role_dns/powerdns_recursor.yml) ; [`dns01.yml`](fichiers/M06-E07/ansible/playbooks/dns01.yml) applique `dnsmasq`, `powerdns_auth`, `powerdns_recursor` ; Molecule [`molecule/powerdns_recursor/`](fichiers/M06-E07/ansible/molecule/powerdns_recursor/) (l'autoritaire et le résolveur sur la même instance).
3. Questions :
   ```
   admin@adm01:~$ dig -p 5301 @10.10.20.10 git01.par1.medisphere.internal      # NOERROR, qr rd ra (pas aa, pas ad)
   admin@adm01:~$ dig -p 5301 @10.10.20.10 -x 10.10.20.12                      # NOERROR, PTR git01…
   admin@adm01:~$ dig -p 5301 @10.10.20.10 nexistepas.par1.medisphere.internal # NXDOMAIN, SOA en autorité
   admin@adm01:~$ dig -p 5301 @10.10.20.10 +dnssec debian.org                  # NOERROR, qr rd ra ad
   admin@adm01:~$ dig -p 5301 @10.10.20.10 dnssec-failed.org                   # SERVFAIL
   ```
   Le Recursor ne met jamais `aa` : il rend une réponse qu'il a obtenue, il ne fait pas autorité.
4. Expérience (VM Molecule, `molecule converge` puis modification à la main de `/etc/powerdns/recursor.yml` et `systemctl restart pdns-recursor`) : sans l'ancre négative de `medisphere.internal`, les noms internes répondent **SERVFAIL** (en mode `validate`), la réponse étant *bogus* (visible dans `journalctl -u pdns-recursor` avec `dnssec.log_bogus: true`). En mode `process`, un client qui ne demande pas de validation (`dig +noadflag`, sans `+dnssec`) reçoit la réponse : le Recursor ne valide que pour ceux qui le demandent. Les clients du lab (glibc) ne demandent rien : en mode `process`, `dnssec-failed.org` leur serait servi, c'est pourquoi le ticket exige `validate`. Remets l'ancre (`molecule converge`).
5. Script [`outils/dns/comparer-resolveurs.sh`](fichiers/M06-E07/outils/dns/comparer-resolveurs.sh) et ses questions [`questions-socle.txt`](fichiers/M06-E07/outils/dns/questions-socle.txt) (copie de la ressource) :
   ```
   admin@adm01:~/src/outils/dns$ ./comparer-resolveurs.sh
     =  git01.par1.medisphere.internal A              NOERROR
     =  -x 10.10.20.12                                NOERROR
   …
   N question(s), 0 écart(s) entre 10.10.20.10:53 et 10.10.20.10:5301.
   ```
   Écarts possibles et normaux sur Internet : ordre et TTL (ignorés), adresses de CDN qui tournent (`deb.debian.org`), réponses différentes selon le serveur interrogé. Écart typique sur les noms internes avant correction : dnsmasq répond pour `sbxNN` (baux DHCP) et pour les noms courts via `domain=` / `expand-hosts`, ce que PowerDNS ne fait pas (les noms courts sont complétés par le client via `search` de `resolv.conf`, pas par le serveur) ; retire ces questions ou note-les comme effets connus (E08).

**Explications**

- **`forward_zones` contre `forward_zones_recurse`.** Le premier envoie la question **sans** récursion (RD=0), comme à un serveur faisant autorité, et sait suivre une délégation ; le second envoie RD=1 et attend une réponse finale, comme d'un autre résolveur. Les adresses de relais échappent à `outgoing.dont_query` (qui interdit 127.0.0.0/8 et 10.0.0.0/8 pour les serveurs découverts par itération).
- **Ancres négatives des zones inverses.** `10.in-addr.arpa` est délégué par la zone `in-addr.arpa` signée, **sans DS** : la chaîne prouve que la zone n'est pas signée, la réponse est *insecure* et passe. L'ancre négative ne change donc rien au résultat aujourd'hui ; elle évite de dépendre de la chaîne publique (accès Internet, changement chez l'IANA) pour une donnée purement interne.
- **Validation de la configuration.** `--config=check` lit le fichier, rejette clés inconnues et types faux et renvoie 1 : un fichier invalide n'est jamais mis en place.

**Alternatives**

- **Relais vers `<DNS-AMONT>`** (`forward_zones_recurse` pour `.`) : moins de flux sortants, mais on dépend du résolveur du FAI (et de sa validation) ; l'itération depuis la racine est plus indépendante, au prix d'un cache froid plus lent.
- **Unbound** ou **Knot Resolver** : excellents résolveurs ; PowerDNS garde une seule famille d'outils (dépôt, journalisation, métriques) pour l'équipe.
- **Ancre de confiance plutôt que négative** : la bonne solution, quand la zone est signée (M06-E26).

**Pièges classiques**

- Garder `recursor.conf` et ajouter `recursor.yml` : le YAML est lu, l'ancien fichier ignoré (et inversement si le YAML est absent) : un seul des deux doit exister.
- Oublier les zones inverses dans `forward_zones` : `serve_rfc1918` répond `NXDOMAIN` pour les PTR internes.
- Laisser le paquet démarrer le Recursor par défaut sur 127.0.0.1:53 : conflit avec dnsmasq (qui écoute aussi sur la boucle locale).
- Comparer les TTL dans le script : écarts permanents qui masquent les vrais.

**En production chez MédiSphère**

Métriques du Recursor (Prometheus, M07 : taux de SERVFAIL, *bogus*, cache), journalisation des réponses *bogus*, supervision de l'échéance des ancres et de la bascule KSK de la racine (question 12 de E09).

---

### M06-E08 — Basculer le DNS du lab sans coupure

**Solution**

1. **Fiche** : [`docs/socle/changements/CHG-708-bascule-dns.md`](fichiers/M06-E08/medisphere/docs/socle/changements/CHG-708-bascule-dns.md).
2. **Code.**
   - Rôle `dnsmasq` : [`roles/dnsmasq/`](fichiers/M06-E08/ansible/roles/dnsmasq/) reprend celui de M04-E46 avec `dnsmasq_dns_actif` (faux → `port=0`, et aucune directive DNS dans le fichier ; le `domain` reste pour le DHCP) et `dnsmasq_redemarrer`.
   - Rôle `powerdns_recursor` : `powerdns_recursor_redemarrer` existe depuis E07.
   - MR de bascule (état après) : `dnsmasq_dns_actif: false`, `powerdns_recursor_ecoute: [127.0.0.1, 10.10.20.10]` ([extrait](fichiers/M06-E08/ansible/inventories/lab/group_vars/role_dns/bascule-extrait.yml)).
   - Playbook : [`playbooks/bascule-dns.yml`](fichiers/M06-E08/ansible/playbooks/bascule-dns.yml) ; [`site.yml`](fichiers/M06-E08/ansible/playbooks/site-extrait.yml) n'importe pas la bascule.
3. **Répétition naïve.** VM 2060 (clone de `current`, pool `lab`, `env-m06`, `vsandbox`) ; inventaire [`inventories/repetition/`](fichiers/M06-E08/ansible/inventories/repetition/) :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/repetition playbooks/dns01.yml
   admin@adm01:~$ sonde-continue.sh -s <IP-DE-LA-VM-2060> -d 60 &
   admin@m06-repetition:~$ sudo tcpdump -ni any 'icmp or (tcp port 53 and tcp[tcpflags] & tcp-rst != 0)' &
   admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/repetition playbooks/dns01.yml \
       -e @inventories/repetition/apres.yml -e dnsmasq_redemarrer=false -e powerdns_recursor_redemarrer=false
   # configuration « après » écrite, rien redémarré ; puis la bascule naïve :
   admin@m06-repetition:~$ sudo systemctl restart dnsmasq && sudo systemctl restart pdns-recursor
   ```
   Résultat de la rédaction (conteneur) : **4 échecs « client »**, fenêtre d'une seconde environ. Le `tcpdump` montre des `ICMP … udp port 53 unreachable` : entre l'arrêt de dnsmasq et la prise du port par le Recursor, le noyau **refuse** chaque question. glibc reçoit cette erreur immédiatement (sa socket UDP est connectée), passe à la tentative suivante, la voit refusée aussi, et rend l'échec à l'application en quelques millisecondes : les 5 secondes d'attente ne s'appliquent qu'au **silence**.
4. **Répétition corrigée.** Remise à l'état de départ (`dns01.yml` sans `apres.yml`, ou instantané), puis :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/repetition playbooks/bascule-dns.yml -e @inventories/repetition/apres.yml
   ```
   Pendant les deux redémarrages, la table `inet bascule_dns` jette les ICMP « port unreachable » et les RST TCP émis depuis le port 53 : les clients ne reçoivent **rien**, attendent, réessaient et obtiennent la réponse du Recursor. Résultat de la rédaction : **0 échec « client »**, 1 échec « brut » (une question sans réponse en 1 s), la plus lente résolution autour d'une seconde. La table est supprimée à la fin, et dans le `rescue`. Test du retour arrière : `-e bascule_sonde_attendue=10.9.9.9` fait échouer le contrôle du nom interne ; le playbook remet les deux configurations, redémarre le Recursor puis dnsmasq, retire la table et échoue avec le message de retour arrière ; `ss -lnup 'sport = :53'` montre de nouveau dnsmasq.
5. **Jour J** : déroulé de la fiche. Après la bascule :
   ```
   admin@adm01:~$ dig +short CH TXT version.bind @10.10.20.10
   "PowerDNS Recursor 5.4.7"
   admin@adm01:~$ dig +tcp +short git01.par1.medisphere.internal @10.10.20.10
   10.10.20.12
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/dns01.yml --check --diff     # changed=0
   ```
6. **Clôture** : compte rendu de la fiche (bilans des deux sondes), `tofu destroy` ciblé ou `qm destroy 2060` selon la façon dont tu l'as créée (par le code : retire-la du code), suppression de l'instantané `avant-chg708` le lendemain.

**Explications**

- **Refus ou silence.** UDP : un paquet vers un port fermé déclenche un ICMP *port unreachable* ; la bibliothèque C le reçoit comme une erreur de la socket et considère le serveur injoignable **tout de suite**. TCP : un SYN vers un port fermé reçoit un RST. Sans réponse, le client applique son délai et réessaie. Transformer le refus en silence pendant une seconde transforme une panne en lenteur : c'est exactement le critère de Nadia.
- **Pourquoi `output`.** L'ICMP et le RST sont produits par le noyau de `dns01` : on les intercepte en sortie, sur l'hôte lui-même, sans toucher à `gw01`. La table est à part (`inet bascule_dns`) : sa suppression ne touche à aucune autre règle.
- **Variables de play et inventaire.** `dnsmasq_redemarrer: false` et `powerdns_recursor_redemarrer: false` sont des variables de play : elles l'emportent sur tout l'inventaire. Pour la même raison, l'adresse à tester ne peut pas s'appeler `bascule_adresse` dans l'inventaire de répétition : le playbook lit `dns_adresse_service` (inventaire) et le recopie dans sa variable.
- **Ordre du retour arrière.** Inverse de la bascule : le Recursor rend le port 53 (retour sur 5301) avant que dnsmasq redémarre et le reprenne.
- **La preuve finale.** Un passage normal `changed=0` montre que le code décrit l'état obtenu : la bascule n'a rien laissé que le code ignore.

**Alternatives**

- **Sans aucun délai** (pour aller plus loin) : une règle de redirection temporaire (`nat prerouting`, 53 → 5301, plus `output` pour la boucle locale) pendant le redémarrage de dnsmasq, puis le Recursor démarré sur le port 53 avec `incoming.reuseport` pendant que l'instance d'essai (5301) tient encore la redirection, puis retrait de la règle. Zéro silence, mais deux instances, des règles NAT, et une procédure nettement plus longue à tester ; justifié pour un résolveur qui sert des milliers de clients à la seconde, pas pour le lab.
- **Changer d'adresse** : le Recursor sur une nouvelle IP, puis bascule des clients (DHCP, `resolv.conf` par Ansible) : sans fenêtre, mais tous les clients changent et l'ancienne adresse doit rester servie longtemps.
- **Anycast/VIP** (keepalived) : la bonne réponse avec deux serveurs (M06-E24/E25).

**Pièges classiques**

- Redémarrer le Recursor **avant** dnsmasq : le port 53 est encore pris, le Recursor échoue à démarrer.
- Oublier la boucle locale (`127.0.0.1:53`) : `dns01` lui-même ne résout plus (et `apt`, `chrony`…).
- Une règle temporaire qui survit à un échec (pas d'`always`/`rescue`) : `dns01` « avale » ensuite toutes les erreurs ; d'où la vérification « aucune règle temporaire ne subsiste ».
- Fusionner la MR **avant** le créneau : le prochain pipeline planifié fait une bascule naïve.
- Répéter sur une VM étiquetée `role-dns` : l'inventaire dynamique du socle la ramasse, et le garde-fou de `site.yml` (huit hôtes) bloque tout.

**En production chez MédiSphère**

Deux résolveurs (`dns01`, `dns02`) annoncés aux clients : on bascule l'un après l'autre et un client glibc passe au second serveur sur refus, sans délai. La fiche de changement passe en revue (CAB), la sonde fait partie de la supervision permanente (blackbox_exporter, M07).

---

### M06-E09 — Questions : DNS, DHCP et PKI

**Grille** : 2 points par question (2 = juste, argumenté **et** appuyé sur une observation du lab ; 1 = juste sans argument ou sans lien avec le lab ; 0 = faux). Total sur 24. En dessous de 14, relis les explications de E02, E06 et E08 avant le palier 2.

**1. Intermédiaire généré sur `ca01`.** La clé de l'intermédiaire ne voyage jamais : elle n'a existé que sur `ca01` (pas sur `adm01`, pas dans un dépôt, pas dans un journal de pipeline). Et la racine n'a jamais été en ligne : seule la CSR, publique, a voyagé. Ce que ça complique : reconstruire `ca01` (VM perdue) exige soit de restaurer la clé de l'intermédiaire depuis une sauvegarde (PBS : elle est chiffrée par le mot de passe des clés en ligne, en Vault `critique`), soit une **nouvelle** cérémonie (nouvelle clé, nouvelle CSR, signature par la racine, déploiement). Le rôle sait faire la seconde (phase 1 automatique) ; la procédure de reconstruction (runbook) dit laquelle choisir. Les certificats déjà émis restent valides dans les deux cas : les clients font confiance à la racine.

**2. Provisioner `admin`.** Quiconque a la clé chiffrée **et** son mot de passe peut obtenir des certificats de 90 jours pour n'importe quel nom. La clé chiffrée est publique en pratique (`/provisioners` la sert à tout client) : toute la protection repose sur le mot de passe (`step-admin.pass`). Si `ca01` est compromise : la clé du provisioner n'est plus le problème, l'attaquant a la clé de l'**intermédiaire** et signe ce qu'il veut, sans limite ; on révoque l'intermédiaire (nouvelle cérémonie) et on réémet tout. Si `step-admin.pass` fuit : l'attaquant (s'il joint `ca01:443`) émet des certificats de 90 jours ; on remplace la clé du provisioner (nouvelle paire JWK, Vault, passage du rôle), on recherche les émissions suspectes dans le journal de step-ca, on révoque celles-ci (`step ca revoke` : révocation passive, qui empêche le renouvellement ; les clients ne vérifient pas de CRL chez nous).

**3. 90 jours contre 30.** Un certificat émis à la main se renouvelle à la main : un humain doit y penser. 90 jours est un compromis entre exposition et charge de travail, **transitoire** jusqu'à M06-E18. Avec ACME, le renouvellement est automatique (aux deux tiers de la durée) : une durée courte ne coûte rien et réduit la fenêtre d'abus d'une clé volée. L'objectif est l'inverse de l'intuition : la voie automatisée a la durée la plus courte.

**4. Réponse B.** Chaque poignée de main TLS vérifie la chaîne avec le magasin du moment : sans la racine, `git clone` en HTTPS et le backend S3 d'OpenTofu (Go, magasin système sous Linux) échouent (« certificate signed by unknown authority »). En pratique, le runner lui-même (Go aussi) n'arrive plus à demander ses jobs à `git01` : le pipeline ne démarre même pas sur ce runner. A est faux : il n'y a pas de cache de confiance. C est faux : OpenTofu utilise le magasin du système. D est faux : le runner journalise des erreurs et réessaie, il ne se désenregistre pas.

**5. Poivres.** Avec la base seule : les jetons v2 sont des empreintes HMAC calculées avec le poivre ; l'attaquant ne peut ni les utiliser ni tester des candidats hors ligne (et le jeton est aléatoire, long). Avec la base **et** `configuration.py` : il ne retrouve toujours pas les jetons existants (empreinte d'une valeur aléatoire de grande entropie), mais s'il peut **écrire** dans la base, il fabrique un jeton dont il calcule lui-même l'empreinte ; et `SECRET_KEY` lui permet de fabriquer des sessions. Rotation : ajouter un poivre d'identifiant supérieur (les nouveaux jetons l'utilisent ; les anciens, vérifiés avec le poivre de leur identifiant, restent valides), réémettre les jetons, puis retirer l'ancien poivre (les jetons restants deviennent invalides).

**6. Valkey.** Pas d'authentification par défaut : quiconque le joint lit et écrit tout. Or la file de tâches contient des tâches que `netbox-rq` **exécute** (sérialisées par pickle avec RQ) : écrire dans la file, c'est exécuter du code sous le compte `netbox`, donc lire `configuration.py` et la base. S'y ajoutent les commandes d'administration (`CONFIG SET dir`/`dbfilename` permettent d'écrire des fichiers). « Seulement un cache » est une illusion : c'est un composant de l'application, au même niveau de sensibilité qu'elle. Boucle locale seulement, vérifiée par le rôle.

**7. `forward_zones_recurse`, dnsmasq.** Avec `_recurse`, le Recursor enverrait RD=1 et traiterait l'autoritaire comme un résolveur : il ne suivrait plus les délégations (une sous-zone déléguée et non relayée ne se résoudrait plus) ; PowerDNS Authoritative ignore RD et répond pour ses zones, donc « ça marche » souvent, ce qui cache l'erreur. Relayer vers dnsmasq : deux caches empilés (TTL cumulés, données périmées plus longtemps), dnsmasq redevient la source pour les zones internes (on n'aurait rien remplacé), et après la bascule (`port=0`) plus rien ne répondrait.

**8. Zone parente.** Elle donne un arbre cohérent : `medisphere.internal` délègue `par1` et `par2` (NS et colle), comme le ferait un vrai domaine, et M06-E24 pourra y ajouter des secondaires. Sans elle, une question sur `git01.medisphere.internal` ne correspond à aucune zone relayée : le Recursor l'envoie **sur Internet** (racine), qui répond `NXDOMAIN` après un aller-retour ; on publie au passage nos noms internes aux serveurs racine. Avec elle, l'autoritaire répond `NXDOMAIN` localement, avec autorité. (`.internal` est réservé par l'ICANN à l'usage privé : il ne sera jamais délégué.)

**9. Numéro de série.** Un numéro fixe dans le modèle : les secondaires (M06-E24) ne verraient jamais les changements. Un numéro calculé dans le modèle (heure courante) : le fichier change à chaque passage, le rôle n'est plus idempotent. L'heure Unix au chargement fonctionnerait (10 chiffres, croissante), mais `AAAAMMJJnn` est lisible par un humain (date du dernier changement) et c'est la règle qu'applique l'API (`SOA-EDIT-API DEFAULT` : `AAAAMMJJ01` ou numéro actuel + 1) : les deux sources d'écriture (rôle et API) suivent la même règle et ne se contredisent pas. Sans `SOA-EDIT-API`, une modification par l'API ne changerait pas le numéro : invisible pour les secondaires.

**10. Réponse B.** Observé en E08 (`tcpdump`) : pendant la fenêtre, la VM renvoie un ICMP « port unreachable » ; glibc considère le serveur injoignable sur-le-champ, épuise ses deux tentatives et rend l'échec en quelques millisecondes. A est faux : la sonde utilise les réglages d'un client glibc (5 s, 2 tentatives), et la version corrigée, avec la même sonde, attend bien. C est faux : un REFUSED serait une réponse DNS (et le Recursor n'en envoie pas pendant son démarrage, il n'écoute pas encore). D est faux : une perte donnerait un délai de 5 s, pas un échec immédiat.

**11. Renouvellement de l'intermédiaire à mi-vie.** Dans l'ordre : fiche de changement ; sur `ca01`, archiver l'ancienne clé et son certificat, relancer le rôle (phase 1 : nouvelle clé, nouvelle CSR) ; cérémonie (racine, `ceremonie-pki.sh signer`), nouveau certificat dans `pki/` ; phase 2 : step-ca signe désormais avec le nouvel intermédiaire ; vérifier `/health` et une émission. Garder l'ancien certificat d'intermédiaire publié tant que des certificats émis par lui sont en service (au plus 90 jours) : les services servent la chaîne avec laquelle ils ont été émis. Les clients ne voient **rien** : ils ne font confiance qu'à la racine, et chaque service présente une chaîne complète valide. Seuls les services qui auraient « épinglé » l'intermédiaire (à éviter) casseraient. Le faire à mi-vie laisse une marge large : l'intermédiaire doit vivre plus longtemps que le plus long certificat qu'il signe.

**12. KSK-2024.** Oui, si le Recursor a l'ancre de la nouvelle clé. La version 5.4 l'intègre : ses ancres intégrées contiennent les DS de KSK-2017 (étiquette 20326) **et** de KSK-2024 (38696) ; le Recursor ne suit pas les changements de clé selon la RFC 5011, c'est donc la version installée (ou un fichier d'ancres comme `/usr/share/dns/root.key` du paquet `dns-root-data`, s'il est configuré par `dnssec.trustanchorfile`) qui compte. Avant, on aurait vérifié : `rec_control get-tas` (ou la question `trustanchor.server CH TXT` si `recursor.allow_trust_anchor_query` est activé) liste `. 20326 38696` ; et que l'horloge de `dns01` est juste (dates des signatures). Le paquet de Debian 13 (5.2) a lui aussi la nouvelle clé : ⚠️ à vérifier sur ta version si tu n'utilises pas le dépôt officiel.

**Pour aller plus loin — registre des risques (exemple pour la question 2)** : *Fuite du mot de passe du provisioner `admin`* ; probabilité faible (fichier 600 sur `adm01`) ; impact élevé (certificats valides 90 jours pour n'importe quel nom interne) ; mesures en place : fichier hors dépôt, plafond de 90 jours, journal d'émission ; à venir : ACME (E18) puis retrait ou restriction du provisioner `admin` (politique de noms, M06-E33), alerte sur les émissions manuelles.

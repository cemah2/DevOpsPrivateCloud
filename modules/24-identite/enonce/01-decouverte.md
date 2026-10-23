# Module 24 — Palier 1 : Découverte

Avant de brancher un seul service, il faut savoir qui existe, comment on le prouve, et lire ce qui circule. Ce palier installe l'annuaire FreeIPA avec une CA subordonnée à la racine MédiSphère, y déclare les personnes et les groupes en code, installe et publie Keycloak, crée un royaume à la main pour en comprendre les pièces, fédère l'annuaire, déroule un flux OpenID Connect à la main jusqu'au décodage des jetons, puis reprend le royaume en code avec OpenTofu. Il s'ouvre et se ferme sur un questionnaire.

Prérequis : module 23 terminé (`lab/bin/check 23 25` vert) ; module 06 (racine hors ligne et step-ca, PowerDNS en API, NetBox) ; module 07 (`lb01`/`lb02`, publication par nom) ; module 05 (OpenTofu, état S3 chiffré) ; module 04 (Ansible, Vault `critique`, pipeline protégé). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les **règles du module**.

**Rappels du module**
- Un accès de secours ouvert **et essayé** avant tout changement d'authentification ; jamais de modification du royaume `master` sans un second administrateur vérifié dans une autre fenêtre.
- Aucun secret sur une ligne de commande, dans Git en clair ou dans un compte rendu ; tout secret local dans `~/.config/workbook/` (600).
- L'annuaire est la seule source des personnes ; rien à la main dans le royaume `medisphere` après E08.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| `ipa01` | 1031, 10.10.20.31, Rocky 10, FreeIPA 4.13, royaume `PAR1.MEDISPHERE.INTERNAL`, base `dc=par1,dc=medisphere,dc=internal` |
| `idp01` | 1030, 10.10.20.30, Debian 13, Keycloak 26.7.5, PostgreSQL 17, ports 8443 et 9000 |
| Nom public | `https://sso.par1.medisphere.internal` → VIP 10.10.70.200 (`lb01`/`lb02`) |
| Émetteur | `https://sso.par1.medisphere.internal/realms/medisphere` |
| Fichiers des checks | `~/.config/workbook/ipa-checks.env` (E03), `~/.config/workbook/keycloak-checks.env` (E05) |
| Projet | `plateforme/identite` (E03 : `annuaire/` ; E08 : `tofu/`) |
| Documentation | `docs/securite/identite/` de `plateforme/medisphere` |

> **Mémoire** : les deux VMs du palier ajoutent 7 Go. Le palier ne touche pas au cluster : si `pve01` manque de mémoire, arrête `k8s-par1` (procédure du M14) le temps du palier, jamais une VM du socle.

**Durée** : 21 à 25 heures. **Ordre conseillé** : celui de la carte, E01 → E09 (voir l'introduction).

---

### M24-E01 — Test de positionnement : identité, authentification, autorisation  `Q` `★★`

> **Ticket PLAT-2501** — *De : Karim Benali*
> Une heure, par écrit, sans moteur de recherche ni IA. Tout le monde a déjà « mis du SSO » quelque part ; je veux savoir si tu sais ce qu'un jeton porteur laisse faire à celui qui le vole, et pourquoi un compte partagé « admin » est une faute même avec un excellent mot de passe. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur l'identité (authentification, autorisation, facteurs, sessions) et sur les protocoles (LDAP, Kerberos, SAML, OAuth 2.0, OIDC).
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 14 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Les notions*

1. Définis identification, authentification et autorisation, avec un exemple de chacune tiré d'une connexion de Julien Petit à Argo CD. Lequel de ces trois rôles un fournisseur d'identité comme Keycloak assure-t-il, et lequel reste au service ?

2. *(QCM)* Laquelle de ces combinaisons est une authentification **à deux facteurs** ?
   - A. Un mot de passe et une question secrète (« nom de votre premier animal »)
   - B. Un mot de passe et un code à six chiffres affiché par une application sur le téléphone
   - C. Deux mots de passe différents saisis l'un après l'autre
   - D. Un mot de passe saisi depuis une adresse IP du réseau de l'entreprise

3. Pourquoi un compte partagé (`admin` utilisé par trois personnes), même protégé par un excellent mot de passe, pose-t-il problème ? Donne au moins trois raisons, dont une qui concerne un audit HDS.

*Sessions et jetons*

4. Une application web garde la personne connectée par un cookie de session. Que contient ce cookie, en général, et que doit garantir l'application quand elle le pose (au moins trois attributs ou précautions) ?

5. Qu'est-ce qu'un jeton **porteur** (*bearer token*) ? Que peut faire quelqu'un qui en a volé un, et quelles sont les deux façons habituelles de limiter le dégât ?

6. *(QCM)* Un JWT signé (`header.payload.signature`) est envoyé à une API. Quelle affirmation est vraie ?
   - A. Le contenu est chiffré : seule l'API qui a la clé peut le lire
   - B. Le contenu est lisible par quiconque l'intercepte ; la signature garantit seulement qu'il n'a pas été modifié et qui l'a émis
   - C. La signature empêche de réutiliser le jeton une seconde fois
   - D. L'API doit appeler l'émetteur à chaque requête pour savoir si le jeton est valable

*Annuaires et fédération*

7. Qu'est-ce qu'une **liaison** (*bind*) LDAP ? Explique comment une application peut vérifier le mot de passe d'une personne grâce à l'annuaire sans jamais lire ce mot de passe.

8. Kerberos n'envoie jamais le mot de passe sur le réseau. Comment la personne prouve-t-elle alors qui elle est ? Pourquoi un écart d'horloge de dix minutes entre un poste et le serveur fait-il échouer l'authentification ?

9. Qu'appelle-t-on **fédération d'identité** ? Donne un exemple entre deux organisations et un exemple à l'intérieur de MédiSphère.

*Protocoles du web*

10. *(QCM)* SAML 2.0 et OpenID Connect :
    - A. sont deux noms du même protocole
    - B. transportent tous deux une preuve d'authentification signée ; SAML en XML (assertions), OIDC en JSON (JWT) au-dessus d'OAuth 2.0
    - C. SAML ne fonctionne que pour les applications mobiles
    - D. OIDC ne permet pas l'authentification unique entre plusieurs applications

11. OAuth 2.0 a été conçu pour **déléguer un accès**, pas pour authentifier. Explique la différence avec l'exemple « une application de prise de rendez-vous qui lit ton agenda », et ce qu'OpenID Connect ajoute.

12. À quoi sert **PKCE** (*Proof Key for Code Exchange*) ? Quelle attaque empêche-t-il, et pour quel type de client était-il d'abord prévu ?

*Exploitation*

13. Le fournisseur d'identité de MédiSphère tombe un lundi matin. Que se passe-t-il pour les personnes déjà connectées à Grafana, pour celles qui veulent s'y connecter, et pour l'astreinte qui doit intervenir sur le cluster ? Qu'est-ce qu'un compte de **bris de glace**, et quelles sont ses trois propriétés indispensables ?

14. Un collaborateur quitte MédiSphère ce soir. Liste tout ce qui doit être coupé pour qu'il ne puisse plus rien faire, en distinguant ce que le SSO coupe d'un coup et ce qu'il ne coupe pas.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 28.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions sur les jetons, pose-toi deux questions : qui peut **lire** ce qui est transporté, et qui peut le **présenter** à la place de son propriétaire ?
</details>

<details><summary>Indice 2</summary>

Pour les questions d'exploitation, mets-toi à la place de Nadia un lundi à 8 h : l'IdP ne répond plus, un service est en panne, et elle doit entrer quelque part pour réparer.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M24-E46), sans relire le corrigé, et compare.

---

### M24-E02 — Construire l'annuaire : FreeIPA sur `ipa01` et sa CA subordonnée  `LAB` `★★★`

> **Ticket PLAT-2502** — *De : Karim Benali* — *Copie : Sophie Laurent*
> L'annuaire d'abord : FreeIPA sur une VM dédiée, `ipa01`. Deux exigences de Sophie. Un : **pas de second DNS**, PowerDNS reste la seule autorité de nos zones ; FreeIPA publie ce dont il a besoin dans PowerDNS, par notre code. Deux : **pas de nouvelle racine de confiance** ; la CA de FreeIPA doit être signée par « MédiSphère Root CA », pendant une cérémonie écrite, avec la racine hors ligne du M06. Tout doit se vérifier jusqu'à la racine qu'on a déjà installée partout.

**Objectifs pédagogiques**
- Créer une VM Rocky Linux 10 du socle par OpenTofu et publier les enregistrements DNS qu'attend un domaine Kerberos/LDAP (SRV, TXT, A).
- Installer FreeIPA sans DNS intégré, avec une CA **externe** (deux passages, CSR signée par la racine hors ligne).
- Conduire et consigner une cérémonie de signature d'autorité subordonnée.
- Contrôler un annuaire : services, Kerberos, chaîne de certificats, flux.

**Prérequis** : M06-E02 (racine hors ligne, `~/pki-racine`), M06-E14 (PowerDNS par API et par OpenTofu, module `enregistrement-dns`), M08-E02 (module `vm-noeud`, image `rocky10`), M04 (rôles, Vault `critique`), M07 (rôle `pare_feu` des passerelles).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `ipa01`, VMID 1031, 10.10.20.31/24 (VNet `vinfra`, passerelle 10.10.20.1), Rocky 10 (image dorée `rocky10` `current`), 2 vCPU, 4 Go, 40 Go `local-nvme` ; démarrage avec `pve01`, protection Proxmox ; étiquettes `socle`, `role-annuaire` ; état OpenTofu `socle` de `plateforme/infra` (fichier `socle/ipa01.tf`) |
| Domaine | domaine IPA `par1.medisphere.internal`, royaume `PAR1.MEDISPHERE.INTERNAL`, sujet de la CA `CN=Certificate Authority,O=PAR1.MEDISPHERE.INTERNAL` |
| Rôles Ansible | `freeipa_serveur` (nouveau, dans `plateforme/ansible`), qui s'appuie sur le rôle `ipaserver` de la collection **`freeipa.ansible_freeipa` 1.17.0** ; playbook `playbooks/annuaire-serveur.yml` (groupe `role_annuaire`) |
| Secrets | mot de passe de `admin` (compte de bris de glace de l'annuaire) et du *Directory Manager* : Vault `critique`, `host_vars/ipa01/vault-critique.yml` |
| Temps | chrony vers la passerelle du VLAN, comme toutes les VMs (rôles communs) ; FreeIPA ne configure pas le NTP |
| Pièces publiques | `pki/ipa01-ipa.csr` et `pki/ipa01-ipa.crt` dans `plateforme/ansible` (à côté de `medisphere-root-ca.crt`) |
| Procès-verbal | `docs/securite/identite/ceremonie-ca.md` de `plateforme/medisphere` (réutilisé au M25) |
| Flux | VMs à inscrire (VLAN 20, VLAN 40, DMZ) → `ipa01` 88 et 464 (TCP/UDP), 389, 443, 636 |

**Travail demandé**

*A. La machine et son nom*

1. Lis la documentation d'installation de FreeIPA « sans DNS intégré » et « avec une CA externe » (liens en fin d'exercice). Note dans `~/m24/e02/notes.md` : les enregistrements DNS que le serveur attend, ce qui est vérifié avant l'installation (résolution directe et inverse du nom), et les deux passages d'une installation à CA externe.
2. Écris `socle/ipa01.tf` dans `plateforme/infra` : la VM par le module `vm-noeud` (famille `rocky10`), son A et son PTR par `enregistrement-dns`, et les enregistrements du domaine par la ressource `powerdns_record` : SRV `_ldap._tcp`, `_kerberos._tcp`, `_kerberos._udp`, `_kerberos-master._tcp`, `_kerberos-master._udp`, `_kpasswd._tcp`, `_kpasswd._udp` (priorité, poids, port, cible), TXT `_kerberos` (le royaume, entre guillemets), A `ipa-ca`. Ajoute l'étiquette `role-annuaire` à la modélisation de NetBox si elle n'existe pas. MR, plan relu, apply par le pipeline.
3. Contrôle depuis `adm01` :
   ```
   admin@adm01:~$ dig +short ipa01.par1.medisphere.internal; dig +short -x 10.10.20.31
   admin@adm01:~$ dig +short SRV _ldap._tcp.par1.medisphere.internal
   admin@adm01:~$ dig +short TXT _kerberos.par1.medisphere.internal
   admin@adm01:~$ ssh admin@ipa01 'hostname -f; cat /etc/rocky-release; chronyc tracking | grep Leap'
   ```
   `hostname -f` doit renvoyer `ipa01.par1.medisphere.internal` : ce nom s'inscrit dans tous les certificats de l'annuaire, on ne le change plus après.

*B. Le rôle et le premier passage*

4. Ajoute `freeipa.ansible_freeipa` 1.17.0 à `collections/requirements.yml`. Lis le `README` du rôle `ipaserver` de la collection : les variables d'une CA externe (`ipaserver_external_ca`, `ipaserver_external_cert_files_from_controller`), du DNS, du NTP, du pare-feu.
5. Écris le rôle `freeipa_serveur`. Exigences :
   - il refuse un autre système que Rocky 10, un nom complet incohérent, une horloge non synchronisée, des mots de passe de moins de 16 caractères ;
   - **phase 1** (ni installation, ni certificat signé dans le dépôt) : installation interrompue à la CSR de la CA, CSR **rapatriée** dans `pki/ipa01-ipa.csr`, arrêt propre de l'hôte avec une consigne ; si une CSR existe déjà sur `ipa01`, il ne relance **pas** la phase 1 (une nouvelle clé rendrait caduque la signature en cours) ;
   - **phase 2** (certificat signé présent dans `pki/`) : il vérifie le certificat contre la racine, puis termine l'installation avec le certificat **et** la racine ;
   - pas de DNS intégré ; FreeIPA ne touche pas à chrony et n'ouvre pas le port 123 ; la règle HBAC `allow_all` est conservée (elle sera remplacée en E19) ;
   - des contrôles finaux (services, CA signée par la racine, ticket Kerberos d'`admin` dans un cache temporaire, mot de passe jamais sur une ligne de commande).
6. Crée `host_vars/ipa01/vault-critique.yml` (identité `critique`) avec deux mots de passe générés et différents ; range-les aussi dans ton gestionnaire de mots de passe (le compte `admin` est le bris de glace de l'annuaire). Écris `playbooks/annuaire-serveur.yml`. Applique les rôles communs du socle à `ipa01` (`site.yml`), puis le premier passage :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/annuaire-serveur.yml
   ```
   Relis la CSR obtenue (`step certificate inspect pki/ipa01-ipa.csr --short`) : sujet, algorithme, taille de clé.

*C. La cérémonie*

7. Écris `docs/securite/identite/ceremonie-ca.md` **avant** de signer : rôles (officiant, témoin), contrôles de la CSR, commande de signature, contrôles du résultat, archivage, procès-verbal. Puis signe la CSR avec la racine hors ligne d'`~/pki-racine`, selon la procédure de cérémonie du M06-E02 : profil d'autorité intermédiaire, **longueur de chemin 0**, cinq ans, phrase de passe saisie au clavier. Contrôle le résultat (`basicConstraints`, `keyUsage`, échéance, empreinte SHA-256, vérification contre la racine), archive `~/pki-racine`, remplis le procès-verbal.
   > ⚠️ **Attention** : la clé de la racine ne sort pas d'`~/pki-racine`. Rien d'autre que la CSR n'entre dans ce dossier, rien d'autre que le certificat signé n'en sort. Si tu as un doute sur la CSR (sujet, origine), arrête la cérémonie : une CA signée par erreur se révoque, mais elle a pu servir entre-temps.

*D. Le second passage et les contrôles*

8. MR dans `plateforme/ansible` (CSR et certificat signés, deux pièces publiques), puis le second passage du playbook. Contrôle sur `ipa01` :
   ```
   [admin@ipa01 ~]$ sudo ipactl status
   [admin@ipa01 ~]$ kinit admin && klist && ipa ca-show ipa
   [admin@ipa01 ~]$ ipa dns-update-system-records --dry-run
   [admin@ipa01 ~]$ kdestroy
   ```
   `ipa dns-update-system-records --dry-run` liste ce que FreeIPA aurait publié s'il gérait le DNS : compare avec ton `ipa01.tf` et complète-le si un enregistrement manque.
9. Depuis `adm01`, vérifie la chaîne **avec la seule racine** comme ancre de confiance :
   ```
   admin@adm01:~$ curl -s http://ipa01.par1.medisphere.internal/ipa/config/ca.crt -o ~/m24/e02/ca-ipa.crt
   admin@adm01:~$ openssl s_client -connect ipa01.par1.medisphere.internal:636 -showcerts </dev/null 2>/dev/null | grep -E '^ *[0-9]+ [si]:'
   ```
   Quels certificats le serveur présente-t-il ? Lequel vérifies-tu contre la racine, et pourquoi n'a-t-on rien eu à distribuer de nouveau sur les postes ?
10. Ouvre les flux de la bordure vers `ipa01` (rôle `pare_feu`, une passerelle à la fois) pour les VMs qui seront inscrites en E19 (VLAN 40, DMZ) et reporte-les dans `docs/socle/matrice-flux.md`. Ouvre l'interface web `https://ipa01.par1.medisphere.internal/ipa/ui/` depuis ton poste (VPN) et connecte-toi en `admin` : c'est **la dernière fois** que ce compte sert au quotidien.

**Critères de réussite**
- [ ] `ipa01` existe (VMID 1031, NetBox, étiquettes `socle` et `role-annuaire`), résout dans les deux sens, son horloge est synchronisée.
- [ ] Les SRV `_ldap._tcp`, `_kerberos._tcp/_udp`, `_kpasswd._udp`, le TXT `_kerberos` et le A `ipa-ca` sont publiés par PowerDNS (OpenTofu) ; aucun `named` sur `ipa01`.
- [ ] `ipactl status` est vert ; `kinit admin` délivre un ticket `krbtgt/PAR1.MEDISPHERE.INTERNAL`.
- [ ] La CA de FreeIPA se vérifie contre la seule racine MédiSphère, avec `CA:TRUE, pathlen:0` ; LDAPS (636) et HTTPS (443) présentent des certificats valides pour `ipa01` jusqu'à la racine.
- [ ] La CSR et le certificat signé sont dans `pki/` de `plateforme/ansible` ; le procès-verbal (empreinte, échéance, renouvellement) est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 24 02`

<details><summary>Indice 1</summary>

Sans DNS intégré, l'installateur ne publie rien : il écrit seulement, à la fin, la liste des enregistrements à créer. Les SRV d'un domaine Kerberos/LDAP suivent la RFC 2782 (`_service._proto`), et les clients Kerberos cherchent le royaume dans un TXT `_kerberos`. Les certificats émis par la CA de FreeIPA pointent vers `ipa-ca.<domaine>` pour l'OCSP et la CRL.
</details>

<details><summary>Indice 2</summary>

Le rôle `ipaserver` sait faire les deux passages : avec `ipaserver_external_ca: true`, il s'arrête après avoir écrit `/root/ipa.csr` ; avec `ipaserver_external_cert_files_from_controller`, il copie les fichiers que tu lui donnes dans `/root/` et termine. Ton rôle n'a qu'à décider de la phase (FreeIPA est-il **complètement** installé ? le certificat signé est-il dans le dépôt ?) et rapatrier la CSR. Attention au premier test : la phase 1 laisse déjà sur `ipa01` des fichiers d'une installation (`/etc/ipa/default.conf`, une instance 389-ds) ; demande plutôt à FreeIPA ce qu'il en pense (`ipactl status` répond « IPA is not configured » tant que l'installation n'est pas terminée). C'est exactement la logique du rôle `step_ca` du M06.
</details>

<details><summary>Indice 3</summary>

Pour la signature, `step certificate sign` avec le profil `intermediate-ca` garde le sujet de la CSR et pose `CA:TRUE` ; `--path-len 0` interdit à la CA de FreeIPA de créer d'autres autorités ; `--not-after` fixe la durée. Le second passage attend le certificat signé **et** la chaîne jusqu'à la racine (deux fichiers).
</details>

**Pour aller plus loin** (facultatif) : lis la procédure de renouvellement d'une CA externe (`ipa-cacert-manage renew --external-ca`) et estime le travail le jour de l'échéance ; lance `ipa-healthcheck` (paquet `freeipa-healthcheck`) et lis ses avertissements. [FreeIPA : *External CA*](https://www.freeipa.org/page/V4/External_CA) · [Rôle `ipaserver`](https://github.com/freeipa/ansible-freeipa/blob/master/roles/ipaserver/README.md)

---

### M24-E03 — Personnes, groupes et politiques de mot de passe en code  `LAB` `★★`

> **Ticket PLAT-2503** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'annuaire existe, il est vide, et je veux qu'il le reste… de toute création à la main. Les personnes et les groupes sont déclarés dans un dépôt, relus en MR, appliqués par un pipeline : c'est ce qui me permettra de répondre à l'auditeur « montrez-moi quand et par qui Lucas a été ajouté au groupe plateforme ». Mes exigences pour les mots de passe : 12 caractères au moins, pas de réutilisation des 6 derniers, verrouillage après 6 échecs. Et prévois les deux comptes techniques dont on aura besoin : celui de Keycloak et celui des vérifications, en lecture seule.

**Objectifs pédagogiques**
- Décrire un annuaire en code (personnes, groupes, politique, comptes système) avec la collection officielle de FreeIPA.
- Distinguer ce qui se synchronise (appartenances) de ce qui ne doit jamais se supprimer (personnes).
- Créer des comptes système LDAP et un premier accès en lecture pour les vérifications, sans secret en clair.
- Appliquer par un job manuel protégé et prouver l'idempotence.

**Prérequis** : M24-E02 ; M04-E30 (Vault, `vault-pass-client.sh`, pipeline protégé) ; M01 (projets, branches protégées, MR).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | **`plateforme/identite`** (nouveau, groupe `plateforme`, `main` protégée, fusion par MR), dossier `annuaire/` |
| Fichiers | `annuaire/personnes.yml`, `groupes.yml`, `politiques.yml`, `comptes-systeme.yml`, `vault-critique.yml` (chiffré, identité `critique`), `inventaire.yml`, playbook `annuaire.yml` ; `collections/requirements.yml`, `ansible.cfg`, `pyproject.toml` (uv), `outils/vault-pass-client.sh` (copie de celui de `plateforme/ansible`) |
| Modules | `freeipa.ansible_freeipa` : `ipauser`, `ipagroup`, `ipapwpolicy`, `ipasysaccount` (comptes système, FreeIPA ≥ 4.13) ; exécutés sur `ipa01` avec le mot de passe d'`admin` |
| Personnes | `<MOI>` et les six personnages, identifiants de GitLab, adresses `prenom.nom@medisphere.internal` |
| Groupes | `plateforme-admins` (`<MOI>`, `karim.benali`), `plateforme` (`<MOI>`, `karim.benali`, `lucas.martin`), `mediagenda` (`julien.petit`), `medidoc` (vide), `securite` (`sophie.laurent`), `support` (`nadia.roussel`), `direction` (`claire.morel`) |
| Comptes système | `uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal`, `uid=wb-checks,cn=sysaccounts,cn=etc,…` |
| Pipeline | runner `runner01` (étiquette `shell`) ; job **manuel** `annuaire:appliquer` sur `main`, environnement `lab/identite` ; variables protégées `ANSIBLE_CI_SSH_KEY` (fichier) et `VAULT_PASS_CRITIQUE` (fichier) de portée `lab/identite` |
| Vérifications | `~/.config/workbook/ipa-checks.env` (600) : `IPA_BIND_DN=…` et `IPA_BIND_PASSWORD=…` (compte `wb-checks`) |

**Travail demandé**

1. Crée le projet `plateforme/identite` (README : ce qu'il contient, ce qui l'applique, ses règles), le squelette Ansible (uv, collections, `ansible.cfg`, inventaire réduit à `ipa01`, `vault-pass-client.sh` recopié tel quel).
2. Écris `personnes.yml`, `groupes.yml`, `politiques.yml` et `comptes-systeme.yml`. Conventions à respecter (et à écrire en tête de chaque fichier) :
   - une personne n'est **jamais supprimée** par le code : un départ se déclare par un état « désactivé » ;
   - l'appartenance aux groupes est **synchronisée** : un membre retiré du fichier est retiré du groupe ;
   - aucun mot de passe de personne dans le dépôt ; les mots de passe des comptes système viennent du Vault et ne sont posés qu'à la création.
   Pour la politique, Sophie a fixé trois valeurs ; choisis et justifie les autres (durée de vie, classes de caractères, durée de verrouillage).
3. Écris `annuaire.yml` : vérification préalable des données (identifiants uniques, membres déclarés, aucune valeur `<À-ADAPTER>` oubliée), puis la politique, les personnes, leur état, les groupes, les comptes système. Lis la documentation des modules pour savoir comment chacun traite une liste de membres (ajout seul ou synchronisation), et vérifie que ton choix correspond à la convention.
4. Crée `annuaire/vault-critique.yml` (mot de passe d'`admin`, mots de passe générés de `svc-keycloak` et `wb-checks`). Relecture locale :
   ```
   admin@adm01:~/src/identite$ uv run ansible-playbook annuaire/annuaire.yml --check --diff
   ```
5. Écris `.gitlab-ci.yml` : `ansible-lint` sur les MR, un aperçu `--check --diff` sur les MR de branches protégées et sur `main`, un job **manuel** sur `main` qui applique puis **rejoue** le playbook et échoue si le second passage change quoi que ce soit. Déclare les variables protégées. MR, fusion, application.
6. Donne leur premier mot de passe à deux personnes pour les essais du palier, `<MOI>` et `lucas.martin`, sans jamais l'écrire nulle part :
   ```
   [admin@ipa01 ~]$ kinit admin
   [admin@ipa01 ~]$ ipa passwd lucas.martin          # mot de passe provisoire, expiré d'office
   [admin@ipa01 ~]$ kdestroy && kinit lucas.martin   # « Password expired. You must change it now. »
   [admin@ipa01 ~]$ kdestroy
   ```
   Fais de même pour `<MOI>`. Range les deux mots de passe définitifs dans ton gestionnaire. Pourquoi un mot de passe posé par un administrateur est-il expiré d'office dans FreeIPA ?
7. Crée `~/.config/workbook/ipa-checks.env` (600) à partir du Vault, sans afficher le mot de passe et sans le passer en argument : il doit être lisible par un `source` du shell (pense aux caractères spéciaux). Essaie :
   ```
   admin@adm01:~$ ( source ~/.config/workbook/ipa-checks.env; ldapsearch -LLL -H ldaps://ipa01.par1.medisphere.internal \
   >     -D "$IPA_BIND_DN" -y <(printf '%s' "$IPA_BIND_PASSWORD") -b dc=par1,dc=medisphere,dc=internal \
   >     '(cn=plateforme-admins)' member )
   ```
8. Essaie la politique : trois échecs de `kinit lucas.martin` avec un mauvais mot de passe, puis `ipa user-status lucas.martin` (en `admin`). Que vois-tu, et que se passerait-il au sixième ?

**Critères de réussite**
- [ ] `plateforme/identite` existe ; `annuaire/` contient les fichiers attendus ; le Vault est chiffré avec l'identité `critique` ; le dernier pipeline de `main` a réussi, avec un job d'application manuel.
- [ ] Les sept personnes existent, actives, avec leur adresse ; aucun compte de personne n'existe hors de `personnes.yml` (hors `admin`).
- [ ] Les sept groupes ont exactement les membres prévus ; le groupe `admins` de FreeIPA ne contient que `admin`.
- [ ] La politique globale impose 12 caractères, un historique de 6 et un verrouillage après 6 échecs.
- [ ] `svc-keycloak` et `wb-checks` sont déclarés sans mot de passe en clair ; `wb-checks` se lie à l'annuaire depuis `adm01` ; `ipa-checks.env` est en 600.

**Vérification** : `lab/bin/check 24 03`

<details><summary>Indice 1</summary>

Chaque module de la collection a un `README-<module>.md`. Cherche-y le paramètre `action` (`group` ou `member`) : il décide si la liste de membres que tu donnes **remplace** l'existant ou s'y **ajoute**. Les modules acceptent tous `ipaadmin_password` : un bloc `module_defaults` sur le groupe d'actions de la collection évite de le répéter.
</details>

<details><summary>Indice 2</summary>

Pour `ipa-checks.env`, `ansible-vault view` sur la sortie standard, un filtre qui extrait la valeur, et `printf '%q'` pour l'écrire sous une forme que `source` relira telle quelle ; le tout dans un sous-shell avec `umask 077`.
</details>

**Pour aller plus loin** (facultatif) : le compte `admin` sert ici à l'automatisation ; crée plutôt un compte de service avec un rôle FreeIPA limité (*User Administrators*, *Group Administrators*, gestion des comptes système) et mesure ce qui casse. [Modules de `ansible-freeipa`](https://github.com/freeipa/ansible-freeipa#modules) · [FreeIPA : *System accounts*](https://freeipa.readthedocs.io/en/latest/designs/sysaccounts.html)

---

### M24-E04 — Installer Keycloak sur `idp01` et le publier  `LAB` `★★`

> **Ticket PLAT-2504** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Keycloak sur `idp01`, en distribution officielle, avec sa propre base PostgreSQL : pas d'image de conteneur bricolée, pas de base partagée avec NetBox. Publication par `lb01`/`lb02` sous `sso.par1.medisphere.internal`, comme GitLab : TLS jusqu'au bout, et la console d'administration invisible hors du réseau d'administration. Sophie veut deux administrateurs du royaume `master` et pas un de plus : toi, nominativement, avec un second facteur, et un compte de bris de glace au coffre. L'administrateur d'installation disparaît le jour même.

**Objectifs pédagogiques**
- Installer Keycloak en production : archive vérifiée, utilisateur dédié, construction optimisée, unité systemd durcie, base PostgreSQL locale.
- Régler le nom public (`hostname` v2), les mandataires, le TLS et l'interface de gestion (santé, métriques).
- Publier un service derrière HAProxy avec re-chiffrement vérifié, contrôle de santé dédié et filtrage par chemin.
- Amorcer les administrateurs en toute sécurité (compte temporaire, comptes définitifs testés, suppression du temporaire).

**Prérequis** : M24-E02 ; M19-E03 (modèle d'un hôte du socle : `vm-debian`, `certificats_acme`, `pare_feu_local`) ; M07-E13 et M15-E20 (publication par `lb01`/`lb02`) ; M06-E18 (ACME).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `idp01`, VMID 1030, 10.10.20.30, Debian 13, 2 vCPU, 3 Go, 32 Go ; étiquettes `socle`, `role-idp` ; `socle/idp01.tf` |
| Keycloak | **26.7.5**, archive `keycloak-quarkus-dist-26.7.5.tar.gz` de Maven Central (`https://repo1.maven.org/maven2/org/keycloak/keycloak-quarkus-dist/26.7.5/`), avec sa somme `.sha256` publiée à côté ; elle se décompresse en `keycloak-26.7.5/` → `/opt/keycloak-26.7.5`, lien `/opt/keycloak` |
| Java | `openjdk-25-jre-headless` (Debian 13) |
| Base | PostgreSQL 17 de Debian, base et rôle `keycloak`, écoute sur la boucle locale seulement ; mot de passe en Vault `critique` (`host_vars/idp01/vault-critique.yml`) |
| Rôle | `keycloak` (nouveau) ; playbook `playbooks/identite.yml` (groupe `role_idp`) : groupe `keycloak`, `certificats_acme` (id `keycloak`, `/etc/keycloak/tls/keycloak.crt` et `.key`, nom `idp01.par1.medisphere.internal`), `pare_feu_local`, `keycloak` |
| Réglages | HTTPS 8443 seulement ; interface de gestion 9000 (santé, métriques) ; `hostname=https://sso.par1.medisphere.internal` ; en-têtes `X-Forwarded-*` acceptés de `lb01` (10.10.70.10) et `lb02` (10.10.70.11) seulement ; journaux JSON sur la sortie standard ; magasin de confiance sortant = racine MédiSphère ; tas Java `-Xms512m -Xmx1024m` |
| Publication | `sso.par1.medisphere.internal` (A → 10.10.70.200, `publication.tf`) ; certificat ACME `sso` sur les répartiteurs ; backend `be_sso` vers `idp01:8443` en TLS vérifié, santé `GET /health/ready` sur 9000 ; `/admin` et `/realms/master` réservés à 10.10.10.0/24, 10.255.1.0/24 et 10.10.20.15 (`runner01`, pipeline d'OpenTofu en E08) |
| Comptes de `master` | `<MOI>-admin` (rôle `admin`, OTP), `kc-secours` (rôle `admin`, mot de passe de 24 caractères en Vault `critique` et au coffre, pas d'OTP) |

**Travail demandé**

*A. Lire avant d'installer*

1. Lis les guides officiels *Configuring Keycloak for production*, *Configuring the hostname (v2)*, *Using a reverse proxy*, *Configuring the Management Interface*, *Enabling health checks* et *Bootstrapping and recovering an admin account*. Note dans `~/m24/e04/notes.md` : la différence entre `start` et `start --optimized`, les options figées par `kc.sh build`, ce que vérifie `/health/ready`, ce que `proxy-headers=xforwarded` fait confiance à croire, et pourquoi `hostname-backchannel-dynamic` reste à `false` chez nous.
2. Sur `adm01`, télécharge l'archive et sa somme, vérifie-la (`sha256sum -c`), décompresse-la dans `~/m24/e04/` et lance `bin/kc.sh start --help` : retrouve chaque option du contexte technique. Combien d'options y a-t-il en tout ? Lesquelles sont marquées comme options de construction ?

*B. La machine et le rôle*

3. `socle/idp01.tf` (sur le modèle de `mon01.tf`), MR, apply ; ajoute `sso` aux noms publiés de `publication.tf`.
4. Écris le rôle `keycloak`. Exigences :
   - archive téléchargée avec contrôle d'empreinte **avant** décompression ; dossiers de la version propriété de `root`, seul `data/` appartient à `keycloak` ;
   - base et rôle PostgreSQL créés de façon idempotente, mot de passe **jamais** en argument d'une commande ;
   - `keycloak.conf` en 0640 `root:keycloak` (il contient le mot de passe de la base) ;
   - construction (`kc.sh build`) par Ansible, seulement quand la version ou la configuration change, et toujours **avant** le premier démarrage ;
   - unité `keycloak.service` : `start --optimized`, utilisateur `keycloak`, durcissement systemd (le service n'écrit que dans `data/`) ;
   - contrôles : `/health/ready` sur 9000 en HTTPS vérifié, émetteur du royaume `master` égal au nom public, 8080 fermé, PostgreSQL sur la boucle locale seulement.
   Le rôle ne crée **aucun** administrateur.
5. Écris `host_vars/idp01/` (`keycloak.yml`, `certificats.yml`, `pare_feu_local.yml`, `vault-critique.yml`) et `playbooks/identite.yml`. Rôles communs (`site.yml`) puis :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml
   admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
   >   https://idp01.par1.medisphere.internal:9000/health/ready | jq .status
   ```

*C. La publication*

6. Dans `group_vars/role_lb/`, ajoute le certificat `sso` et le backend `be_sso` ; dans `fe_publication`, l'aiguillage par nom et le filtrage par chemin. Pense à ce qu'un client peut mettre dans un chemin pour contourner un filtre par préfixe, et aux en-têtes `X-Forwarded-*` qu'il pourrait envoyer lui-même. Applique sur `lb02` (secours) puis `lb01`. Ouvre les flux de la bordure (DMZ → `idp01` 8443 et 9000 ; VLAN 20 et 40 → VIP 443 si ta matrice ne les a pas déjà).
   ```
   admin@adm01:~$ curl -s https://sso.par1.medisphere.internal/realms/master/.well-known/openid-configuration | jq -r .issuer
   admin@adm01:~$ ssh admin@lb01 'echo "show servers state be_sso" | sudo socat stdio /run/haproxy/admin.sock'
   ```
   Depuis une VM qui n'est ni en MGMT ni sur le VPN (par exemple `mon01`), essaie `/admin/` et `/realms/master/` : quels codes reçois-tu ?

*D. Les administrateurs*

7. Amorce le premier administrateur, **une seule fois**, sans écrire le mot de passe nulle part :
   ```
   admin@idp01:~$ sudo systemctl stop keycloak
   admin@idp01:~$ sudo -u keycloak /opt/keycloak/bin/kc.sh bootstrap-admin user --optimized --username temp-admin
   admin@idp01:~$ sudo systemctl start keycloak
   ```
   Pourquoi faut-il arrêter Keycloak ? Pourquoi `--optimized` ? Que deviendrait ce mot de passe s'il était passé par la variable `KC_BOOTSTRAP_ADMIN_PASSWORD` dans l'unité systemd ?
8. Connecte-toi à `https://sso.par1.medisphere.internal/admin/` en `temp-admin` (bandeau « temporaire »). Dans le royaume `master`, crée `<MOI>-admin` (rôle `admin`, action requise *Configure OTP*) et `kc-secours` (rôle `admin`, mot de passe de 24 caractères, rangé au Vault `critique` et au coffre).
   > ⚠️ **Attention** : garde la session `temp-admin` **ouverte** jusqu'à la fin de cette étape. Dans une **seconde fenêtre privée**, connecte-toi en `<MOI>-admin` (enregistre l'OTP), puis dans une troisième en `kc-secours`. Seulement si les deux entrent et voient la console, supprime `temp-admin` depuis la session `<MOI>-admin`. Si tout est perdu : arrêt de Keycloak et nouvel amorçage (étape 7).
9. Pourquoi deux comptes et pas un seul ? Pourquoi `kc-secours` n'a-t-il pas d'OTP ? Note tes réponses : elles alimenteront le runbook de bris de glace (RB-240, palier 3).

**Critères de réussite**
- [ ] `idp01` existe (NetBox, `role-idp`) ; `sso.par1.medisphere.internal` pointe vers la VIP ; Keycloak 26.7 tourne sous `keycloak` en `start --optimized`, Java 25 ; `keycloak.conf` en 640 `root:keycloak`.
- [ ] 8443 et 9000 en HTTPS (certificat ACME de `idp01` vérifié jusqu'à la racine), 8080 fermé, PostgreSQL sur la boucle locale ; `cert-renewer@keycloak.timer` actif ; `/health/ready` et `/metrics` répondent sur 9000.
- [ ] `https://sso.par1.medisphere.internal` présente un certificat valide ; l'émetteur du royaume `master` est `https://sso.par1.medisphere.internal/realms/master` ; HAProxy contrôle `be_sso` sur `/health/ready` ; la console est refusée hors des réseaux d'administration.
- [ ] Le royaume `master` contient `<MOI>-admin` (OTP enregistré) et `kc-secours`, tous deux `admin` et actifs, et plus aucun administrateur temporaire.

**Vérification** : `lab/bin/check 24 04`

<details><summary>Indice 1</summary>

Dans le guide de production, les options marquées d'un marteau sont de construction : `db`, `health-enabled`, `metrics-enabled`, `cache`, `features`… En changer une sans reconstruire, c'est démarrer une image optimisée qui ne correspond plus à sa configuration. Un témoin (l'empreinte de `keycloak.conf` au moment de la dernière construction) permet de ne reconstruire que quand il le faut.
</details>

<details><summary>Indice 2</summary>

HAProxy compare les chemins **tels qu'ils arrivent** : `/realms/%6Daster` n'est pas `/realms/master` pour une ACL, mais peut l'être pour le serveur derrière. Plutôt qu'une liste de chemins interdits, une liste de chemins **permis** au public (le royaume `medisphere`, les ressources statiques), et un refus net de tout ce qui contient `..` ou des caractères encodés suspects. Pour le contrôle de santé sur un autre port que le trafic, relis `port` et `check-ssl` dans la documentation des options de serveur.
</details>

<details><summary>Indice 3</summary>

`kc.sh bootstrap-admin user` démarre une instance de Keycloak le temps de créer le compte : elle ne doit pas cohabiter avec le service en marche (même base, mêmes caches). Sans `--password:env`, il demande le mot de passe au terminal.
</details>

**Pour aller plus loin** (facultatif) : le chart `codecentric/keycloakx` déploierait Keycloak dans `k8s-par1` ; liste ce qui change (image avec JDK 21, base, sondes, publication) et pourquoi l'IdP de la plateforme reste hors du cluster qu'il authentifie. [Keycloak : *Configuring for production*](https://www.keycloak.org/server/configuration-production) · [*Using a reverse proxy*](https://www.keycloak.org/server/reverseproxy) · [*Hostname v2*](https://www.keycloak.org/server/hostname)

---

### M24-E05 — Premiers pas dans Keycloak : royaumes, clients, utilisateurs  `LAB` `★`

> **Ticket PLAT-2505** — *De : Karim Benali*
> Avant d'écrire le royaume en code, fais-le une fois à la main dans la console : on ne décrit bien que ce qu'on a vu. Un royaume `medisphere`, un client d'essai, un utilisateur d'essai pour tester, et le compte de service des vérifications. Tout ce qui sera gardé sera repris dans OpenTofu en E08, le reste supprimé.

**Objectifs pédagogiques**
- Se repérer dans la console d'administration : royaumes, clients, portées, utilisateurs, sessions, événements.
- Créer un client OIDC confidentiel avec une redirection exacte et PKCE, et un client de compte de service.
- Donner des droits d'administration **en lecture seule** à un compte de service.

**Prérequis** : M24-E04.
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Royaume | `medisphere`, nom affiché « MédiSphère », inscription libre fermée |
| Client d'essai | `essai-oidc` : authentification du client activée (confidentiel), flux standard seulement (ni implicite, ni *Direct Access Grants*), URI de redirection **exacte** `http://localhost:8765/rappel`, PKCE `S256` exigé |
| Utilisateur d'essai | un compte **local** du royaume, au nom sans ambiguïté (par exemple `essai.local`), supprimé en E06 |
| Client des vérifications | `wb-checks` : confidentiel, comptes de service seulement, rôles `view-realm`, `view-users`, `view-clients` du client `realm-management` |
| Fichier | `~/.config/workbook/keycloak-checks.env` (600) : `KEYCLOAK_CLIENT_ID=wb-checks`, `KEYCLOAK_CLIENT_SECRET=…` |

**Travail demandé**

1. Connecte-toi à la console en `<MOI>-admin`. Parcours le royaume `master` sans rien changer : quels clients y existent déjà, et à quoi sert `admin-cli` ? Que contient le client `<royaume>-realm` qui apparaîtra quand tu auras créé `medisphere` ?
2. Crée le royaume `medisphere`. Dans *Realm settings*, relève les durées par défaut (jeton d'accès, session SSO inactive et maximale) et les réglages de connexion. Dans *Client scopes*, liste les portées par défaut : lesquelles sont ajoutées à tout nouveau client ?
3. Crée le client `essai-oidc` selon le contexte technique. Retrouve dans ses écrans où se règlent chacune des exigences (authentification du client, flux autorisés, redirections, PKCE dans les réglages avancés).
4. Crée l'utilisateur local d'essai, donne-lui un mot de passe (non temporaire), et connecte-toi avec lui à la console de compte `https://sso.par1.medisphere.internal/realms/medisphere/account/` dans une fenêtre privée. Dans la console d'administration, regarde ensuite *Sessions* : que vois-tu, et que se passe-t-il si tu « déconnectes » la session ?
5. Crée le client `wb-checks` et attribue à son compte de service les trois rôles de lecture, **et aucun autre**. Copie son secret dans `keycloak-checks.env` sans l'afficher dans le terminal (presse-papiers puis éditeur, ou `read -rs`), en 600. Essaie :
   ```
   admin@adm01:~$ lab/bin/check 24 05
   ```
   Ce check obtient un jeton par `client_credentials` puis lit l'API d'administration. Que se passerait-il si `wb-checks` avait `manage-users` et que son secret fuyait ? Et avec ses seuls rôles de lecture : que lit-il exactement d'un client **confidentiel** comme `essai-oidc` (représentation complète, `…/clients/<id>/client-secret`) ? Qu'en déduis-tu sur la protection de `keycloak-checks.env` ?
6. Note dans `~/m24/e05/notes.md` chaque objet créé et son identifiant (dans l'URL de la console) : E08 en aura besoin.

**Critères de réussite**
- [ ] Le royaume `medisphere` existe, nom affiché « MédiSphère », inscription libre fermée ; sa découverte OIDC publie l'émetteur `https://sso.par1.medisphere.internal/realms/medisphere`.
- [ ] `essai-oidc` est confidentiel, en flux standard seul, avec la seule redirection `http://localhost:8765/rappel` et PKCE `S256` exigé.
- [ ] Un utilisateur local d'essai existe (aucun personnage n'est créé à la main).
- [ ] `wb-checks` est un client à compte de service seul, avec exactement `view-realm`, `view-users`, `view-clients` ; `keycloak-checks.env` est en 600.

**Vérification** : `lab/bin/check 24 05`

<details><summary>Indice 1</summary>

Dans la console récente, l'onglet *Credentials* n'apparaît qu'une fois l'authentification du client activée ; les rôles d'un compte de service s'attribuent dans l'onglet *Service accounts roles* du client, en filtrant sur les rôles **de clients** (`realm-management`).
</details>

<details><summary>Indice 2</summary>

Une redirection « exacte » n'a ni joker `*`, ni chemin partiel : Keycloak compare la chaîne entière. Le réglage PKCE se trouve dans *Advanced* → *Advanced settings* du client.
</details>

**Pour aller plus loin** (facultatif) : crée un second royaume jetable et compare l'isolement (utilisateurs, clés de signature, émetteur), puis supprime-le. [Keycloak : *Server Administration Guide*](https://www.keycloak.org/docs/latest/server_admin/)

---

### M24-E06 — Fédérer l'annuaire FreeIPA dans Keycloak  `LAB` `★★`

> **Ticket PLAT-2506** — *De : Sophie Laurent*
> Les personnes sont dans l'annuaire : Keycloak doit les y trouver, vérifier leur mot de passe auprès de lui, et lire leurs groupes. Il ne doit **jamais** y écrire : un mot de passe changé, une personne désactivée, un groupe modifié, c'est dans l'annuaire, par le dépôt. Et les jetons doivent porter les groupes, sous leur nom court : tous nos services en décideront les droits.

**Objectifs pédagogiques**
- Configurer une fédération LDAPS en lecture seule avec un compte système et un magasin de confiance maîtrisé.
- Comprendre l'import, la synchronisation périodique et la vérification du mot de passe par liaison LDAP.
- Faire porter les groupes de l'annuaire dans les jetons par une portée dédiée.

**Prérequis** : M24-E03, M24-E05.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fédération | nom `ipa01`, éditeur *Red Hat Directory Server*, `ldaps://ipa01.par1.medisphere.internal`, magasin de confiance de Keycloak (racine MédiSphère, `truststore-paths`), liaison simple par `uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal` |
| Personnes | `cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal`, un seul niveau, identifiant `uid`, identifiant stable `ipaUniqueID`, classes `inetOrgPerson, organizationalPerson`, filtre qui exclut `admin` de FreeIPA ; mode `READ_ONLY` |
| Synchronisation | complète une fois par jour, changements toutes les 15 minutes |
| Groupes | mappeur `groupes-ipa` : `cn=groups,cn=accounts,…`, attribut `member` (DN), mode `READ_ONLY`, filtre limité aux sept groupes de personnes |
| Portée | `groupes` (OpenID Connect), mappeur *Group Membership* `groups` : revendication `groups`, chemin complet **désactivé**, dans l'ID token, le jeton d'accès, userinfo et l'introspection ; portée **par défaut** du royaume |
| Flux | `idp01` → `ipa01` 636 (même VLAN : firewalld de `ipa01` seulement) |

**Travail demandé**

1. Depuis `idp01`, vérifie que l'annuaire est joignable et que son certificat se vérifie avec la racine du lab, avant de toucher à Keycloak :
   ```
   admin@idp01:~$ openssl s_client -connect ipa01.par1.medisphere.internal:636 -verify_return_error \
   >   -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null 2>&1 | grep 'Verify return'
   ```
   Pourquoi n'a-t-il fallu ajouter aucun certificat au magasin de confiance de Keycloak ?
2. Crée la fédération dans la console selon le contexte technique (mot de passe de `svc-keycloak` collé depuis le Vault, jamais tapé dans un fichier). Utilise *Test connection* et *Test authentication*. Lis ce que fait chaque option de la section *Synchronization settings* et *Advanced settings* que tu touches.
3. Lance une synchronisation complète. Combien de personnes ont été importées ? `admin` en fait-il partie ? Ouvre `lucas.martin` dans *Users* : d'où viennent ses attributs, et que se passe-t-il si tu essaies de modifier son adresse ?
4. Ajoute le mappeur de groupes, synchronise les groupes. Vérifie que `lucas.martin` est dans `plateforme` et pas dans `plateforme-admins`, et qu'aucun groupe interne de FreeIPA (`admins`, `ipausers`…) n'est arrivé.
5. Crée la portée `groupes` et son mappeur, fais-en une portée **par défaut** du royaume. Ajoute-la aussi au client `essai-oidc`, créé avant elle : pourquoi ne l'a-t-il pas reçue tout seul ?
6. Connecte-toi à la console de compte (`…/realms/medisphere/account/`) en `lucas.martin`, avec le mot de passe qu'il a choisi en E03. Puis, en `admin` sur `ipa01`, désactive-le (`ipa user-disable lucas.martin`) et réessaie : à quel moment le refus arrive-t-il, et pourquoi pas plus tard ? Réactive-le par le **dépôt** : relance le job d'application de l'annuaire (la personne est déclarée active dans `personnes.yml`).
7. Supprime l'utilisateur local d'essai d'E05. Le royaume n'a plus une seule personne qui ne vienne de l'annuaire.

**Critères de réussite**
- [ ] Une seule fédération LDAP : LDAPS vers `ipa01`, liaison par `svc-keycloak`, `READ_ONLY`, `uid` et `ipaUniqueID`, `admin` exclu, changements synchronisés toutes les 900 s.
- [ ] Le mappeur de groupes lit `cn=groups,cn=accounts` en lecture seule ; les sept groupes de personnes sont dans Keycloak, aucun groupe interne de FreeIPA.
- [ ] `lucas.martin` est importé (lien de fédération), avec son adresse, membre de `plateforme` et pas de `plateforme-admins`.
- [ ] La portée `groupes` met `groups` (noms courts) dans l'ID token, le jeton d'accès et userinfo, et elle est portée par défaut du royaume.
- [ ] Plus aucun utilisateur local dans le royaume ; autant de personnes fédérées que dans l'annuaire (hors `admin`).

**Vérification** : `lab/bin/check 24 06`

<details><summary>Indice 1</summary>

L'éditeur *Red Hat Directory Server* préremplit des valeurs adaptées à 389-ds. Chez FreeIPA, l'identifiant immuable d'une personne est `ipaUniqueID` : un renommage ne doit pas créer une seconde personne dans Keycloak. Le champ *Custom user LDAP filter* accepte un filtre LDAP complet entre parenthèses.
</details>

<details><summary>Indice 2</summary>

Avec le chemin complet, la revendication vaudrait `/plateforme-admins` ; Argo CD, Grafana et kube-apiserver compareraient alors des chaînes qui ne correspondent jamais à leurs règles. Le refus d'une personne désactivée tient à ce que Keycloak vérifie le mot de passe par une liaison LDAP à **chaque** connexion.
</details>

**Pour aller plus loin** (facultatif) : essaie le mode *Kerberos* de la fédération (authentification par ticket du navigateur, SPNEGO) et liste ce qu'il faudrait côté postes. [Keycloak : *LDAP and Active Directory*](https://www.keycloak.org/docs/latest/server_admin/#_ldap)

---

### M24-E07 — OIDC à la main : code d'autorisation, PKCE, jetons et découverte  `LAB` `★★`

> **Ticket PLAT-2507** — *De : Karim Benali*
> Au palier suivant, dix services vont faire de l'OIDC à notre place, et le jour où l'un d'eux refusera un jeton, il faudra savoir lire ce qui circule. Fais-le une fois toi-même : un navigateur, `curl`, `jq`, `openssl`, et rien d'autre. Écris ce que tu observes ; ne recopie aucun jeton complet dans le compte rendu.

**Objectifs pédagogiques**
- Lire la découverte OIDC et les clés publiques (JWKS) d'un royaume.
- Dérouler un flux de code d'autorisation avec PKCE : défi, redirection, `state`, `nonce`, échange du code.
- Décoder et comparer l'ID token, le jeton d'accès et le jeton de rafraîchissement ; utiliser userinfo, l'introspection, le rafraîchissement et la déconnexion.
- Constater ce que PKCE, l'audience et l'URI de redirection exacte empêchent.

**Prérequis** : M24-E06.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Client | `essai-oidc` (confidentiel, PKCE `S256`, redirection `http://localhost:8765/rappel`) ; son secret dans `~/m24/e07/essai-oidc.secret` (600, supprimé en fin d'exercice) |
| Utilisateur | `lucas.martin` (annuaire) |
| Navigateur | ton poste par le VPN d'administration ; rien n'écoute sur `localhost:8765` : la page d'erreur de connexion du navigateur est normale, le code est dans la **barre d'adresse** |
| Durées | le code d'autorisation vaut **une minute** et ne sert qu'une fois : prépare la commande d'échange avant d'ouvrir l'URL |
| Compte rendu | `docs/securite/identite/oidc-a-la-main.md` de `plateforme/medisphere` |

**Travail demandé**

*A. Ce que publie le royaume*

1. Lis la découverte et les clés :
   ```
   admin@adm01:~$ E=https://sso.par1.medisphere.internal/realms/medisphere
   admin@adm01:~$ curl -s $E/.well-known/openid-configuration | jq '{issuer, authorization_endpoint, token_endpoint,
   >   userinfo_endpoint, introspection_endpoint, end_session_endpoint, jwks_uri, code_challenge_methods_supported}'
   admin@adm01:~$ curl -s $E/protocol/openid-connect/certs | jq '.keys[] | {kid, kty, alg, use}'
   ```
   À quoi sert chaque point de terminaison ? Pourquoi y a-t-il plusieurs clés, et pourquoi aucune ne contient de partie privée ?

*B. Le flux de code avec PKCE*

2. Prépare dans un shell, **sans les écrire dans un fichier** : un `code_verifier` (43 à 128 caractères base64url, aléatoires), le `code_challenge` correspondant (`S256` : base64url, sans `=`, du SHA-256 du verifier), un `state` et un `nonce` aléatoires. Construis l'URL d'autorisation (`client_id`, `response_type=code`, `scope=openid`, `redirect_uri`, `state`, `nonce`, `code_challenge`, `code_challenge_method`).
3. Ouvre l'URL dans une fenêtre privée, connecte-toi en `lucas.martin`. Relève dans la barre d'adresse les paramètres de retour : `state` est-il le tien ? Que contient `iss` ? Échange **immédiatement** le code :
   ```
   admin@adm01:~/m24/e07$ curl -s -K <(printf 'user = "essai-oidc:%s"\n' "$(<essai-oidc.secret)") \
   >   -d grant_type=authorization_code -d "code=$CODE" -d redirect_uri=http://localhost:8765/rappel \
   >   -d "code_verifier=$VERIFIER" $E/protocol/openid-connect/token > jetons.json
   ```
   Pourquoi le secret passe-t-il par `-K <(…)` et pas par `-u` ? Le fichier `jetons.json` contient des jetons valables : où doit-il vivre, et combien de temps ?
4. Décode l'en-tête et la charge de chaque jeton (base64url : pense aux caractères `-` et `_`, et au rembourrage absent). Pour l'ID token, le jeton d'accès et le jeton de rafraîchissement, relève `typ`, l'algorithme et `kid`, `iss`, `aud`, `azp`, `exp - iat`, `nonce`, `sid`, `groups`. Que dit `aud` de chacun ? À qui chacun est-il destiné ?

*C. Ce qu'on fait des jetons*

5. Appelle `userinfo` avec le jeton d'accès (en-tête `Authorization: Bearer`, passé lui aussi par `-K`). Puis introspecte ce même jeton (client authentifié, jeton envoyé sur l'entrée standard de `curl`, sans retour à la ligne final). Que répond Keycloak ? Cherche la raison dans le journal de Keycloak (`journalctl -u keycloak` sur `idp01`, événement `INTROSPECT_TOKEN_ERROR`) et corrige-la dans la console par un mappeur sur le client `essai-oidc`. Refais un flux complet et l'introspection.
6. Rafraîchis les jetons (`grant_type=refresh_token`) : qu'est-ce qui change, qu'est-ce qui reste ? Puis déconnecte la session (`POST` sur `end_session_endpoint` avec le jeton de rafraîchissement, client authentifié). Réintrospecte et rappelle `userinfo` avec l'**ancien** jeton d'accès. Un service qui vérifie la signature lui-même, sans appeler Keycloak, accepterait-il encore ce jeton ? Jusqu'à quand ?

*D. Ce qui est refusé*

7. Recommence l'autorisation **sans** `code_challenge` ; puis avec une `redirect_uri` différente (`…/autre`) ; puis échange un code avec un mauvais verifier, et réessaie le même code avec le bon. Note chaque réponse. Que se serait-il passé, sans PKCE, si un journal de mandataire avait gardé l'URL de retour ?
8. Écris le compte rendu `oidc-a-la-main.md` (découverte, flux, tableau comparatif des trois jetons, userinfo, introspection et audience, rafraîchissement, déconnexion, refus) avec des extraits **tronqués**. Supprime `~/m24/e07/essai-oidc.secret` et `jetons.json`.

**Critères de réussite**
- [ ] La découverte publie tous les points de terminaison sous l'émetteur public et annonce `S256` ; le JWKS contient au moins une clé RS256 de signature, sans partie privée.
- [ ] `essai-oidc` porte un mappeur d'audience qui met `essai-oidc` dans le jeton d'accès ; PKCE `S256` et l'absence de *Direct Access Grants* sont inchangés.
- [ ] Le compte rendu, sur `main`, traite PKCE, les revendications (`iss`, `aud`, `azp`, `exp`, `nonce`), l'introspection, le rafraîchissement, la déconnexion et les refus, sans aucun jeton complet.

**Vérification** : `lab/bin/check 24 07`

<details><summary>Indice 1</summary>

`openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n'` donne un verifier valable ; le défi est le SHA-256 **binaire** (`openssl dgst -sha256 -binary`) encodé en base64 puis transformé de la même façon. `jq -R 'split(".") | .[1] | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson'` décode la charge d'un JWT.
</details>

<details><summary>Indice 2</summary>

Keycloak 26 n'introspecte pour un client que les jetons dont il est **destinataire** : regarde `aud` du jeton d'accès. Un mappeur de type *Audience* sur le client ajoute un destinataire. Pour envoyer un jeton à `curl` sans retour à la ligne, `printf '%s' "$JETON" | curl … --data-urlencode "token@-"`.
</details>

<details><summary>Indice 3</summary>

Un code d'autorisation consommé, même par un échange raté, ne sert plus. Si l'échange échoue avec `invalid_grant`, recommence le flux depuis l'URL d'autorisation.
</details>

**Pour aller plus loin** (facultatif) : vérifie la signature d'un ID token à la main avec la clé du JWKS (reconstruire une clé publique RSA à partir de `n` et `e`) : c'est l'objet de M24-E44. [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html) · [RFC 7636 (PKCE)](https://www.rfc-editor.org/rfc/rfc7636) · [RFC 7662 (introspection)](https://www.rfc-editor.org/rfc/rfc7662)

---

### M24-E08 — Keycloak en code avec OpenTofu  `LAB` `★★`

> **Ticket PLAT-2508** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Le royaume a été fait à la main, c'était voulu. Maintenant on le reprend en code : ce qui existe est **importé**, pas recréé (les secrets des clients et les identifiants des personnes ne doivent pas changer), le plan doit être vide après l'import, et le client d'essai disparaît par une MR, pas par un clic. Même chaîne que `plateforme/infra` : plan sur les MR, apply manuel sur `main`, état chiffré sur `s3-01`.

**Objectifs pédagogiques**
- Piloter Keycloak par OpenTofu avec un compte de service aux droits limités à un royaume.
- Importer des objets existants (blocs `import`) et faire converger le code jusqu'à un plan vide.
- Garder les secrets hors du code et de l'état (variables éphémères, arguments en écriture seule) et protéger l'état qui en contient d'autres.
- Supprimer par le code, avec la trace de la MR.

**Prérequis** : M24-E07 ; M05-E11 à E27 (état S3, verrou, pipeline, chiffrement de l'état).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fournisseur | **`keycloak/keycloak` `~> 5.10`** (suite de `mrparkers/keycloak`) ; OpenTofu 1.13 |
| Code | `tofu/` de `plateforme/identite` : `fournisseurs.tf` (contraintes, état, fournisseur), `chiffrement.tf` (identique à `plateforme/infra`), `variables.tf`, `royaume.tf`, `federation-ldap.tf`, `portees.tf`, `comptes-service.tf`, `imports.tf`, et provisoirement `clients-essai.tf` |
| État | S3 `https://s3-01.par1.medisphere.internal:8333`, compartiment `tofu-state`, clé **`identite/terraform.tfstate`**, verrou natif, chiffré côté client (`TF_ENCRYPTION`, M05-E27) |
| Compte d'OpenTofu | client **`svc-tofu-keycloak`** du royaume **`master`** : comptes de service seulement, rôles du client `medisphere-realm` de `master` **sauf** `impersonation` ; secret dans `~/.config/workbook/keycloak-tofu.env` (`KEYCLOAK_CLIENT_ID`, `KEYCLOAK_CLIENT_SECRET`) et en variables protégées de CI |
| Secret de la fédération | mot de passe de `svc-keycloak` : variable **éphémère** `svc_keycloak_mot_de_passe`, argument **`bind_credential_wo`** ; fourni par l'environnement (`TF_VAR_…`) |
| Pipeline | sur le modèle de `plateforme/infra` : `fmt`/`validate`, `plan` enregistré (MR et `main`), `apply` manuel sur `main` qui applique ce plan puis exige un plan vide ; `runner01` joint `sso…/realms/master` et `/admin` (HAProxy, E04) |

**Travail demandé**

*A. Le compte d'OpenTofu*

1. Dans le royaume `master`, en `<MOI>-admin`, crée `svc-tofu-keycloak` selon le contexte technique. Liste les rôles du client `medisphere-realm` : que permet chacun, et pourquoi retirer `impersonation` ? Pourquoi ne lui donne-t-on pas le rôle `admin` de `master`, ni `create-realm` ? Range son secret dans `keycloak-tofu.env` (600) et dans les variables protégées et masquées du projet.

*B. Le code et l'import*

2. Lis la documentation du fournisseur pour les ressources `keycloak_realm`, `keycloak_ldap_user_federation`, `keycloak_ldap_group_mapper`, `keycloak_openid_client_scope`, `keycloak_openid_group_membership_protocol_mapper`, `keycloak_realm_default_client_scopes`, `keycloak_openid_client`, `keycloak_openid_client_service_account_role`, et la section **Import** de chacune : quel identifiant attend-elle ?
3. Écris les fichiers de `tofu/` pour décrire **ce qui existe** : le royaume, la fédération et son mappeur de groupes, la portée `groupes` et son mappeur, les portées par défaut, `wb-checks` et ses rôles, et `essai-oidc`. Le mot de passe de `svc-keycloak` ne doit apparaître ni dans le code ni dans l'état. Écris `imports.tf` avec les identifiants relevés en E05-E06 (la console les montre dans ses URL ; l'API d'administration aussi, avec le compte d'OpenTofu).
4. Écris `outils/charger-acces.sh` (à sourcer) qui charge, sans les afficher, les accès S3, le compte d'OpenTofu, la phrase de chiffrement et le mot de passe de `svc-keycloak` lu dans `annuaire/vault-critique.yml`. Puis :
   ```
   admin@adm01:~/src/identite$ . outils/charger-acces.sh
   admin@adm01:~/src/identite$ tofu -chdir=tofu init && tofu -chdir=tofu plan
   ```
   Fais converger le code jusqu'à ce que le plan n'annonce **que** les imports et la seule mise à jour attendue (laquelle, et pourquoi elle est inévitable la première fois ?). Pour chaque autre différence, décide : le code se trompe (corrige-le), ou la réalité ne convient pas (laisse le plan la changer, et écris-le dans la MR).

*C. Le pipeline et la suppression*

5. Complète `.gitlab-ci.yml` (étapes `plan` et `appliquer` d'OpenTofu, à côté de celles de l'annuaire), `outils/ci-preparer.sh`, les variables protégées. Versionne `.terraform.lock.hcl`. Première MR (« import du royaume ») : relis le plan du pipeline, fusionne, lance l'apply, vérifie le plan vide qui suit.
6. Seconde MR : supprime `clients-essai.tf` et l'import correspondant. Que montre le plan ? Fusionne et applique. Vérifie dans la console que `essai-oidc` n'existe plus.
7. Contrôle ce que contient l'état : `tofu -chdir=tofu state pull | jq '.resources[] | {type, name}'`. Y a-t-il des secrets dedans, malgré tes précautions ? Lesquels, et pourquoi le chiffrement de l'état n'est-il pas une option ici ?
   > ⚠️ **Attention** : `tofu state pull` affiche l'état **déchiffré** dans ton terminal. Ne le redirige pas vers un fichier, ne le colle nulle part.

**Critères de réussite**
- [ ] `tofu/` est sur `main` avec le fournisseur `keycloak/keycloak` en `~> 5.10`, l'état `identite/terraform.tfstate` du compartiment `tofu-state` avec verrou, le chiffrement imposé, et le verrou des versions versionné.
- [ ] Le mot de passe de `svc-keycloak` passe par `bind_credential_wo` ; aucun secret littéral dans le code.
- [ ] Le pipeline fait un plan sur les MR et un apply manuel sur `main` ; le dernier pipeline de `main` a réussi, plan vide après l'apply.
- [ ] `essai-oidc` n'existe plus, supprimé par une MR ; la fédération et la portée `groupes` sont intactes ; `svc-tofu-keycloak` vit dans `master` ; `keycloak-tofu.env` est en 600.

**Vérification** : `lab/bin/check 24 08`

<details><summary>Indice 1</summary>

Le royaume s'importe par son **nom** ; la plupart des autres objets par `royaume/identifiant`, les mappeurs de protocole par `royaume/client-scope/<portée>/<mappeur>`, les rôles d'un compte de service par quatre identifiants. Les portées par défaut s'importent par le nom du royaume : la liste que tu écris doit être **complète**, telle que la console la montre.
</details>

<details><summary>Indice 2</summary>

Une source de données qui dépend d'une ressource en cours d'import n'est lue qu'à l'apply : tout ce qui en dépend devient « à remplacer » au premier plan. Donne-lui des valeurs connues d'avance. Un argument en écriture seule n'est jamais relu : OpenTofu ne sait le pousser que par un numéro de version qui change ; à l'import, il le pousse une fois.
</details>

<details><summary>Indice 3</summary>

Les attributs que la console pose d'elle-même à la création d'un client (jetons de rafraîchissement, déconnexion par canal arrière) n'ont pas forcément la même valeur par défaut dans le fournisseur : écris-les explicitement.
</details>

**Pour aller plus loin** (facultatif) : les mappeurs d'attributs créés d'office avec la fédération (`username`, `email`…) restent hors du code ; importe-les avec `keycloak_ldap_user_attribute_mapper`, ou décide par écrit de les laisser. Compare avec `keycloak-config-cli` (6.5, images arrêtées à Keycloak 26.5). [Fournisseur `keycloak/keycloak`](https://search.opentofu.org/provider/keycloak/keycloak/latest) · [OpenTofu : *Import*](https://opentofu.org/docs/language/import/) · [*Ephemeral and write-only*](https://opentofu.org/docs/language/ephemerality/)

---

### M24-E09 — Questions : OIDC, OAuth 2.0, SAML, LDAP et Kerberos  `Q` `★★`

> **Ticket PLAT-2509** — *De : Karim Benali*
> Tu as tout fait une fois à la main. Avant de brancher dix services, vérifions que le *pourquoi* est clair. Par écrit, avec tes propres mots ; appuie-toi sur ce que tu as observé en E06 et E07.

**Objectifs pédagogiques**
- Expliquer les choix des protocoles (flux, jetons, audience, liaison des requêtes) à partir de ce que tu as observé.
- Distinguer les rôles de l'annuaire et du fournisseur d'identité, de la fédération et de la synchronisation.

**Prérequis** : M24-E02 à M24-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 11 questions.

1. Décris le flux de **code d'autorisation** en six à huit étapes, en indiquant pour chacune qui parle à qui (navigateur, client, fournisseur) et ce qui passe par le navigateur.

2. Pourquoi le flux **implicite** (jetons renvoyés directement dans l'URL) est-il abandonné par les bonnes pratiques actuelles d'OAuth ? Et le flux *Resource Owner Password Credentials* (les *Direct Access Grants* de Keycloak), désactivé chez nous ?

3. *(QCM)* Grafana reçoit un ID token et un jeton d'accès. Lequel doit-il utiliser pour savoir **qui** s'est connecté, et lequel présenterait-il à une API ?
   - A. Le jeton d'accès pour les deux
   - B. L'ID token pour savoir qui s'est connecté ; le jeton d'accès pour appeler une API
   - C. L'ID token pour les deux
   - D. Aucun : il doit toujours appeler userinfo

4. À quoi sert la revendication `aud` ? Raconte l'attaque qu'on empêche en la vérifiant (un jeton délivré pour un service présenté à un autre), et ce que tu as vu en E07 quand `essai-oidc` n'était pas destinataire de son propre jeton d'accès.

5. `state` et `nonce` : à quoi sert chacun, où le client le retrouve-t-il, et que se passe-t-il si un client oublie de le vérifier ?

6. *(QCM)* Le paramètre `iss` ajouté à la réponse d'autorisation (RFC 9207) protège contre :
   - A. le vol du code par un journal de mandataire
   - B. la confusion entre plusieurs fournisseurs d'identité (*mix-up*) chez un client qui en utilise plusieurs
   - C. l'expiration du jeton d'accès
   - D. la falsification de la signature

7. SAML 2.0 : qu'est-ce qu'une **assertion**, qui la signe, et par où passe-t-elle ? Donne deux situations où MédiSphère devra encore parler SAML, et dis pourquoi le lab choisit OIDC pour ses propres services.

8. LDAP et Kerberos dans FreeIPA : qu'apporte chacun ? Pourquoi Keycloak vérifie-t-il les mots de passe par une liaison LDAP et pas par Kerberos, et dans quel cas ferait-on l'inverse ?

9. *(QCM)* Keycloak **fédère** l'annuaire en `READ_ONLY`. Une personne change son mot de passe dans l'interface de FreeIPA. Que se passe-t-il à sa prochaine connexion à Grafana ?
   - A. Elle doit attendre la synchronisation de 15 minutes
   - B. Le nouveau mot de passe fonctionne immédiatement : Keycloak le vérifie par une liaison LDAP à chaque connexion
   - C. L'ancien mot de passe fonctionne jusqu'à la synchronisation complète de la nuit
   - D. Keycloak refuse : il ne connaît que l'empreinte du mot de passe qu'il a importée

10. Fédération ou synchronisation : explique la différence, puis dis ce que fait **vraiment** la synchronisation périodique de Keycloak dans notre configuration (que copie-t-elle, à quoi sert-elle, qu'est-ce qu'elle ne fait pas).

11. Rôle de l'**IdP** et rôle de l'**annuaire** : répartis entre FreeIPA, Keycloak et les services les responsabilités suivantes, en justifiant : existence d'une personne, appartenance à un groupe, mot de passe, second facteur, session SSO, durée des jetons, droits dans Argo CD, accès SSH à une VM, sudo.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 11 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) et calculé ton score sur 22.
- [ ] Pour chaque réponse fausse, tu as relu l'exercice du palier où tu l'as observé.

<details><summary>Indice 1</summary>

Reprends ton compte rendu d'E07 : chaque question du bloc OIDC y a une observation (paramètres de retour, revendications, refus).
</details>

<details><summary>Indice 2</summary>

Pour la question 11, demande-toi pour chaque responsabilité : qui doit pouvoir la changer, et où l'auditeur ira-t-il en chercher la preuve ?
</details>

**Pour aller plus loin** (facultatif) : lis la RFC 9700 (*OAuth 2.0 Security Best Current Practice*) et le brouillon d'OAuth 2.1 : liste ce qui change par rapport à la RFC 6749. [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700) · [SAML 2.0 Technical Overview (OASIS)](https://docs.oasis-open.org/security/saml/Post2.0/sstc-saml-tech-overview-2.0.html)

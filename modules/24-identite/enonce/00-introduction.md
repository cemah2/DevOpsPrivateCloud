# Module 24 — Introduction : identité et accès

## Trois semaines pour couper deux comptes

Mardi, 9 h 10. La RSSI a envoyé hier soir à la direction le relevé qu'elle prépare pour l'audit HDS. Claire Morel le transmet à l'équipe Plateforme avec sa décision.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
> **Objet** : Une identité par personne — fin des comptes locaux
>
> Bonjour,
>
> Sophie a compté : GitLab, Argo CD, Grafana, Harbor, Proxmox, PBS, NetBox, Mailpit et le cluster ont **chacun** leurs comptes, leurs mots de passe, leurs oublis. Quand le prestataire d'InfoGér est parti, il a fallu trois semaines pour retrouver ses accès, et deux étaient encore actifs le mois dernier. L'auditeur HDS nous demandera la liste de qui a accès à quoi, et la preuve qu'un départ coupe tout. Nous ne savons fournir ni l'une ni l'autre.
>
> Ce que je veux à la fin du module :
> 1. un **annuaire** unique des personnes et de leurs groupes, géré en code ;
> 2. un **fournisseur d'identité** devant tous nos services : une connexion, un mot de passe, et un **second facteur** pour quiconque administre ;
> 3. des droits qui **découlent des groupes**, jamais attribués personne par personne ;
> 4. plus de certificats `kubectl` de sept jours ni de clés SSH éternelles : des jetons et des certificats de quelques heures ;
> 5. une **porte de secours** par service, qu'on a essayée, et dont l'usage se voit.
>
> Les règles de la maison s'appliquent : Git et MR pour tout, Ansible pour les VMs, OpenTofu pour ce qui a une API, Argo CD pour le cluster, aucun secret en clair. Et une règle de plus, qui passe avant les autres : **on ne change jamais une authentification sans un accès de secours ouvert et testé**. Je ne veux pas apprendre qu'on s'est enfermés dehors.
>
> Premier jalon : l'annuaire, Keycloak publié, le royaume `medisphere` relié à l'annuaire, et tout ça en code. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 24, MédiSphère a son identité **v1** (étiquette `identite-v1` de `plateforme/medisphere`), reprise par le M25 (OpenBao s'authentifie par Keycloak), le M26 et les workbooks finaux :

- **`ipa01`** (Rocky Linux 10) : **FreeIPA 4.13**, annuaire LDAP et Kerberos (`PAR1.MEDISPHERE.INTERNAL`) des personnes et des groupes, règles HBAC et sudo, CA **subordonnée** à « MédiSphère Root CA » ;
- **`idp01`** (Debian 13) : **Keycloak** (26.7, monté en 26.8.1 au palier 3) et sa base PostgreSQL 17, publié en `https://sso.par1.medisphere.internal` par `lb01`/`lb02` ;
- le projet **`plateforme/identite`** : l'annuaire en Ansible (`freeipa.ansible_freeipa`) et le royaume `medisphere` en OpenTofu (`keycloak/keycloak`) ;
- le **SSO** de GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, du cluster (`kubectl` par OIDC) et, par **OAuth2 Proxy**, de Hubble, Pyroscope et Mailpit ; les VMs inscrites dans l'annuaire, des certificats SSH de 16 h délivrés après SSO ;
- l'OTP obligatoire pour les administrateurs, les procédures d'arrivée et de départ, la revue des accès, le bris de glace (palier 2 et 3).

Le **palier 1** (ce fichier et `01-decouverte.md`) construit les fondations : l'annuaire et sa CA, les personnes en code, Keycloak publié, un royaume créé à la main pour comprendre, la fédération de l'annuaire, un flux OIDC déroulé à la main jusqu'aux octets, puis le royaume repris en code. Aucun service n'est encore branché : c'est le palier 2. Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module (fin du palier 1)

```
                     navigateur (poste, VPN wg1 10.255.1.0/24)          adm01 (MGMT 10.10.10.10)
                                 │  https://sso.par1.medisphere.internal     │ tofu · ansible · curl · jq · ldapsearch
                                 ▼                                           ▼
 ════════ gw01/gw02 (bordure : DMZ ⇄ INFRA, VLAN 40 → ipa01, VLAN 20/40 → VIP 443) ══════════════════
                                 │
            VIP 10.10.70.200:443 │ lb01 / lb02 — HAProxy 3.2 (certificat ACME « sso »)
              fe_tls_sni ──► fe_publication : /realms/medisphere/*, /resources/* → tout le monde
                                              /admin, /realms/master → MGMT, VPN, runner01 seulement
                                 │ TLS re-chiffré, vérifié (nom idp01) ; santé /health/ready sur 9000
                                 ▼
  idp01 10.10.20.30 ─ Keycloak 26.7 (:8443 HTTPS, :9000 gestion) ─ PostgreSQL 17 (127.0.0.1:5432)
     royaume master : <MOI>-admin (OTP), kc-secours (bris de glace), svc-tofu-keycloak
     royaume medisphere : fédération LDAPS (READ_ONLY) ──────────────┐ uid=svc-keycloak,cn=sysaccounts
                          portée « groupes », clients wb-checks…      │ 636 (LDAPS, racine MédiSphère)
                                                                      ▼
  ipa01 10.10.20.31 ─ FreeIPA 4.13 : 389-ds (LDAP 389/636), KDC (88, 464), Dogtag (CA), httpd (443)
     cn=users,cn=accounts : <MOI> et les 6 personnages ; cn=groups : plateforme-admins, plateforme…
     CA « Certificate Authority, O=PAR1.MEDISPHERE.INTERNAL » ◄── signée par MédiSphère Root CA
                                                                     (cérémonie, ~/pki-racine d'adm01)
  dns01/dns02 (PowerDNS) : ipa01, ipa-ca, _ldap._tcp, _kerberos._udp…, sso → VIP (OpenTofu)
  git01 : plateforme/identite (annuaire/ en Ansible, tofu/ en OpenTofu) ─ runner01 : jobs manuels protégés
```

### Une connexion, de bout en bout

Ce que tu dérouleras à la main en E07, et que chaque service fera à ta place au palier 2 :

1. Le navigateur demande une page de Grafana. Grafana n'a pas de session : il **redirige** le navigateur vers `https://sso…/realms/medisphere/protocol/openid-connect/auth?client_id=grafana&redirect_uri=…&state=…&code_challenge=…`.
2. Keycloak n'a pas de session SSO pour ce navigateur : il affiche son formulaire. La personne saisit `lucas.martin` et son mot de passe.
3. Keycloak ne connaît pas le mot de passe : il fait une **liaison LDAP** (*bind*) sur `ipa01` avec le DN de `lucas.martin` et ce mot de passe. L'annuaire accepte ou refuse (et compte les échecs : verrouillage après 6).
4. Keycloak ouvre une **session SSO** (cookie sur `sso.par1…`), lit les groupes de la personne dans l'annuaire, et redirige le navigateur vers Grafana avec un **code** à usage unique.
5. Grafana échange le code, de serveur à serveur, contre des **jetons** signés (ID token, access token) en prouvant qu'il est le bon client (secret, et verifier PKCE).
6. Grafana vérifie la signature avec les clés publiques de Keycloak (JWKS), lit `preferred_username` et `groups`, et en déduit un **rôle** (`plateforme` → Editor). La personne est connectée.
7. Dix minutes plus tard, elle ouvre Argo CD : redirection vers Keycloak, la **session SSO existe** (elle expire après 30 minutes sans activité, 10 heures au plus), aucun formulaire, code, jetons. C'est l'authentification unique.

L'annuaire dit **qui existe** et à quels groupes il appartient. Keycloak dit **comment on prouve qui on est** et fabrique les jetons. Chaque service décide **ce qu'on a le droit de faire**, à partir des groupes. Trois rôles, trois composants.

---

## Le chemin imposé

1. **VMs** : `plateforme/infra`, état `socle` (OpenTofu, modules `vm-noeud` pour Rocky 10 et `vm-debian`, enregistrements PowerDNS), puis `plateforme/ansible` (rôles `freeipa_serveur` et `keycloak`, pipeline protégé, ADR-0040).
2. **Publication** : rôle `haproxy` de `lb01`/`lb02` (`group_vars/role_lb/`), une passerelle de répartition à la fois.
3. **Flux** : rôle `pare_feu` (`group_vars/role_routeur/pare_feu.yml`), une passerelle à la fois, et `docs/socle/matrice-flux.md`.
4. **Contenu de l'annuaire et du royaume** : projet **`plateforme/identite`** (créé en E03) : `annuaire/` (Ansible), `tofu/` (OpenTofu, à partir d'E08), appliqués par des jobs **manuels protégés** de `main`.
5. **Documentation** : `docs/securite/identite/` de `plateforme/medisphere` (procès-verbal de cérémonie, comptes rendus, puis ADR et runbooks).

Deux exceptions **voulues** au « tout en code », limitées au palier 1 : le royaume, le client d'essai et la fédération sont d'abord créés **à la main** dans la console (E05, E06), pour comprendre ce que le code décrira ; E08 les **importe** dans OpenTofu et supprime le client d'essai par une MR. Ensuite, plus rien à la main dans le royaume `medisphere`.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Identification, authentification, autorisation.** S'identifier, c'est dire qui l'on est (`lucas.martin`). S'authentifier, c'est le prouver (un mot de passe, un code à usage unique, une clé matérielle : les **facteurs**, ce qu'on sait, ce qu'on possède, ce qu'on est). Être autorisé, c'est avoir le droit de faire une action. Un fournisseur d'identité authentifie ; il transmet des **attributs** (groupes) ; la décision d'autoriser reste au service.

**Annuaire (LDAP) et Kerberos.** Un annuaire LDAP range des entrées (personnes, groupes, machines) dans un arbre (`uid=lucas.martin,cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal`) ; un client s'y **lie** (*bind*) avec un DN et un mot de passe, puis cherche. Kerberos authentifie sans faire circuler le mot de passe : un centre de distribution de clés (KDC) délivre des **tickets** à durée limitée, ce qui exige des horloges synchronisées. **FreeIPA** assemble les deux (389-ds, MIT Kerberos), une CA (Dogtag), des règles d'accès aux machines (HBAC) et sudo, et les clients Linux (SSSD).

**Fédération ou synchronisation.** Keycloak peut **fédérer** l'annuaire : il y cherche les personnes, y vérifie les mots de passe (liaison LDAP), importe une copie des attributs et des groupes, mais l'annuaire reste la **source de vérité** (`READ_ONLY`). Synchroniser, c'est recopier des comptes d'un système dans un autre : deux copies, deux vérités possibles.

**OAuth 2.0 et OpenID Connect.** OAuth 2.0 délègue un **accès** : un client obtient un *access token* pour appeler une API au nom d'une personne. OIDC ajoute l'**identité** : un *ID token* (JWT signé) qui dit au client qui s'est connecté. Le flux recommandé est le **code d'autorisation** avec **PKCE** : le navigateur ne voit qu'un code à usage unique, les jetons s'échangent de serveur à serveur. Un JWT se lit (base64url) : en-tête (`alg`, `kid`), revendications (`iss`, `sub`, `aud`, `exp`, `groups`…), signature vérifiée avec les clés publiques publiées (JWKS).

**SAML.** L'ancêtre d'OIDC pour le web : des **assertions** XML signées, transportées par le navigateur. Toujours courant chez les partenaires et les logiciels d'entreprise ; Keycloak sait faire les deux.

**Royaume, client, portée.** Dans Keycloak, un **royaume** (*realm*) isole des utilisateurs, des clients et des réglages ; `master` ne sert qu'à administrer Keycloak, `medisphere` porte les personnes. Un **client** est une application qui demande des jetons (Grafana, `kubectl`…), **confidentiel** (il a un secret, il tourne sur un serveur) ou **public** (CLI, application dans le navigateur : PKCE obligatoire). Une **portée** (*client scope*) regroupe des revendications à mettre dans les jetons (`groupes` → `groups`).

**Bris de glace.** Quand le SSO tombe, il faut entrer quand même : un compte **local** par service, au mot de passe fort rangé au coffre, testé régulièrement, dont l'usage est journalisé et alerté. Ce module en crée un pour chaque service qu'il branche, **avant** de le brancher.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | **FreeIPA 4.13.x** (AppStream de Rocky 10), `freeipa.ansible_freeipa` **1.17.0** ; **Keycloak 26.7.5** (dernière corrective de la 26.7, Maven Central) installé en E04, monté en **26.8.1** en E33 ; **OpenJDK 25** (`openjdk-25-jre-headless`) ; PostgreSQL 17 (Debian 13) ; fournisseur OpenTofu **`keycloak/keycloak` `~> 5.10`** ; OpenTofu 1.13 ; step-ca 0.30 |
| Changements de version | [`annexes/versions-bloc-F.md`](../../../annexes/versions-bloc-F.md), section « Identité et accès » : options `hostname` v2, port de gestion 9000, ruptures de la 26.8, fournisseur OpenTofu renommé, GitLab CE sans groupes OIDC, Harbor et son mode d'authentification, authentification structurée de Kubernetes |
| `ipa01` | VMID **1031**, **10.10.20.31**, Rocky Linux 10, 2 vCPU, 4 Go, 40 Go ; domaine IPA `par1.medisphere.internal`, royaume Kerberos **`PAR1.MEDISPHERE.INTERNAL`**, base **`dc=par1,dc=medisphere,dc=internal`** ; **sans DNS intégré** ; CA subordonnée (`CN=Certificate Authority,O=PAR1.MEDISPHERE.INTERNAL`) ; étiquettes `socle`, `role-annuaire` |
| `idp01` | VMID **1030**, **10.10.20.30**, Debian 13, 2 vCPU, 3 Go, 32 Go ; `/opt/keycloak-<version>`, lien `/opt/keycloak`, `/opt/keycloak/conf/keycloak.conf`, utilisateur `keycloak`, unité `keycloak.service` ; HTTPS **8443**, gestion **9000** ; certificat ACME `/etc/keycloak/tls/` ; étiquettes `socle`, `role-idp` |
| Publication | **`https://sso.par1.medisphere.internal`** (A → VIP **10.10.70.200**), `lb01`/`lb02`, backend `be_sso` ; `/admin` et `/realms/master` réservés à MGMT (10.10.10.0/24), au VPN d'administration (10.255.1.0/24) et à `runner01` (10.10.20.15) |
| Émetteur OIDC | **`https://sso.par1.medisphere.internal/realms/medisphere`** |
| Comptes de l'annuaire | `admin` (bris de glace, Vault `critique`), `<MOI>`, `claire.morel`, `karim.benali`, `sophie.laurent`, `julien.petit`, `nadia.roussel`, `lucas.martin` ; comptes système `uid=svc-keycloak,cn=sysaccounts,cn=etc,…` (fédération) et `uid=wb-checks,cn=sysaccounts,cn=etc,…` (vérifications) |
| Groupes | `plateforme-admins` (`<MOI>`, Karim), `plateforme` (+ Lucas), `mediagenda` (Julien), `medidoc`, `securite` (Sophie), `support` (Nadia), `direction` (Claire) |
| Royaume `master` | `<MOI>-admin` (OTP), **`kc-secours`** (bris de glace, Vault `critique`), client `svc-tofu-keycloak` (OpenTofu, administrateur du seul royaume `medisphere`) |
| Royaume `medisphere` | nom affiché « MédiSphère » ; fédération `ipa01` (LDAPS, `READ_ONLY`, `svc-keycloak`, changements toutes les 15 min) ; portée par défaut **`groupes`** (revendication `groups`, noms courts) ; client **`wb-checks`** (lecture seule) ; client d'essai `essai-oidc` (E05-E07, supprimé en E08) |
| Projet | **`plateforme/identite`** : `annuaire/` (E03), `tofu/` (E08, état S3 `identite/terraform.tfstate` du compartiment `tofu-state`, chiffré) |
| Documentation | `docs/securite/identite/` de `plateforme/medisphere` : `ceremonie-ca.md` (E02), `oidc-a-la-main.md` (E07) ; ADR-0240 et runbooks RB-240 à RB-246 aux paliers suivants |
| Tickets | PLAT-25xx, SEC-25xx, DEV-25xx, CHG-25xx, INC-51xx (xx = exercice) |
| Brouillons | `~/m24/eXX/` sur `adm01` (non versionnés, **sans secret** ; tout secret est dans `~/.config/workbook/` en 600 ou dans un Vault) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton identifiant (celui de GitLab, M01-E05) : aussi ton compte dans l'annuaire, et `<MOI>-admin` dans le royaume `master` |
| `<PRÉNOM>`, `<NOM>` | Ton prénom et ton nom, pour ta fiche dans l'annuaire |
| `<VERSION-TOFU-MODULES>` | La dernière étiquette publiée de `plateforme/tofu-modules` |

### Variables de `lab/lab.env`

Les fonctions de vérification du bloc F existent déjà (`keycloak_api`, `ipa_ldap` dans `lab/lib/check-lib.sh`). Les variables ci-dessous sont **facultatives** : ne les définis que si ton lab s'écarte des valeurs par défaut. `WB_MOI` (bloc A) doit être renseignée.

```
#WB_KEYCLOAK_URL="https://sso.par1.medisphere.internal"
#WB_KEYCLOAK_CHECKS_FILE="$HOME/.config/workbook/keycloak-checks.env"   # client wb-checks (E05)
#WB_IPA_URL="ldaps://ipa01.par1.medisphere.internal"
#WB_IPA_CHECKS_FILE="$HOME/.config/workbook/ipa-checks.env"             # compte système wb-checks (E03)
#WB_M24_IPA=ipa01                                                       # alias SSH de ipa01
#WB_M24_IDP=idp01                                                       # alias SSH de idp01
#WB_RACINE_PKI=/usr/local/share/ca-certificates/medisphere-root-ca.crt
```

---

## Règles du module

1. **Un accès de secours ouvert avant tout changement d'authentification.** Avant de toucher à la façon dont on se connecte à un service : une session déjà ouverte qu'on ne ferme pas (console root, onglet d'administration), et le compte de bris de glace du service **essayé** dans les dix minutes qui précèdent. Ce module te le rappelle à chaque fois par un avertissement.
   > ⚠️ **Attention** : sur Keycloak, ne supprime jamais l'administrateur temporaire (E04) ni ne touche au royaume `master` sans avoir vérifié **dans une seconde fenêtre privée** qu'un autre compte administrateur s'y connecte. Retour arrière si tout est perdu : arrêter Keycloak et recréer un administrateur temporaire par `kc.sh bootstrap-admin user` (E04), procédure à garder sous la main.
2. **La clé de la racine ne quitte pas `~/pki-racine`.** Elle signe la CA de FreeIPA en E02 pendant une cérémonie écrite, et c'est tout. Jamais de copie sur `ipa01`, jamais dans un dépôt.
3. **Aucun secret sur une ligne de commande** (`ps` le montre à tous), ni dans Git en clair, ni dans un compte rendu : mots de passe saisis au clavier, lus dans un fichier en 600 ou passés sur l'entrée standard ; secrets d'automatisation dans l'Ansible Vault `critique` ou en variables protégées de CI. Les jetons OIDC décodés en E07 ne sont recopiés que **tronqués**.
4. **L'annuaire est la seule source des personnes.** Pas de compte de personne créé dans Keycloak ni dans FreeIPA à la main (une exception : l'utilisateur d'essai d'E05, supprimé en E06).
5. **Mémoire.** Profil du bloc F ≈ 111 Go sur 128 Go quand le socle v5 sera complet ; au M24 (sans les VMs d'OpenBao du M25) : socle v4 + `ipa01` (4 Go) + `idp01` (3 Go) + `ceph-par1` + `k8s-par1` ≈ 107 Go. Aucun composant temporaire d'un module précédent ne doit tourner (Jaeger, OpenSearch, `lyo-k3s01`, `flux01`…). Si la mémoire manque pendant le palier 1, qui ne touche pas au cluster, arrête `k8s-par1` (procédure du M14) plutôt que d'éteindre une VM du socle.

---

## Préparer `adm01`

Vérifie d'abord l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 23 25        # mini-projet du M23 : observabilité v1
admin@adm01:~$ lab/bin/check 07 46        # socle v2 : bordure redondante, lb01/lb02
admin@adm01:~$ lab/bin/check 06 46        # socle v1 : PKI (step-ca, racine hors ligne), PowerDNS, NetBox
admin@adm01:~$ ls -ld ~/pki-racine && step certificate inspect ~/pki-racine/medisphere-root-ca.crt --short
admin@adm01:~$ step ca health             # ca01 répond (ACME pour idp01 et sso)
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

La racine hors ligne du M06-E02 doit être là : dossier `~/pki-racine` en 700, clé chiffrée, au moins une archive chiffrée hors d'`adm01` (si tu as gardé le script `ceremonie-pki.sh` du corrigé du M06, `ceremonie-pki.sh verifier` fait ces contrôles). Retrouve aussi la phrase de passe de la racine dans ton gestionnaire de mots de passe : E02 en a besoin.

Il te faut **7 Go libres** sur `pve01` en plus du profil en cours pour les deux nouvelles VMs.

Installe les outils de consultation de l'annuaire (les vérifications en ont besoin) et contrôle ceux qui doivent déjà être là :

```
admin@adm01:~$ sudo apt install ldap-utils
admin@adm01:~$ ldapsearch -VV 2>&1 | head -n 1
admin@adm01:~$ jq --version && openssl version && step version && tofu version | head -n 1
```

Si un rôle de `plateforme/ansible` gère les paquets d'`adm01` (rôle `base` ou un rôle d'outils), ajoute plutôt `ldap-utils` à ce rôle.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 24 <XX>`. Elles sont en lecture seule : DNS, ports, chaînes TLS, découverte OIDC publique, API d'administration du royaume `medisphere` par le client `wb-checks` (E05), annuaire par le compte système `wb-checks` (E03), SSH en consultation sur `ipa01` et `idp01` (dont un `SELECT` dans la base de Keycloak pour les comptes du royaume `master`, que le client des vérifications ne voit pas), GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M24-EXX/` : `infra/` reproduit `plateforme/infra`, `ansible/` reproduit `plateforme/ansible`, `identite/` reproduit `plateforme/identite`, `medisphere/` la documentation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
```

L'ordre de la carte est l'ordre de travail : chaque exercice s'appuie sur le précédent (l'annuaire avant ses personnes, Keycloak avant son royaume, la fédération avant le flux OIDC, la console avant le code). E07 peut se faire avant E06 si tu crées un second utilisateur local d'essai, mais tu perdrais la revendication `groups` dans les jetons : garde l'ordre.

Durée indicative du palier 1 : 21 à 25 heures (somme des durées des exercices : 22 h 30).

## Pour aller plus loin

- FreeIPA, documentation de Red Hat (*Planning Identity Management*, *Installing Identity Management*, chapitres « external CA » et « without integrated DNS ») : <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10> · projet : <https://www.freeipa.org/page/Documentation>
- Collection `freeipa.ansible_freeipa` : <https://github.com/freeipa/ansible-freeipa>
- Keycloak, guides du serveur (installation, configuration de production, `hostname` v2, mandataires, santé) : <https://www.keycloak.org/guides#server> · administration : <https://www.keycloak.org/docs/latest/server_admin/>
- OpenID Connect Core 1.0 : <https://openid.net/specs/openid-connect-core-1_0.html> · OAuth 2.0 (RFC 6749), PKCE (RFC 7636), bonnes pratiques de sécurité (RFC 9700) : <https://www.rfc-editor.org/rfc/rfc9700>
- Fournisseur OpenTofu Keycloak : <https://search.opentofu.org/provider/keycloak/keycloak/latest>

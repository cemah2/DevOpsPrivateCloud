# Module 24 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `identite/` pour `plateforme/identite`, `medisphere/` pour la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M24-E02/` (VM, rôle `freeipa_serveur`, procès-verbal), `M24-E03/` (projet `plateforme/identite`, annuaire), `M24-E04/` (VM, rôle `keycloak`, publication), `M24-E07/` (compte rendu), `M24-E08/` (OpenTofu, pipeline **état E08**, outils).

**Ce qui a été vérifié à la rédaction** :
- **Keycloak 26.7.5** réel (archive `keycloak-quarkus-dist-26.7.5.tar.gz` de Maven Central, empreinte SHA-256 `87d680d1…97c8` comparée à la somme publiée) lancé sous OpenJDK 21 : `kc.sh start --help` (toutes les options utilisées existent), `kc.sh build` puis `show-config` avec le `keycloak.conf` rendu par le rôle (options reconnues, `cache=local`), `kc.sh bootstrap-admin user` contre PostgreSQL 16 (création de `tmp-admin`), puis requêtes SQL des checks d'E04 sur le schéma réel (`user_entity`, `realm`, `credential`, `user_role_mapping`, `keycloak_role`) ;
- le royaume d'E05-E06 créé par l'API d'administration (client confidentiel avec PKCE, compte de service `wb-checks` et ses trois rôles, fédération LDAP `rhds`, mappeur de groupes, portée `groupes` par défaut) : checks d'E05 et d'E06 exécutés contre lui (contrôles corrects, seuls les KO attendus sans annuaire réel) ;
- **le flux d'E07 complet** contre ce Keycloak : découverte, PKCE (`S256`), échange du code, décodage des trois jetons (`typ`, `aud`, `azp`, `nonce`, HS512 pour le jeton de rafraîchissement), userinfo, refus de l'introspection tant que le client n'est pas dans `aud` (`INTROSPECT_TOKEN_ERROR … not in the token audience`), mappeur d'audience puis introspection active, rafraîchissement, déconnexion (204) puis introspection inactive et userinfo 401 ; refus sans `code_challenge` (`Missing parameter: code_challenge_method`), avec une autre redirection (400), avec un mauvais verifier (`PKCE verification failed: Code mismatch`), puis le même code refusé (`Code not valid`) ;
- **E08 de bout en bout** avec OpenTofu 1.13.2 et `keycloak/keycloak` 5.10.0 contre ce Keycloak : client `svc-tofu-keycloak` dans `master` (rôles de `medisphere-realm` sauf `impersonation`), import des 11 objets avec les fichiers de [`fichiers/M24-E08/identite/tofu/`](fichiers/M24-E08/identite/tofu/) (seule mise à jour : le mot de passe en écriture seule), plan vide après l'apply, suppression d'`essai-oidc` par le code (`1 to destroy`) ; l'état ne contient pas le mot de passe de la fédération mais contient les secrets des clients ; `outils/identifiants-keycloak.sh` exécuté ;
- la collection **`freeipa.ansible_freeipa` 1.17.0** (Galaxy) : variables du rôle `ipaserver` (CA externe, copie des fichiers depuis le contrôleur, `ipaclient_no_ntp`, pare-feu), modules `ipauser`, `ipagroup` (synchronisation des membres avec `action: group`), `ipapwpolicy`, `ipasysaccount` ; `ansible-lint` 26 (profil `production`) et `--syntax-check` (ansible-core 2.21.5) sur `annuaire.yml`, le rôle `freeipa_serveur` et le rôle `keycloak`, rendu du gabarit `keycloak.conf.j2` ;
- les contrôles de chaîne d'E02 (sélection de la CA dans le paquet PEM, `pathlen:0`, vérification contre la seule racine) sur une hiérarchie de test racine EC P-384 → CA RSA 3072 ;
- HAProxy 3.2 : `check-ssl`, `port`, `check-sni`, et le statut **expérimental** de `http-request normalize-uri` relus dans `configuration.txt` de la version ;
- tous les scripts (checks, outils) : `shellcheck -x` et `bash -n` ; `.gitlab-ci.yml` analysés comme YAML.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- **FreeIPA 4.13 sur Rocky 10** n'a pas été installé à la rédaction : l'installation en deux passages par le rôle `ipaserver` 1.17 (pas de fichier de variables propre à RHEL 10 dans la collection : valeurs par défaut `ipa-server`), l'acceptation par Dogtag d'une CA **RSA** signée par une racine **EC P-384**, la présentation de la CA de FreeIPA dans la chaîne LDAPS et HTTPS, les droits de lecture du compte système `wb-checks` (personnes, groupes ; la politique de mot de passe peut lui être cachée : le check passe alors en « ignoré ») ;
- les **rôles communs du socle** (`base`, `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `pare_feu_local`, `alloy`…) ont été écrits pour Debian ; `ipa01` est la première VM **Rocky** du groupe `socle` : vérifie qu'ils prennent en charge la famille RedHat (magasin `/etc/pki/ca-trust/source/anchors/`, firewalld au lieu de nftables), sinon limite-les par une condition sur `ansible_os_family` (et note-le) ;
- Keycloak 26.7.5 sous **OpenJDK 25** (testé sous 21) ; l'unité systemd durcie (`ProtectSystem=strict`, `ReadWritePaths`) ; le contrôle de santé HAProxy sur 9000 ; le filtrage par chemin de `fe_publication` (règles écrites d'après la documentation, non chargées dans un HAProxy réel) ;
- l'interface de la console de Keycloak 26.7 (noms des onglets cités) ; les valeurs que la console pose à la création d'un client (si ton premier plan d'E08 montre d'autres écarts, aligne le code) ;
- l'introspection limitée aux destinataires du jeton est un comportement **observé** sur 26.7.5 ; la documentation ne l'annonce pas comme une rupture : si ton introspection répond `active: true` sans mappeur d'audience, note-le.

---

### M24-E01 — Test de positionnement : identité, authentification, autorisation

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 28. En dessous de 14, relis les « Concepts clés » de l'introduction avant E05 ; les questions 4 à 6 et 10 à 12 sont reprises en E07 et E09, 7 à 9 en E02, E03 et E06, 13 et 14 en E23 et E28.

**1. Les trois notions.** *Identification* : Julien saisit `julien.petit` (il dit qui il est). *Authentification* : il prouve que c'est lui (mot de passe vérifié par l'annuaire, puis code OTP s'il est administrateur). *Autorisation* : Argo CD décide qu'il peut synchroniser `mediagenda-dev` mais pas `mediagenda-prod` (règle `g, mediagenda, role:mediagenda`). Keycloak **authentifie** et **transmet des attributs** (groupes) ; l'**autorisation** reste au service, qui seul sait ce que veut dire « synchroniser une Application ». Un IdP qui déciderait des droits de chaque service deviendrait un point de configuration de tous les services à la fois.

**2. Réponse B.** Deux facteurs = deux **catégories** différentes : ce qu'on sait (mot de passe) et ce qu'on possède (le téléphone qui porte le secret TOTP). A : deux choses qu'on sait (un seul facteur, et une question secrète se devine ou se trouve sur les réseaux sociaux). C : deux fois le même facteur. D : l'adresse IP est un **contexte** (utile pour une politique d'accès conditionnel), pas un facteur que la personne prouve.

**3. Compte partagé.** (a) **Imputabilité** : le journal dit « admin a supprimé l'Application », pas qui ; un audit HDS exige des accès nominatifs et traçables. (b) **Départ** : quand l'un des trois part, il faut changer le mot de passe et le redistribuer aux deux autres, ce qu'on oublie (cas d'InfoGér). (c) Le mot de passe **circule** (messagerie, papier, gestionnaires différents) : sa qualité ne protège plus rien. (d) Impossible d'imposer un second facteur personnel, ni de retirer un droit à une seule personne. Le seul compte partagé acceptable est un compte de **bris de glace** : sous scellé, utilisé rarement, chaque usage tracé et justifié.

**4. Cookie de session.** En général un **identifiant aléatoire** qui renvoie à un état côté serveur (ou un contenu signé et éventuellement chiffré). Précautions : `Secure` (jamais en HTTP), `HttpOnly` (illisible par JavaScript, contre le vol par XSS), `SameSite` (`Lax` ou `Strict`, contre la falsification de requête intersite), portée la plus étroite (`Path`, pas de `Domain` large, préfixe `__Host-`), durée limitée et invalidation côté serveur à la déconnexion, **nouvel identifiant après authentification** (contre la fixation de session). Keycloak pose les siens sur `sso.par1…` (`KEYCLOAK_SESSION`, `AUTH_SESSION_ID`, étudiés en M24-E44).

**5. Jeton porteur.** Un jeton dont la **simple possession** donne l'accès : quiconque le présente est cru (comme un billet de spectacle). Un voleur peut appeler l'API au nom de la personne jusqu'à l'expiration. Limiter le dégât : (a) des jetons **courts** (5 minutes chez nous) et des jetons de rafraîchissement révocables, (b) une **audience** étroite (le jeton ne vaut que pour une API) ; en plus, le transport en TLS, et la **liaison** du jeton à une clé du client (DPoP, mTLS) qui en fait autre chose qu'un jeton porteur.

**6. Réponse B.** Un JWS (JWT signé) est seulement encodé en base64url : n'importe qui le lit (c'est ce que tu feras en E07). La signature garantit l'**intégrité** et l'**origine** (émis par le détenteur de la clé privée). A décrit un JWE (chiffré), rare pour les jetons d'accès. C est faux : rien n'empêche le rejeu d'un jeton porteur avant son expiration (sauf `jti` suivi côté serveur, ou DPoP). D est faux : l'API vérifie la signature **hors ligne** avec les clés publiques (JWKS) mises en cache ; l'introspection (appel à l'émetteur) est une option, pas une obligation.

**7. Liaison LDAP.** Une opération *bind* présente un DN et un mot de passe ; le serveur compare avec ce qu'il a stocké (une empreinte) et répond succès ou échec. Pour vérifier le mot de passe de Lucas, l'application (Keycloak) se lie d'abord avec son propre compte de service, **cherche** le DN de `lucas.martin`, puis tente une liaison **avec le DN de Lucas et le mot de passe saisi** : le succès vaut vérification. L'application ne lit jamais le mot de passe stocké (FreeIPA refuse d'ailleurs de le montrer), et l'annuaire applique ses propres règles (compte désactivé, verrouillage après échecs).

**8. Kerberos.** La personne obtient du KDC un ticket (TGT) **chiffré avec une clé dérivée de son mot de passe** : seul celui qui connaît le mot de passe peut l'utiliser (en pratique, la pré-authentification chiffre un horodatage avec cette clé). Ensuite, des tickets de service, présentés aux services, prouvent l'identité sans mot de passe. Les messages portent des **horodatages** pour empêcher le rejeu ; le KDC et les services refusent un écart supérieur à la tolérance (5 minutes par défaut, `clockskew`) : d'où chrony partout, et la panne M24-E38.

**9. Fédération.** Une organisation fait confiance aux authentifications d'une autre, par un protocole (SAML, OIDC) et des clés échangées, sans recopier ses comptes. Entre organisations : un centre de santé partenaire connecte ses médecins à MédiAgenda avec leurs comptes de l'hôpital (SAML) ; à l'intérieur : Grafana, Argo CD et Harbor font confiance à Keycloak, qui fait lui-même confiance à l'annuaire pour les mots de passe.

**10. Réponse B.** Même but (une preuve d'authentification signée, transportée par le navigateur, pour du SSO web), deux formats : SAML 2.0 (2005, XML, assertions signées XML-DSig, liaisons POST et Redirect) ; OIDC (2014, JSON, JWT, au-dessus d'OAuth 2.0, adapté aux API et aux applications mobiles). A est faux ; C est l'inverse (SAML est malcommode sur mobile) ; D est faux : le SSO entre applications est le cœur d'OIDC.

**11. Déléguer un accès.** OAuth 2.0 : la personne autorise l'application de rendez-vous à **lire son agenda** ; l'application reçoit un jeton d'accès pour l'API de l'agenda, avec une portée (`calendar.read`), sans jamais connaître le mot de passe. Ce jeton ne dit pas à l'application **qui** est la personne de façon fiable (il ne lui est pas destiné : son `aud` est l'API). Utiliser OAuth « pour authentifier » a produit des failles (un jeton obtenu pour une autre application rejoué ici). OIDC ajoute l'**ID token**, destiné au client (`aud` = le client), avec `iss`, `sub`, `nonce`, la découverte, userinfo : une identité normalisée.

**12. PKCE.** Le client crée un secret à usage unique (`code_verifier`) et n'envoie que son empreinte (`code_challenge`) dans la requête d'autorisation ; à l'échange du code, il présente le verifier, que le serveur compare. Un **code intercepté** (application malveillante qui écoute le même schéma d'URL sur un téléphone, journal de mandataire, historique) est inutilisable sans le verifier. Prévu d'abord pour les **clients publics** (applications mobiles et natives, qui n'ont pas de secret), il est aujourd'hui recommandé pour tous (RFC 9700, OAuth 2.1) : il lie la requête et l'échange, même pour un client confidentiel.

**13. IdP en panne.** Déjà connectés : ils gardent leur session **chez Grafana** (cookie de Grafana) jusqu'à son expiration ; ceux qui doivent se connecter, ou dont la session expire, sont bloqués ; tout ce qui vérifie les jetons hors ligne continue tant que les jetons vivent (5 minutes), puis échoue au rafraîchissement ; `kubectl` par OIDC aussi. L'astreinte doit entrer par les **comptes de bris de glace** : un compte local par service (`admin.conf` du cluster, `root@pam`, `root` de GitLab, `kc-secours` pour réparer Keycloak lui-même). Trois propriétés : (a) **indépendant** de ce qui est en panne (local, pas de SSO), (b) **protégé et rare** (mot de passe fort au coffre, deux personnes pour l'ouvrir), (c) **éprouvé et surveillé** (testé régulièrement, chaque usage journalisé et alerté). RB-240 (M24-E28).

**14. Départ.** Le SSO coupe d'un coup : désactiver la personne dans l'annuaire empêche toute **nouvelle** connexion à tous les services fédérés (le mot de passe est vérifié à chaque fois), et fermer ses sessions Keycloak force la reconnexion. Il ne coupe pas : les **sessions déjà ouvertes** dans chaque service (jusqu'à leur expiration, sauf déconnexion par canal arrière), les **jetons personnels** (GitLab, Grafana, Argo CD), les **clés SSH** et certificats déjà émis, les `kubeconfig` à certificat, les comptes **locaux** restants (bases, outils hors SSO), les accès physiques et VPN, les secrets qu'il connaissait (à faire tourner). D'où la procédure RB-242 (M24-E23) et la revue d'accès (M24-E30).

---

### M24-E02 — Construire l'annuaire : FreeIPA sur `ipa01` et sa CA subordonnée

**Solution**

*A. La machine et son nom.* [`socle/ipa01.tf`](fichiers/M24-E02/infra/socle/ipa01.tf) : module `vm-noeud` (famille `rocky10`, une carte sur `vinfra` avec la passerelle, `demarrage_auto` et `protection` à vrai), `enregistrement-dns` pour A et PTR, puis les `powerdns_record` du domaine IPA (sept SRV, un TXT, le A `ipa-ca`). Notes attendues : sans DNS intégré, `ipa-server-install` vérifie que le nom complet résout vers une adresse locale **et** que l'inverse revient au même nom ; il affiche à la fin les enregistrements à créer ; l'installation à CA externe se fait en deux passages (`--external-ca` produit `/root/ipa.csr` et s'arrête ; `--external-cert-file` reprend avec le certificat signé et la chaîne).

```
admin@adm01:~$ dig +short SRV _ldap._tcp.par1.medisphere.internal
0 100 389 ipa01.par1.medisphere.internal.
admin@adm01:~$ dig +short TXT _kerberos.par1.medisphere.internal
"PAR1.MEDISPHERE.INTERNAL"
admin@adm01:~$ ssh admin@ipa01 'hostname -f; chronyc tracking | grep Leap'
ipa01.par1.medisphere.internal
Leap status     : Normal
```

*B. Le rôle et la phase 1.* [`roles/freeipa_serveur/`](fichiers/M24-E02/ansible/roles/freeipa_serveur/) ([`defaults`](fichiers/M24-E02/ansible/roles/freeipa_serveur/defaults/main.yml), [`tasks/main.yml`](fichiers/M24-E02/ansible/roles/freeipa_serveur/tasks/main.yml), [`tasks/controles.yml`](fichiers/M24-E02/ansible/roles/freeipa_serveur/tasks/controles.yml)), [`playbooks/annuaire-serveur.yml`](fichiers/M24-E02/ansible/playbooks/annuaire-serveur.yml), [`host_vars/ipa01/freeipa.yml`](fichiers/M24-E02/ansible/inventories/lab/host_vars/ipa01/freeipa.yml), [modèle du Vault](fichiers/M24-E02/ansible/inventories/lab/host_vars/ipa01/vault-critique.yml.exemple), [`requirements.yml.extrait`](fichiers/M24-E02/ansible/collections/requirements.yml.extrait). Le rôle décide de la phase par deux `stat` (`/etc/ipa/default.conf` sur `ipa01`, `pki/ipa01-ipa.crt` sur le contrôleur), refuse de rejouer la phase 1 si `/root/ipa.csr` existe déjà, et passe au rôle amont : `ipaserver_setup_dns: false`, `ipaclient_no_ntp: true`, `ipaserver_external_ca: true` (phase 1) ou `ipaserver_external_cert_files_from_controller: [certificat, racine]` (phase 2).

```
admin@adm01:~/src/ansible$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
admin@adm01:~/src/ansible$ uv run ansible-vault create --encrypt-vault-id critique inventories/lab/host_vars/ipa01/vault-critique.yml
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit ipa01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/annuaire-serveur.yml
…
TASK [freeipa_serveur : Phase 1 — consigne] ***
ok: [ipa01] => msg: CSR de la CA de FreeIPA prête : …/pki/ipa01-ipa.csr. Relis-la …
admin@adm01:~/src/ansible$ step certificate inspect pki/ipa01-ipa.csr --short
admin@adm01:~/src/ansible$ openssl req -in pki/ipa01-ipa.csr -noout -subject -verify
```

À relire : le sujet (`O=PAR1.MEDISPHERE.INTERNAL, CN=Certificate Authority`), une clé RSA (3072 bits par défaut dans FreeIPA récent), une signature de la CSR valide, aucune extension inattendue.

*C. La cérémonie.* Procédure et procès-verbal : [`ceremonie-ca.md`](fichiers/M24-E02/medisphere/docs/securite/identite/ceremonie-ca.md). La signature elle-même, avec le script de cérémonie du M06-E02 (ou ses commandes à la main) :

```
admin@adm01:~/src/ansible/pki$ ceremonie-pki.sh signer ipa01-ipa.csr
# équivalent sans le script (phrase de passe demandée au clavier) :
admin@adm01:~/src/ansible/pki$ step certificate sign --profile intermediate-ca --path-len 0 --not-after 43800h \
>   ipa01-ipa.csr ~/pki-racine/medisphere-root-ca.crt ~/pki-racine/medisphere-root-ca.key > ipa01-ipa.crt
admin@adm01:~/src/ansible/pki$ openssl x509 -in ipa01-ipa.crt -noout -ext basicConstraints,keyUsage -enddate -fingerprint -sha256
X509v3 Basic Constraints: critical
    CA:TRUE, pathlen:0
X509v3 Key Usage: critical
    Certificate Sign, CRL Sign
notAfter=…
sha256 Fingerprint=…
admin@adm01:~/src/ansible/pki$ openssl verify -CAfile medisphere-root-ca.crt ipa01-ipa.crt
ipa01-ipa.crt: OK
```

Puis archivage d'`~/pki-racine`, MR avec la CSR et le certificat, procès-verbal rempli.

*D. Phase 2 et contrôles.*

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/annuaire-serveur.yml
[admin@ipa01 ~]$ sudo ipactl status
Directory Service: RUNNING
krb5kdc Service: RUNNING
kadmin Service: RUNNING
httpd Service: RUNNING
ipa-custodia Service: RUNNING
pki-tomcatd Service: RUNNING
ipa-otpd Service: RUNNING
ipa: INFO: The ipactl command was successful
[admin@ipa01 ~]$ kinit admin && klist | grep krbtgt
… krbtgt/PAR1.MEDISPHERE.INTERNAL@PAR1.MEDISPHERE.INTERNAL
[admin@ipa01 ~]$ ipa ca-show ipa
  Name: ipa
  Description: IPA CA
  Subject DN: CN=Certificate Authority,O=PAR1.MEDISPHERE.INTERNAL
  Issuer DN: CN=MédiSphère Root CA
```

(La liste des services de `ipactl` dépend des options : pas de `named` ni d'`ipa-dnskeysyncd` sans DNS intégré.) `ipa dns-update-system-records --dry-run` liste en plus des enregistrements **URI** (`_kerberos.par1… URI "krb5srv:m:tcp:ipa01…"`) et `_kerberos-adm` selon la version : les clients MIT et SSSD se contentent des SRV ; ajoute-les à `ipa01.tf` si tu veux une liste identique (aucun check ne l'exige).

Réponse à l'étape 9 : 389-ds présente le certificat de `ipa01` **et** la CA de FreeIPA ; la racine n'est pas envoyée (le client l'a déjà). On vérifie la CA de FreeIPA contre la racine seule : elle est subordonnée, donc **rien à distribuer** — tout ce qui fait confiance à « MédiSphère Root CA » (VMs, navigateurs du lab, Keycloak en E06, `ldapsearch` d'`adm01`) fait confiance à l'annuaire.

Flux : [`pare_feu.yml.extrait`](fichiers/M24-E02/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) (VLAN 40 et DMZ vers 88, 464 en TCP et UDP, 389, 443, 636), [`matrice-flux.md.extrait`](fichiers/M24-E02/medisphere/docs/socle/matrice-flux.md.extrait).

**Explications**

- **Pourquoi Rocky.** FreeIPA serveur (Dogtag, 389-ds intégrés, outils `ipa-*`) n'est empaqueté que pour la famille Fedora/RHEL ; Debian n'a que le client. D'où une seconde famille d'OS dans le socle, et l'avertissement sur les rôles communs.
- **Pourquoi pas de DNS intégré.** Deux autorités pour `par1.medisphere.internal` seraient deux vérités (DNSSEC, mises à jour RFC 2136 de Kea et de cert-manager, TSIG du M06). FreeIPA n'a besoin que de **lire** son domaine : les enregistrements sont du code comme le reste. Le prix : à chaque ajout de serveur ou de service FreeIPA, il faut publier les nouveaux enregistrements nous-mêmes.
- **Pourquoi une CA subordonnée.** Une CA auto-signée par FreeIPA aurait été une **seconde racine** à distribuer partout et à protéger comme la première, mais en ligne. Subordonnée, elle hérite de la confiance déjà distribuée ; sa compromission se traite par révocation, pas par un changement de racine. `pathlen:0` l'empêche d'émettre d'autres autorités (FreeIPA sait créer des *sub-CAs* « légères » : on ne s'en sert pas).
- **Pourquoi le NTP n'est pas confié à FreeIPA.** Sans `--no-ntp` (`ipaclient_no_ntp`), l'installateur ouvrirait le service `ntp` dans firewalld et réécrirait la configuration de chrony : `ipa01` deviendrait un serveur de temps concurrent des passerelles (PLAN §4.3 bis). Kerberos a seulement besoin d'horloges justes : le rôle exige `Leap status : Normal` avant d'installer.
- **Les mots de passe.** Le rôle `ipaserver` passe `ipaadmin_password` et `ipadm_password` à ses modules (fichiers d'arguments d'Ansible), jamais à une ligne de commande ; les contrôles envoient le mot de passe à `kinit` sur l'entrée standard, dans un cache temporaire détruit.

**Alternatives**

- *CA auto-signée de FreeIPA* (installation par défaut) : plus simple, une racine de plus à distribuer (`ipa-certupdate` sur les clients, mais aussi navigateurs, Keycloak, conteneurs) ; refusée par Sophie.
- *FreeIPA sans CA* (`--no-pki`, certificats fournis par step-ca) : pas de Dogtag (moins de mémoire, pas de Java), mais plus de certificats émis par l'annuaire (machines, services, cartes à puce) et des certificats HTTP/LDAP à renouveler par nous. Défendable ; le module garde Dogtag pour la gestion des certificats d'hôtes au M24-E19.
- *DNS intégré* avec délégation d'une sous-zone (`ipa.par1…`) : FreeIPA gère sa zone, PowerDNS délègue ; propre, mais un nom de domaine IPA différent de celui des hôtes complique tout (royaume, `dns_lookup_realm`).
- *Samba AD* ou *OpenLDAP* : comparés en M24-E32.

**Pièges classiques**

- Un `hostname -f` faux au moment de l'installation : le nom est gravé dans les certificats, les principaux Kerberos, l'URL de l'interface ; corriger après coup = réinstaller.
- Relancer la phase 1 après avoir signé : nouvelle clé de CA, le certificat signé ne correspond plus, `ipa-server-install` refuse (« certificate does not match key »). Le rôle s'en garde ; à la main, supprimer `/root/ipa.csr` relance tout.
- Donner à la phase 2 le seul certificat de la CA, sans la racine : l'installateur ne peut pas construire la chaîne et échoue.
- Oublier `ipa-ca` dans le DNS : les certificats émis contiennent `http://ipa-ca.par1…/ca/ocsp` ; les vérifications OCSP échouent plus tard, loin de la cause.
- Signer avec le profil `leaf` ou sans `CA:TRUE` : Dogtag refuse de démarrer une CA qui n'en est pas une.
- Se connecter tous les jours en `admin` à l'interface : c'est le bris de glace ; au quotidien, ton compte (E03) et des rôles FreeIPA.

**En production chez MédiSphère**

Deux réplicas FreeIPA au moins (sur deux hôtes physiques), tous deux avec la CA ; sauvegarde `ipa-backup` et PBS (M24-E25) ; supervision (`ipa-healthcheck`, échéances des certificats suivis par certmonger, M24-E26) ; cérémonie à deux personnes avec la racine dans un HSM hors ligne ; renouvellement de la CA de FreeIPA planifié un an avant l'échéance (procès-verbal) ; journal d'audit de 389-ds et du KDC vers Loki `audit`. Le risque d'un annuaire unique est écrit dans l'ADR-0240 (M24-E31).

---

### M24-E03 — Personnes, groupes et politiques de mot de passe en code

**Solution**

Projet `plateforme/identite` : [`README.md`](fichiers/M24-E03/identite/README.md), [`ansible.cfg`](fichiers/M24-E03/identite/ansible.cfg), [`pyproject.toml`](fichiers/M24-E03/identite/pyproject.toml), [`.gitignore`](fichiers/M24-E03/identite/.gitignore), [`collections/requirements.yml`](fichiers/M24-E03/identite/collections/requirements.yml), `outils/vault-pass-client.sh` (copie conforme de `plateforme/ansible`, M04-E30). Dossier `annuaire/` : [`personnes.yml`](fichiers/M24-E03/identite/annuaire/personnes.yml), [`groupes.yml`](fichiers/M24-E03/identite/annuaire/groupes.yml), [`politiques.yml`](fichiers/M24-E03/identite/annuaire/politiques.yml), [`comptes-systeme.yml`](fichiers/M24-E03/identite/annuaire/comptes-systeme.yml), [`inventaire.yml`](fichiers/M24-E03/identite/annuaire/inventaire.yml), [`annuaire.yml`](fichiers/M24-E03/identite/annuaire/annuaire.yml), [modèle du Vault](fichiers/M24-E03/identite/annuaire/vault-critique.yml.exemple). Pipeline (état E03) : [`.gitlab-ci.yml`](fichiers/M24-E03/identite/.gitlab-ci.yml).

```
admin@adm01:~/src/identite$ uv lock && uv sync
admin@adm01:~/src/identite$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
admin@adm01:~/src/identite$ uv run ansible-vault create --encrypt-vault-id critique annuaire/vault-critique.yml
admin@adm01:~/src/identite$ uv run ansible-playbook annuaire/annuaire.yml --check --diff
admin@adm01:~/src/identite$ uv run ansible-lint --offline annuaire/
```

Points du playbook :
- `module_defaults` sur le groupe d'actions `freeipa.ansible_freeipa.modules` porte `ipaadmin_password` (le paramètre est marqué `no_log` par la collection) ;
- `ipagroup` avec `user:` et l'action par défaut (`group`) **synchronise** les membres : la collection calcule les ajouts **et** les retraits (`gen_member_add_del_lists`, mode « sync ») ; avec `action: member`, elle ne ferait qu'ajouter. `membres: []` vide donc un groupe ;
- `ipauser` crée ou met à jour sans jamais supprimer ; une seconde tâche pose l'état `enabled` ou `disabled` selon `etat` ;
- `ipasysaccount` (FreeIPA ≥ 4.13) avec `update_password: on_create` : le mot de passe n'est posé qu'à la création ; la tâche est en `no_log`.

Politique choisie : longueur 12, historique 6, verrouillage après 6 échecs (exigences), **3 classes** de caractères, verrouillage de **10 minutes** (`lockouttime: 600`) avec remise à zéro du compteur après 60 s sans échec, **durée de vie de 365 jours** et durée minimale d'un jour. Justification : les recommandations actuelles (NIST SP 800-63B, ANSSI) déconseillent le changement périodique court, qui pousse aux mots de passe prévisibles ; on impose un changement sur soupçon de compromission. Un verrouillage court limite le déni de service qu'un attaquant ferait en verrouillant exprès les comptes.

Premier mot de passe : `ipa passwd lucas.martin` (en `admin`) pose un mot de passe **expiré d'office** ; `kinit lucas.martin` oblige Lucas à le changer (« Password expired. You must change it now. »). FreeIPA le fait pour que l'administrateur qui a posé le mot de passe ne le connaisse plus : seule la personne connaît le sien.

Fichier des checks, sans afficher ni passer le mot de passe en argument :

```
admin@adm01:~/src/identite$ ( umask 077
>   mdp="$(uv run ansible-vault view annuaire/vault-critique.yml | sed -n 's/^vault_annuaire_wb_checks_mot_de_passe: *"\(.*\)"$/\1/p')"
>   { echo "IPA_BIND_DN=uid=wb-checks,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal"
>     printf 'IPA_BIND_PASSWORD=%q\n' "$mdp"; } > ~/.config/workbook/ipa-checks.env )
admin@adm01:~$ stat -c %a ~/.config/workbook/ipa-checks.env
600
```

(`printf '%q'` échappe les caractères spéciaux pour le `source` du shell : un mot de passe base64 peut contenir `+`, `/`, `=`.)

Essai de la politique : après trois `kinit` ratés, `ipa user-status lucas.martin` montre `Failed logins: 3` et l'heure du dernier échec ; au sixième, le compte est verrouillé 10 minutes (`ipa user-unlock` pour le débloquer avant).

Pipeline : `ansible-lint` sur les MR ; `annuaire:verifier` (`--check --diff`) sur les MR issues de branches protégées et sur `main`, avec `environment: {name: lab/identite, action: prepare}` pour recevoir les variables de cet environnement sans compter comme un déploiement ; `annuaire:appliquer` manuel sur `main`, `resource_group` (jamais deux applications en même temps), second passage qui doit donner `changed=0`. La clé SSH de CI est copiée en 600 dans le dossier du job puis effacée en `after_script`.

**Explications**

- **Personnes jamais supprimées.** Un `uid` supprimé puis recréé recevrait un autre `ipaUniqueID` et un autre UID POSIX : les fichiers, les journaux et Keycloak ne le reconnaîtraient plus, ou pire, un homonyme futur hériterait des traces. FreeIPA propose d'ailleurs la **préservation** (`ipa user-del --preserve`). Le départ se fait par désactivation (RB-242).
- **Groupes synchronisés.** C'est l'inverse : un droit retiré dans le dépôt doit disparaître de l'annuaire, sinon le dépôt n'est plus la vérité. L'auditeur demandera « qui a ajouté Lucas à `plateforme` » : la MR répond.
- **Groupes plats.** FreeIPA sait imbriquer les groupes ; on ne le fait pas : la revendication `groups` reste une liste de noms courts lisible par tous les services, et la revue d'accès (M24-E30) reste simple.
- **Comptes système.** Un service qui se lie à l'annuaire n'est pas une personne : pas de principal Kerberos, pas de connexion aux machines, pas de politique de mot de passe des personnes. `cn=sysaccounts,cn=etc` est fait pour cela, et la commande `sysaccount-*` de FreeIPA 4.13 le gère enfin proprement.
- **Le groupe `admins` de FreeIPA.** Il donne tous les droits **sur l'annuaire**. On n'y met pas `plateforme-admins` : administrer la plateforme n'implique pas de pouvoir créer des comptes sans MR. Les changements passent par le pipeline, qui utilise `admin`.

**Alternatives**

- *Ansible natif `community.general.ipa_*`* : modules plus anciens, moins complets (pas de comptes système) ; la collection officielle du projet FreeIPA est la référence.
- *OpenTofu pour l'annuaire* : il existe un fournisseur communautaire FreeIPA ; moins mûr, et l'annuaire n'a pas d'état à réconcilier finement : Ansible idempotent suffit.
- *Personnes provisionnées par les RH* (SCIM, import depuis le SIRH) : la cible d'une entreprise de 400 personnes ; question M24-E32.
- *Mots de passe initiaux aléatoires* (`random: true` de `ipauser`) envoyés par le pipeline : il faudrait transmettre le mot de passe à la personne, donc le faire sortir du job ; `ipa passwd` par l'administrateur de garde, puis changement immédiat, est plus sûr au lab.

**Pièges classiques**

- `action: member` sur `ipagroup` : les ajouts passent, les retraits jamais ; le dépôt ment sans bruit.
- Supprimer une personne du fichier en croyant la désactiver : rien ne se passe (elle reste active).
- Écrire `ipa-checks.env` avec un `echo "IPA_BIND_PASSWORD=$mdp"` : un mot de passe contenant `$`, un espace ou une apostrophe casse le `source`, ou pire, s'exécute.
- Lancer `ansible-playbook … -e ipaadmin_password=…` : le secret est visible dans `ps` sur `adm01` et dans l'historique du shell.
- Oublier `kdestroy` après `kinit admin` sur `ipa01` : le ticket `admin` reste dans le cache de ta session pendant 24 heures.

**En production chez MédiSphère**

Arrivées et départs déclenchés depuis le SIRH (ticket automatique, MR préparée), double validation des MR qui touchent `plateforme-admins` et `securite` (règle d'approbation par fichier), compte d'automatisation dédié avec un rôle FreeIPA limité au lieu d'`admin`, alerte sur toute modification de l'annuaire faite hors du pipeline (journal d'audit de 389-ds dans Loki : une modification dont l'auteur n'est pas le compte du pipeline), revue trimestrielle des groupes par Sophie (M24-E30).

---

### M24-E04 — Installer Keycloak sur `idp01` et le publier

**Solution**

*A. Lire.* Notes attendues : `start` construit l'image puis démarre (lent, et il refait la construction à chaque changement d'option de construction) ; `start --optimized` démarre une image **déjà construite** par `kc.sh build` (rapide, reproductible). Options de construction (marquées d'un marteau dans la documentation) : `db`, `cache`, `cache-stack`, `health-enabled`, `metrics-enabled`, `features`, `http-relative-path`… `/health/ready` répond 200 quand Keycloak est initialisé et que la base répond. `proxy-headers=xforwarded` fait croire à Keycloak les en-têtes `X-Forwarded-For`, `-Proto`, `-Host`, `-Port` : il faut donc les limiter aux mandataires connus (`proxy-trusted-addresses`) et que le mandataire efface ceux du client. `hostname-backchannel-dynamic=true` servirait un émetteur différent aux appels de serveur à serveur faits par un nom interne : chez nous, tout le monde passe par le nom public, il n'y a donc **qu'un émetteur**.

```
admin@adm01:~/m24/e04$ B=https://repo1.maven.org/maven2/org/keycloak/keycloak-quarkus-dist/26.7.5
admin@adm01:~/m24/e04$ curl -fsSLO $B/keycloak-quarkus-dist-26.7.5.tar.gz
admin@adm01:~/m24/e04$ printf '%s  keycloak-quarkus-dist-26.7.5.tar.gz\n' "$(curl -fsSL $B/keycloak-quarkus-dist-26.7.5.tar.gz.sha256)" | sha256sum -c
keycloak-quarkus-dist-26.7.5.tar.gz: OK
admin@adm01:~/m24/e04$ tar xzf keycloak-quarkus-dist-26.7.5.tar.gz && keycloak-26.7.5/bin/kc.sh start --help | grep -c '^--'
```

(163 options affichées par `start --help` en 26.7.5, 243 avec `--help-all` ; le compte varie d'une version à l'autre. Java est nécessaire pour `kc.sh`, même pour l'aide.)

*B. La machine et le rôle.* [`socle/idp01.tf`](fichiers/M24-E04/infra/socle/idp01.tf), [`publication.tf.extrait`](fichiers/M24-E04/infra/socle/publication.tf.extrait). Rôle [`keycloak`](fichiers/M24-E04/ansible/roles/keycloak/) : [`defaults/main.yml`](fichiers/M24-E04/ansible/roles/keycloak/defaults/main.yml), [`tasks/main.yml`](fichiers/M24-E04/ansible/roles/keycloak/tasks/main.yml), [`postgresql.yml`](fichiers/M24-E04/ansible/roles/keycloak/tasks/postgresql.yml), [`distribution.yml`](fichiers/M24-E04/ansible/roles/keycloak/tasks/distribution.yml), [`service.yml`](fichiers/M24-E04/ansible/roles/keycloak/tasks/service.yml), [`controles.yml`](fichiers/M24-E04/ansible/roles/keycloak/tasks/controles.yml), gabarits [`keycloak.conf.j2`](fichiers/M24-E04/ansible/roles/keycloak/templates/keycloak.conf.j2) et [`keycloak.service.j2`](fichiers/M24-E04/ansible/roles/keycloak/templates/keycloak.service.j2). Le point délicat est la **construction** : elle est faite par Ansible en root, quand le témoin `lib/quarkus/.construit-pour` (empreinte de `keycloak.conf` lors de la dernière construction) diffère de l'empreinte actuelle ; le témoin vit dans le dossier de la version, donc une montée de version reconstruit forcément. Le service n'est jamais démarré par une tâche avant la construction : c'est le gestionnaire « Redémarrer » qui le lance, puis une tâche `state: started` après `flush_handlers`.

Fichiers de l'hôte : [`keycloak.yml`](fichiers/M24-E04/ansible/inventories/lab/host_vars/idp01/keycloak.yml), [`certificats.yml`](fichiers/M24-E04/ansible/inventories/lab/host_vars/idp01/certificats.yml), [`pare_feu_local.yml`](fichiers/M24-E04/ansible/inventories/lab/host_vars/idp01/pare_feu_local.yml), [modèle du Vault](fichiers/M24-E04/ansible/inventories/lab/host_vars/idp01/vault-critique.yml.exemple) ; playbook [`identite.yml`](fichiers/M24-E04/ansible/playbooks/identite.yml).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit idp01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/identite.yml
admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
>   https://idp01.par1.medisphere.internal:9000/health/ready | jq .status
"UP"
```

*C. La publication.* [`haproxy.yml.extrait`](fichiers/M24-E04/ansible/inventories/lab/group_vars/role_lb/haproxy.yml.extrait), [`certificats.yml.extrait`](fichiers/M24-E04/ansible/inventories/lab/group_vars/role_lb/certificats.yml.extrait), [`pare_feu.yml.extrait`](fichiers/M24-E04/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`matrice-flux.md.extrait`](fichiers/M24-E04/medisphere/docs/socle/matrice-flux.md.extrait). `sso…` n'est pas un nom du cluster : il suit `default_backend be_terminaison_locale` de `fe_tls_sni` et arrive dans `fe_publication`. Le filtrage est une **liste blanche** (`/realms/medisphere/`, `/resources/` pour tous ; le reste pour MGMT, le VPN et `runner01`), complétée par un refus des chemins qui contiennent `/..`, `%2e`, `%2f` ou `%5c`. Le contrôle de santé vise 9000 avec `port 9000` **et** `check-ssl` : avec un port explicite, le contrôle n'hérite pas du TLS du serveur.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb02 --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb01
admin@adm01:~$ curl -s https://sso.par1.medisphere.internal/realms/master/.well-known/openid-configuration | jq -r .issuer
https://sso.par1.medisphere.internal/realms/master
admin@mon01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://sso.par1.medisphere.internal/admin/
403
admin@mon01:~$ curl -s -o /dev/null -w '%{http_code}\n' 'https://sso.par1.medisphere.internal/realms/medisphere/%2e%2e/master/'
400
```

*D. Les administrateurs.* `kc.sh bootstrap-admin user` démarre une instance de Keycloak (mêmes base et caches) le temps de créer le compte : la documentation exige que **tous** les nœuds soient arrêtés. `--optimized` évite qu'il reconstruise l'image (une construction implicite écraserait celle que le service utilise). Sans `--password:env`, le mot de passe est demandé au terminal : il ne touche ni le disque, ni l'environnement. Par `KC_BOOTSTRAP_ADMIN_PASSWORD` dans l'unité, il resterait lisible par root dans `/etc/systemd/system/keycloak.service` (ou un fichier d'environnement), dans `systemctl show`, et dans `/proc/<pid>/environ` tant que Keycloak tourne — et il ne sert qu'au tout premier démarrage (quand `master` n'existe pas encore), ce qui le rend inutile ensuite et dangereux à oublier.

Deux comptes : `<MOI>-admin` est **nominatif** (traçabilité, OTP) ; `kc-secours` est le **bris de glace** : si ton téléphone d'OTP est perdu ou si tu es absent, quelqu'un doit pouvoir réparer Keycloak. Pas d'OTP pour lui : un second facteur attaché à un téléphone personnel le rendrait inutilisable le jour où on en a besoin ; sa protection est ailleurs (mot de passe long au coffre, usage rare, journalisé et alerté au M24-E26). En production, une clé matérielle FIDO2 rangée au coffre avec lui est une bonne option.

**Explications**

- **Distribution officielle plutôt que conteneur.** Le PLAN fixe la distribution « zip » sur une VM : Keycloak authentifie le cluster, il ne doit pas en dépendre ; et l'image officielle embarque un JDK 21 alors que la 26.8 recommande Java 25.
- **Archive de Maven Central.** C'est le dépôt de publication du projet ; il publie les sommes (`.sha256`, `.sha512`) et une signature GPG (`.asc`) à côté de chaque archive. Le rôle épingle la version **et** l'empreinte : changer l'une sans l'autre échoue.
- **`hostname` v2.** Une URL complète (`https://sso.par1.medisphere.internal`) fixe le schéma, le nom et le port publiés : Keycloak écrit ce nom dans `iss`, dans les URL de la découverte et dans les redirections, quel que soit le chemin par lequel la requête est arrivée. `hostname-strict` (vrai par défaut) refuse de déduire le nom de la requête.
- **Mandataires.** Keycloak voit toutes les connexions venir de `lb01`/`lb02` ; `X-Forwarded-For` lui donne l'adresse du client (journaux, détection de force brute au M24-E27). HAProxy efface ce que le client a envoyé avant d'ajouter le vrai : sans cela, un attaquant choisirait l'adresse que Keycloak enregistre.
- **TLS de bout en bout.** HAProxy termine le TLS public (certificat `sso`) et **re-chiffre** vers `idp01:8443` en vérifiant le certificat de `idp01` contre la racine : un attaquant sur le VLAN 20 ne lit ni les mots de passe ni les jetons.
- **Durcissement systemd.** `ProtectSystem=strict` rend tout le système de fichiers en lecture seule pour le service, sauf `ReadWritePaths` (`data/` de la version) ; aucune capacité, pas de nouveaux privilèges : un Keycloak compromis ne réécrit pas ses propres binaires.

**Alternatives**

- *Image de conteneur `quay.io/keycloak/keycloak` sous Podman* sur `idp01` : mêmes réglages en variables `KC_*`, construction dans l'image (`Containerfile` qui lance `kc.sh build`) ; mise à jour par changement d'image. Valable ; le PLAN retient la distribution pour rester sur Java 25 et un schéma d'exploitation identique aux autres services VM.
- *Opérateur Keycloak dans `k8s-par1`* : CRD `Keycloak` et `KeycloakRealmImport`, très pratique pour un IdP d'applications ; mauvais pour l'IdP de la plateforme (dépendance circulaire avec `kubectl` par OIDC).
- *Exposition directe d'`idp01`* sans les répartiteurs : un seul point de passage en moins, mais pas de filtrage de `/admin`, pas de VIP, et un second certificat public.
- *`hostname-admin`* : console servie sous un autre nom (`sso-admin.par1…`), joignable seulement en MGMT ; plus propre que le filtrage par chemin, un nom et un certificat de plus (piste du durcissement, M24-E27).

**Pièges classiques**

- `start` au lieu de `start --optimized` dans l'unité : chaque démarrage reconstruit, en écrivant dans `lib/` (refusé par `ProtectSystem=strict`).
- Une option de construction changée sans reconstruire : Keycloak démarre avec l'ancienne valeur, ou refuse (« build time options differ »).
- `proxy-headers` sans `proxy-trusted-addresses`, ou un HAProxy qui laisse passer le `X-Forwarded-For` du client : journaux et verrouillages par adresse falsifiables.
- Un filtrage de `/admin` par **préfixe interdit** : `//admin`, `/Admin` ou un caractère encodé passent l'ACL ; la liste blanche ne laisse passer que ce qu'on a nommé.
- Oublier `runner01` dans la liste d'administration : le pipeline d'OpenTofu (E08) reçoit un 403 sur `/realms/master/protocol/openid-connect/token`.
- Supprimer `temp-admin` avant d'avoir **essayé** les deux autres comptes : si l'OTP de `<MOI>-admin` est mal enregistré et que le mot de passe de `kc-secours` a une faute, plus personne n'administre Keycloak (retour arrière : arrêt, `bootstrap-admin`).
- Un mot de passe de base avec `#` ou `\` dans `keycloak.conf` (fichier de propriétés) : coupé ou interprété ; d'où le mot de passe hexadécimal.

**En production chez MédiSphère**

Deux nœuds Keycloak au moins derrière les répartiteurs (essai et décision au M24-E24), base PostgreSQL répliquée et sauvegardée (M24-E25), supervision de la santé, des métriques et des événements de connexion et d'administration (M24-E26), console d'administration sous un nom séparé, MFA par clé matérielle pour les administrateurs, revue mensuelle des administrateurs de `master`, alerte sur toute connexion de `kc-secours` (RB-240), montées de version suivies de près (RB-245) : la 26.8.1 corrige des failles de sécurité que la 26.7.5 n'a pas (`annexes/versions-bloc-F.md`), elle est installée au M24-E33.

---

### M24-E05 — Premiers pas dans Keycloak : royaumes, clients, utilisateurs

**Solution**

1. Royaume `master` : clients `account`, `account-console`, `admin-cli` (client public utilisé par `kcadm.sh` et les scripts avec un mot de passe), `broker`, `master-realm` (rôles d'administration du royaume `master` lui-même), `security-admin-console` (la console). Dès qu'un royaume `medisphere` existe, `master` reçoit un client **`medisphere-realm`** qui porte les rôles d'administration **de ce royaume** (`manage-users`, `view-clients`…) : c'est lui qu'on utilise en E08 pour donner à OpenTofu des droits limités à `medisphere`.
2. *Realm settings* → *Tokens* : jeton d'accès 5 minutes ; *Sessions* : session SSO inactive 30 minutes, maximale 10 heures (valeurs par défaut, celles que veut la fiche ; le durcissement du M24-E27 les revoit). *Client scopes* : `acr`, `basic`, `email`, `profile`, `roles`, `web-origins`, `role_list`, `saml_organization` (et pour SAML `AuthnContextClassRef`) en portées par défaut ; `address`, `phone`, `offline_access`, `microprofile-jwt`, `organization` en optionnelles. Inscription libre : désactivée par défaut (vérifie-le).
3. `essai-oidc` : *Client authentication* ON (confidentiel) ; *Authentication flow* : *Standard flow* seulement (décocher *Direct access grants*, *Implicit* déjà décoché) ; *Valid redirect URIs* : `http://localhost:8765/rappel` ; *Advanced* → *Proof Key for Code Exchange Code Challenge Method* : `S256`.
4. La console de compte affiche le profil et les sessions de l'utilisateur d'essai ; dans l'administration, *Sessions* montre sa session (adresse, début, dernier accès, clients) ; « déconnecter » la ferme côté Keycloak : au prochain clic dans la console de compte, retour au formulaire.
5. `wb-checks` : *Client authentication* ON, *Service accounts roles* seul flux coché ; onglet *Service accounts roles* → *Assign role* → filtre « clients » → `realm-management` `view-realm`, `view-users`, `view-clients`. Le secret, onglet *Credentials* :
   ```
   admin@adm01:~$ ( umask 077; read -rsp 'Secret de wb-checks : ' s; echo
   >   printf 'KEYCLOAK_CLIENT_ID=wb-checks\nKEYCLOAK_CLIENT_SECRET=%q\n' "$s" > ~/.config/workbook/keycloak-checks.env )
   admin@adm01:~$ lab/bin/check 24 05
   ```
   Avec `manage-users` et un secret qui fuit, n'importe qui pourrait réinitialiser un mot de passe local, retirer un second facteur ou ajouter quelqu'un à un groupe du royaume : un compte de **vérification** n'a besoin que de lire.
6. Identifiants : visibles dans l'URL de la console (`…/#/medisphere/clients/<ID>/settings`, `…/user-federation/ldap/<ID>`, `…/client-scopes/<ID>/settings`).

**Explications**

Un royaume est une frontière complète : utilisateurs, clients, clés de signature, émetteur (`…/realms/<nom>`), sessions. On n'utilise jamais `master` pour les personnes : un compte de `master` avec un rôle de trop administre **tous** les royaumes. Un client confidentiel prouve son identité au point de terminaison des jetons (secret, ou JWT signé, ou certificat) ; un client public ne le peut pas, PKCE le protège. Le client à compte de service n'a pas de navigateur : il obtient un jeton pour **lui-même** (`client_credentials`), avec les rôles de son compte de service.

**Alternatives**

- *`kcadm.sh`* (dans `bin/` de la distribution) ou l'API d'administration avec `curl` : même résultat, scriptable ; la console est imposée ici pour apprendre où sont les choses.
- *Authentification de `wb-checks` par JWT signé* (*Signed JWT*) plutôt que par secret : pas de secret partagé à faire tourner ; un peu plus complexe pour un script de vérification.

**Pièges classiques**

- Une redirection `http://localhost:8765/*` « pour essayer » : le joker reste, et un jour quelqu'un en abuse (redirection ouverte, M24-E22, M24-E45).
- Créer l'utilisateur d'essai avec le nom d'un personnage : il deviendrait un doublon local de la personne de l'annuaire en E06.
- Donner `realm-admin` à `wb-checks` « parce que c'est plus simple » : la vérification devient un compte d'administration.
- Coller le secret dans un `echo … >>` : il reste dans l'historique du shell.

**En production chez MédiSphère**

Création manuelle interdite hors exercices ; tout client par MR (E08 et suivants) ; comptes de service avec authentification par JWT signé ou mTLS et rotation des secrets (M24-E29) ; revue des rôles des comptes de service dans la revue d'accès (M24-E30).

---

### M24-E06 — Fédérer l'annuaire FreeIPA dans Keycloak

**Solution**

1. La chaîne de `ipa01` se vérifie avec la seule racine (E02). Keycloak lit son magasin de confiance sortant dans `truststore-paths` (la racine MédiSphère, posée par le rôle en E04) : rien à ajouter, c'est le bénéfice direct de la CA subordonnée.
2. *User federation* → *Add Ldap providers* :

   | Réglage | Valeur |
   |---|---|
   | *UI display name* | `ipa01` |
   | *Vendor* | Red Hat Directory Server |
   | *Connection URL* | `ldaps://ipa01.par1.medisphere.internal` ; *Use Truststore SPI* : *Always* ; *Connection pooling* ON ; *StartTLS* OFF |
   | *Bind type* / *Bind DN* | `simple` / `uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal` |
   | *Edit mode* | `READ_ONLY` |
   | *Users DN* | `cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal` ; *Search scope* : *One Level* |
   | *Username / RDN / UUID LDAP attribute* | `uid` / `uid` / `ipaUniqueID` |
   | *User object classes* | `inetOrgPerson, organizationalPerson` |
   | *Custom user LDAP filter* | `(!(uid=admin))` |
   | *Synchronization* | *Import users* ON, *Sync registrations* OFF ; *Periodic full sync* 86400 s ; *Periodic changed users sync* 900 s |
   | *Trust email* | ON (l'adresse vient de l'annuaire, géré par nous) |

   *Test connection* (ouverture LDAPS, chaîne vérifiée) puis *Test authentication* (liaison de `svc-keycloak`).
3. *Action* → *Sync all users* : 7 utilisateurs importés (les sept personnes ; `admin` exclu par le filtre). Ouvre `lucas.martin` : bandeau « fédéré », lien vers `ipa01`, champs en lecture seule ; une modification de l'adresse est refusée (mode `READ_ONLY`).
4. Onglet *Mappers* → *Add mapper* → `group-ldap-mapper` nommé `groupes-ipa` : *LDAP Groups DN* `cn=groups,cn=accounts,dc=par1,dc=medisphere,dc=internal`, *Group name LDAP attribute* `cn`, *Group object classes* `groupOfNames`, *Preserve group inheritance* OFF, *Membership LDAP attribute* `member`, *Membership attribute type* `DN`, *Membership user LDAP attribute* `uid`, *LDAP filter* `(|(cn=plateforme-admins)(cn=plateforme)(cn=mediagenda)(cn=medidoc)(cn=securite)(cn=support)(cn=direction))`, *Mode* `READ_ONLY`, *User groups retrieve strategy* « Load groups by member attribute ». Puis *Sync LDAP groups to Keycloak*.
5. *Client scopes* → *Create* : `groupes`, protocole OpenID Connect, *Include in token scope* ON ; onglet *Mappers* → *By configuration* → *Group Membership* : nom `groups`, *Token Claim Name* `groups`, *Full group path* OFF, *Add to ID token*, *access token*, *userinfo*, *token introspection* ON. Puis *Client scopes* → type *Default* pour `groupes` (portée par défaut du royaume). `essai-oidc` a été créé avant : les portées par défaut ne s'appliquent qu'aux clients créés **après** ; on l'ajoute à la main (*Clients* → `essai-oidc` → *Client scopes* → *Add client scope* → `groupes`, *Default*).
6. Connexion de `lucas.martin` à la console de compte : réussie. Après `ipa user-disable lucas.martin` : « Invalid username or password » **immédiatement** — Keycloak vérifie le mot de passe par une liaison LDAP à chaque connexion, et 389-ds refuse la liaison d'un compte verrouillé (`nsAccountLock`). Une session SSO **déjà ouverte** de Lucas, elle, resterait valable jusqu'à son expiration (d'où la fermeture des sessions dans RB-242). Le job d'application de l'annuaire réactive Lucas (`etat` absent = actif) : la vérité est le dépôt.
7. *Users* → utilisateur d'essai → *Delete*.

**Explications**

- **Import et fédération.** Avec *Import users*, Keycloak garde une **copie** des attributs (et un lien `federationLink`) pour ses propres besoins (identifiant interne, sessions, second facteur stocké chez lui) ; l'annuaire reste la référence : à chaque connexion, Keycloak relit la personne et vérifie le mot de passe par une liaison. La synchronisation périodique met à jour les copies (nouveaux arrivants, changements de nom, désactivations) pour ceux qui ne se connectent pas, et pour les listes de la console.
- **`ipaUniqueID`.** Identifiant immuable de l'entrée : un renommage de `uid` garde la même personne dans Keycloak (même identifiant, mêmes sessions, même OTP), au lieu d'en créer une seconde.
- **Revendication `groups` en noms courts.** Tous les services du palier 2 comparent des chaînes : `plateforme-admins` dans la politique d'Argo CD, dans `role_attribute_path` de Grafana, dans le RBAC de Kubernetes. Le chemin complet (`/plateforme-admins`) ne correspondrait à rien. Depuis la 26.8, un nom nu dans une politique désigne le groupe de premier niveau (`annexes/versions-bloc-F.md`) : nos groupes sont tous de premier niveau.
- **Exclure `admin`.** Le compte `admin` de FreeIPA est le bris de glace de l'**annuaire** : il ne doit pas pouvoir se connecter aux services par SSO (s'il se faisait voler, le voleur n'aurait pas en plus le SSO).

**Alternatives**

- *Mode `UNSYNCED`* : Keycloak garde les modifications pour lui, sans les écrire dans l'annuaire : deux vérités. *`WRITABLE`* : Keycloak écrit dans l'annuaire (mot de passe changé depuis la console de compte) ; pratique, mais le compte de service devient un compte d'écriture sur l'annuaire (M24-E22 en fait un défaut).
- *Sans import* (*Import users* OFF) : Keycloak ne garde rien ; chaque recherche interroge l'annuaire ; pas de second facteur stocké par utilisateur fédéré dans certaines configurations ; plus de charge sur `ipa01`.
- *Groupes par l'attribut `memberOf`* des personnes (stratégie « Get groups from user memberOf attribute ») : une requête de moins, mais dépend de la réplication de `memberOf` (fiable dans 389-ds).
- *Kerberos* (SPNEGO) : connexion sans mot de passe depuis un poste inscrit au domaine ; les postes de MédiSphère ne le sont pas.

**Pièges classiques**

- `ldap://` (389) au lieu de `ldaps://` : les mots de passe des personnes passent en clair sur le VLAN 20 à chaque connexion.
- *Use Truststore SPI* à *Never* et un certificat « qui marche » : Keycloak utiliserait le magasin du JDK, qui ne connaît pas la racine MédiSphère, ou pire, quelqu'un désactiverait la vérification.
- *UUID LDAP attribute* laissé à `nsuniqueid` ou `entryUUID` sans savoir lequel l'annuaire renvoie : un identifiant vide ou instable fait dupliquer les personnes.
- Oublier le filtre de groupes : `admins`, `ipausers`, `editors`, `trust admins` arrivent dans Keycloak, et `ipausers` (tout le monde) dans chaque jeton.
- Désactiver une personne dans **Keycloak** (bouton *Enabled*) : l'annuaire ne le sait pas ; la prochaine synchronisation ou le prochain administrateur la réactivera sans le savoir.

**En production chez MédiSphère**

Fédération vers **deux** serveurs d'annuaire (URL multiples, `ldaps://ipa01 ldaps://ipa02`), délais de connexion et de lecture courts (une panne de l'annuaire ne doit pas bloquer Keycloak des minutes), supervision de la synchronisation (alerte `FederationLdapEnEchec`, M24-E26), compte `svc-keycloak` dont le mot de passe tourne (RB-244), revue de l'écart entre l'annuaire et Keycloak dans la revue d'accès (M24-E30).

---

### M24-E07 — OIDC à la main : code d'autorisation, PKCE, jetons et découverte

**Solution**

Compte rendu modèle : [`oidc-a-la-main.md`](fichiers/M24-E07/medisphere/docs/securite/identite/oidc-a-la-main.md). Le déroulé, en un seul shell (rien n'est écrit sur disque sauf le secret, en 600, et les jetons, effacés à la fin) :

```
admin@adm01:~$ install -d -m 700 ~/m24/e07 && cd ~/m24/e07
admin@adm01:~/m24/e07$ ( umask 077; read -rsp 'Secret de essai-oidc : ' s; echo; printf '%s' "$s" > essai-oidc.secret )
admin@adm01:~/m24/e07$ E=https://sso.par1.medisphere.internal/realms/medisphere
admin@adm01:~/m24/e07$ VERIFIER=$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')
admin@adm01:~/m24/e07$ CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
admin@adm01:~/m24/e07$ STATE=$(openssl rand -hex 16); NONCE=$(openssl rand -hex 16)
admin@adm01:~/m24/e07$ echo "$E/protocol/openid-connect/auth?client_id=essai-oidc&response_type=code&scope=openid&redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Frappel&state=$STATE&nonce=$NONCE&code_challenge=$CHALLENGE&code_challenge_method=S256"
```

L'URL ouverte dans une fenêtre privée, connexion de `lucas.martin`, la barre d'adresse montre :

```
http://localhost:8765/rappel?state=<STATE>&session_state=…&iss=https%3A%2F%2Fsso.par1.medisphere.internal%2Frealms%2Fmedisphere&code=…
```

`state` est le nôtre (sinon : abandon, c'est une réponse qu'on n'a pas demandée) ; `iss` désigne l'émetteur qui répond (RFC 9207). Échange immédiat (le code vit une minute) :

```
admin@adm01:~/m24/e07$ read -r CODE           # collé depuis la barre d'adresse
admin@adm01:~/m24/e07$ curl -s -K <(printf 'user = "essai-oidc:%s"\n' "$(<essai-oidc.secret)") \
>   -d grant_type=authorization_code -d "code=$CODE" -d redirect_uri=http://localhost:8765/rappel \
>   -d "code_verifier=$VERIFIER" $E/protocol/openid-connect/token > jetons.json && chmod 600 jetons.json
admin@adm01:~/m24/e07$ jq 'keys' jetons.json
[ "access_token", "expires_in", "id_token", "not-before-policy", "refresh_expires_in", "refresh_token", "scope", "session_state", "token_type" ]
admin@adm01:~/m24/e07$ charge() { jq -R 'split(".") | .[1] | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson'; }
admin@adm01:~/m24/e07$ entete() { jq -R 'split(".") | .[0] | gsub("-";"+") | gsub("_";"/") | @base64d | fromjson'; }
admin@adm01:~/m24/e07$ jq -r .id_token jetons.json | charge | jq '{typ, iss, aud, azp, nonce, sid, exp, iat, preferred_username, groups}'
admin@adm01:~/m24/e07$ jq -r .access_token jetons.json | charge | jq '{typ, aud, azp, scope, exp, iat, groups}'
admin@adm01:~/m24/e07$ jq -r .refresh_token jetons.json | entete
```

`-K <(…)` : la commande `curl` lit l'option `user` dans un fichier anonyme ; avec `-u essai-oidc:secret`, le secret serait visible par tout utilisateur de la machine dans `ps` pendant l'appel. `jetons.json` contient des jetons valables (5 minutes pour l'accès, 30 minutes pour le rafraîchissement) : dans ce dossier en 700, effacé à la fin.

Ce qu'on observe (Keycloak 26.7.5) :

| | ID token | Jeton d'accès | Jeton de rafraîchissement |
|---|---|---|---|
| En-tête | `RS256`, `kid` du JWKS | `RS256`, même `kid` | **`HS512`** (clé secrète du royaume) |
| `typ` | `ID` | `Bearer` | `Refresh` |
| `aud` | `essai-oidc` | `account` | l'émetteur |
| `azp` | `essai-oidc` | `essai-oidc` | — |
| `nonce` | le nôtre | — | — |
| `exp - iat` | 300 | 300 | 1800 |

L'ID token est pour le **client** (il dit qui s'est connecté) ; le jeton d'accès est pour une **API** : ici `account` (l'API de la console de compte), parce que l'utilisateur a des rôles de ce client et que la portée `roles` met ses clients dans `aud` ; le jeton de rafraîchissement n'est lu que par Keycloak (signature symétrique, illisible pour vérification par quiconque d'autre).

Userinfo, puis introspection :

```
admin@adm01:~/m24/e07$ AT=$(jq -r .access_token jetons.json)
admin@adm01:~/m24/e07$ curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$AT") $E/protocol/openid-connect/userinfo | jq .
admin@adm01:~/m24/e07$ printf '%s' "$AT" | curl -s -K <(printf 'user = "essai-oidc:%s"\n' "$(<essai-oidc.secret)") \
>   --data-urlencode "token@-" $E/protocol/openid-connect/token/introspect | jq '{active, client_id, username}'
{ "active": false, "client_id": null, "username": null }
admin@idp01:~$ sudo journalctl -u keycloak --since -5min | grep INTROSPECT
… "type":"INTROSPECT_TOKEN_ERROR" … "error":"invalid_token","reason":"Client 'essai-oidc' is not in the token audience" …
```

Correction : *Clients* → `essai-oidc` → *Client scopes* → `essai-oidc-dedicated` → *Add mapper* → *By configuration* → *Audience*, nom `audience-essai-oidc`, *Included Client Audience* `essai-oidc`, *Add to access token* ON, *Add to ID token* OFF. Nouveau flux : `aud` du jeton d'accès vaut `["essai-oidc", "account"]` et l'introspection répond `active: true`, `client_id: essai-oidc`, `username: lucas.martin`.

Rafraîchissement et déconnexion :

```
admin@adm01:~/m24/e07$ RT=$(jq -r .refresh_token jetons.json)
admin@adm01:~/m24/e07$ printf '%s' "$RT" | curl -s -K <(printf 'user = "essai-oidc:%s"\n' "$(<essai-oidc.secret)") \
>   -d grant_type=refresh_token --data-urlencode "refresh_token@-" $E/protocol/openid-connect/token | jq 'keys'
admin@adm01:~/m24/e07$ printf '%s' "$RT" | curl -s -o /dev/null -w '%{http_code}\n' -K <(printf 'user = "essai-oidc:%s"\n' "$(<essai-oidc.secret)") \
>   --data-urlencode "refresh_token@-" $E/protocol/openid-connect/logout
204
```

Après rafraîchissement : nouveaux jetons d'accès et d'identité (nouveaux `iat`, `exp`, `jti`), même `sid` (même session SSO), même `sub`. Après déconnexion : l'introspection de l'**ancien** jeton d'accès répond `active: false` et `userinfo` répond **401** (`user_session_not_found` dans le journal) : la session n'existe plus. Un service qui vérifie la signature lui-même (kube-apiserver, Argo CD, Grafana entre deux rafraîchissements) accepterait encore ce jeton jusqu'à son `exp`, soit au plus 5 minutes : c'est **la** raison des jetons d'accès courts.

Refus :

| Essai | Réponse |
|---|---|
| sans `code_challenge` | redirection `…/rappel?error=invalid_request&error_description=Missing+parameter%3A+code_challenge_method&state=…` |
| `redirect_uri=…/autre` | page d'erreur de Keycloak (HTTP 400, « Invalid parameter: redirect_uri »), **aucune** redirection |
| mauvais `code_verifier` | `{"error":"invalid_grant","error_description":"PKCE verification failed: Code mismatch"}` |
| même code, bon verifier | `{"error":"invalid_grant","error_description":"Code not valid"}` : un échange raté consomme le code |

Sans PKCE, un code relevé dans un journal de mandataire (l'URL de retour complète) aurait pu être échangé par quiconque connaît aussi le secret du client — pour un client public (CLI, application dans le navigateur), par **quiconque**. Avec PKCE, il faut aussi le verifier, qui n'a jamais quitté le client.

Fin : `rm -f essai-oidc.secret jetons.json` ; `unset VERIFIER CODE AT RT`.

**Explications**

- **La découverte** évite de configurer chaque service avec six URL : on lui donne l'émetteur, il lit le reste. Elle annonce aussi ce que le royaume **sait** faire (`grant_types_supported` liste `password` et `implicit`) ; ce que chaque client **a le droit** de faire se règle sur le client.
- **Plusieurs clés dans le JWKS** : une de signature RS256 active, une de chiffrement (`RSA-OAEP`), et, pendant une rotation, l'ancienne et la nouvelle clé de signature (M24-E29). Le `kid` de l'en-tête dit laquelle a signé.
- **Pourquoi l'audience compte pour l'introspection.** Un client qui peut introspecter n'importe quel jeton du royaume apprend des choses sur des sessions qui ne le regardent pas ; Keycloak ne répond qu'aux destinataires. C'est la même logique que la vérification de `aud` par une API : un jeton émis pour `account` ne doit pas être accepté par `essai-oidc`. On le reverra avec kube-apiserver (audience `kubernetes`, M24-E16).
- **Le code d'une minute, à usage unique** : il traverse le navigateur, donc des endroits où il peut fuir ; sa valeur doit être nulle très vite.

**Alternatives**

- *`oauth2c`*, *`step oauth`* ou un petit serveur local sur `localhost:8765` qui reçoit le code : plus confortable, mais ils cachent ce que l'exercice veut faire voir.
- *Flux d'appareil* (*device authorization grant*, RFC 8628) : pour un terminal sans navigateur ; Keycloak le propose (case à cocher du client) ; kubelogin sait l'utiliser.

**Pièges classiques**

- Défi calculé sur la représentation **hexadécimale** du SHA-256 (`sha256sum`) au lieu des octets : `Code mismatch` à chaque fois.
- `--data-urlencode "token@-" <<<"$AT"` : la chaîne envoyée se termine par un retour à la ligne, le jeton est invalide et l'introspection répond `active: false` pour une **autre** raison que l'audience. `printf '%s'` n'en ajoute pas.
- Décoder un JWT avec `base64 -d` sans transformer `-` et `_` ni rembourrer : charge tronquée ou erreur.
- Prendre l'introspection `active: false` pour une preuve que le jeton est expiré, sans lire le journal de Keycloak.
- Coller un jeton complet dans le compte rendu ou dans un ticket : c'est un **mot de passe** de cinq minutes (et le jeton de rafraîchissement, de trente).

**En production chez MédiSphère**

Les services utilisent des bibliothèques éprouvées, jamais un flux codé à la main ; chacun vérifie `iss`, `aud`, `exp` et la signature, garde les jetons côté serveur (pas dans le stockage local du navigateur) ; les jetons d'accès restent courts, les jetons de rafraîchissement tournent à chaque usage (M24-E27) ; les journaux des mandataires n'enregistrent pas les paramètres des URL de retour (M24-E41).

---

### M24-E08 — Keycloak en code avec OpenTofu

**Solution**

*A. Le compte d'OpenTofu.* Royaume `master` → *Clients* → *Create* : `svc-tofu-keycloak`, *Client authentication* ON, seul *Service accounts roles* coché. *Service accounts roles* → *Assign role* → filtre clients → client **`medisphere-realm`** : tous ses rôles **sauf** `impersonation` (`create-client`, `manage-authorization`, `manage-clients`, `manage-events`, `manage-identity-providers`, `manage-organizations`, `manage-realm`, `manage-users`, `query-*`, `view-*`). `impersonation` permettrait de se connecter **en tant que** n'importe quelle personne du royaume : OpenTofu n'en a jamais besoin. Le rôle `admin` de `master` donnerait tous les royaumes, `master` compris (donc la création d'administrateurs) ; `create-realm` permettrait de créer des royaumes (et d'en devenir administrateur) : le royaume existe, OpenTofu n'en crée pas. Secret dans `~/.config/workbook/keycloak-tofu.env` (même méthode que `keycloak-checks.env`, variables `KEYCLOAK_CLIENT_ID` et `KEYCLOAK_CLIENT_SECRET`, lues directement par le fournisseur), et en variables protégées masquées et cachées du projet.

*B. Le code et l'import.* [`fournisseurs.tf`](fichiers/M24-E08/identite/tofu/fournisseurs.tf), [`chiffrement.tf`](fichiers/M24-E08/identite/tofu/chiffrement.tf), [`variables.tf`](fichiers/M24-E08/identite/tofu/variables.tf), [`royaume.tf`](fichiers/M24-E08/identite/tofu/royaume.tf), [`federation-ldap.tf`](fichiers/M24-E08/identite/tofu/federation-ldap.tf), [`portees.tf`](fichiers/M24-E08/identite/tofu/portees.tf), [`comptes-service.tf`](fichiers/M24-E08/identite/tofu/comptes-service.tf), [`imports.tf`](fichiers/M24-E08/identite/tofu/imports.tf), et pour la première MR [`clients-essai.tf`](fichiers/M24-E08/identite/tofu/clients-essai.tf.premiere-mr). Outils : [`charger-acces.sh`](fichiers/M24-E08/identite/outils/charger-acces.sh), [`ci-preparer.sh`](fichiers/M24-E08/identite/outils/ci-preparer.sh), [`identifiants-keycloak.sh`](fichiers/M24-E08/identite/outils/identifiants-keycloak.sh) (liste en lecture les identifiants à importer).

Formats d'import (section *Import* de chaque ressource) :

| Ressource | Identifiant d'import |
|---|---|
| `keycloak_realm` | `medisphere` (le nom) |
| `keycloak_ldap_user_federation` | `medisphere/<ID fédération>` |
| `keycloak_ldap_group_mapper` | `medisphere/<ID fédération>/<ID mappeur>` |
| `keycloak_openid_client_scope` | `medisphere/<ID portée>` |
| `keycloak_openid_group_membership_protocol_mapper` | `medisphere/client-scope/<ID portée>/<ID mappeur>` |
| `keycloak_realm_default_client_scopes` | `medisphere` |
| `keycloak_openid_client` | `medisphere/<ID client>` (l'identifiant interne, pas `clientId`) |
| `keycloak_openid_client_service_account_role` | `medisphere/<ID utilisateur du compte de service>/<ID client realm-management>/<ID rôle>` |

```
admin@adm01:~/src/identite$ outils/identifiants-keycloak.sh
admin@adm01:~/src/identite$ . outils/charger-acces.sh
charger-acces : S3 (état), Keycloak (svc-tofu-keycloak), chiffrement et svc-keycloak chargés.
admin@adm01:~/src/identite$ tofu -chdir=tofu init && tofu -chdir=tofu plan
…
  # keycloak_ldap_user_federation.ipa01 will be updated in-place
  # (imported from "medisphere/…")
  ~ resource "keycloak_ldap_user_federation" "ipa01" {
      ~ bind_credential_wo              = (write-only attribute)
      + bind_credential_wo_version      = "1"
…
Plan: 11 to import, 0 to add, 1 to change, 0 to destroy.
```

La seule mise à jour attendue est celle de la fédération : un argument en **écriture seule** n'est jamais relu (Keycloak masque d'ailleurs `bindCredential` dans ses réponses) ; OpenTofu ne peut pas savoir si la valeur en place est la bonne, il la pousse donc une fois à l'import, puis seulement quand `bind_credential_wo_version` change (rotation, RB-244). Les autres écarts rencontrés pendant la mise au point, et leur traitement :

| Écart au premier plan | Cause | Décision |
|---|---|---|
| `default_signature_algorithm = "RS256" -> null` | attribut posé par Keycloak, absent du code | l'écrire dans `royaume.tf` |
| rôles de `wb-checks` « must be replaced » | source de données `realm-management` lue à l'apply car elle dépend du royaume en cours d'import | `realm_id = "medisphere"` en littéral dans la source de données |
| `use_refresh_tokens`, `backchannel_logout_session_required` | valeurs posées par la console à la création, différentes des défauts du fournisseur | les écrire comme la console (sans effet pour un compte de service) |
| `include_in_openid_provider_metadata false -> true` | défaut du fournisseur | `false`, comme la portée créée en E06 |
| portées par défaut | la liste du code doit être complète | recopier la liste de la console, `groupes` compris |

Contenu de l'état (`tofu state pull | jq '.resources[] | {type, name}'`) : les onze objets, la source de données. Le mot de passe de `svc-keycloak` **n'y est pas** (variable éphémère, argument en écriture seule) ; en revanche le fournisseur enregistre le **secret** de chaque client confidentiel (`client_secret` de `wb-checks`, d'`essai-oidc` avant sa suppression, et demain de `grafana`, `argocd`…) : le chiffrement de l'état (même phrase que `plateforme/infra`) et le compartiment `tofu-state` réservé à l'identité S3 `tofu-etat` sont indispensables.

*C. Pipeline et suppression.* [`.gitlab-ci.yml`](fichiers/M24-E08/identite/.gitlab-ci.yml) (état E08, remplace celui d'E03) : `tofu:valider` (`fmt -check`, `validate` sans état), `tofu:plan` (plan **enregistré**, artefact réservé aux Developers, alerte en tête de journal si le plan détruit), `tofu:apply` manuel sur `main`, qui applique **ce** plan puis exige un plan vide ; `tofu:secrets-indisponibles` explique pourquoi une MR d'une branche non protégée n'a pas de plan. La variable éphémère n'est pas conservée dans le plan enregistré : le job d'apply la relit dans son environnement. Première MR « import du royaume » → plan `11 to import, 1 to change`, fusion, apply, contrôle vide. Seconde MR (suppression de `clients-essai.tf` et de son import) :

```
  # keycloak_openid_client.essai_oidc will be destroyed
  # (because keycloak_openid_client.essai_oidc is not in configuration)
Plan: 0 to add, 0 to change, 1 to destroy.
⚠️  CE PLAN DÉTRUIT des objets du royaume : lire chaque ligne « - » ou « -/+ » de plan.txt.
```

Après l'apply, *Clients* ne montre plus `essai-oidc`, et sa suppression a un auteur, une date et une relecture : la MR.

**Explications**

- **Importer plutôt que recréer.** Recréer `wb-checks` changerait son secret (le check tomberait) ; recréer la fédération changerait son identifiant, donc le `federationLink` de chaque personne importée : Keycloak oublierait leurs OTP et leurs sessions. L'import reprend les objets tels quels.
- **Blocs `import` plutôt que `tofu import`.** Ils sont dans le code : relus en MR, appliqués par le pipeline, avec un plan qui montre exactement ce qui sera fait. La commande `tofu import` écrit dans l'état depuis un poste, sans relecture.
- **Variables éphémères et arguments en écriture seule** (OpenTofu ≥ 1.11) : la valeur sert à l'appel d'API puis disparaît ; ni le plan enregistré, ni l'état ne la gardent. Le fournisseur 5.10 propose `bind_credential_wo` pour la fédération (et `client_secret_wo` pour les clients, pour imposer un secret qu'on génère soi-même).
- **Un compte d'administration par royaume.** Le client `<royaume>-realm` de `master` est fait pour cela : ses rôles donnent les droits d'administration **sur ce royaume seul**, sans pouvoir toucher à `master`.

**Alternatives**

- *Tout créer par OpenTofu dès E05* : plus court, mais on décrit sans avoir vu ; et c'est l'occasion d'apprendre l'import, utile pour reprendre un royaume existant (InfoGér, M24-E22).
- *Export du royaume en JSON* (`kc.sh export`, *Partial export* de la console) et `kc.sh import` ou *keycloak-config-cli* : configuration déclarative en un fichier ; pas de plan, et keycloak-config-cli n'a plus d'images pour les versions 26.6 et suivantes (`annexes/versions-bloc-F.md`).
- *Opérateur et `KeycloakRealmImport`* : seulement pour un Keycloak dans Kubernetes, et l'import ne fait que créer (pas de mise à jour).
- *Authentification du fournisseur par JWT signé* (`jwt_signing_key`) au lieu d'un secret : pas de secret à faire tourner côté Keycloak, une clé privée à protéger côté CI.

**Pièges classiques**

- Importer un client par son `clientId` (`medisphere/wb-checks`) : le fournisseur attend l'identifiant **interne** (UUID).
- Une liste de portées par défaut incomplète : à l'apply, le fournisseur **retire** les portées absentes (par exemple `basic`, ce qui supprime `sub` des jetons de tous les nouveaux clients).
- `bind_credential` (non éphémère) avec une variable : le mot de passe finit en clair dans le plan enregistré et dans l'état.
- `tofu state pull > etat.json` « pour regarder » : un fichier en clair de plus, avec les secrets des clients.
- Pas de verrou de versions versionné : un `tofu init` le jour d'une nouvelle 5.x installe une version que personne n'a relue.
- Le 403 de HAProxy sur `/realms/master` depuis `runner01` : penser à l'adresse du runner dans la liste d'administration (E04).

**En production chez MédiSphère**

Royaume entièrement en code (y compris flux, durées, politiques de mot de passe locales, événements) avec un contrôle de dérive planifié (plan nocturne qui doit être vide, alerte sinon, comme M05-E28) ; secrets des clients générés par OpenTofu et rangés dans OpenBao (M25) plutôt que lus dans l'état ; authentification du pipeline par jeton d'identité GitLab (M19-E25) et OpenBao, sans secret statique ; revue de chaque MR qui touche un client par Sophie Laurent (règle d'approbation sur `tofu/clients-*.tf`).

---

### M24-E09 — Questions : OIDC, OAuth 2.0, SAML, LDAP et Kerberos

**Barème** : 2 points par question, total sur 22. Une réponse juste mais sans lien avec ce que tu as observé en E06-E07 vaut 1 point.

**1. Le flux de code.** (1) Le navigateur demande une page au **client** (Grafana) ; (2) le client le **redirige** vers le point d'autorisation du fournisseur avec `client_id`, `redirect_uri`, `scope`, `state`, `nonce`, `code_challenge` (dans l'URL, donc par le navigateur) ; (3) le **fournisseur** authentifie la personne (formulaire, annuaire, OTP) et ouvre une session SSO ; (4) il redirige le navigateur vers `redirect_uri` avec `code` et `state` (par le navigateur) ; (5) le client vérifie `state`, puis **de serveur à serveur** échange le code au point de jetons, en s'authentifiant et en présentant le `code_verifier` ; (6) le fournisseur renvoie ID token, jeton d'accès, jeton de rafraîchissement ; (7) le client vérifie l'ID token (signature, `iss`, `aud`, `exp`, `nonce`) et ouvre sa propre session. Par le navigateur ne passent que des paramètres sans valeur seuls : le code (une minute, usage unique, lié au verifier), jamais un jeton.

**2. Implicite et mot de passe.** L'implicite renvoie les jetons **dans l'URL** (fragment) : ils passent par le navigateur, l'historique, les extensions, les en-têtes `Referer`, sans liaison au client ; aucun jeton de rafraîchissement sûr ; il existait parce que les navigateurs ne savaient pas faire d'appels intersites (CORS) : ce n'est plus le cas, le code avec PKCE le remplace (RFC 9700, OAuth 2.1 le supprime). Le flux par mot de passe (*Direct Access Grants*) donne le mot de passe de la personne **au client** : il le voit, peut le garder, et le flux contourne le second facteur et toutes les étapes du fournisseur (OTP, consentement, détection d'anomalie). On le désactive partout ; il n'avait de sens que pour des clients de premier rang en migration.

**3. Réponse B.** L'ID token est destiné au client (`aud` = le client) et décrit l'authentification ; le jeton d'accès est destiné à une API (son `aud`), qui le vérifie. A est faux : un jeton d'accès n'est pas fait pour être lu par le client (son format n'est même pas garanti : il peut être opaque) ; C est faux : présenter l'ID token à une API, c'est lui donner un jeton qui ne la vise pas ; D est faux : userinfo est un complément, la signature de l'ID token suffit.

**4. `aud`.** Elle désigne le ou les destinataires du jeton ; chaque destinataire **refuse** un jeton qui ne le nomme pas. Attaque : un service peu sûr (ou malveillant) reçoit des jetons valides de ses utilisateurs ; sans contrôle d'audience, il pourrait les **rejouer** contre l'API de production, qui ferait confiance à la signature de Keycloak. En E07, le jeton d'accès d'`essai-oidc` avait `aud: account` : Keycloak a refusé de l'introspecter pour `essai-oidc` (`not in the token audience`) jusqu'à ce qu'un mappeur d'audience l'ajoute. kube-apiserver fera pareil avec l'audience `kubernetes` (M24-E16).

**5. `state` et `nonce`.** `state` protège la **requête d'autorisation** : valeur aléatoire liée à la session du navigateur côté client, renvoyée telle quelle dans la redirection ; le client vérifie qu'il attendait cette réponse. Sans cette vérification, un attaquant fait arriver dans la session de la victime une réponse obtenue avec **son** compte à lui (CSRF de connexion : la victime travaille dans le compte de l'attaquant). `nonce` protège l'**ID token** : envoyé dans la requête, recopié par le fournisseur dans l'ID token ; le client vérifie qu'il correspond, ce qui empêche de rejouer un ID token volé ailleurs. PKCE couvre aujourd'hui une partie du rôle de `state` ; on garde les deux.

**6. Réponse B.** Un client qui accepte plusieurs fournisseurs peut être trompé sur **lequel** lui répond (un fournisseur malveillant obtient le code émis par le fournisseur honnête : attaque *mix-up*) ; `iss` dans la réponse lui permet de vérifier que c'est l'émetteur à qui il a envoyé la personne. A : c'est PKCE ; C : rien à voir (`exp`) ; D : c'est la signature et la vérification des clés.

**7. SAML.** Une **assertion** est un document XML émis et **signé** par le fournisseur d'identité (l'IdP SAML), qui affirme une authentification et des attributs pour un **fournisseur de service** (SP) précis (`Audience`), avec une durée de validité. Elle passe **par le navigateur** (formulaire POST auto-soumis). Situations : un établissement de santé partenaire qui veut connecter ses agents à MédiAgenda avec son propre IdP (souvent SAML, ADFS ou Entra ID) ; un logiciel du marché (portail RH, outil de ticket) qui ne sait que SAML. Le lab choisit OIDC pour ses services : JSON et JWT plus simples à lire et à vérifier, pris en charge nativement par tous nos outils (Argo CD, Grafana, Kubernetes, kubelogin, OAuth2 Proxy, step-ca, OpenBao), adapté aux CLI et aux API ; Keycloak peut faire la passerelle SAML ↔ OIDC le jour où un partenaire l'exige.

**8. LDAP et Kerberos.** LDAP **range et sert** les données (personnes, groupes, règles HBAC et sudo) et sait vérifier un mot de passe par liaison ; Kerberos **authentifie** par tickets, sans faire circuler le mot de passe, et donne le SSO aux machines (SSH, NFS, `sudo` avec SSSD). Keycloak reçoit le mot de passe **dans son formulaire** (il le voit de toute façon) : le vérifier par une liaison LDAPS est direct et suffit. On ferait l'inverse (Kerberos) pour les postes **inscrits au domaine** : le navigateur présente un ticket Kerberos (SPNEGO), et la personne n'a plus de formulaire à remplir ; Keycloak le sait faire (fédération avec Kerberos).

**9. Réponse B.** En mode fédéré, Keycloak ne garde **pas** le mot de passe des personnes de l'annuaire : il fait une liaison LDAP à chaque connexion, avec ce que la personne a saisi. Le nouveau mot de passe est donc pris en compte tout de suite, l'ancien refusé tout de suite. A et C sont faux : la synchronisation recopie des attributs, pas des mots de passe ; D est faux : aucune empreinte n'est importée (FreeIPA ne la donnerait d'ailleurs pas à `svc-keycloak`).

**10. Fédération et synchronisation.** Fédérer, c'est **déléguer** à une autre source (l'annuaire) la vérité sur les personnes et la vérification des mots de passe, en direct ; synchroniser, c'est **recopier** des comptes d'un système dans un autre, qui devient autonome (deux vérités qui divergent : le compte supprimé ici reste là-bas). Notre synchronisation périodique (changements toutes les 15 min, complète chaque nuit) met à jour la **copie** que Keycloak garde des personnes et de leurs groupes : nouveaux arrivants visibles dans la console avant leur première connexion, changements de nom ou d'adresse, personnes désactivées marquées. Elle ne copie **pas** les mots de passe, n'écrit **jamais** dans l'annuaire (`READ_ONLY`), et n'est pas ce qui bloque un départ : la liaison LDAP à la connexion s'en charge. Ce qu'elle ne fait pas non plus : fermer les sessions déjà ouvertes d'une personne désactivée (RB-242).

**11. Répartition.**

| Responsabilité | Où | Pourquoi |
|---|---|---|
| Existence d'une personne | FreeIPA (par `plateforme/identite`) | source de vérité unique, auditée par les MR |
| Appartenance à un groupe | FreeIPA | idem ; Keycloak et les machines (SSSD) la lisent |
| Mot de passe | FreeIPA (politique, verrouillage, empreinte) | une seule politique pour le web et les machines (Kerberos) |
| Second facteur | Keycloak | il est demandé au formulaire web ; FreeIPA sait aussi faire de l'OTP (pour SSH/Kerberos), non retenu au lab |
| Session SSO | Keycloak | c'est l'objet du SSO web ; durées réglées au M24-E27 |
| Durée des jetons | Keycloak | émetteur des jetons |
| Droits dans Argo CD | Argo CD (`policy.csv`, à partir des `groups`) | seul Argo CD sait ce qu'est « synchroniser » ; versionné dans son dépôt |
| Accès SSH à une VM | FreeIPA (HBAC), appliqué par SSSD sur la VM ; certificat SSH court par step-ca après SSO | règle centrale, décision locale à chaque connexion |
| sudo | FreeIPA (règles sudo), appliqué par SSSD | idem |

L'IdP prouve **qui** ; l'annuaire dit **qui existe et dans quels groupes** ; chaque service et chaque machine décide **ce qui est permis**, à partir des groupes.

**Pour aller plus loin** : ces réponses reviennent dans l'ADR-0240 (M24-E31) et dans les questions d'attaques et défenses du M24-E45.

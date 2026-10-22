# ADR-0240 — Architecture d'identité de MédiSphère

| | |
|---|---|
| Statut | Accepté |
| Date | <AAAA-MM-JJ> |
| Ticket | PLAT-2531 (M24-E31), demandé par Claire Morel |
| Auteur | <MOI> ; relu par Karim Benali, Sophie Laurent |
| Liens | ADR-0241 (HA de Keycloak), `modele-autorisation.md` (E10), RB-240 à RB-246, PLAN §4.12 |

## Contexte

HDS et ISO 27001 exigent des accès **nominatifs**, une **authentification forte** des administrateurs, une **révocation** rapide au départ d'une personne et la **preuve** de qui a accès à quoi. Avant le M24 : un compte local par service (neuf services), des certificats `kubectl` de 7 jours, des clés SSH sans échéance. Contraintes : un hyperviseur, ≈ 110 Go sur 128, pas de second site, logiciels libres sans licence par utilisateur, 400 salariés.

## Décisions

| # | Décision | Options écartées (raison décisive) |
|---|---|---|
| 1 | **Annuaire FreeIPA 4.13** (`ipa01`, Rocky 10) : personnes, groupes, Kerberos, HBAC, sudo, CA subordonnée à « MédiSphère Root CA » ; contenu en code (`freeipa.ansible_freeipa`) | Samba AD (pas de HBAC ni de CA intégrée, administration Windows) ; OpenLDAP seul (ni Kerberos, ni HBAC, ni sudo, ni clients : tout à assembler) |
| 2 | **Keycloak 26.8** (`idp01`) comme seul fournisseur d'identité, royaume `medisphere` en OpenTofu, `master` réservé à l'administration | Authentik (moins mûr pour la fédération LDAP en lecture seule et l'OIDC des CLI) ; Zitadel (multi-locataire, base CockroachDB/PostgreSQL, fédération LDAP plus récente) ; Dex (pas de MFA, pas de console : un connecteur, pas un IdP) |
| 3 | **Fédération `READ_ONLY`** : l'annuaire est la seule vérité, Keycloak vérifie le mot de passe par liaison LDAP à chaque connexion | synchronisation (deux vérités, départ non immédiat) ; Keycloak comme annuaire (pas de Kerberos, ni HBAC, ni sudo) |
| 4 | **OIDC** pour tous les services (code + PKCE, redirections exactes, groupes `groups` en noms courts) ; **SAML** réservé aux partenaires (courtage dans Keycloak) | SAML partout (malcommode pour les CLI et les API) ; LDAP direct dans chaque service (mot de passe vu par chaque service, pas de SSO ni de MFA) |
| 5 | **`kubectl` par l'authentification structurée** de kube-apiserver (`AuthenticationConfiguration` v1, audience `kubernetes`, préfixes `oidc:`) + **kubelogin** ; `admin.conf` en bris de glace | certificats clients (pas de révocation) ; Pinniped (utile pour des clusters gérés, une pièce de plus ici) ; drapeaux `--oidc-*` (exclusifs, un seul émetteur, pas de règles CEL) |
| 6 | **SSH par certificats courts** (16 h) de step-ca, provisioner OIDC `keycloak`, comptes résolus par SSSD, HBAC dans l'annuaire | clés SSH (éternelles, non révocables) ; **Teleport** (binaires Community Edition interdits au-delà de 100 salariés ; compilation AGPLv3 ou contrat Enterprise : coût et maintenance) |
| 7 | **OAuth2 Proxy 7.15.5** devant ce qui ne sait pas l'OIDC (Hubble, Pyroscope, Pyrra, Mailpit), un client Keycloak partagé, une instance par interface | authentification basique (comptes partagés) ; filtrage réseau seul (pas d'identité) |
| 8 | **MFA** : OTP obligatoire pour `plateforme-admins` et `securite` (flux conditionnel), WebAuthn/passkeys en option ; jamais sur les comptes de secours ni de service | MFA pour tous dès maintenant (support et direction : déploiement à part) ; SMS (faible) |
| 9 | **Un seul nœud Keycloak** + sauvegardes restaurées + comptes de secours (ADR-0241) | deux nœuds sur un hyperviseur (la base reste un point unique) |
| 10 | **IdP hors du cluster** qu'il authentifie (VM, distribution officielle, Java 25) | Keycloak dans `k8s-par1` (dépendance circulaire : plus de `kubectl` OIDC quand le cluster va mal) |

## Conséquences

Positives : une identité par personne ; un départ = désactivation dans l'annuaire, effective à la connexion suivante partout ; droits par groupes, relus par la revue mensuelle (E30) ; MFA des administrateurs ; jetons et certificats de quelques heures ; journal d'audit des connexions et de l'administration (Loki `audit`).

Négatives et actions :

| Conséquence | Action / mesure |
|---|---|
| `idp01` et `ipa01` sont des points uniques : sans eux, plus de nouvelle connexion (et plus d'inscription ni de sudo sur les VMs sans cache SSSD) | supervision (E26), RB-243 (RTO mesuré), comptes de secours par service (RB-240), cache SSSD |
| Le compte `admin` de FreeIPA sert aussi à l'automatisation de l'annuaire | alerte d'usage (E28) ; compte de service à rôle limité (M25) |
| Comptes locaux de secours dans chaque service | RB-240 : coffre, essai trimestriel, alertes ; revue mensuelle |
| Les secrets des clients confidentiels transitent par OpenTofu ; avec un secret généré par Keycloak, l'état les contient | secrets imposés par `client_secret_wo` (E29 : plus dans l'état) ; état chiffré ; migration dans OpenBao (M25) |
| GitLab CE n'a pas les groupes OIDC | `outils/synchro-gitlab.py` (E11) |
| Grafana OSS n'a pas la synchronisation d'équipes | équipes par OpenTofu (M21) |
| PBS ne synchronise pas les groupes | ACL par utilisateur, revue mensuelle |
| Les sessions déjà ouvertes dans les services survivent à une désactivation | durées courtes (E27), procédure de départ RB-242 (fermeture des sessions Keycloak, jetons GitLab) |

## Risques acceptés

- Pas de réplica FreeIPA (mémoire) : RPO 24 h des données de l'annuaire, restauration de VM depuis PBS (RB-243).
- Un seul hyperviseur : la disponibilité de l'identité est celle de `pve01` (F5 : PRA).
- `X-Frame-Options: SAMEORIGIN` et non `DENY` (iframes de session de Keycloak).
- Les certificats SSH émis (16 h) et les jetons en cache (5 min) survivent à un départ : délai écrit dans RB-242.

## Ce que consomment les modules suivants

- **M25 (secrets)** : client OIDC **`openbao`** (méthode `oidc` d'OpenBao, groupes de l'annuaire → politiques par groupes externes) ; les **secrets des clients** quittent le Vault Ansible pour OpenBao (`kv/plateforme/keycloak/<client>`) et External Secrets ; le mot de passe de `svc-keycloak` aussi.
- **M26 (durcissement)** : `idp01` et `ipa01` passent par le rôle `durcissement` (CIS Debian 13, CIS RHEL 10) ; politiques d'admission qui s'appuient sur les groupes `oidc:*` ; journaux des hôtes (GitLab `root`, `pveproxy`) vers Loki `audit`.
- **F3 / F5** : astreinte (RB-246 « SSO indisponible ») ; PRA de l'identité (reconstruction d'`idp01` et d'`ipa01` à PAR2).

## Conditions de révision

Second hyperviseur ou second site ; plus de 100 comptes externes (partenaires) ; exigence de MFA pour tous ; abandon de FreeIPA par Rocky/RHEL ; Keycloak 27.

# Module 24 — Identité et accès

| | |
|---|---|
| **Bloc** | F — Sécurité |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v5 (socle v4 + `idp01`, `ipa01`) + `ceph-par1` + `k8s-par1` (≈ 107 Go) ; `idp02` (2241, 2 Go) le temps de M24-E24 |
| **Prérequis** | Module 23 (`traces-v1`) ; module 06 (step-ca, PowerDNS, certificats SSH, NetBox) ; module 07 (`lb01`/`lb02`) ; module 14 (RBAC, kubeadm) ; module 20 (Argo CD, comptes locaux) ; module 21 (Grafana, organisations) ; module 22 (locataire Loki `audit`) |
| **Durée indicative** | 103 à 125 heures (palier 1 : 21-25 h ; palier 2 : 40-46 h ; palier 3 : 22-27 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

Sophie Laurent a fait le compte avant l'audit HDS : GitLab, Argo CD, Grafana, Harbor, Proxmox, NetBox, Mailpit et le cluster ont chacun leurs comptes, leurs mots de passe et leurs oublis. Quand un prestataire d'InfoGér est parti l'an dernier, il a fallu trois semaines pour retrouver ses accès, et deux sont encore actifs. Claire Morel tranche : **une identité par personne, une seule source de vérité, une authentification forte pour les administrateurs, des droits qui découlent des groupes**, et la preuve écrite de qui a accès à quoi. L'équipe Plateforme construit l'annuaire de MédiSphère (FreeIPA), le fournisseur d'identité (Keycloak), branche tous les services en SSO, remplace les certificats personnels de `kubectl` et les clés SSH éternelles par des jetons et des certificats de quelques heures, et garde une porte de secours qu'on sait ouvrir.

## Objectifs

À la fin de ce module, tu sais :
- distinguer identification, authentification et autorisation, et lire OIDC, OAuth 2.0, SAML, LDAP et Kerberos au niveau des messages ;
- installer et exploiter un annuaire **FreeIPA** (utilisateurs, groupes, HBAC, sudo, CA subordonnée) et y inscrire des hôtes Linux ;
- installer, configurer en code (OpenTofu) et durcir **Keycloak** : royaumes, clients, fédération LDAP, flux d'authentification, MFA ;
- brancher en SSO GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox et Kubernetes (authentification structurée, kubelogin), et protéger par **OAuth2 Proxy** les interfaces qui ne savent pas le faire ;
- délivrer des certificats SSH courts après authentification unique ;
- concevoir un modèle d'autorisation par groupes, les procédures d'arrivée et de départ, la revue des accès et le bris de glace ;
- diagnostiquer les pannes d'identité : jetons refusés, horloges, fédération, redirections, RBAC.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M24-E01 | Test de positionnement : identité, authentification, autorisation | Q | ★★ | 1 |
| M24-E02 | Construire l'annuaire : FreeIPA sur `ipa01` et sa CA subordonnée | LAB | ★★★ | 1 |
| M24-E03 | Personnes, groupes et politiques de mot de passe en code | LAB | ★★ | 1 |
| M24-E04 | Installer Keycloak sur `idp01` et le publier | LAB | ★★ | 1 |
| M24-E05 | Premiers pas dans Keycloak : royaumes, clients, utilisateurs | LAB | ★ | 1 |
| M24-E06 | Fédérer l'annuaire FreeIPA dans Keycloak | LAB | ★★ | 1 |
| M24-E07 | OIDC à la main : code d'autorisation, PKCE, jetons et découverte | LAB | ★★ | 1 |
| M24-E08 | Keycloak en code avec OpenTofu | LAB | ★★ | 1 |
| M24-E09 | Questions : OIDC, OAuth 2.0, SAML, LDAP et Kerberos | Q | ★★ | 1 |
| M24-E10 | Le modèle d'autorisation : groupes, rôles et services | RED | ★★ | 2 |
| M24-E11 | SSO de GitLab | LAB | ★★ | 2 |
| M24-E12 | SSO de Grafana : rôles, organisations et équipes | LAB | ★★ | 2 |
| M24-E13 | SSO d'Argo CD et fin des comptes locaux | LAB | ★★ | 2 |
| M24-E14 | Harbor en OIDC | LAB | ★★★ | 2 |
| M24-E15 | Proxmox VE, PBS et NetBox en SSO | LAB | ★★ | 2 |
| M24-E16 | `kubectl` par OIDC : authentification structurée et kubelogin | LAB | ★★★ | 2 |
| M24-E17 | RBAC Kubernetes par groupes de l'annuaire | LAB | ★★ | 2 |
| M24-E18 | OAuth2 Proxy devant Hubble, Pyroscope et Mailpit | LAB | ★★ | 2 |
| M24-E19 | Inscrire les VMs dans FreeIPA : SSSD, HBAC et sudo | LAB | ★★★ | 2 |
| M24-E20 | SSH par certificats courts après SSO | LAB | ★★★ | 2 |
| M24-E21 | Authentification forte : OTP obligatoire, WebAuthn en option | LAB | ★★ | 2 |
| M24-E22 | Revue : la configuration Keycloak du stagiaire | REV | ★★ | 2 |
| M24-E23 | Arrivées, mobilités et départs | RED | ★★ | 2 |
| M24-E24 | Keycloak en haute disponibilité : essai à deux nœuds | LAB | ★★★ | 3 |
| M24-E25 | Sauvegarder et restaurer l'identité | LAB | ★★★ | 3 |
| M24-E26 | Superviser l'identité : santé, métriques, événements | LAB | ★★★ | 3 |
| M24-E27 | Durcir Keycloak : sessions, jetons, force brute, administration | LAB | ★★★ | 3 |
| M24-E28 | Bris de glace : comptes de secours et procédure éprouvée | LAB | ★★ | 3 |
| M24-E29 | Rotation des secrets des clients et des clés de signature | LAB | ★★★ | 3 |
| M24-E30 | Revue des accès automatisée : qui a accès à quoi | LIBRE | ★★★ | 3 |
| M24-E31 | ADR : l'architecture d'identité de MédiSphère | RED | ★★ | 3 |
| M24-E32 | Questions de production : Teleport, Pinniped, fédération, licences | Q | ★★★ | 3 |
| M24-E33 | Monter de version Keycloak et FreeIPA | LAB | ★★★ | 3 |
| M24-E34 | Ouvrir un nouveau service au SSO en temps limité | CHRONO | ★★★ | 3 |
| M24-E35 | Panne : plus personne n'entre dans Grafana | BF | ★★ | 4 |
| M24-E36 | Panne : `kubectl` refuse les jetons | BF | ★★★ | 4 |
| M24-E37 | Panne : les nouveaux arrivants n'existent pas | BF | ★★ | 4 |
| M24-E38 | Panne : « jeton expiré » à la première connexion | BF | ★★ | 4 |
| M24-E39 | Panne : les droits d'Argo CD sont faux | BF | ★★★ | 4 |
| M24-E40 | Panne : SSH et sudo refusés sur les VMs | BF | ★★★ | 4 |
| M24-E41 | Panne : boucle de redirection derrière OAuth2 Proxy | BF | ★★ | 4 |
| M24-E42 | Panne : le fournisseur d'identité ne répond plus comme avant | BF | ★★ | 4 |
| M24-E43 | Astreinte : la matinée où personne ne pouvait se connecter | BF | ★★★★ | 4 |
| M24-E44 | Sous le capot : signatures, JWKS, sessions et rotation des clés | LAB | ★★★★ | 4 |
| M24-E45 | Questions expert : attaques sur OIDC et défenses | Q | ★★★ | 4 |
| M24-E46 | Mini-projet : l'identité de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| `ipa01` | VMID 1031, 10.10.20.31, Rocky Linux 10 | FreeIPA 4.13 : annuaire, Kerberos `PAR1.MEDISPHERE.INTERNAL`, HBAC, sudo, CA subordonnée | E02 |
| `idp01` | VMID 1030, 10.10.20.30, Debian 13 | Keycloak 26.8 + PostgreSQL 17, `sso.par1.medisphere.internal` (publié par `lb01`/`lb02`) | E04 |
| `plateforme/identite` | projet GitLab | Royaume `medisphere` en OpenTofu, annuaire en Ansible (`freeipa.ansible_freeipa`) | E03, E08 |
| OAuth2 Proxy 7.15 | espace `oauth2-proxy` (Argo CD) ; `mon01` | Authentification devant Hubble UI, Pyroscope, Mailpit | E18 |
| `idp02` | VMID 2241, 10.10.20.42 | Second nœud Keycloak d'essai, **détruit** | E24 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.12. Versions : [`annexes/versions-bloc-F.md`](../../annexes/versions-bloc-F.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 24 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 24 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

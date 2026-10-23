# Identité MédiSphère v1 — fiche de livraison

*M24-E46 (PLAT-2546). Responsable : équipe Plateforme. Relu par : Sophie Laurent (RSSI), Karim Benali, Nadia Roussel, Julien Petit. Approuvé par : Claire Morel. Étiquette `identite-v1` de `plateforme/medisphere`. Exemple de corrigé : heures et chiffres représentatifs, à remplacer par les tiens.*

## 1. Ce qui est livré

| Brique | Où | Code | Exploitation |
|---|---|---|---|
| Annuaire FreeIPA 4.13 | `ipa01` (1031, 10.10.20.31), CA subordonnée de la racine MédiSphère | `plateforme/identite/annuaire/` (personnes, groupes, politiques, HBAC, sudo), job `annuaire:appliquer`, dérive `annuaire:derive` chaque nuit | `ipa-backup` + PBS (RB-243), journaux 389-ds et KDC dans Loki `audit` |
| Keycloak 26.8.1 | `idp01` (1030, 10.10.20.30), une instance (ADR-0241), PostgreSQL 17 locale | royaume `medisphere` en OpenTofu (`plateforme/identite/tofu/`, état chiffré), dérive `tofu:derive` chaque nuit | sauvegarde chiffrée (RB-243), alertes `KeycloakIndisponible`, `KeycloakEchecsConnexion`, `FederationLdapEnEchec`, `ClientSsoEnEchec`, `SsoSansServeur`, `KeycloakBaseSaturee`, sonde `oidc` du témoin |
| Publication | `sso.par1.medisphere.internal` → VIP `lb` → `be_sso` (TLS vérifié, santé sur 9000) | rôle `haproxy` | RB-246 |
| SSO des services | GitLab, Grafana, Argo CD, Harbor, Proxmox VE, PBS, NetBox, kubectl (authentification structurée, kubelogin), Hubble, Pyroscope, Pyrra, Mailpit (OAuth2 Proxy) | un client par service en code (URI exactes, sans flux implicite ni *Direct Access Grants*) | revue des accès mensuelle (`revue-acces/`) |
| Accès aux VMs | toutes les VMs inscrites (hors bordure) | rôles `freeipa_client`, `ssh_ca_utilisateur`, provisioner `keycloak` de step-ca | certificats de 16 h, HBAC, sudo par l'annuaire ; `SssdArrete` |
| Authentification forte | OTP pour `plateforme-admins` et `securite` (flux `navigateur-medisphere`), WebAuthn facultatif | `tofu/flux.tf` | RB-242 (perte de téléphone) |

## 2. Comptes locaux restants (inventaire)

| Service | Compte | Type | Rangement | Alerte d'usage |
|---|---|---|---|---|
| Keycloak (`master`) | `kc-secours` | secours | Vault `critique`, coffre | `BrisDeGlaceKeycloak` |
| Keycloak (`master`) | `<MOI>-admin` | personne (administration, OTP) | — | événements d'administration |
| Keycloak (`master`) | `svc-tofu-keycloak` | service (OpenTofu) | variable protégée de CI, `~/.config/workbook/keycloak-tofu.env` | client utilisé hors `runner01` (RB-246 §1) |
| FreeIPA | `admin` | secours (et automatisation de l'annuaire) | Vault `critique` | `BrisDeGlaceAnnuaire` |
| GitLab | `root` | secours (seul mot de passe local accepté) | gestionnaire, coffre | journal d'audit |
| Argo CD | `admin` (désactivé), `ci-lecture` (jeton) | secours réactivable ; service | Helmfile ; Vault | `ConfigurationArgoCDModifiee` |
| Grafana | `admin` ; compte de service `wb-checks`, `revue-acces` | secours ; service | Vault `critique` (Secret `grafana-admin`) | journal de Grafana |
| Harbor | `admin` (base locale) ; robots | secours ; service | Vault `critique` | journal de Harbor |
| Proxmox VE, PBS | `root@pam` ; jetons d'automatisation | secours ; service | coffre ; Vault | journal des tâches |
| NetBox | superutilisateur local | secours | Vault `critique` | — (limite) |
| Cluster | `admin.conf` | secours | Vault `critique` | `BrisDeGlaceCluster` |
| VMs | `admin` local (clé d'`adm01`, `ms-ssh-cert`) | secours et automatisation | `adm01`, Vault | journal de step-ca |
| Mailpit | `wb-checks`, `sso` (basique, MGMT seulement) | service | Vault | — |

Aucun compte local de **personne** ne reste en dehors de `<MOI>-admin` (administration de `master`, hors du royaume des personnes).

## 3. Démonstration de départ (RB-242)

Thomas Leroy (`thomas.leroy`, prestataire, groupe `plateforme`), le <AAAA-MM-JJ>, chronomètre de Claire :

| Heure | Étape | Preuve (`outils/preuves-depart.sh thomas.leroy`, extrait) |
|---|---|---|
| <HH:MM> (T0) | MR `etat: disabled` + retrait de `plateforme`, fusion, `annuaire:appliquer` | Annuaire : verrouillé, aucun groupe — coupé |
| T0 + 3 min | sessions Keycloak fermées | Keycloak : 0 session — coupé |
| T0 + 6 min | jeton GitLab révoqué, sessions Grafana fermées, utilisateur Harbor supprimé | GitLab : 0 jeton actif ; Grafana : 0 — coupé |
| T0 + 9 min | refus constatés : SSO (`LOGIN_ERROR … user_disabled`), SSH avec le certificat encore valable (`pam_sss … Access denied`), `kubectl` au rafraîchissement | journaux Loki `audit`, `journalctl -u ssh` de `mon01` |
| T0 + 12 min | revue des accès relancée | Thomas en « désactivé », aucun accès |

**Durée totale : 12 minutes** (objectif : 15). Restait ouvert, par construction : le certificat SSH (valable 16 h, inutilisable : SSSD refuse le compte), le dernier jeton d'accès (5 min au plus), aucune session de service non fermée.

## 4. Limites assumées (ce qui n'est pas couvert)

| Limite | Risque | Ce qui la détecte | Traitée par |
|---|---|---|---|
| Une seule instance de Keycloak (ADR-0241) | SSO indisponible le temps d'une restauration | `KeycloakIndisponible`, sonde du témoin | RB-246, RB-243 ; F5 (PRA) |
| Annuaire sans réplica | annuaire indisponible : plus de nouvelles connexions | `FederationLdapEnEchec`, sonde LDAPS | F5 |
| `idp01` et la CA SSH d'utilisateurs sans HSM | vol de la clé de signature = jetons ou certificats forgés | événements d'administration, alertes de bris de glace | M26 (durcissement), F6 |
| Aucune déconnexion par canal arrière vers les services | sessions de service ouvertes après un départ | revue des accès, RB-242 étape 4 | à chaque montée de version des services |
| Jetons non liés à l'émetteur de la requête (pas de DPoP ni mTLS) | jeton d'accès volé utilisable 5 min | — | à surveiller (M24-E45 q. 8) |
| Argo CD sans PKCE (client confidentiel) | injection de code (faible : `state`, secret) | — | ticket SEC-2545 |
| Secrets des clients dans Ansible Vault, poussés par `secrets-k8s.sh` | rotation manuelle (RB-244) | âge des secrets dans la revue d'accès | **M25** (OpenBao, External Secrets) |
| Thanos Query et Alertmanager sans authentification (filtrage réseau) | lecture des métriques, silences depuis MGMT | — | promesse du M21 reportée : M26 |
| Tableau de bord de Ceph sans SSO ; pas de fédération Keystone | comptes locaux sur ces interfaces | revue d'accès (hors périmètre aujourd'hui) | M26 ; OpenStack hors du profil de lab |
| Console d'administration de Keycloak sous le même nom que le SSO (filtrage par chemin) | exposition de `/admin` si une règle de HAProxy est mal écrite | journal de HAProxy | M26 (`hostname-admin`) |

## 5. Promesses des modules précédents

Tenues : SSO de GitLab avec mot de passe réservé à `root` (M01, réglage *Disable password authentication for users with an SSO identity*), comptes nominatifs Proxmox et TOTP par l'IdP (M09), Hubble derrière OIDC (M15), Grafana en SSO (M21), `kubectl` par OIDC (M14), certificats SSH nominatifs (M06). Partielles ou reportées : authentification devant Prometheus/Thanos Query/Alertmanager (Pyrra seulement : M26), CA SSH sous HSM (F6), tableau de bord de Ceph (M26), fédération Keystone (hors profil).

## 6. Ce que consommera le M25 (secrets)

- Un client **`openbao`** à créer en code dans `plateforme/identite/tofu/` (confidentiel, URI de retour de la méthode OIDC d'OpenBao et de `bao login -method=oidc` en local, PKCE, portée `groupes`) ; Keycloak et l'annuaire sont prêts, rien n'est créé d'avance.
- Les **groupes** de l'annuaire (revendication `groups`, noms courts) → politiques OpenBao (`plateforme-admins`, `plateforme`, `mediagenda`, `medidoc`, `securite`).
- Les **secrets des clients** (`keycloak_secrets_clients.*` du Vault `critique`) et le mot de passe de `svc-keycloak` à migrer dans OpenBao, distribués par External Secrets à la place de `secrets-k8s.sh`.
- RB-240 : les secrets de secours dans OpenBao avec ouverture à deux.

## 7. Ce que consommera le M26 (durcissement)

- Durcissement d'`idp01` et `ipa01` (CIS, systemd, pare-feu local), console d'administration de Keycloak sous un autre nom (`hostname-admin`, MGMT seulement).
- Journal d'audit (Kubernetes, Falco, Tetragon) rattaché aux identités `oidc:*` ; `exec` réservé au bris de glace par le RBAC.
- Politiques d'admission qui supposent les groupes de l'annuaire (pas de liaison RBAC vers une personne).

## 8. Démonstration « SSO coupé » (Nadia)

<AAAA-MM-JJ HH:MM> arrêt de Keycloak (CHG-2546) ; <+2 min> `KeycloakIndisponible` ; entrée dans Grafana (`admin`, RB-240) et dans le cluster (`admin.conf`) ; alertes `BrisDeGlace*` reçues par Sophie et l'astreinte ; <+18 min> comptes refermés, Keycloak redémarré, `lab/bin/check 24 42` vert.

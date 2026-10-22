# Modèle d'autorisation de MédiSphère

| | |
|---|---|
| Ticket | SEC-2510 |
| Exercice | M24-E10 (appliqué par M24-E11 à E21) |
| Propriétaire | Sophie Laurent (RSSI) ; maintenu par l'équipe Plateforme |
| Source des groupes | annuaire FreeIPA (`plateforme/identite`, `annuaire/groupes.yml`) |
| Contrôle | revue d'accès mensuelle automatisée (M24-E30) : la réalité de chaque service est comparée à ce document |
| Dernière revue | <DATE> |

Toute modification de ce document passe par une MR relue par la RSSI. Un branchement qui s'en écarte est corrigé (le branchement **ou** ce document, jamais en silence).

## 1. Principes

1. **Les droits découlent des groupes, jamais des personnes.** Aucun nom de personne dans une politique, une ACL, une liaison RBAC ou une table de correspondance. Arriver, changer d'équipe ou partir = une MR sur `annuaire/groupes.yml` ou `annuaire/personnes.yml`, rien d'autre.
2. **Moindre privilège par défaut.** Un compte authentifié sans groupe reconnu ne voit rien (Argo CD : `policy.default` vide ; Kubernetes : aucune liaison ; Grafana : Viewer de l'organisation principale seulement). L'écriture en production est l'exception, justifiée ligne par ligne ci-dessous.
3. **Un compte par personne, nominatif et fédéré.** Les comptes humains viennent de Keycloak (lui-même fédéré à l'annuaire). Un compte local d'humain est une anomalie, sauf les comptes de bris de glace (section 5).
4. **Authentification forte pour qui administre.** Les membres de `plateforme-admins` et `securite` ont l'OTP obligatoire (M24-E21) ; leurs droits d'administration ne s'exercent que par le SSO.
5. **Une porte de secours par service, éprouvée et surveillée.** Elle ne dépend pas du SSO, son secret est au Vault `critique` (et au coffre), son usage est journalisé et alerté (RB-240).

## 2. Groupes

| Groupe | Qui (à titre indicatif : la vérité est l'annuaire) | Raison d'être |
|---|---|---|
| `plateforme-admins` | administrateurs de la plateforme | administration complète, astreinte niveau 2 |
| `plateforme` | équipe Plateforme (dont le stagiaire) | exploitation courante, lecture large, écriture dans les dépôts de la plateforme par MR |
| `mediagenda` | équipe MédiAgenda | livrer en dev et recette, lire la production |
| `medidoc` | équipe MédiDoc | idem pour MédiDoc |
| `securite` | RSSI | audit en lecture partout, organisation « Sécurité » de Grafana |
| `support` | support et astreinte niveau 1 | lecture et diagnostic |
| `direction` | direction | rapports, revue d'accès ; n'écrit nulle part |

## 3. Matrice groupes × services

Lecture : rôle natif du service, puis sa portée. « — » : aucun accès.

| Service | `plateforme-admins` | `plateforme` | `mediagenda` | `medidoc` | `securite` | `support` | `direction` |
|---|---|---|---|---|---|---|---|
| **GitLab** (groupes de premier niveau) | Maintainer de `plateforme` | Developer de `plateforme` | Maintainer de `mediagenda` | Maintainer de `medidoc` | Reporter de `plateforme`, `mediagenda`, `medidoc` | Reporter de `plateforme` | Reporter de `plateforme` |
| **Grafana** | *Grafana Admin* (serveur) + Admin de l'organisation principale ; Viewer de « Sécurité » | Editor | Viewer | Viewer | Viewer ; Editor de « Sécurité » | Editor ; Viewer de « Sécurité » | Viewer ; Viewer de « Sécurité » |
| **Argo CD** | `role:plateforme-admin` (hérite de `role:admin`) | `role:lecture` | `role:mediagenda-equipe` | rôle de projet `medidoc/equipe` | `role:lecture` | `role:lecture` | — |
| **Harbor** | administrateur système (`oidc_admin_group`) | `maintainer` de `medisphere`, `developer` de `plateforme`, `bibliotheque`, `charts` | `developer` de `medisphere` | `developer` de `medisphere` | — (audit par le journal de Harbor exporté) | — | — |
| **Proxmox VE** (`pve01`) | `PVEAdmin` sur `/` | `PVEAuditor` sur `/` | — | — | `PVEAuditor` sur `/` | `PVEAuditor` sur `/pool/lab` | — |
| **PBS** (`pbs01`) | `Admin` sur `/` (par personne) | — | — | — | `Audit` sur `/` (par personne) | `DatastoreAudit` sur `/datastore/ds-lab` (par personne) | — |
| **NetBox** | groupe local `sso-ecriture` (+ `sso-lecture`) | `sso-lecture` | `sso-lecture` | `sso-lecture` | `sso-lecture` | `sso-lecture` | `sso-lecture` |
| **Cluster `k8s-par1`** | `cluster-admin` | ClusterRole `medisphere-plateforme` : lecture globale sans Secrets, écriture dans `wb-essais` | `view` dans `mediagenda-dev`, `-recette`, `-prod` ; `edit` dans `mediagenda-dev` | `view` dans `medidoc-dev`, `-recette` | ClusterRole `medisphere-securite` : lecture sans Secrets | ClusterRole `medisphere-lecture` : lecture sans Secrets | — |
| **VMs du socle** (SSH par certificat, HBAC, sudo) | toutes les VMs inscrites ; sudo complet (`sudo-plateforme-admins`) | toutes les VMs inscrites ; sudo de consultation (`sudo-plateforme`) | — | — | — | `mon01`, `nbx01` ; pas de sudo | — |
| **Interfaces derrière OAuth2 Proxy** | Hubble, Pyroscope, Mailpit | Hubble, Pyroscope, Mailpit | Pyroscope | Pyroscope | — | Hubble, Pyroscope, Mailpit | — |
| **Keycloak** (console) | — par le SSO ; administrateurs nominatifs de `master` (`<MOI>-admin`) | — | — | — | — | — | — |
| **OpenBao** (M25) | politique `plateforme-admin` | lecture des chemins `kv/plateforme/*` hors `critique` | `kv/mediagenda/*` | `kv/medidoc/*` | lecture du journal d'audit | — | — |

**Lucas, stagiaire (`plateforme`) en une ligne** : il lit tout ce que la plateforme exploite (Grafana Editor, Argo CD et cluster en lecture sans Secrets, Proxmox en auditeur, SSH et sudo de consultation) et propose des changements par MR (Developer de `plateforme`, `edit` dans `wb-essais`), mais ne fusionne rien sur `main`, ne synchronise aucune Application, n'écrit dans aucun espace applicatif et n'a aucun droit en production : tout changement réel passe par la relecture d'un membre de `plateforme-admins`.

## 4. Comment le groupe arrive jusqu'au droit

| Service | Mécanisme | Où c'est écrit |
|---|---|---|
| GitLab CE | **synchronisation par l'API** (`outils/synchro-gitlab.py`, pipeline planifié horaire), car les groupes OIDC sont réservés à Premium | `plateforme/identite`, `outils/synchro-gitlab.yml` |
| Grafana OSS | revendication `groups` → `role_attribute_path` (rôle de l'organisation principale) et `org_mapping` (organisation « Sécurité »), à chaque connexion. **Équipes** : OpenTofu (la *team sync* est Enterprise) | `plateforme/observabilite`, `kps/values.yaml` ; `plateforme/infra`, `observabilite-grafana/` |
| Argo CD | revendication `groups` (`scopes: [groups]`) → lignes `g` de `policy.csv` et rôles de projet | `plateforme/k8s`, `releases/argocd/policy.csv` ; `plateforme/gitops`, `projets/` |
| Harbor | revendication `groups` → groupes OIDC membres des projets ; `oidc_admin_group` | `plateforme/infra`, `registre/` |
| Proxmox VE | revendication `groups` → groupes `<groupe>-medisphere` (déclarés en code, écrasés à chaque connexion) → ACL | `plateforme/infra`, `acces-proxmox/` |
| PBS | **aucune** correspondance de groupes dans le royaume OpenID : ACL **par personne**, posées à la main par `plateforme-admins` à l'arrivée (RB-241) | ce document, section 3 ; RB-241 |
| NetBox | groupes non transmis par le flux OIDC : groupe par défaut `sso-lecture` (`REMOTE_AUTH_DEFAULT_GROUPS`), `sso-ecriture` donné à la main | rôle `netbox` ; RB-241 |
| Kubernetes | revendication `groups` préfixée `oidc:` → liaisons RBAC | `plateforme/k8s`, `rbac/oidc.yaml` |
| VMs | groupes de l'annuaire lus par SSSD → HBAC et sudo de FreeIPA | `plateforme/identite`, `annuaire/hbac.yml`, `sudo.yml` |
| OAuth2 Proxy | revendication `groups` → `--allowed-group` | `plateforme/gitops` (releases), rôle Ansible de `mon01` |

## 5. Séparation des tâches

| Droits à ne pas cumuler | Mécanisme |
|---|---|
| Écrire un changement de droits **et** l'approuver | règle d'approbation des MR sur `annuaire/`, `tofu/clients-*.tf`, `policy.csv`, `rbac/` : l'auteur ne compte pas ; une approbation de `securite` exigée sur `annuaire/groupes.yml` (en CE, règle tenue par revue et vérifiée dans la revue d'accès, faute d'approbations obligatoires) |
| Administrer Keycloak **et** l'annuaire avec le même compte | `<MOI>-admin` (royaume `master`) et `admin` (FreeIPA) sont distincts ; aucune personne n'a de rôle d'administration FreeIPA à son nom ; l'annuaire ne change que par le pipeline |
| Livrer en production **et** changer la politique d'admission (M26) | `mediagenda` ne synchronise pas `mediagenda-prod` ; `plateforme/politiques` n'est fusionnable que par `plateforme-admins` |
| Utiliser un compte de bris de glace **et** effacer ses traces | journaux envoyés à Loki (locataire `audit`, lecture par l'organisation « Sécurité ») ; alerte à l'usage (RB-240) |
| Gérer les sauvegardes **et** pouvoir les supprimer sans trace | PBS : personne n'a `DatastoreAdmin` par le SSO hors `plateforme-admins` ; politique de rétention en code (M22) |

## 6. Comptes qui restent locaux

| Compte | Service | Raison | Propriétaire | Protection |
|---|---|---|---|---|
| `root` | GitLab | bris de glace (SSO en panne) | Plateforme | Vault `critique` + coffre ; connexion alertée (journal d'audit → Loki) ; RB-240 |
| `admin` | Grafana | bris de glace ; fournisseur OpenTofu `admin_serveur` (API d'administration) | Plateforme | Vault `critique` ; formulaire désactivé, API seulement |
| `admin` | Argo CD | bris de glace, **désactivé** (`admin.enabled: false`), réactivable par Helmfile | Plateforme | réactivation tracée (MR ou journal) ; RB-240 |
| `ci-lecture` | Argo CD | jeton des vérifications | Plateforme | `apiKey` seul, `role:lecture` |
| `admin` | Harbor | bris de glace, administrateur système | Plateforme | Vault `critique` ; journal d'audit de Harbor |
| robots `robot$…` | Harbor | CI, Argo CD, checks | Plateforme | durée 180 jours, permissions explicites (M13) |
| `root@pam` | Proxmox VE, PBS | bris de glace de l'hyperviseur et des sauvegardes | Plateforme | coffre ; console physique ; alerte à la connexion |
| `wb-admin@pve` | Proxmox VE | ancien compte humain du M00, **désactivé** (pas supprimé : historique des tâches) | Plateforme | désactivé |
| `wb-*@pve` et leurs jetons | Proxmox VE | automatisation (Packer, Ansible, OpenTofu, lecture) | Plateforme | rôles minimaux, variables protégées de CI |
| `admin` | NetBox | bris de glace | Plateforme | Vault `critique` |
| `wb-checks`, `svc-automatisation`, `svc-supervision` | NetBox | jetons d'API | Plateforme | jetons v2, permissions limitées |
| `admin.conf` | Kubernetes | bris de glace (`kubernetes-admin`, groupe `kubeadm:cluster-admins`) | Plateforme | Vault `critique` ; usage visible dans l'audit de l'API |
| comptes de service Kubernetes | Kubernetes | charges de travail, `wb-checks` | équipes | jetons liés, sauf `wb-checks` (exception documentée, M14) |
| `admin` (local, clé SSH) | VMs | Ansible et bris de glace | Plateforme | clé d'`adm01` et `ansible-ci` (`from=10.10.20.15`) |
| `admin` | FreeIPA | bris de glace de l'annuaire, automatisation de l'annuaire | Plateforme | Vault `critique` ; exclu de la fédération |
| `kc-secours` | Keycloak (`master`) | bris de glace de l'IdP | Plateforme | Vault `critique` + coffre ; sans OTP ; connexion alertée |
| `svc-tofu-keycloak`, `svc-keycloak`, `wb-checks` | Keycloak, FreeIPA | automatisation, fédération, vérifications | Plateforme | secrets en Vault et variables protégées ; rôles minimaux |
| `svc-synchro-identite` | GitLab | synchronisation des groupes | Plateforme | Owner des trois groupes (exigé par GitLab pour gérer les membres), bornes dans l'outil (jamais le niveau Owner), jeton à expiration en variable protégée |
| compte basique de l'API Mailpit | Mailpit | vérifications | Plateforme | API filtrée à MGMT |

## 7. Écarts et décisions

| Écart | Cause | Décision |
|---|---|---|
| Pas de groupes OIDC dans GitLab | Premium/Ultimate seulement | synchronisation par l'API, horaire ; retard maximal d'une heure accepté (le départ coupe la connexion tout de suite : RB-242) |
| Pas de *team sync* dans Grafana | Enterprise | équipes en OpenTofu, membres par adresse ; un membre qui ne s'est jamais connecté est ajouté au plan suivant |
| PBS sans groupes | royaume OpenID de PBS sans correspondance de groupes | ACL par personne, peu nombreuses ; contrôlées par la revue d'accès |
| NetBox sans groupes par OIDC | `python-social-auth` ne transmet pas les groupes ; la synchronisation existe seulement en mode en-tête de mandataire | groupe par défaut en lecture, écriture donnée à la main ; à revoir si NetBox passe derrière OAuth2 Proxy |
| Le compte de synchronisation GitLab est Owner | GitLab réserve la gestion des membres d'un groupe aux Owners | l'outil ne donne ni ne retire jamais le niveau Owner ; les Owners se gèrent à la main (deux personnes au plus), contrôlés par la revue d'accès |
| Sessions déjà ouvertes au départ d'une personne | chaque service garde sa propre session | RB-242 : fermeture des sessions Keycloak, puis des sessions et jetons propres à chaque service |

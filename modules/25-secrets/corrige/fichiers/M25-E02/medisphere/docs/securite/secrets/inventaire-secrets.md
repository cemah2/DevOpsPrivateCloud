# Inventaire des secrets de MédiSphère

> M25-E02 (SEC-2602). Registre de **tous** les secrets de la plateforme : où ils sont, qui les lit,
> comment ils tournent, ce qu'une fuite coûterait, et où ils iront. Il ne contient **aucune valeur**.
> Il prend la suite de `docs/socle/registre-secrets.md` (M01 à M24), qui reste la liste détaillée des
> jetons et de leurs procédures de rotation ; l'inventaire est la vue d'ensemble, revue chaque
> trimestre et à chaque départ. Mis à jour au mini-projet (M25-E46) avec l'état de la migration.
>
> Relevé du `<AAAA-MM-JJ>` par `<MOI>` (commandes du relevé : M25-E02, corrigé). Les lignes marquées
> *(à vérifier)* dépendent de choix faits dans les modules précédents : confronte-les à ton lab.

## Échelle de criticité

| Niveau | Une fuite permet… | Exemples |
|---|---|---|
| **C1** | de prendre la main sur toute la plateforme, ou de lire des données de santé | clé de la racine PKI, jeton `wb-automation@pve`, `admin.conf`, mots de passe Vault `critique`, base de production |
| **C2** | de prendre la main sur un service, ou de se faire passer pour lui | secrets des clients OIDC, jetons de runner, clé Cosign, clés S3 des sauvegardes |
| **C3** | une gêne limitée, un service de lecture ou d'essai | jetons de lecture des checks, comptes d'essai |

## Cibles de migration

| Code | Cible | Module |
|---|---|---|
| `KV` | secret statique dans `kv/…` d'OpenBao, livré par ESO (cluster), lookup Ansible (VMs) ou CLI | M25-E04, E11, E13 |
| `DYN` | identifiant **dynamique** délivré à la demande, durée courte | M25-E14 |
| `ID` | **supprimé** : remplacé par une identité vérifiée (jeton OIDC de GitLab, compte de service Kubernetes, SSO) | M25-E06, E10, E12 |
| `TR` | clé qui ne sort plus : chiffrement ou signature par `transit` | M25-E17, E20 |
| `PKI` | certificat court émis à la demande | M25-E16 |
| `AMO` | **reste** hors du coffre : amorçage ou bris de glace (le coffre en dépend, ou on en a besoin quand il est fermé) | — |

## Inventaire

| # | Secret | Propriétaire | Où aujourd'hui | Qui le lit | Rotation aujourd'hui | Crit. | Cible |
|---|---|---|---|---|---|---|---|
| 1 | Mots de passe des identités Ansible Vault `lab` et `critique` | plateforme | `adm01` (`outils/vault-pass-client.sh`, M04), variables protégées de CI | Ansible, pipelines | à chaque départ (M04-E42) | C1 | `KV` (`kv/plateforme/ansible-vault`, E11) ; copie `AMO` sous scellé |
| 2 | Contenu des Vaults `lab` (mots de passe de services, clés API) | plateforme | `plateforme/ansible/inventories/**/vault-*.yml`, chiffrés | Ansible | rare, à la main | C2 | `KV` progressivement (lookups, E11) |
| 3 | Contenu du Vault `critique` (`admin` FreeIPA, *Directory Manager*, `kc-secours`, `root` GitLab, base de Keycloak…) | plateforme | `vault-critique.yml` (identité `critique`) | Ansible, bris de glace | rare | C1 | `AMO` : bris de glace, doit rester lisible coffre fermé |
| 4 | Parts de la clé racine d'OpenBao | dépositaires | `secrets/openbao-init.yml` (Vault `critique` + `age` par personne), M25-E03 | 3 dépositaires sur 5 | à chaque départ d'un dépositaire | C1 | `AMO` (par nature) |
| 5 | Clé privée de « MédiSphère Root CA » | plateforme | `~/pki-racine` d'`adm01` (hors ligne, chiffrée), archives (M06-E02) | cérémonie | jamais (expiration) | C1 | `AMO` hors ligne |
| 6 | Mot de passe du provisioner JWK et de la CA intermédiaire de step-ca | plateforme | `ca01` (fichier de mot de passe), Vault `critique` | step-ca | jamais | C1 | `AMO` (step-ca démarre sans le coffre) |
| 7 | Jeton API Proxmox `wb-automation@pve!lab` | plateforme | `~/.config/workbook/pve-api.env`, variables de CI de `plateforme/infra` | medictl, OpenTofu (bpg/proxmox) | annuelle *(à vérifier)* | C1 | `KV` (`kv/plateforme/medictl/pve`, E07) puis `ID` pour la CI |
| 8 | Jeton Proxmox de lecture (synchronisation NetBox, supervision `pve-exporter`) | plateforme | `pve-lecture.env` sur `adm01`, Secret du cluster (M21) | medictl, pve-exporter | annuelle | C3 | `KV` |
| 9 | Jetons GitLab personnels des checks (`workbook-checks`, `workbook-admin`) | `<MOI>` | `~/.config/workbook/gitlab-*.token` | checks, scripts | 1 an / 90 jours (M01-E20) | C2 | reste un jeton personnel, durée courte ; inventaire automatique (M19) |
| 10 | Jetons d'accès de projet et de groupe GitLab (`bot-release`, `svc-synchro-identite`…) | plateforme | variables de CI protégées | pipelines | 1 an | C2 | `ID` (jeton d'identité + OpenBao, E10) ou `KV` avec rotation planifiée (E33) |
| 11 | Jetons d'authentification des runners (`runner01`, `runner02`, runners Kubernetes) | plateforme | `config.toml` des runners ; Secrets `gitlab-runner`, `gitlab-runner-protege-jeton` | gitlab-runner | à la réinscription | C2 | `KV` (Secrets par ESO, E13) |
| 12 | Clés S3 du cache de CI (`ci-cache-s3`) | plateforme | Secret `gitlab-runner/ci-cache-s3` (`secrets-k8s.sh`) | runners | jamais *(à vérifier)* | C2 | `KV` + ESO |
| 13 | Clé privée Cosign et sa phrase de passe | plateforme | Secret `ci-jobs-protege/cosign-medisphere` (M19-E24) | jobs protégés de signature | jamais | C1 | `TR` (`transit/cosign-medisphere`, E20) |
| 14 | Robots Harbor (pull du cluster, push de la CI) | plateforme | Secrets `harbor-pull` des espaces, variables de CI | kubelet, CI | 1 an *(à vérifier)* | C2 | `KV` + ESO ; `ID` pour la CI quand Harbor l'accepte |
| 15 | Clés TSIG (mises à jour dynamiques de PowerDNS, ExternalDNS) | plateforme | Vault `lab` ; Secret `externaldns-tsig` | PowerDNS, ExternalDNS | jamais | C2 | `KV` + ESO |
| 16 | Clé API de PowerDNS | plateforme | Vault `lab` ; `powerdns-api.env` (`adm01`) ; variables de CI de `plateforme/infra` | OpenTofu, medictl | jamais | C2 | `KV` |
| 17 | Jeton NetBox d'automatisation | plateforme | `netbox-auto.token` (`adm01`), CI | medictl, inventaire Ansible, OpenTofu | 1 an | C2 | `KV` |
| 18 | Clés S3 de l'état OpenTofu (`tofu-etat`) et phrase de chiffrement de l'état | plateforme | `s3-tofu.env`, `tofu-chiffrement.pass` (`adm01`), variables de CI | OpenTofu | jamais | C1 | `KV` (CI par `ID`, E10) ; phrase : `AMO` sous scellé |
| 19 | Clés WireGuard (`wg0` inter-sites, `wg1` VPN) | plateforme | `gw01`/`gw02`, `hp01`, poste de l'apprenant | WireGuard | annuelle (ADR-0070) | C1 | `AMO` (la bordure doit démarrer sans le coffre) |
| 20 | Clés SSH : `admin` des VMs, `ansible-ci` (runner), CA SSH de step-ca | plateforme | `adm01`, variables protégées de CI, `ca01` | SSH, Ansible | à chaque départ | C1 | certificats SSH courts (M24-E20) ; clé `ansible-ci` → `KV` ; CA SSH `AMO` |
| 21 | Jetons PBS (sauvegardes de `pve01`) | plateforme | `pve01` (stockage `pbs-par2`) | vzdump | jamais *(à vérifier)* | C1 | `AMO` (la sauvegarde ne doit pas dépendre du coffre) |
| 22 | Clé `age` des instantanés etcd et des sauvegardes chiffrées | plateforme | clé publique sur les nœuds ; privée hors ligne (M14) | restauration | jamais | C1 | `AMO` hors ligne |
| 23 | Clé de chiffrement d'etcd (`EncryptionConfiguration`, `secretbox`) | plateforme | nœuds de contrôle (`/etc/kubernetes/…`), Vault `critique` | kube-apiserver | jamais *(à vérifier)* | C1 | `AMO` (aucun plugin KMS v2 pour OpenBao, ADR-0251) |
| 24 | `admin.conf` du cluster | plateforme | Vault `critique`, nœuds de contrôle | bris de glace | à l'expiration (1 an) | C1 | `AMO` |
| 25 | Clés cephx (clients CSI, Proxmox, sauvegardes) | plateforme | Vault `lab`, Secrets `ceph-csi-*` (M16) | ceph-csi, Proxmox | jamais | C1 | `KV` + ESO |
| 26 | Clés S3 des sauvegardes et de l'observabilité (Velero, CNPG, Thanos, Loki, Tempo) | plateforme | Secrets `velero-s3`, `cnpg-s3`, `thanos-objstore`, `loki-objstore`, `tempo-objstore` | composants | jamais | C2 | `KV` + ESO, rotation par E33 |
| 27 | Secrets des clients OIDC de Keycloak (`grafana`, `argocd`, `oauth2-proxy`, `gitlab`, `harbor`, `proxmox`, `pbs`, `netbox`, `step-ca`, `openbao`) | plateforme | Vault `critique` (`secrets/identite.yml`), état OpenTofu d'`identite` ; Secrets `grafana-oidc`, `argocd-oidc`, `oauth2-proxy-oidc` | les services | M24-E29 (manuelle) | C2 | `KV` (`kv/plateforme/<service>/oidc`) + ESO ; rotation planifiée (E33) |
| 28 | Mot de passe `svc-keycloak` (fédération LDAP) et `wb-checks` de l'annuaire | plateforme | `annuaire/vault-critique.yml`, CI d'`identite`, `ipa-checks.env` | Keycloak, checks | M24-E29 | C2 | `KV` |
| 29 | Secret du client `svc-tofu-keycloak` | plateforme | `keycloak-tofu.env`, CI d'`identite` | OpenTofu | à la main | C1 | `KV` (CI par `ID`) |
| 30 | Comptes d'administration locaux (Grafana `admin`, Argo CD `admin`, Harbor `admin`, Jenkins, SonarQube) | plateforme | Secrets `grafana-admin`, `argocd-secret`, Vault `lab` | bris de glace | rare | C2 | `KV` + ESO ; désactivés quand le SSO suffit (M24) |
| 31 | Jeton `ci-lecture` d'Argo CD, jeton de l'agent GitLab | plateforme | variables de CI, Secret `gitlab-agent-jeton` | CI, agent | 1 an | C2 | `KV` ; `ID` à terme |
| 32 | Mot de passe PostgreSQL de MédiAgenda (rôle applicatif CNPG) | mediagenda | Secret `mediagenda-db-app` généré par CNPG | API MédiAgenda | jamais | C1 (données de santé) | `DYN` (`db-mediagenda/`, E14) |
| 33 | Mot de passe Valkey de MédiAgenda | mediagenda | Secret de l'espace (`secrets-k8s.sh`) *(à vérifier)* | API MédiAgenda | jamais | C2 | `KV` (`kv/mediagenda/<env>/valkey`) + ESO |
| 34 | Clés S3 de MédiDoc | medidoc | Secret `medidoc-s3` | MédiDoc | jamais | C1 (documents patients) | `KV` + ESO, rotation planifiée |
| 35 | Clés privées TLS des services (certificats ACME de step-ca, cert-manager) | plateforme | chaque hôte (`/etc/<service>/tls`), Secrets TLS du cluster | services | automatique (30 j / 90 j) | C2 | inchangé (déjà courts) ; certificats internes du cluster → `PKI` (E16) |
| 36 | Comptes des checks du workbook (`keycloak-checks.env`, `ipa-checks.env`, `openbao-checks.env`, Mailpit…) | `<MOI>` | `~/.config/workbook/` (600) | `lab/bin/check` | trimestrielle (E33) | C3 | restent locaux (outil personnel) ; droits de lecture seule |
| 37 | Fichier `.env` de Lucas collé dans un ticket (le mois dernier) | mediagenda | ticket, messagerie | n'importe qui | — | C2 | **à faire tourner tout de suite** ; procédure de fuite RB-250 (E23) |

## Constats

- **Où sont les secrets C1 hors d'un coffre ?** Lignes 7, 13, 18, 29 : sur `adm01` en fichiers 600 et en variables de CI. Ce sont les premières migrations (E07, E10, E20).
- **Ce qui ne tourne jamais** : clés S3, TSIG, cephx, Cosign, mot de passe de la base de MédiAgenda. Une politique de rotation (E33) leur fixe une fréquence, l'automatisation la tient.
- **Qui lit quoi ?** Aujourd'hui, personne ne sait dire qui a lu un Secret Kubernetes ou une variable de CI : l'audit d'OpenBao (E21) le dira pour tout ce qui y entre.
- **Ce qui reste dehors (`AMO`)**, et pourquoi : ce dont le coffre a besoin pour démarrer ou être réparé (parts, Vault `critique`, racine PKI, step-ca, réseau, sauvegardes, `admin.conf`). Ces secrets sont peu nombreux, sous scellé, et leur usage est alerté.
- **Le `.env` de Lucas** (ligne 37) : un mois après, on ne sait toujours pas tout ce qu'il contenait. C'est le cas d'école du runbook RB-250.

# Extraits de documentation du socle — ajout de git01 (M01-E04)

> À intégrer dans `~/medisphere/docs/socle/` (fichiers créés au M00-E50), puis commit local.
> Aucune valeur secrète : seulement les **emplacements** des secrets.

## `inventaire.md`, section 2 « VMs du socle » — ligne à ajouter

| VM | VMID | VNet / VLAN | Adresse(s) | FQDN | vCPU / RAM | Disques (stockage) | Démarrage | Sauvegarde |
|---|---|---|---|---|---|---|---|---|
| `git01` | 1004 | `vinfra` (20) | 10.10.20.12 | git01.par1.medisphere.internal | 4 / 8 Gio fixes (sans ballooning) + swap 4 Gio | 60 Gio (`local-nvme`) | onboot, ordre 4 | quotidienne `pbs-par2` (VM) ; sauvegarde applicative GitLab en M01-E28 |

## `inventaire.md`, nouvelle section « Services »

| Service | Hôte | Version | URL / accès | Configuration | Remarques |
|---|---|---|---|---|---|
| GitLab CE | `git01` | 19.3.x (paquet `gitlab-ce` bloqué par `apt-mark hold`) | `https://git01.par1.medisphere.internal`, Git en SSH `git@git01.par1.medisphere.internal` (port 22) | `/etc/gitlab/gitlab.rb` (profil mémoire contrainte, Prometheus désactivé) | secrets d'instance : `/etc/gitlab/gitlab-secrets.json` (à sauvegarder à part, M01-E28) |

## `inventaire.md`, section 4 « Comptes, jetons et secrets » — lignes à ajouter

| Identité | Type | Droits | Où est le secret | Rotation |
|---|---|---|---|---|
| CA provisoire « MédiSphère CA provisoire » | clé privée ECDSA P-256 | signe les certificats serveur du lab jusqu'au M06 | `~/pki-provisoire/ca.key` sur `adm01` (700/600), **jamais copiée** | retrait au M06 (step-ca) ; expiration de la racine : <AAAA-MM-JJ> |
| Certificat serveur `git01` | clé privée ECDSA P-256 | TLS de GitLab | `/etc/gitlab/ssl/git01.par1.medisphere.internal.key` (600) ; copie de travail `~/pki-provisoire/git01.key` | 397 jours, expiration : <AAAA-MM-JJ> |
| `root` GitLab | compte de bris de glace | administrateur | gestionnaire de mots de passe personnel | à chaque départ ou usage |

## `matrice-flux.md` — nouvelle section « 5. Flux applicatifs du socle »

| # | Source | Destination | Proto/port | Justification | Filtrage |
|---|---|---|---|---|---|
| A1 | `adm01` (MGMT), VPN `wg1` | `git01` 10.10.20.12 | TCP/443, TCP/80 (redirection vers 443) | interface web et API de GitLab | `gw01` : F2 (MGMT) et F3 (VPN), déjà en place |
| A2 | `adm01` (MGMT), VPN `wg1` | `git01` | TCP/22 | Git en SSH (`git@`), administration (`admin@`) | `gw01` : F2, F3 |
| A3 | `git01` | Internet (`packages.gitlab.com`, miroirs Debian) | TCP/443, TCP/80 | paquets | `gw01` : F13 (NAT) |
| A4 | `git01` | `dns01` 10.10.20.10 | UDP+TCP/53 | résolution | même VLAN : pas de traversée de `gw01` |
| A5 | `git01` | `gw01` 10.10.20.1 | UDP/123 | temps | `gw01` : I4 |

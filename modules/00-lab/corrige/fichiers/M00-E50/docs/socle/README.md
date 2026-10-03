# Socle MédiSphère — v0

> Dossier d'exploitation du socle PAR1/PAR2 (exemple de corrigé M00-E50 : structure et
> contenu attendus ; les valeurs `<…>` et les dates sont à remplacer par les tiennes).

| | |
|---|---|
| Version | `socle-v0` (étiquette Git) |
| Date de livraison | AAAA-MM-JJ |
| Responsable | Équipe Plateforme — <nom> |
| Validation | Revue Claire Morel (AAAA-MM-JJ), relecture sécurité Sophie Laurent |
| État | En service — contrôle global `lab/bin/check 00 50` vert le AAAA-MM-JJ |

## Périmètre

Hyperviseur `pve01` (PAR1), routeur/pare-feu `gw01`, poste d'administration `adm01`, DNS/DHCP
provisoire `dns01`, template `tpl-debian13`, serveur de sauvegarde `pbs01` (PAR2), tunnel
inter-sites, VPN d'administration, temps synchronisé, sauvegardes chiffrées hors site.

Hors périmètre v0 (modules suivants) : `ca01`, `git01`, `nbx01`, `s3-01` (PLAN §4.5).

## Contenu

| Document | Rôle |
|---|---|
| [architecture.md](architecture.md) | schéma réseau, composants, points uniques de défaillance |
| [inventaire.md](inventaire.md) | hôtes, VMs, ressources, comptes, accès |
| [matrice-flux.md](matrice-flux.md) | flux autorisés et leur règle de filtrage |
| [capacite.md](capacite.md) | plan de capacité mémoire et disque |
| [runbooks/](runbooks/) | procédures d'exploitation (RB-001 à RB-004) |
| [adr/](adr/) | décisions d'architecture (ADR-0001 à ADR-0003) |
| [tests/restauration.md](tests/restauration.md) | preuve de restauration, RTO/RPO mesurés |
| [post-mortems/](post-mortems/) | incidents analysés |
| `journal/`, `analyses/`, `mesures/` (produits au palier 4, absents de cet exemple) | journaux de diagnostic, analyses (M00-E47), mesures disque (M00-E48) |

## Risques connus (v0)

| Risque | Impact | Traitement prévu |
|---|---|---|
| `gw01` point unique de défaillance (routage, NAT, NTP, VPN, relais DHCP) | perte de tout le lab | `gw02` + VRRP (module 07) |
| `dns01` point unique (DNS + DHCP) | perte de résolution | PowerDNS redondé, Kea (module 06) |
| `pve01` seul hyperviseur PAR1 | perte de PAR1 | PRA depuis PAR2 (final F5), cluster (module 09) |
| Documentation et configuration hors GitLab | perte du poste `adm01` | migration vers `git01` (module 01) |

## Contacts

Astreinte : Nadia Roussel (processus incident). Architecture : Claire Morel. Sécurité : Sophie Laurent.

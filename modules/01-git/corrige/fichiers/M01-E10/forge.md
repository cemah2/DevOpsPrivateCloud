# Fiche de service — forge GitLab (git01)

| | |
|---|---|
| Service | GitLab CE (paquet omnibus), version : voir `Admin > Tableau de bord` ou `/help` |
| URL | <https://git01.par1.medisphere.internal> |
| Git en SSH | `git@git01.par1.medisphere.internal:<groupe>/<projet>.git` (sshd système, port 22) |
| Hôte | `git01`, VMID 1004, 10.10.20.12 (VLAN 20 INFRA), 4 vCPU, 8 Go |
| Certificat | signé par « MédiSphère CA provisoire » (`~/pki-provisoire/` sur `adm01`, jusqu'au M06) |
| Comptes d'administration | `root` (bris de glace, coffre de l'équipe) ; administrateurs nominatifs |
| Responsable | équipe Plateforme — astreinte : Nadia Roussel |

## Accès

- Depuis `adm01` et le VPN d'administration uniquement (MGMT/VPN → INFRA, ports 22 et 443).
- Faire confiance à la CA provisoire sur un poste Linux : copier `ca.crt` dans
  `/usr/local/share/ca-certificates/medisphere-provisoire.crt` puis `update-ca-certificates`.
- Inscriptions publiques désactivées : un compte se demande à l'équipe Plateforme.

## Organisation

| Groupe | Contenu | Règles |
|---|---|---|
| `plateforme` | dépôts de la plateforme (`medisphere`, puis `outils`, `images`, `ansible`, `infra`…) | `main` protégée, fusion par MR, voir `CONTRIBUTING.md` |
| `formation` | bacs à sable des exercices (`git-labo`) | pas de protection, rien de critique |

## Exploitation

- État des services : `sudo gitlab-ctl status` sur `git01` ; santé : `/-/readiness`, `/-/liveness`
  (depuis les adresses autorisées).
- Journaux : `sudo gitlab-ctl tail` ; fichiers sous `/var/log/gitlab/`.
- Configuration : `/etc/gitlab/gitlab.rb`, appliquée par `sudo gitlab-ctl reconfigure`
  (jamais sans copie de sauvegarde du fichier).

## En cas d'indisponibilité

1. **Prévenir** : astreinte (Nadia Roussel) et canal de l'équipe ; noter l'heure de début.
2. **Diagnostiquer** : runbooks de la forge dans `docs/socle/runbooks/` (VM démarrée ? `gitlab-ctl status`,
   disque, mémoire, certificat expiré ?).
3. **Continuer à travailler** : Git est distribué. Chacun garde son clone, committe en local
   sur sa branche et pousse quand la forge revient. Aucune modification de production ne se fait
   « à la main » pendant la panne pour compenser.
4. **Sauvegardes** : sauvegarde de la VM par PBS (`lab-nuit`, pool `lab`) et sauvegarde applicative
   GitLab (M01-E28). Toute restauration passe par le runbook dédié.
5. **Clore** : message de fin d'incident, et post-mortem si la panne a duré plus d'une heure.

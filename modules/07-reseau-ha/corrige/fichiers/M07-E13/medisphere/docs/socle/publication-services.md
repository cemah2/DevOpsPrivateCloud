# Services publiés par les répartiteurs

> Source : PLAT-823 (M07-E13). Architecture : ADR-0071. Maintenance : RB-070.

## Ce qui est publié

| Nom publié | Service | Serveur | Contrôle de santé | Certificat présenté au client | Vérifié vers le serveur |
|---|---|---|---|---|---|
| `gitlab.par1.medisphere.internal` | GitLab (HTTPS) | `git01` 10.10.20.12:443 | `GET /-/readiness` (200) | `gitlab.par1…` (ACME, sur chaque répartiteur) | `git01.par1…`, racine MédiSphère |
| `netbox.par1.medisphere.internal` | NetBox | `nbx01` 10.10.20.13:443 | `GET /login/` (200) | `netbox.par1…` | `nbx01.par1…`, racine MédiSphère |
| `lb.par1.medisphere.internal` | santé des répartiteurs (`/sante`) | HAProxy lui-même | — | `lb.par1…` + nom de l'hôte | — |

Tous ces noms pointent vers la VIP **10.10.70.200** (VRRP, VRID 170). Ce qui n'est **pas** publié :
le SSH de GitLab (`git@git01.par1.medisphere.internal`, port 22, direct), l'API PowerDNS, les
interfaces d'administration (Proxmox, PBS).

## Qui y accède, par où

| Depuis | Chemin | Règle |
|---|---|---|
| Socle (VLAN 20), dont `runner01` | routé par `gw01` vers la VIP | transit INFRA → VIP:443 |
| MGMT (`adm01`) | routé par `gw01` | règle « bastion vers tout le lab » |
| VPN d'administration (`wg1`) | routé par `gw01` | transit `wg1` → VIP:443 |
| LAN maison | `https://<IP-GW01-WAN>` traduit vers la VIP (DNAT sur `gw01`) | DNAT + transit WAN → VIP:443 |

**Depuis un poste du LAN maison.** Le DNS du lab n'y est pas connu : on fait résoudre les noms
publiés vers l'adresse WAN de la passerelle, par exemple dans `/etc/hosts` du poste (ou dans le
DNS local de la box, si elle le permet) :

```
<IP-GW01-WAN>  gitlab.par1.medisphere.internal netbox.par1.medisphere.internal
```

Le poste doit aussi faire confiance à la racine « MédiSphère Root CA » (magasin du système ou du
navigateur). À partir de M07-E26, `<IP-GW01-WAN>` devient la VIP WAN `<IP-GW-WAN-VIP>`.

## Changements induits

- GitLab : `external_url` = `https://gitlab.par1.medisphere.internal` ; les liens et URL de clone
  HTTPS utilisent ce nom ; `runner01` reste enregistré sur `git01.par1…` (accès direct, inchangé) ;
  ses jobs clonent par `CI_SERVER_URL`, donc par les répartiteurs.
- NetBox : `ALLOWED_HOSTS` contient les deux noms.
- Retour arrière : rétablir `external_url 'https://git01.par1.medisphere.internal'` + reconfigure ;
  retirer le nom de `netbox_allowed_hosts` ; retirer les noms publiés (OpenTofu) ; retirer la
  redirection et les règles de `pare_feu.yml`.

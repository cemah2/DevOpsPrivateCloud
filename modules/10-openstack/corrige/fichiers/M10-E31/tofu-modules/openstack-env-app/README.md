# Module `openstack-env-app`

Environnement d'application **en libre-service** dans un projet OpenStack de MédiSphère (M10-E31) : réseau privé et routeur, groupes de sécurité, N serveurs web, volume de données sur la première instance, répartiteur Octavia (fournisseur **OVN**, TCP 80) et son IP flottante.

## Exemple

```hcl
module "recette" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//openstack-env-app?ref=v1.5.0"

  prefixe          = "agenda-recette"
  cidr             = "172.20.10.0/24"
  cle_publique_ssh = var.cle_publique_ssh
}
```

Le provider `openstack` est configuré par la configuration racine (identifiant d'application du projet, rôle `member`, variables `OS_*`).

## Variables

| Nom | Défaut | Rôle |
|---|---|---|
| `prefixe` | — | préfixe de toutes les ressources (`<prefixe>-net`, `-sn`, `-rt`, `-app`, `-admin`, `-appNN`, `-donnees`, `-lb`) |
| `cidr` | — | sous-réseau privé, /24 à /28, hors 10.10/16, 10.20/16, 10.255/16 |
| `nombre_instances` | 2 | 2 à 4 |
| `gabarit` | `m1.petit` | `m1.petit` ou `m1.moyen` |
| `image` | `debian-13` | image publique de la plateforme |
| `cle_publique_ssh` | — | paire `<prefixe>-cle` |
| `volume_taille`, `point_de_montage` | 5, `/srv/donnees` | volume XFS sur la première instance, retrouvé par numéro de série |
| `page_titre` | « MédiAgenda — recette » | page de démonstration (nom d'hôte ajouté) |
| `clients_http` | MGMT, VPN d'admin | plages autorisées sur le port 80 (adresses **clientes** : pas de SNAT avec OVN) |
| `cidr_admin` | MGMT, VPN d'admin | SSH et ICMP d'administration |
| `acces_admin` | `false` | IP flottante temporaire sur la première instance |
| `reseau_externe`, `dns`, `etiquettes` | `ext-net`, résolveurs du socle, `[]` | — |

## Sorties

`url`, `ip_flottante`, `instances` (nom → adresse privée), `acces_admin`.

## Ce que le module impose (non négociable en libre-service)

- Fournisseur **OVN** pour le répartiteur : L4 (TCP), algorithme `SOURCE_IP_PORT`, pas de TLS ni de L7 (ADR-0100).
- Aucune IP flottante sur les instances, sauf `acces_admin` temporaire.
- Port 80 ouvert aux seules `clients_http` et au sous-réseau (contrôles de santé) ; SSH aux seules `cidr_admin`.
- Anti-affinité souple entre instances ; étiquettes `libre-service` et `<prefixe>`.

## Versions

Étiquettes du dépôt `plateforme/tofu-modules` (semantic-release). Provider `terraform-provider-openstack/openstack` `~> 3.4`, OpenTofu ≥ 1.13.

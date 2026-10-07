# Module `enregistrement-dns`

A et PTR d'un nom dans PowerDNS (fournisseur `mmianl/powerdns` `~> 2.5.0`), M06-E14.
Disponible à partir de l'étiquette `v2.1.0` du dépôt `plateforme/tofu-modules`.

**Pourquoi un module à part ?** On nomme aussi ce qui n'est pas une VM (adresse virtuelle, service) ;
`vm-debian` n'impose pas un fournisseur de plus à ses appelants ; chacun évolue à son rythme.

**Propriété.** Chaque *rrset* porte le commentaire `gere-par=opentofu (plateforme/infra)` : la
génération NetBox → PowerDNS (M06-E15) n'y touche pas, et un humain sait qui le gère.

```hcl
module "dns_ipam01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  nom    = module.ipam01.fqdn    # sans point final
  ipv4   = module.ipam01.ipv4
}
```

| Entrée | Défaut | Rôle |
|---|---|---|
| `nom` | — | nom complet, sans point final |
| `ipv4` | — | adresse, sans masque |
| `zone` | `par1.medisphere.internal.` | zone directe |
| `ttl` | 300 | TTL des deux enregistrements |
| `ptr` | `true` | créer le PTR (faux pour un second nom sur la même adresse) |

Zones inverses gérées : `10.10.in-addr.arpa.` et `20.10.in-addr.arpa.` (bloc `check`).
Sorties : `fqdn` (avec point final), `nom_ptr`.

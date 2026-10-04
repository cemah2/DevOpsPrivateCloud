# Inventaire de l'atelier conflits (M01-E13)

| Hôte | VMID | Adresse | vCPU | RAM | Rôle |
|---|---|---|---|---|---|
| gw01 | 1000 | 10.10.10.1 | 2 | 2 Go | Routeur, pare-feu, NAT |
| adm01 | 1001 | 10.10.10.10 | 2 | 4 Go | Poste d'administration |
| dns01 | 1002 | 10.10.20.10 | 1 | 2 Go | DNS et DHCP (dnsmasq, provisoire jusqu'au M06) |
| git01 | 1004 | 10.10.20.12 | 4 | 8 Go | GitLab CE |
| runner01 | 1007 | 10.10.20.15 | 2 | 4 Go | GitLab Runner (exécuteur shell) |

Source de vérité provisoire : ce fichier sera remplacé par NetBox au module 06.

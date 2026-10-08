# plateforme/provisioning

Chaîne de provisioning bare-metal de MédiSphère (module 11) : ce qu'un serveur trouve quand il
démarre sur le VLAN 60.

| Dossier | Contenu | Publié sur pxe01 |
|---|---|---|
| `ipxe/` | `boot.ipxe` (point d'entrée), `menu.ipxe` | `/srv/http/boot.ipxe`, `/srv/http/ipxe/` |
| `preseed/` | fichiers de réponses de debian-installer | `/srv/http/preseed/` |
| `kickstart/` | kickstarts d'Anaconda (Rocky Linux) | `/srv/http/kickstart/` |
| `gabarits/` | gabarits Jinja2 rendus depuis NetBox (M11-E06) | (par le rendu) |
| `outils/` | `publier.sh`, `verifier.sh`, `netbox-provision.py`, `alim.sh`, `redfish.sh` | non |
| `rendu/` | fichiers produits par `netbox-provision.py` — **non versionnés** | via `publier.sh` |

Le reste de `pxe01` (TFTP, nginx, installateurs vérifiés, racine de la PKI) appartient au rôle
Ansible `pxe` de `plateforme/ansible`.

Avant une MR : `outils/verifier.sh`. Publier : `outils/publier.sh --simulation`, puis `outils/publier.sh`.
Procédure d'exploitation : RB-110.

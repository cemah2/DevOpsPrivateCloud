# envs/m07-maquette — maquette réseau du module 07

Dix VMs jetables (VMID 2070-2079, étiquette `env-m07`) pour pratiquer l'agrégation de liens,
Open vSwitch, OSPF, BGP, VRRP, HAProxy et le raccordement du site de Lyon sans toucher au socle.
Description complète : `maquette.tf` (une entrée par VM). Adresses : introduction du module 07.

## Prérequis (une fois)

- VNets `vfab1` à `vfab8` (zone `lab`, VLAN 901-908) et droits `PVESDNUser` de `wb-tofu` :
  `outils/m07-vnets.sh creer`, **en root sur pve01** (le jeton d'OpenTofu n'administre pas le SDN).
- `terraform.tfvars` (copie de `terraform.tfvars.exemple`).

## Construire / reconstruire (depuis adm01)

```
admin@adm01:~/src/infra/envs/m07-maquette$ . ../../outils/charger-acces.sh
admin@adm01:~/src/infra/envs/m07-maquette$ set -a; . ~/.config/workbook/netbox-tofu.env; . ~/.config/workbook/powerdns-api.env; set +a
admin@adm01:~/src/infra/envs/m07-maquette$ tofu init && tofu plan -out plan.bin && tofu apply plan.bin
admin@adm01:~$ rm -f ~/.ssh/known_hosts.m07          # nouvelles VMs = nouvelles clés d'hôte
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/proxmox.yml playbooks/m07-maquette.yml
```

Puis, selon l'avancement : `playbooks/m07-net01.yml`, `m07-fabric.yml`, `m07-web.yml`.
Durée mesurée d'une reconstruction complète (destroy + apply + playbook) : **à noter ici** (environ
10 à 15 minutes sur le lab de référence).

## Choix

- **Pas de VM NetBox créée par cet état.** Les VMs de la maquette vivent quelques jours : la
  synchronisation Proxmox → NetBox (M06-E11) les fait apparaître et disparaître avec la réalité.
  Seules les **adresses fixes** prises dans le VLAN 99 (10.10.99.250-.253) et la VIP de démonstration
  (10.10.99.240) sont réservées dans NetBox par cet état, pour qu'aucune allocation ne les reprenne.
- **Noms** : A + PTR des adresses fixes par le module `enregistrement-dns` ; les VMs en DHCP sont
  nommées par Kea (DNS dynamique, M06-E17).
- **Adresses de fabric par cloud-init** (`ipconfig1`…) : elles existent dès le démarrage, avant
  tout routage ; FRR ne gère que les boucles (`lo`) et le routage.
- **Appliqué depuis adm01**, jamais par le pipeline du socle : ce n'est pas de la production.

## Détruire

```
admin@adm01:~/src/infra/envs/m07-maquette$ tofu destroy      # relire la liste : 2070-2079 SEULEMENT
admin@adm01:~$ rm -f ~/.ssh/known_hosts.m07
```

Les VNets restent (ils ne coûtent rien) ; `outils/m07-vnets.sh supprimer` les retire si besoin.

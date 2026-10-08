# Rôle `pve_noeud`

Configuration de base d'un nœud Proxmox VE 9.2 du cluster imbriqué `hv-par1` (module 09).

## Ce que fait le rôle

| Étape | Fichier | Détail |
|---|---|---|
| Contrôles d'entrée | `tasks/controles.yml` | numéro ↔ nom, `pve-manager/9.2`, nom résolu vers l'adresse MGMT, MAC des cartes `nic0`..`nic4`, `/dev/kvm` présent |
| Dépôts | `tasks/depots.yml` | retire toute source vers `enterprise.proxmox.com`, déclare `pve-no-subscription` (deb822), paquets d'exploitation |
| DNS et temps | `tasks/temps.yml` | résolveurs par l'API locale (`pvesh set /nodes/<nœud>/dns`), chrony vers la passerelle de MGMT, attente de synchronisation |
| Réseau | `tasks/reseau.yml` | `/etc/network/interfaces` complet (vmbr0, Corosync, Ceph en MTU 9000, vmbr1 VLAN-aware), syntaxe vérifiée, retour automatique armé avant `ifreload -a` |
| Système | `tasks/systeme.yml` | ARC de ZFS plafonné à 1 Gio, getty sur `ttyS0`, SSH root par clé seulement, fragment cloud-init `medisphere-agent.yaml` |

Il ne crée pas le cluster et ne touche ni à Corosync, ni à Ceph, ni au stockage.

## Variables

Voir `defaults/main.yml` et `meta/argument_specs.yml`. Seule `pve_noeud_numero` est obligatoire (inventaire `inventories/lab/hv.yml`).

## Tests

Pas de scénario Molecule : une instance de test serait elle-même un nœud Proxmox VE imbriqué (12 Go, ISO préparée), ce que le module construit déjà. Le rôle est testé par :

- `ansible-lint` (profil `production`) dans le pipeline ;
- `--check --diff` sur un nœud avant chaque application ;
- second passage `changed=0` ;
- la reconstruction complète du cluster depuis le code (mini-projet M09-E46).

## Règles

- Le réseau des nœuds ne se modifie **pas** par l'interface web : ce rôle possède `/etc/network/interfaces`.
- Ne jamais gérer `/root/.ssh/authorized_keys` d'un nœud en cluster avec un module qui remplace le fichier : c'est un lien vers `/etc/pve/priv/authorized_keys`, partagé par tout le cluster.

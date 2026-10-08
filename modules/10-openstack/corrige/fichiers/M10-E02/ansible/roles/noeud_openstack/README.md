# Rôle `noeud_openstack`

Prépare un nœud OpenStack (`osctl01`, `oscmp01`, `oscmp02`) pour Kolla-Ansible (M10-E02, PLAT-1102).

## Ce qu'il fait

1. Calcule le **suffixe** du nœud (dernier octet de `ansible_host`, adresse OS-API) et en déduit, par la règle de l'état OpenTofu `envs/openstack` (`noeuds.tf`), les MAC et les adresses : aucune table recopiée.
2. Vérifie que chaque MAC attendue existe, **avant** de toucher à quoi que ce soit.
3. Retire le réseau à cloud-init (`/etc/cloud/cloud.cfg.d/99-openstack-reseau.cfg`), écrit `/etc/netplan/60-openstack.yaml` (validé d'abord par `netplan generate --root-dir` dans un dossier de répétition), supprime `50-cloud-init.yaml`, puis **redémarre** le nœud (gestionnaire, une fois).
4. Vérifie après redémarrage : `ens18`-`ens20` (MAC, MTU, adresse), `ens21` montée sans adresse sur les nœuds du groupe réseau, `ping -M do -s 8972` sur les VLAN 51 et 30, `/dev/kvm` sur les calculs, horloge synchronisée.

Il ne pose **ni Docker, ni paquet OpenStack** : `kolla-ansible bootstrap-servers` s'en charge.

## Pourquoi pas de scénario Molecule

Les instances Molecule du projet (M04-E24) ont **une** carte sur `vsandbox`, en DHCP. Le cœur du rôle — reconnaître quatre cartes par leur MAC sur quatre VLAN, dont deux en MTU 9000, et vérifier des pings de 9000 octets vers des pairs et vers Ceph — n'y a aucun sens : le test passerait à vide ou échouerait toujours. Ce qui teste le rôle :
- l'assertion de départ (MAC présentes) et la validation `netplan generate` avant toute mise en place ;
- ses propres vérifications après redémarrage (un nœud mal câblé fait échouer le playbook) ;
- `lab/bin/check 10 02` ;
- `ansible-lint` (profil `production`) dans le pipeline.

Un scénario à quatre cartes demanderait des instances Molecule dédiées sur les VNets d'OpenStack : à envisager si le rôle grossit.

## Retour arrière

Depuis la console (`qm terminal <VMID>` sur `pve01`) : supprimer `/etc/netplan/60-openstack.yaml` et `/etc/cloud/cloud.cfg.d/99-openstack-reseau.cfg`, `cloud-init clean --configs network`, redémarrer. Ou revenir à l'instantané `avant-reseau`.

## Variables

Voir `defaults/main.yml` et `meta/argument_specs.yml`. `noeud_openstack_redemarrage_autorise: false` fait échouer le rôle au lieu de redémarrer (nœud qui porte déjà des instances).

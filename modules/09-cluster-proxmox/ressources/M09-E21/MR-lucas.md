# MR !214 — « Cluster de recette : configuration de référence » (Lucas Martin)

> Projet `plateforme/medisphere`, branche `lucas/cluster-recette`, dossier `docs/virtualisation/reference/`.
> Relecteurs demandés : Karim Benali, toi.

Bonjour,

Pour le futur cluster de **recette** (même architecture que `hv-par1` : trois nœuds `hv01-03`, Ceph, PBS à PAR2), j'ai préparé les fichiers de configuration « de référence » que l'équipe copiera sur les nœuds après l'installation. Je les ai validés sur trois VMs de ma sandbox : le cluster se forme, `pvecm status` est vert, les VMs démarrent, la HA les relance.

Ce que j'ai voulu faire :

- **Corosync** : deux liens pour la redondance. J'ai mis le lien 0 sur le réseau de stockage, parce que c'est le plus rapide (MTU 9000), et le lien 1 sur le nom des nœuds, comme ça si on change une adresse il suffit de mettre le DNS à jour. J'ai désactivé le chiffrement de Corosync : le VLAN est privé et ça économise du CPU. `two_node` parce qu'au début on n'aura que deux nœuds, ça évite d'oublier de le mettre. `hv03` a deux voix : c'est le plus gros serveur, il doit peser plus.
- **HA** : `vm:100` (base de données) reste sur `hv01`, le seul qui a des disques NVMe. Les quatre frontaux web (`vm:101` à `vm:104`) sont tous séparés les uns des autres. `vm:103` préfère `hv02` pour des raisons de licence.
- **Stockage** : `local-lvm` marqué partagé, sinon la migration à chaud refuse de déplacer les VMs ; le Ceph de PAR1 avec le compte `admin` (c'est celui qui marche du premier coup) ; PBS avec `root@pam` pour ne pas avoir à gérer un compte de plus.

Fichiers : `corosync.conf`, `ha-resources.cfg` (= `/etc/pve/ha/resources.cfg`), `ha-rules.cfg` (= `/etc/pve/ha/rules.cfg`), `storage.cfg`.
Les mots de passe et empreintes qui y figurent sont **fictifs**.

Merci pour la relecture !
Lucas

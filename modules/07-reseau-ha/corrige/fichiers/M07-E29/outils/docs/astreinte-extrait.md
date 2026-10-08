## ms-verif-reseau (bordure et répartiteurs, M07-E29)

| Ligne `KO` | Signification | Premier geste | Runbook |
|---|---|---|---|
| `acces … état illisible` | la sonde ne joint pas l'hôte ou `etat-reseau` échoue | `ssh -i ~/.config/workbook/ssh-supervision-reseau supervision@<hôte>` ; console Proxmox si l'hôte ne répond plus | RB-072 |
| `vrrp … keepalived actif=false` ou `état FAULT` | plus de redondance (passerelle de secours arrêtée, lien suivi tombé) | `journalctl -u keepalived` sur l'hôte ; `ip -br link` | RB-071 §4 |
| `vrrp … portée par 2 hôtes` | cerveau divisé : annonces VRRP perdues | **arrêter keepalived sur la passerelle qui ne doit pas être maître**, puis diagnostiquer (`tcpdump … ip proto 112`) | RB-071 §4 |
| `vrrp … portée par AUCUN hôte` | un réseau sans passerelle | `journalctl -u keepalived` des deux côtés ; démarrer keepalived sur la passerelle saine | RB-071 §4 |
| `vrrp … groupe de synchronisation rompu` | VIP réparties : routage asymétrique en cours | vérifier `keepalived.conf` (groupe `BORDURE`) des deux côtés ; RB-071 pour regrouper | RB-071 |
| `vrrp-dmz …` | répartiteurs : 0 ou 2 porteurs de 10.10.70.200 | `systemctl status haproxy keepalived` sur `lb01`/`lb02` | RB-070 |
| `bgp … session … Active/Connect/absente` | voisin injoignable ou refusé | `vtysh -c 'show bgp neighbors <voisin>'` ; tunnel `wg2` pour Lyon | RB-072, runbooks du palier 4 |
| `wireguard … poignée de main` | tunnel muet (pair arrêté, extrémité, traduction) | `wg show` sur le maître ; côté pair (`pbs01`, `lyo-gw01`) | RB-072 |
| `conntrackd …` | synchronisation des connexions arrêtée : la prochaine bascule coupera les connexions | `systemctl status conntrackd` ; `conntrackd -s` | RB-071 §1 |
| `haproxy … DOWN` / `MAINT` | serveur en échec de contrôle de santé ou laissé en maintenance | page `/stats` ; `curl` du chemin de santé depuis le répartiteur | RB-070 |
| `publie … répond 000/503` | service publié injoignable de bout en bout | DNS du nom publié, VIP, `haproxy` ; le serveur lui-même | RB-070, RB-072 |

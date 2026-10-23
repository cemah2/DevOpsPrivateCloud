# Journal de diagnostic — INC-5235 « le coffre répond mal depuis la maintenance » (Nadia Roussel)

> Modèle de journal (M25-E35, variante 1 jouée, nœud touché : `vault03`). Une ligne par geste : heure,
> hypothèse, commande (sans secret), résultat, conclusion. Aucun jeton, aucune clé privée, aucun
> contenu de `kms.env`.

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 09:02 | — | alerte `OpenBaoScelle` (Alertmanager) | `vault03`, depuis 04:47 | heure de la maintenance de Lucas |
| 09:04 | le coffre est fermé | `curl … openbao.par1…:8200/v1/sys/health \| jq '{sealed, standby}'` | `false`, `false` | le service répond ; l'incident touche **un** nœud |
| 09:05 | lequel, comment | boucle `curl -w '%{http_code} %{errormsg}'` sur les trois noms | `vault01 429`, `vault02 200`, `vault03 000 Failed to connect … Connection refused` | refus de connexion : rien n'écoute sur l'adresse réseau de `vault03` |
| 09:07 | `vault03` scellé | `curl --resolve vault03…:8200:127.0.0.1 …/v1/sys/seal-status` sur `vault03` | `"sealed": false`, `"type": "transit"` | **pas scellé** : le titre de l'alerte est trompeur |
| 09:08 | processus arrêté | `systemctl status openbao` | `active (running)` depuis 04:46 | redémarré pendant la maintenance |
| 09:09 | écoute | `sudo ss -ltnp 'sport = :8200'` | `127.0.0.1:8200` seulement | l'écouteur ne sert que la boucle locale |
| 09:10 | Raft | `bao operator raft list-peers` | trois voters, `vault03` suiveur | la grappe le croit sain (8201) |
| 09:12 | écart avec Git | `ansible-playbook playbooks/coffre.yml --limit vault03 --check --diff` | `-  address = "127.0.0.1:8200"` / `+  address = "0.0.0.0:8200"` | modification à la main, hors pipeline |
| 09:14 | risque de bascule | lecture de `chk_openbao_actif` | vérifie par `--resolve …:127.0.0.1` | si `vault03` devient actif, il prend la VIP sans la servir : **tout** tombe |
| 09:16 | — | pas de step-down ni de redémarrage de l'actif ; Lucas prévenu (reporter son redémarrage) | — | — |
| 09:20 | — | `ansible-playbook playbooks/coffre.yml --limit vault03 -e openbao_redemarrer=true` | `changed` sur `openbao.hcl`, redémarrage, descellé seul | — |
| 09:22 | — | boucle `curl` sur les trois noms, `lab/bin/check 25 35` | `429`, `200`, `429` | réparé |

**Cause** : `address` de l'écouteur de `vault03` passée à `127.0.0.1:8200` pendant la maintenance,
prise en compte au redémarrage du nœud. Raft (8201) et le descellement ne dépendent pas de l'écouteur
API : le nœud est resté membre sain de la grappe, invisible de tous ses clients.
**Correctif** : rôle `openbao` réappliqué sur le seul `vault03`, redémarrage autorisé.
**Prévention** : le job `derive` de `plateforme/ansible` couvre `coffre.yml` (cet écart y apparaît en
`changed`) ; surcharges systemd non déclarées retirées par le rôle ; certificat à réémettre compté comme
un changement en `--check` ; `OpenBaoScelle` scindée (`OpenBaoInjoignable` pour `up == 0`) ;
modifications des nœuds du coffre par MR seulement, relues par un second membre de `plateforme-admins`.

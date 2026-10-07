# RB-062 — DHCP : exploiter la paire Kea en haute disponibilité

| | |
|---|---|
| Service | DHCPv4 du VLAN 99 (SANDBOX) : Kea 3.0 sur `dns01` (primary) et `dns02` (standby), mode `hot-standby` |
| Rédigé | M06-E25 (PLAT-751) — testé le AAAA-MM-JJ |
| Délai de bascule mesuré | __ s (arrêt de Kea sur `dns01` → `dns02` en `partner-down`) |
| Liens | RB-060 (ajouter un hôte), RB-063 (certificats), `group_vars/role_dns/kea.yml`, M06-E29 (supervision) |

## 1. Lire l'état de la paire

Depuis `adm01` (compte `supervision`, lecture de l'état ; compte `kea-api` pour agir, mot de passe dans Vault, `vault_kea_api_mot_de_passe`) :

```
admin@adm01:~$ set -a; . ~/.config/workbook/kea-supervision.env; set +a
admin@adm01:~$ kea() { curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
                 -u "$KEA_API_USER:$KEA_API_PASSWORD" -H 'Content-Type: application/json' \
                 -d "{\"command\": \"$2\"}" "https://$1:8004/"; }
admin@adm01:~$ for s in 10.10.20.10 10.10.20.16; do kea $s status-get | jq -c '.[0].arguments["high-availability"][0]["ha-servers"] | {local: .local.state, role: .local.role, pair: .remote["last-state"], contact: .remote["in-touch"], decalage: .remote["clock-skew"]}'; done
```

| Ce que tu vois | Signification | Action |
|---|---|---|
| les deux en `hot-standby`, `contact: true` | état normal : `dns01` répond, `dns02` reçoit chaque bail | aucune |
| `dns02` en `partner-down` | `dns02` sert seul : `dns01` (ou son Kea) ne répond plus depuis `max-response-delay` (60 s) | §3 |
| `waiting`, `syncing` | un serveur redémarre et récupère les baux du pair | attendre (quelques secondes à minutes) |
| `partner-in-maintenance` / `in-maintenance` | maintenance contrôlée en cours | §2 |
| `terminated` | la paire a cessé de coopérer (écart d'horloge > 60 s, ou trop de mises à jour rejetées) | §4 |
| `communication-recovery` | **n'existe qu'en `load-balancing`** : si tu le vois, la configuration a changé de mode | vérifier `group_vars/role_dns/kea.yml` |

## 2. Maintenance planifiée d'un nœud (mise à jour, redémarrage)

Toujours un nœud à la fois, l'autre en état normal.

1. Annonce (canal de l'équipe) : « maintenance DHCP sur `<NŒUD>`, pas d'impact attendu ».
2. Envoie `ha-maintenance-start` **au nœud qui reste** (compte `kea-api` ; le mot de passe est lu sans écho, jamais tapé sur la ligne de commande) : il passe en `partner-in-maintenance` et sert seul ; le nœud à arrêter passe en `in-maintenance`.
   ```
   admin@adm01:~$ KEA_API_USER=kea-api; read -rsp 'Mot de passe kea-api : ' KEA_API_PASSWORD; echo
   admin@adm01:~$ kea <IP-NŒUD-QUI-RESTE> ha-maintenance-start
   admin@adm01:~$ set -a; . ~/.config/workbook/kea-supervision.env; set +a     # retour au compte de lecture
   ```
3. Intervention sur le nœud (`apt full-upgrade`, redémarrage…). Pendant ce temps, le nœud restant ne peut pas transmettre les baux : il les mémorise.
4. Au redémarrage, le nœud repasse par `waiting` → `syncing` → `ready` → `hot-standby`. Si le nœud restant reste en `partner-in-maintenance`, envoie-lui `ha-maintenance-cancel`.
5. Vérifie §1 sur les deux nœuds, puis un bail réel (VM sandbox : `sudo dhclient -r && sudo dhclient -v` ou `networkctl renew`).

Différence avec une panne : en maintenance, la bascule est **immédiate** (pas d'attente de `max-response-delay`) et sans demandes perdues.

## 3. Panne d'un nœud

- `dns01` tombe : après 60 s sans réponse aux battements (`max-response-delay`, `max-unacked-clients: 0`), `dns02` passe en `partner-down` et répond à tous les clients ; les mises à jour DNS dynamiques partent de son `kea-dhcp-ddns` vers `dns01:5300`… qui est peut-être lui aussi tombé (même machine) : les noms `sbxNN` ne sont alors plus mis à jour, les baux fonctionnent. Les mises à jour perdues sont refaites au renouvellement suivant.
- `dns02` tombe : `dns01` passe en `partner-down` et continue seul (aucun effet visible).
- Retour : le nœud revenu se synchronise **seul** (`syncing`), puis la paire revient en `hot-standby`. Rien à faire, sauf vérifier §1.
- Si un nœud doit rester arrêté longtemps, rien d'autre à faire : le survivant sert seul indéfiniment.

## 4. Les deux nœuds se croient seuls, ou `terminated`

1. Horloges : `chronyc tracking` sur les deux (écart > 60 s = `terminated`). Corriger le temps (M06-E21), puis redémarrer Kea sur le **standby**.
2. Réseau entre pairs : depuis `dns01`, `curl -sk https://10.10.20.16:8001/` doit répondre (même une erreur TLS de certificat client manquant prouve que le port est joignable). Filtrage local (M06-E30) : 8001 entre 10.10.20.10 et 10.10.20.16.
3. Certificats : `step certificate inspect /etc/kea/tls/kea.crt --short` sur les deux (expiré ? émetteur ? SAN avec l'adresse IP ?). Voir §5.
4. Un nœud en `partner-down` pendant que l'autre sert aussi (lien coupé, les deux vivants) : en `hot-standby` le standby ne répond qu'en `partner-down`. Si le relais joint les deux, deux serveurs peuvent répondre au même client ; les baux du standby sont pris dans la **même** plage. À la reconnexion, les serveurs se synchronisent ; les conflits éventuels sont rejetés (`max-rejected-lease-updates`). Pour limiter le risque : rétablir le lien vite, ou arrêter Kea sur le standby tant que le lien est coupé.

## 5. Certificats TLS de Kea

- Fichiers : `/etc/kea/tls/kea.crt` et `kea.key` (groupe de l'utilisateur du service, 0640).
- Renouvellement automatique : `systemctl list-timers 'cert-renewer@kea*'` (rôle `certificats_acme`, entrée `kea` de `host_vars/dns0X/certificats.yml`) ; seuil 15 jours avant l'expiration (`certificats_acme_seuil`, M06-E27).
- Renouvellement forcé, **un nœud à la fois** : `sudo systemctl start cert-renewer@kea.service` ne fait rien tant que le seuil n'est pas atteint (c'est voulu). Pour forcer : `sudo env STEPPATH=/etc/step step ca renew --force /etc/kea/tls/kea.crt /etc/kea/tls/kea.key`, puis remets les droits comme le fait l'unité (`sudo chown root:_kea /etc/kea/tls/kea.crt /etc/kea/tls/kea.key && sudo chmod 0640 /etc/kea/tls/kea.key`) et `sudo systemctl try-restart isc-kea-dhcp4-server`.
- Certificat expiré : le renouvellement par mTLS est refusé. Supprimer `kea.crt`/`kea.key` et relancer le pipeline (`--tags kea --limit <nœud>`) : le rôle refait une émission ACME.

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création (M06-E25), tests de bascule et de maintenance |

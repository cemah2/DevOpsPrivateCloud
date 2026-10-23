# RB-291 — Sonde Goss rouge

| | |
|---|---|
| Déclencheurs | Alertes `TestsGossEnEchec` et `SondeGossMuette` du Prometheus témoin (`mon01`), avertissement |
| Durée | 10 à 30 min |
| Références | `plateforme/ansible` : rôle `goss`, `tests/infra/` (Testinfra) ; comparaison `docs/qualite/testinfra-goss.md` |

Goss ne **répare** rien : il dit qu'un hôte n'est plus dans l'état promis par les rôles. La réparation passe par le rôle concerné (pipeline `appliquer` de `plateforme/ansible`), jamais par une modification à la main.

## 1. `TestsGossEnEchec` : goss serve répond 503

```
admin@adm01:~$ curl -s http://<HÔTE>.par1.medisphere.internal:8099/healthz | jq -r '.results[] | select(.successful == false) | "\(.["resource-type"]) \(.["resource-id"]) \(.property) : \(.["summary-line"])"'
```

| Test en échec | Rôle | Vérifier | Réparer |
|---|---|---|---|
| `Service node_exporter`, `Port tcp:9100`, `HTTP …:9100/metrics` | `node_exporter` | `systemctl status node_exporter`, `journalctl -u node_exporter -n 50` ; certificat (`cert-renewer@node-exporter`) | rejouer le rôle (`LIMITE=<hôte>`) |
| `Service alloy`, `HTTP 127.0.0.1:12345/-/ready` | `alloy` | `journalctl -u alloy -n 50` ; `alloy validate /etc/alloy/config.alloy` | rejouer le rôle |
| `File /etc/chrony/chrony.conf`, `Command chrony-synchronise` | `base` (temps) | `chronyc -n sources`, `chronyc -N authdata` ; les passerelles répondent-elles en NTP ? | rejouer `base` ; si les passerelles sont en cause : `chrony_serveur` |
| `Kernel-param`, `Mount /tmp` | `durcissement` | `sysctl …`, `findmnt /tmp` ; exception déclarée ? | rejouer le rôle ; une exception se déclare (RB-261), elle ne se pose pas à la main |

Puis : `curl -s -o /dev/null -w '%{http_code}\n' http://<HÔTE>…:8099/healthz` → `200` (le résultat est gardé 30 s en cache par goss serve). L'alerte se lève après la sonde suivante.

## 2. `SondeGossMuette` : aucune réponse HTTP

1. La VM est-elle allumée et joignable ? (`ping`, sondes `icmp` de `mon01`, NetBox).
2. Le service : `systemctl status goss-serve` ; `journalctl -u goss-serve -n 30` (fichier de tests illisible après une modification ? `goss --gossfile /etc/goss/goss.yaml render`).
3. Le pare-feu local : la règle 8099 depuis `mon01` (10.10.20.19) est-elle dans `host_vars/<hôte>/pare_feu_local.yml` ? `sudo nft list ruleset | grep 8099`.

## 3. Fin de l'essai

Si Goss n'est pas retenu (décision de M29-E07) : `playbooks/goss-retrait.yml`, puis retrait du groupe `goss` des sondes de `mon01`, de la règle 8099 du pare-feu local et des règles `goss.yml` du témoin.

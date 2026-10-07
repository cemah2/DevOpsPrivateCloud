## Alerte « ÉCHEC ms-verif-services.service » (sonde des services socle, M06-E29)

La sonde passe toutes les 15 minutes. L'alerte contient les lignes `KO` : traite-les **dans cet ordre** (le DNS d'abord, tout en dépend).

| Ligne KO | Vérifier en premier | Runbook |
|---|---|---|
| `dns … ne résout pas git01…` sur **un** récurseur | `systemctl status pdns-recursor` sur l'hôte ; l'autre résout-il ? (les clients basculent après leur délai) | RB du DNS (M06-E08) |
| `dns … ne résout pas deb.debian.org` | sortie Internet de `dns01`/`dns02` (`pare_feu.yml`, ligne « récurseurs vers Internet ») | — |
| `dns … pas de NXDOMAIN` | récurseur qui relaie mal les zones internes (`forward_zones`), serveur faisant autorité arrêté | RB du DNS |
| `replication … numéros de série différents` | journaux de `pdns` sur `dns02` (AXFR refusé ? clé TSIG ?) ; `pdns_control retrieve <ZONE>` sur `dns02` | M06-E24 |
| `dnssec … ne valide pas` | **urgent** : la zone est en SERVFAIL. Ancre de confiance (`rec_control get-tas`) contre clé publiée (`pdnsutil zone export-ds`), horloges | RB-064 |
| `dhcp … état partner-down` | le pair est-il arrêté ? (`status-get` sur les deux) | RB-062 §3 |
| `dhcp … adresse(s) libre(s)` | VMs sandbox oubliées (`qm list`), baux trop longs | — |
| `dhcp … identité … illisible` / `socket injoignable` | `~/.config/workbook/kea-supervision.env` (600), filtrage local (8004 depuis `adm01`) | M06-E30 |
| `netbox …` | `systemctl status netbox nginx postgresql` sur `nbx01` | RB-061 §4 si données perdues |
| `pki … health` | `systemctl status step-ca` et `journalctl -u step-ca` sur `ca01` (un `ca.json` invalide l'empêche de démarrer) | RB-063 |
| `certificat … expire dans moins de 10 jours` | le renouvellement automatique a échoué : `systemctl status 'cert-renewer@*'` sur l'hôte, `journalctl -u cert-renewer@<SERVICE>` | RB-063 §4 |
| `certificat … chaîne non reconnue ou nom incorrect` | certificat remplacé à la main ? émis par la CA provisoire (retirée) ? | RB-063 |

Après réparation : `sudo systemctl start ms-verif-services.service` et `journalctl -u ms-verif-services -n 40` pour confirmer le retour au vert.

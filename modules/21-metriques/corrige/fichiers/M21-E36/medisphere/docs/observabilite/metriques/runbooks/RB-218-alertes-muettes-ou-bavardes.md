# RB-218 — Les alertes sont muettes ou bavardes

| | |
|---|---|
| **Alertes liées** | `AlertmanagerCourrielEnEchec` (relayée par le témoin : `ClusterNePrevientPlus`), `AlertmanagerFailedToSendAlerts`, `TemoinNotificationsEnEchec`, toute alerte qui sonne trop |
| **Gravité** | critique : si les alertes ne partent plus, plus rien ne prévient l'astreinte |
| **Propriétaire** | Équipe Plateforme (astreinte : Nadia Roussel) |
| **Dernière revue** | 2026-10-27 (pannes M21-E36, E40, E42) |

```
A=http://alertmanager.apps.par1.medisphere.internal:9093     # Alertmanager du cluster
P=http://prometheus.apps.par1.medisphere.internal:9090       # vue globale
amtool() { command amtool --alertmanager.url=$A "$@"; }
```

## L'alerte n'arrive pas

Prouve chaque maillon **dans l'ordre**, sans rien modifier :

| # | Maillon | Preuve | Si KO |
|---|---|---|---|
| 1 | La règle est `firing` | `curl -s $P/api/v1/alerts \| jq '.data.alerts[] \| select(.labels.alertname=="X") \| .state'` | `pending` : attendre `for` ; absente : RB-217 « règle » |
| 2 | Alertmanager la connaît | `curl -s "$A/api/v2/alerts" -G --data-urlencode 'filter=alertname="X"'` | Prometheus n'envoie pas : `prometheus_notifications_errors_total`, `alertmanagers` de `/api/v1/alertmanagers` |
| 3 | Pas éteinte | même réponse : `.status.state`, `.status.silencedBy`, `.status.inhibitedBy` | silence : `amtool silence query` ; inhibition : règle `inhibit_rules` dont la source est active |
| 4 | Bon récepteur | `.receivers[].name` ; `amtool config routes test --config.file=<(curl -s $A/api/v2/status \| jq -r .config.original) <étiquettes>` | route : matchers, ordre, `continue` |
| 5 | Envoi réussi | `sum by (integration, reason) (increase(alertmanager_notifications_failed_total[15m]))` ; `kubectl -n supervision logs alertmanager-kps-0 -c alertmanager \| grep -i notify` | SMTP : smarthost, STARTTLS, racine, authentification |
| 6 | Bonne boîte | Mailpit, recherche `to:<adresse> <alertname>` | `email_configs[].to` |

Règles de l'équipe :
- toujours la configuration **chargée** (`/api/v2/status`), jamais celle de ton clone ;
- **silences** : matchers précis (`alertname` + `instance` ou `namespace`, jamais une équipe ou une gravité entière), durée = fenêtre du changement + 1 h, commentaire avec le ticket `CHG-`/`INC-`, auteur nominatif ; les maintenances récurrentes passent par `time_intervals`, pas par des silences ; tout silence de plus de 24 h est revu au point quotidien ;
- une **inhibition** n'éteint jamais une alerte plus grave que sa source ; elle a toujours un `equal` qui désigne **le même problème** ; elle est couverte par `alertmanager/inhibitions-tests.txt` ;
- quand le courriel est cassé, l'alerte `AlertmanagerCourrielEnEchec` arrive par le **témoin** (`ClusterNePrevientPlus`) : consulter Alertmanager du cluster directement et prévenir l'équipe par téléphone.

## Trop de courriels

| Profil | Comment le reconnaître | Réglage en cause | Valeurs MédiSphère |
|---|---|---|---|
| Battement | `changes(ALERTS{alertname="X",alertstate="firing"}[1h])` élevé ; `[FIRING]`/`[RESOLVED]` en alternance | `for` absent ou trop court, pas de `keep_firing_for`, seuil au milieu du bruit | `for` ≥ 5 min pour un symptôme ; `keep_firing_for` 10 min si la grandeur oscille |
| Répétition | ligne continue dans `ALERTS` ; même courriel à intervalle fixe | `repeat_interval` trop court | `repeat_interval` 4 h (critique), 12 h (avertissement) ; `group_interval` 5 min |
| Éclatement | plusieurs séries `ALERTS` en parallèle, un courriel par série | `group_by` trop fin (`pod`, `instance`, `...`) | `group_by: [alertname, namespace]` (routes d'équipe : + `equipe`) |

Mesure avant/après : nombre de courriels par heure dans Mailpit, `sum by (receiver) (increase(alertmanager_notifications_total[1h]))`. Les valeurs sont contrôlées en CI par `outils/verifier-routes.sh`.

## Le témoin de mon01 se trompe

1. Sur `mon01` : `systemctl status prometheus alertmanager blackbox_exporter` ; `sudo journalctl -u … --since -2h | grep -iE 'error|reload'`.
2. Configuration **chargée** : `curl -s localhost:9090/api/v1/status/config`, `curl -s localhost:9115/config`, `curl -s localhost:9093/api/v2/status`.
3. Cibles : `curl -s localhost:9090/api/v1/targets` (santé, `lastError`), nombre par job comparé à `host_vars/mon01/supervision_temoin.yml`. **Un fichier de cibles vide est valide** : aucune erreur ne le signale.
4. Une sonde à la main : `curl -s 'localhost:9115/probe?target=<URL>&module=<module>&debug=true'` (résolution, famille d'adresses, TLS, code).
5. Réseau : `sudo nft list ruleset` (compteurs), `curl -m 5 http://10.10.41.60:9090/-/healthy` **depuis mon01**.
6. Écart avec le code : `ansible-playbook playbooks/supervision-temoin.yml --limit mon01 --check --diff`. Corriger en rejouant le rôle (pipeline protégé, ADR-0040).
7. Le témoin peut **crier au loup** (il ne voit plus le cluster) ou **se taire** (il ne sonde plus rien) : confronter avec une seconde vue (`lab/bin/check 21 28`, vue globale depuis `adm01`).

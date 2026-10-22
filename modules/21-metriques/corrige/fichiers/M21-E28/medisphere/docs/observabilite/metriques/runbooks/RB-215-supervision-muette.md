# RB-215 — La supervision du cluster est muette (alertes du témoin `mon01`) ou le témoin est aveugle

| | |
|---|---|
| Alertes du témoin (`mon01`, courriel à `astreinte@`) | `SupervisionClusterMuette` (§1), `SupervisionClusterComposantKO` (§2), `SupervisionClusterSondeAbsente` (§3) |
| Alertes du cluster (sur le témoin) | `TemoinInjoignable`, `TemoinSansAlertmanager`, `TemoinNotificationsEnEchec`, `TemoinReglesEnEchec` (§3) |
| Gravité | critique (sauf `TemoinReglesEnEchec`) |
| Équipe | plateforme |
| Ticket d'origine | PLAT-2228 (M21-E28) |

## Principe

Deux supervisions se surveillent l'une l'autre, sur deux domaines de panne différents :

```
  k8s-par1 (Prometheus ×2, Thanos Query, Alertmanager)          mon01 (VM du socle, hors cluster)
  ───────────────────────────────────────────────                ─────────────────────────────────
  règle Watchdog toujours en alerte ──▶ Thanos Query (.60) ◀──── sonde « watchdog_cluster » (1 min)
  /-/healthy, /-/ready de .60 et .61                     ◀──── sonde « http_sante » (30 s)
  ScrapeConfig temoin-mon01 ──────────────────────────────────▶ Prometheus témoin :9090/metrics
  alertes Temoin* ──▶ Alertmanager du cluster ──▶ Mailpit        alertes SupervisionCluster* ──▶
  alertes Alertmanager* (secours) ─────────────────────────────▶ Alertmanager témoin ──▶ Mailpit
```

Chemin de secours : les alertes du cluster dont le nom commence par `Alertmanager` (envois en échec, configuration rechargée en erreur…) partent **aussi** vers l'Alertmanager témoin (`additionalAlertManagerConfigs`, `kps/values.yaml`) : un Alertmanager du cluster qui ne sait plus envoyer de courriel est quand même signalé.

Si tout le cluster tombe, il ne peut pas le dire : c'est le témoin qui écrit. Si le témoin tombe, le cluster le dit. Les deux en même temps (`pve01` arrêté : même hyperviseur) : plus personne n'écrit. Limite assumée et écrite dans l'ADR-0210 ; la réponse serait un service de « dead man's switch » hors de la salle (un abonnement externe qui alerte quand il ne reçoit plus le Watchdog), hors du périmètre du lab.

## 1. `SupervisionClusterMuette` : plus d'alerte Watchdog dans Thanos Query

Le cluster a cessé de produire ou de servir ses alertes. **Toutes** ses alertes sont suspectes.

```
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query \
    --data-urlencode 'query=ALERTS{alertname="Watchdog"}' | jq '.data.result | length'
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/stores | jq '.data | map_values(length)'
admin@adm01:~$ kubectl get nodes; kubectl -n supervision get pods -o wide
```

| Constat | Piste |
|---|---|
| `curl` sans réponse | Thanos Query ou le réseau (§2), ou le cluster entier (`kubectl get nodes`, RB-14x) |
| `stores` sans sidecar | les deux Prometheus sont arrêtés ou leurs sidecars injoignables (RB-214 §1) |
| sidecars présents, 0 résultat | les règles ne sont plus évaluées : `kubectl -n supervision port-forward pod/prometheus-kps-0 9090` puis `/rules` (PrometheusRule refusée, groupe en erreur) ; la règle Watchdog a-t-elle été supprimée (valeurs `defaultRules`) ? |
| tout va bien vu de `adm01` | le chemin `mon01` → 10.10.41.60 : `ssh mon01 curl -s -o /dev/null -w '%{http_code}' http://prometheus.apps.par1.medisphere.internal:9090/-/ready` ; politique `thanos-query-entree` (10.10.20.19/32), pare-feu local de `mon01`, DNS |

Tant que la cause n'est pas réparée : surveillance manuelle des services critiques (sondes blackbox du témoin, M21-E11 : elles restent valables) et message à Nadia Roussel.

## 2. `SupervisionClusterComposantKO`

- `composant="alertmanager"` : **plus aucune notification du cluster**. `kubectl -n supervision get alertmanager kps -o jsonpath='{.spec.replicas}'` (un essai oublié ?), pods `alertmanager-kps-N`, Service `alertmanager-externe`, politique `alertmanager-entree`. Le témoin, lui, notifie : c'est le seul canal pendant la panne.
- `composant="thanos-query"` : lecture impossible (Grafana, Pyrra, checks) ; les alertes du cluster, elles, partent encore (Prometheus → Alertmanager ne passe pas par Query). Pods `thanos-query`, Service `prometheus-externe`, RB-214 §1.

## 3. Le témoin est aveugle ou muet

```
admin@adm01:~$ ssh mon01 systemctl status prometheus alertmanager blackbox_exporter --no-pager
admin@adm01:~$ curl -s http://mon01.par1.medisphere.internal:9090/api/v1/targets?state=active \
    | jq -r '.data.activeTargets[] | select(.labels.job | test("watchdog|supervision")) | [.labels.job, .health, .lastError] | @tsv'
admin@adm01:~$ curl -s http://mon01.par1.medisphere.internal:9090/api/v1/rules | jq -r '.data.groups[] | [.name, (.rules|length)] | @tsv'
```

| Alerte | Piste |
|---|---|
| `TemoinInjoignable` | VM `mon01` arrêtée (Proxmox), service `prometheus`, flux `K8S_TRAV` → `mon01`:9090 (bordure, pare-feu local) |
| `TemoinSansAlertmanager`, `TemoinNotificationsEnEchec` | service `alertmanager` de `mon01`, adresse dans `prometheus.yml` du témoin |
| `TemoinReglesEnEchec` | règle invalide déployée (le rôle valide pourtant avec `promtool` : chercher un changement manuel) |
| `SupervisionClusterSondeAbsente` | `blackbox_exporter` arrêté, job supprimé du `prometheus.yml` |

Corriger **par le rôle** `supervision_temoin` (`plateforme/ansible`), jamais à la main sur `mon01` (le prochain passage du rôle l'écraserait).

## 4. Essai périodique (trimestriel, ticket CHG)

1. Prévenir l'astreinte ; heures ouvrées ; 20 min au plus.
2. MR « Alertmanager à 0 réplica » (`kps/values.yaml`), synchronisation.
3. Attendu dans les 7 min : courriel du témoin `SupervisionClusterComposantKO` (composant `alertmanager`) à `astreinte@` ; **aucun** `SupervisionClusterMuette` (Prometheus et Watchdog vivent).
4. `git revert`, synchronisation, courriel de résolution du témoin.
5. Noter les heures dans `docs/kubernetes/journal/` (délai de détection mesuré).

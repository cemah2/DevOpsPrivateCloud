# Exploration de Prometheus — `k8s-par1`

> Exemple de corrigé (M21-E03) : la forme attendue. Les chiffres sont **représentatifs** d'un cluster du lab avec la seule pile du chart ; les tiens diffèrent, et ce sont les tiens qui comptent.

| | |
|---|---|
| Date de l'exploration | 2026-10-22 |
| Version de Prometheus (`/api/v1/status/buildinfo`) | 3.15.0 (image `quay.io/prometheus/prometheus:v3.15.0-distroless`) |
| Rétention et taille du volume (`/api/v1/status/flags`) | `storage.tsdb.retention.time=15d`, `storage.tsdb.retention.size=32GB`, volume `ceph-rbd` de 40 Gio, `storage.tsdb.path=/prometheus` |

## 1. Les cibles

- 12 jobs, 33 cibles actives, 0 en échec (`count by (job) (up)`). Le job `kubelet` a 18 cibles : 6 nœuds × 3 chemins (`/metrics`, `/metrics/cadvisor`, `/metrics/probes`).
- Cible kubelet de `k8s-w01` : `https://10.10.40.61:10250/metrics/cadvisor`, toutes les 10 s (intervalle propre à cet endpoint dans le chart), dernière collecte en 0,21 s ; étiquettes finales `endpoint="https-metrics"`, `instance="10.10.40.61:10250"`, `job="kubelet"`, `metrics_path="/metrics/cadvisor"`, `namespace="kube-system"`, `node="k8s-w01"`, `service="kps-kubelet"`.
- Échec provoqué : `kubectl -n supervision scale deploy kps-kube-state-metrics --replicas=0` le temps d'une collecte (Argo CD l'a remis à 1 en moins d'une minute, `selfHeal`) : la cible a disparu de *Target health* (plus de point de terminaison), et `absent(up{job="kube-state-metrics"})` est passé à 1. Pour une cible en échec **présente**, le message est `Get "…": context deadline exceeded` (filtrage) ou `connection refused` (rien n'écoute).

## 2. Découverte de services et relabeling

| Étiquette découverte (extrait) | Valeur | Étiquette finale |
|---|---|---|
| `__address__` | `10.10.40.61:10250` | `instance="10.10.40.61:10250"` |
| `__scheme__` / `__metrics_path__` | `https` / `/metrics/cadvisor` | `metrics_path` (règle du chart) |
| `__meta_kubernetes_namespace` | `kube-system` | `namespace` |
| `__meta_kubernetes_service_name` | `kps-kubelet` | `service` |
| `__meta_kubernetes_service_label_k8s_app` | `kubelet` | `job` (`jobLabel: k8s-app`) |
| `__meta_kubernetes_endpointslice_port_name` | `https-metrics` | `endpoint` |
| `__meta_kubernetes_endpoint_node_name` | `k8s-w01` | `node` |

- `job`, `instance` : posés par Prometheus (`job` = nom du job, réécrit ici par la règle tirée de `jobLabel`) ; `namespace`, `service`, `pod`, `endpoint` : règles `replace` écrites par l'opérateur.
- 12 cibles découvertes puis écartées par `serviceMonitor/supervision/kps-kubelet/0` : le Service `kps-kubelet` déclare trois ports (`https-metrics`, `http-metrics`, `cadvisor`) ; la règle `keep` sur le nom de port ne garde que `https-metrics`.

## 3. La configuration générée

- Secret `supervision/prometheus-kps`, clé `prometheus.yaml.gz` (gzip, base64 dans l'objet) ; lu par `kubectl get secret … -o jsonpath | base64 -d | gunzip | less`, jamais écrit sur disque ; les règles sont dans les ConfigMaps `prometheus-kps-rulefiles-0…`.
- Job `serviceMonitor/supervision/kps-kubelet/0` : `kubernetes_sd_configs` rôle `endpointslice`, espace `kube-system` ; `keep` sur les étiquettes du Service (`app.kubernetes.io/name=kubelet`, `k8s-app=kubelet`) ; `keep` sur le port `https-metrics` ; `replace` vers `namespace`, `service`, `pod`, `container` ; `job` depuis `k8s-app`.
- `/api/v1/status/flags` : `web.enable-lifecycle=true` (le conteneur de rechargement appelle `/-/reload`), `web.enable-admin-api=false`, `config.file=/etc/prometheus/config_out/prometheus.env.yaml`.

## 4. La TSDB

- Tête : 186 412 séries, environ 6 200 échantillons ingérés par seconde ; 3 blocs persistés, le plus ancien a 9 heures.
- Métriques les plus coûteuses : `apiserver_request_duration_seconds_bucket` (≈ 9 000 séries), `apiserver_request_sli_duration_seconds_bucket`, `etcd_request_duration_seconds_bucket`, `apiserver_response_sizes_bucket`, `container_memory_failures_total`. Étiquettes aux valeurs les plus nombreuses : `id` (cgroups de cAdvisor), `name`, `pod`, `le`.
- Surprise : plus de la moitié des séries viennent des histogrammes du kube-apiserver, que personne ne regarde. Question pour Karim : les filtrer dès la collecte (`metricRelabelings` en `drop`, E13) ou les garder pour le SLO de l'API (E14) ?

## 5. Requêtes

Les requêtes utilisées sont dans `plateforme/observabilite`, fichier `requetes/E03.promql`.

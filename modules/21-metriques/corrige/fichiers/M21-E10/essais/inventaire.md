# ~/m21/e10/inventaire.md — exportateurs natifs du socle (M21-E10, PLAT-2210)

| Source | Point d'accès | Authentification | Par défaut | Coût | Décision |
|---|---|---|---|---|---|
| Ceph 20.2 (mgr) | `http://<mgr>:9283/metrics` | aucune | module désactivé ; actif seulement sur le mgr actif | cache de 15 s dans le mgr ; compteurs de démons exclus (`ceph-exporter`) | activé, 3 cibles, `honor_labels` |
| HAProxy 3.2 | service `prometheus-exporter` appelé par un frontend | aucune (ACL à écrire) | rien n'écoute : il faut un frontend | négligeable | `fe_metriques` sur 8405, ACL |
| PowerDNS Auth 5.0 | `/metrics` du serveur web (8081) | `webserver-password` si posé, `webserver-allow-from` | serveur web actif sur `dns01` (API) ; absent sur `dns02` | négligeable | allow-from étendu ; serveur web sans API sur `dns02` |
| PowerDNS Recursor 5.4 | `/metrics` du webservice (8082) | `webservice.password` si posé, `allow_from` | webservice désactivé | négligeable | webservice activé, sans clé d'API |
| Kea 3.0 | **aucun** point d'accès Prometheus natif : statistiques par les commandes `statistic-get-all` du canal de contrôle (socket HTTPS 8004, M06-E25) | — | — | — | non collecté en E10 ; voir ci-dessous |
| GitLab 19.5 | `/-/metrics` (Rails, 443), gitlab-exporter 9168, Sidekiq 8082, Workhorse 9229, Gitaly 9236 | liste blanche `monitoring_whitelist` (`/-/metrics`), aucune pour les autres | coupés par `prometheus_monitoring` (M01-E04), en partie rouverts (M01-E30) | gitlab-exporter ≈ 100-150 Mo ; les autres ≈ 0 | les cinq ; pas de Prometheus embarqué, ni postgres/redis_exporter |
| Harbor 2.15 | `:9090/metrics` (exportateur), `?comp=core|registry|jobservice` | aucune | activé au M13 | requêtes SQL de l'exportateur à chaque collecte | 4 cibles, collecte à 60 s |

**Kea.** Kea 3.0 n'expose pas de format Prometheus : ses statistiques (baux par sous-réseau,
paquets reçus, refusés…) se lisent par le canal de contrôle. Trois voies :
1. `kea-exporter` (PyPI, 0.7) : petit service Python qui interroge le canal de contrôle et expose
   `/metrics` ; dans un environnement `uv` sur `dns01`/`dns02`, avec le compte `supervision` ;
2. **Stork** d'ISC (agent sur chaque serveur Kea, exportateur Prometheus intégré à l'agent,
   port 9547) : plus complet, plus lourd (serveur Stork + base) ;
3. un script dans le collecteur `textfile` de node_exporter : à éviter (fragile, pas de typage).
Choix : `kea-exporter` en « pour aller plus loin », Stork si MédiSphère généralise Kea (PRA, F5).

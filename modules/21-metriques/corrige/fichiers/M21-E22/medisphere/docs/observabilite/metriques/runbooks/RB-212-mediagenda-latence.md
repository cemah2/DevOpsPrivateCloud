# RB-212 — MediagendaLatenceElevee : l'API MédiAgenda est lente

**Alerte** : `MediagendaLatenceElevee` (avertissement ; équipe `mediagenda`) ; aussi `MediagendaCpuBride` · **Tableau** : [RED MédiAgenda](https://grafana.apps.par1.medisphere.internal/d/mediagenda-red?var-environnement=prod), [USE des nœuds](https://grafana.apps.par1.medisphere.internal/d/plateforme-use-noeuds) · **Dernière vérification** : à la création (M21-E22)

## Que signifie cette alerte
En production, 5 % des requêtes de l'API prennent plus de **300 ms** (objectif) depuis 15 minutes,
avec un trafic d'au moins 6 requêtes par minute.

## Impact pour les utilisateurs
Les pages de prise de rendez-vous se chargent lentement ; au-delà de quelques secondes, les
utilisateurs abandonnent ou recommencent (ce qui ajoute de la charge).

## Premières vérifications (5 minutes)
1. Quelle route est lente ?
   `histogram_quantile(0.95, sum by (route, le) (rate(mediagenda_http_request_duration_seconds_bucket{environnement="prod"}[5m])))`
2. Le trafic a-t-il augmenté ? `environnement:mediagenda_requetes:taux5m{environnement="prod"}` sur 24 h.
3. Saturation de l'API : `namespace_pod:mediagenda_cpu_bride:ratio5m{namespace="mediagenda-prod"}`
   (part des périodes bridées par la limite de CPU) et mémoire des pods.
4. Base : connexions et requêtes lentes, `sum by (pod) (cnpg_backends_total{namespace="mediagenda-prod"})`
   comparées à `cnpg_pg_settings_setting{name="max_connections", namespace="mediagenda-prod"}`.
5. Cache : `sum by (resultat) (rate(mediagenda_cache_total{environnement="prod"}[5m]))` — une chute
   des `hit` ou des `erreur` envoie toutes les lectures de créneaux à la base.

## Causes connues et actions
| Ce que tu observes | Cause probable | Action |
|---|---|---|
| Plus de 25 % de périodes bridées, trafic en hausse | CPU de l'API limité (INC-4823) | ajouter des réplicas ou relever la limite par MR (overlay prod) ; en urgence, Karim peut valider une MR rapide |
| Connexions PostgreSQL proches du maximum | réservoir de connexions saturé | réplicas de l'API × 10 connexions ≤ maximum de la base : ne pas multiplier les réplicas sans vérifier |
| `mediagenda_cache_total{resultat="erreur"}` en hausse | Valkey indisponible : mode dégradé | vérifier le StatefulSet `valkey`, prévenir Karim |
| Un seul nœud concerné | nœud saturé (voisins bruyants) | tableau USE des nœuds ; drainer le nœud si besoin (RB-140) |

## Escalade
Avertissement : traité aux heures ouvrées par l'équipe MédiAgenda. Si la latence dépasse 2 s
pendant 15 minutes en prod, ou si des erreurs apparaissent (RB-211), astreinte et Julien Petit.

## Retour à la normale
`environnement:mediagenda_duree_requetes:p95_5m{environnement="prod"}` sous 300 ms pendant 30 minutes.

## Après l'incident
Mesure retenue (réplicas, limite) inscrite dans `mediagenda/deploiement` ; seuil de l'alerte et
SLO de latence (palier 3, Pyrra) revus si l'objectif n'est plus réaliste.

<!-- plateforme/medisphere — docs/plateforme-dev/autoscaling.md : section AJOUTÉE en M28-E03 (PLAT-2903), après « MédiAgenda ». -->

## KEDA

| Élément | Valeur |
|---|---|
| Version | KEDA 2.21.0 (chart 2.21.0), Application `keda`, espace `keda` |
| API servie | `v1beta1.external.metrics.k8s.io` → `keda/keda-operator-metrics-apiserver` (seul fournisseur du cluster : ne jamais installer prometheus-adapter en mode « externe » à côté) |
| Cibles autorisées | Deployment, StatefulSet (d'office) et Rollout (`rbac.scaledRefKinds` : ressource `rollouts`) |
| Confiance TLS | racine MédiSphère montée sur `/custom/ca` (`--ca-dir`) ; jamais `unsafeSsl` |
| Supervision | ServiceMonitors des trois composants ; métriques `keda_scaler_detail_errors_total`, `keda_scaler_metrics_value`, `keda_scaler_active`, `keda_scaled_object_errors_total` (noms relevés dans le code de la 2.21.0) |
| Risque accepté | l'opérateur lit (`list`, `watch`) tous les Secrets du cluster (règle par défaut du chart) : nécessaire aux `TriggerAuthentication` des équipes. Alternative étudiée : `permissions.operator.restrict.secret: true` + `ClusterTriggerAuthentication` dont la plateforme gère les Secrets dans `keda`. Décision à l'ADR-0280 (palier 3). |

## MédiNotif — `ScaledObject` `medinotif` (file `notifications`)

### Protocole du scaler `rabbitmq`

| | AMQP | HTTP (API de gestion) — **retenu** |
|---|---|---|
| Ce que fait le scaler | déclaration **passive** de la file | `GET /api/queues/<vhost>/notifications` |
| Droits exigés | depuis RabbitMQ 4.3.1, au moins une permission (`configure`, `write` ou `read`) **sur la file** | étiquette `management` + une entrée de permissions sur le vhost (motifs `^$`) |
| Pouvoir en trop | `read` : consommer (voler) des notifications ; `write` : en publier ; `configure` : supprimer la file | aucun sur les messages ; voit les objets du vhost `medinotif-recette` seulement |
| Messages comptés | prêts seulement | prêts **et** non acquittés |
| Port, flux | AMQPS 5671 | HTTPS 15671 (CNP `keda-operator` → `messagerie`) |

`monitoring` à la place de `management` marcherait aussi, mais cette étiquette voit **tous** les vhosts (dont la production) : écarté.

### Réglages (recette)

| Champ | Valeur | Raison |
|---|---|---|
| `minReplicaCount` / `maxReplicaCount` | 1 / 5 | zéro au palier 3 seulement ; 5 = quota de `medinotif-recette` |
| `value` (`QueueLength`) | 100 messages par pod | un pod traite ≈ 20 msg/s (50 ms par envoi, `prefetch` 1) : ≈ 5 s de retard toléré |
| `pollingInterval` | 15 s | réactivité lors des vagues de rappels |
| Descente | stabilisation 300 s, 1 pod / min | les campagnes arrivent par vagues |
| Identifiants | `TriggerAuthentication` `medinotif-rabbitmq` → Secret `medinotif-rabbitmq` (ExternalSecret, `kv/medinotif/recette/keda`) | aucun secret dans Git ni dans le `ScaledObject` |

### Essai (recette)

`MEDINOTIF_DELAI_ENVOI_MS` porté à 500 ms le temps de l'essai (≈ 2 msg/s par pod), `charge.sh -m rendez-vous -c 16 -d 180` : la file monte à ≈ 900 messages, l'HPA `keda-hpa-medinotif` passe à 5 pods en ≈ 1 min, la file se vide, retour à 1 pod ≈ 10 min après. Délai remis à 50 ms par MR. *(Valeurs représentatives : relève les tiennes.)*

# Autoscaling des applications — MédiSphère

> Créé en M28-E02 et M28-E03, complété en M28-E13 (PLAT-2913). Propriétaire : équipe Plateforme. Revue : à chaque changement de seuil, et après chaque campagne de rappel de plus de 20 000 messages.
> Les valeurs « mesurées » ci-dessous sont celles du corrigé (lab de référence) : **remplace-les par les tiennes**.

## 1. Qui pilote quoi

| Application | Environnement | Mécanisme | Déclencheurs | Min / max | Retour à 0 | Repli (source en erreur) |
|---|---|---|---|---|---|---|
| MédiAgenda (Rollout `mediagenda`) | recette | HPA `mediagenda` | CPU 70 % des requests | 2 / 4 | non | — (métriques de ressources : pas de repli) |
| MédiAgenda | prod | HPA `mediagenda` | CPU 70 % | 3 / 6 | non | — |
| MédiNotif (Deployment `medinotif`) | recette | KEDA `ScaledObject` `medinotif` → HPA `keda-hpa-medinotif` | file `notifications` (100/pod), cron 13 h 50–14 h 30 (2), débit de publication de MédiAgenda (20/s/pod) | **0** / 5 | après 10 min sans activité | 2 pods, ou l'effectif courant s'il est plus haut |
| MédiNotif | prod | idem | file (100/pod), cron 7 h 50–9 h 30 jours ouvrés (6), débit de publication (20/s/pod) | 2 / 8 | jamais | 4 pods, ou l'effectif courant s'il est plus haut |
| Toutes | toutes | VPA `updateMode: "Off"` | — | — | — | recommandations seulement (rapport mensuel, M28-E14) |

Comportement de l'HPA (MédiNotif) : montée immédiate (+100 % ou +2 pods / 15 s en recette, +4 en prod, le plus fort) ; descente après 5 min (recette) ou 10 min (prod) de stabilisation, un pod à la fois.

## 2. Mesures

| Mesure (recette, 2 000 messages) | Avant (E03) | Après (E13) |
|---|---|---|
| Délai avant le premier pod supplémentaire | 45 s | 15 s (file) ; 0 s pendant la fenêtre cron |
| Pods au maximum | 4 | 4 |
| Temps pour vider la file | 3 min 10 s | 1 min 05 s |
| Débit d'un pod | ≈ 20 messages/s (`MEDINOTIF_DELAI_ENVOI_MS=50`) | idem |
| **Démarrage à froid** (message sur file vide, MédiNotif à 0 → message traité) | — | 22 s en moyenne (15 s d'interrogation au pire + 2 s de planification + 4 s de démarrage du pod et de connexion AMQPS) |

Campagne de prod (simulation) : 40 000 messages à 8 h 00 ; avec le cron, 6 pods sont prêts à 7 h 52 ; la file est vide à 8 h 06 (au lieu de 8 h 40 avant E13).

## 3. Quand une source tombe

| Source | À 0 réplica (recette) | Entre 1 et N | Ce qui alerte |
|---|---|---|---|
| RabbitMQ (API de gestion 15671) | l'activation ne voit rien : **MédiNotif reste à 0** tant que le cron ou Prometheus ne l'activent pas ; les messages attendent dans la file (rien n'est perdu) | après 3 échecs (45 s), repli : 2 pods en recette / 4 en prod, ou l'effectif courant s'il est plus haut | `KedaScalerEnErreur` (10 min) |
| Thanos Query (déclencheur prometheus) | idem : l'activation repose sur les autres déclencheurs | repli identique (le repli s'applique dès qu'UN déclencheur échoue) | `KedaScalerEnErreur` |
| KEDA (opérateur) | plus aucune activation depuis 0 : les messages attendent | l'HPA garde la dernière décision… puis n'a plus de métrique quand l'adaptateur tombe (`FailedGetExternalMetric`) : l'effectif reste figé | `KedaAbsent` (5 min) |
| Adaptateur de métriques de KEDA | sans effet sur l'activation | HPA figé | `KedaAbsent` |

Conséquence écrite : en recette, une panne de RabbitMQ ou de KEDA **pendant que MédiNotif dort** retarde les notifications jusqu'au retour de la source (ou jusqu'à la fenêtre cron). C'est accepté en recette ; c'est la raison pour laquelle la prod garde un minimum de 2.

## 4. Pause pour maintenance (RabbitMQ, KEDA)

1. MR sur l'overlay concerné de `medinotif/deploiement` : ajouter `pause-maintenance.yaml` aux `patches` (annotation `autoscaling.keda.sh/paused-replicas: "<N>"` ; N = effectif voulu pendant la maintenance, 2 en prod). Ticket `CHG-` dans l'annotation `medisphere.internal/ticket`.
2. Synchronisation (recette : automatique ; prod : à la main). Contrôle : `kubectl -n medinotif-prod get scaledobject medinotif -o jsonpath='{.status.conditions[?(@.type=="Paused")].status}'` → `True`, et l'effectif vaut N.
3. Fin : MR inverse (retirer le fichier ET son entrée). L'alerte `KedaScaledObjectEnPause` se déclenche si la pause dure plus de 2 h.

Pas d'`kubectl annotate` à la main : Argo CD ne l'efface pas forcément (le champ n'est pas dans Git), il serait donc **oublié** — exactement ce que l'alerte de pause rattrape.

## 5. Règles pour les équipes

- Jamais de `replicas` dans Git pour une charge pilotée par un HPA ou KEDA.
- Jamais de VPA en mode automatique sur une ressource qu'un HPA pilote sur le CPU ou la mémoire.
- Un `ScaledObject` déclare toujours un `fallback`, un `cooldownPeriod` et un comportement d'HPA explicites.

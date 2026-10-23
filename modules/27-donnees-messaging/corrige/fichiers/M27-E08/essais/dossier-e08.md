# Dossier M27-E08 (modèle) — `~/m27/e08/`

## MR, dans l'ordre de fusion

| # | Projet | Objet | Pourquoi dans cet ordre |
|---|---|---|---|
| 1 | `plateforme/secrets` | `eso-plateforme` lit `kv/data/{medinotif,mediagenda}/prod/amqp` ; rôle `eso-medinotif-prod` | les utilisateurs de prod ne peuvent pas exister sans |
| 2 | `plateforme/k8s` | espace `medinotif-prod`, `isolement-medinotif-prod` | l'Application de prod a besoin de l'espace (`CreateNamespace=false`) |
| 3 | `plateforme/donnees` | `topologie/medinotif-prod/` ; CNP `rabbitmq` : entrées depuis `medinotif-prod` et `mediagenda-prod` | la file doit exister avant le premier message |
| 4 | `mediagenda/api` | correctif de publication, `pika` ; étiquette `vX.Y.Z` (image signée) | dormant tant que la variable n'est pas posée |
| 5 | `mediagenda/deploiement` | component `notifications` en **recette** ; promotion de la version | démonstration de vendredi |
| 6 | `medinotif/deploiement` | `overlays/prod` | |
| 7 | `plateforme/gitops` | élément `prod` de l'ApplicationSet `medinotif` (synchronisation manuelle) | |
| 8 | `mediagenda/deploiement` | component `notifications` en **prod** ; promotion | en dernier : un consommateur attend déjà |

## Décisions

- **Publier après la validation**, pas avant, pas dans la transaction : on ne notifie jamais un rendez-vous annulé par un conflit ; un arrêt brutal entre les deux perd une confirmation (rare, visible nulle part : limite écrite). *Outbox* refusée **pour l'instant** : table, relais et nettoyage en plus pour un SMS de confirmation ; à reprendre si les rappels de la veille passent par ce chemin (ADR-0270).
- **Ne jamais faire échouer la requête** : `201` même si la publication échoue ; journal + compteur ; délai de connexion 2 s, abandon si le courtier bloque les éditeurs (5 s).
- **Confirmations + `mandatory`** : « publiée » = acceptée **et** routée. Sans `mandatory`, un message vers un échange sans liaison est accepté puis jeté en silence.
- **Une connexion par processus**, sous verrou (pika bloquant non sûr entre fils), ouverte à la première publication : un RabbitMQ absent n'empêche ni le démarrage ni `/pret`.
- **Refusé** : un `/pret` qui dépend de RabbitMQ (une panne de messagerie couperait la prise de rendez-vous) ; une file déclarée par l'API (la plateforme déclare) ; le compte de la recette réutilisé en prod.
- **Prod de MédiNotif** : deux réplicas répartis, `PodDisruptionBudget`, même image que la recette (empreinte).

## Panne simulée en recette

Choix : retirer **le temps de l'essai, par MR** la règle d'entrée `mediagenda-recette` de la CNP `rabbitmq` (et non arrêter un nœud : la file quorum survit à un nœud, l'éditeur ne verrait rien ; ni réduire la grappe, opération dangereuse sur des files quorum). Pendant dix minutes, 30 prises de rendez-vous avec rappel : toutes en `201`, `mediagenda_notifications_total{resultat="echec"}` +30, journaux `AMQPConnectionError`, latence p99 de la route + ≈ 2 s (délai de connexion) — à noter : chaque requête paie le délai tant que le courtier est injoignable. MR de retour, publications de nouveau `publiee`. Les 30 confirmations sont **perdues** (pas de reprise) : c'est le prix du choix ci-dessus.

## Preuves (sans donnée personnelle)

```
sum by (namespace, resultat) (increase(mediagenda_notifications_total{namespace=~"mediagenda-(recette|prod)"}[1h]))
sum by (namespace, resultat) (increase(medinotif_messages_total{namespace=~"medinotif-(recette|prod)"}[1h]))
```
API de gestion (`wb-checks`) : `GET /api/connections` → `mediagenda-prod`, `ssl: true` ; `GET /api/queues/medinotif-prod/notifications` → 2 consommateurs, `messages: 0`.

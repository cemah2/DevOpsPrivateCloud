<!-- docs/donnees/messagerie-topologie.md : SECTIONS À AJOUTER (M27-E08, DEV-2808) -->

## Production (M27-E08)

Même topologie qu'en recette dans le vhost **`medinotif-prod`** (dossier `topologie/medinotif-prod/` de `plateforme/donnees`, objets préfixés `medinotif-prod-…`), mêmes droits : `medinotif-prod` lit `notifications`, `mediagenda-prod` écrit sur l'échange `notifications`, `wb-checks` voit les métadonnées. Secrets `kv/medinotif/prod/amqp` et `kv/mediagenda/prod/amqp` ; lecture par `eso-plateforme` (exception SEC-2804 étendue, chemin par chemin).

MédiNotif en prod (`medinotif/deploiement`, `overlays/prod`, Application `medinotif-prod` synchronisée à la main) : **deux** workers sur deux nœuds (`topologySpreadConstraints`), `PodDisruptionBudget` `maxUnavailable: 1`, image signée par empreinte (la même qu'en recette).

## L'éditeur : MédiAgenda (M27-E08)

```
POST /api/v1/rendez-vous ──► transaction validée (INSERT) ──► demande_confirmation()
     (rappel.canal ≠ aucun)                                     │ {type, destinataire, modele: confirmation, rendez_vous_id}
                                                                ▼
                       PublieurAMQP : amqps://mediagenda-<env>@rabbitmq.messagerie.svc:5671/medinotif-<env>
                       confirmations + mandatory ; échec → journal + compteur, réponse 201 quand même
                                                                ▼
                       échange notifications ─(clé notifications)─► file quorum notifications ─► MédiNotif
                                                                       └─ rejet / limite de livraison ─► notifications.rebut
```

| Élément | Valeur |
|---|---|
| Variable | `MEDIAGENDA_AMQP_URL`, Secret `mediagenda-amqp` (component `notifications` de `mediagenda/deploiement`, recette et prod ; absent en dev : rien n'est publié) |
| Réseau | NetworkPolicy `mediagenda-vers-rabbitmq` (sortie 5671 vers les pods `rabbitmq` de `messagerie`) ; CNP `rabbitmq` : entrée depuis `mediagenda-<env>` |
| Confiance | racine MédiSphère, `SSL_CERT_FILE` (component `racine-medisphere`) : pika vérifie chaîne et nom (`rabbitmq.messagerie.svc`) |
| Métrique | `mediagenda_notifications_total{resultat="publiee|echec|desactivee"}` |
| Garanties | publication **après** la validation : jamais de notification pour un rendez-vous qui n'existe pas ; un arrêt brutal entre la validation et la confirmation perd la notification (trou assumé, compté par aucun indicateur : c'est la limite de ce choix ; *outbox* discutée dans l'ADR-0270) |

### Diagnostic

- `sum by (namespace, resultat) (rate(mediagenda_notifications_total[5m]))` : `echec` > 0 → journaux `mediagenda.notifications` (`erreur` : `AMQPConnectionError` réseau ou TLS, `UnroutableError` liaison ou file absente, `NackError` courtier qui refuse, `ConnectionBlockedTimeout` alarme mémoire ou disque).
- API de gestion : connexions de `mediagenda-<env>` (doit être `ssl: true`), taux de publication de l'échange `notifications`.

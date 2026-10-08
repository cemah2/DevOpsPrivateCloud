# MédiNotif — worker de notifications

Worker Python 3.13 qui consomme les demandes de notification (SMS, mail) émises lors de la prise de rendez-vous et les « envoie ». L'envoi est **simulé** : chaque notification produit une ligne de journal JSON, rien ne part réellement.

Projet GitLab cible : `medinotif/worker`.

## Messages

File RabbitMQ `notifications`, un objet JSON par message :

```json
{"type": "sms", "destinataire": "+33612345678", "modele": "rappel-veille", "rendez_vous_id": 42}
{"type": "mail", "destinataire": "jeanne@exemple.fr", "modele": "confirmation", "rendez_vous_id": 42}
```

| Résultat du traitement | Effet sur RabbitMQ |
|---|---|
| Envoyé | `basic_ack` |
| Message invalide (JSON illisible, champ manquant, type inconnu…) | `basic_nack` **sans** remise en file : le message part vers la *dead letter exchange* si la file en a une, sinon il est supprimé |
| Échec passager de l'envoi | `basic_nack` **avec** remise en file, après une pause d'une seconde |

Le worker prend un message à la fois (`prefetch_count=1`) et n'acquitte qu'**après** l'envoi : un worker tué en plein traitement ne perd pas le message (livraison « au moins une fois » ; un message peut donc, rarement, être traité deux fois).

Les journaux ne contiennent jamais le destinataire en clair (`j***@exemple.fr`, `**********78`) : c'est une donnée personnelle.

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `MEDINOTIF_BACKEND` | `rabbitmq` | Source des messages : `rabbitmq`, `stdin` (tests, développement) ; `kafka` est réservé (module 27) et refusé pour l'instant |
| `MEDINOTIF_AMQP_URL` | *(obligatoire avec `rabbitmq`)* | ex. `amqp://medinotif:<MOT-DE-PASSE>@rabbitmq.exemple:5672/medinotif` (`amqps://` pour TLS) |
| `MEDINOTIF_FILE` | `notifications` | Nom de la file |
| `MEDINOTIF_TYPE_FILE` | `quorum` | Type de file déclaré au démarrage : `quorum` (répliquée, recommandée) ou `classic` |
| `MEDINOTIF_DECLARER_FILE` | `1` | `0` si la plateforme crée la file elle-même (le worker ne la déclare plus) |
| `MEDINOTIF_PORT_METRIQUES` | `9100` | Port HTTP des métriques Prometheus |
| `MEDINOTIF_LOG_LEVEL` | `INFO` | Niveau de journal |
| `MEDINOTIF_LOG_FORMAT` | `json` | `json` ou `texte` |
| `MEDINOTIF_DELAI_ENVOI_MS` | `50` | Latence simulée d'un envoi (utile pour observer l'arrêt propre) |
| `MEDINOTIF_VERSION` | `dev` | Version affichée au démarrage |

Si la file existe déjà avec un autre type que `MEDINOTIF_TYPE_FILE`, RabbitMQ refuse la déclaration (`PRECONDITION_FAILED`) et le worker boucle sur des reconnexions : aligne le type ou passe `MEDINOTIF_DECLARER_FILE=0`.

> Le port 9100 est aussi celui de `node_exporter`. Sur une VM qui en a déjà un, change `MEDINOTIF_PORT_METRIQUES` ; dans un conteneur, la question ne se pose pas.

## Métriques et santé

Sur `http://<hôte>:9100/metrics` : `medinotif_messages_total{type,resultat}` (`envoye`, `invalide`, `echec`), `medinotif_traitement_duration_seconds` (histogramme), plus les métriques du processus. Le serveur répond sur n'importe quel chemin : il sert aussi de sonde de vivacité (le processus est vivant). Il n'y a pas de sonde de disponibilité : un worker ne reçoit pas de trafic entrant, il consomme.

## Arrêt propre

SIGTERM (ou SIGINT) lève un drapeau. Le message en cours est terminé et acquitté, l'abonnement est annulé (les messages reçus et non traités retournent dans la file), la connexion est fermée, le processus sort avec le code 0. Le délai de grâce de la plateforme doit couvrir la durée d'un traitement.

Connexion perdue : nouvelle tentative avec une attente croissante (1 s, 2 s, 4 s… plafonnée à 30 s).

## Lancer en local

```
admin@adm01:~/src/medinotif-worker$ uv sync --locked
admin@adm01:~/src/medinotif-worker$ echo '{"type":"sms","destinataire":"+33612345678","modele":"rappel","rendez_vous_id":1}' \
  | MEDINOTIF_BACKEND=stdin uv run medinotif
admin@adm01:~/src/medinotif-worker$ MEDINOTIF_AMQP_URL='amqp://medinotif:<MOT-DE-PASSE>@127.0.0.1:5672/%2F' uv run medinotif
```

(`%2F` est le *vhost* par défaut `/`, encodé dans l'URL.)

## Tests

```
admin@adm01:~/src/medinotif-worker$ uv run pytest        # faux courtier, aucun RabbitMQ requis
admin@adm01:~/src/medinotif-worker$ uv run ruff check . && uv run ruff format --check .
admin@adm01:~/src/medinotif-worker$ MEDINOTIF_TEST_AMQP_URL='amqp://…' uv run pytest -m integration   # vrai RabbitMQ
```

## Ajouter un backend (Kafka, module 27)

Le traitement (`traitement.py`) reçoit des octets et rend un `Resultat` ; il ignore d'où vient le message. Une source respecte l'interface `Source` de `sources/base.py` : `consommer(traiter)` (bloquant) et `arreter()` (appelable depuis un gestionnaire de signal). Pour Kafka : écrire `sources/kafka.py`, valider l'offset après `ENVOYE` ou `INVALIDE` (ou publier l'invalide sur un *topic* de rebut), ne pas le valider après `ECHEC`, puis brancher la classe dans `creer_source` (`sources/__init__.py`).

## Structure

```
src/medinotif/
  __main__.py      point d'entrée, signaux, serveur de métriques
  config.py        variables d'environnement
  message.py       format et validation des messages
  traitement.py    analyse + envoi simulé + métriques
  sources/         base.py (interface), rabbitmq.py, stdin.py
tests/             pytest
```

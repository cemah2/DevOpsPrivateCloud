# M27-E08 — correctif de `mediagenda/api` : publication des notifications

S'applique **après** celui de M27-E06 (`rappel.patch` : la demande utilise `rendez_vous.rappel`).

```
admin@adm01:~/src/mediagenda-api$ git switch -c dev-2808-notifications
admin@adm01:~/src/mediagenda-api$ git apply --index ~/DevOpsPrivateCloud/modules/27-donnees-messaging/corrige/fichiers/M27-E08/mediagenda-api/notifications.patch
admin@adm01:~/src/mediagenda-api$ uv add "pika>=1.4.4,<2"          # pyproject.toml ET uv.lock (cache de paquets du lab)
admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
67 passed, 3 deselected …
admin@adm01:~/src/mediagenda-api$ MEDIAGENDA_TEST_AMQP_URL='amqp://…' uv run pytest -m integration -k notifications   # vrai RabbitMQ (facultatif)
```

| Fichier | Rôle |
|---|---|
| `src/mediagenda/notifications.py` | `PublieurAMQP` (confirmations, `mandatory`, verrou, une reconnexion), `PublieurInactif`, `demande_confirmation`, métrique `mediagenda_notifications_total{resultat}` |
| `src/mediagenda/config.py` | `MEDIAGENDA_AMQP_URL` (facultative ; `amqp://` ou `amqps://` ; message d'erreur sans l'URL) |
| `src/mediagenda/app.py` | publieur créé au démarrage (sans connexion), fermé à l'arrêt ; publication **après** `depot.creer` |
| `tests/test_notifications.py` | publieur factice, refus du courtier, connexion perdue, absence de donnée personnelle dans les journaux ; essai d'intégration marqué `integration` |

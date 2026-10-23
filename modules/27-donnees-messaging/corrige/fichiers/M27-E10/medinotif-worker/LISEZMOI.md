# M27-E10 — correctif de `medinotif/worker` : backend Kafka

```
admin@adm01:~/src/medinotif-worker$ git switch -c dev-2810-kafka
admin@adm01:~/src/medinotif-worker$ git apply --index ~/DevOpsPrivateCloud/modules/27-donnees-messaging/corrige/fichiers/M27-E10/medinotif-worker/kafka.patch
admin@adm01:~/src/medinotif-worker$ uv add "confluent-kafka>=2.16.0,<3"      # pyproject.toml ET uv.lock
admin@adm01:~/src/medinotif-worker$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
32 passed, 2 deselected …
admin@adm01:~/src/medinotif-worker$ MEDINOTIF_TEST_KAFKA_BOOTSTRAP=127.0.0.1:9092 uv run pytest -m integration -k kafka   # facultatif
```

Facultatif : compléter la description du marqueur `integration` dans `pyproject.toml`
(« … ou un vrai Kafka (MEDINOTIF_TEST_KAFKA_BOOTSTRAP) »).

| Fichier | Rôle |
|---|---|
| `src/medinotif/sources/kafka.py` | `SourceKafka` : *commit* manuel synchrone après `ENVOYE` ; `INVALIDE` → copie sur `notifications.rebut` (`acks=all`, idempotent, accusé attendu) puis *commit* ; `ECHEC` → `seek` sur le message (la partition attend) ; `close()` à l'arrêt |
| `src/medinotif/config.py`, `sources/__init__.py` | variables `MEDINOTIF_KAFKA_*`, branchement dans `creer_source` |
| `tests/test_kafka.py`, `tests/test_worker.py` | faux consommateur et faux producteur ; essai d'intégration marqué `integration` |
| `README.md` | variables et garanties |

Testé : 32 tests unitaires ; intégration contre Kafka 4.3.1 (KRaft, un nœud, en clair) : envoi, rebut, *commit*, reprise après redémarrage du worker sans perte.

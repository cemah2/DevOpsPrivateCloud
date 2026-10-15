# MédiAnnuaire — annuaire des praticiens

Service HTTP en lecture seule de l'équipe de Julien Petit : il sert la liste des praticiens (nom, spécialité, cabinet, numéro RPPS) à la prise de rendez-vous. Python 3.13, **bibliothèque standard uniquement** (aucune dépendance), projet géré par `uv`.

Projet GitLab cible : `mediagenda/annuaire`. Données **fictives**.

## Points d'accès

| Méthode et chemin | Rôle |
|---|---|
| `GET /sante` | Vivacité : `{"statut":"ok","version":"…"}` |
| `GET /pret` | Disponibilité : 200 quand l'annuaire est chargé, 503 sinon |
| `GET /metrics` | Métriques au format texte Prometheus (`mediannuaire_http_requests_total`, `mediannuaire_praticiens`, `mediannuaire_info`) |
| `GET /api/v1/praticiens[?specialite=…]` | Liste (filtre facultatif, insensible à la casse) |
| `GET /api/v1/praticiens/{id}` | Détail (404 si inconnu) |
| `POST /admin/recharger` | Relit le fichier de données ; en-tête `Authorization: Bearer <JETON>` obligatoire (401 sinon) |

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `MEDIANNUAIRE_JETON_ADMIN` ou `MEDIANNUAIRE_JETON_ADMIN_FICHIER` | *(l'un des deux est obligatoire)* | Jeton du rechargement (16 caractères au moins). La variante `_FICHIER` lit le jeton dans un fichier (secret monté) |
| `MEDIANNUAIRE_DONNEES` | `/donnees/praticiens.csv` | Fichier CSV (séparateur `;`, UTF-8), en lecture seule |
| `MEDIANNUAIRE_CACHE_DIR` | `/var/cache/mediannuaire` | Dossier où l'index est mis en cache. **Doit être inscriptible** : sans lui, le service refuse de démarrer |
| `MEDIANNUAIRE_PORT` | `8080` | Port d'écoute (toutes interfaces) |
| `MEDIANNUAIRE_LOG_LEVEL` | `INFO` | Niveau des journaux (JSON sur la sortie standard) |
| `MEDIANNUAIRE_VERSION` | `dev` | Version affichée par `/sante` et les métriques |
| `MEDIANNUAIRE_DELAI_ARRET` | `10` | Secondes laissées aux requêtes en cours après SIGTERM |

Codes de sortie : 0 arrêt normal, 2 configuration invalide, 3 données ou cache inutilisables.

## Commandes

```
admin@adm01:~/src/annuaire$ uv sync --locked
admin@adm01:~/src/annuaire$ uv run python -m unittest discover -s tests
admin@adm01:~/src/annuaire$ MEDIANNUAIRE_JETON_ADMIN=$(openssl rand -hex 16) MEDIANNUAIRE_DONNEES=donnees/praticiens.csv \
    MEDIANNUAIRE_CACHE_DIR=/tmp/annuaire-cache uv run mediannuaire
admin@adm01:~/src/annuaire$ uv run mediannuaire sonde ; echo $?     # 0 si /sante répond
```

`mediannuaire sonde` interroge `http://127.0.0.1:$MEDIANNUAIRE_PORT/sante` et rend 0 ou 1 : c'est la commande de sonde de santé à utiliser dans une image sans `curl`.

## Arrêt propre

SIGTERM (ou SIGINT) : plus de nouvelle connexion, les requêtes en cours ont `MEDIANNUAIRE_DELAI_ARRET` secondes, puis sortie avec le code 0. Le processus doit recevoir le signal lui-même (PID 1 du conteneur).

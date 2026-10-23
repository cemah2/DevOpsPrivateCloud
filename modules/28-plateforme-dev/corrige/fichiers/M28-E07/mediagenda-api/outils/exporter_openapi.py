"""mediagenda/api — outils/exporter_openapi.py (M28-E07, PLAT-2907).

Écrit sur la sortie standard le document OpenAPI de l'API, tel que FastAPI le génère, sans démarrer
le serveur ni se connecter à PostgreSQL ou Valkey (le cycle de vie n'est pas exécuté : seules les
routes et les modèles sont lus). Sortie triée et stable : le fichier openapi.json du dépôt se
compare en CI (un écart = le contrat a changé sans que le fichier suive).

Usage : uv run python outils/exporter_openapi.py > openapi.json
"""

import json
import sys

from mediagenda.app import create_app
from mediagenda.config import Settings

# Adresses factices : create_app ne s'y connecte qu'au démarrage du serveur (lifespan).
REGLAGES = Settings.depuis_env(
    {
        "MEDIAGENDA_DB_URL": "postgresql://openapi:openapi@localhost:5432/openapi",
        "MEDIAGENDA_VALKEY_URL": "redis://localhost:6379/0",
        "MEDIAGENDA_VERSION": "contrat",
    }
)

json.dump(create_app(REGLAGES).openapi(), sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
sys.stdout.write("\n")

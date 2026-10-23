# mediagenda/api — src/mediagenda/app.py : EXTRAIT (F7-S10, PLAT-3710 ; clôt DEV-2226 du M21).
# Seaux EXPLICITES de l'histogramme des durées : ceux du client Python par défaut, plus 0,3 s (seuil
# d'ENF-05 du GHSV) et 0,2 s. Additif : les séries des seaux existants ne changent pas ; une série
# le="0.3" (et le="0.2") apparaît. Coût : 2 séries de plus par couple (méthode, route).
#
# Remplacer la déclaration de DUREES par :
from prometheus_client import Histogram

SEAUX_DUREES = (0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.2, 0.25, 0.3, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0)

DUREES = Histogram(
    "mediagenda_http_request_duration_seconds",
    "Durée de traitement des requêtes HTTP",
    ["methode", "route"],
    buckets=SEAUX_DUREES,
)

# Test à ajouter (tests/test_api.py) :
#   def test_seau_du_contrat(client):
#       client.get("/api/v1/creneaux", params={"date": "2026-11-02"})
#       texte = client.get("/metrics").text
#       assert 'le="0.3"' in texte and 'le="1.0"' in texte

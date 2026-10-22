"""Tests de bin/dora.py sur des réponses d'API enregistrées (sans réseau)."""
import datetime as dt
import importlib.util
import pathlib

_chemin = pathlib.Path(__file__).resolve().parents[1] / "bin" / "dora.py"
_spec = importlib.util.spec_from_file_location("dora", _chemin)
dora = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dora)

MAINTENANT = dt.datetime(2026, 10, 30, tzinfo=dt.timezone.utc)


class FauxGitLab:
    def __init__(self):
        self.reponses = {
            "projects/mediagenda%2Fdeploiement/deployments": [
                {"status": "success", "sha": "a1", "finished_at": "2026-10-10T10:00:00Z"},
                {"status": "failed", "sha": "a2", "finished_at": "2026-10-12T10:00:00Z"},
                {"status": "success", "sha": "a3", "finished_at": "2026-10-14T10:00:00Z"},
                {"status": "success", "sha": "a4", "finished_at": "2026-10-20T10:00:00Z"},
            ],
            "projects/mediagenda%2Fdeploiement/repository/commits/a1/merge_requests": [{"source_branch": "promotion/dev-v1.4.0"}],
            "projects/mediagenda%2Fdeploiement/repository/commits/a3/merge_requests": [{"source_branch": "promotion/dev-v1.5.0"}],
            "projects/mediagenda%2Fdeploiement/repository/commits/a4/merge_requests": [{"source_branch": "promotion/dev-v1.4.0"}],
            "projects/mediagenda%2Fapi/repository/tags/v1.4.0": {"commit": {"committed_date": "2026-10-10T06:00:00Z"}},
            "projects/mediagenda%2Fapi/repository/tags/v1.5.0": {"commit": {"committed_date": "2026-10-14T08:00:00Z"}},
            "projects/mediagenda%2Fapi/issues": [
                {"created_at": "2026-10-20T11:00:00Z", "closed_at": "2026-10-20T13:00:00Z"},
                {"created_at": "2026-10-25T11:00:00Z", "closed_at": None},
            ],
        }

    def get(self, chemin, **_):
        return self.reponses[chemin]

    def pages(self, chemin, **_):
        return self.reponses[chemin]


def test_quatre_indicateurs():
    r = dora.calculer(FauxGitLab(), "mediagenda/deploiement", "mediagenda/api", "dev", 30, MAINTENANT)
    assert r["deploiements_reussis"] == 3
    assert r["frequence_par_jour"] == 0.1
    # délais : 4 h (v1.4.0), 2 h (v1.5.0), 244 h (redéploiement de v1.4.0) → médiane 4 h
    assert r["delai_median_h"] == 4.0
    # 1 échec + 1 retour arrière (v1.5.0 → v1.4.0) sur 4 tentatives
    assert r["retours_arriere"] == 1
    assert r["taux_echec"] == 0.5
    assert r["retablissement_median_h"] == 2.0
    assert r["incidents_ouverts"] == 1


def test_markdown_sans_donnees():
    r = {"fenetre_jours": 30, "deploiements_reussis": 0, "frequence_par_jour": 0.0, "delai_median_h": None,
         "echecs": 0, "retours_arriere": 0, "taux_echec": None, "incidents": 0, "incidents_ouverts": 0,
         "retablissement_median_h": None}
    assert "n. d." in dora.markdown(r, "x/y", "dev")

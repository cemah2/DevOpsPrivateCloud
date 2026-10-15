"""Tests sans réseau extérieur : bibliothèque standard (unittest), lancés par
« uv run python -m unittest discover -s tests »."""

import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from mediannuaire.annuaire import Annuaire, ErreurDonnees
from mediannuaire.config import ErreurConfiguration, Reglages
from mediannuaire.serveur import creer_serveur

DONNEES = Path(__file__).resolve().parent.parent / "donnees" / "praticiens.csv"
JETON = "jeton-de-test-0123456789"


class TestConfiguration(unittest.TestCase):
    def test_jeton_obligatoire(self):
        with self.assertRaises(ErreurConfiguration):
            Reglages.depuis_env({})

    def test_jeton_par_fichier(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write(JETON + "\n")
        try:
            r = Reglages.depuis_env({"MEDIANNUAIRE_JETON_ADMIN_FICHIER": f.name})
            self.assertEqual(r.jeton_admin, JETON)
            self.assertEqual(r.port, 8080)
        finally:
            os.unlink(f.name)


class TestAnnuaire(unittest.TestCase):
    def test_chargement_et_cache(self):
        with tempfile.TemporaryDirectory() as cache:
            a = Annuaire(DONNEES, Path(cache))
            self.assertEqual(a.charger(), 8)
            self.assertEqual(len(a.liste("cardiologie")), 2)
            self.assertEqual(len(list(Path(cache).glob("index-*.json"))), 1)
            # Second chargement : index relu depuis le cache.
            self.assertEqual(Annuaire(DONNEES, Path(cache)).charger(), 8)

    def test_cache_non_inscriptible(self):
        with tempfile.TemporaryDirectory() as d:
            ro = Path(d) / "ro"
            ro.mkdir(mode=0o500)
            if os.geteuid() == 0:
                self.skipTest("root écrit partout")
            with self.assertRaises(OSError):
                Annuaire(DONNEES, ro / "cache").charger()

    def test_fichier_absent(self):
        with self.assertRaises(ErreurDonnees):
            Annuaire(Path("/nulle/part.csv"), Path(tempfile.gettempdir())).charger()


class TestServeur(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cache = tempfile.TemporaryDirectory()
        annuaire = Annuaire(DONNEES, Path(cls.cache.name))
        annuaire.charger()
        cls.serveur = creer_serveur(annuaire, 0, JETON, "test")
        cls.base = f"http://127.0.0.1:{cls.serveur.server_address[1]}"
        threading.Thread(target=cls.serveur.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.serveur.shutdown()
        cls.serveur.server_close()
        cls.cache.cleanup()

    def get(self, chemin):
        with urllib.request.urlopen(self.base + chemin, timeout=5) as r:
            return r.status, r.read().decode()

    def test_sondes(self):
        self.assertEqual(self.get("/sante")[0], 200)
        self.assertEqual(self.get("/pret")[0], 200)

    def test_liste_et_detail(self):
        code, corps = self.get("/api/v1/praticiens?specialite=pédiatrie".replace("é", "%C3%A9"))
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(corps)[0]["id"], "p004")
        with self.assertRaises(urllib.error.HTTPError) as e:
            self.get("/api/v1/praticiens/inconnu")
        self.assertEqual(e.exception.code, 404)

    def test_rechargement_protege(self):
        req = urllib.request.Request(self.base + "/admin/recharger", method="POST")
        with self.assertRaises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(req, timeout=5)
        self.assertEqual(e.exception.code, 401)
        req.add_header("Authorization", f"Bearer {JETON}")
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertEqual(r.status, 200)

    def test_metriques(self):
        self.assertIn("mediannuaire_praticiens 8", self.get("/metrics")[1])


if __name__ == "__main__":
    unittest.main()

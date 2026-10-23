"""Tests unitaires du service (bibliothèque standard)."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import app  # noqa: E402


class TestRoutes(unittest.TestCase):
    def test_route_bornee(self):
        self.assertEqual(app._route("/sante"), "/sante")
        self.assertEqual(app._route("/api/v1/salles?x=1"), "/api/v1/salles")
        self.assertEqual(app._route("/n/importe/quoi"), "autre")

    def test_metriques_cumulatives(self):
        app._mesurer("GET", "/sante", 200, 0.02)
        texte = app._metriques()
        self.assertIn('consultation_http_requests_total{methode="GET",route="/sante",code="200"}', texte)
        self.assertIn('le="0.01"} 0', texte)
        self.assertIn('le="0.025"} 1', texte)


if __name__ == "__main__":
    unittest.main()

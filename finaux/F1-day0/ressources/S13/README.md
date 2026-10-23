# F1-S13 — Évolution DEV-3113 (fournie par l'équipe MédiAgenda)

> **Demande DEV-3113** — *De : Julien Petit*
> Ajouter à la réponse de `GET /api/v1/creneaux` le champ **`nombre`** (nombre de créneaux libres de la liste `libres`). Évolution compatible : aucun champ retiré ni renommé, aucun changement de schéma de base, aucune variable de configuration nouvelle. Une réponse déjà en cache dans Valkey (écrite par la version précédente, sans le champ) doit rester servie, avec le champ.

Ce dossier contient le changement de code, prêt à être reporté dans **ton** dépôt `mediagenda/api`. Le code de référence de `apps/mediagenda` du workbook n'est pas modifié.

| Fichier | Contenu | Usage |
|---|---|---|
| `DEV-3113.patch` | Différence au format `git diff` contre `apps/mediagenda` (modèle `Creneaux` + nouveau fichier de tests) | `git apply --check` puis `git apply` dans ta copie de `mediagenda/api`, sur une branche |
| `mediagenda-api/modeles-Creneaux.extrait.py` | La classe `Creneaux` complète après le changement (import `computed_field` de `pydantic` à ajouter en tête de `modeles.py`) | À reporter à la main si le correctif ne s'applique pas (ton `modeles.py` a évolué aux modules 23 et 27) |
| `mediagenda-api/tests/test_creneaux_nombre.py` | Quatre tests (champ présent, suit les réservations, réponse en cache d'une version précédente, champ non imposable en entrée) | À copier tel quel dans `tests/` ; il utilise les doublures de `tests/conftest.py` |

Vérifié contre le code de référence : `uv run pytest` (31 tests réussis), `uv run ruff check .`, `uv run ruff format --check .`.

Le message de commit suit tes conventions (Conventional Commits : `feat(creneaux): nombre de créneaux libres (DEV-3113)`), pour que semantic-release publie une version **mineure**.

Ce qui t'est demandé n'est pas d'écrire ce code, c'est de le **livrer** par le chemin normal sur la plateforme reconstruite (voir l'énoncé de F1-S13).

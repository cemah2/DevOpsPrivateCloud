# Contrat d'interface du GHSV — origine

| | |
|---|---|
| Fichier | `api-rendez-vous-v1.yaml` (OpenAPI 3.1.0, `info.version` 1.0.0) |
| Origine | Annexe A1 du CCTP GHSV-DSI-2026-014, profil d'acheteur du GHSV, téléchargée le <AAAA-MM-JJ> par <MOI> |
| Statut | **Non négociable** pour la v1 (EF-05). Questions et réserves : `docs/capstone/api/ecarts-contrat-v1.md` de `plateforme/medisphere` |
| Copie de référence | `ghsv/contrat-api` (groupe GitLab du compte GHSV), étiquette `v1.0.0` |

Empreinte du fichier tel que reçu (calculée avec `sha256sum api-rendez-vous-v1.yaml`, vérifiée par `tests/test_contrat_ghsv.py::test_contrat_intact` et par le job `contrat:ghsv`) :

- sha256 : `<SHA256-DU-CONTRAT>`

**Règle** : ce fichier n'est **jamais** modifié dans ce dépôt. Une nouvelle version du contrat (1.1, R-06 du GHSV ; 2.0) arrive comme un **nouveau** fichier (`api-rendez-vous-v1.1.yaml`), avec sa ligne ici et ses tests, par une MR relue par Julien Petit et Karim Benali (RB-373). Les deux versions restent testées tant qu'elles sont servies.

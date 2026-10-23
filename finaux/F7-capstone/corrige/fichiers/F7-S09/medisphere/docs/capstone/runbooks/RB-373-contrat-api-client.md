# RB-373 — Faire évoluer le contrat d'API d'un client

| | |
|---|---|
| Portée | API de MédiSphère consommée par un client sous contrat (GHSV : API de rendez-vous v1) |
| Déclencheur | demande d'évolution (client ou MédiSphère), nouvelle version du contrat reçue, rupture détectée par la CI ou en production |
| Rôles | Julien Petit (MédiAgenda, auteur et relecteur), Karim Benali (relecteur), responsable du compte (communication au client) |
| Références | `docs/capstone/api/versionnage.md`, `ecarts-contrat-v1.md`, EF-05, EXP-05, EXP-06 du GHSV |
| Créé | F7-S09 (DEV-3709) |

## 1. Une demande d'évolution arrive

1. Écrire la demande dans un ticket `DEV-` : opération, besoin, client(s) concerné(s).
2. Classer le changement (versionnage.md §1) : compatible ou non. En cas de doute : **incompatible**.
3. Compatible → §2. Incompatible → §3.

## 2. Changement compatible (mineure ou corrective)

1. Si le client fournit une nouvelle version de son contrat : la déposer **comme nouveau fichier** dans `mediagenda/api/contrats/<client>/` (jamais en écrasant l'ancien), empreinte dans `ORIGINE.md`.
2. MR de l'API : code, tests unitaires, **tests de contrat** de la nouvelle version (copie de `test_contrat_<client>.py` paramétrée par le fichier). Les tests de l'ancienne version restent.
3. Pipeline vert (jobs `contrat:*` compris) ; relecture Julien + Karim.
4. Livraison en recette du client par la promotion normale ; annonce au client (ticket commun, EXP-01) **au moins 10 jours ouvrés** avant la production (EXP-06).
5. Promotion en production (MR approuvée, synchronisation manuelle de `<client>-prod` dans la fenêtre).
6. Ligne dans le rapport mensuel (« changements réalisés »).

## 3. Changement incompatible (nouvelle majeure)

1. Écrire la note de migration (différences, exemples avant/après) et la date de fin envisagée de l'ancienne majeure (≥ 12 mois après la mise en production de la nouvelle : EF-05).
2. Présenter au comité de suivi du client (EXP-04) ; décision écrite.
3. Implémenter `/api/v<N+1>` **à côté** de `/api/v<N>` (couche d'adaptation), avec son contrat et ses tests ; les tests de `v<N>` restent verts.
4. Recette, annonce, production comme au §2.
5. Sur `v<N>` : en-têtes `Deprecation` et `Sunset`, suivi du trafic par version dans le rapport mensuel.
6. Retrait de `v<N>` seulement quand les deux conditions de versionnage.md §3 sont remplies ; MR qui retire les routes **et** les tests de `v<N>` ; communication au client.

## 4. La CI refuse une MR (job `contrat:*` rouge)

1. Lire le rapport JUnit du job (`contrat:ghsv`) ou la sortie d'oasdiff (`contrat:compatibilite:oasdiff`) : quelle opération, quel champ.
2. Si la MR casse le contrat : corriger la MR. **Jamais** modifier le fichier du contrat, ni marquer le job `allow_failure`, ni retirer le test.
3. Si le contrat lui-même paraît faux ou ambigu : question écrite au client, décision provisoire dans `ecarts-contrat-v1.md`, le test reste.

## 5. Rupture constatée en production

1. Incident P2 au moins : retour arrière de la version (promotion inverse dans `overlays/clients/<client>-prod`).
2. Message au client (ticket commun).
3. Post-mortem : quel test de contrat aurait dû l'attraper ; l'ajouter.

## Vérifications

- `uv run pytest -m contrat` vert en local et en CI.
- `lab/bin/check F7 9` vert.

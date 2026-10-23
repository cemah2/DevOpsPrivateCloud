# Annexes de preuves — dossier GHSV

> Une ligne par preuve citée dans le dossier. Emplacements : `plateforme/medisphere` (chemins relatifs), MR GitLab (`!nn` du projet nommé), objets du compartiment verrouillé `preuves-conformite` (collectés, horodatés et signés par `ms-preuves`, F6 ; identifiant = clé de l'objet `lots/<AAAA>/<MM>/<JJ>/<LOT>/preuves/P-CAP-nn.<format>`, domaine `CAP` du catalogue). Aucune donnée personnelle ni secret.

| ID | Exigence | Nature | Emplacement | Date | Ce qu'elle prouve |
|---|---|---|---|---|---|
| P-01 | EF-01, ESC-06 | locataire en code | `plateforme/equipes` `equipes/ghsv.yaml`, MR `plateforme/equipes!<NN>` ; rendu de `equipes/ghsv.yaml` dans le pipeline de `main` | `<DATE>` | une MR crée tout ce que reçoit le client |
| P-02 | EF-01 | description OpenAPI de la recette | `/openapi.json` de `ghsv-recette` (constat de la recette, `docs/capstone/recette.md`) | | marque blanche de l'API |
| P-05 | EF-05 | pipeline de `mediagenda/api` | MR `mediagenda/api!<NN>` (correctifs du contrat) ; rapport JUnit `contrat:ghsv`, objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-06.xml` | | les tests de contrat passent |
| P-06 | EF-05 | MR fautive refusée | MR `mediagenda/api!<NN>` (fermée), job `contrat:ghsv` en échec | | une rupture du contrat ne fusionne pas |
| P-07 | ENF-02 | charge | `plateforme/resilience` `charge/resultats/…` ; séries `testid=demo-ghsv-<AAAAMMJJ>` | | coût par requête mesuré (base du dimensionnement) |
| P-08 | ENF-03, ENF-05, EXP-03 | rapport mensuel | `docs/capstone/rapports/ghsv-<AAAA-MM>.md`, MR `plateforme/medisphere!<NN>` ; objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-01.md` | | disponibilité et latence calculées sans saisie |
| P-09 | ENF-03 | SLO | `plateforme/observabilite` `slo/ghsv-*.yaml` | | objectifs pilotés en continu |
| P-10 | ENF-05 | écart client/serveur | résumé k6 de la journée de jeu (p95 client et serveur) | | la mesure serveur est représentative |
| P-22 | ENF-03, EXP-02 | journée de jeu sous incidents | `docs/qualite/journees-de-jeu/<AAAA-MM-JJ>-demonstration-ghsv.md`, objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-03.md` | | détection, réparation et chiffrage d'incidents sous le regard du client |
| P-11 | ENF-06 | essai de reprise isolé | `docs/capstone/pra-ghsv.md` §2 ; objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-04.md` | | RPO et temps de reprise mesurés |
| P-12 | ENF-06, ENF-08 | exercice PRA | `docs/pra/exercices/2026-exercice-1/rapport.md` (F5) | | une reprise complète a eu lieu |
| P-13 | ESC-03 | cartographie des transferts | `docs/conformite/transferts-hors-eee.md` (F6) | | aucun transfert hors EEE non déclaré |
| P-14 | ESC-04 | cloisonnement des agents | `docs/capstone/identite-federee.md` §3 ; objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-05.md` | | un agent n'entre pas dans nos outils |
| P-15 | ESC-04 | révocation chronométrée | `docs/capstone/identite-federee.md` §4 (agent désactivé à `<HH:MM>`, refusé à `<HH:MM>`) | | délai < 15 min |
| P-16 | ESC-06 | configuration des clés | objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-07.json` (métadonnées, sans clé) | | non exportables, non supprimables, rotation |
| P-17 | ERV-02, ERV-03 | essai de réversibilité | `docs/capstone/reversibilite/<AAAA-MM-JJ>.md`, objet `preuves-conformite/lots/…/<LOT>/preuves/P-CAP-02.md` ; empreinte de l'archive `<SHA-256>` | | export ouvert, relu dans une base vierge |
| P-18 | ESC-08 | journaux inaltérables | `docs/conformite/ecarts/ECA-3601.md` (F6) | | conservation un an, verrouillage |
| P-19 | ESC-10 | réponse à incident | `docs/securite/incidents/INC-6211/` (F6) | | un incident a été traité et notifié |
| P-20 | ERV-04 | destruction de clé | procès-verbal d'essai (clé `transit/essai-destruction`), journal d'audit d'OpenBao | | la destruction cryptographique se prouve |
| P-21 | — | recette | `docs/capstone/recette.md`, étiquette `capstone-v1` | | tout se rejoue depuis le code |

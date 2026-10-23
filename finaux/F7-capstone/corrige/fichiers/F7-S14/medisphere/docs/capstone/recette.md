# Recette `capstone-v1`

> F7-S14 (PLAT-3714). Recette de la preuve de concept GHSV avant l'envoi du dossier. Réalisée le `<AAAA-MM-JJ>` par `<MOI>`, relue par Karim Benali et Sophie Laurent. Étiquette posée : `capstone-v1` sur `plateforme/medisphere`.

## 1. Idempotence (« rien à changer »)

| Contrôle | Commande | Attendu | Résultat |
|---|---|---|---|
| Rendu de l'équipe en code | `uv run outils/rendre.py` puis comparaison avec les dépôts cibles (job `propager` à blanc) | aucune MR ouverte | `<OK / écart>` |
| Royaume `medisphere` | `tofu plan` (`plateforme/identite/tofu`) | « No changes » | |
| Royaume `ghsv-idp` (simulation) | `tofu plan` (`simulations/ghsv-idp`) | « No changes » | |
| Coffre | `tofu plan` (`plateforme/secrets/tofu`) | « No changes » | |
| Argo CD | Applications `ghsv-recette`, `ghsv-prod`, `equipes-k8s`, `equipes-gitops`, `oauth2-proxy`, `observabilite` | `Synced` / `Healthy` | |
| Pipelines de `main` | `equipes`, `identite`, `secrets`, `k8s`, `gitops`, `observabilite`, `outils`, `mediagenda/api`, `mediagenda/deploiement`, `medisphere` | verts | |

## 2. Reconstruction de `ghsv-recette` depuis le code

⚠️ Données fictives seulement. `ghsv-prod`, MédiAgenda et les autres locataires ne sont pas touchés : vérification avant et après (`lab/bin/check F7 11`, sonde de MédiAgenda).

| Étape | Heure | Durée | Geste manuel ? |
|---|---|---|---|
| Suppression de l'Application `ghsv-recette` (sans ses objets), puis de l'espace (RB-320 § Départ, appliqué à un seul environnement) | `<HH:MM>` | | oui (prévu par le runbook) |
| Recréation de l'espace par l'Application `equipes-k8s` (auto-synchronisation) | | | non |
| Recréation de l'Application par l'ApplicationSet `client-ghsv` | | | non |
| Secrets (ESO) disponibles | | | non |
| Base vide initialisée, migrations Flyway jouées (hook) | | | non |
| Données de démonstration chargées (Job de jeu de données de l'overlay de recette) | | | non |
| Mandataires prêts, `/pret` à 200, connexion d'`agent.demo1` | | | non |
| **Total** | | `<MIN>` | `<N>` geste(s) |

Chaque geste manuel imprévu est un écart (§4).

## 3. Preuves collectées par `ms-preuves`

| Preuve | Objet dans `preuves-conformite` |
|---|---|
| Rapport mensuel du client | `capstone/<…>/rapport-ghsv-<AAAA-MM>.md` |
| Essai de réversibilité (compte rendu, empreinte) | `capstone/<…>/reversibilite-<AAAA-MM-JJ>.md` |
| Compte rendu de la journée de jeu | `capstone/<…>/journee-de-jeu-<AAAA-MM-JJ>.md` |
| Essai de reprise de PAR2 | `capstone/<…>/essai-reprise-ghsv.txt` |
| Constat de cloisonnement des identités | `capstone/<…>/cloisonnement/` |
| Pipelines du contrat (rapport JUnit) | `capstone/<…>/contrat-ghsv-junit.xml` |
| Configuration des clés `transit/ghsv-*` (métadonnées) | `capstone/<…>/cles-transit-ghsv.json` |

Identifiants reportés dans `soutenance/annexes-preuves.md`.

## 4. Écarts restants et suite

| ID | Écart | Suite | Responsable | Échéance |
|---|---|---|---|---|
| E-1 | Identité absente à PAR2 pendant un PRA | Keycloak de repli dans le RB-350 | Karim | avant la mise en service |
| E-2 | Clés du client non appliquées à la base et aux archives | chiffrement applicatif (ADR-0371), SSE-KMS | Julien, Karim | lot de construction |
| E-3 | Jours fériés absents du contrôle des maintenances | calendrier dans `ms-rapport-client` | `<MOI>` | avant le premier rapport |
| E-4 | `/pret` dépend du cache (journée de jeu) | correctif de `mediagenda/api` | Julien | prochaine version |
| E-5 | `<…>` | | | |

## 5. Plan de la suite

Contrôles F7 7 à 12 verts le `<AAAA-MM-JJ>` ; dossier envoyé au GHSV le `<AAAA-MM-JJ>` ; reconstruction hebdomadaire de `ghsv-recette` planifiée (pipeline) jusqu'à la notification.

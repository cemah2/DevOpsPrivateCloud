# Normes de conteneurisation de MédiSphère

| | |
|---|---|
| **Statut** | En vigueur |
| **Version** | 1.0 — 2026-10 (M12-E33, ticket PLAT-1359) |
| **Propriétaire** | Équipe Plateforme (Claire Morel) ; relecteurs : Sophie Laurent (sécurité), Julien Petit (équipes de développement), Karim Benali (exploitation) |
| **Revue** | semestrielle, et à chaque ADR qui touche les conteneurs |

Niveaux : **DOIT** (obligatoire, bloquant), **DEVRAIT** (attendu ; un écart se justifie dans la MR), **NE DOIT PAS** (interdit, bloquant). Contrôles : `CI` (job bloquant du gabarit), `REV` (revue de MR, grille ci-dessous), `SONDE` (`ms-verif-conteneurs`), `CHECK` (vérification d'exploitation), `ADM` (admission Kubernetes, à partir du M26).

## 1. Objet et périmètre

S'applique à toute image construite par MédiSphère et à tout conteneur exécuté **hors Kubernetes** (serveurs de recette et d'outillage, registre, CI) à partir du 2026-11-01. Les règles d'images (§2, §3, §5) valent aussi pour Kubernetes ; l'exécution sous Kubernetes (Pod Security, politiques) relève des documents `docs/kubernetes/` (M14+), qui reprennent les règles `CNT-RUN-*`. Les choix de moteur sont dans l'ADR-0120.

## 2. Images

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-IMG-01` Partir d'une image de la **liste des images autorisées** (`plateforme/images-base`), à chaque `FROM` (étapes de construction comprises) | DOIT | images de base maîtrisées, corrigées chaque semaine (`images-de-base.md`) | CI `images-autorisees` |
| `CNT-IMG-02` Épingler l'image de base par **étiquette datée et empreinte** (`…:3.13-trixie-AAAAMMJJ@sha256:…`) | DOIT | construction reproductible, montée de version par MR | CI `images-autorisees` (motif `@sha256:`) |
| `CNT-IMG-03` Noms d'images **complets** (registre compris) dans tout fichier livré | DOIT | pas de résolution de nom court ambiguë (Podman `short-name-mode`) | CI `images-autorisees`, REV |
| `CNT-IMG-04` Construction **multi-étapes** : compilateurs, gestionnaires de paquets de langage et sources hors de l'image finale | DEVRAIT | surface d'attaque, taille | REV, Dive (`.dive-ci`) |
| `CNT-IMG-05` Dernier `USER` **numérique et non nul** (UID ≥ 10000, propre à l'application) | DOIT | non root ; vérifiable par `runAsNonRoot` (M14) | CI Hadolint (DL3002, DL3066 en erreur), CHECK |
| `CNT-IMG-06` Étiquettes OCI `title`, `version`, `revision`, `source`, `vendor`, `base.name` | DOIT | traçabilité jusqu'à l'image amont | CI Hadolint (`label-schema`), REV |
| `CNT-IMG-07` `CMD`/`ENTRYPOINT` en **forme exec** ; le processus principal reçoit SIGTERM et s'arrête proprement dans le délai de grâce (≤ 20 s) | DOIT | arrêt propre, mises à jour sans perte (E17, E30) | CI Hadolint (DL3025), REV, essai `docker stop` |
| `CNT-IMG-08` Une **sonde de santé** (`HEALTHCHECK` de l'image ou de l'orchestration), qui ne dépend pas des services externes | DOIT | détection des pannes (E18, E28), retour arrière (E30) | SONDE (conteneur attendu sans sonde = KO), REV |
| `CNT-IMG-09` `.dockerignore` en **liste blanche** (`*` puis `!…`) | DOIT | ni secrets, ni `.git`, ni artefacts locaux dans le contexte | REV |
| `CNT-IMG-10` Aucune donnée secrète dans une couche, un `ARG`, un `ENV` ou une étiquette ; secrets de construction par `RUN --mount=type=secret` | NE DOIT PAS (secret en couche) | une couche publiée est publique pour qui tire l'image | CI Gitleaks (M01), REV ; analyse de l'image au M13 |
| `CNT-IMG-11` Ni `ADD <URL>`, ni `curl … \| sh`, ni téléchargement sans somme de contrôle | NE DOIT PAS | chaîne d'approvisionnement | CI Hadolint (DL3020), REV |
| `CNT-IMG-12` Hadolint sans avertissement (`.hadolint.yaml` de MédiSphère) ; dérogation **ligne par ligne** avec sa raison | DOIT | qualité homogène | CI Hadolint |
| `CNT-IMG-13` Efficacité Dive ≥ 0,95, gaspillage ≤ 10 Mio | DEVRAIT | couches propres (E16) | CI Dive |
| `CNT-IMG-14` Multi-architectures (amd64, arm64) quand l'amont l'est | DEVRAIT | portabilité (E12) | REV |

## 3. Construction et publication

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-PUB-01` Images publiées **par la CI** seulement (gabarit `image.yml`, BuildKit sans privilège sur `runner02`) | DOIT | traçabilité, pas d'image « de poste » en recette | registre : compte `ci` seul en écriture (M13 : robots) |
| `CNT-PUB-02` Étiquette de version **immuable** (`X.Y.Z`, `trixie-AAAAMMJJ`) ; étiquette **mobile** (`recette`, `trixie`) documentée, jamais en production | DOIT | savoir ce qui tourne (RB-122) | CHECK, immuabilité Harbor (M13) |
| `CNT-PUB-03` `latest` | NE DOIT PAS | ne désigne rien de précis | CI Hadolint (DL3007), REV |
| `CNT-PUB-04` Un pipeline rouge (tests, Hadolint, images autorisées, construction) ne publie rien | DOIT | | CI |
| `CNT-PUB-05` Mode privilégié de l'exécuteur, socket du démon dans un job | NE DOIT PAS | root sur `runner02` (E20, E26) | `config.toml` de `runner02` (rôle `gitlab_runner`), CHECK |

## 4. Configuration et exécution

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-RUN-01` Configuration par **variables d'environnement** ; même image pour tous les environnements | DOIT | 12 facteurs (III), E19 | REV |
| `CNT-RUN-02` Utilisateur **non root** à l'exécution (`user:`, `User=`) | DOIT | E24 | CHECK, ADM (M26) |
| `CNT-RUN-03` `cap_drop: [ALL]` ; toute capacité ajoutée est justifiée dans le fichier | DOIT | E24 | REV, CHECK |
| `CNT-RUN-04` `no-new-privileges` | DOIT | neutralise les binaires setuid (E24) ; défaut du démon sur les hôtes Docker (E26) | CHECK |
| `CNT-RUN-05` Racine en **lecture seule** ; écritures dans des `tmpfs` bornés `noexec,nosuid,nodev` ou des volumes nommés | DOIT | pas de persistance d'un attaquant (E24) | REV, CHECK |
| `CNT-RUN-06` seccomp par défaut au minimum ; profil personnalisé versionné et régénéré à chaque version du moteur | DOIT (défaut) / DEVRAIT (personnalisé) | surface du noyau (E24) | REV |
| `CNT-RUN-07` Secrets à l'exécution par **fichier monté** (secrets Compose ou Podman, `_FILE`), jamais en clair dans `compose.yaml`, une unité ou `docker inspect` | DOIT | E08, E34 | REV, Gitleaks |
| `CNT-RUN-08` Limites de mémoire, CPU et nombre de processus | DOIT | un conteneur ne fait pas tomber l'hôte (E18) | REV |
| `CNT-RUN-09` Politique de redémarrage (`restart: unless-stopped`, `Restart=on-failure`) | DOIT | | REV |
| `CNT-RUN-10` Journaux en **JSON sur la sortie standard**, sans donnée personnelle ni de santé ; rotation par le moteur | DOIT | 12 facteurs (XI), RGPD, HDS | REV, échantillon des journaux |
| `CNT-RUN-11` Ports > 1024 dans le conteneur ; publication sur l'hôte limitée au nécessaire (adresse de boucle locale pour l'administration) | DEVRAIT | pas besoin de privilège, surface réseau | REV |
| `CNT-RUN-12` `--privileged`, `network_mode: host`, `pid: host`, `label=disable`, `seccomp=unconfined`, socket du démon monté | NE DOIT PAS | chacun annule une couche d'isolement | REV, CHECK, ADM (M26) |

## 5. Données

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-DON-01` Données persistantes dans des **volumes nommés** (ou un dossier de l'hôte étiqueté par la politique, E25) ; processus sans état | DOIT | 12 facteurs (VI), E07, E19 | REV |
| `CNT-DON-02` Bases : **export logique** quotidien vers PBS (`wb-backup-conteneurs`) ; copie de volume **à froid** seulement | DOIT | cohérence (E29) | CHECK (PBS < 48 h), test de restauration semestriel (RB-121) |
| `CNT-DON-03` Données de santé dans une image, un journal, un nom d'objet | NE DOIT PAS | HDS, RGPD | REV |

## 6. Exploitation

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-EXP-01` Tout conteneur de service est déclaré dans `ms-verif-conteneurs.conf` | DOIT | être prévenu (E28) | REV |
| `CNT-EXP-02` Mise à jour sans interruption (deux instances, script de E30, ou mise à jour automatique avec retour arrière par la santé) ; migrations compatibles avec N et N+1 | DEVRAIT | RB-122 | REV, charge témoin |
| `CNT-EXP-03` Reconstruction des images d'application dans les 5 jours ouvrés suivant une image de base corrigée d'une faille critique | DOIT | `images-de-base.md` | REV (MR d'empreinte) ; Renovate (M13) |
| `CNT-EXP-04` Chaque application a son runbook de redémarrage et de restauration (RB-120, RB-121, RB-122 en modèles) | DEVRAIT | | REV |

## 7. Hôtes et moteurs

ADR-0120 (Podman sans privilège sur les serveurs, Docker pour la CI et Harbor). Règles :

| Règle | Niveau | Justification | Contrôle |
|---|---|---|---|
| `CNT-HOTE-01` Groupe `docker` limité aux comptes qui ont déjà `sudo` (et au compte du runner) | DOIT | socket = root (E26) | CHECK |
| `CNT-HOTE-02` Démon Docker joignable en TCP | NE DOIT PAS | E26 | CHECK (`ss`) |
| `CNT-HOTE-03` SELinux *enforcing* sur la famille RHEL ; accès inhabituel par un module udica versionné ; pas de `:z`/`:Z` sur un dossier non dédié | DOIT | E25 | CHECK, REV |
| `CNT-HOTE-04` Audit des modifications du moteur (rôle `audit_conteneurs`) | DOIT | traçabilité (E26) | CHECK |

## 8. Exceptions et gestion du document

Une exception est demandée par MR sur ce dépôt (`docs/conteneurs/exceptions.md`) : règle, périmètre, raison, mesure compensatoire, **date de fin** (6 mois au plus), approbation de Sophie Laurent pour toute règle `NE DOIT PAS` ou `CNT-RUN-*`. Les exceptions échues sont retirées à la revue semestrielle. Exceptions en vigueur à la création : HAProxy de test de la recette (`CNT-IMG-08`, image sans `curl`, jusqu'à M14) ; images de base `bibliotheque/*` en root (`CNT-IMG-05`, ce sont des bases de construction, permanent).

**Correspondance règles → contrôles automatiques** : Hadolint (`CNT-IMG-05`, `06`, `07`, `11`, `12`, `CNT-PUB-03`) ; `images-autorisees` (`CNT-IMG-01` à `03`) ; Dive (`CNT-IMG-13`) ; Gitleaks (`CNT-IMG-10`, `CNT-RUN-07`) ; `ms-verif-conteneurs` (`CNT-IMG-08`, `CNT-EXP-01`) ; checks d'exploitation (`CNT-RUN-02` à `05`, `CNT-HOTE-*`, `CNT-DON-02`) ; au M13, analyse Trivy et signature à la publication ; au M26, admission Kubernetes (`CNT-RUN-02` à `06`, `12`).

### Grille de revue de MR (extrait)

- [ ] `FROM` autorisés et épinglés ; noms complets ; `.dockerignore` en liste blanche.
- [ ] `USER` numérique ; forme exec ; sonde de santé ; étiquettes OCI.
- [ ] `compose.yaml` / unité : `user`, `cap_drop: [ALL]`, `no-new-privileges`, `read_only` + `tmpfs`, limites, secrets en fichier, aucune option `CNT-RUN-12`.
- [ ] Conteneur ajouté à la sonde ; sauvegarde des données déclarée ; runbook.

# ADR-0190 — La chaîne d'intégration continue de MédiSphère

| | |
|---|---|
| Statut | **Acceptée** |
| Date | AAAA-MM-JJ |
| Auteur | <MOI> |
| Relecteurs | Karim Benali (approbation de la MR), Sophie Laurent, Claire Morel |
| Ticket | PLAT-2030 (M19-E30) |
| Remplace / complète | ADR-0120 (constructions sans privilège sur `runner02`), ADR-0130 (signature et registre) |

## Contexte

- Jusqu'au module 19, tous les pipelines tournaient sur un seul runner Docker (`runner02`, 4 Go) : file d'attente le matin, gabarits copiés d'un projet à l'autre, constructions concurrentes sur un même démon.
- Contraintes : édition **GitLab CE (Free)** ; lab de **≈ 100 Go** de mémoire pour tout le profil (blocs D et E) ; données de santé (**HDS**, ISO 27001) : traçabilité, moindre privilège, secrets maîtrisés ; souveraineté (rien hors du lab hormis le téléchargement de dépendances publiques) ; une petite équipe Plateforme (maintenance minimale).
- Ce que nous avons essayé dans le module : runners Kubernetes (E04-E08, E24, E27), composants CI/CD (E10), SonarQube Community Build 26.10 (E16), Jenkins LTS 2.580 (E19, E20), BuildKit *rootless* partagé (E08), mesures de durée et de capacité (E23, E27).

## Décision

1. **Moteur** : GitLab CI, runners dans `k8s-par1` (exécuteur Kubernetes) : `k8s-par1` (jobs ordinaires, `ci-jobs`) et `k8s-par1-protege` (références protégées : signature, promotion ; `ci-jobs-protege`). `runner02` reste pour l'étiquette `docker` (secours de construction par Buildah, projets hors standard), `runner01` pour les jobs `shell` du socle.
2. **Partage** : composants CI/CD versionnés de `plateforme/ci-templates` (`construction-image`, `qualite`, `securite`, `deploiement`, `promotion`), publiés au catalogue de l'instance, épinglés en version exacte par les projets ; socle imposé par un contrôle nocturne (E32).
3. **Constructions** : démon **BuildKit rootless partagé** (`buildkitd`, TLS mutuel, cache en registre Harbor). Pas de Docker-in-Docker, aucun conteneur privilégié. Buildah sur `runner02` en secours.
4. **Qualité et sécurité du code** : ruff, pytest et couverture dans GitLab, **Semgrep CE** (règles épinglées), Gitleaks, Trivy, SBOM Syft. **SonarQube non retenu.**
5. **Chaîne d'approvisionnement** : signature et attestations (SBOM, provenance SLSA v1) par le seul runner protégé, avec une clé montée par lui ; **porte de vérification** bloquante dans les MR des dépôts de déploiement.
6. **Livraison** : promotion par MR dans les dépôts de déploiement (jeton `ci-promotion` par dépôt) ; déploiement en dev par l'agent `k8s-par1` jusqu'au M20 (Argo CD).
7. **Jenkins non retenu.**

## Options écartées

### Jenkins LTS (E19, E20)

| Critère | GitLab CI (composants) | Jenkins (E20) |
|---|---|---|
| Lignes pour le pipeline de MédiAgenda | ≈ 25 (includes + entrées) | ≈ 140 (`Jenkinsfile`) + JCasC ≈ 120 |
| Durée du pipeline de MR mesurée | … min (E23) | … min (E20) |
| Mémoire au repos | gestionnaires ≈ 2 × 128 Mio | contrôleur ≈ 1,5 Gio + agents |
| Maintenance | une montée de GitLab par mois (déjà due) | contrôleur + ≈ 30 plugins à suivre (avis de sécurité réguliers) |
| Identité, droits, audit | ceux de GitLab (groupes, MR, journal d'audit) | une seconde base de comptes jusqu'au SSO (M24), droits par plugin |

Ce que Jenkins fait mieux : pipelines arbitrairement programmables (Groovy), écosystème d'intégrations très large, indépendance vis-à-vis de la forge. Raison du rejet : une seconde plateforme à maintenir et à sécuriser pour aucun besoin que GitLab CI ne couvre ; surface d'attaque des plugins.

### SonarQube Community Build 26.10 (E16)

Ce qu'il fait mieux : tableau de bord de dette technique, règles de qualité riches, historique. Raisons du rejet : en édition communautaire, **analyse de la seule branche principale**, pas de décoration des MR (le moment où l'information est utile) ; ≈ 4 Gio de mémoire demandés par défaut, une base PostgreSQL de plus (CNPG) ; plus d'analyse anonyme depuis 26.x (jetons à gérer). Ce qu'on perd : la vue de dette consolidée ; compensée en partie par la couverture et les rapports de MR de GitLab, Semgrep CE et ruff.

### Kaniko

Écarté **avant essai** : projet archivé par Google en juin 2025 (dernière version 1.24.0) ; le fork de maintenance (Chainguard) n'apporte pas de raison de choisir un outil sans avenir pour une chaîne neuve.

### Docker-in-Docker

Exige un conteneur privilégié : incompatible avec Pod Security `restricted` et avec ADR-0120.

### Un runner par équipe / un espace par job (`namespace_per_job`)

Meilleure isolation, mais quotas, politiques et RBAC à multiplier ; la séparation retenue (deux mondes : ordinaire et protégé) couvre le risque principal (clé de signature). À revoir si une équipe externe arrive (E31 Q2).

## Conséquences

- **Démontage** (mini-projet M19-E46) : releases `jenkins` et `sonarqube`, leurs espaces, la base CNPG `sonarqube-db`, les enregistrements DNS, les variables de CI associées (`SONAR_TOKEN`…) ; variables de groupe `COSIGN_*` (dernière exception de E24).
- **Dettes acceptées** : `CI_JOB_TOKEN` encore utile entre quelques projets (liste d'autorisation) ; secrets longue durée (jetons de promotion, robot Harbor) tournés à la main tous les 60 jours (RB-191) jusqu'au M25 (OpenBao, jetons d'identité) ; pas d'admission par signature dans le cluster avant le M26.
- **Exploitation** : RB-190 à RB-193 (puis RB-194 à RB-198, pannes du palier 4) ; capacité de 16 jobs simultanés (E27) ; montée de GitLab à chaque arrêt obligatoire au moins.

## Révision

Cette décision est à revoir si : MédiSphère passe en **GitLab Premium/Ultimate** (environnements protégés, approbations, politiques d'exécution de pipelines : E32 deviendrait natif) ; un besoin d'**analyse de qualité par MR** est exprimé par les équipes (SonarQube Developer Edition ou alternative) ; la charge dépasse durablement la capacité mesurée en E27 ; une équipe apporte des pipelines Jenkins impossibles à migrer à coût raisonnable (E31 Q14).

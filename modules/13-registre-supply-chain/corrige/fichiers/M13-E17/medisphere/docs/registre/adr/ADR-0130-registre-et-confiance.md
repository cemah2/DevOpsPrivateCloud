# ADR-0130 — Registre d'images et politique de confiance

| | |
|---|---|
| Statut | Accepté |
| Date | `<AAAA-MM-JJ>` |
| Décideurs | Claire Morel (responsable infrastructure), Sophie Laurent (RSSI), Karim Benali |
| Rédaction | `<MOI>` |
| Révision | à la mise en place de Vault (M25), de l'admission Kubernetes (M26), et au plus tard dans 12 mois |

## Contexte

MédiSphère publie ses applications en images de conteneurs (M12). Elles vivaient sur un registre de travail sans contrôle d'accès, et les images de base venaient directement de Docker Hub. HDS et ISO 27001 demandent de savoir **d'où vient** ce qui tourne en production, **ce qu'il contient**, **qui l'a validé**, et de pouvoir répondre vite à une alerte (incident Trivy de mars 2026, alerte CS-2026-0412 de M13-E18). Contraintes : auto-hébergé (souveraineté), lab sans dépendance obligatoire à Internet pour vérifier, une équipe plateforme de quatre personnes.

## Options — le registre

| Critère | **Harbor 2.15** | Registre de GitLab | CNCF Distribution nu (M12) | Registre de nuage public |
|---|---|---|---|---|
| Contrôle d'accès, comptes robots | projets, rôles, robots système et projet, durée de vie | lié aux projets GitLab, jetons de déploiement | `htpasswd` global | IAM du fournisseur |
| Caches des registres publics | oui (Docker Hub, Quay, GHCR, registre générique) | « dependency proxy » (Docker Hub seulement) | un seul amont par instance | selon fournisseur |
| Analyse intégrée | Trivy, à la poussée, SBOM | GitLab Ultimate | non | oui |
| Politique de signature au tirage | Cosign/Notation (présence) | non | non | selon fournisseur |
| Réplication | oui, filtrée, planifiée, accessoires compris | non | non (outils externes) | oui |
| Quotas, rétention, immuabilité | oui | partiel | non | oui |
| Exploitation | 9-10 conteneurs, PostgreSQL, Valkey ; mises à jour mensuelles | inclus dans GitLab (déjà exploité) | un conteneur | aucune |
| Souveraineté | oui | oui | oui | **non** (exclu HDS sans contrat dédié) |
| Mesuré dans le module | RPO réplication `<…>` (E13), RTO `<…>` (E15), refus 412 (E14) | — | — | — |

## Options — la signature

| Critère | **Cosign, clé MédiSphère** | Cosign sans clé (Fulcio + Rekor publics) | Sigstore privé (Fulcio + Rekor + TSA) | Notation (Notary Project) |
|---|---|---|---|---|
| Dépendance à Internet | aucune | à la signature et à la vérification | aucune | aucune |
| Fuite d'information | aucune | nom et digest des images, identité du pipeline dans un journal public **permanent** | interne | aucune |
| Gestion de clé | une clé privée à protéger (Vault critique, variable de CI) et à faire tourner | aucune clé longue durée (certificat de 10 min) | CA et journal à exploiter | certificats X.509, PKI MédiSphère possible |
| Révocation | rotation + re-signature (pas de liste de révocation) | identité OIDC révoquée ; entrées anciennes restent valides | idem, en interne | CRL/OCSP de la PKI |
| Preuve d'horodatage | **aucune** (signatures sans date opposable) | Rekor | Rekor/TSA privés | TSA RFC 3161 possible |
| Harbor 2.15 | oui (bundle v3, référents) | oui | oui | oui |
| Kubernetes (M26) | Kyverno `verifyImages` par clé | Kyverno par identité | idem | Kyverno/Ratify |
| Coût d'exploitation | faible | nul | **élevé** (3 services HA) | moyen |

## Décision

1. **Harbor 2.15** sur `reg01` est le registre unique de MédiSphère ; les images publiques passent par ses caches.
2. **Cosign 3 avec une clé MédiSphère**, sans journal de transparence (configuration de signature sans service, vérification avec `--insecure-ignore-tlog=true`). Sigstore privé est réexaminé au module 25 (identités de pipeline, Vault) et pour F6.
3. **Politique de confiance** : une image peut tourner en production si et seulement si :

| Règle | Où c'est vérifié | Comment |
|---|---|---|
| Elle vient du projet `medisphere` de `registry.par1.medisphere.internal` | admission (M14 : VAP ; M26 : Kyverno) | registre et projet imposés |
| Elle est désignée par son **digest** | gabarits de déploiement (M14-M20), admission (M26) | refus des étiquettes seules |
| Elle est signée par la **clé de la CI** | consommateur (`verification.yml`), admission (M26) ; Harbor vérifie seulement la présence | `cosign verify --key` |
| Sa SBOM SPDX et sa provenance sont attestées par la même clé | consommateur, puis admission | `cosign verify-attestation` |
| Son analyse ne montre aucune vulnérabilité Critical corrigeable | chaîne de livraison (blocage), Harbor (412 au tirage) | Trivy |
| Les exceptions sont datées et tracées | revue de MR | `cve_allowlist` par projet, ticket SEC- |

4. **Compromission de la clé privée** (procédure) :
   1. Déclarer l'incident (INC-, Sophie Laurent) ; geler les publications (variables de CI de signature désactivées).
   2. Générer une nouvelle paire (procédure de M13-E07), publier la nouvelle `cosign.pub` à côté de l'ancienne.
   3. **Période de recouvrement** : les consommateurs acceptent les deux clés (gabarit `verification.yml` et politique d'admission avec deux clés) le temps de re-signer.
   4. Inventorier les images en service (SBOM, Harbor) ; pour chacune, **vérifier sa provenance** (attestation, pipeline d'origine, digest) **avant** de la re-signer avec la nouvelle clé ; toute image dont la provenance ne se prouve pas est reconstruite.
   5. Retirer l'ancienne clé des consommateurs ; supprimer les signatures de l'ancienne clé dans Harbor si nécessaire ; post-mortem.

## Conséquences

- Une seule VM porte le registre : réplication (E13) et sauvegarde (E15) mesurées, copie à PAR2 aux finaux.
- La politique de Harbor ne vérifie pas l'auteur : la vérification par clé est obligatoire chez le consommateur.
- Les signatures n'ont pas de date opposable : on ne peut pas prouver qu'une signature est antérieure à une compromission. Accepté jusqu'à M25.

## Risques acceptés

| Risque | Propriétaire | Révision |
|---|---|---|
| Clé privée en variable de CI (lisible par un job malveillant d'un projet du groupe) | Sophie Laurent | M25 (signature par Vault Transit) |
| Pas d'horodatage ni de journal de transparence | Sophie Laurent | M25 / F6 |
| Pas de vérification à l'admission avant M26 | Claire Morel | M26 |
| Registre unique, un seul site | Claire Morel | finaux (PAR2) |
| Exemption de lecture avant la première signature (Harbor 2.15.3, `CONTENT_TRUST_LEGACY_SIGNER_PULL_ENABLED`) : une identité qui peut pousser dans `medisphere` peut aussi lire une image non signée en se présentant comme Cosign | Sophie Laurent | M26 (admission par clé) ; à chaque version de Harbor |

# Chaîne d'approvisionnement des images

| | |
|---|---|
| Ticket | SEC-2029 (M19-E29) |
| Propriétaire | Équipe Plateforme ; relecture : Sophie Laurent |
| Code | `plateforme/ci-templates` v2.2.0 : composants `construction-image`, `securite`, `deploiement` |
| Clé publique | `docs/registre/cosign.pub` (M13), empreinte épinglée dans les composants |

## 1. Ce qui est produit, par qui

| Étape | Job (composant) | Runner | Produit | Stocké |
|---|---|---|---|---|
| Construction | `image:construction` (`construction-image`) | `k8s` → buildkitd | archive OCI (index + manifeste d'attestation SLSA v1 de BuildKit, `mode=max`), `IMAGE_EMPREINTE` | artefact (1 jour) |
| Analyse | `securite:trivy` | `k8s` | rapport Trivy, refus si critique avec correctif | artefact (30 jours) |
| SBOM et provenance | `securite:sbom` | `k8s` | `sbom.spdx.json`, `sbom.cdx.json`, `provenance.json` (extrait de l'archive) | artefacts (1 an) |
| Publication | `image:publication` | `k8s` | image dans Harbor `medisphere`, `IMAGE_REF` par digest | Harbor (étiquette `vX.Y.Z` immuable) |
| Signature et attestations | `securite:signature` | **`protege`** (clé montée par le runner) | signature de l'index et des manifestes de plateforme ; attestations `spdxjson` et `slsaprovenance1` | Harbor, référents OCI de l'image (Cosign 3), sans journal public |
| Vérification (producteur) | `securite:verification` | `k8s` | contrôle signature + 2 attestations | journal du job |
| **Porte** (consommateur) | `deploiement:images` + `verifier-images` (`deploiement`) | `k8s` | `rapport-images.tsv` | artefact (1 an) |

## 2. Ce que la porte vérifie

Pour chaque image rendue par `kustomize build` de chaque overlay touché par la MR (tous les overlays si `base/` ou `components/` change) :

1. référence **par digest** ;
2. images de `medisphere/` et `bibliotheque/` : signature par la clé MédiSphère, attestation SBOM SPDX, attestation de provenance SLSA v1 produite par BuildKit (`buildDefinition.buildType`), label `org.opencontainers.image.source` sous `https://git01.par1.medisphere.internal/` ;
3. images tierces : présentes **à l'identique** (digest compris) dans `images-tierces.txt` du dépôt de déploiement, fichier relu par la Plateforme (`CODEOWNERS`).

Les deux jobs sont bloquants ; `mediagenda/deploiement` exige un pipeline réussi pour fusionner (`only_allow_merge_if_pipeline_succeeds`). Identité de lecture : robot `robot$medisphere+verification` (droit de tirage seul), variables `HARBOR_ROBOT_RO_USER`/`HARBOR_ROBOT_RO_TOKEN` **non protégées** (les pipelines de MR tournent sur des branches non protégées), masquées : exposition acceptée (lecture d'images déjà servies au cluster).

## 3. Ce qu'elle ne vérifie pas

- Le **contenu** de la provenance au-delà du type de constructeur et de la source (paramètres de construction, dépendances résolues) : à durcir avec `cosign verify-attestation --policy` (CUE/Rego).
- Qu'une clé n'a pas fuité : la révocation d'une clé Cosign sans journal de transparence passe par le changement de clé publique dans les composants (empreinte épinglée) et la re-signature (M13).
- Harbor lui-même : un administrateur de Harbor peut remplacer une étiquette… mais pas un digest ; la porte travaille par digest.
- Le déploiement lui-même : une image appliquée à la main (`kubectl apply` hors chaîne) n'est pas contrôlée ici ; c'est l'admission du cluster (Kyverno, M26) et l'interdiction des `apply` manuels (M20).
- Les images antérieures à E29 : la v2.0.0 des composants n'attestait pas la provenance. Décision : les images en service sont **reconstruites** par une version corrective (`vX.Y.Z+1`) avant d'activer la porte en bloquant ; aucune exception permanente.

## 4. Essai inverse (AAAA-MM-JJ)

| Cas | Résultat |
|---|---|
| Image construite sur `adm01`, poussée sans signature dans `plateforme/essai-porte` (projet sans politique de signature), référencée par digest dans `overlays/dev` | `verifier-images` en échec : « signature MédiSphère absente ou invalide » ; MR non fusionnable |
| Même image signée par une clé jetable | échec : signature invalide pour la clé MédiSphère |
| Image `medisphere/mediagenda-api` signée par la chaîne v2.1.0 (sans provenance attestée) | échec : « attestation de provenance (slsaprovenance1) absente » |
| Image par étiquette (`…:v1.6.0`) | échec : « image sans digest » |
| Promotion légitime (v2.2.0) | succès |

Nettoyage : dépôt `plateforme/essai-porte` supprimé, branches de test supprimées, clé jetable détruite.

## 5. Procédure d'urgence

Un correctif urgent dont l'image ne passe pas la porte **n'est pas** une raison de désactiver le job ni de retirer « Pipelines must succeed » (un retrait laisserait passer la MR suivante aussi). Dans l'ordre :

1. Comprendre le refus (`rapport-images.tsv`) : la plupart des refus sont une image mal référencée (étiquette au lieu du digest) ou une chaîne non terminée (signature en attente de l'analyse de Harbor).
2. Si la chaîne est en cause (runner protégé en panne) : la réparer (RB-190, RB-195) ; c'est elle qui produit des images de confiance.
3. Dernier recours, décision de Sophie Laurent **et** Claire Morel, tracée dans le ticket : un Maintainer fusionne une MR dédiée qui ajoute l'image au fichier `images-tierces.txt` avec la mention `URGENCE <ticket>` ; une seconde MR la retire dans les 24 h après reconstruction par la chaîne. La porte reste active pendant toute l'opération.

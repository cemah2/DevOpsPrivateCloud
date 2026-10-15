# Registre des charts — projet Harbor `charts`

Responsable : équipe Plateforme. Mise à jour à chaque changement de règle, de robot ou de chart tiers.

## Règles du projet

| Règle | Valeur | Pourquoi |
|---|---|---|
| Visibilité | privé | Les charts décrivent notre infrastructure ; lecture par comptes nominatifs, robots et `robot$k8s-pull` |
| Immuabilité | toutes les étiquettes (`**`) de tous les dépôts (`**`) | Une version publiée ne change jamais de contenu ; on publie une version suivante |
| Signature | Cosign exigée (comme `medisphere`, M13-E14) | Rien d'installé qui ne soit signé par la clé MédiSphère |
| Analyse de vulnérabilités | sans objet pour les charts (Trivy analyse les images qu'ils citent) | — |
| Conservation | aucune suppression automatique | Un retour arrière doit pouvoir réinstaller une ancienne version |

## Comptes

| Compte | Droits | Usage | Expiration | Rangé où |
|---|---|---|---|---|
| `robot$charts+ci` | push et pull d'artefacts, lecture des dépôts, projet `charts` seulement | Pipeline du chart (M17-E13) | <DATE-EXPIRATION> (90 jours, renouvellement au RB de rotation des robots) | Variables CI `HARBOR_CHARTS_USER` / `HARBOR_CHARTS_TOKEN`, groupe GitLab `mediagenda`, protégées et masquées. Nulle part ailleurs |
| `robot$k8s-pull` (M13) | pull | Nœuds de `k8s-par1` (non utilisé pour les charts) | — | M13 |
| `robot$wb-checks` (M13) | lecture système | Vérifications du workbook | — | `~/.config/workbook/harbor-checks.env` |

## Charts tiers recopiés

| Chart | Version | Origine | Relu par | Date | Digest |
|---|---|---|---|---|---|
| `valkey` | 0.12.0 | `https://valkey.io/valkey-helm/` | <MOI> | <DATE> | `sha256:<DIGEST>` |

Procédure : `outils/recopier-chart.sh` du projet `mediagenda/chart` (relecture des images, du RBAC et des
hooks avant signature).

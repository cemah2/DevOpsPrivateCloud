# Répétition de mise à jour de Harbor

> Modèle de corrigé (M13-E16). Une répétition sur `reg02` avant chaque mise à jour de `reg01` (RB-132).

| | |
|---|---|
| Date | `<AAAA-MM-JJ>` |
| Hôte | `reg02` |
| De → vers | `2.15.<N-1>` → `2.15.<N>` |
| Données | `<N>` images répliquées, `<X>` Go |

| Étape | Commande | Durée |
|---|---|---|
| Garde-fous, arrêt | `harbor-mise-a-jour.yml` (pre_tasks, arrêt) | |
| Copie de la base à l'arrêt | `cp -a /data/database …` | |
| Archive, bascule, `install.sh --with-trivy` | rôle `harbor` | |
| Migration du schéma au démarrage de `harbor-core` | — | |
| Santé `healthy` | — | |
| **Total (indisponibilité)** | | |

## Vérifications après mise à jour

- [ ] `systeminfo` : `v2.15.<N>`
- [ ] tirage d'une image signée, `cosign verify` réussi
- [ ] nouvelle analyse (Trivy embarqué de la nouvelle version)
- [ ] `prepare migrate` : écart de clés avec le gabarit du rôle (`<aucun / liste>`)

## Retour arrière (répété)

| Étape | Durée |
|---|---|
| Arrêt, lien vers l'ancienne version, base d'avant | |
| Démarrage, santé | |
| Vérifications | |

Écarts constatés et tickets : `<…>`.

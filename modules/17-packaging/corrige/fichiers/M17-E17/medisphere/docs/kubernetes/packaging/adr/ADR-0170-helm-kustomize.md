# ADR-0170 — Helm, Kustomize ou les deux

- **Statut** : accepté
- **Date** : <AAAA-MM-JJ>
- **Décideurs** : Claire Morel, Karim Benali, Julien Petit, équipe Plateforme
- **Ticket** : PLAT-1817

## Contexte

MédiAgenda est empaquetée en chart Helm (`mediagenda/chart`) : testé (helm-unittest, `ct lint`), publié en OCI dans Harbor `charts` et signé Cosign par un pipeline (M17-E13). Elle est livrée par Kustomize (`mediagenda/deploiement`) : la base est le rendu commité du chart signé (`chart.env`, `outils/rendre-base.sh`), les overlays `dev`, `recette`, `prod` l'adaptent (M17-E09). Le dev porte aussi une release Helm de banc d'essai. La plateforme (Cilium, cert-manager, ExternalDNS, ceph-csi, Velero, CloudNativePG, metrics-server) est décrite par Helmfile (M17-E10).

À venir :
- Argo CD (M20), qui **rend** les charts sans exécuter `helm install` ;
- MédiDoc et MédiNotif ;
- l'accueil de nouvelles équipes (F2).

Contraintes :
- HDS : savoir ce qui tourne, depuis quel artefact, et qui l'a changé ;
- souveraineté : tout vient de Harbor ;
- Helm 4 applique en *server-side apply* : une modification manuelle bloque le déploiement suivant (M17-E14).

## Critères (poids)

1. Lisibilité de ce qui est appliqué, relu en MR (3)
2. Paramétrage par environnement sans copie (3)
3. Cycle de vie : ordre, hooks, retour arrière, désinstallation (2)
4. État stocké dans le cluster : Secrets de release, valeurs lisibles (2)
5. Dérive et SSA : détection et correction (2)
6. Tests et publication d'un artefact versionné et signé (3)
7. Consommation par Argo CD (M20) (3)
8. Charts tiers de la plateforme (2)
9. Compétences de l'équipe, nombre d'outils (1)

## Options

Notes de 0 (mauvais) à 3 (très bon).

| Critère (poids) | A. Tout Helm (une release par environnement) | B. Tout Kustomize (manifestes rendus versionnés) | C. Chart pour empaqueter, Kustomize pour livrer (rendu commité) | D. Helmfile partout |
|---|---|---|---|---|
| 1 Lisibilité (3) | 1 — valeurs lisibles, rendu caché (`helm diff` indispensable, E14) | 3 — YAML final dans le dépôt | 2 — overlays lisibles, rendu par `kustomize build` | 1 — comme A |
| 2 Environnements (3) | 2 — un fichier de valeurs par environnement | 1 — copies de manifestes, patchs volumineux | 3 — overlays + components (E09) | 2 — environnements Helmfile |
| 3 Cycle de vie (2) | 3 — hooks ordonnés, `rollback` (E12) | 1 — aucun ordre, aucun historique | 2 — ordre par conteneur d'initialisation, retour par Git | 3 — `needs` + hooks |
| 4 État stocké (2) | 1 — Secrets de release, valeurs en clair (E15, E23) | 3 — aucun | 3 — aucun | 1 — comme A |
| 5 Dérive (2) | 2 — conflits SSA explicites, `helm diff --three-way-merge` | 2 — `kubectl diff --server-side` | 2 — idem B | 2 — `helmfile diff` |
| 6 Tests et artefact (3) | 3 | 1 — rien à publier, tests à inventer | 3 — l'artefact est le chart signé | 3 |
| 7 Argo CD (3) | 1 — Argo CD ne crée pas de release, hooks traduits partiellement | 3 | 3 — Argo CD applique l'overlay tel quel, rendu déjà commité | 0 — Argo CD n'exécute pas Helmfile sans greffon |
| 8 Charts tiers (2) | 3 | 1 — réécrire le rendu des fournisseurs à chaque version | 2 — possible, mais hooks des fournisseurs perdus | 3 |
| 9 Compétences (1) | 3 | 2 | 2 | 1 |
| **Total (sur 63)** | **42** | **40** | **53** | **37** |

## Décision

1. **Application maison** : un **chart** (paquet versionné, testé, signé, sans secret, sans dépendance de données), **livré par Kustomize** : rendu du chart tiré de Harbor par version **et** digest, signature vérifiée, rendu commité dans `base/rendu/` (`outils/rendre-base.sh`), puis overlays. La configuration d'environnement vit dans les overlays de `<équipe>/deploiement`, jamais dans le chart. Les **hooks** du chart ne servent qu'aux usages Helm directs (banc d'essai, `ct install`). En livraison, les migrations passent par un conteneur d'initialisation idempotent (`migrations.mode: initContainer`).
2. **Composant tiers de plateforme** : release Helm décrite par **Helmfile** dans `plateforme/k8s` (version épinglée, `needs`, `rollbackOnFailure`), parce que les hooks et les CRD des fournisseurs supposent `helm install`.
3. **Objets de configuration de la plateforme** (émetteurs, politiques, quotas, espaces) : manifestes **Kustomize** dans `plateforme/k8s`.
4. Le dev n'est plus livré par une release Helm à partir de `packaging-v1` : il suit la règle 1 (M17-E25). Les essais du chart se font dans un espace jetable (`wb-ct`, `ct install`).

## Conséquences

- ➕ Un seul artefact par version d'application, promu de dev à prod sans reconstruction. Aucun état Helm pour les applications. Le dépôt de déploiement est directement consommable par Argo CD (M20).
- ➖ Deux endroits pour paramétrer : valeurs communes du chart (`values-communes.yaml`) et overlays. Règle : le chart porte les **défauts sûrs**, l'overlay porte ce qui **diffère** par environnement.
- ➖ Les hooks du chart ne s'exécutent pas en livraison. Toute nouvelle tâche d'ordre (migration, initialisation) doit être idempotente et tolérer plusieurs réplicas. Revue obligatoire des hooks à chaque MR du chart.
- ➖ Les composants tiers gardent l'état Helm (Secrets de release) : `historyMax: 10`, aucun secret en valeur (`audit-valeurs-helm.sh`, E15).
- ➖ Il faut deux outils (Helm 4 et Kustomize 5.8, plus Helmfile pour la plateforme), et des versions alignées sur `adm01`, les runners et Argo CD.

Actions :
- gabarit CI `helm-chart.yml` pour les futurs charts (MédiDoc), M19 ;
- applications Argo CD sur `mediagenda/deploiement` et `plateforme/k8s`, M20 ;
- External Secrets Operator pour les Secrets référencés, M25 ;
- règle d'admission qui exige un chart signé, M26 ;
- revue de cette décision si Helm stabilise les charts v3 ou si Argo CD exécute nativement Helmfile.

## Liens

M17-E09 (overlays, components), E10 (Helmfile), E12 (hooks), E13 (pipeline), E14 (dérive), E15 (secrets), E23 (stockage des releases) ; [Argo CD — Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/).

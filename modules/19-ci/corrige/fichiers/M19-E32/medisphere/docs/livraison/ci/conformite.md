# Conformité CI des projets applicatifs

| | |
|---|---|
| Ticket | SEC-2032 (M19-E32) |
| Propriétaire | Équipe Plateforme ; règles approuvées par Sophie Laurent |
| Outil | `plateforme/outils` : `bin/ms-ci-conformite`, règles `etc/ci-conformite.toml` |
| Exécution | pipeline planifié `ci-conformite`, chaque nuit à 02:17, runner `k8s` ; propriétaire : compte technique `ci-conformite` |
| Rapport | artefacts `conformite.md` / `conformite.json` du dernier pipeline planifié (90 jours) |

## Règles

| # | Règle | Pourquoi |
|---|---|---|
| R1 | Configuration CI présente et valide | un projet sans CI échappe à tout |
| R2 | Composant `securite` inclus par `include: component` | une copie locale diverge et n'a plus les correctifs |
| R3 | Version ≥ 2.1.0 (signature sur le runner protégé), hors versions retirées | les versions plus anciennes signent avec une variable de groupe (E24) |
| R4 | « Pipelines must succeed » activé | sinon une analyse rouge n'empêche rien |
| R5 | Aucun job `securite:*` rendu facultatif (`allow_failure: true`) par le projet | contournement le plus simple du socle |

Périmètre : groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` (projets non archivés, sous-groupes compris). Les projets qui ne construisent pas d'image (`mediagenda/deploiement`, `medidoc/deploiement`, `mediagenda/chart`, liste `sans_image`) ne sont soumis qu'à R1 et R4.

## Ce que fait l'outil

Un ticket par projet non conforme, étiqueté `conformite-ci`, mis à jour chaque nuit (liste des écarts) ; fermé automatiquement, avec un commentaire, quand le projet redevient conforme. Le pipeline reste vert même si des projets sont non conformes (option `--strict` pour un usage ponctuel).

## Identité

Compte technique `ci-conformite` (pas un compte de service : fonction Premium), sans connexion interactive, Developer sur les seuls groupes du périmètre ; jeton personnel portée `api`, 90 jours, tourné par RB-196 ; variable `CI_CONFORMITE_TOKEN` du projet `plateforme/outils` : fichier, protégée, masquée, cachée.

Limite connue : le compte peut lire le code de tous les projets du périmètre et y ouvrir des tickets ; il ne peut ni pousser sur une branche protégée ni fusionner.

## Dérogations

Une dérogation se demande par ticket à Sophie Laurent : motif, échéance, décideur ; elle s'inscrit dans `etc/ci-conformite.toml` (`[derogations]`) par MR. Le projet reste signalé dans le rapport ; pas de ticket avant l'échéance.

## Ce que ce contrôle ne remplace pas

Les *pipeline execution policies* d'Ultimate **imposent** des jobs à l'exécution ; ici on **constate** après coup (au plus 24 h). Un projet peut être non conforme pendant une journée, et un Maintainer peut désactiver « pipelines must succeed » entre deux contrôles : le journal d'audit du projet et le ticket le montreront le lendemain.

## Premier passage (AAAA-MM-JJ)

| Projet | Conforme | Écarts |
|---|---|---|
| `mediagenda/api` | oui | — |
| `mediagenda/chart` | oui | — (sans image : R1, R4) |
| `mediagenda/deploiement` | oui | — (sans image : R1, R4) |
| `mediagenda/annuaire` | NON | R2 (E34) |
| `medidoc/medidoc` | NON | R2 (E33) |
| `medinotif/worker` | NON | R2, R4 |
| `legacy/legacy-rdv` | NON | R2, R4 |

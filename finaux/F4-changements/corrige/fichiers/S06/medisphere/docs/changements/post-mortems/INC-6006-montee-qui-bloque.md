# INC-6006 — La montée qui bloque (post-mortem)

| | |
|---|---|
| Gravité | 3 (aucun impact utilisateur de production ; fenêtre de changement menacée) |
| Changement en cours | CHG-3404 |
| Rédaction | équipe Plateforme, sans recherche de coupable |

> Modèle rédigé pour la **variante 1** (PDB qui interdit toute éviction). Pour les variantes 2 et 3, la
> structure est la même ; cause, détection et prévention sont dans le corrigé de F4-S06.

## Résumé

Pendant CHG-3404, le drain de `k8s-w02` n'a jamais terminé. Une PDB `maintenance-montee`, posée à la main dans `mediagenda-recette` quelques jours plus tôt « pour protéger la recette pendant la montée », imposait `maxUnavailable: 0` : toute éviction des pods couverts était refusée. Le drain réessayait sans fin. Karim l'a interrompu ; le nœud est resté cordonné 35 minutes.

## Chronologie (heure locale)

| Heure | Événement |
|---|---|
| 21 h 02 | `kubectl drain k8s-w02` ; la plupart des pods partent |
| 21 h 03 → 21 h 22 | le drain répète « Cannot evict pod as it would violate the pod's disruption budget » sur le même pod |
| 21 h 22 | drain interrompu, INC-6006 ouvert |
| 21 h 30 | `outils/controles-montee.sh noeud k8s-w02` : PDB `maintenance-montee`, 0 perturbation autorisée |
| 21 h 34 | origine : objet créé à la main (`managedFields` : `kubectl-client-side-apply`, étiquette `auteur: lucas.martin`), absent de tout dépôt |
| 21 h 37 | PDB supprimée (après accord de Lucas et de Karim, tracé dans la fiche) ; drain relancé, terminé en 2 min |

## Cause

Une PDB à `maxUnavailable: 0` (équivalente à `minAvailable` = nombre de réplicas) **interdit toute éviction volontaire** ; un drain n'utilise que l'éviction. Elle a été créée hors du code, sans relecture, avec une bonne intention (protéger la recette) et un mauvais réglage (une PDB protège en **limitant** les perturbations, pas en les interdisant).

## Détection

- Le contrôle « avant le go » de CHG-3404 (`controles-montee.sh avant`) aurait listé la PDB : il n'a pas été rejoué après l'ajout de Lucas (il datait de la veille).
- Aucune alerte ne signale une PDB à 0 perturbation autorisée.

## Ce qui a bien marché

Personne n'a forcé le drain (`--disable-eviction`) ni supprimé la PDB sans savoir d'où elle venait. La sonde est restée à 0 seconde d'erreur.

## Actions

| Action | Responsable | Échéance | Ticket |
|---|---|---|---|
| Rejouer `controles-montee.sh avant` **au go/no-go** (et non la veille) : ajouté au modèle de fiche | Plateforme | immédiat | PLAT-3406-1 |
| Alerte `PDBSansPerturbationAutorisee` : `kube_poddisruptionbudget_status_pod_disruptions_allowed == 0` pendant 1 h, hors PDB des primaires CNPG | Plateforme | 2 semaines | PLAT-3406-2 |
| Politique Kyverno (CEL) en `Audit` puis `Enforce` : refuser une PDB `maxUnavailable: 0` ou `minAvailable: 100%` dans les espaces applicatifs | Plateforme + Sophie Laurent | 1 mois | SEC-3406 |
| Rappel à l'équipe : rien à la main dans les espaces gérés par Argo CD (même un objet « en plus ») | Karim | immédiat | — |

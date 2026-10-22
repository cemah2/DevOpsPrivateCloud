# Indicateurs de livraison (DORA)

| | |
|---|---|
| Ticket | PLAT-2028 (M19-E28) |
| Propriétaire | Équipe Plateforme (Claire Morel) |
| Script | `plateforme/outils` : `bin/dora.py` (bibliothèque standard, lecture seule, jeton `read_api`) |
| Revue | mensuelle, réunion de l'équipe Plateforme avec Julien Petit ; tendance sur trois mois |

## 1. Vocabulaire chez MédiSphère

| Terme DORA | Chez nous | Pourquoi ce choix |
|---|---|---|
| Déploiement | un déploiement **réussi** de l'environnement visé (`dev`, puis `recette`, `prod`) du projet `mediagenda/deploiement` (job `deployer-dev`, E18 ; Argo CD au M20) | c'est le seul événement enregistré par GitLab (API des déploiements) ; un pipeline vert de `mediagenda/api` ne change rien chez l'utilisateur |
| Changement | une version `vX.Y.Z` de `mediagenda/api` promue par MR (`promotion/<env>-vX.Y.Z`) ; les changements de configuration seule du dépôt de déploiement sont comptés comme déploiements mais sans délai | la promotion relie le code au déploiement |
| Échec d'un changement | un déploiement en échec **ou** un retour arrière (version déployée inférieure à la précédente) | les deux sont visibles dans l'API ; l'incident ouvert après un déploiement réussi n'est pas relié automatiquement (biais, §4) |
| Rétablissement | durée d'un ticket étiqueté `incident` de `mediagenda/api`, de l'ouverture à la fermeture | les incidents de Nadia Roussel sont des tickets ; la fermeture signifie « service rétabli », pas « cause corrigée » |

## 2. Les quatre indicateurs

### 2.1 Fréquence de déploiement
- Source : `GET /projects/mediagenda%2Fdeploiement/deployments?environment=dev&updated_after=<J-30>&order_by=updated_at` (`status` = `success` ; l'API répond `400` à `updated_after` sans `order_by=updated_at`).
- Calcul : nombre / 30. Fenêtre : 30 jours glissants.
- Confiance : bonne. Biais : un redéploiement sans changement (relance de job) compte.

### 2.2 Délai de mise en production
- Source : pour chaque déploiement réussi, `sha` → `GET /projects/:id/repository/commits/:sha/merge_requests` (MR de promotion, branche `promotion/dev-vX.Y.Z`) → `GET /projects/mediagenda%2Fapi/repository/tags/vX.Y.Z` (`commit.committed_date`).
- Calcul : médiane de (fin du déploiement − date du commit étiqueté).
- Confiance : moyenne. Biais : on mesure depuis le **dernier** commit de la version, pas depuis le premier changement qu'elle contient (sous-estimation pour une version qui en regroupe beaucoup) ; une promotion par configuration seule n'entre pas dans le calcul.

### 2.3 Taux d'échec des changements
- Source : mêmes déploiements (`status` = `failed`) ; versions déduites des MR de promotion.
- Calcul : (échecs + retours arrière) / déploiements tentés.
- Confiance : moyenne. Biais : un problème découvert après un déploiement réussi et corrigé par une **nouvelle** version (pas un retour arrière) n'est pas compté.

### 2.4 Temps de rétablissement
- Source : `GET /projects/mediagenda%2Fapi/issues?labels=incident&created_after=<J-30>&state=all`.
- Calcul : médiane de (fermeture − ouverture), en heures ; incidents encore ouverts comptés à part.
- Confiance : faible tant que les incidents ne sont pas systématiquement ouverts dans GitLab (aujourd'hui : aucun incident de production, l'application n'est pas encore en service pour des patients).

## 3. Résultat daté

```
admin@adm01:~/src/outils$ bin/dora.py --deploiement mediagenda/deploiement --application mediagenda/api --environnement dev
```

Calcul du AAAA-MM-JJ — `mediagenda/deploiement`, environnement `dev`, 30 jours glissants

| Indicateur | Valeur | Base |
|---|---|---|
| Fréquence de déploiement | 0,4 / jour | 12 déploiements réussis |
| Délai de mise en production (médiane) | 1,2 h | commit étiqueté → déploiement réussi |
| Taux d'échec des changements | 0,143 | 2 échecs, 0 retour arrière |
| Temps de rétablissement (médiane) | n. d. h | 0 incident, 0 encore ouvert |

(Valeurs d'exemple : colle les tiennes. Les chiffres d'un lab de formation ne valent pas ceux d'une équipe réelle.)

## 4. Ce que ces chiffres ne disent pas

- La **valeur** livrée : dix déploiements d'une virgule ne valent pas un déploiement d'une fonction attendue.
- La qualité du code (couverture, dette) ni la sécurité.
- La cause d'un délai : attente de revue, file des runners (E27), fenêtre de recette ? Il faut décomposer (temps de MR, temps de pipeline, temps d'attente de fusion).
- Un faible taux d'échec peut venir d'une faible fréquence (on déploie peu, donc on rate peu).
- Sur 30 jours et quelques déploiements, une médiane bouge beaucoup : on regarde la **tendance** sur trois mois.

## 5. Ce que nous en ferons (et ce que nous n'en ferons pas)

- Revue mensuelle : tendance, et une question « qu'est-ce qui nous ralentit ? » ; chaque action décidée est un ticket.
- **Jamais** d'objectif individuel ni de comparaison entre équipes (loi de Goodhart : un indicateur qui devient objectif cesse de mesurer).
- Pas de diffusion des chiffres bruts hors de l'équipe sans leur contexte (§4).

## 6. Évolutions prévues

- M20 : les déploiements deviennent des synchronisations d'Argo CD ; la source change (historique des Applications, ou notifications vers GitLab qui enregistrent un déploiement). Le script devra lire l'une ou l'autre : définition inchangée, source différente.
- Environnements `recette` et `prod` dès qu'ils sont déployés par la chaîne.
- Incidents : étiquette `incident` obligatoire (modèle de ticket de Nadia Roussel) et lien vers le déploiement en cause, pour relier un incident à un changement.

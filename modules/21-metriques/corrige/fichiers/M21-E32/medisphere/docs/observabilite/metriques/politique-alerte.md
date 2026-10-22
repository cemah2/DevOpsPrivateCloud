# Politique d'alerte et d'astreinte

| | |
|---|---|
| Ticket | PLAT-2232 (M21-E32) |
| Rédaction | Équipe Plateforme, avec Nadia Roussel (support et astreinte) |
| Validée par | Claire Morel ; Julien Petit (équipe MédiAgenda) ; Sophie Laurent (alertes de sécurité) |
| S'applique à | toutes les règles d'alerte : `plateforme/observabilite` (`regles/`, `slo/`), dépôts `…/deploiement` des équipes, témoin `mon01` |
| Révision | revue mensuelle des alertes (§7) ; politique relue chaque semestre |

## 1. Principes

1. **Une alerte qui réveille doit exiger une action humaine immédiate.** Sinon, ce n'est pas une alerte critique : c'est un avertissement, une info ou un tableau de bord.
2. **On alerte sur les symptômes** (ce que vit l'utilisateur : erreurs, lenteur, indisponibilité, budget d'erreur qui brûle) ; les causes (CPU, disque, pod redémarré) servent au diagnostic et ne réveillent que si elles annoncent un symptôme certain et proche (disque plein dans moins de 4 h, etc.).
3. **Chaque alerte a un propriétaire et un runbook** : étiquette `equipe`, annotation `runbook_url` vers un runbook qui existe (RB-21x), annotations `resume` et `description` en français, sans donnée personnelle.
4. **Pas d'alerte sans test** : `promtool test rules` dans la CI pour toute règle qui peut réveiller.

## 2. Gravités (étiquette `gravite`)

| Gravité | Signification | Notification | Délai de prise en compte | Exemples |
|---|---|---|---|---|
| `critique` | impact utilisateur en cours ou imminent en **production**, ou perte de capacité à voir (supervision muette, perte de données en cours) | courriel `astreinte@` à toute heure (téléphone d'astreinte relié à la boîte) ; rappel toutes les 4 h tant qu'active | 15 min (heures ouvrées), 30 min (nuit, week-end) | `ErrorBudgetBurn` (prod, rapide), `MediagendaIndisponible`, `SupervisionClusterMuette`, `ThanosCompacteursMultiples`, `PrometheusVolumePresquePlein` |
| `avertissement` | dégradation sans impact immédiat, ou impact hors production | courriel à l'équipe (`plateforme@`, `mediagenda@`, `medidoc@`), **heures ouvrées** seulement (`time_intervals`, E16) | jour ouvré suivant | `ErrorBudgetBurn` (lent), `ThanosCompacteurArrete`, `PrometheusSeriesProchesDuBudget`, certificats < 14 j |
| `info` | à savoir, à regarder en revue | aucun courriel ; visible dans Alertmanager et Grafana | revue hebdomadaire | `PrometheusRetentionParTaille`, SLO de recette |

Une alerte sans `gravite` est une erreur de configuration (refusée en revue de MR) ; les règles du chart, qui portent `severity`, sont traduites (`critical` → critique, `warning` → avertissement) par le routage.

## 3. Qui est réveillé

| `equipe` | Heures ouvrées (lun.-ven. 8 h-18 h, Europe/Paris) | Nuit et week-end |
|---|---|---|
| `plateforme` | équipe Plateforme | astreinte plateforme (rotation hebdomadaire, §5) |
| `mediagenda` | équipe MédiAgenda | astreinte plateforme, qui escalade à l'équipe si la cause est applicative |
| `medidoc` | équipe MédiDoc | jamais (pas de production MédiDoc à ce jour) |

L'astreinte reçoit **toutes** les alertes `critique` ; les équipes reçoivent leurs alertes de toute gravité (sauf `info`).

## 4. Regroupement, répétition, silence, inhibition

- Regroupement par `alertname` et `namespace` (un courriel pour 30 pods en échec) ; `group_wait` 30 s, `group_interval` 5 min, `repeat_interval` 4 h.
- Inhibitions : nœud injoignable → alertes des pods de ce nœud ; une alerte critique → avertissements du même nom dans le même espace ; supervision muette → rien n'est inhibé (au contraire, tout est suspect).
- **Silences** : posés par `amtool` ou l'interface d'Alertmanager, **toujours** avec auteur, commentaire (ticket CHG ou INC) et fin. Durée maximale 24 h, renouvelable explicitement ; un silence sans ticket est retiré à la revue. Jamais de silence sur `Watchdog` ni sur les alertes du témoin.
- `Watchdog` ne notifie jamais par courriel : il est surveillé par le témoin de `mon01` (RB-215).

## 5. Astreinte

- Rotation hebdomadaire de l'équipe Plateforme (lundi 9 h), planning tenu par Nadia Roussel ; passation écrite (incidents ouverts, silences actifs, changements prévus).
- L'astreinte a : accès VPN, `adm01`, les runbooks RB-1xx et RB-2xx, le droit de geler les déploiements (politique de budget d'erreur).
- **Escalade** : 30 min sans diagnostic → Karim Benali (plateforme) ; incident touchant des données de santé ou suspicion d'intrusion → Sophie Laurent, immédiatement ; indisponibilité de MédiAgenda prod > 1 h → Claire Morel et Julien Petit.
- Compensation et repos de sécurité après une intervention de nuit : selon l'accord d'entreprise (hors de ce document).

## 6. Écrire une alerte (liste de contrôle de la MR)

- [ ] symptôme ou cause justifiée par un délai ; expression testée (`promtool test rules`) ;
- [ ] `for:` adapté (pas de `for` = alerte sur un seul échantillon) ; fenêtre de `rate()` ≥ 4 intervalles de collecte ;
- [ ] pas d'étiquette à forte cardinalité dans le résultat (identifiant de requête, d'utilisateur) ;
- [ ] `gravite`, `equipe`, `resume`, `description`, `runbook_url` (le runbook existe) ;
- [ ] routage vérifié (`alertmanager/routes-tests.txt`) ;
- [ ] pour une alerte qui ne devrait jamais être vide : prévue avec son `absent()` (ou une alerte SLOMetricAbsent).

## 7. Revue des alertes (mensuelle, 30 min)

Tableau « Alertes du mois » (Grafana) : nombre de notifications par alerte, part des alertes `critique` qui ont donné lieu à une action, alertes les plus bruyantes, silences posés. Pour chaque alerte critique sans action : la rétrograder, la corriger ou la supprimer. Objectif : **moins de 2 notifications critiques par semaine d'astreinte** hors incident réel. Compte rendu dans `docs/observabilite/metriques/revues/`.

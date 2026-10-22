# Politique de changement de la production (GitOps)

| | |
|---|---|
| Ticket | CHG-2129 |
| Exercice | M20-E29 |
| Code | `plateforme/gitops` : `syncWindows` des AppProjects `mediagenda`, `medidoc` |
| Dernière revue | <DATE> |

## Règle

1. Aucune mise en production du **vendredi 16:00 au lundi 08:00** (heure de Paris), ni pendant un **gel** annoncé par un ticket CHG (fin d'année, audit HDS, migration).
2. Pendant ces périodes, seule l'**astreinte** peut synchroniser une Application de production, à la main, pour corriger un incident ouvert (ticket INC).
3. En dehors de ces périodes, une mise en production = une MR de promotion fusionnée (digest recopié, `promotion.md`) puis une synchronisation **manuelle** de l'Application de production par un compte nominatif autorisé.

## Fenêtres en place

```
admin@adm01:~$ argocd proj windows list mediagenda
ID  STATUS    KIND  SCHEDULE    DURATION  APPLICATIONS  NAMESPACES  CLUSTERS  MANUALSYNC  SYNCOVERRUN  TIMEZONE      USEANDOPERATOR
0   Inactive  deny  0 16 * * 5  64h       *-prod        -           -         Enabled     Disabled     Europe/Paris  Disabled
```
(Même fenêtre sur `medidoc`, posée avant sa production.)

## Comment Argo CD l'applique

- Sans fenêtre applicable : tout est permis. Avec une fenêtre `allow` applicable : seulement pendant elle. Avec une fenêtre `deny` active : rien, même si une fenêtre `allow` est active (`deny` l'emporte).
- `deny` bloque les synchronisations **automatiques**, l'**auto-réparation** et les synchronisations **manuelles** ; `manualSync: true` laisse passer les manuelles. Qui peut synchroniser à la main la production : le RBAC (`role:plateforme-admin` seulement, `rbac.md`).
- `syncOverrun` (non utilisé) : laisse finir une synchronisation commencée avant l'ouverture d'une fenêtre `deny`.
- Le cron est évalué dans `Europe/Paris` ; la durée (64 h) est une durée réelle : les week-ends de changement d'heure, la fenêtre se termine le lundi à 09:00 (fin mars) ou 07:00 (fin octobre).
- Essai (M20-E29, étape 3) : une fenêtre `deny` de 30 min sur `mediagenda-recette` a bloqué la synchronisation automatique d'un commit (état `OutOfSync`, condition indiquant que la fenêtre refuse la synchronisation : texte exact relevé dans `argocd app get`) et l'auto-réparation après `kubectl scale` ; la synchronisation manuelle a été refusée sans `manualSync`, acceptée avec. À la fermeture de la fenêtre, la synchronisation automatique a eu lieu au rafraîchissement suivant : **un commit bloqué n'est pas perdu, il attend**.

## Gel des changements

1. Ticket CHG du gel (dates, périmètre, responsable).
2. MR sur `plateforme/gitops` qui ajoute à chaque AppProject concerné une fenêtre `deny` (`applications: ["*-prod"]`, `manualSync: true`, `description` avec le numéro du ticket et la date de fin) ; la **MR inverse** est ouverte en même temps, en brouillon, et liée au ticket.
3. Fusion avant le début du gel ; contrôle `argocd proj windows list` ; annonce aux équipes.
4. Fin du gel : fusion de la MR inverse, contrôle, clôture du ticket.

Une fenêtre `deny` à date fixe s'écrit avec un cron qui ne se déclenche qu'une fois par an (`0 0 21 12 *`) et une durée : d'où la MR inverse, sans laquelle le gel reviendrait l'année suivante.

## Dérogation d'urgence

- Condition : incident ouvert (ticket INC), correctif fusionné sur `main` par MR (relue après coup si nécessaire, mention dans la MR).
- Geste : `argocd app sync mediagenda-prod` par un compte nominatif de `role:plateforme-admin` (jamais un compte partagé) ; la fenêtre ayant `manualSync`, la synchronisation passe.
- Traces : MR (qui, quoi), `status.history` de l'Application et événements Kubernetes (qui a synchronisé, quand), ticket INC (pourquoi). Mention dans le post-mortem.

## Ce que la règle ne couvre pas

| Hors règle | Pourquoi | Ce qu'on fait |
|---|---|---|
| Argo Rollouts | une fenêtre bloque les **synchronisations** d'Argo CD ; un canary commencé avant 16:00 continue ses étapes (pauses, analyses) | ne pas lancer de mise en production après 14:00 le vendredi (durée d'un canary complet) ; `kubectl argo rollouts abort` si besoin |
| `kubectl` d'un administrateur | l'API du cluster ignore les fenêtres d'Argo CD | interdit hors bris de glace (RB-201, astreinte), tracé par l'audit de l'API |
| Couche de base (Helmfile : Cilium, cert-manager, Argo CD…) | hors d'Argo CD | même règle appliquée par la procédure (ticket CHG, pas de `helmfile apply` le vendredi) |
| Les environnements dev et recette | volontairement libres | — |

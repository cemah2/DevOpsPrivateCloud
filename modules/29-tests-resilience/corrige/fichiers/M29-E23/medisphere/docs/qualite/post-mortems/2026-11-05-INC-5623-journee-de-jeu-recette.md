# Post-mortem — INC-5623 — La journée de jeu automatique rend la recette de MédiAgenda indisponible

> Exemple rédigé pour la **variante 1** (sonde de vivacité sur `/pret`) ; la variante 2 (HPA à une réplique) change la section 4.2 et la chronologie, pas la structure. Heures et chiffres d'un lab de référence : mets les tiens. Sans recherche de coupable.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | 2026-11-05 |
| **Rédacteur** | <MOI> |
| **Relecteurs** | Nadia Roussel, Karim Benali, Julien Petit |
| **Sévérité** | P3 — recette seulement, aucune donnée, mais une hypothèse de résilience fausse sur un composant qui part en prod |
| **Durée d'impact** | 10:04:10 → 10:09:40 (5 min 30 sans aucun pod prêt de l'API, puis 2 min de redémarrages) |
| **Services touchés** | MédiAgenda recette (API) ; tests de l'équipe de Julien |

## 1. Résumé

La journée de jeu automatique de la plateforme (Workflow `journee-de-jeu-auto`, hypothèse « aucun impact visible ») a coupé 45 s l'accès de l'API MédiAgenda de recette à son cache Valkey, en même temps qu'elle supprimait un pod de l'API. Au lieu d'une dégradation, la recette a été **totalement indisponible 5 min 30**. Trois causes se sont additionnées : la sonde de **disponibilité** `/pret` exige le cache (faiblesse de conception connue depuis M14-E07, jamais traitée) ; la sonde de **vivacité** avait été déplacée de `/sante` vers `/pret` la veille (changement de configuration de l'overlay de recette), ce qui a fait **redémarrer en boucle** toutes les API pendant et après la coupure ; et la journée de jeu ne vérifie pas l'état de sa cible avant de commencer. Le service est rétabli, le changement défait, le correctif de `/pret` proposé à l'équipe MédiAgenda.

## 2. Impact

- Recette indisponible : 5 min 30 de 503 à la Gateway pour toutes les routes, puis 2 min de réponses intermittentes. Les tests manuels de l'équipe de Julien ont échoué ; aucune version n'a été promue sur ce résultat.
- Données : **aucune** perte ; la base et le cache n'ont pas été touchés (le cache était coupé, pas vidé) ; les rendez-vous créés pendant la journée de jeu par la charge ont été annulés par le scénario.
- Conformité : aucune ; l'audit de l'API et les journaux de Chaos Mesh tracent chaque geste.

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| 04/11 17:42 | Commit « fix(recette): vivacité sur /pret, plus honnête que /sante (M29-E23) » dans `mediagenda/deploiement` (overlay recette, `patches` JSON6902 sur le Deployment `mediagenda`), fusionné | `git log -p overlays/recette/kustomization.yaml` |
| 04/11 17:49 | Argo CD synchronise ; nouvelle révision du Rollout (canary), pods avec vivacité sur `/pret` | historique de l'Application de recette |
| 05/11 10:04:00 | Workflow `journee-de-jeu-auto` appliqué : `coupure-cache` (partition API ↔ Valkey, 45 s) en parallèle de `perte-api` (pod-kill d'une API) | événements du Workflow, audit de l'API |
| 10:04:05 | `/pret` échoue sur toutes les API (Valkey injoignable) → sorties des points de terminaison, 503 à la Gateway | `kube_pod_status_ready`, k6 |
| 10:04:35 | Vivacité en échec 3 fois sur `/pret` → **kubelet redémarre** toutes les API | `kubectl get events` : `Liveness probe failed … Killing` |
| 10:04:45 | Fin de la partition ; les API redémarrées échouent encore (pool de connexions à la base en cours d'ouverture, sonde au démarrage), nouveaux redémarrages, `CrashLoopBackOff` (attente 20 s, puis 40 s) | `RESTARTS` = 3 à 4 par pod |
| 10:07 | Nadia ouvre INC-5623 (alerte budget de recette dans Pyrra + Julien) | ticket |
| 10:08 | Arrêt : `outils/chaos-arret.sh --supprimer` (le Workflow était déjà terminé) ; constat : plus d'injection | RB-294 |
| 10:09:40 | Premier pod prêt (fin du dernier délai de `CrashLoopBackOff`) | |
| 10:11:30 | Deux pods prêts, plus de redémarrages ; service rétabli | |
| 10:25 | Cause du défaut latent trouvée (`git log -p` de l'overlay) | |
| 10:40 | MR de revert fusionnée, synchronisée ; vivacité de nouveau sur `/sante` | Argo CD |

## 4. Causes

### 4.1 Causes racines

1. **Déclencheur** — l'expérience : 45 s sans cache pour toutes les API. Elle est voulue ; ce n'est pas une cause à corriger, c'est le révélateur.
2. **Défaut latent** — la sonde de **vivacité** de l'API pointait sur `/pret`. Une sonde de vivacité qui regarde une **dépendance** transforme la panne de la dépendance en redémarrage de l'application ; avec plusieurs échecs, le `CrashLoopBackOff` (attente exponentielle) retarde le retour **après** le retour de la dépendance. Preuve : événements `Liveness probe failed: HTTP probe failed with statuscode: 503`, `RESTARTS`, commit de la veille.
3. **Faiblesse de conception** — `/pret` renvoie 503 dès que Valkey ne répond pas (code de `create_app`, présent depuis le M12, relevé en M14-E07 et en M29-E13) : la disponibilité de **tous** les pods dépend d'un cache que la documentation déclare facultatif (« sa perte dégrade, ne casse pas », M27). Même sans le défaut latent, l'expérience aurait rendu la recette indisponible 45 s.

### 4.2 Facteurs contributifs

- La journée de jeu automatique ne vérifie pas l'état de sa cible avant de commencer (pas de `StatusCheck` initial) et n'a pas de vérification continue qui l'interrompt.
- Le changement de sonde est passé en MR sans relecture de l'équipe MédiAgenda (fichier de l'overlay recette sans propriétaire désigné).
- L'action DEV-3013 (« `/pret` ne doit pas dépendre du cache »), ouverte après M29-E13, n'avait pas d'échéance.

## 5. Détection et diagnostic

- Détection par Julien (2 min) puis l'alerte de consommation de budget de recette (3 min) ; la plateforme n'a pas d'alerte « aucun pod prêt » sur la recette.
- Ralenti : la première hypothèse « l'expérience ne s'est pas arrêtée » (RB-297) a pris 5 min à écarter (aucun `netem`, aucune règle `CHAOS-*`, Workflow terminé).
- Accéléré : les événements Kubernetes (`Liveness probe failed` sur `/pret`) et `git log -p` de l'overlay.

## 6. Ce qui a bien fonctionné

Le bouton d'arrêt et RB-294 ; la recette seule était visée (filtre d'espaces) ; aucune donnée n'a été touchée ; la traçabilité (audit, Git, Argo CD) a donné l'auteur et l'heure du changement en quelques minutes.

## 7. Actions

| # | Action | Type | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | Revert de la vivacité sur `/pret` (fait) ; règle de revue : `mediagenda/deploiement` exige l'approbation de l'équipe MédiAgenda sur les sondes | prévenir | plateforme + MédiAgenda | fait / 15/11 | INC-5623 |
| 2 | `/pret` ne dépend plus de Valkey (correctif proposé, tests fournis) | prévenir | équipe MédiAgenda | 22/11 | DEV-3013 |
| 3 | Test de politique (Kyverno CLI en CI) : une sonde de vivacité ne doit pas viser le chemin de la sonde de disponibilité | prévenir | plateforme | 30/11 | PLAT-3023 |
| 4 | Journée de jeu automatique : `StatusCheck` initial (≥ 2 pods prêts, SLO vert) et vérification continue qui interrompt | atténuer | plateforme | 15/11 | PLAT-3023-2 |
| 5 | Alerte « aucun pod prêt » (recette et prod) sur `kube_deployment_status_replicas_available`/Rollout | détecter | plateforme | 15/11 | PLAT-3023-3 |
| 6 | Toute action de journée de jeu a une échéance | documenter | plateforme | fait | — |

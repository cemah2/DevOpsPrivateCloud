# Journée de jeu — La recette sous charge perd ses dépendances — 2026-10-29

> Exemple de rapport rempli (lab de référence, chiffres indicatifs). Le tien porte **tes** hypothèses, **tes** mesures et **tes** surprises.

| | |
|---|---|
| Ticket | PLAT-3016 |
| Maître du jeu | <MOI> (plateforme) |
| Astreinte (joueur) | Nadia Roussel |
| Observateurs | Julien Petit (MédiAgenda), Karim Benali |
| Scribe | Lucas Martin |
| Date, heure | jeudi 29/10/2026, 14:00-15:00 (jeu 14:10-14:40) |
| Expériences versionnées | `plateforme/resilience/journees-de-jeu/2026-10-29/jeu.yaml` (commit `a1b2c3d`) |

## 1. Préparation : objectifs

1. Vérifier que la recette tient trois pannes de dépendances **sous charge** sans sortir de ses SLO de recette plus de 5 minutes au total.
2. Mesurer le temps de **détection** par l'astreinte (alertes, tableaux) et le temps jusqu'au **bon diagnostic**, sans qu'elle connaisse l'ordre des pannes.
3. Vérifier que MédiNotif ne perd aucune notification quand il est ralenti.

## 2. Préparation : hypothèses

| # | Expérience (modèle du Workflow) | Hypothèse | Mesure | Critère d'arrêt |
|---|---|---|---|---|
| H1 | `h1-perte-pooler` : 10 % de perte API → pooler, 4 min | Le p95 reste sous 400 ms, 5xx < 1 % ; l'astreinte voit la hausse de latence sur le tableau RED en moins de 5 min | p95 et 5xx serveur ; budget `mediagenda-recette-latence` | 5xx > 5 % pendant 1 min |
| H2 | `h2-stress-medinotif` : CPU de MédiNotif à 90 %, 5 min | La file `notifications` (recette) monte puis redescend en moins de 5 min après la fin ; KEDA ajoute un pod ; aucune perte | profondeur de file, `medinotif_messages_total`, réplicas | file > 2 000 messages |
| H3 | `h3-kill-api` : 50 % des API tuées d'un coup | Aucune requête en erreur visible (l'autre moitié sert, le Rollout recrée en < 30 s) ; l'alerte « pods redémarrés » arrive à l'astreinte | 5xx, 503 de la Gateway, pods prêts | plus aucun pod prêt 30 s |

## 3. Préparation : rayon d'action et garde-fous

- Dans le champ : `mediagenda-recette`, `medinotif-recette` (Chaos Mesh), charge k6-operator 30 itérations/s.
- Hors champ : `messagerie` (partagé avec la prod), Valkey (faiblesse connue DEV-3013, déjà démontrée en M29-E13), toute la prod.
- Critère d'arrêt global : vérification continue `/sante` du Workflow (6 échecs → interruption automatique) ; ou décision du maître du jeu.
- Bouton d'arrêt : `outils/chaos-arret.sh` (RB-294), terminal tenu par Karim.
- Juste avant : SLO de recette verts depuis 15 min, aucune MR de `mediagenda/deploiement` en cours de déploiement, `lab/bin/check 29 13` vert.

## 4. Préparation : communication

| Quand | Qui | Quoi | Canal |
|---|---|---|---|
| J-2 | maître du jeu | annonce (créneau, périmètre, « recette perturbée ») | liste de l'équipe MédiAgenda |
| H-15 min | maître du jeu | confirmation, état vert | journal `docs/qualite/journal/` |
| H0 | maître du jeu | « début du jeu » | idem |
| Fin | maître du jeu | « retour à la normale, recette disponible » | liste MédiAgenda + journal |

## 5. Chronologie

| Heure | Événement | Qui | Preuve |
|---|---|---|---|
| 14:10 | Charge lancée (TestRun `jdj-1029`, 30 it/s) | MJ | `testid=jdj-1029` |
| 14:12 | Workflow appliqué ; H1 injectée | MJ | événements du Workflow |
| 14:15 | Alerte ? aucune ; Nadia remarque le p95 à 380 ms sur le tableau RED | Nadia | capture du tableau |
| 14:19 | Diagnostic de Nadia : « latence base » (bonne direction, cause exacte non trouvée : perte de paquets) | Nadia | journal |
| 14:16-14:22 | H1 terminée, retour | — | p95 < 120 ms à 14:18 |
| 14:22 | H2 injectée | — | |
| 14:24 | File `notifications` (recette) à 1 450 messages, KEDA passe MédiNotif de 1 à 3 pods | — | `kubectl get scaledobject`, API de gestion |
| 14:27 | H2 terminée ; file vide à 14:29 | — | |
| 14:33 | H3 : 1 pod sur 2 tué | — | événements |
| 14:33:04 | 12 réponses 502 sur des requêtes en cours dans le pod tué ; pas de 503 | — | k6, Gateway |
| 14:33:40 | Alerte `KubePodNotReady` ? non (seuil 15 min) ; Nadia voit le redémarrage dans Argo Rollouts | Nadia | |
| 14:40 | Fin du Workflow (`Accomplished`), arrêt de la charge, annonce de fin | MJ | |

## 6. Hypothèses : résultats

| # | Résultat | Mesures | Commentaire |
|---|---|---|---|
| H1 | **Confirmée** | p95 avant 95 ms / pendant 380 ms / après 100 ms ; 5xx 0,2 % | Pas d'alerte : le SLO de latence de recette n'alerte pas (choix de M29-E13) et celui de prod ne voit pas la recette. |
| H2 | **Confirmée en partie** | file max 1 450 ; vidée 2 min après ; 0 perte, 0 doublon | KEDA a réagi en 90 s (intervalle d'interrogation 30 s + stabilisation) ; aucune alerte sur la profondeur de file en recette. |
| H3 | **Réfutée** | 12 réponses 502, 0 503 | Requêtes en cours perdues avec le pod tué (`gracePeriod` absent = délai par défaut, mais le pod reste dans la HTTPRoute le temps que la Gateway le retire). |

## 7. Détection

| # | Alerte attendue | Alerte reçue | Temps de détection | Temps jusqu'au bon diagnostic | Commentaire |
|---|---|---|---|---|---|
| H1 | latence de recette | aucune | 3 min (tableau, par chance) | non trouvé (perte de paquets jamais envisagée) | pas de tableau « réseau du pod » |
| H2 | profondeur de file | aucune | 4 min (Nadia regardait KEDA) | 6 min | rien n'alerte sur la recette |
| H3 | redémarrage d'API | aucune | 1 min (Argo Rollouts ouvert) | 2 min | seuils prévus pour la prod |

## 8. Actions correctives

| Action | Type | Responsable | Échéance | Ticket | État |
|---|---|---|---|---|---|
| Alerte « latence de recette » pendant les heures ouvrées (vers la plateforme, pas l'astreinte) | détection | plateforme | 15/11 | `plateforme/resilience#12` | ouverte |
| Panneau « retransmissions TCP et pertes » par pod (Hubble, `node_netstat`) dans le tableau de diagnostic | détection | plateforme | 15/11 | `#13` | ouverte |
| Alerte de profondeur de file `notifications` (seuil, durée) en recette et en prod | détection | plateforme + MédiNotif | 22/11 | `#14` | ouverte |
| Arrêt propre de l'API sur `pod-kill` : `preStop` (attendre que la Gateway retire le pod) | système | équipe MédiAgenda | 22/11 | `#15` (→ DEV-3016) | ouverte |
| `/pret` ne dépend plus de Valkey (faiblesse de M29-E13) | système | équipe MédiAgenda | 30/11 | `#16` (→ DEV-3013) | ouverte |
| Toute journée de jeu commence par une vérification automatique de l'état de la cible | processus | plateforme | 15/11 | `#17` | ouverte |

## 9. Ce qui a bien marché, ce qu'on refera autrement

Bien : préparation relue la veille, bouton d'arrêt jamais utilisé mais prêt, aucune surprise pour l'équipe de Julien. Autrement : prévoir un tableau « journée de jeu » unique (SLO, file, pods, alertes) ; faire jouer l'astreinte **sans** Argo Rollouts ouvert, comme une nuit réelle.

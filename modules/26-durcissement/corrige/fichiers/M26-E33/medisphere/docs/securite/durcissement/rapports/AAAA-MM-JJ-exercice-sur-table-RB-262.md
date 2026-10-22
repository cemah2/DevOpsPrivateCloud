# Exercice sur table — conteneur compromis (RB-262)

| | |
|---|---|
| Date, durée | <DATE>, 1 h 30 |
| Participants | <MOI> (responsable de l'incident), Nadia Roussel (astreinte, support), Sophie Laurent (RSSI) ; Claire Morel joue la direction (15 dernières minutes) |
| Animateur | <MOI> (scénario écrit à l'avance, injections remises sur papier) |
| Version du runbook | RB-262 du <DATE>, commit <SHA> |

## Scénario (rédigé par l'animateur, inconnu des joueurs)

Mardi, 02:10. Falco signale « shell interactif dans un conteneur applicatif » sur `mediagenda-prod`, pod `mediagenda-…-x7k2p`, puis Tetragon une lecture du jeton de compte de service par `/tmp/.k`. 02:25 : Hubble montre des tentatives de connexion vers une adresse inconnue sur le port 4444. 03:00 (injection) : le même pod a lu le Secret de la base de données de recette (audit de l'API). 03:20 (injection) : Julien appelle, il a vu passer « des requêtes bizarres sur /api/v1/patients » dans les journaux applicatifs de la veille.

## Chronologie jouée

| Heure (jeu) | Décision / action | Qui | Écart au runbook |
|---|---|---|---|
| 02:10 | qualification : pas de déploiement en cours, pas de test annoncé → incident INC-… ouvert | Nadia | aucun |
| 02:18 | RSSI appelée | Nadia | RB-262 dit « dans l'heure » : OK, mais le numéro n'était pas dans l'annuaire d'astreinte → corrigé |
| 02:22 | quarantaine posée, pod sorti du contrôleur | <MOI> | oubli initial : Argo CD en auto-synchronisation avec élagage sur `prod` ? Non (`prod` manuelle) → noter la règle pour `dev`/`recette` |
| 02:40 | collecte 1 à 6 | <MOI> | le tampon Hubble ne couvrait que 40 min : export à faire avant la quarantaine (ordre modifié) |
| 03:05 | injection « Secret de recette lu » : rotation des identifiants OpenBao `db-mediagenda` | Sophie | le runbook ne disait pas qui peut révoquer les baux la nuit → ajouté |
| 03:25 | injection « /api/v1/patients » : possibilité d'accès aux données de santé, décision « violation probable » | Sophie | délais RGPD (72 h) et signalement santé relus ; DPO non joignable la nuit → suppléant à nommer |
| 03:40 | communication direction | Claire | modèle de message absent → à créer |

## Ce qui a fonctionné

- La quarantaine préparée : une commande, sans redémarrage, sans attendre d'MR.
- La collecte sans toucher au conteneur suspect (conteneur éphémère).

## Actions

| Action | Responsable | Échéance |
|---|---|---|
| Numéro de la RSSI et suppléant du DPO dans l'annuaire d'astreinte | Nadia | <DATE> |
| RB-262 : export Hubble AVANT la quarantaine ; qui révoque les baux OpenBao la nuit | <MOI> | <DATE> |
| Modèle de message à la direction et aux clients | Claire, Sophie | <DATE> |
| Règle Argo CD : pas d'élagage automatique pendant un incident (procédure de gel) | Karim | <DATE> |
| Rejouer en conditions réelles (M26-E42) | <MOI> | <DATE> |

# Grille d'auto-évaluation — ADR-0040 (M04-E31)

Note ton ADR **avant** de lire l'exemple. 2 points par ligne : 0 absent, 1 partiel, 2 complet et justifié.

| # | Critère | Points |
|---|---|---|
| 1 | Le titre énonce la décision (à l'impératif), pas le sujet | /2 |
| 2 | Le contexte se comprend sans connaître le lab : trois chemins, trois journaux, aucune exclusion mutuelle, exigence d'audit | /2 |
| 3 | Les facteurs de décision sont explicites et réutilisés dans la décision (traçabilité, séparation des rôles, surface d'attaque, concurrence, disponibilité, coût, besoin de l'astreinte) | /2 |
| 4 | Au moins quatre options réelles, dont postes, CI seule, Semaphore seul, CI + Semaphore ; AWX et `ansible-pull` analysés | /2 |
| 5 | Le chemin normal est décrit de la MR à l'application, avec **qui** peut déclencher l'application | /2 |
| 6 | La procédure de bris de glace tient en dix lignes, dit qui, comment c'est tracé, comment on revient au chemin normal, et elle est vérifiable après coup | /2 |
| 7 | La concurrence entre exécutants est traitée par un mécanisme ou une règle explicite (et ses limites dites) | /2 |
| 8 | La dérive : détection, réaction, et la règle « on corrige par une application ou une MR, pas à la main » | /2 |
| 9 | Les secrets : identités Vault, qui détient quoi, renvoi à la rotation | /2 |
| 10 | Le sort de `sem01` est tranché et cohérent avec le PLAN (VMID d'environnement, ou mise à jour de PLAN §4.5 si conservé) | /2 |
| 11 | Les conséquences négatives sont nommées avec leur traitement et le module où il arrive | /2 |
| 12 | Une date ou un seuil de révision de la décision | /2 |

**Total : /24.** En dessous de 16, reprends les lignes à 0 avant de comparer à l'exemple.

## Décisions également valables

L'exemple retient « CI seule » et détruit `sem01`. D'autres décisions sont acceptables si elles sont **justifiées
par les facteurs** et assument leurs conséquences :

- **CI + Semaphore** : acceptable si l'ADR fixe un mécanisme d'exclusion mutuelle (verrou par hôte posé par un
  premier play, avec expiration, ou Semaphore limité à `--check` et aux diagnostics), conserve `sem01` comme
  service (VMID et adresse du socle à réserver dans PLAN §4.5, sauvegarde, supervision, mises à jour) et limite
  sa clé (`from=10.10.20.41`, identité Vault `critique` absente si Semaphore n'applique pas).
- **Semaphore seul** : acceptable si l'ADR traite le journal (rattacher chaque tâche à un commit de `main`), la
  vérification des clés d'hôte et l'accès au dépôt (corrigés en M04-E28), et la disponibilité de `sem01`.

Une décision « on garde les trois chemins » sans exclusion mutuelle ni journal commun n'est pas une décision.

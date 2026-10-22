# Journal de diagnostic — INC-4823 : saturation de la recette de MédiAgenda

**Date** : 2026-10-23 · **Auteur** : <MOI> · **Environnement** : `mediagenda-recette` · **Ticket** : INC-4823
> Exemple de journal (corrigé M21-E23). Les chiffres sont **ceux d'un essai type** : remplace-les
> par les tiens, ce sont tes mesures qui font foi.

## Contexte
Pendant les tests de charge des partenaires, la recette a répondu en plusieurs secondes. On
reproduit la charge par paliers (Job `charge-oha` dans `wb-essais`, `oha` 1.16, 20/50/100 req/s,
3 minutes par palier) et on mesure uniquement par les métriques (Prometheus, tableaux RED et USE).
Julien Petit prévenu à 14:02.

## Référence (10 minutes au calme, 14:05-14:15)
| Mesure | Valeur |
|---|---|
| Débit | 0,3 req/s |
| p95 | 45 ms |
| 5xx | 0 % |
| CPU de l'API (par pod) / limite | 0,02 cœur / 0,5 cœur (LimitRange de l'espace : pas de limite dans le chart) |
| Périodes bridées | 0 % |
| Connexions PostgreSQL (`cnpg_backends_total`) | 6 / `max_connections` 100 |
| Succès du cache (`hit / (hit + miss)`) | 80 % |

## Chronologie et mesures par palier
| Palier | Heure | Débit servi | p95 (appli) | p95 (oha) | 5xx | Périodes bridées | Connexions PG | Succès du cache |
|---|---|---|---|---|---|---|---|---|
| 20 req/s, créneaux | 14:20 | 20 req/s | 60 ms | 75 ms | 0 % | 5 % | 8 | 99 % |
| 50 req/s, créneaux | 14:23 | 48 req/s | 410 ms | 900 ms | 0 % | 55 % | 9 | 99 % |
| 100 req/s, rendez-vous | 14:26 | 61 req/s | 2,4 s | 4,8 s | 0,4 % | 78 % | 20 (2 pods × 10) | — (pas de cache) |

## Hypothèses et vérifications
1. **La base sature ?** Non au palier 50 : 9 connexions, latence des requêtes SQL stable ; le cache
   absorbe les créneaux (99 % de succès). Au palier 100, chaque pod atteint son réservoir de
   **10 connexions** : c'est une conséquence (requêtes plus longues, connexions tenues plus
   longtemps), pas la cause première.
2. **Le CPU de l'API est bridé ?** Oui dès le palier 50 : 55 % des périodes de 100 ms bridées, alors
   que l'utilisation moyenne affichée reste « à 0,5 cœur », c'est-à-dire à la limite. Le pod n'a pas
   de limite dans le chart : c'est le **LimitRange** `limites-defaut` de l'espace (M14-E10) qui lui
   a donné 500m.
3. **Vérification (un seul paramètre changé)** : même charge (palier 50) sur une copie de MédiAgenda
   dans `wb-essais` avec une limite de 2 cœurs (LimitRange de `wb-essais`) : p95 à 70 ms, 0 % de
   périodes bridées. L'écart p95 oha / p95 appli (900 ms contre 410 ms) confirme une attente
   **avant** le traitement (file d'attente de la boucle de l'application et de la passerelle).

## Cause
L'API de recette est limitée à 0,5 cœur par pod (limite injectée par défaut), avec 2 réplicas :
au-delà d'environ 40 req/s sur les créneaux, le processus est bridé, la file d'attente grossit, puis
les connexions à la base sont tenues plus longtemps et le réservoir (10 par pod) sature.

## Recommandations
1. Déclarer explicitement les ressources de l'API dans `mediagenda/deploiement` (overlay recette et
   prod) : requête 250m, limite 1 cœur, ou pas de limite de CPU (choix à argumenter avec Karim,
   ADR-0140) — MR à l'équipe MédiAgenda.
2. Trois réplicas en prod (déjà le cas) et un HPA sur le CPU au palier production (M28).
3. Alerte `MediagendaCpuBride` (plus de 25 % de périodes bridées et p95 au-dessus de 300 ms pendant
   15 min) ajoutée à `regles/alertes-mediagenda.yaml`, testée en CI.
4. Réplicas × taille du réservoir (10) à garder sous `max_connections` de `mediagenda-db`.

## Nettoyage
Job `charge-oha` supprimé (14:40), copie d'essai de `wb-essais` supprimée.

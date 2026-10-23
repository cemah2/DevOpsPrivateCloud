# RB-295 — Non-régression de performance rouge

| | |
|---|---|
| Ticket d'origine | PLAT-3014 (M29-E14) |
| Déclencheur | le pipeline planifié « non-regression-nocturne » de `plateforme/resilience` échoue (courriel de GitLab à la plateforme et à l'équipe MédiAgenda) |
| Qui | la plateforme regarde d'abord l'outillage ; l'équipe de Julien Petit décide pour l'application |
| Délai | avant le passage de la version en recette vers la prod |

## 1. Lire le verdict

Ouvre le job `non-regression-performance` : la fin du journal montre le tableau de `outils/comparer-reference.sh` (p95, p99, erreurs, débit, écart à la référence) ; l'artefact `resultat.json` garde les chiffres 90 jours. Ouvre le tableau Grafana **« Charge k6 — MédiAgenda recette »** (UID `m29-charge-k6`) et choisis l'essai (`testid` = `nuit-<id du pipeline>`).

## 2. L'outil ou l'application ?

| Constat | Cause probable | Preuve | Suite |
|---|---|---|---|
| « Mesure impossible : pas de séries » (code 2) | TestRun en erreur (quota, image, script), écriture distante refusée | journal du job (dernier stage), `kubectl -n k6 get events`, `hubble observe --to-namespace supervision --verdict DROPPED` | outillage : relance à la main (étape 4) sans `cleanup` pour lire les journaux des exécuteurs |
| Débit « INSUFFISANT », latence normale | les exécuteurs n'ont pas pu envoyer la charge (CPU des exécuteurs, quota de `k6`, nœuds pleins) | `k6_vus` au plafond (`maxVUs`), `dropped_iterations` dans les journaux des exécuteurs, `kubectl top pod -n k6` | outillage : augmenter `parallelism` ou les ressources, pas la référence |
| p95/p99 en régression, débit atteint | l'application ou son environnement | p95 **serveur** (histogramme de MédiAgenda) : c'est lui qui fait foi | application : étape 3 |
| Erreurs 5xx | application, base, cache | journaux de MédiAgenda (Loki, locataire `mediagenda`) à l'heure de l'essai | application : étape 3 |

## 3. Régression de l'application

1. Qu'est-ce qui a changé depuis la dernière nuit verte ? Version de l'image en recette (`kubectl -n mediagenda-recette get rollout mediagenda -o jsonpath='{.spec.template.spec.containers[0].image}'` ou le `Deployment` référencé), migrations Flyway, configuration (`mediagenda/deploiement`), plateforme (Argo CD : historique des Applications de la nuit).
2. Une expérience de chaos tournait-elle (`kubectl get networkchaos,stresschaos,podchaos,schedule,workflow -A`) ? Si oui : essai invalide, relance.
3. Ticket `DEV-` à l'équipe MédiAgenda avec le `testid`, les chiffres et le lien du tableau. La version ne part pas en prod tant que la nuit suivante n'est pas verte ou que l'équipe n'a pas accepté l'écart **par écrit**.

## 4. Relancer à la main

Pipeline manuel (`Build → Pipelines → Run pipeline`, branche `main`, variable `NON_REGRESSION=1`). Pour garder les pods et lire leurs journaux, applique le TestRun **sans** `cleanup` depuis `adm01` (identité OIDC de la plateforme) :

```
admin@adm01:~/src/resilience$ sed -e "s/TESTID/debug-$(date +%H%M)/" -e '/cleanup: post/d' charge/distribue/testrun.yaml | kubectl -n k6 apply -f -
admin@adm01:~/src/resilience$ kubectl -n k6 logs -l k6_cr=mediagenda-recette-distribue,runner=true --tail=50
admin@adm01:~/src/resilience$ kubectl -n k6 delete testrun mediagenda-recette-distribue     # à la fin, toujours
```

## 5. Mettre à jour la référence

Seulement quand la performance a changé **volontairement** (nouvelle fonction plus coûteuse acceptée, dimensionnement de la recette modifié, scénario modifié) : MR sur `charge/references/mediagenda-recette.json` avec le `testid` de mesure, la version mesurée, la raison ; approbation de Julien Petit **et** de la plateforme. Jamais pour faire passer une régression. Trois nuits vertes de suite après la MR, sinon on revient en arrière.

## 6. Limites connues

- Une seule mesure par nuit : une nuit rouge isolée sans changement est d'abord relancée (bruit de la recette partagée).
- La recette n'a ni le volume de données ni la charge de la prod : la référence compare la recette **à elle-même**.
- Tout job de `ci-jobs` peut lire Thanos Query (politique `thanos-query-lecture-charge`) : lecture de métriques seulement, accepté (M29-E14).

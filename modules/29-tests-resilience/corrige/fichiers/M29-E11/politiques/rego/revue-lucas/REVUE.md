# Revue des MR !214 (plateforme/politiques) et !37 (plateforme/resilience) — Lucas Martin

> M29-E11, PLAT-3011. Relecteur : <MOI>. Les deux MR sont **refusées en l'état** ; les versions corrigées sont sur la branche `revue-lucas` (`rego/revue-lucas/`, `charge/revue-lucas/`). Gravité : **B** bloquant (faux sentiment de sécurité, donnée de santé, production), **M** majeur (résultat faux), **m** mineur.

## MR !214 — garde-fous des plans

| # | Défaut | Gravité | Preuve | Correction |
|---|---|---|---|---|
| 1 | Syntaxe Rego **v0** (`deny[msg] { … }`) : OPA ≥ 1.0 refuse de charger le fichier | B | `opa test rego/tofu` : `rego_parse_error: 'if' keyword is required before rule body` (« vert chez moi » = OPA 0.68 du poste) | `deny contains msg if { … }` ; migration assistée : `opa fmt --v0-v1` ; outils de l'équipe épinglés (OPA 1.21, conftest 0.71) |
| 2 | `package main.infra` alors que la CI lance `conftest test --namespace tofu` : aucune règle évaluée | B | une fois la syntaxe corrigée : `0 tests, 0 passed … rc=0` sur un plan qui détruit le socle | `package tofu` (ou `--namespace` aligné) ; un test de la CI qui exige au moins un refus |
| 3 | Chemin `rc.after.vm_id` : le format JSON du plan range les valeurs dans `change.after` ; la règle ne se déclenche jamais | B | VMID 5001 accepté | `rc.change.after.vm_id` |
| 4 | Une seule plage 2000-2999 pour tous les états : refuse le socle (1000-1099), accepte un VMID d'un autre module | M | `dns03` en 1050 refusé ; une VM du M29 en 2105 acceptée | plage selon l'état (`data.contexte.etat`, `rego/donnees/plages-vmid.yaml`, M29-E03) |
| 5 | `refuser_destruction` : conftest n'évalue que `deny*`, `violation*`, `warn*` | B | remplacement de `dns02` accepté | renommer en `deny` |
| 6 | `actions[0] == "delete"` ne voit pas un remplacement `["create","delete"]` (`create_before_destroy`) | M | plan de remplacement accepté | `"delete" in rc.change.actions` |
| 7 | Pool en `warn` (ne bloque rien) et `!= "lab"` sur un champ absent = indéfini = silence | M | `pool_id` absent : aucun message | `deny` + `object.get(…, "pool_id", null) != "lab"` |
| 8 | « Toute VM étiquetée socle » : exigence fausse (les VMs d'environnement ne le sont pas) **et** mal écrite (refuse toute VM qui a une autre étiquette que `socle`, même `dns02`) | M | le plan conforme `env-m29` est refusé ; `role-dns, socle` aussi | exigence corrigée (`socle` ou `env-…`), testée sur l'ensemble des étiquettes |
| 9 | Un seul test, qui vérifie qu'un plan correct passe : il reste vert quand aucune règle ne se déclenche | M | défauts 2, 3, 5 invisibles | pour chaque règle, un cas accepté **et** un cas refusé |

## MR !37 — test « 500 req/s »

| # | Défaut | Gravité | Preuve | Correction |
|---|---|---|---|---|
| 10 | Aucun seuil ; les `check()` n'ont jamais fait échouer un test (« les checks font échouer si < 95 % » est faux) ; et `status < 500` accepte les 422 et 409 | B | rejoué sur un MédiAgenda local : **100 % des checks verts, 50 % des requêtes en échec** (toutes les créations en 422), code de sortie 0 | `thresholds` (p95 < 250 ms, échecs < 0,5 %, arrêt à 5 %), check `=== 201` |
| 11 | `sleep(0.1)` et 50 VUs maximum dans un exécuteur à **taux d'arrivée** : le rythme vient de l'exécuteur, la pause occupe les VUs ; une itération fait 3 requêtes (500 it/s ≈ 1 500 req/s) ; k6 perd des itérations (« ce n'est pas une erreur » : si, le débit demandé n'a pas été tenu) | M | même rejeu : 1 627 `dropped_iterations` en 10 s, 333 it/s au lieu de 500 | pas de `sleep`, `rate` en itérations (167 it/s ≈ 500 req/s), `maxVUs` dimensionné, seuil sur `dropped_iterations` |
| 12 | Données de santé réelles : export de la production (noms, NIR, téléphones) copié dans un dépôt et envoyé à la recette ; NIR dans le motif | B | `donnees/patients.csv` | supprimer le fichier **et son historique** (réécriture de la branche de la MR avant fusion, signalement à Sophie Laurent : c'est un incident de données), données factices générées |
| 13 | Cible par défaut = **production**, lancé « hier vers 18 h » ; `insecureSkipTLSVerify: true` ; même créneau pour tous (`dr-morel`, 09:00 sans fuseau) ; rien n'est annulé ; URL par identifiant sans nom (une série par rendez-vous) ; import de `jslib.k6.io` à l'exécution | B | — | recette par défaut et liste d'autorisation ; TLS vérifié ; créneau unique par VU et itération, avec fuseau ; annulation ; `tags: { name }` ; aucune dépendance téléchargée à l'exécution |

**Suites** : ticket SEC- pour le défaut 12 (fichier dans l'historique, accès à l'export, purge) ; demander à Julien ce qui a été vu hier à 18 h en production (charge de 10 min sur la prod) ; binôme avec Lucas sur les tests de Rego (un cas refusé par règle) et sur la lecture du résumé de k6.

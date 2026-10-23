# M29-E11 — Ce que Lucas a proposé

Deux merge requests de Lucas Martin, ouvertes le même jour, à relire avant fusion.

## MR !214 de `plateforme/politiques` — « politiques : garde-fous des plans »

> J'ai ajouté des règles conftest pour bloquer les plans dangereux de `plateforme/infra` : VMID hors plage, destruction du socle, mauvais pool, étiquette manquante. Repris d'un exemple de blog, adapté. Les tests passent chez moi (`opa test rego/tofu`, OPA 0.68 de mon poste). Il suffira d'ajouter `conftest test --namespace tofu -p rego/tofu plan.json` dans le job de plan.

Fichiers : [`politiques/rego/tofu/garde-fous.rego`](politiques/rego/tofu/garde-fous.rego), [`politiques/rego/tofu/garde-fous_test.rego`](politiques/rego/tofu/garde-fous_test.rego).

## MR !37 de `plateforme/resilience` — « charge : test 500 req/s »

> Pour le ticket de Julien (« est-ce que MédiAgenda tient 500 requêtes/s ? »). 50 VUs × 10 itérations par seconde = 500 req/s. J'ai pris de vrais patients pour que ce soit réaliste. Je l'ai lancé hier soir vers 18 h : tout est vert, aucun check en échec (j'ai juste vu des « dropped_iterations » mais ce n'est pas une erreur).

Fichiers : [`resilience/charge/creneaux-charge.js`](resilience/charge/creneaux-charge.js), [`resilience/charge/donnees/patients.csv`](resilience/charge/donnees/patients.csv).

> ⚠️ Les noms et numéros du fichier `patients.csv` sont **inventés** pour l'exercice. Le défaut à relever est ce que le fichier **prétend** être.

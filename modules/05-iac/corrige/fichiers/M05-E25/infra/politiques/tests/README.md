# politiques/tests — un cas qui DOIT échouer par règle maison (M05-E25)

Chaque dossier contient une configuration volontairement fautive (`main.tf.cas`) et un
fichier `ATTENDU` qui donne l'identifiant de la règle qui doit la refuser.
`outils/analyse-securite.sh --tests` copie chaque cas dans un dossier temporaire sous le nom
`main.tf`, lance les analyseurs, et échoue si la règle attendue ne se déclenche pas.

Pourquoi l'extension `.tf.cas` : un vrai `.tf` serait vu par `tofu fmt`, `outils/tofu-valider.sh`
et `tflint --recursive` (E20), qui échoueraient sur ces cas volontairement faux ou incomplets.

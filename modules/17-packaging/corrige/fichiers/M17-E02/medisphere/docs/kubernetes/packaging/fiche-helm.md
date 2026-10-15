# Fiche d'astreinte — lire une release Helm

Public : astreinte (RB-170 pour agir). Toutes les commandes sont **en lecture**, depuis `adm01`, avec ton
identité personnelle. Remplace `<R>` par le nom de la release et `<NS>` par son espace (`helm list -A`).

| Question | Commande | Ce qu'elle montre |
|---|---|---|
| Quelles releases, où, dans quel état ? | `helm list -A` (`-a` pour tous les états, `--failed`, `--pending`) | Nom, espace, révision, statut (`deployed`, `failed`, `pending-upgrade`…), chart et version de l'application |
| Quel chart, quelle version exactement ? | `helm status <R> -n <NS>` ; `helm history <R> -n <NS>` | Révision courante, date, description de chaque révision (installation, montée, retour arrière, échec) |
| Avec quelles valeurs ? | `helm get values <R> -n <NS>` (fournies) ; `… --all` (calculées) | Ce qui a été passé par `-f`/`--set` ; ce que les gabarits ont lu (défauts du chart compris) |
| Les valeurs d'une révision précédente ? | `helm get values <R> -n <NS> --revision <N>` | Pour comparer avant/après une montée |
| Quels objets ont été appliqués ? | `helm get manifest <R> -n <NS>` | Le rendu enregistré (ce que Helm croit avoir appliqué) ; à comparer au cluster avec `kubectl diff -f -` |
| Quels hooks ? | `helm get hooks <R> -n <NS>` | Jobs de migration, tests ; leurs annotations `helm.sh/hook*` |
| Qui possède un champ ? | `kubectl get <objet> -n <NS> -o yaml --show-managed-fields` | Gestionnaire `helm` (opération `Apply` en Helm 4, `Update` pour une release née en Helm 3) ou un autre |
| L'application répond-elle ? | `helm test <R> -n <NS> --logs` | Résultat et journaux des pods de test du chart |
| Quelle révision revenir ? | `helm history <R> -n <NS>` puis RB-170 | Ne **jamais** lancer `helm rollback` sans le runbook : il faut d'abord geler ce qui réconcilie (Helmfile, puis Argo CD au M20) |

Rappels Helm 4 : `--rollback-on-failure` remplace `--atomic` (déprécié), `--force-replace` remplace `--force` ; une
nouvelle release est en *server-side apply*, une release née en Helm 3 le reste en *client-side* (`--server-side=auto`).
Une montée sans `-f` repart des **défauts du chart** : repasser toujours les fichiers de valeurs versionnés.

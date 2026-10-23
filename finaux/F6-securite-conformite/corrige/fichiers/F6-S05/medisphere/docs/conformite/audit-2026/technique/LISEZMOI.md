# Résultats bruts de l'audit technique (F6-S05)

Ce dossier reçoit, par MR, les fichiers de résultats listés au § 6 d'[`audit-technique.md`](../audit-technique.md) (au moins un par outil) : `openscap-scores.json`, `kube-bench-k8s-cp01.json`, `kube-bench-k8s-w01.json`, `kubescape-resume.json`, `images-en-service.json`, `ssh-audit.txt`, `lynis-index.json`.

Le corrigé ne fournit pas de faux résultats : ils viennent de **tes** outils, sur **ton** lab. Avant la MR :
- relire chaque fichier : aucun secret, aucun nom de patient, aucune valeur de variable d'environnement (les résumés de kubescape gardent les identifiants de contrôle, les noms d'objets et les nombres, pas les valeurs) ;
- `sha256sum *` et reporter les empreintes dans le rapport.

# MR !3 — medidoc/chart : premier chart de MédiDoc

**Auteur** : Lucas Martin — **Relecteur demandé** : toi (Karim en copie)

Salut ! Voilà le chart de MédiDoc, sur le modèle de celui de MédiAgenda. Je l'ai testé sur mon kind
perso : `helm install medidoc . -n medidoc-dev --create-namespace` et ça marche (sauf la première fois
où il a fallu relancer). J'ai mis des valeurs par défaut qui marchent tout de suite, comme ça Julien
n'a rien à configurer. Les clés S3 sont celles de mon compte de test, je les changerai plus tard.

J'ai aussi ajouté un jeton d'API généré automatiquement, et la configuration est installée avant le
reste (hook) pour être sûr qu'elle existe quand le pod démarre.

Fichiers : `Chart.yaml`, `values.yaml`, `templates/_helpers.tpl`, `templates/configmap.yaml`,
`templates/secret.yaml`, `templates/deployment.yaml`, `templates/service.yaml`,
`templates/ingress.yaml`, `templates/pdb.yaml`, `templates/NOTES.txt`.

Merci de valider vite, Julien voudrait l'avoir pour vendredi :)

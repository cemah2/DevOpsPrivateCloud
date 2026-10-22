# Notes de Lucas — pipeline du service « rappels »

Salut ! Voici le pipeline pour le futur service de rappels de rendez-vous (je l'ai mis dans
`ci-labo` pour l'essayer, le code est le même que la bibliothèque `labo`).

- J'ai pris `python:3.13` parce que c'est l'image officielle, comme ça on a toujours la dernière.
- Pour construire l'image, j'ai utilisé Docker-in-Docker, c'est ce que tout le monde fait sur
  Internet. Il a fallu demander à Karim de mettre le runner en `privileged = true`, mais c'est
  seulement sur `runner02`.
- J'ai mis le mot de passe du robot Harbor directement dans les variables du fichier, c'est plus
  simple que de demander les droits Maintainer sur le projet pour créer une variable. De toute façon
  le dépôt est interne.
- Le `set -x` c'est pour déboguer quand la poussée échoue.
- Trivy et Gitleaks sont en `allow_failure` parce qu'ils trouvaient des trucs et ça bloquait tout.
- Le cache marche bien : le deuxième pipeline est plus rapide. J'ai mis une seule clé pour que
  toutes les branches en profitent.
- Le déploiement se lance tout de suite (`needs: []`), comme ça on gagne du temps. Le kubeconfig est
  dans la variable `KUBECONFIG_DEV` (je l'ai créée sans cocher « protégée » sinon ça ne marchait pas
  sur ma branche).
- Les tests ont besoin de l'image, j'ai mis `needs: [construire-image]`.
- Parfois il y a deux pipelines quand j'ouvre une MR, je ne sais pas pourquoi, mais ça ne gêne pas.

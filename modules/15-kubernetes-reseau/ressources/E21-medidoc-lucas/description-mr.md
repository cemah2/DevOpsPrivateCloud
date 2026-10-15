# MR !42 — feat(medidoc-dev): exposition de MédiDoc

*Auteur : Lucas Martin*

Salut ! Voici l'exposition de MédiDoc en dev, tout est prêt :

- une Gateway rien que pour MédiDoc (comme ça on ne dérange pas `gw-par1`), avec la même adresse
  que `gw-par1` pour ne pas consommer d'IP du pool ;
- HTTP et HTTPS, le joker est réutilisé grâce à un ReferenceGrant dans `passerelles` ;
- un certificat dédié quand même, d'un an (moins de renouvellements = moins de pannes) ;
- les politiques réseau (j'ai tout ouvert pour l'instant, on resserrera après la démo) ;
- le Secret S3 pour que l'équipe n'ait rien à faire ;
- l'espace en `privileged` parce que sinon les pods ne démarraient pas chez moi.

Testé avec `kubectl apply` sur mon kind, tout est vert. Je peux fusionner demain ?

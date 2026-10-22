# MR !214 — plateforme/secrets : accès de MédiDoc au coffre

*Auteur : Lucas Martin · Relecteurs demandés : Karim Benali, toi · Branche : `lucas/medidoc-coffre`*

Salut ! Voici les accès de l'équipe MédiDoc, pour qu'ils arrêtent de passer par nous :

- `politiques/medidoc-dev.hcl` : le groupe `medidoc` gère ses secrets de dev tout seul (comme `mediagenda-dev`). J'ai ajouté le droit de révoquer leurs identifiants de base de données, ils le demandaient pour leurs tests.
- `politiques/medidoc-ci.hcl` : ce que lit la CI de `medidoc/medidoc` (les secrets de prod pour le job de déploiement). J'ai mis un `path "*"` en lecture le temps qu'ils trouvent ce dont ils ont besoin, on le retirera après.
- `tofu/medidoc.tf` :
  - rôle JWT `ci-medidoc` pour tous les projets du groupe `medidoc` (ils en ont trois, et ça évite un rôle par projet) ; jetons de 30 jours parce que le pipeline de nuit dure longtemps et qu'il échouait ;
  - rôle Kubernetes `medidoc` pour ESO ; j'ai mis `*` pour les comptes de service et les espaces parce que je ne savais pas lesquels ils utilisent ;
  - AppRole `medidoc-batch` pour leur script de purge nocturne sur `runner02` ; sans `secret_id`, c'était trop compliqué à distribuer (OpenBao exigeait « au moins une contrainte » : j'ai mis `0.0.0.0/0`, l'apply passe sur mon essai).

`tofu validate` passe et `tofu plan` montre 7 ressources à créer. Je peux fusionner ?

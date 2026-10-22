# MR !41 — feat(identite): royaume de recette pour MédiAgenda et MédiStat

*Auteur : Lucas Martin — branche `lucas/royaume-recette` → `main` de `plateforme/identite`*

## Pourquoi

Julien veut tester l'authentification de MédiAgenda (interface web) et de MédiStat (nouvel outil de statistiques d'usage) en recette sans risquer de casser le royaume `medisphere`, qui sert à toute la plateforme. Je crée donc un royaume `medisphere-recette`, branché sur le même annuaire pour que les développeurs aient leurs comptes habituels.

## Ce que fait la MR

- `tofu/royaume-recette.tf` : le royaume, la fédération `ipa01` (copiée de `federation-ldap.tf`), le mappeur de groupes, un groupe par défaut pour que personne ne soit bloqué pendant les essais.
- `tofu/clients-recette.tf` : les clients `mediagenda-web` (application monopage) et `medistat` (application serveur), une portée `groupes` adaptée aux développeurs (ils renseignent eux-mêmes leur équipe), le profil utilisateur avec l'attribut `equipe`, les portées par défaut des deux clients.

## Essais

J'ai fait `tofu apply` sur un Keycloak 26.7 lancé sur mon poste (`kc.sh start-dev`), après avoir créé à la main le groupe `plateforme-admins` (pas d'annuaire chez moi). Tout s'applique. Je me connecte à MédiStat avec le script de test de Julien (identifiant et mot de passe), je reçois bien un jeton avec mes groupes. Le second `tofu plan` montre encore une petite mise à jour sur `mediagenda-web`, je pense que c'est un bogue du fournisseur.

## Points d'attention

- Les secrets sont dans le code pour l'instant, je les déplacerai dans le Vault après la revue.
- La fédération utilise le même compte `svc-keycloak` que la production ; son mot de passe est dans le fichier (je l'ai recopié depuis le Vault pour que le plan passe).

/assign @karim.benali

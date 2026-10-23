# Démonstration secrets-v1 — « un secret a fuité, tourne-le devant moi »

> M25-E46. Sophie désigne le secret sur place. Règles : aucune valeur à l'écran (champs lus par
> `-field` vers un fichier 600 ou par l'entrée standard), une boucle de requêtes tourne pendant toute la
> rotation et doit rester verte, l'audit est montré à la fin.

## Préparation (avant la revue)

- Terminal 1 : boucle sans coupure, par exemple
  `while sleep 1; do printf '%s %s\n' "$(date +%T)" "$(curl -s -o /dev/null -w '%{http_code}' https://mediagenda-recette.apps.par1.medisphere.internal/pret)"; done`
  (ou `/pret` de la prod, et un appel de rendez-vous si le secret touche la base).
- Terminal 2 : `bao` avec un jeton `plateforme-admin` de plus d'une heure.
- Grafana : requête d'audit enregistrée « lectures d'un chemin, 7 j ».

## Scénario A — secret statique (`kv/mediagenda/recette/valkey`)

1. Nouvelle valeur côté source (Valkey : `ACL SETUSER` avec **deux** mots de passe le temps de la
   bascule), puis `bao kv patch -mount=kv mediagenda/recette/valkey mdp=-` (valeur sur l'entrée standard).
2. ESO rafraîchit (`kubectl annotate externalsecret … force-sync=$(date +%s) --overwrite`), Reloader
   redémarre les pods en roulement ; la boucle reste à 200.
3. Ancien mot de passe retiré de Valkey ; preuve : `AUTH` avec l'ancienne valeur refusé (sans l'afficher :
   lue depuis la version précédente `bao kv get -version=<N-1> -field=mdp … | valkey-cli --askpass …` : le mot de passe passe par l’entrée standard).
4. Audit : qui a lu `kv/data/mediagenda/recette/valkey` depuis 7 jours (requête RB-250).

## Scénario B — identifiants dynamiques (prod)

1. `bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-prod/` ; révocation **du bail
   désigné** (`bao lease revoke <id>`) ou du préfixe si tout est réputé fuité (`-prefix`, sudo).
2. Le générateur ESO redemande des identifiants au rafraîchissement suivant (forcé), Reloader roule ;
   la boucle reste verte (le pool de connexions se reconnecte).
3. Preuve : le rôle PostgreSQL révoqué n'existe plus (`\du` côté CNPG), connexion avec l'ancien refusée.
4. Audit : émissions `db-mediagenda/creds/mediagenda-api-prod` des 7 jours, par identité.

## Scénario C — secret d'un client OIDC (`grafana`)

1. Rotation du secret du client dans Keycloak avec période de grâce (« secret tourné »), écriture du
   nouveau dans `kv/plateforme/grafana/oidc` (pipeline de rotation E33 ou geste RB-254).
2. ESO puis redémarrage contrôlé de Grafana ; une connexion SSO réussie pendant la démonstration.
3. Fin de la période de grâce (suppression du secret tourné) ; l'ancien est refusé par Keycloak.
4. Audit : lectures de `kv/data/plateforme/grafana/oidc`.

## Ce que Sophie doit voir à la fin

- la boucle sans un seul échec ; l'ancienne valeur refusée ; la nouvelle version dans les
  métadonnées (`bao kv metadata get`), avec `proprietaire` et `rotation` à jour ;
- les lectures des sept derniers jours, par identité et adresse ;
- l'entrée au journal de RB-250 (heure, geste, preuve).

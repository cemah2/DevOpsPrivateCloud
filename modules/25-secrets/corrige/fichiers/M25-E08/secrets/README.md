# plateforme/secrets

Configuration du coffre **OpenBao** de MédiSphère, en code (M25-E08, PLAT-2608).

| Dossier | Contenu |
|---|---|
| `tofu/` | OpenTofu, fournisseur `hashicorp/vault` `~> 5.13` (utilisé contre l'API d'OpenBao) : moteurs, méthodes d'authentification, rôles, groupes d'identité, politiques. État S3 `secrets/terraform.tfstate` (compartiment `tofu-state`, chiffré côté client) |
| `politiques/` | une politique ACL par fichier `<nom>.hcl` ; le nom du fichier est le nom de la politique |
| `outils/` | `charger-acces.sh` (session sur `adm01`), `identifiants-openbao.sh` (identifiants des objets à importer, lecture seule) |

## Règles

1. **Rien à la main dans OpenBao** après M25-E08 : toute modification de configuration passe par une MR de ce projet, relue (Sophie Laurent pour `politiques/`).
2. **Aucune valeur de secret ici**, ni dans le code, ni dans l'état : les valeurs vivent dans `kv/`, écrites par leurs propriétaires ; ce projet ne gère que la configuration. Un secret dont la configuration a besoin (secret du client OIDC) est lu par une ressource **éphémère** et poussé en **écriture seule**.
3. **Pas de jeton racine** : l'application se fait avec le jeton OIDC d'un membre de `plateforme-admins` (`bao login -method=oidc`), le fournisseur en tire un jeton enfant de 20 minutes.
4. Toute ressource nouvelle est essayée contre OpenBao (plan, apply, plan vide) avant d'être fusionnée : le fournisseur vise Vault, certaines ressources (espaces de noms, Sentinel, réplication) n'ont pas d'équivalent.

## Appliquer (palier 1 : depuis `adm01`)

```
admin@adm01:~/src/secrets$ bao login -method=oidc skip_browser=true      # navigateur du poste, tunnel SSH 8250
admin@adm01:~/src/secrets$ . outils/charger-acces.sh
admin@adm01:~/src/secrets$ tofu -chdir=tofu init && tofu -chdir=tofu plan -out=plan.tfplan
admin@adm01:~/src/secrets$ tofu -chdir=tofu apply plan.tfplan && tofu -chdir=tofu plan -detailed-exitcode
```

Le pipeline fait `fmt` et `validate` sur chaque MR ; le plan et l'apply par le pipeline (jeton d'identité de GitLab, méthode `jwt`) arrivent au M25-E10.

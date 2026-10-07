# plateforme/tofu-modules

Modules OpenTofu réutilisables de la plateforme MédiSphère.

| Module | Rôle |
|---|---|
| [`vm-debian`](vm-debian/) | VM Debian 13 clonée de l'image dorée courante, cloud-init, étiquettes d'inventaire |

## Consommer un module

Toujours par une **étiquette de version**, jamais par une branche :

```hcl
module "s3_01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.0.0"
  # …
}
```

- `//vm-debian` : sous-dossier du dépôt ; `?ref=v1.0.0` : étiquette posée par semantic-release.
- Authentification : sur `adm01`, Git réécrit l'URL HTTPS en SSH (`url.<ssh>.insteadOf`,
  clé de l'utilisateur) ; en CI, le job utilise `CI_JOB_TOKEN` (le projet consommateur doit
  figurer dans la liste d'autorisation des jetons de job de ce projet).
- Après un changement de `ref` : `tofu init -upgrade` (sinon le module en cache est conservé),
  puis un plan relu : un module plus récent peut changer des ressources.

## Publier une version

Conventional Commits : `fix(vm-debian): …` → correctif, `feat(vm-debian): …` → mineure,
`feat!:` ou pied `BREAKING CHANGE:` → majeure. **Majeure** dès qu'un consommateur doit changer
son code, ou qu'un plan propose de **recréer** une ressource existante (renommage d'une ressource
sans bloc `moved`, nouvel attribut à remplacement forcé…).

## Contrôles avant MR

```
cd vm-debian && tofu fmt -check -recursive && tofu init -backend=false && tofu validate && tofu test
terraform-docs --output-check vm-debian
```

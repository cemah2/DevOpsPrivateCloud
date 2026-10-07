# Environnements : espaces de travail ou répertoires ?

Décision de l'équipe Plateforme (DEV-625, M05-E15). Révisable avec Terragrunt (M05-E24).

## Décision

- Un environnement **durable**, ou qui diffère des autres (accès, taille, versions de modules
  ou de providers) = **un répertoire** `envs/<environnement>/`, avec sa propre clé d'état
  (`envs/<environnement>/terraform.tfstate`) et donc son propre verrou.
- Les **espaces de travail** (`tofu workspace`) sont tolérés pour des copies **identiques et
  éphémères** d'une même configuration (essai d'une branche, démonstration), détruites dans la
  journée. Jamais pour séparer recette et production, jamais dans `socle/`.

## Pourquoi

| Critère | Espaces de travail | Répertoires |
|---|---|---|
| États et verrous | séparés (`env:/<espace>/…`) | séparés (clé par dossier) |
| Accès différents par environnement | non (même backend, mêmes identifiants) | oui |
| Versions de providers/modules | identiques pour tous | propres à chaque environnement |
| Lisibilité d'une MR | on ne voit pas quel environnement change | le chemin le dit |
| Risque d'erreur humaine | espace courant invisible dans le shell | dossier courant visible |
| Duplication | aucune | backend, provider, versions (Terragrunt, E24) |

La documentation d'OpenTofu le dit aussi : les espaces de travail ne conviennent pas quand les
environnements demandent des identifiants ou des contrôles d'accès différents.

## En pratique

- Nouvel environnement : copier un dossier existant **et changer la clé du backend** (sinon
  deux configurations écrivent le même état : voir la revue de M05-E21).
- Les VMs d'un environnement passent par le module `vm-debian` à une étiquette publiée.
- Essai de M05-E15 : espaces `recette` et `dev` sur `~/m05/e15/espaces/`, supprimés ; il n'en
  reste que l'historique des versions sous `env:/` dans `tofu-state`.

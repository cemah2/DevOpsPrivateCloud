# Plan de référence « dangereux » (M29-E19)

`plan-dangereux.json` est la sortie `tofu show -json` (format 1.2, OpenTofu 1.13) d'un plan de `plateforme/infra` qui :

- **supprime** la VM du socle `nbx01` (VMID 1005, étiquettes `socle` et `role-netbox`, protégée) : son bloc `module "nbx01"` a disparu de la configuration (`action_reason: delete_because_no_resource_config`) ;
- **crée** une VM `essai-lucas` **sans aucune étiquette**, non protégée, avec un VMID de la plage du socle (1099).

Les politiques de `plateforme/politiques/rego/tofu/` (M29-E03) doivent le refuser. C'est le **cas de référence** de la chaîne de validation : on le rejoue pour prouver que le filet attrape encore.

```
admin@adm01:~/src/politiques$ conftest test -p rego/tofu <ARGUMENTS-DE-LA-CI> ~/DevOpsPrivateCloud/modules/29-tests-resilience/ressources/E19-plan-dangereux/plan-dangereux.json
```

`<ARGUMENTS-DE-LA-CI>` : exactement ce que passe le job de plan de `plateforme/infra` (modèle `.validation:conftest-plan` du composant `validation`, M29-E10) : les options d'espaces (`--namespace …` ou `--all-namespaces`), les données (`--data rego/donnees`) et le contexte que le job écrit (`--data contexte.json`, ici `{"contexte": {"etat": "socle", "etiquettes_mr": []}}` : le plan touche l'état `socle`). Lis-les dans le composant et dans le `.gitlab-ci.yml` du projet, pas de mémoire. Sans le contexte, la règle « contexte absent » refuse le plan à elle seule : le refus ne prouve alors rien sur les autres règles.

Le fichier est **fabriqué** pour l'exercice (aucun identifiant, aucun secret) ; il ne contient que les champs que lisent des politiques usuelles (`resource_changes[].change.actions`, `before`, `after`, `tags`, `vm_id`, `protection`).

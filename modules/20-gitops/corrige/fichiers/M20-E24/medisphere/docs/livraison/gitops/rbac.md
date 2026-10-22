# Droits dans Argo CD (RBAC)

| | |
|---|---|
| Ticket | SEC-2124 |
| Exercice | M20-E24 |
| Politique | `plateforme/k8s`, `releases/argocd/policy.csv` (seule source) |
| Tests | `releases/argocd/rbac-tests.txt`, joués par `outils/argocd-rbac-tests.sh` (job `argocd-rbac`) |
| Dernière revue | <DATE> |

## Modèle

- Politique Casbin dans `argocd-rbac-cm` : `p, <sujet>, <ressource>, <action>, <objet>, <effet>` et `g, <compte ou groupe>, <rôle>`. L'objet vaut `<projet>/<application>` pour `applications`, `applicationsets`, `logs`, `exec` ; le nom du projet pour `projects` ; l'URL pour `clusters` et `repositories`.
- Un `deny` qui correspond l'emporte sur tous les `allow`, quel que soit l'ordre des lignes.
- `policy.default` est évalué **avant** la politique du compte : ce qu'il autorise ou refuse ne peut plus être changé. Il est **vide** : un compte qui n'est cité nulle part ne voit rien.
- Rôles intégrés (`assets/builtin-policy.csv`) : `role:readonly` (lecture de tout **y compris les journaux des pods**), `role:admin` (tout, terminal compris, hérite de `role:readonly`). Le compte `admin` est lié à `role:admin` par la politique intégrée : c'est `admin.enabled: "false"` dans `argocd-cm` qui le neutralise, pas le RBAC.
- Depuis Argo CD 3.0 : `update` et `delete` sur une Application ne portent que sur l'objet Application ; sur ses ressources, il faut `update/<groupe>/<kind>/<espace>/<nom>` (ou `update/*`). Le comportement d'avant se retrouve avec `server.rbac.disableApplicationFineGrainedRBACInheritance: "false"` (non retenu).
- `override` : synchroniser des manifestes locaux ou, avec `application.sync.requireOverridePrivilegeForRevisionSync: "true"` (posé en E25), une autre révision que celle de l'Application. Réservé aux administrateurs.
- Comptes locaux : pas de point dans le nom (la clé `accounts.<nom>` d'`argocd-cm` est découpée sur les points).

## Rôles

| Rôle | Où | Comptes ou groupes | Raison |
|---|---|---|---|
| `role:plateforme-admin` | `policy.csv` (hérite de `role:admin`) | `<MOI>`, `karim-benali` | exploitation de la plateforme |
| `role:mediagenda-equipe` | `policy.csv` | `julien-petit` | livrer dev et recette, voir la production |
| `role:lecture` | `policy.csv` | `nadia-roussel`, `ci-lecture` | support, astreinte, vérifications ; **sans** journaux des pods (données de santé possibles : ils se lisent dans Loki au M22, par locataire) |
| `proj:mediagenda:equipe` | AppProject `mediagenda` | groupe SSO `medisphere:mediagenda-devs` (M24) | même droits que `role:mediagenda-equipe`, portés par le projet |
| `proj:medidoc:equipe` | AppProject `medidoc` | groupe SSO `medisphere:medidoc-devs` (M24) | équipe MédiDoc, dev et recette |

Rôle global ou rôle de projet ? Un rôle de **projet** est écrit avec le projet (MR sur `plateforme/gitops`), ne peut donner de droits que dans ce projet (Argo CD refuse un objet qui en sort) et peut porter des **jetons JWT** propres au projet (`argocd proj role create-token`) pour une automatisation limitée à ce projet, révocables un par un. Un rôle **global** traverse les projets (lecture, administration). On n'affecte pas un compte **local** à un rôle de projet : en SSO, un groupe de même nom recevrait les mêmes droits.

## Matrice

`O` autorisé, `—` refusé (par absence d'`allow` ou par `deny` explicite, marqué `D`).

| Action | plateforme-admin | mediagenda-equipe | lecture | inconnu |
|---|---|---|---|---|
| lire les Applications de tous les projets | O | — (seulement `mediagenda/*`) | O | — |
| synchroniser `mediagenda-dev`, `mediagenda-recette` | O | O | — | — |
| synchroniser `mediagenda-prod` | O | D | — | — |
| actions sur le Rollout de recette (promouvoir, interrompre) | O | O | — | — |
| actions sur le Rollout de production | O | D | — | — |
| supprimer une Application | O | D | — | — |
| `override` (manifestes locaux, autre révision) | O | D | — | — |
| journaux des pods dev et recette | O | O | — | — |
| journaux des pods de production | O | — | — | — |
| terminal web (`exec`) | O (désactivé : `exec.enabled: false`) | D | — | — |
| projets, clusters, dépôts, certificats : lire | O | projet `mediagenda` seulement | O | — |
| projets, clusters, dépôts : modifier | O | — | — | — |

## Garde-fous et tests

- Les `deny` de `role:mediagenda-equipe` sur la production, `delete`, `override` et `exec` ne servent à rien **aujourd'hui** (aucun `allow` ne les ouvre) : ils protègent contre l'`allow` trop large de demain. Essai fait : remplacer `sync, mediagenda/mediagenda-dev` par `sync, mediagenda/*` ne change aucun résultat de test (le `deny` tient) ; le faire **et** retirer le `deny` fait échouer le test « non julien-petit sync applications mediagenda/mediagenda-prod ». Les deux couches sont nécessaires : les tests disent ce qui doit être vrai, les `deny` rendent la politique robuste aux erreurs.
- Règle de MR : tout nouveau droit arrive avec un test « oui » et un test « non » qui montre sa limite.
- `argocd admin settings rbac can` sort en 1 pour « No » comme pour une erreur : le script lit la sortie. La commande veut un kubeconfig même avec `--policy-file` : un kubeconfig factice (avec un jeton) suffit.
- Avertissement attendu au chargement : `user defined roles not found in policies: role:admin,role:plateforme-admin` (un rôle qui n'a que des héritages n'a pas de ligne `p` à lui) ; sans conséquence.

## Vérifications sur le cluster

```
admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username julien-petit
admin@adm01:~$ argocd account can-i sync applications mediagenda/mediagenda-recette    # yes
admin@adm01:~$ argocd account can-i sync applications mediagenda/mediagenda-prod       # no
admin@adm01:~$ argocd app sync mediagenda-prod
FATA[0000] rpc error: code = PermissionDenied desc = permission denied: applications, sync, mediagenda/mediagenda-prod, sub: julien-petit, …
```

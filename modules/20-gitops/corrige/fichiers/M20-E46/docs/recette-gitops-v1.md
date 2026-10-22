# Recette gitops-v1 (M20-E46, PLAT-2146)

> Exemple de dossier de recette rempli. Les numéros de MR et de pipelines sont ceux de ton lab.

| # | Exigence | Preuve | Écart éventuel et sa justification |
|---|---|---|---|
| 1 | Toutes les applications sous ApplicationSets, racine Synced | `argocd app list` (racine, applications, projets, mediagenda-dev/recette/prod, medidoc-dev/recette, labo) ; `kubectl get applications -n argocd -o json \| jq '.items[] \| {n: .metadata.name, owner: .metadata.ownerReferences[0].name}'` | `labo` reste une Application simple (application d'essai, projet labo) |
| 2 | Aucune écriture de la CI dans les espaces applicatifs | `lab/bin/check 20 30` ; `.gitlab/agents/k8s-par1/config.yaml` (ci_access : wb-essais seul) | — |
| 3 | Canary + analyses en recette et en production | `kubectl argo rollouts get rollout mediagenda -n mediagenda-prod` ; AnalysisRuns `Successful` | — |
| 4 | Une mise en production complète par MR, avec notification reçue | MR de promotion !91, synchro manuelle de prod (`argocd app sync mediagenda-prod`), courriel `on-deployed` dans Mailpit | — |
| 5 | Notifications (échec, dégradation, déploiement de prod) | `kubectl -n argocd get cm argocd-notifications-cm -o yaml` ; `lab/bin/check 20 19` | ajout `on-sync-status-unknown` (post-mortem INC-4743) |
| 6 | Fenêtres de synchronisation et gel des changements | `argocd proj windows list mediagenda` ; `politique-changements.md` | — |
| 7 | RBAC par équipe, admin désactivé | `lab/bin/check 20 24` ; `argocd admin settings rbac can …` (tests versionnés) | — |
| 8 | Durcissement d'Argo CD | `lab/bin/check 20 25` | — |
| 9 | `lyo-k3s01` et `flux01` détruites, état `envs/m20` vide | `tofu -chdir=envs/m20 destroy` (CHG-2146), `tofu state list` vide, `pvesh get /cluster/resources --type vm` | — |
| 10 | Flux réseau du M20 retirés, DNS et NetBox nettoyés | MR de plateforme/ansible (pare_feu.yml), `nft list ruleset` sur gw01/gw02, `dig lyo-k3s01.par1.medisphere.internal` NXDOMAIN | — |
| 11 | Plus aucun cluster distant enregistré | `argocd cluster list` (in-cluster seul) ; Secret `cluster-lyo-k3s01` retiré par secrets-k8s.sh | ApplicationSet `labo-agences` conservé, sans cluster ciblé |
| 12 | Documentation | `docs/livraison/gitops/` : ADR-0200, RB-200 (+ sections des pannes), promotion, politique-changements, comparatif-flux, sous-le-capot | — |
| 13 | Étiquette `gitops-v1` | `git tag -n gitops-v1` sur plateforme/medisphere | — |

Contrôle global :

```
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 20 46
…
Bilan : 74 OK, 0 KO, 0 ignoré(s)
Exercice validé.
```

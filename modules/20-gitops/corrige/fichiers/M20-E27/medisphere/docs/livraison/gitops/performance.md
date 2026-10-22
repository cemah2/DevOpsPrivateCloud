# Argo CD : haute disponibilité et réactivité

| | |
|---|---|
| Ticket | PLAT-2127 |
| Exercice | M20-E27 |
| Code | `plateforme/k8s` : `composants/argocd/values-ha.yaml`, `outils/argocd-webhooks-gitlab.sh` ; Vault `secrets/argocd.yml` (`argocd_webhook_gitlab_secret`) |
| Dernière revue | <DATE> |

## Ce qui est sans état, ce qui ne l'est pas

| Composant | État | Réplicas | Ce que coûte la perte d'un pod |
|---|---|---|---|
| `argocd-server` | aucun (sessions = jetons signés par `server.secretkey`) | 2 | rien : l'autre répond (Service, PDB) |
| `argocd-repo-server` | cache disque des dépôts, cache Redis des manifestes | 2 | un clonage et un rendu de plus |
| `argocd-application-controller` | **partition** : chaque réplica gère des **clusters** | 2 (`ARGOCD_CONTROLLER_REPLICAS=2`) | les clusters de la partition perdue ne sont plus réconciliés jusqu'au redémarrage du pod (StatefulSet : même nom, même partition) ; pas de reprise par l'autre réplica sans distribution dynamique (alpha) |
| `argocd-applicationset-controller` | aucun ; élection d'un meneur | 2 | l'autre prend la main (quelques secondes) |
| `argocd-redis` | cache seulement | 1 | recalcul des caches ; l'interface est lente une à deux minutes |

## Partitionnement

Deux clusters gérés (`in-cluster`, `lyo-k3s01`), deux réplicas. L'algorithme par défaut (`legacy`) place `in-cluster` sur la partition 0 et un cluster déclaré sur `empreinte(UID du Secret) mod 2` : les deux clusters pouvaient se retrouver sur la partition 0. Le champ `shard: "1"` du Secret de `lyo-k3s01` le place explicitement sur la partition 1.

```
admin@adm01:~$ argocd admin cluster stats --namespace argocd
SERVER                                            SHARDS  APPS  RESOURCES
https://kubernetes.default.svc                    0       11    1843
https://lyo-k3s01.par1.medisphere.internal:6443   1       1     9
```
(Sortie illustrative, non relevée sur un lab : colonnes et valeurs exactes à relever sur le tien. La commande lit le cache Redis par une redirection de port : elle exige ton kubeconfig.)

Conclusion : le second réplica du contrôleur n'allège pas le travail sur `in-cluster` (presque tout) ; il évite qu'une panne de nœud arrête **tous** les clusters et prépare d'autres agences. Pour répartir la charge d'un seul gros cluster, Argo CD n'offre rien : on augmente `controller.status.processors`/`operation.processors` et les ressources du réplica.

## Redis

**Décision : pas de `redis-ha`.** Redis n'est qu'un cache (documentation : « disposable cache, can be safely rebuilt without service disruption »). Le mode HA du chart demande trois Redis avec Sentinel et trois HAProxy, en anti-affinité **stricte** sur trois nœuds : `k8s-par1` n'a que deux travailleurs sans taint (`k8s-w03` est réservé aux bases), et ses images viennent de `ecr-public.aws.com`, hors de nos caches Harbor. Coût évité : six pods et environ 600 Mio. À revoir si l'interface devient inutilisable pendant les redémarrages de Redis, ou avec un troisième travailleur généraliste.

## Webhooks

- GitLab → `https://argocd.apps.par1.medisphere.internal/api/webhook`, événements de *push*, TLS vérifié, jeton secret (`X-Gitlab-Token`) = `webhook.gitlab.secret` d'`argocd-secret`, qui **référence** le Secret `argocd-webhook-gitlab` (`$argocd-webhook-gitlab:secret`).
- Projets : `plateforme/gitops`, `mediagenda/deploiement`, `medidoc/deploiement`, `formation/gitops-labo` (script idempotent `outils/argocd-webhooks-gitlab.sh`).
- GitLab : liste d'autorisation des requêtes locales = `argocd.apps.par1.medisphere.internal` (et `10.10.41.10`) ; « Autoriser les requêtes vers le réseau local » reste **désactivé** pour tout le reste.
- Bordure : `git01` → 10.10.41.10:443.

Ce qu'un webhook ne signale pas : une nouvelle version d'un chart OCI dans Harbor (le chart est épinglé : rien à voir de toute façon), un dépôt suivi sans webhook, un webhook perdu (GitLab indisponible, refus réseau). D'où l'interrogation périodique gardée, ralentie à 300 s + 60 s de gigue.

## Mesures

Délai entre la fusion d'une MR triviale sur `mediagenda/deploiement` (`overlays/dev`) et `status.operationState.startedAt` de `mediagenda-dev`, 10 essais :

| Configuration | Min | Médiane | Max |
|---|---|---|---|
| Interrogation 120 s + gigue 60 s, sans webhook | <ex. 18 s> | <ex. 1 min 54 s> | <ex. 2 min 58 s> |
| Webhooks, interrogation 300 s + 60 s | <ex. 2 s> | <ex. 4 s> | <ex. 9 s> |

Mémoire (somme des `kubectl top pods -n argocd`) : avant <ex. 610 Mio>, après <ex. 1 020 Mio> ; demandes mémoire : +≈ 1,2 Gio (un réplica de plus de chaque composant).

Essai de panne (drainage de `k8s-w02` pendant `argocd app list` toutes les 5 s et une fusion) : <heure>, <nombre d'échecs de la boucle>, <délai de synchronisation observé>, <partition touchée>.

# Clusters gérés par l'Argo CD de `k8s-par1`

| | |
|---|---|
| Ticket | PLAT-2126 |
| Exercice | M20-E26 |
| Dernière revue | <DATE> |

## Clusters

| Nom | Serveur | Espaces gérés | Objets de cluster | Partition (E27) | Étiquettes | Compte côté cluster |
|---|---|---|---|---|---|---|
| `in-cluster` | `https://kubernetes.default.svc` | tous | oui | 0 | — | compte de service du contrôleur (ClusterRole du chart) |
| `lyo-k3s01` | `https://lyo-k3s01.par1.medisphere.internal:6443` | `agence` | non | 1 | `site=lyo1`, `medisphere.internal/environnement=agence` | `agence/argocd-gestion` (Role dans `agence` seulement) |

## Enregistrement déclaratif

Le cluster est un Secret de l'espace `argocd` portant `argocd.argoproj.io/secret-type: cluster`, créé par `plateforme/k8s/outils/secrets-k8s.sh` (composant `argocd`) à partir du Vault (`secrets/argocd.yml` : jeton et autorité). Pas de `argocd cluster add` : cette commande crée un compte `argocd-manager` **cluster-admin** dans le cluster cible, ce que la RSSI refuse.

Champs utilisés (documentation *Declarative Setup*, section *Clusters*) :

- `name`, `server` : le nom doit figurer dans le certificat du serveur d'API (`tls-san` de k3s).
- `namespaces: agence` : le contrôleur ne surveille **que** cet espace. Sans ce champ, il essaie de lister et surveiller tous les types de **tout** le cluster ; avec un compte limité à un Role, chaque refus fait échouer son cache (`Failed`). Un compte à droits limités impose donc `namespaces`.
- `clusterResources: "false"` : Argo CD ne gère aucun objet de cluster (Namespace, CRD, ClusterRole) sur ce cluster, même si un projet l'autorisait.
- `config` : `bearerToken` (jeton du compte de service) et `tlsClientConfig` avec `caData` (autorité du serveur d'API de k3s, PEM encodé en base64) et `insecure: false`. `insecure: true` accepterait n'importe quel serveur se présentant à cette adresse : le jeton partirait chez lui.
- `resource.respectRBAC: normal` dans `argocd-cm` : même dans `agence`, le compte n'a pas le droit de lister les Secrets, les Roles… Le contrôleur retire de sa surveillance les types qu'on lui refuse au lieu de tomber en erreur.
- `shard: "1"` (E27) : le cluster est placé sur la seconde partition du contrôleur.

État de connexion d'un cluster **sans** Application : `Unknown` (« Cluster has no applications and is not being monitored ») : le contrôleur ne maintient de cache que pour les clusters qui ont des Applications. Il passe à `Successful` à la première Application.

## Deux niveaux de défense

| Essai | Refusé par | Message |
|---|---|---|
| Application de test du projet `labo` vers `lyo-k3s01`, espace `kube-system` | l'AppProject `labo` (destination non autorisée) | `application destination server '…' and namespace 'kube-system' do not match any of the allowed destinations in project 'labo'` |
| Même essai depuis un projet qui autoriserait `kube-system` (projet d'essai) | le cluster (le compte `argocd-gestion` n'a pas de droit dans `kube-system`), et avant lui Argo CD, qui ne gère que les espaces listés dans `namespaces` | `… namespace 'kube-system' is not managed` (texte exact à relever sur ton lab) |
| Objet de cluster (Namespace) dans `agence/` | l'AppProject (`clusterResourceWhitelist` vide) puis `clusterResources: "false"` | `Cluster level Namespace … can not be managed when in namespaced mode` (à relever) |

## Exploitation

- Ajouter une agence : VM + k3s + `argocd-gestion.yaml` (playbook), Secret de cluster (Vault + `secrets-k8s.sh`) avec `site=<agence>`, destination dans l'AppProject. L'ApplicationSet `labo-agences` (ou son successeur) n'a pas à changer.
- Rotation du jeton : supprimer `agence/argocd-gestion-jeton` sur le cluster (k3s le recrée depuis le dossier des manifestes au redémarrage ou par un nouveau passage du playbook), reporter le nouveau jeton dans le Vault, relancer `secrets-k8s.sh appliquer argocd`.
- Flux : `K8S_TRAV` → 10.10.99.61:6443 (bordure) et sortie `toFQDNs` `lyo-k3s01.par1.medisphere.internal:6443` de la politique `argocd-application-controller`.
- Retrait (mini-projet) : supprimer le Secret de cluster **après** l'Application (ou en sachant que l'Application devient `Unknown`), retirer la destination du projet, la règle de bordure et la sortie de la politique, `lyo_k3s01 = false` dans `envs/m20`.

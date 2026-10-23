# Locataires (Capsule)

> Plateforme développeurs — M28-E05 (PLAT-2905). Responsable : équipe Plateforme. Relu par : Sophie Laurent (sécurité), Julien Petit (équipes).

## Modèle

| Locataire | Propriétaire (groupe OIDC) | Environnements rattachés | Espaces au plus | Budget du libre-service |
|---|---|---|---|---|
| `mediagenda` | `oidc:mediagenda` | `mediagenda-dev`, `-recette`, `-prod`, `-secours` | 7 | 2 CPU, 4 Gi demandés ; 8 Gi de limites ; 30 pods ; 5 PVC / 20 Gi |
| `medinotif` | `oidc:mediagenda` (l'équipe de Julien possède MédiNotif) | `medinotif-recette`, `-prod` | 4 | 1 CPU, 2 Gi ; 4 Gi ; 15 pods ; 5 PVC / 20 Gi |
| `medidoc` | `oidc:medidoc` | `medidoc-dev`, `-recette` | 5 | 2 CPU, 4 Gi ; 8 Gi ; 30 pods ; 5 PVC / 20 Gi |

Définitions : `plateforme/k8s/locataires/` (Application `locataires`). Composant : Capsule 0.15.1 (Application `capsule`, espace `capsule-system`).

## Qui a quels droits, où

| Espace | Équipe | Plateforme | Argo CD |
|---|---|---|---|
| Environnements (`…-dev`, `-recette`, `-prod`, `-secours`) | `view` (propriétaire Capsule, `clusterRoles: [view]`) ; `edit` sur `mediagenda-dev` (liaison `oidc-mediagenda-edition` du M24, conservée) | inchangé | livre, inchangé |
| Libre-service (`<locataire>-<nom>`, créé par l'équipe) | `admin` + suppression de l'espace (règle du `Tenant`, sélecteur « sans étiquette `medisphere.internal/environnement` ») | inchangé | rien (rien n'y est déclaré dans Git) |

Ce qui distingue un environnement d'un espace de libre-service : l'étiquette `medisphere.internal/environnement`, posée par la plateforme (`plateforme/k8s/espaces/`) et **interdite** aux équipes (`namespaceOptions.forbiddenLabels`). Un environnement sans cette étiquette donnerait `admin` à l'équipe : `lab/bin/check 28 05` le vérifie.

Les équipes ne sont pas administratrices par défaut sur la production : Capsule donne `admin` et `capsule-namespace-deleter` à tout propriétaire **dans tous les espaces** du locataire si l'on ne fixe pas `owners[].clusterRoles`.

## Ce que Capsule ajoute

- **Création d'espaces en libre-service** : un utilisateur Capsule (groupes `oidc:mediagenda`, `oidc:medidoc` de la `CapsuleConfiguration`) crée `mediagenda-<nom>` ; le préfixe désigne le locataire (`forceTenantPrefix`), le nombre d'espaces est plafonné, Pod Security `restricted` et les étiquettes `medisphere.internal/libre-service: "oui"`, `…/proprietaire` sont posés d'office.
- **Budget du libre-service** : une `GlobalResourceQuota` `<locataire>-libre-service` (règle `quota` du `Tenant`), répartie en `ResourceQuota` `capsule-global-quota-…` dans chaque espace de libre-service. `spec.resourceQuotas` (déprécié en 0.15) n'est pas utilisé.
- **Classes de stockage** : `ceph-rbd` seule, et par défaut pour un PVC sans classe.
- **Liaisons RBAC** dans chaque espace (`capsule-<locataire>-…`).

## Ce que Capsule ne fait pas (ici)

- **Réseau** : aucune politique posée dans les espaces de libre-service (les `networkPolicies` du `Tenant` sont dépréciés au profit des réplications `TenantResource`) ; les cloisons entre équipes restent les CiliumNetworkPolicy de la plateforme (M15). À traiter au palier 3 (M28-E15).
- **Signatures d'images** : Kyverno (M26) les vérifie dans les espaces `recette` et `prod` ; un espace de libre-service n'y est pas soumis. Écart connu, M28-E15.
- **Nœuds, noyau, plan de contrôle** : partagés (multi-locataire souple).

## Cohabitation

| Mécanisme | Où | Effet cumulé |
|---|---|---|
| Pod Security (M26) | étiquette de chaque espace | `restricted` partout ; Capsule le pose sur le libre-service, l'équipe ne peut pas l'abaisser |
| Kyverno (M26) | politiques de cluster | inchangé ; s'applique avant ou après Capsule selon l'ordre des webhooks, tous doivent accepter |
| Quotas de la plateforme | `plateforme/k8s/espaces/<espace>/` | intacts sur les environnements ; Kubernetes applique **tous** les ResourceQuota d'un espace |
| Budget du locataire | `GlobalResourceQuota` | libre-service seulement : un bac à sable ne peut pas affamer la production |
| Argo CD | Applications des équipes | toujours `Synced` : Capsule ne contraint pas ses requêtes (pas un utilisateur Capsule) ; les objets posés par Capsule sont ignorés par la surveillance des orphelins (AppProjects) |

⚠️ **Dépendance forte.** Les webhooks de Capsule sont en `failurePolicy: Fail` : sur **tous** les objets d'espace des espaces rattachés (création, mise à jour) et sur **tous** les espaces du cluster (création, mise à jour, suppression). Capsule arrêté = plus de création de pod dans `mediagenda-prod`, plus de `task espaces`. Le contrôleur passe à deux réplicas et est supervisé au palier 3 (M28-E16 et E21).

## Essai de Sophie (relevé)

| Action, en tant que `oidc:julien.petit` / `oidc:mediagenda` | Résultat |
|---|---|
| `kubectl create namespace mediagenda-essai-julien` | créé ; étiquettes `pod-security.kubernetes.io/enforce=restricted`, `capsule.clastix.io/tenant=mediagenda` |
| `kubectl create namespace essai-julien` | refusé par le webhook de Capsule (préfixe d'aucun locataire de Julien) |
| `kubectl create namespace medidoc-essai` | refusé (locataire dont Julien n'est pas propriétaire) |
| PVC `cephfs` dans `mediagenda-essai-julien` | refusé (classe non autorisée) |
| `kubectl -n mediagenda-prod delete deploy mediagenda` | `forbidden` (RBAC : `view`) |
| Création d'espaces au-delà de 7 | refusé (« Cannot exceed Namespace quota ») |
| `kubectl delete namespace mediagenda-essai-julien` | supprimé |

## Retour arrière

1. Pour chaque espace : retirer la référence de propriétaire et l'étiquette `capsule.clastix.io/tenant` (`kubectl patch namespace … '{"metadata":{"labels":{"capsule.clastix.io/tenant":null},"ownerReferences":[]}}'`), et l'étiquette de `plateforme/k8s/espaces/`.
2. Seulement ensuite : retirer `preventDeletion`, puis les `Tenant`.
3. Désinstaller Capsule (Application `capsule`) : ses *jobs* de suppression retirent ses webhooks.

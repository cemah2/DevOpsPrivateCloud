# Essais d'isolation des locataires

> Essai d'intrusion d'un propriétaire de locataire (M28-E15, SEC-2915). Compte d'essai `essai-medidoc` (groupe `medidoc` seul), contexte kubectl à part, espace `medidoc-essai-isolation`. Rejouer : avant chaque montée de Capsule, de Kyverno ou de Kubernetes, et à chaque nouveau locataire.
> Résultats du lab de référence ; remplace-les par les tiens (commandes et messages exacts dans les annexes de la MR).

## 1. Résultats

| # | Essai | Avant correction | Couche | Après correction |
|---|---|---|---|---|
| 1a | `kubectl create ns projet-x` | **refusé** : *The namespace doesn't match the tenant prefix* | Capsule (`forceTenantPrefix`) | refusé |
| 1b | `kubectl create ns medidoc-essai-isolation` | accepté (attendu), étiquettes PSA `restricted` et `libre-service` posées par Capsule (E05), **sans** NetworkPolicy | — | accepté, avec en plus la NetworkPolicy `refus-par-defaut` |
| 2a | étiquette `pod-security.kubernetes.io/enforce=privileged` sur l'espace | refusé par Capsule (`forbiddenLabels`, E05) | Capsule | refusé (Capsule, puis Kyverno `locataires-pod-security`, second verrou) |
| 2b | pod privilégié dans `medidoc-essai-isolation` | refusé : *violates PodSecurity "restricted:latest"* (étiquettes posées par Capsule, E05) | PSA | refusé |
| 3a | pod qui tolère `node-role.kubernetes.io/control-plane` + `nodeSelector` sur `k8s-cp01` | **accepté**, planifié sur `k8s-cp01` | **trou n°3** | refusé par Kyverno `locataires-placement` |
| 3b | pod avec `spec.nodeName: k8s-cp01` | **accepté** (contourne l'ordonnanceur) | **trou n°3** | refusé par Kyverno `locataires-placement` |
| 4 | Service `LoadBalancer`, `NodePort`, puis `ExternalName` vers `git01` | `LoadBalancer` et `NodePort` refusés par le budget du libre-service (`services.loadbalancers: "0"`, `services.nodeports: "0"`, E05) — refus « par quota », pas par conception ; **`ExternalName` accepté** | **trou n°4** | refusés par Capsule (règle `enforce` `deny` sur les trois types) |
| 5a | `kubectl -n mediagenda-recette get secrets` | refusé : *cannot list resource "secrets"* | RBAC | refusé |
| 5b | `kubectl -n medidoc-dev get secrets` ; puis `-n medidoc-essai-isolation` | `medidoc-dev` : refusé (`view` sur les environnements, E05) ; libre-service : accepté (`admin`, attendu) | RBAC | idem — d'où « aucun secret écrit à la main : ESO » |
| 6a | `RoleBinding` vers `cluster-admin` | refusé : *attempting to grant RBAC permissions not currently held* | RBAC (prévention de l'escalade) | refusé |
| 6b | `RoleBinding` vers `admin` dans `medidoc-essai-isolation`, puis dans `medidoc-dev` | accepté dans le libre-service (attendu) ; refusé dans `medidoc-dev` (`view`) | RBAC | idem |
| 7a | NetworkPolicy « tout ouvert » puis `curl` vers un pod de `mediagenda-recette` | **joint** depuis l'espace de libre-service (aucune cloison) ; refusé depuis `medidoc-dev` (`isolement-medidoc-dev`) | **trou n°2** | refusé (CCNP `isolement-locataire-medidoc`, verdict `DROPPED` dans Hubble) |
| 7b | vers l'API de RabbitMQ (15671) | refusé (`refus-par-defaut` de `messagerie`) | Cilium | refusé |
| 8a | PVC en classe `ceph-rbd-retain` | refusé par Capsule (classes autorisées) | Capsule | refusé |
| 8b | `priorityClassName: medisphere-critique` | refusé par Capsule (classes autorisées, E14) | Capsule | refusé |
| 8c | image `docker.io/library/nginx` | refusé par Kyverno `registres-autorises` | Kyverno | refusé |

## 2. Trous et corrections

| Trou | Cause | Correction (MR) |
|---|---|---|
| 1 — PSA (pas un trou, verrou unique) | les étiquettes PSA du libre-service reposent sur le seul Capsule (E05) ; le cluster n'a pas de niveau par défaut : une erreur dans le Tenant suffirait | second verrou : Kyverno `locataires-pod-security` refuse un espace de locataire sans `restricted` |
| 2 — pas de cloison réseau ni de refus par défaut | `isolement-<espace>` (M15) et la GeneratingPolicy (M26) dépendent de fichiers ou d'étiquettes que l'espace de libre-service n'a pas | CCNP `isolement-locataire-<locataire>` sur l'étiquette `capsule.clastix.io/tenant` ; condition de `networkpolicy-par-defaut` élargie |
| 3 — placement forcé | ni Capsule (pas de `nodeSelector` de locataire) ni PSA ne regardent tolérances et `nodeName` | ValidatingPolicy `locataires-placement` |
| 4 — Service `ExternalName` | les quotas ne savent pas compter les `ExternalName` ; un alias vers un nom interne (git01, OpenBao) contourne la logique « tout passe par la plateforme » | règle Capsule `deny` sur `LoadBalancer`, `NodePort` et `ExternalName`, dans tous les espaces du locataire |

## 3. Risques résiduels (hors périmètre)

- Noyau partagé : une évasion de conteneur (faille du noyau ou de runc) franchit toutes ces couches ; parades : PSA `restricted`, seccomp `RuntimeDefault`, Falco/Tetragon, mises à jour (M26). C'est la limite structurelle de Capsule face à un vCluster ou un cluster dédié.
- Déni de service par l'API (requêtes massives d'un propriétaire) : APF (*API Priority and Fairness*) par défaut, sans règle par locataire.
- Bande passante et IOPS : non bornées par locataire.
- Un propriétaire peut déclarer un `Cluster` CNPG avec la tolérance `dedie` (exception de `locataires-placement` pour l'opérateur CNPG) : à couvrir par une règle sur les `Cluster` CNPG des espaces de locataire.
- Capsule < 0.15.0 : contournement d'autorisation (GHSA-p8j8-x28r-3c9v) ; version minimale 0.15.0 inscrite dans l'ADR-0280.

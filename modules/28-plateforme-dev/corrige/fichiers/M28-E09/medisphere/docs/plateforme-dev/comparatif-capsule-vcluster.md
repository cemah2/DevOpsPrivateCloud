# Capsule ou vCluster : comparatif et décision

> Plateforme développeurs — M28-E09 (PLAT-2909). Essai `vc-essai` (vCluster OSS 0.37.4, distribution `k8s` v1.36.5, SQLite embarqué) dans `medidoc-vc-essai` (locataire `medidoc`), **retiré** à la fin de l'essai. Auteur : équipe Plateforme ; relu par Karim Benali.

## Ce que l'essai a montré

| Observation | Détail |
|---|---|
| Ce qui est synchronisé vers l'hôte | pods, Services, Endpoints/EndpointSlices, PVC, ConfigMaps et Secrets **utilisés par des pods** (`sync.toHost`), renommés `<nom>-x-<espace>-x-vc-essai` dans `medidoc-vc-essai`, avec des étiquettes `vcluster.loft.sh/…` |
| Ce qui reste virtuel | espaces, Deployments, ReplicaSets, CRD et leurs objets, ClusterRoles, RoleBindings, webhooks : ils n'existent que dans l'API du vCluster (SQLite du StatefulSet) |
| Nœuds | des nœuds **fictifs** (nom du nœud réel, sans détails) ; pas d'accès aux nœuds de l'hôte |
| Pod `privileged` créé dans le vCluster | accepté par l'API virtuelle ; refusé **à la synchronisation** par Pod Security `restricted` de `medidoc-vc-essai` : événement sur le pod virtuel (`SyncError`), journal du *syncer* ; le pod reste `Pending` dans le vCluster |
| PVC `cephfs` | accepté virtuellement ; refusé à la synchronisation par le webhook de Capsule (classe non autorisée au locataire) |
| Dépassement du budget | refus du `ResourceQuota` de l'hôte (budget du libre-service `medidoc-libre-service`) à la synchronisation |
| Image non signée | non vérifiée : Kyverno ne vise que `recette` et `prod` — même écart que pour tout espace de libre-service (M28-E15) |
| Ce que le chart crée côté hôte | StatefulSet, Services, Role et RoleBinding dans l'espace, **et une ClusterRole** (lecture des PV, création et suppression de `VolumeSnapshotContent`) : l'installation dépasse les droits d'une équipe |
| Pod Security du plan de contrôle | `root` par défaut : passé en non-root (UID 12345) par les valeurs ; aucune exception PSA nécessaire |
| Coût mesuré | ≈ 400 Mi (plan de contrôle) + ≈ 70 Mi (CoreDNS virtuel), 2 Gi de volume ; démarrage ≈ 1 min *(valeurs représentatives)* |

## Comparatif

| Critère | Capsule (locataire) | vCluster (cluster virtuel) |
|---|---|---|
| Isolation de l'API | partagée : l'équipe voit l'API de l'hôte, limitée par RBAC et webhooks | une API par équipe : elle y est administratrice |
| CRD, opérateurs, webhooks propres | impossible (objets de cluster) | possible dans le vCluster |
| Version de Kubernetes | celle de l'hôte | au choix (dans les limites du syncer) |
| Garde-fous de la plateforme | appliqués directement (Pod Security, Kyverno, quotas, classes) | appliqués **à la synchronisation** : erreurs moins lisibles, découvertes tard |
| Coût | quasi nul (un contrôleur) | un plan de contrôle par équipe (≈ 0,5 Gi + volume), à mettre à jour, sauvegarder, superviser |
| Exploitation | un composant | N clusters de plus (versions, CVE, sauvegarde de SQLite, supervision du *syncer*) |
| GitOps | Argo CD livre dans les espaces comme avant | Argo CD doit enregistrer chaque vCluster comme cluster (secret de cluster, droits) |
| Sécurité | multi-locataire souple ; nœuds et noyau partagés | idem pour les nœuds et le noyau : un vCluster **n'isole pas** les charges entre elles plus qu'un espace |
| Capsule dans le vCluster | — | impossible ici : Capsule 0.15 exige Kubernetes ≥ 1.36.0 et son modèle suppose l'API partagée ; empiler deux couches de locataires n'a pas de sens |

## Quand chacun gagne

- **Capsule** : équipes internes qui déploient des applications, sans opérateur à elles ; c'est le cas de toutes les équipes de MédiSphère aujourd'hui.
- **vCluster** : une équipe qui doit installer ses propres CRD ou opérateurs, tester une autre version de Kubernetes, ou des environnements éphémères de CI qui ont besoin d'un cluster entier (tests d'opérateur, de chart avec CRD).

## Décision

**Capsule pour tous les locataires.** Pas de vCluster permanent. Un vCluster éphémère reste possible pour un besoin ponctuel (tests de CRD), créé et détruit par la Plateforme, dans un espace de libre-service, après une demande écrite ; à reconsidérer dans l'ADR-0280 si deux équipes au moins en ont besoin régulièrement.

## Retrait (fait)

1. Fichier `plateforme/plateforme/vc-essai.yaml` supprimé de `plateforme/gitops` (MR) → l'Application de groupe l'élague ; le finaliseur supprime StatefulSet, PVC, Services, Role, ClusterRole.
2. Destination `medidoc-vc-essai` retirée de l'AppProject `plateforme`.
3. Espace `medidoc-vc-essai` supprimé par l'équipe MédiDoc (libre-service).
4. Contrôle : `kubectl get applications -n argocd vc-essai` → absente ; `kubectl get ns medidoc-vc-essai` → absent ; `kubectl get pods,pvc -A -l app=vcluster` → rien ; `kubectl get clusterrole | grep vc-vc-essai` → rien ; locataire `medidoc` revenu à 2 espaces.

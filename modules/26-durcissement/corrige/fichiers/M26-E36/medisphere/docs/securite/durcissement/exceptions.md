# Registre des exceptions de durcissement

> Source de vérité des écarts acceptés et signés. Relu à chaque revue HDS. Procédure de dérogation :
> RB-261. Toute exception a un périmètre minimal, une justification, un risque résiduel, une
> compensation, un valideur et une **date de revue**. Une exception périmée est un défaut.

## Hôtes (rôle `durcissement`, `durcissement_exceptions`)

| Règle (CIS/XCCDF ou ANSSI) | Périmètre | Justification | Risque résiduel | Compensation | Valideur | Revue |
|---|---|---|---|---|---|---|
| `net.ipv4.ip_forward=1` (interdit par CIS) | `gw01`, `gw02`, nœuds `k8s-par1` | routage / réseau de pods indispensable | transfert de paquets | pare-feu d'hôte, matrice des flux | sophie.laurent | 2027-04 |
| `/tmp` sans `noexec` | `runner01`, `runner02` | outils de CI qui exécutent dans `/tmp` | exécution depuis `/tmp` | Falco (binaire exécuté depuis `/tmp`), montage dédié | sophie.laurent | 2027-04 |

## Kubernetes (PSA, Kyverno)

| Objet | Périmètre | Justification | Risque résiduel | Compensation | Valideur | Revue |
|---|---|---|---|---|---|---|
| PSA `privileged` | `supervision-noeuds`, `falco`, `tetragon` | node-exporter / agents eBPF ont besoin de privilèges | pods privilégiés | espaces dédiés, RBAC strict, pas de charge applicative | sophie.laurent | 2027-04 |
| `PolicyException essai-outil-interne` | `wb-pannes`, outil `essai-outil-interne` | essai d'un outil interne hors registre | image non vérifiée en bac à sable | périmètre bac à sable, `expiresAt` | sophie.laurent | 2026-12 |

## Hors registre (interdits)

- Exempter un **groupe d'utilisateurs** (`system:masters`…) d'une politique : jamais (panne M26-E36 v4).
- Mettre un espace **applicatif** en PSA `privileged` : jamais.
- Désactiver un contrôle (`setenforce 0`, webhook `Ignore`, politique en `Audit` censée être en `Deny`) comme correctif : jamais.

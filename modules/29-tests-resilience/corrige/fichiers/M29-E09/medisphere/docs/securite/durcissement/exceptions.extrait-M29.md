<!-- docs/securite/durcissement/exceptions.md — lignes AJOUTÉES en M29-E09 (PLAT-3009), dans les tableaux existants. -->

### Kubernetes — Pod Security et admission (ajouts)

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-K-005 | Pod Security `restricted` | espace `chaos-mesh` (`privileged`) | `chaos-daemon` entre dans les espaces de noms des conteneurs visés (hostPID, privilégié, socket containerd) | Un pod de cet espace a les droits de l'hôte sur chaque nœud | Espace sans accès des équipes ; images du cache Harbor épinglées ; aucune expérience hors de la liste fermée (VAP `medisphere-chaos-espaces`) ; Chaos Mesh retirable par Argo CD | `plateforme/k8s/espaces/chaos-mesh.yaml` | sophie.laurent | 2027-04-30 |
| EXC-K-006 | VAP `medisphere-interdire-hostpath` | espace `chaos-mesh` : `/run/containerd`, `/sys`, `/lib/modules` | Socket du runtime (injection), `/sys` et modules (règles réseau) | Accès à containerd = contrôle de tous les conteneurs du nœud | Même compensation qu'EXC-K-005 ; Tetragon observe les exécutions du démon | `plateforme/k8s/admission/20-interdire-hostpath.yaml` (clé `chaos-mesh`) | sophie.laurent | 2027-04-30 |

### Détection (ajouts)

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-D-002 | Règles Falco par défaut déclenchées par Chaos Mesh (noms exacts relevés pendant M29-E09) | conteneurs `chaos-daemon` et `chaos-mesh` de l'espace `chaos-mesh`, image du cache Harbor | Comportement attendu de l'injecteur (entrée dans les espaces de noms, `tc`, `iptables`, appels à l'API) | Un attaquant dans ces conteneurs n'est plus vu par ces règles | Exceptions limitées à l'image ET à l'espace ; les règles MédiSphère (espaces applicatifs) restent actives ; Tetragon `observer-exec` | `plateforme/politiques/falco/regles-medisphere.yaml` (exceptions `chaos_mesh`) | sophie.laurent | 2027-01-31 |

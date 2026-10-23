<!-- docs/securite/durcissement/exceptions.md — EXTRAIT (M26-E36) : ligne à ajouter au tableau
     « Kubernetes — Pod Security et admission » du registre d'E23, si l'essai de l'outil est légitime.
     Sinon : aucune ligne, l'exception trop large de la panne est simplement retirée. -->

| ID | Règle | Périmètre | Justification | Risque résiduel | Compensation | Codée dans | Valideur | Revue |
|---|---|---|---|---|---|---|---|---|
| EXC-K-005 | Kyverno `registres-autorises` | pods `essai-outil-interne*` de `wb-pannes` (bac à sable) | Essai d'un outil interne tiré d'un registre public avant sa recopie dans Harbor (SEC-2736) | Image non analysée par Trivy, exécutée dans le cluster | Espace bac à sable sans données, refus réseau par défaut, PSA `restricted`, `expiresAt` 2027-01-15 | `plateforme/politiques`, `kyverno/exceptions/essai-outil-interne.yaml` | sophie.laurent | 2027-01-08 |

Les deux autres leviers de la panne ne s'inscrivent **jamais** au registre : exempter un groupe d'utilisateurs (`system:masters`…) d'une politique (variante 4), mettre un espace applicatif en PSA `privileged` (variante 2).

# RB-195 — Un job échoue avant son script ou est tué

| | |
|---|---|
| Portée | Runners `k8s-par1` et `k8s-par1-protege` (exécuteur Kubernetes), espaces `ci-jobs` et `ci-jobs-protege` |
| Déclencheur | Job en échec sans aucune ligne de son script (`system failure`, `prepare environment`), ou journal coupé net en cours d'exécution |
| Auteur / relecture | Équipe Plateforme (M19-E36, M19-E42) / Karim Benali |

## Avant tout

1. Lis le journal du job **depuis le haut** : la dernière étape atteinte (`Preparing environment`, `Getting source`, script…) situe l'échec.
2. Garde la preuve avant qu'elle disparaisse : les pods de job sont supprimés à la fin, les événements au bout d'une heure.
   ```
   kubectl -n ci-jobs get events --sort-by=.lastTimestamp | tail -n 30
   kubectl -n gitlab-runner get pods ; kubectl -n gitlab-runner logs deploy/<gestionnaire> --tail=50 [--previous]
   ```
3. Compare le cluster au code : `helmfile -e par1 -l composant=gitlab-runner diff`, `kubectl diff -f plateforme/k8s/espaces/ci-jobs/`.

## Avant le script

| Étape | Message typique (représentatif) | Preuve | Correctif |
|---|---|---|---|
| Gestionnaire | pods du gestionnaire en `CrashLoopBackOff`, `x509: certificate signed by unknown authority` dans `logs --previous` | `kubectl get secret <certs> -o json \| jq '.data \| map_values(length)'` | `outils/secrets-k8s.sh gitlab-runner` (Vault), puis redémarrage |
| Création du pod | `forbidden: error looking up service account ci-jobs/ci-job` | `kubectl -n ci-jobs get sa` ; audit (`verb=delete`, `resource=serviceaccounts`) | `task appliquer` (espace `ci-jobs`) |
| Création du pod | `forbidden: ValidatingAdmissionPolicy 'medisphere-images' … denied` | référence d'image du job | Image par Harbor (`registry.par1.medisphere.internal/<cache>/…`) |
| Création du pod | `forbidden: exceeded quota` | `kubectl describe resourcequota -n ci-jobs` | quota du code (voir RB-190) |
| Tirage | `image pull failed`, `ErrImagePull` sur le *helper* ou l'image du job | événements ; `helper_image` du gabarit ; projet Harbor | values Helmfile, `helmfile apply` |
| Démarrage | `CreateContainerConfigError`, `RunContainerError` | `kubectl describe pod` | selon le message (Secret ou ConfigMap monté absent, profil de sécurité) |

## Job tué

| Ce que je vois | Qui a tué | Réglage | Commande de preuve |
|---|---|---|---|
| `OOMKilled`, code 137 | noyau (cgroup du conteneur) | `memory_limit` du gabarit, `KUBERNETES_MEMORY_LIMIT` du job (borné par `memory_limit_overwrite_max_allowed`) | `kubectl get pod -o jsonpath='{..containerStatuses[*].state.terminated}'` |
| Pod `Failed`, raison `DeadlineExceeded` | kubelet (`activeDeadlineSeconds`) | délai du job + 1 s posé par le runner ; **toute autre valeur** vient d'ailleurs (politique de mutation) | `kubectl get pod -o jsonpath='{.spec.activeDeadlineSeconds}'` ; `kubectl get mutatingadmissionpolicies` |
| `Evicted`, « exceeded its local ephemeral storage limit » | kubelet (éviction) | `ephemeral_storage_limit` (conteneur), `emptyDir` `/builds` (pod) | `kubectl get events --field-selector reason=Evicted` |
| `Preempted by pod … on node …` | ordonnanceur (préemption) | PriorityClass des jobs `medisphere-ci` (basse, voulue) et du pod préempteur | `kubectl get pods -A --field-selector spec.nodeName=<nœud> -o custom-columns=…,PRIO:.spec.priority` |
| Journal coupé, pod disparu, rien dans les événements | gestionnaire redémarré pendant le job, ou nœud perdu | journaux du gestionnaire, `kubectl get nodes` | voir RB-140 (nœud) ou le redémarrage du gestionnaire |

## Après

- Correctif dans le code, MR liée au ticket ; canari (`formation/ci-pannes`) relancé jusqu'au vert.
- Journal de diagnostic dans `docs/kubernetes/journal/`.

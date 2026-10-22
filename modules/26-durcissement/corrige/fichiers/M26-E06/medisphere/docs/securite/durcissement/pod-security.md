# Pod Security : registre des espaces de `k8s-par1`

> SEC-2706 — état au <AAAA-MM-JJ>, tenu par l'équipe Plateforme, validé par Sophie Laurent (RSSI). Source de vérité des étiquettes : `plateforme/k8s/espaces/`. Inventaire à jour : `outils/psa-inventaire.sh` de `plateforme/k8s`. Toute ligne « exception » a une raison, un responsable et une date de revue ; elle est reprise au registre général `exceptions.md` (E23).

## Règle

- Tout espace porte les trois étiquettes `pod-security.kubernetes.io/enforce`, `audit` et `warn`.
- Cible : `enforce: restricted`, `enforce-version: v1.36` (figée : une montée de Kubernetes ne durcit pas la règle sans MR), `audit` et `warn` en `restricted` avec la version `latest` (on voit venir la prochaine).
- **Exception** : `enforce` en `baseline` ou `privileged`, mais `audit` et `warn` restent `restricted`, et l'espace porte l'annotation `medisphere.internal/exception-psa` (raison courte et référence). Un espace d'exception n'héberge **que** la charge qui le justifie.
- Hors registre : `kube-system`, `kube-public`, `kube-node-lease` (gérés par kubeadm et Cilium ; exclus de Kyverno et de nos politiques).
- Les espaces des équipes (`mediagenda-*`, `medidoc-*`) n'ont **jamais** d'exception.

## Registre

Lignes attendues à la fin d'E08 ; adapte à ce que `psa-inventaire.sh` trouve chez toi (un espace retiré par un module ne figure plus, un espace inconnu doit être expliqué ou supprimé).

| Espace | `enforce` | Version | Exception : raison | Responsable | Revue |
|---|---|---|---|---|---|
| `default` | restricted | v1.36 | — (rien n'y tourne) | plateforme | — |
| `mediagenda-dev`, `-recette`, `-prod` | restricted | v1.36 | — | julien.petit | — |
| `medidoc-dev`, `-recette` | restricted | v1.36 | — | équipe MédiDoc | — |
| `argocd`, `argo-rollouts` | restricted | v1.36 | — | plateforme | — |
| `cert-manager`, `external-dns`, `passerelles`, `cnpg-system` | restricted | v1.36 | — | plateforme | — |
| `gitlab-runner`, `gitlab-agent`, `ci-jobs`, `ci-jobs-protege` | restricted | v1.36 | — | plateforme | — |
| `supervision`, `traces` | restricted | v1.36 | — | plateforme | — |
| `external-secrets` (M25), `oauth2-proxy` (M24) | restricted | v1.36 | — | plateforme | — |
| `kyverno` (E07) | restricted | v1.36 | — | plateforme | — |
| `wb-system`, `wb-pannes`, `wb-restauration` | restricted | v1.36 | — | plateforme | — |
| `wb-essais` | **baseline** | v1.36 | essais des exercices : conteneurs root jetables | plateforme | fin de chaque module |
| `supervision-noeuds` | **privileged** | — | node-exporter : `hostNetwork`, `hostPID`, `hostPath` en lecture (ADR-0210) | plateforme | annuelle |
| `journaux` | **privileged** | — | Alloy en DaemonSet : `hostPath` (journaux des pods, journald, audit de l'API) | plateforme | annuelle ; étudier un espace dédié au seul DaemonSet, comme `supervision-noeuds` |
| `ceph-csi` | **privileged** | — | pilotes CSI : montages de blocs, `privileged`, `hostNetwork` | plateforme | annuelle |
| `velero` | **privileged** | — | agent de nœud : `hostPath` sur `/var/lib/kubelet/pods` | plateforme | annuelle |
| `buildkit` | **privileged** | — | BuildKit (M19) : seccomp et AppArmor `Unconfined` exigés par la construction sans privilège | plateforme | à la revue de la CI (le mode sans racine total est à étudier) |
| `wb-diagnostic` | **privileged** | — | diagnostic de nœud, kube-bench : `hostPID`, `hostNetwork`, `hostPath` | plateforme-admins | vide hors diagnostic |
| `falco` (E08) | **privileged** | — | capteur eBPF : `privileged`, montages de `/proc`, `/sys/kernel`, socket du runtime | plateforme | annuelle ; essayer `leastPrivileged` |
| `tetragon` (E20) | **privileged** | — | capteur eBPF (à venir) | plateforme | annuelle |

## Créer un espace

1. Un fichier (ou un dossier) dans `plateforme/k8s/espaces/`, copié du modèle `default.yaml` : les six étiquettes Pod Security en `restricted`, `enforce-version: v1.36`.
2. Les étiquettes de l'équipe (`medisphere.internal/equipe` pour un espace d'équipe, `medisphere.internal/proprietaire` pour la plateforme).
3. MR relue par l'équipe Plateforme ; `task appliquer`.
4. Avant de déployer une charge, `outils/psa-inventaire.sh --essai restricted --espace <nom>` après un premier essai dans `wb-essais` si nécessaire.

## Demander une exception

En attendant la procédure RB-261 (E23) : un ticket SEC à Sophie Laurent avec la charge, la règle de Pod Security qu'elle viole, pourquoi elle ne peut pas s'en passer, ce qui compense (espace dédié, RBAC fermé, Falco), une date de revue. Sans accord écrit, pas d'exception ; jamais d'exception pour un espace d'équipe.

## Retour arrière

Remettre l'ancienne valeur dans le fichier de l'espace et `task appliquer`. En urgence, `kubectl label namespace <espace> pod-security.kubernetes.io/enforce=<ancien niveau> --overwrite` avec un compte d'administration, puis la MR qui l'écrit (sinon le prochain `task appliquer` réimpose la règle).

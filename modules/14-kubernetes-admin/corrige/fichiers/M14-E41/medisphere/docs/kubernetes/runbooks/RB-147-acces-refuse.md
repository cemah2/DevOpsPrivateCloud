# RB-147 — Accès refusé à l'API Kubernetes

| | |
|---|---|
| Cluster | `k8s-par1` |
| Identités | humains : certificats clients (groupes `medisphere:*`, 7 jours, `outils/kubeconfig-personnel.sh`) ; charges de travail : comptes de service et jetons liés ; bris de glace : `admin.conf`, `super-admin.conf` (Vault `critique`) |
| Rédigé | M14-E41 (INC-4141) |

## 1. Quelle porte ?

| Message | Porte | Première commande |
|---|---|---|
| `You must be logged in to the server (Unauthorized)`, `401` | authentification | `kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' \| base64 -d \| openssl x509 -noout -subject -issuer -dates` |
| `… is forbidden: User "X" cannot <verbe> resource "<ressource>" … in the namespace "<espace>"` | autorisation (RBAC) | `kubectl auth can-i --list -n <espace> --as X --as-group <groupe>` |
| `ValidatingAdmissionPolicy '<p>' with binding '<b>' denied request: …` | admission (politique CEL) | `kubectl get validatingadmissionpolicy <p> -o yaml` |
| `violates PodSecurity "restricted:latest": …` | admission (Pod Security) | `kubectl get ns <espace> --show-labels` |
| `admission webhook "<w>" denied the request` | admission (*webhook*) | `kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations` |
| application : `403` sur l'API avec son jeton | RBAC d'un compte de service | `kubectl auth can-i <verbe> <ressource> -n <espace> --as system:serviceaccount:<espace>:<compte>` |

## 2. Remonter la chaîne

- **Authentification** : émetteur (`openssl verify -CAfile` avec la CA du cluster), sujet (`CN` = utilisateur, `O` = groupes), dates. Un certificat client ne se révoque pas : il expire.
- **Autorisation** : `kubectl get rolebindings,clusterrolebindings -A -o wide | grep <sujet>` ; comparer **caractère par caractère** les sujets (groupe, utilisateur, compte de service **et** son espace). RBAC ne signale jamais un sujet inexistant.
- **Admission** : expression de la politique, liaison (`validationActions`, `matchResources`) ; essai avec `kubectl apply --dry-run=server` d'un objet qui doit passer et d'un objet qui doit être refusé.
- **Qui a changé quoi** : journal d'audit sur **les trois** nœuds de contrôle (`/var/log/kubernetes/audit/`), par exemple `sudo jq -c 'select(.objectRef.resource=="rolebindings" and (.verb=="patch" or .verb=="update" or .verb=="delete"))' audit.log`.

## 3. Corriger sans élargir

- Ton certificat a expiré : `outils/kubeconfig-personnel.sh` ; s'il dépend de ton identité courante, `kubeadm kubeconfig user --client-name <MOI> --org medisphere:plateforme-admins --validity-period 168h` sur un nœud de contrôle (SSH + sudo).
- Liaisons et politiques : réappliquer le code (`plateforme/k8s/rbac/`, `plateforme/k8s/admission/`, `task appliquer`), jamais un `cluster-admin` « en attendant ».
- Politique de sécurité fautive : la corriger, la tester en `Warn`, la repasser en `Deny`, la faire relire par la RSSI ; ne pas la supprimer.

## 4. Bris de glace

1. Condition : aucune identité nominative ne fonctionne et l'incident l'exige ; l'astreinte prévient Claire Morel ou Karim Benali.
2. `admin.conf` : `(umask 077; ansible-vault view --vault-id critique@prompt secrets/<FICHIER-ADMIN-CONF> > /dev/shm/admin.conf)` (`<FICHIER-ADMIN-CONF>` : le fichier chiffré de `secrets/` dans `plateforme/k8s`, M14-E04), puis `--kubeconfig /dev/shm/admin.conf`.
3. `super-admin.conf` (`system:masters`, ignore RBAC) : seulement si RBAC lui-même est cassé.
4. Après usage : `shred -u /dev/shm/admin.conf` ; ligne dans le journal d'incident (heure, commandes, raison) ; mention dans le post-mortem.

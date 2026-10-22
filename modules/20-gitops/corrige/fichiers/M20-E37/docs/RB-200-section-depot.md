## Argo CD ne lit plus le dépôt (ComparisonError, statut Unknown)

> Section ajoutée à RB-200 après INC-4737 (M20-E37). Tant qu'Argo CD ne lit pas Git, rien ne
> casse dans le cluster… et rien n'y arrive : ni les correctifs, ni les retours arrière. Priorité
> haute, même un vendredi soir.

1. **Message exact** : `argocd app get <app> -o json | jq -r '.status.conditions[].message'`.
   Le message dit presque toujours l'étage :
   | Extrait du message | Étage | Où regarder |
   |---|---|---|
   | `authentication required`, `HTTP Basic: Access denied`, `403` | identifiants | Secrets `repo-creds`/`repository` de l'espace argocd (qui les a modifiés ? `metadata.managedFields`, annotations), jeton de déploiement dans GitLab (révoqué, expiré ?) |
   | `x509: certificate signed by unknown authority` | confiance TLS | `argocd-tls-certs-cm` (entrée par **nom d'hôte**), release Helmfile `argocd` (`configs.tls.certificates`) |
   | `no such host`, `not permitted in project`, `repository not found` | adresse du dépôt | `spec.source.repoURL` de l'Application (et le dépôt d'où elle vient : `git log -p` dans plateforme/gitops), `sourceRepos` de l'AppProject |
   | `i/o timeout`, `context deadline exceeded`, `connection refused` | réseau | politiques de l'espace argocd (`kubectl get cnp,netpol -n argocd`), Hubble (`hubble observe --namespace argocd --verdict DROPPED`), pare-feu de la bordure |
2. **Reproduire depuis le repo-server**, pas depuis adm01 (qui a d'autres identifiants, une autre
   CA et un autre chemin réseau) :
   `kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote https://git01.par1.medisphere.internal/<groupe>/<projet>.git`
   (sans identifiants : une erreur d'authentification prouve que TLS et réseau passent).
3. **Corriger à la source** : identifiants → `plateforme/k8s/outils/secrets-k8s.sh argocd` depuis
   le Vault (jamais une valeur collée à la main) ; CA → `helmfile -e par1 -l composant=argocd apply`
   après un `diff` qui montre exactement l'écart ; adresse → revert par MR dans plateforme/gitops ;
   réseau → retirer la politique fautive par le code qui la porte (plateforme/k8s), matrice des flux.
4. **Accélérer la reprise** : `argocd app get <app> --hard-refresh` (le cache des révisions
   résolues dure jusqu'à 3 min par défaut), ou attendre le prochain webhook.
5. **Vérifier** : plus aucune Application en `ComparisonError` (`argocd app list | grep -v Synced`).

Ne jamais : passer un dépôt en `insecure` (TLS non vérifié) ; remplacer un jeton de déploiement
par un jeton personnel ; ouvrir une politique réseau « pour tester » sans la refermer.

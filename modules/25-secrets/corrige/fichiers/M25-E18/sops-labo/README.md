# formation/sops-labo

Dépôt d'**essai** du M25-E18 : des Secrets Kubernetes chiffrés dans Git par **SOPS 3.13.3**, avec
la clé de transit `sops-plateforme` d'OpenBao et une clé `age` de secours. Il ne sert à aucun
déploiement : chez MédiSphère, les Secrets des clusters viennent d'OpenBao par External Secrets
Operator (décision : `docs/securite/secrets/comparatif-livraison-k8s.md`).

## Prérequis sur adm01

- `sops` 3.13.3 et `age` 1.3.2 (rôle `outils_k8s`) ;
- un jeton OpenBao avec la politique `sops-plateforme` : `bao login -method=oidc` (SOPS lit
  `~/.vault-token` ou `VAULT_TOKEN`, **pas** `BAO_TOKEN`) ;
- `export SOPS_HC_VAULT_ALLOWLIST=https://openbao.par1.medisphere.internal:8200` (dans `~/.bashrc`) :
  SOPS ne parlera à aucun autre serveur, même si un fichier piégé en nomme un autre ;
- `git config --global diff.sopsdiffer.textconv "sops decrypt"` (voir `.gitattributes`).

## Gestes

| Geste | Commande |
|---|---|
| Créer ou modifier un Secret chiffré | `sops edit k8s/wb-essais/<nom>.sops.yaml` (le clair n'existe que dans un fichier temporaire) |
| Chiffrer un fichier écrit à part | `sops encrypt -i k8s/wb-essais/<nom>.sops.yaml` |
| Lire | `sops decrypt k8s/wb-essais/<nom>.sops.yaml` |
| Appliquer (essai, `wb-essais` seulement) | `sops decrypt … \| kubectl apply -n wb-essais -f -` |
| Changer les destinataires après modification de `.sops.yaml` | `sops updatekeys k8s/wb-essais/<nom>.sops.yaml` |
| Changer la clé de données (après un départ) | `sops rotate -i k8s/wb-essais/<nom>.sops.yaml` |
| Vérifier qu'il n'y a rien en clair | `outils/verifier-chiffres.sh k8s` (aussi en CI) |

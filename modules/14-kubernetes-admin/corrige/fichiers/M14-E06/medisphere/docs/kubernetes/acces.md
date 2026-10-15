# Accéder à k8s-par1 — identités et droits

> `docs/kubernetes/acces.md` (plateforme/medisphere), M14-E06 (PLAT-1506, SEC-1506). Complété par M14-E11/E12
> (rôles des équipes, certificats des développeurs) et M24 (OIDC).

## Les identités

| Identité | Comment | Droits | Durée | Où |
|---|---|---|---|---|
| Personnelle (`<MOI>`, membres de l'équipe Plateforme) | certificat client CN=`<nom>`, O=`medisphere:plateforme-admins`, émis par `outils/kubeconfig-personnel.sh` (`kubeadm kubeconfig user` sur `k8s-cp01`) | `cluster-admin` par la liaison `medisphere:plateforme-admins` (`rbac/plateforme-admins.yaml`) | **7 jours**, à renouveler | `~/.kube/config` (600), contexte `k8s-par1` |
| Vérifications du workbook | compte de service `wb-system/wb-checks`, jeton du Secret `wb-checks-jeton` | ClusterRole agrégée `wb-checks` : lecture de tout **sauf les Secrets**, GET par `services/proxy`, `SubjectAccessReview` | sans expiration (**exception**, voir ci-dessous) | `~/.config/workbook/k8s-checks.kubeconfig` (600) |
| Bris de glace | `admin.conf` (groupe `kubeadm:cluster-admins`) | `cluster-admin` | 1 an (certificat kubeadm) | `plateforme/k8s` `secrets/admin.conf.vault` (Vault `critique`) et `/etc/kubernetes/admin.conf` des nœuds de contrôle |
| Bris de glace ultime | `super-admin.conf` (groupe `system:masters`) | tout, **sans autorisation** | 1 an | `secrets/super-admin.conf.vault` seulement (retiré de `k8s-cp01`) |

## Règles

- On travaille avec son identité personnelle. Un certificat ne se révoque pas : on limite sa durée (7 jours) et on
  retire les droits du **groupe** si besoin (supprimer la liaison).
- `admin.conf` ne sort d'un nœud de contrôle que chiffré. Son usage depuis `adm01` passe par le dossier de session en
  mémoire (`$XDG_RUNTIME_DIR`), puis effacement ; chaque usage est noté au journal (`docs/socle/journal/`).
- `super-admin.conf` n'est utilisé que si le RBAC lui-même est cassé. `system:masters` contourne toute autorisation
  et ne se retire qu'en changeant la CA du cluster.
- Tout ce qui est appliqué au cluster vient de `plateforme/k8s` (`task appliquer`, gestionnaire de champs
  `plateforme-k8s`).

## Exception : le jeton durable de wb-checks

Inscrite au registre des secrets (`docs/socle/registre-secrets.md`). Les vérifications tournent sur des mois, à
intervalles irréguliers : un jeton lié (`kubectl create token --duration`) expirerait entre deux exercices.
Compensations : lecture seule sans Secrets, aucun pod ne monte ce jeton (`automountServiceAccountToken: false`),
fichier 600 sur `adm01` seulement. **Révocation** : `kubectl -n wb-system delete secret wb-checks-jeton` (refus
immédiat), `task appliquer` (nouveau jeton), `outils/kubeconfig-checks.sh`.
Contrôle : `outils/kubeconfig-checks.sh --verifier`.

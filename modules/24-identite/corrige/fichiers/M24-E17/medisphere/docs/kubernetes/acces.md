# Accès humains et automatisés à `k8s-par1`

*Version M24-E17 (SEC-2517) — remplace la version du M14. Responsable : équipe Plateforme. Relu par : Sophie Laurent.*

## Qui entre, comment

| Qui | Identité vue par l'API | Comment | Durée |
|---|---|---|---|
| Personnes (toutes équipes) | `oidc:<identifiant de l'annuaire>`, groupes `oidc:<groupe>` | kubelogin (`kubectl oidc-login`), client Keycloak `kubernetes`, contexte `k8s-par1-oidc` (et `k8s-par1`, même utilisateur) ; OTP pour `plateforme-admins` et `securite` (M24-E21) | jeton d'accès 5 min, renouvelé par le jeton de rafraîchissement tant que la session SSO vit (10 h au plus) |
| Vérifications du workbook | `system:serviceaccount:wb-system:wb-checks` | jeton long (Secret), `~/.config/workbook/k8s-checks.kubeconfig` | sans expiration (exception documentée, M14-E06) |
| Supervision externe | comptes de service `ms-supervision*` (M15, M16) | jetons longs dédiés | idem |
| Bris de glace | `kubernetes-admin`, groupe `kubeadm:cluster-admins` | `admin.conf` (Ansible Vault `critique`), RB-240 | certificat d'un an (renouvelé par kubeadm) |

Les certificats clients personnels de sept jours (M14-E06, `outils/kubeconfig-personnel.sh`) et les certificats des référents d'équipe (`outils/kubeconfig-csr.sh`) sont **retirés** : scripts supprimés, liaisons aux groupes `medisphere:*` supprimées. Un certificat encore valide authentifie toujours (un certificat ne se révoque pas), mais ne donne plus aucun droit.

## Droits

Les droits découlent **uniquement** des groupes de l'annuaire (`docs/securite/identite/modele-autorisation.md`), par `plateforme/k8s/rbac/oidc.yaml` :

| Groupe | Droits |
|---|---|
| `oidc:plateforme-admins` | `cluster-admin` |
| `oidc:plateforme` | `medisphere-plateforme` (tout lire sauf les Secrets, objets des composants compris) ; `edit` dans `wb-essais` |
| `oidc:mediagenda` | `edit` dans `mediagenda-dev` ; `view` dans `mediagenda-dev`, `mediagenda-recette` et `mediagenda-prod` |
| `oidc:medidoc` | `view` dans `medidoc-dev` et `medidoc-recette` |
| `oidc:support` | `medisphere-lecture` (tout lire sauf Secrets et composants) |
| `oidc:securite` | `medisphere-securite` (tout lire sauf les Secrets, plus le RBAC et les politiques d'admission) |
| `oidc:direction` | rien |

Règles : aucune liaison nominative ; aucune liaison sans le préfixe `oidc:` ; toutes les liaisons des personnes s'appellent `oidc-*` (`kubectl get clusterrolebindings,rolebindings -A | grep oidc-`). Contrôle : `outils/matrice-droits-oidc.sh` (sans écart), relancé à chaque MR de `rbac/`.

## Poste d'administration (`adm01`)

- `~/.kube/config` : utilisateur `oidc` (kubelogin), contextes `k8s-par1-oidc` (courant) et `k8s-par1` (même utilisateur : les outils de `plateforme/k8s` visent ce nom).
- Jetons en cache dans `~/.kube/cache/oidc-login/` (600) ; `kubectl oidc-login clean` les efface (déconnexion locale).
- Ne jamais copier un jeton dans un ticket ou une conversation : il vaut une session complète pendant sa durée de vie.

## Bris de glace

`admin.conf` du Vault, dans un fichier temporaire en 600 hors de tout dépôt, supprimé après usage ; chaque usage est consigné (RB-240) et visible dans le journal d'audit de l'API (utilisateur `kubernetes-admin`, locataire Loki `audit`).

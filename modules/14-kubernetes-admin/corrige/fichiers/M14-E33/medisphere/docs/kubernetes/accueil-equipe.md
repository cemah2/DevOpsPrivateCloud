# Accueillir une équipe sur `k8s-par1`

> Procédure générique (M14-E33, DEV-1533). Durée visée : une demi-heure de travail, une MR, une revue.

## 1. Le ticket

Le ticket d'accueil (`DEV-`) précise : nom court de l'équipe, environnement(s), enveloppe accordée (CPU et mémoire demandés et en limites, nombre de pods), référent(s) humain(s) au format `prenom.nom`, image(s) (projet Harbor), besoins particuliers. L'enveloppe est **accordée par écrit** par la responsable infrastructure.

## 2. La MR sur `plateforme/k8s`

1. `outils/nouvelle-equipe.sh <EQUIPE> <ENV>` → `espaces/<EQUIPE>-<ENV>/` (espace étiqueté, enveloppe, valeurs par défaut, compte `default`) et `rbac/40-<EQUIPE>-<ENV>.yaml` (liaisons du groupe `medisphere:<EQUIPE>-devs` aux ClusterRoles réutilisables de M14-E11 : `medisphere-developpeur`, et `medisphere-secrets-edition` en développement seulement).
2. Ajuster l'enveloppe et le responsable ; relire les étiquettes (Pod Security `restricted` ; `medisphere.internal/equipe`, qui fait appliquer la politique d'images de M14-E18).
3. Pipeline vert, revue, fusion, `task appliquer`.

## 3. Après l'application

- Secret de tirage `harbor-pull` dans l'espace : `outils/secret-tirage.sh <EQUIPE>-<ENV>` (M14-E19).
- Essais consignés dans la fiche de l'équipe : `kubectl auth can-i` (avec `--as <REFERENT> --as-group medisphere:<EQUIPE>-devs`) — **oui** pour créer un Deployment, lire ses Secrets ; **non** pour modifier le ResourceQuota, créer un RoleBinding, modifier l'espace, lire un autre espace, lister les nœuds ; un pod privilégié refusé par Pod Security ; une image `latest` ou hors de `registry.par1.medisphere.internal` refusée par la politique d'admission ; un pod de test de l'application qui démarre.
- Identité du référent : CSR (procédure de M14-E12, certificat court), kubeconfig remis par un canal chiffré, renouvellement par `outils/kubeconfig-personnel.sh`.

## 4. Documentation

- Fiche `docs/kubernetes/equipes/<EQUIPE>.md` : contacts, espaces, enveloppe et ticket qui l'accorde, rôles, essais, date de revue.
- Registre des secrets : Secret de tirage de l'espace (emplacement, pas la valeur).

## 5. Retrait d'une équipe

MR qui supprime les dossiers, `kubectl delete namespace`, liaisons RBAC supprimées, certificats laissés expirer (ils ne se révoquent pas, M14-E12) : les liaisons supprimées suffisent à retirer les droits.

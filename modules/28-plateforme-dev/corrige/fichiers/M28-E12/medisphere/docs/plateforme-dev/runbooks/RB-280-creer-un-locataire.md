# RB-280 — Créer un locataire pour une équipe

| | |
|---|---|
| Déclencheur | ticket `DEV-` d'arrivée d'une équipe, signé par son responsable et par Claire Morel |
| Exécutant | équipe Plateforme (membre de `plateforme-admins`) |
| Durée | ≈ 1 h 30 de travail, 1 jour ouvré avec les relectures |
| Prérequis | nom court de l'équipe `<equipe>` (minuscules, sans tiret de fin, pas déjà un préfixe d'espace existant), liste des personnes, responsable, budget convenu (CPU, mémoire, nombre d'espaces) |
| Références | `locataires.md`, `guide-accueil-equipe.md`, M24 (annuaire, Keycloak), M25 (coffre), M28-E05 (Capsule) |

Variables utilisées ci-dessous : `EQUIPE=<equipe>`.

## 1. Annuaire et SSO

1. MR `plateforme/identite` : groupe `<equipe>` dans `annuaire/groupes.yml`, personnes dans `annuaire/personnes.yml` (comptes avec OTP), passage de la CI, fusion, pipeline protégé d'application.
   **Vérifier** : `ipa group-show $EQUIPE` liste les membres ; une personne se connecte au portail (son entité `User` existe, groupe `$EQUIPE` dans le catalogue, ≤ 30 min).
2. Aucun changement Keycloak : la revendication `groups` porte déjà les groupes de l'annuaire. **Vérifier** : `kubectl auth whoami` d'un membre montre `oidc:$EQUIPE`.

## 2. Capsule

3. MR `plateforme/gitops` : ajouter `oidc:$EQUIPE` à `manager.options.users` (`valeurs/capsule/values.yaml`).
   **Vérifier** : `kubectl get capsuleconfiguration default -o jsonpath='{.spec.users}'` contient le groupe.
4. MR `plateforme/k8s` : `locataires/$EQUIPE.yaml` (copie de `medidoc.yaml` : propriétaire `oidc:$EQUIPE` en `view`, règles de libre-service, budget, `preventDeletion`, annotation `Prune=false,Delete=false`), ajout à `locataires/kustomization.yaml`.
   **Vérifier** : `kubectl get tenant $EQUIPE` → `Active` ; `kubectl delete tenant $EQUIPE --dry-run=server` → **refusé** (protection).

## 3. Environnements

5. MR `plateforme/k8s` : `espaces/$EQUIPE-dev/` (Namespace avec `capsule.clastix.io/tenant: $EQUIPE`, `medisphere.internal/environnement: dev`, Pod Security `restricted` ; ResourceQuota, LimitRange ; SecretStore `openbao`), puis `task espaces`, ajout de l'espace à `outils/rattacher-locataires.sh` et exécution.
   **Vérifier** : `kubectl get tenant $EQUIPE -o jsonpath='{.status.namespaces}'` contient `$EQUIPE-dev` ; `kubectl -n $EQUIPE-dev get limitrange limites-locataire` (plancher répliqué par la `GlobalTenantResource` `limites-par-defaut`, qui sélectionne le `Tenant` par son étiquette `app.kubernetes.io/part-of: plateforme-k8s`, reprise de `medidoc.yaml`) ; `kubectl auth can-i create deployments -n $EQUIPE-dev --as=oidc:<membre> --as-group=oidc:$EQUIPE` → `no` (livraison par Argo CD).

## 4. Livraison et coffre

6. GitLab : groupe `$EQUIPE`, membres (Developer, responsable Maintainer), `svc-portail` Developer (modèles), réglage « rôle pour créer un projet » = Developer, protection de branche par défaut avec premier envoi autorisé aux développeurs.
7. MR `plateforme/gitops` : AppProject `$EQUIPE` (dépôts `$EQUIPE/*`, destinations `$EQUIPE-*`, `ResourceQuota` et `LimitRange` interdits, ressources orphelines surveillées avec les objets de Capsule ignorés), identifiants de dépôt `repo-creds-$EQUIPE` (jeton de déploiement en lecture).
   **Vérifier** : `argocd proj get $EQUIPE`.
8. MR `plateforme/secrets` : chemin `kv/$EQUIPE/*`, politiques de l'équipe (OIDC) et de ses rôles ESO (`eso-$EQUIPE-dev`).
   **Vérifier** : `bao kv list kv/$EQUIPE` par un membre (après connexion OIDC).

## 5. Portail et supervision

9. MR `plateforme/portail` : fournisseur de découverte GitLab pour le groupe `$EQUIPE` (`catalog.providers.gitlab`) ; MR `plateforme/portail-modeles` : le locataire `$EQUIPE` dans les choix du modèle `nouveau-service`.
   **Vérifier** : le modèle propose l'équipe ; un essai crée un projet dans le groupe (puis supprime-le).
10. MR `plateforme/observabilite` : locataire Loki `$EQUIPE`, dossier et équipe Grafana (OpenTofu).
11. Envoie le guide d'accueil à l'équipe ; ferme le ticket avec les liens.

## Retour arrière

Dans l'ordre inverse, **jamais** en supprimant d'abord le `Tenant` (il emporterait les espaces rattachés) :
1. retirer les espaces du locataire (`kubectl patch namespace … '{"metadata":{"labels":{"capsule.clastix.io/tenant":null},"ownerReferences":[]}}'`), puis les supprimer s'ils doivent disparaître ;
2. retirer `preventDeletion` et l'annotation, puis le fichier du `Tenant` (MR) et le supprimer explicitement ;
3. retirer le groupe de `manager.options.users`, l'AppProject, les politiques du coffre, le groupe de l'annuaire en dernier.

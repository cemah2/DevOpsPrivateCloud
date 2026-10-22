# outils/revue-acces — revue mensuelle des accès (M24-E30, SEC-2530)

Produit, chaque mois, « qui a accès à quoi » à partir des **faits** (annuaire, Keycloak, chaque service), le compare au modèle d'autorisation de M24-E10 (`modele.yml`) et en tire les **écarts**. Le rapport (Markdown pour la RSSI, JSON pour comparer deux mois) est envoyé à `securite@medisphere.internal`, gardé comme artefact, et proposé par MR sur `plateforme/medisphere` (`docs/securite/identite/revue-acces/AAAA-MM.md`). Sophie Laurent **signe** en approuvant la MR.

## Exécution

- **Pipeline planifié** de `plateforme/identite` (`main`, runner protégé `runner01`), le 1er de chaque mois à 06:17, job `revue-acces` : comparaison avec le JSON du mois précédent (lu sur `main` de `plateforme/medisphere`), envoi, MR.
- **À la main** (essai, enquête) : *Run pipeline* sur `main` avec `REVUE_ESSAI=1` (pas d'envoi, pas de MR ; rapport en artefact seulement).
- Localement, pour mettre au point : `uv run revue_acces.py --sortie /tmp/revue` après avoir chargé les variables (jamais depuis un fichier versionné).

## Identités (une par source, lecture seule, variables protégées et masquées de l'environnement `lab/revue-acces`)

| Source | Identité | Droits | Variable(s) |
|---|---|---|---|
| Annuaire | `uid=revue-acces,cn=sysaccounts,cn=etc,…` (`annuaire/comptes-systeme.yml`) | lecture des personnes et des groupes (ACI par défaut des comptes système) | `REVUE_LDAP_DN`, `REVUE_LDAP_MOT_DE_PASSE` |
| Keycloak (`medisphere`) | client `revue-acces` (`tofu/comptes-service.tf`), compte de service | `view-users` de `realm-management` | `REVUE_KEYCLOAK_CLIENT_SECRET` |
| GitLab | `svc-revue-acces`, administrateur, **jeton `read_api` à expiration** (seul un administrateur voit `is_admin` et les jetons des autres en CE) | lecture | `REVUE_GITLAB_TOKEN` |
| GitLab (`plateforme/medisphere`) | jeton de **projet** `revue-acces` (rôle Developer, `api`) | créer une branche, un commit, une MR ; pas de fusion (branche protégée) | `REVUE_GITLAB_TOKEN_DOC` |
| Grafana | compte de service `revue-acces`, rôle `Admin` de l'organisation principale (lecture des membres et de `authLabels`) | ⚠️ un administrateur d'organisation peut **modifier** : jeton à expiration, revu chaque trimestre | `REVUE_GRAFANA_TOKEN` |
| Kubernetes | compte de service `revue-acces` (espace `wb-outils`), ClusterRole `revue-acces` : `get, list` sur `clusterrolebindings`, `rolebindings`, et `get` sur les ConfigMaps `argocd-cm`, `argocd-rbac-cm` (Role dans `argocd`) ; jeton lié de 24 h demandé par la CI | lecture | `REVUE_K8S_TOKEN`, `REVUE_K8S_CA` |
| Proxmox VE | `wb-revue@pve!revue`, rôle `PVEAuditor` sur `/` | lecture | `REVUE_PVE_TOKEN` |
| Courriel | aucune (Mailpit, `smtp.par1…:25`, STARTTLS) | — | — |

## Écarts signalés

`acces-personne-desactivee` (une personne désactivée dans l'annuaire garde un compte actif quelque part), `compte-local-inconnu` (compte hors SSO absent de `modele.yml`), `droit-hors-modele` (droit effectif ≠ modèle), `administrateur-hors-modele`, `jeton-sans-expiration`, `liaison-hors-oidc` (liaison RBAC vers un utilisateur ou un groupe qui ne vient pas de l'annuaire), `groupe-inconnu`. Un écart accepté se déclare dans `ecarts-acceptes.yml` (qui, pourquoi, jusqu'à quand) par une MR approuvée par Sophie ; expiré, il redevient un écart.

## Ce que l'outil ne voit pas (et pourquoi)

- Les **administrateurs du royaume `master`** de Keycloak : l'outil n'a et ne doit avoir aucun droit sur `master` ; contrôle par RB-240 (essai trimestriel) et `lab/bin/check 24 04` (lecture SQL sur `idp01`).
- **Harbor, NetBox, PBS** : pas encore de source (piste : robot Harbor en lecture, jeton NetBox en lecture, `PVEAuditor` sur PBS) ; **règles HBAC et sudo** de l'annuaire ; **comptes locaux des VMs**.
- L'organisation **« Sécurité »** de Grafana (un second compte de service serait nécessaire).
- Les **sessions** ouvertes et les **jetons OIDC** déjà délivrés (de courte durée) ; les **certificats SSH** déjà émis (16 h).
- Les droits **dans les applications** (MédiAgenda, MédiDoc) : hors de la plateforme.

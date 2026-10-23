# Offre de service de la plateforme MédiSphère

> Version 1.0 du `<AAAA-MM-JJ>` (F2-S01, PLAT-3201). Propriétaire : équipe Plateforme (Claire Morel). Relue par Sophie Laurent (sécurité) et Nadia Roussel (support). Révisée chaque trimestre et à chaque changement du chemin balisé. Pour qui : toute équipe qui livre ou exploite un logiciel sur l'infrastructure de MédiSphère (équipes produit, équipe Data, prestataires).

## 1. En une phrase

La Plateforme te fournit **un endroit sûr et outillé pour livrer, faire tourner et observer ton service**, en libre-service, par Git ; tu restes **responsable de ton service** (son code, sa configuration, ses données applicatives, ses alertes, sa disponibilité).

## 2. Ce que la plateforme fournit

| Domaine | Ce que tu reçois | Comment |
|---|---|---|
| Identité | comptes dans l'annuaire, SSO sur tous les outils, groupe d'équipe ; OTP (obligatoire pour les prestataires) | fichier de ton équipe dans `plateforme/equipes` (RB-320) |
| Code | un groupe GitLab, des composants CI standard (construction, analyse, signature, promotion), runners partagés | catalogue CI de `plateforme/ci-templates` |
| Images | registre Harbor (`medisphere/…`), analyse de vulnérabilités, signature Cosign par la clé MédiSphère | composants `construction-image`, `securite` |
| Exécution | un **locataire** Kubernetes (Capsule) : un espace par environnement (`<equipe>-dev`, `-recette`, `-prod`), quotas, espaces de libre-service, classes de priorité, stockage `ceph-rbd` | rendu de `plateforme/equipes` |
| Déploiement | Argo CD : projet de ton équipe, une Application par service et par environnement, sans ticket | dépôt `<equipe>/gitops` (ApplicationSet) |
| Exposition | publication HTTPS sur `*.apps.par1.medisphere.internal` par la Gateway `gw-par1` (certificat, en-têtes de sécurité) | `HTTPRoute` dans ton dépôt de déploiement |
| Secrets | coffre OpenBao : `kv/<equipe>/<env>/…` en libre-service (SSO), livrés dans Kubernetes par External Secrets | `ExternalSecret` dans ton dépôt |
| Observabilité | métriques (Prometheus, 15 j en local, 2 ans agrégés), journaux (Loki, 30 j), traces (Tempo), dossier Grafana de ton équipe, SLO (Pyrra), alertes routées vers l'adresse de ton équipe | objets dans ton dépôt ; tableaux par MR sur `plateforme/observabilite` |
| Portail | catalogue (Backstage), documentation (TechDocs), modèles « Nouveau service » | <https://portail.apps.par1.medisphere.internal> |
| Sauvegarde | volumes et objets du cluster (Velero), bases CloudNativePG vers `s3-01`, VMs (PBS) | automatique pour les environnements ; **pas** pour le libre-service |
| Sécurité | Pod Security `restricted`, signatures exigées en recette et en production, cloison réseau entre locataires, Falco, revues d'accès trimestrielles | imposé par la plateforme |

## 3. Ce que la plateforme ne fournit pas (aujourd'hui)

- **Pas de cluster dédié** ni de droits d'administration du cluster (CRD, webhooks, objets de cluster) : multi-locataire souple (`docs/plateforme-dev/comparatif-capsule-vcluster.md`, F2-S03).
- **Pas de base, de file ni de compartiment en libre-service** pour une équipe produit : sur demande (ticket `DEV-`), sauf l'équipe Data (bases CNPG dans son locataire, F2-S07).
- **Pas d'accès aux données de production** pour qui n'exploite pas le service (Data, prestataires) : des extractions pseudonymisées, oui (F2-S07, F2-S09).
- **Pas d'accès SSH aux machines**, pas de `kubectl exec` ni de modification à la main dans `dev`, `recette`, `prod`.
- **Pas d'astreinte applicative** : la Plateforme est d'astreinte pour la plateforme ; ton service a besoin de ton propre contact (voir § 5).
- **Pas de sortie vers Internet** depuis les pods sans demande (flux ouverts par MR, matrice des flux).
- Pas de GPU, pas de Windows, pas d'images hors Harbor.

## 4. Responsabilités partagées

| Sujet | Plateforme | Équipe |
|---|---|---|
| Cluster, nœuds, réseau, stockage, sauvegarde des volumes | ✅ conçoit, exploite, met à jour | — |
| Composants partagés (Argo CD, Harbor, OpenBao, Grafana…) | ✅ | — |
| Locataire, quotas, politiques | ✅ pose le cadre | demande les changements (MR sur son fichier d'équipe) |
| Code, dépendances, image de base de **ton** service | — | ✅ (Renovate propose, tu fusionnes) |
| Vulnérabilités de ton image | alerte (Trivy, Harbor) | ✅ corrige sous les délais de la politique de sécurité |
| Manifestes, `requests`/`limits`, sondes, HPA | modèle et revue sur demande | ✅ |
| Secrets applicatifs (valeurs, rotation) | coffre et accès | ✅ |
| Données applicatives (schéma, migrations, purge RGPD) | sauvegarde et restauration de l'infrastructure | ✅ |
| SLO, alertes, runbook de ton service | outils, modèles, revue | ✅ |
| Incident sur ton service | appui de l'astreinte plateforme si la cause est la plateforme | ✅ diagnostique et répare |
| Incident plateforme | ✅ (astreinte, messages d'état) | prévient, patiente, relit le post-mortem |
| Accès des personnes | ✅ applique | ✅ responsable de l'équipe : déclare arrivées et départs le jour même |

## 5. Niveaux de service de la plateforme

Mesurés par la Plateforme (Prometheus, sondes de `mon01`), publiés chaque mois dans le portail. Fenêtre de 28 jours.

| Service | Objectif | Indicateur |
|---|---|---|
| API Kubernetes | 99,5 % | réponses non-5xx de `k8s-api.par1.medisphere.internal` |
| Publication HTTPS (Gateway `gw-par1`) | 99,5 % | réponses non-5xx imputables à la Gateway |
| Livraison (Argo CD, Harbor, CI) | 99 % aux heures ouvrées | synchronisation possible ; *pull* d'image possible ; jobs pris en charge en moins de 5 min |
| SSO (Keycloak) | 99,5 % | page de connexion et jetons |
| Coffre (OpenBao) | 99,5 % | lecture d'un secret de test |
| Délai d'accueil d'une équipe | ≤ 1 jour ouvré | ticket `DEV-` d'arrivée → MR fusionnée et appliquée |
| Délai du premier déploiement | ≤ 1 jour ouvré | création par le modèle → service prêt en `dev` (mesuré en F2-S04) |

Maintenance planifiée : annoncée 5 jours ouvrés avant (courriel à toutes les équipes, bandeau du portail), hors du gel de fin d'année, jamais le vendredi après 16 h. Une maintenance annoncée ne compte pas dans l'objectif.

## 6. Canaux de support

| Besoin | Canal | Délai de prise en charge |
|---|---|---|
| Question, conseil, revue | ticket `DEV-` (projet `plateforme/medisphere`) ou `plateforme@medisphere.internal` | 1 jour ouvré |
| Demande de changement (quota, nouvel environnement, personne) | MR sur `plateforme/equipes` (ou modèle « Nouvelle équipe ») | relecture sous 4 h ouvrées |
| Incident plateforme (tout le monde est touché) | `astreinte@medisphere.internal`, ticket `INC-` | 15 min, 24 h/24 |
| Incident sur ton service | ton équipe d'abord ; la Plateforme en appui si la cause semble être la plateforme | heures ouvrées (24 h/24 si production indisponible) |
| Sécurité (fuite, compromission) | `securite@medisphere.internal` + astreinte | immédiat |

## 7. Quotas par défaut

| Profil | Environnements | CPU (*requests*) | Mémoire (*requests*) | Pods | Stockage |
|---|---|---|---|---|---|
| Équipe produit | dev 0,5 · recette 0,5 · prod 1 | budget 2,5 | budget 3 Gi | 45 | 5 à 10 Gi par environnement |
| Équipe de traitements | traitements 1,5 | budget 2 | budget 3,5 Gi | 30 | 40 Gi |
| Libre-service | 1 à 2 espaces | 0,25 à 0,5 | 512 Mi | 5 à 10 | 5 Gi |
| Prestataire | un espace dans le locataire de l'équipe qui l'accueille | pris sur son budget | | | |

Au-delà : MR sur ton fichier d'équipe avec la justification (mesures, recommandations du VPA) ; la Plateforme vérifie le bilan de capacité (`docs/accueil/capacite.md`).

## 8. Le chemin balisé

1. Ton équipe existe (RB-320) → 2. portail, modèle **« Nouveau service »** → 3. ton code passe par les composants CI (image signée) → 4. la promotion ouvre une MR dans ton dépôt de déploiement, tu la fusionnes → 5. Argo CD déploie en `dev`, puis en `recette` et en `prod` par MR → 6. SLO, alertes, tableau de bord, runbook avant la production. Guide pas à pas : `docs/plateforme-dev/guide-accueil-equipe.md` et `parcours-accueil.md`.

Tout ce qui est sur le chemin est soutenu et documenté. Tout ce qui est à côté est possible, plus lent, et devient une **exception**.

## 9. Exceptions

- Une exception est **demandée** (ticket `DEV-` ou `SEC-`), **justifiée**, **bornée dans le temps** (date de revue), **validée** (Plateforme ; Sophie Laurent pour tout ce qui touche la sécurité ou les données de santé) et **inscrite** dans le registre (`docs/securite/durcissement/exceptions.md` pour la sécurité, `docs/accueil/exceptions.md` sinon).
- Jamais d'exception sur : données de santé hors de la production, secrets dans Git, images non signées en production, accès de prestataire sans date de fin, comptes partagés.
- Une exception non revue à sa date est retirée.

## 10. Évolution de cette offre

Retours : ticket `DEV-` étiqueté `offre-de-service`, revue trimestrielle (voir `retour-experience.md`, F2-S14). Toute baisse d'un niveau de service ou d'un quota par défaut est annoncée un mois avant.

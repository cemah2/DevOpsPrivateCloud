# Bienvenue sur la plateforme MédiSphère — guide d'accueil d'une équipe

> Pour : une équipe de développement qui arrive (développeurs, responsable technique). Mis à jour par l'équipe Plateforme à chaque évolution du chemin balisé (dernière : M28-E12, PLAT-2912). Questions : `plateforme@medisphere.internal`, ou un ticket `DEV-` dans GitLab.

Ce guide décrit **le chemin balisé** : la façon recommandée, outillée et soutenue de livrer un service sur la plateforme. Tu peux en sortir, mais tout ce qui est hors du chemin passe par une demande à la Plateforme, et sera plus lent.

## 0. Avant de commencer (une fois par équipe)

| Il te faut | Qui le fait | Délai | Comment vérifier |
|---|---|---|---|
| Un compte par personne dans l'annuaire, avec l'OTP | la Plateforme (ticket `DEV-` signé par ton responsable) | 1 jour ouvré | tu te connectes à <https://portail.apps.par1.medisphere.internal> (SSO Keycloak) |
| Un **groupe d'équipe** dans l'annuaire (ex. `teleconsultation`) | la Plateforme | idem | le portail montre ton équipe et ses membres (*Catalogue → Groups*) |
| Un **locataire** à ton nom d'équipe (espaces, budget, droits) | la Plateforme (runbook RB-280) | 1 jour ouvré | `kubectl get tenant <équipe>` (lecture) ou la page de ton équipe dans le portail |
| Un groupe GitLab, un projet Argo CD, un chemin dans le coffre (`kv/<équipe>/…`) | la Plateforme (RB-280) | idem | tu vois le groupe dans GitLab ; `bao kv list kv/<équipe>` |

## 1. Créer un service (10 minutes)

1. Portail → **Créer** → modèle **« Nouveau service »**.
2. Choisis ton équipe, ton locataire, un nom `<locataire>-<nom>` (minuscules, tirets), le langage (Python ou Go), une phrase de description.
3. Le portail crée deux projets dans ton groupe GitLab (le code ; le déploiement Kustomize) et ouvre deux MR à la Plateforme (ton espace `dev`, ton Application Argo CD).

**Vérifier** : le résumé du modèle donne les quatre liens ; ton composant apparaît dans le catalogue, à ton équipe.

## 2. Le voir déployé (même jour)

| Étape | Qui | Délai |
|---|---|---|
| Relecture et fusion des deux MR de la Plateforme | Plateforme | sous 4 h ouvrées |
| Premier pipeline de `main` de ton code (construction, analyse, signature) | automatique | ≈ 10 min |
| MR de promotion dans ton projet de déploiement, fusion par toi | toi | quand tu veux |
| Argo CD synchronise l'environnement `dev` | automatique | < 3 min |

**Vérifier** : fiche du composant → onglet **Kubernetes** (pods prêts) ; Argo CD (`<nom>-dev` `Synced` et `Healthy`).

## 3. Le faire monter en charge

- Une **API** (HTTP) : un HPA sur le CPU, avec un `behavior` ; jamais sans `requests` CPU. Modèle : `docs/plateforme-dev/autoscaling.md`.
- Un **consommateur de file** : un `ScaledObject` KEDA sur la profondeur de sa file ; demande à la Plateforme ton compte de lecture de la file (jamais celui du worker).
- Les **ressources** : lis les recommandations du VPA (en `Off`) après une semaine de trafic, change tes `requests` par MR.

**Vérifier** : `kubectl get hpa -n <espace>` (lecture) ; panneau « réplicas » de ton tableau de bord.

## 4. La documentation

Un dossier `docs/` et un `mkdocs.yml` dans ton projet, l'annotation `backstage.io/techdocs-ref: dir:.` dans `catalog-info.yaml`, le job `techdocs:publication` (voir `mediagenda/api`). **Vérifier** : onglet **Docs** de ta fiche.

## 5. Superviser

Tableaux de bord dans Grafana (dossier de ton équipe), journaux dans Loki (locataire de ton équipe), traces dans Tempo. Une alerte « service indisponible » et une alerte de SLO sont proposées par la Plateforme quand ton service passe en recette.

## 6. Ton espace de travail (libre-service)

Tu peux créer toi-même des espaces `<locataire>-<nom>` pour essayer (bac à sable, environnement de revue) : `kubectl create namespace <locataire>-essai-<nom>`. Ils ont Pod Security `restricted`, la seule classe de stockage `ceph-rbd`, et un **budget partagé** (`<locataire>-libre-service`) ; tu y es administrateur et tu les supprimes quand tu as fini. Rien de ce qui compte n'y vit : ils ne sont ni sauvegardés ni livrés par Argo CD.

## Ce qui est interdit, et pourquoi

| Interdit | Pourquoi |
|---|---|
| `kubectl apply` dans tes environnements (`dev`, `recette`, `prod`) | Argo CD les livre depuis Git : une modification à la main est écrasée et n'est tracée nulle part |
| Un secret dans Git | il y reste pour toujours ; les secrets vivent dans OpenBao et arrivent par ESO |
| Une image hors de Harbor, ou non signée en recette et en production | provenance, analyse de vulnérabilités, Kyverno la refuse |
| Un conteneur `root`, privilégié, ou un `hostPath` | Pod Security `restricted` le refuse : ton conteneur ne doit pas pouvoir prendre le nœud |
| Un Service `LoadBalancer` ou `NodePort` | l'exposition passe par la Gateway de la plateforme (HTTPRoute), qui porte TLS et la supervision |
| Un HPA **et** un VPA actif sur la même ressource | les deux boucles se répondent et font osciller ton service |
| Des données de santé dans les journaux, traces, métriques ou la documentation | HDS et RGPD |

## Les limites actuelles du libre-service

Ce que le modèle ne fait pas encore (demande à la Plateforme) : secrets applicatifs, base de données, file, compartiment S3, environnements `recette` et `prod`, exposition publique, alertes. Pas de cluster dédié ni de CRD à toi (multi-locataire souple : voir `comparatif-capsule-vcluster.md`).

## Aide

- Documentation : ce dossier (`docs/plateforme-dev/`) et les TechDocs de la plateforme dans le portail.
- Ticket : GitLab, projet `plateforme/medisphere`, préfixe `DEV-`.
- Incident en production : astreinte (Nadia Roussel), `astreinte@medisphere.internal`.

# Module 28 — Plateforme développeurs

| | |
|---|---|
| **Bloc** | G — Services de plateforme |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle v5 + `ceph-par1` + `k8s-par1` (≈ 111 Go) ; vCluster `vc-essai` (≈ 1 Gi) de E09 à la fin du palier 2 |
| **Prérequis** | Module 27 (`donnees-v1` : RabbitMQ, MédiNotif) ; module 20 (Argo CD, Argo Rollouts) ; module 21 (Prometheus) ; module 24 (Keycloak, groupes OIDC, FreeIPA) ; module 25 (OpenBao, External Secrets) ; module 26 (PSA, Kyverno) ; module 19 (CI, BuildKit) |
| **Durée indicative** | 40 à 50 heures (palier 1 : 8-10 h ; palier 2 : 13-16 h ; palier 3 : 10-12 h ; palier 4 : 6-8 h ; mini-projet : 4-6 h) |

## Contexte MédiSphère

Julien Petit a compté : pour lancer un nouveau service, son équipe ouvre six tickets à la Plateforme (projet GitLab, chart, espaces, quotas, Application Argo CD, secrets) et attend dix jours. Pendant les campagnes de rappel, MédiNotif prend une heure de retard parce qu'il tourne avec un seul réplica ; la nuit, trois réplicas de MédiAgenda attendent des patients qui dorment. Claire Morel veut une plateforme **en libre-service** : les équipes créent ce dont elles ont besoin dans un cadre que la Plateforme a posé (quotas, isolation, politiques), le cluster s'adapte à la charge, et un portail dit qui possède quoi.

## Objectifs

À la fin de ce module, tu sais :
- faire suivre la charge aux applications : **HPA** (`autoscaling/v2`, comportement), **KEDA** (files, cron, Prometheus, mise à zéro), **VPA** (recommandations, redimensionnement en place) sans les faire se battre ;
- partager un cluster entre équipes avec **Capsule** (locataires, quotas, libre-service encadré) et savoir quand un **vCluster** se justifie ;
- construire et exploiter un portail **Backstage** : catalogue, propriétaires, modèles qui créent un service complet par MR, état des déploiements, documentation ;
- situer Crossplane, Tilt et Skaffold ;
- diagnostiquer un autoscaling muet, des pods qui oscillent, un locataire bloqué, un portail qui ne crée plus rien.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M28-E01 | Test de positionnement : plateforme développeurs | Q | ★★ | 1 |
| M28-E02 | HPA : MédiAgenda suit sa charge | LAB | ★★ | 1 |
| M28-E03 | KEDA : MédiNotif suit sa file | LAB | ★★ | 1 |
| M28-E04 | VPA : des requêtes justes | LAB | ★★ | 1 |
| M28-E05 | Capsule : un locataire par équipe | LAB | ★★ | 1 |
| M28-E06 | Backstage : construire et installer le portail | LAB | ★★★ | 2 |
| M28-E07 | Le catalogue : services, équipes et propriétaires | LAB | ★★★ | 2 |
| M28-E08 | Un modèle « nouveau service » | LIBRE | ★★★ | 2 |
| M28-E09 | vCluster : un cluster virtuel pour une équipe, puis retrait | LAB | ★★★ | 2 |
| M28-E10 | Le portail montre l'état : plugins Kubernetes et TechDocs | LAB | ★★ | 2 |
| M28-E11 | Revue : l'autoscaling et le locataire du stagiaire | REV | ★★ | 2 |
| M28-E12 | Guide d'accueil d'une équipe : le chemin balisé | RED | ★★ | 2 |
| M28-E13 | KEDA en production : zéro, cron, Prometheus, repli | LAB | ★★★ | 3 |
| M28-E14 | Capacité et équité : quotas, priorités et recommandations | LAB | ★★★ | 3 |
| M28-E15 | Isolation des locataires : tenter de s'évader | LAB | ★★★ | 3 |
| M28-E16 | Backstage en production : mise à jour, sauvegarde, supervision | LAB | ★★★ | 3 |
| M28-E17 | ADR : la plateforme développeurs de MédiSphère | RED | ★★ | 3 |
| M28-E18 | Questions de production : plateforme développeurs | Q | ★★★ | 3 |
| M28-E19 | Panne : MédiNotif ne monte plus en charge | BF | ★★ | 4 |
| M28-E20 | Panne : des pods redémarrent en boucle depuis l'autoscaling | BF | ★★★ | 4 |
| M28-E21 | Panne : une équipe ne peut plus créer d'espace | BF | ★★ | 4 |
| M28-E22 | Panne : le portail ne crée plus de services | BF | ★★ | 4 |
| M28-E23 | Astreinte : un locataire sature le cluster | BF | ★★★★ | 4 |
| M28-E24 | Sous le capot : la boucle de l'HPA, les métriques externes et les webhooks de Capsule | LAB | ★★★★ | 4 |
| M28-E25 | Mini-projet : la plateforme développeurs de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 5 break & fix · 2 questionnaires · 1 revue · 2 rédactions.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| KEDA 2.21 | espace `keda` | Autoscaling piloté par les événements | E03 |
| VPA 1.7.1 | espace `vpa` | Recommandations de ressources | E04 |
| Capsule 0.15 | espace `capsule-system`, locataires dans `plateforme/k8s/locataires/` | Multi-locataire | E05 |
| Backstage 1.56 | espace `portail`, base CNPG `portail-db`, projet `plateforme/portail`, `https://portail.apps.par1.medisphere.internal` | Portail développeurs | E06 |
| vCluster 0.37 `vc-essai` | locataire `medidoc` | Comparaison, **retiré** en fin de palier 2 | E09 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.13. Versions : [`annexes/versions-bloc-G.md`](../../annexes/versions-bloc-G.md). Fiches : [`annexes/decouverte/crossplane.md`](../../annexes/decouverte/crossplane.md), [`annexes/decouverte/tilt-skaffold.md`](../../annexes/decouverte/tilt-skaffold.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 28 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 28 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

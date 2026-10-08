# Module 13 — Registre et chaîne d'approvisionnement logicielle

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle + `reg01` (1013, 6 Go, rejoint le socle) ; `reg02` (2131, 4 Go) ponctuellement |
| **Prérequis** | Module 12 (images, `runner02`, pipelines de construction) ; module 06 (step-ca, PowerDNS) |
| **Durée indicative** | 20 à 28 heures |

## Contexte MédiSphère

Les images de MédiSphère existent, mais elles vivent sur un registre de travail sans contrôle d'accès, et les images de base sont tirées directement de Docker Hub. L'incident Trivy de mars 2026 (une version piégée de l'outil de sécurité lui-même) a fait le tour des comités de sécurité : Sophie Laurent veut savoir **d'où vient chaque image**, ce qu'elle contient, qui l'a signée, et pouvoir répondre en une heure à « sommes-nous touchés par cette CVE ? ». Karim Benali veut un registre d'entreprise, des caches des registres publics et des dépendances tenues à jour automatiquement.

## Objectifs

À la fin de ce module, tu sais :
- installer et exploiter Harbor : projets, robots, caches de registres publics, quotas, rétention, réplication, sauvegarde, mise à jour ;
- analyser des images (Trivy, Grype) et produire des SBOM (Syft) ;
- signer et vérifier des images et des attestations avec Cosign 3, et imposer la signature ;
- construire une chaîne de livraison d'images complète en CI ;
- tenir les dépendances à jour avec Renovate ;
- expliquer et manipuler l'API de distribution OCI.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M13-E01 | Questions : la chaîne d'approvisionnement logicielle | Q | ★★ | 1 |
| M13-E02 | Installer Harbor sur `reg01` | LAB | ★★ | 1 |
| M13-E03 | Projets, membres et comptes robots | LAB | ★★ | 1 |
| M13-E04 | Des caches pour les registres publics | LAB | ★★ | 1 |
| M13-E05 | Analyser les images avec Trivy | LAB | ★★ | 1 |
| M13-E06 | SBOM avec Syft, analyse avec Grype | LAB | ★★ | 2 |
| M13-E07 | Signer et vérifier avec Cosign | LAB | ★★★ | 2 |
| M13-E08 | Attestations : SBOM et provenance attachés à l'image | LAB | ★★★ | 2 |
| M13-E09 | La chaîne de livraison d'une image | LIBRE | ★★★ | 2 |
| M13-E10 | Quotas, rétention et immuabilité des étiquettes | LAB | ★★ | 2 |
| M13-E11 | Renovate auto-hébergé | LAB | ★★★ | 2 |
| M13-E12 | Revue : la chaîne de livraison du stagiaire | REV | ★★ | 2 |
| M13-E13 | Répliquer vers un second registre | LAB | ★★★ | 3 |
| M13-E14 | Politiques : signature obligatoire, vulnérabilités bloquantes | LAB | ★★★ | 3 |
| M13-E15 | Sauvegarder et restaurer Harbor | LAB | ★★★ | 3 |
| M13-E16 | Superviser et mettre à jour Harbor | LAB | ★★★ | 3 |
| M13-E17 | ADR : registre et politique de confiance des images | RED | ★★ | 3 |
| M13-E18 | Alerte CVE critique : répondre en temps limité | CHRONO | ★★★ | 3 |
| M13-E19 | Panne : impossible de tirer l'image | BF | ★★ | 4 |
| M13-E20 | Panne : la publication de l'image échoue | BF | ★★★ | 4 |
| M13-E21 | Panne : la signature n'est plus reconnue | BF | ★★★ | 4 |
| M13-E22 | Panne : Harbor ne démarre plus | BF | ★★★ | 4 |
| M13-E23 | Sous le capot : l'API de distribution OCI | LAB | ★★★ | 4 |
| M13-E24 | Questions expert : supply chain | Q | ★★★ | 4 |
| M13-E25 | Mini-projet : registre MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 4 break & fix · 2 questionnaires · 1 revue · 1 rédaction · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Réseau | Rôle | Exercice |
|---|---|---|---|---|
| `reg01` | **1013** (socle) | INFRA 10.10.20.18 | Harbor 2.15, `https://registry.par1.medisphere.internal` | E02 |
| `reg02` | 2131 | `vsandbox` (DHCP) | Registre de réplication (détruit en fin de module) | E13 |

Projets Harbor, caches, robots, signature Cosign et Renovate : voir [`PLAN.md`](../../PLAN.md) §4.10. À partir de ce module, toutes les images de MédiSphère sont publiées dans Harbor et signées ; les nœuds Kubernetes (M14) tireront les images publiques par ses caches.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 13 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 13 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

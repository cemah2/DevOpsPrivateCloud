# Module 25 — Secrets

| | |
|---|---|
| **Bloc** | F — Sécurité |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v5 (avec `vault01-03` et `kms01`) + `ceph-par1` + `k8s-par1` (≈ 111 Go) ; `bao-essai` (2251, 2 Go) le temps de M25-E30 |
| **Prérequis** | Module 24 (`identite-v1` : Keycloak, groupes de l'annuaire) ; module 19 (jetons d'identité `id_tokens`, runner protégé, Cosign) ; module 20 (Argo CD, `secrets-k8s.sh`) ; module 16 (CloudNativePG) ; module 04 (Ansible Vault) ; module 06 (step-ca, racine hors ligne) |
| **Durée indicative** | 85 à 105 heures (palier 1 : 15-19 h ; palier 2 : 31-37 h ; palier 3 : 22-27 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

Le registre des risques de Sophie Laurent a une ligne qui ne descend jamais : « secrets ». Mots de passe dans Ansible Vault déchiffré sur `adm01`, clé Cosign dans un Secret du runner, Secrets Kubernetes créés à la main par un script hors Git, jetons GitLab de longue durée, mot de passe PostgreSQL de MédiAgenda inchangé depuis la recette. Quand Lucas a collé un fichier `.env` dans un ticket le mois dernier, personne n'a su dire quels secrets il fallait changer, ni qui les avait lus. Claire Morel veut un **coffre** : des secrets centralisés, délivrés à des identités vérifiées (personnes par le SSO, jobs de CI par leur jeton signé, pods par leur compte de service), **à durée de vie courte** quand c'est possible, tournés sans coupure, audités, sauvegardés, et un coffre qui redémarre seul sans exposer ses clés.

## Objectifs

À la fin de ce module, tu sais :
- installer et exploiter **OpenBao** (fork libre de Vault) : initialisation, descellement Shamir puis automatique (`transit`), grappe Raft, sauvegarde, montée de version ;
- écrire des politiques au plus juste et authentifier personnes (OIDC), jobs de CI (JWT de GitLab), pods (Kubernetes) et machines (AppRole) ;
- servir des secrets statiques (KV v2), **dynamiques** (PostgreSQL), du chiffrement (transit) et des certificats (PKI) ;
- livrer les secrets à Kubernetes par **External Secrets Operator**, et comparer SOPS, Sealed Secrets et le pilote CSI ;
- tourner un secret sans coupure, répondre à une fuite, prouver par l'audit qui a lu quoi ;
- diagnostiquer un coffre scellé, sans leader, une politique trop stricte, un secret dynamique expiré.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M25-E01 | Test de positionnement : secrets | Q | ★★ | 1 |
| M25-E02 | Inventaire des secrets de MédiSphère | RED | ★★ | 1 |
| M25-E03 | Installer et initialiser OpenBao sur `vault01` | LAB | ★★ | 1 |
| M25-E04 | Premiers pas : KV v2, versions, CLI et API | LAB | ★ | 1 |
| M25-E05 | Politiques et jetons | LAB | ★★ | 1 |
| M25-E06 | Les personnes entrent par le SSO : méthode OIDC | LAB | ★★ | 1 |
| M25-E07 | Les machines : AppRole pour les checks et `medictl` | LAB | ★★ | 1 |
| M25-E08 | OpenBao en code avec OpenTofu | LAB | ★★ | 1 |
| M25-E09 | Questions : barrière, seal, baux et chemins | Q | ★★ | 1 |
| M25-E10 | La CI sans secret durable : jetons d'identité de GitLab | LAB | ★★★ | 2 |
| M25-E11 | Ansible lit ses secrets dans OpenBao | LAB | ★★ | 2 |
| M25-E12 | Méthode Kubernetes et External Secrets Operator | LAB | ★★ | 2 |
| M25-E13 | Migrer les Secrets hors Git vers des ExternalSecret | LAB | ★★★ | 2 |
| M25-E14 | Identifiants dynamiques PostgreSQL pour MédiAgenda | LAB | ★★★ | 2 |
| M25-E15 | Tourner un secret sans redémarrage manuel | LAB | ★★★ | 2 |
| M25-E16 | PKI de services : « MédiSphère Services CA » et cert-manager | LAB | ★★★ | 2 |
| M25-E17 | Transit : le chiffrement comme service | LAB | ★★ | 2 |
| M25-E18 | Des secrets chiffrés dans Git : SOPS, age et transit | LAB | ★★ | 2 |
| M25-E19 | Comparer : Sealed Secrets et Secrets Store CSI | LAB | ★★ | 2 |
| M25-E20 | Signer avec une clé qui ne sort jamais du coffre | LAB | ★★★ | 2 |
| M25-E21 | Audit : qui a lu quel secret | LAB | ★★ | 2 |
| M25-E22 | Revue : les politiques du stagiaire | REV | ★★ | 2 |
| M25-E23 | Runbook : un secret a fuité | RED | ★★ | 2 |
| M25-E24 | Grappe Raft à trois nœuds et VIP | LAB | ★★★ | 3 |
| M25-E25 | Auto-descellement : `kms01` et migration du seal | LAB | ★★★ | 3 |
| M25-E26 | Instantanés chiffrés et restauration éprouvée | LAB | ★★★ | 3 |
| M25-E27 | Superviser OpenBao | LAB | ★★ | 3 |
| M25-E28 | Durcir OpenBao : jeton racine, enveloppement, systemd, TLS | LAB | ★★★ | 3 |
| M25-E29 | Monter de version la grappe sans coupure | LAB | ★★ | 3 |
| M25-E30 | Comparer : HashiCorp Vault 2.2 | LAB | ★★ | 3 |
| M25-E31 | ADR : le coffre de MédiSphère et le chiffrement d'etcd | RED | ★★ | 3 |
| M25-E32 | Questions de production : secrets | Q | ★★★ | 3 |
| M25-E33 | Une politique de rotation automatisée | LIBRE | ★★★ | 3 |
| M25-E34 | Rotation d'urgence en temps limité | CHRONO | ★★★ | 3 |
| M25-E35 | Panne : le coffre est scellé après un redémarrage | BF | ★★ | 4 |
| M25-E36 | Panne : la CI ne lit plus ses secrets | BF | ★★★ | 4 |
| M25-E37 | Panne : un ExternalSecret en erreur | BF | ★★ | 4 |
| M25-E38 | Panne : MédiAgenda perd sa base | BF | ★★★ | 4 |
| M25-E39 | Panne : la grappe n'a plus de leader | BF | ★★★ | 4 |
| M25-E40 | Panne : « permission denied » | BF | ★★ | 4 |
| M25-E41 | Panne : les certificats de service sont refusés | BF | ★★ | 4 |
| M25-E42 | Panne : l'auto-descellement échoue | BF | ★★★ | 4 |
| M25-E43 | Astreinte : la nuit où le coffre s'est fermé | BF | ★★★★ | 4 |
| M25-E44 | Sous le capot : barrière, trousseau, Raft et baux | LAB | ★★★★ | 4 |
| M25-E45 | Questions expert : secrets | Q | ★★★ | 4 |
| M25-E46 | Mini-projet : les secrets de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| `vault01-03` | VMID 1021-1023, 10.10.20.21-23 ; VIP 10.10.20.200 `openbao.par1.medisphere.internal:8200` | OpenBao 2.7 en grappe Raft | E03, E24 |
| `kms01` | VMID 1024, 10.10.20.24 | OpenBao de descellement (`transit`) | E25 |
| `plateforme/secrets` | projet GitLab | Configuration d'OpenBao en OpenTofu (`hashicorp/vault`) | E08 |
| External Secrets Operator 2.13 | espace `external-secrets` (Argo CD) | ClusterSecretStore `openbao` | E12 |
| `bao-essai` | VMID 2251, `vsandbox` | HashiCorp Vault 2.2 en comparaison, **détruite** | E30 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.12. Versions : [`annexes/versions-bloc-F.md`](../../annexes/versions-bloc-F.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 25 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 25 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

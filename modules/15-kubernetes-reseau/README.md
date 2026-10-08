# Module 15 — Réseau Kubernetes

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Cœur |
| **Profil de lab** | k8s : socle + `k8s-par1` ; `m15-essai` (2151, 4 Go) ponctuellement |
| **Prérequis** | Module 14 (`k8s-v1`) ; module 07 (FRR et BGP de la bordure, répartiteurs `lb01`/`lb02`) ; module 06 (PowerDNS, step-ca) |
| **Durée indicative** | 45 à 55 heures |

## Contexte MédiSphère

MédiAgenda tourne sur `k8s-par1`, mais personne ne peut l'atteindre sans un `kubectl port-forward`. Julien Petit veut une adresse, un nom et un certificat pour chaque environnement, sans ouvrir de ticket. Sophie Laurent veut que les pods d'une équipe ne parlent qu'à ce qu'ils doivent, et que le trafic entre nœuds soit chiffré. Karim Benali a une contrainte : ingress-nginx, que le prestataire utilisait partout, a été **retiré par son projet** en mars 2026 ; MédiSphère partira directement sur la **Gateway API**, servie par Cilium, avec des IP de service annoncées en BGP à la bordure.

## Objectifs

À la fin de ce module, tu sais :
- expliquer et observer le modèle réseau de Kubernetes (pods, Services, EndpointSlices, DNS) et le chemin d'un paquet avec Cilium et eBPF ;
- remplacer kube-proxy par Cilium, attribuer des IP de service (LB IPAM) et les annoncer en BGP ;
- publier des applications par la Gateway API, avec des certificats cert-manager (ACME de step-ca) et des noms publiés par ExternalDNS ;
- écrire des politiques réseau L3/L4/L7 et segmenter un cluster multi-équipes ;
- chiffrer, superviser, mesurer et mettre à jour le réseau du cluster ;
- diagnostiquer les pannes de Services, DNS, politiques, BGP, Gateway et certificats.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M15-E01 | Test de positionnement : réseau Kubernetes | Q | ★★ | 1 |
| M15-E02 | Suivre un paquet de pod à pod | LAB | ★★ | 1 |
| M15-E03 | Services : ClusterIP, NodePort, headless et EndpointSlices | LAB | ★★ | 1 |
| M15-E04 | CoreDNS : résolution interne et DNS de MédiSphère | LAB | ★★ | 1 |
| M15-E05 | Cilium et Hubble : observer les flux | LAB | ★★ | 1 |
| M15-E06 | Premières politiques réseau : tout interdire par défaut | LAB | ★★ | 1 |
| M15-E07 | Gateway API : premières routes HTTP | LAB | ★★ | 1 |
| M15-E08 | Remplacer kube-proxy par Cilium | LAB | ★★★ | 1 |
| M15-E09 | Questions : CNI, eBPF et Services | Q | ★★ | 1 |
| M15-E10 | LB IPAM : des adresses de service en 10.10.41.0/24 | LAB | ★★ | 2 |
| M15-E11 | BGP : annoncer les services à la bordure | LAB | ★★★ | 2 |
| M15-E12 | La Gateway principale `gw-par1` et le TLS | LAB | ★★★ | 2 |
| M15-E13 | cert-manager et l'ACME de step-ca | LAB | ★★ | 2 |
| M15-E14 | Défis DNS-01 par RFC 2136 : la zone `apps` | LAB | ★★★ | 2 |
| M15-E15 | ExternalDNS : publier les noms automatiquement | LAB | ★★ | 2 |
| M15-E16 | Routage avancé : poids, en-têtes, réécritures, gRPC et TLS | LAB | ★★★ | 2 |
| M15-E17 | Les politiques réseau de MédiAgenda | LIBRE | ★★★ | 2 |
| M15-E18 | Migrer les Ingress d'InfoGér vers la Gateway API | LAB | ★★★ | 2 |
| M15-E19 | MetalLB en comparaison | LAB | ★★ | 2 |
| M15-E20 | Publier une application hors du lab par `lb01`/`lb02` | LAB | ★★★ | 2 |
| M15-E21 | Revue : politiques et routes du stagiaire | REV | ★★ | 2 |
| M15-E22 | Runbook : un service n'est plus joignable | RED | ★★ | 2 |
| M15-E23 | Le réseau du cluster décrit par le code | LIBRE | ★★★ | 2 |
| M15-E24 | Chiffrer le trafic entre nœuds | LAB | ★★★ | 3 |
| M15-E25 | Haute disponibilité de l'entrée : perdre un nœud, une passerelle | LAB | ★★★ | 3 |
| M15-E26 | Superviser le réseau du cluster | LAB | ★★ | 3 |
| M15-E27 | Mettre à jour Cilium sans coupure | LAB | ★★★ | 3 |
| M15-E28 | Segmenter un cluster multi-équipes | LAB | ★★★ | 3 |
| M15-E29 | Mesurer les performances réseau | LAB | ★★★ | 3 |
| M15-E30 | ADR : le réseau et l'entrée de `k8s-par1` | RED | ★★ | 3 |
| M15-E31 | Questions de production : réseau Kubernetes | Q | ★★★ | 3 |
| M15-E32 | La matrice des flux du cluster | RED | ★★ | 3 |
| M15-E33 | Durcir l'entrée : TLS, en-têtes et authentification mutuelle | LAB | ★★★ | 3 |
| M15-E34 | Publier une nouvelle application en temps limité | CHRONO | ★★★ | 3 |
| M15-E35 | Panne : le service ne répond plus | BF | ★★ | 4 |
| M15-E36 | Panne : la résolution DNS échoue dans les pods | BF | ★★ | 4 |
| M15-E37 | Panne : plus rien ne passe dans l'espace de noms | BF | ★★ | 4 |
| M15-E38 | Panne : l'adresse du LoadBalancer est injoignable | BF | ★★★ | 4 |
| M15-E39 | Panne : la Gateway refuse le HTTPS | BF | ★★★ | 4 |
| M15-E40 | Panne : le certificat n'est jamais délivré | BF | ★★★ | 4 |
| M15-E41 | Panne : le nom n'est plus publié | BF | ★★ | 4 |
| M15-E42 | Panne : les pods ne se joignent plus entre nœuds | BF | ★★★ | 4 |
| M15-E43 | Astreinte : plus rien n'entre dans le cluster | BF | ★★★★ | 4 |
| M15-E44 | Sous le capot : eBPF et les tables de Cilium | LAB | ★★★★ | 4 |
| M15-E45 | Questions expert : réseau Kubernetes | Q | ★★★ | 4 |
| M15-E46 | Mini-projet : réseau Kubernetes MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et objets créés dans ce module

| Élément | Valeur | Exercice |
|---|---|---|
| Pool LB IPAM `lb-par1` | 10.10.41.10-10.10.41.199 | E10 |
| BGP | nœuds en AS 65040 ↔ `gw01` (10.10.40.2) et `gw02` (10.10.40.3) en AS 65000 | E11 |
| Gateway `gw-par1` | espace `passerelles`, 10.10.41.10, `*.apps.par1.medisphere.internal` | E12 |
| Zone DNS | `apps.par1.medisphere.internal` (RFC 2136, clés TSIG `externaldns-k8s` et `certmanager-k8s`) | E14-E15 |
| `m15-essai` | VMID 2151, `vsandbox`, kubeadm mononœud pour MetalLB (détruite en fin de module) | E19 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.10.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 15 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 15 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

# ADR-0260 — Stratégie de durcissement et de détection

| | |
|---|---|
| Statut | Accepté (<DATE>) |
| Décideurs | Claire Morel, Sophie Laurent (RSSI), Karim Benali |
| Ticket | PLAT-2731 |
| Remplace / complète | complète ADR-0150 (réseau du cluster), ADR-0240 (identité), ADR-0250 (secrets) |

## Contexte

L'audit HDS approche. Il demandera un référentiel, la preuve qu'on le mesure, les écarts acceptés et signés, et la réponse à une compromission. Avant le module 26 : des VMs « un peu durcies » par chaque module, une admission limitée à Pod Security et à quelques VAP du M14, aucune observation des processus, des nœuds qui se parlent en clair hors trafic des pods, aucun filtrage local des nœuds.

Le modèle de menace (E02) retient en priorité : compromission d'un conteneur applicatif exposé (MédiAgenda), vol d'identifiants d'administration, image malveillante dans la chaîne d'approvisionnement, mouvement latéral depuis un pod vers les nœuds ou les services du socle, dérive silencieuse de configuration, initié malveillant ou erreur d'un administrateur.

Contraintes : équipe de quatre personnes plus un stagiaire ; logiciels libres, hébergés chez nous (souveraineté) ; lab de 128 Go déjà occupé à 111 Go ; astreinte qui ne doit pas être réveillée par la sécurité sans raison (Nadia) ; tout en code, GitOps.

## Décisions et options, par couche

Critères : **C** couverture du besoin, **M** maturité et licence, **R** ressources dans le lab, **E** compétences et exploitation, **D** risque pour la disponibilité, **P** preuves fournies à l'auditeur. Notes de 1 (faible) à 3 (fort).

### 1. Référentiels

| Option | C | M | R | E | D | P | Commentaire |
|---|---|---|---|---|---|---|---|
| CIS seul | 2 | 3 | 3 | 3 | 2 | 2 | reconnu internationalement, outillé (ComplianceAsCode) |
| ANSSI-BP-028 seul | 2 | 3 | 3 | 2 | 2 | 2 | attendu par un auditeur français, plus exigeant en accès et journalisation |
| **CIS niveau 1 serveur + ANSSI intermédiaire** | 3 | 3 | 2 | 2 | 2 | 3 | **retenu** : les deux profils existent pour Debian 13 et RHEL 10 dans ComplianceAsCode 0.1.82 ; coût : deux analyses |
| DISA STIG | 2 | 3 | 3 | 1 | 1 | 2 | pensé pour la défense américaine, nombreuses règles hors sujet |

### 2. Mesure des hôtes

| Option | C | M | R | E | D | P | Commentaire |
|---|---|---|---|---|---|---|---|
| **OpenSCAP + ComplianceAsCode + Lynis** | 3 | 3 | 2 | 2 | 3 | 3 | **retenu** : ARF normalisé, profil adapté = exceptions codées ; Lynis en indice lisible |
| Lynis seul | 1 | 3 | 3 | 3 | 3 | 1 | pas de référentiel, pas de preuve règle par règle |
| Wazuh (SCA + agent) | 3 | 2 | 1 | 1 | 2 | 3 | gestionnaire et indexeur lourds (OpenSearch) : hors budget mémoire |
| Produit commercial | 3 | 3 | 2 | 2 | 2 | 3 | coût, données de configuration hors de chez nous |

### 3. Durcissement

| Option | Commentaire |
|---|---|
| **Rôle Ansible `durcissement` maison, exceptions déclarées** (retenu) | lisible, testé sur VMs d'essai, appliqué par vagues ; exceptions et *tailoring* générés du même registre |
| Collection communautaire (ex. `devsec.hardening`) | rapide, mais pas alignée règle par règle sur nos profils, et des choix par défaut à contourner |
| Remédiations générées par ComplianceAsCode (playbooks) | couverture totale, mais des centaines de tâches non relues qui cassent des services (M03) |
| Images dorées durcies seules | nécessaire (M03) mais insuffisant : la dérive arrive après le démarrage |

### 4. Admission dans Kubernetes

| Option | C | M | R | E | D | P | Commentaire |
|---|---|---|---|---|---|---|---|
| Pod Security seule | 1 | 3 | 3 | 3 | 3 | 1 | indispensable, retenue en socle, mais ne vérifie ni registre ni signature |
| **Kyverno 1.19, politiques CEL `policies.kyverno.io/v1`** | 3 | 2 | 2 | 2 | 2 | 3 | **retenu** : validation, mutation, génération, signatures Cosign, exceptions datées, rapports |
| OPA Gatekeeper 3.23 | 2 | 3 | 2 | 1 | 2 | 2 | Rego à apprendre, pas de vérification de signature intégrée ni de génération |
| VAP/MAP natives seules | 2 | 3 | 3 | 2 | 3 | 1 | pas de rapports, pas d'images ; retenues en complément pour les règles simples (E17) |

### 5. Détection à l'exécution

| Option | Commentaire |
|---|---|
| **Falco 0.45 (détection) + Tetragon 1.7 (observation fine, application ciblée)** (retenu) | Falco : règles communautaires riches, acheminement mûr (falcosidekick) ; Tetragon : filtrage dans le noyau, politiques par espace, **blocage** ; recouvrement assumé sur 3 règles |
| Falco seul | ne bloque rien |
| Tetragon seul | peu de règles prêtes à l'emploi, acheminement à construire |
| Kubescape node-agent | prometteur (version 4), moins éprouvé pour la détection en continu |

### 6. Réseau

| Option | Commentaire |
|---|---|
| **WireGuard de Cilium, pods (M15) + nœud à nœud (M26-E26)** (retenu) | clés gérées par Cilium, coût processeur mesuré ; nœuds de contrôle exclus (amorçage des clés), mode strict écarté |
| IPsec de Cilium | clés à gérer, incompatible avec le pare-feu d'hôte (*known issues*) |
| Maillage de services (mTLS) | identité par charge, mais un composant de plus par pod ou par nœud ; à réévaluer (ztunnel) |
| **Pare-feu d'hôte de Cilium** (retenu) | politiques comme le reste du cluster, audit avant application, pas de conflit avec le chemin de données |
| nftables local sur les nœuds | se bat avec les règles de Cilium et de kube-proxy historique, invisible de Hubble |
| Rien (bordure seule) | tout le VLAN 40 joint le kubelet et etcd |

## Conséquences

### Positives

- Une mesure hebdomadaire de tout le parc, opposable (ARF conservés trois ans), avec ses exceptions signées.
- Une admission qui refuse ce qui n'est pas conforme en recette et en production, des rapports pour le reste.
- Une détection en minutes, acheminée vers l'astreinte et conservée un an (Loki `audit`).
- Des nœuds filtrés en entrée et un trafic inter-nœuds chiffré, hors nœuds de contrôle.

### Négatives et leur action

| Conséquence | Action ou acceptation |
|---|---|
| Faux positifs et fatigue d'alerte (Falco, Tetragon, Kyverno en audit) | revue mensuelle des alertes (objectif : moins de 5 alertes ignorées par semaine), exceptions par macro/`PolicyException` datées (RB-261) |
| Double détection Falco/Tetragon sur quelques règles | acceptée : deux mécanismes indépendants ; corrélation dans Grafana |
| Dépendance à eBPF et au noyau (Falco, Tetragon, Cilium) | noyaux épinglés par l'image dorée ; montée de noyau testée sur un travailleur d'abord |
| `ClusterPolicy` supprimée en Kyverno 1.20 | déjà évitée : politiques CEL uniquement ; montée en 1.20 planifiée après sa sortie |
| Pare-feu d'hôte : un oubli coupe un nœud | audit 24 h par nœud, ordre imposé, RB-264 éprouvé, accès console |
| Chiffrement nœud à nœud en *beta*, nœuds de contrôle exclus | accepté ; flux restants en TLS ou sans secret (`chiffrement.md`) ; révision à la sortie en stable |
| Analyses hebdomadaires : charge sur `pve01` le dimanche | décalage aléatoire fixe, quotas de l'unité |
| Registre d'exceptions qui vieillit | date de revue obligatoire, alerte du check du mini-projet sur les exceptions expirées |
| Effort d'exploitation (≈ 0,5 ETP) | accepté par Claire Morel ; réévalué à 6 mois |

## Conditions de révision

- Score moyen CIS sous l'objectif (85) deux semaines de suite sans plan de remédiation.
- Plus de 20 alertes Falco ignorées par semaine pendant un mois.
- Chiffrement nœud à nœud de Cilium en stable, ou ztunnel en stable.
- Sortie de Kyverno 1.20 ; nouvelle version majeure de CIS Debian ou RHEL.
- Un incident réel où une couche a manqué (post-mortem).

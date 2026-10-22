# Module 26 — Durcissement et sécurité à l'exécution

| | |
|---|---|
| **Bloc** | F — Sécurité |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v5 + `ceph-par1` + `k8s-par1` (≈ 111 Go) ; `durci-deb` (2261) et `durci-rocky` (2262), 2 Go chacune, le temps des paliers 1 et 2 |
| **Prérequis** | Module 25 (`secrets-v1`) ; module 24 (identité, SSSD) ; module 04 (rôles Ansible) ; module 13 (signatures Cosign) ; module 14 (audit, PSA, kubeadm) ; module 15 (Cilium) ; modules 21 et 22 (alertes, locataire Loki `audit`) |
| **Durée indicative** | 85 à 105 heures (palier 1 : 15-19 h ; palier 2 : 30-36 h ; palier 3 : 23-28 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

L'auditeur HDS vient dans six semaines. Il demandera un référentiel, la preuve qu'on le mesure, la liste des écarts acceptés et signés, et ce qui se passe quand un conteneur est compromis. Aujourd'hui, chaque VM a été « un peu durcie » par son module, le cluster accepte n'importe quel pod que l'API veut bien créer, rien ne regarde ce que font les processus, et les nœuds se parlent en clair. Sophie Laurent fixe le cap : **CIS et ANSSI comme référentiels, mesurés chaque semaine, appliqués par le code avec des exceptions écrites ; une admission qui refuse ce qui n'est pas conforme ; une détection à l'exécution qui alerte en minutes ; une réponse à incident répétée**. Nadia Roussel, elle, pose une condition : que le durcissement ne casse pas l'astreinte.

## Objectifs

À la fin de ce module, tu sais :
- mesurer un parc par rapport à un référentiel (OpenSCAP et ComplianceAsCode, Lynis, ssh-audit, kube-bench, kubescape) et lire un écart ;
- durcir des hôtes Debian et Rocky par un rôle Ansible (SSH, PAM, sudo, noyau, auditd, AIDE, AppArmor, SELinux), par vagues et avec exceptions écrites ;
- imposer Pod Security Admission, écrire des politiques Kyverno en CEL (validation, signatures d'images, mutation, génération) et des politiques d'admission natives ;
- détecter à l'exécution avec Falco et Tetragon, et bloquer avec Tetragon ;
- chiffrer le trafic entre nœuds et filtrer les hôtes avec Cilium, et sécuriser les kubelets ;
- mener une réponse à incident sur un conteneur compromis ;
- diagnostiquer ce que le durcissement casse.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M26-E01 | Test de positionnement : sécurité des systèmes et de Kubernetes | Q | ★★ | 1 |
| M26-E02 | Modèle de menace de la plateforme | RED | ★★ | 1 |
| M26-E03 | Mesurer avant d'agir : Lynis et ssh-audit | LAB | ★ | 1 |
| M26-E04 | OpenSCAP et ComplianceAsCode : évaluer une VM contre CIS et ANSSI | LAB | ★★ | 1 |
| M26-E05 | kube-bench et kubescape : évaluer `k8s-par1` | LAB | ★★ | 1 |
| M26-E06 | Pod Security Admission : auditer puis imposer `restricted` | LAB | ★★ | 1 |
| M26-E07 | Kyverno : installation et premières politiques CEL | LAB | ★★ | 1 |
| M26-E08 | Falco : installation et premières détections | LAB | ★★ | 1 |
| M26-E09 | Questions : référentiels, contrôles et défense en profondeur | Q | ★★ | 1 |
| M26-E10 | Le rôle Ansible `durcissement` sur les VMs d'essai | LAB | ★★★ | 2 |
| M26-E11 | Accès : SSH, PAM, sudo et comptes | LAB | ★★ | 2 |
| M26-E12 | Tracer et détecter : auditd et AIDE | LAB | ★★ | 2 |
| M26-E13 | Confiner un service : AppArmor et SELinux | LAB | ★★★ | 2 |
| M26-E14 | Durcir le socle par vagues | LAB | ★★★ | 2 |
| M26-E15 | Kyverno : n'admettre que les images signées | LAB | ★★★ | 2 |
| M26-E16 | Kyverno : muter et générer | LAB | ★★ | 2 |
| M26-E17 | Politiques d'admission natives : ValidatingAdmissionPolicy et MutatingAdmissionPolicy | LAB | ★★ | 2 |
| M26-E18 | Exceptions et rapports de politiques | LAB | ★★ | 2 |
| M26-E19 | Falco : règles de MédiSphère et acheminement des alertes | LAB | ★★ | 2 |
| M26-E20 | Tetragon : observer processus, fichiers et réseau | LAB | ★★★ | 2 |
| M26-E21 | Des charges sûres par construction | LAB | ★★ | 2 |
| M26-E22 | Revue : les manifestes et le Dockerfile du stagiaire | REV | ★★ | 2 |
| M26-E23 | Registre des exceptions et procédure de dérogation | RED | ★★ | 2 |
| M26-E24 | Conformité continue : analyses hebdomadaires, rapports, alertes | LAB | ★★★ | 3 |
| M26-E25 | Kubelets : certificats de service et approbation des CSR | LAB | ★★★ | 3 |
| M26-E26 | Chiffrement transparent entre nœuds avec WireGuard | LAB | ★★★ | 3 |
| M26-E27 | Pare-feu d'hôte de Cilium | LAB | ★★★★ | 3 |
| M26-E28 | Audit Kubernetes revisité : politique, détection, rétention | LAB | ★★ | 3 |
| M26-E29 | Tetragon en application : bloquer | LAB | ★★★ | 3 |
| M26-E30 | Correctifs de sécurité : le parc, le cluster et les images en service | LAB | ★★ | 3 |
| M26-E31 | ADR : la stratégie de durcissement et de détection | RED | ★★ | 3 |
| M26-E32 | Questions de production : sécurité | Q | ★★★ | 3 |
| M26-E33 | Préparer la réponse à incident | LIBRE | ★★★ | 3 |
| M26-E34 | Audit de conformité en temps limité | CHRONO | ★★★ | 3 |
| M26-E35 | Panne : plus aucun déploiement ne passe en recette | BF | ★★ | 4 |
| M26-E36 | Panne : un pod privilégié est passé | BF | ★★★ | 4 |
| M26-E37 | Panne : Falco est muet | BF | ★★ | 4 |
| M26-E38 | Panne : sudo cassé après le durcissement | BF | ★★ | 4 |
| M26-E39 | Panne : un service confiné ne démarre plus | BF | ★★★ | 4 |
| M26-E40 | Panne : des nœuds ne se parlent plus | BF | ★★★ | 4 |
| M26-E41 | Panne : `kubectl logs` et `exec` refusés | BF | ★★ | 4 |
| M26-E42 | Incident : un conteneur compromis | BF | ★★★ | 4 |
| M26-E43 | Astreinte : la semaine avant l'audit | BF | ★★★★ | 4 |
| M26-E44 | Sous le capot : eBPF, LSM et chaîne d'admission | LAB | ★★★★ | 4 |
| M26-E45 | Questions expert : sécurité | Q | ★★★ | 4 |
| M26-E46 | Mini-projet : MédiSphère durcie v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| `durci-deb`, `durci-rocky` | VMID 2261, 2262, `vsandbox` | VMs d'essai du durcissement, **détruites** en fin de palier 2 | E04, E10 |
| Rôle `durcissement` | `plateforme/ansible` | CIS / ANSSI-BP-028, exceptions déclarées | E10 |
| Kyverno 1.19 | espace `kyverno` (Argo CD) | Admission : politiques CEL `policies.kyverno.io/v1` | E07 |
| Falco 0.45 + falcosidekick | espace `falco` (Argo CD) | Détection à l'exécution | E08 |
| Tetragon 1.7 | espace `tetragon` (Argo CD) | Observabilité et application eBPF | E20 |
| `plateforme/politiques` | projet GitLab | Politiques Kyverno, règles Falco, `TracingPolicy` | E07 |
| kubelet-csr-approver 1.2 | Argo CD | Approbation des certificats de service des kubelets | E25 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.12. Versions : [`annexes/versions-bloc-F.md`](../../annexes/versions-bloc-F.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 26 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 26 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

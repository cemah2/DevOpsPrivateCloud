# Audit technique outillé — audit à blanc 2026

> SEC-3605 (F6-S05). Réalisé du 2026-11-16 au 2026-11-18 par la Plateforme (auditeur interne : `<MOI>`), relu par Karim Benali, présenté à Hélène Mercier (Auditia Santé) le 2026-11-19.
> **Exemple de référence** : les nombres et constats ci-dessous sont ceux d'un lab type ; les tiens viennent de tes outils.

## 1. Synthèse

| Domaine | Outil | Résultat | Constats retenus (après tri) |
|---|---|---|---|
| Hôtes du socle | OpenSCAP (CIS niveau 1 serveur, ANSSI-BP-028 intermédiaire), Lynis | CIS 84 à 91 %, ANSSI 76 à 83 % ; aucun hôte sans analyse depuis 7 jours | 0 critique, 2 élevés, 5 moyens |
| Cluster `k8s-par1` | kube-bench (`cis-1.12` forcé), kubescape (NSA, MITRE, CIS) | 9 échecs kube-bench, dont 6 faux positifs ou choix enregistrés ; kubescape 81 % (NSA) | 0 critique, 1 élevé, 4 moyens |
| Images en service | Harbor (Trivy), Trivy CLI | 23 images en service, 21 analysées | **2 critiques** (dont 1 sans correctif), 9 élevées |
| Services SSH | ssh-audit 3.9 | 16 points d'accès | 0 critique, 1 moyen, 1 faible |

**Ce qui devient un écart** : les vulnérabilités critiques en recette connues depuis plus de 30 jours, sans délai de traitement écrit ni dérogation datée → **ECA-3602** ; deux images sans analyse retrouvée → ECA-3602 (couverture). Le reste devient des actions du plan (§ 7), sans écart : les mesures 8.8 et 8.9 fonctionnent, elles ont des défauts ponctuels.

**Points forts** : analyses OpenSCAP hebdomadaires réelles et supervisées (M26-E24), dérogations enregistrées et reliées aux profils adaptés, aucune image hors registre interne en recette ou en production, chiffrement entre nœuds actif, SSH sans mot de passe partout.

## 2. Plan d'audit

| Élément | Choix | Raison |
|---|---|---|
| Hôtes | échantillon **représentatif** de 12 VM : `gw01` (bordure), `adm01` (bastion), `dns01`, `ca01`, `git01`, `reg01`, `mon01`, `idp01`, `ipa01` (Rocky 10), `vault01`, `kms01`, `ceph01` (Rocky 10) + deux nœuds de `k8s-par1` (`k8s-cp01`, `k8s-w01`) | une VM par rôle et par famille de système ; les autres membres d'une grappe ont la même configuration (même rôle Ansible), vérifiée par les analyses hebdomadaires |
| Cluster | `k8s-par1` entier (kube-bench sur un nœud de contrôle et un travailleur, kubescape sur toute l'API) | — |
| Images | toutes les images **en service** dans les espaces applicatifs et de plateforme (par empreinte, `imageID`) | ce qui tourne, pas ce qui est stocké |
| SSH | toutes les VM du socle et les nœuds (16) | coût négligeable |
| Exclus | `pve01`, `pbs01` (hôtes physiques, analysés à part en revue manuelle) ; PAR2 (`hp01`, F5) ; OpenStack (arrêté) | dits ici, à couvrir à l'audit suivant |
| Créneau | 2026-11-16, 20 h - 22 h (hors charge des cabinets), annoncé la veille (fiche CHG standard) | 8.34 : l'audit ne perturbe pas l'exploitation |
| Droits | lecture partout ; Job kube-bench dans `wb-diagnostic` (`hostPID`, montages en lecture), **supprimé** après | aucun objet d'audit ne reste |

## 3. Outils et versions

| Outil | Version | Contenu / référentiel |
|---|---|---|
| OpenSCAP | 1.4.x | ComplianceAsCode 0.1.82 amont (`ssg-debian13-ds.xml`), `ssg-rl10-ds.xml` (Rocky), profils adaptés `…_medisphere` (M26-E10) |
| Lynis | 3.1.7 | profil par défaut |
| kube-bench | 0.16.0 | `--benchmark cis-1.12` (aucun référentiel CIS pour Kubernetes 1.36) |
| kubescape | 4.0.x | cadres `nsa`, `mitre`, `cis-v1.12.0` |
| Trivy | celle du rôle `outils_supply_chain` (base de vulnérabilités du 2026-11-16) ; analyse de Harbor 2.15 | — |
| ssh-audit | 3.9 | politique par défaut + politique MédiSphère (M26-E03) |

## 4. Résultats par domaine

### 4.1 Hôtes (OpenSCAP, Lynis)

| # | Constat | Hôtes | Gravité | Statut |
|---|---|---|---|---|
| H-1 | `auditd` : règles de surveillance des modifications de `/etc/sudoers.d/` absentes sur les VM Rocky | `ipa01`, `ceph01` | élevée | vrai écart (le rôle `durcissement` n'applique pas la variable Rocky) → action A-3 |
| H-2 | AIDE : base non réinitialisée depuis la montée de 2026-10 ; 2 300 différences signalées, toutes des paquets mis à jour | 9 hôtes | élevée (une alerte noyée dans le bruit ne protège plus) | vrai écart → action A-4 |
| H-3 | Partition séparée pour `/var/log/audit` absente | toutes | — | **faux positif enregistré** : exception `EXC-H-…` du registre (VM à disque unique, quotas journald et rotation) |
| H-4 | `kernel.yama.ptrace_scope` à 1 au lieu de 2 (ANSSI) | nœuds K8s | — | **choix enregistré** : Tetragon et le débogage de conteneurs l'exigent ; exception au registre |
| H-5 | Bannière de connexion absente | 3 hôtes | faible | vrai écart, sans risque : action A-6 |
| H-6 | Lynis : `hardening_index` 78 à 84 | — | information | cohérent avec OpenSCAP |
| H-7 | Mots de passe : durée de vie maximale non définie pour les comptes locaux | toutes | — | **non applicable** : comptes locaux sans mot de passe (clés, SSO, sudo par FreeIPA) ; règle désélectionnée dans le profil adapté |

### 4.2 Cluster (kube-bench, kubescape)

| # | Constat | Gravité | Statut |
|---|---|---|---|
| K-1 | kube-bench (`cis-1.12`, numéros à relire dans ton rapport) : `--profiling` non désactivé (API, contrôleur, ordonnanceur) | moyenne | vrai écart (M26 l'avait noté) → action A-5 |
| K-2 | kube-bench 1.1.12 : répertoire de données d'etcd propriété de `root` | — | **choix de kubeadm** (etcd en pod statique sous root) ; dit dans `mesure-k8s-par1.md` (M26-E05) |
| K-3 | kube-bench 1.2.x : `--kubelet-certificate-authority` absent | moyenne | vrai écart (kubeadm ne le pose pas, M26) : action A-5 ; risque réduit par `serverTLSBootstrap` |
| K-4 | kube-bench 4.1.x : contrôles de fichiers du kubelet « WARN » | — | faux positifs : chemins kubeadm différents des chemins attendus par le référentiel ; vérifiés à la main |
| K-5 | kubescape : comptes de service avec jeton monté automatiquement | moyenne | vrai pour 4 charges de plateforme (Backstage, outils) → action A-7 |
| K-6 | kubescape : conteneurs privilégiés ou avec capacités | — | **exceptions enregistrées** (`falco`, `tetragon`, `supervision-noeuds`, ceph-csi) ; vérifiées une à une contre le registre |
| K-7 | kubescape : `ClusterRoleBinding` vers `cluster-admin` pour un compte de service applicatif | élevée | **trouvé et corrigé en S04** (ECA-361x) |

### 4.3 Images en service (Harbor, Trivy)

| # | Constat | Gravité | Statut |
|---|---|---|---|
| I-1 | `mediagenda-api` en **recette** : 1 critique corrigeable, détectée le 2026-10-09 (38 jours), image de prod déjà corrigée | **critique** | **ECA-3602** : aucun délai écrit, rien n'obligeait à reconstruire la recette |
| I-2 | Image de plateforme (portail) : 1 critique **sans correctif publié** depuis 21 jours | critique | ECA-3602 : ni dérogation datée ni mesure compensatoire écrite |
| I-3 | 9 vulnérabilités élevées réparties sur 6 images | élevée | plan : délai à fixer en S09 |
| I-4 | 2 images en service sans analyse retrouvée dans Harbor (tirées avant l'activation de l'analyse automatique d'un cache) | moyenne | ECA-3602 (couverture de la détection) |

### 4.4 SSH (ssh-audit)

| # | Constat | Gravité | Statut |
|---|---|---|---|
| S-1 | Échanges de clés à courbes NIST (`ecdh-sha2-nistp*`) proposés par les VM Rocky 10 (politique de chiffrement système) | faible | **accepté** : signalés par ssh-audit pour leur origine, pas pour une faiblesse connue ; on préfère les retirer quand la politique système le permet (`crypto-policies` sous-politique) → action A-8 |
| S-2 | Clé d'hôte RSA 3072 encore publiée sur 2 VM anciennes | moyenne | vrai écart (Ed25519 seul attendu) → action A-8 |

## 5. Faux positifs et choix enregistrés : règle appliquée

Un « échec » d'outil n'est **écarté** que s'il entre dans l'un de ces cas, écrit à côté : (1) exception déjà au registre `docs/securite/durcissement/exceptions.md`, avec échéance ; (2) choix d'architecture documenté (ADR ou mesure du M26) ; (3) contrôle non applicable, avec la raison vérifiable. Sinon, c'est un constat.

## 6. Résultats bruts et intégrité

Fichiers dans [`technique/`](technique/) (versionnés ; les rapports complets OpenSCAP restent dans `s3-01`, compartiment `conformite`) :

| Fichier | Outil | SHA-256 |
|---|---|---|
| `openscap-scores.json` | scores et comptes `fail` des 12 hôtes (extraits des ARF) | `<64 caractères hexadécimaux>` |
| `kube-bench-k8s-cp01.json`, `kube-bench-k8s-w01.json` | kube-bench | `<…>` |
| `kubescape-resume.json` | kubescape (cadres, scores, contrôles en échec, nombre de ressources ; aucun nom de Secret) | `<…>` |
| `images-en-service.json` | Harbor + Kubernetes (empreinte, espaces, résumé d'analyse) | `<…>` |
| `ssh-audit.txt` | ssh-audit, 16 points d'accès | `<…>` |
| `lynis-index.json` | Lynis (`hardening_index` par hôte) | `<…>` |

Empreintes calculées par `sha256sum technique/*` avant la MR. Pour dater l'audit de façon inaltérable, les mêmes fichiers peuvent être déposés par `ms-preuves` avec un catalogue d'audit (`--catalogue`) dont chaque collecteur relit un de ces fichiers (amélioration notée au plan).

## 7. Actions (hors écarts)

| Action | Objet | Responsable | Échéance |
|---|---|---|---|
| A-3 | règles `auditd` des VM Rocky (variable du rôle `durcissement`) | Plateforme | 2026-12-04 |
| A-4 | réinitialisation d'AIDE après chaque montée (tâche du playbook de correctifs) | Plateforme | 2026-12-04 |
| A-5 | `--profiling=false` et `--kubelet-certificate-authority` (ClusterConfiguration, un nœud à la fois) | Karim Benali | 2026-12-11 (fenêtre CHG) |
| A-6 | bannière de connexion | Plateforme | 2026-12-18 |
| A-7 | `automountServiceAccountToken: false` sur 4 charges | Plateforme | 2026-12-04 |
| A-8 | SSH : Ed25519 seul, retrait des courbes NIST sur Rocky | Plateforme | 2026-12-18 |

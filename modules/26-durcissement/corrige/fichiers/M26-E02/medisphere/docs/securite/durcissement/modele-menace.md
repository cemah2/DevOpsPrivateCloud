# Modèle de menace de la plateforme MédiSphère

> SEC-2702 — rédigé le <AAAA-MM-JJ> par `<MOI>`, relu par Sophie Laurent (RSSI). Revue : à chaque nouveau composant exposé, et au moins une fois par an. Document interne, diffusion restreinte (dépôt `plateforme/medisphere`).

## 1. Périmètre et hypothèses

**Dans le périmètre** : le site PAR1 (socle de VMs, `ceph-par1`, `k8s-par1`), la chaîne de livraison (GitLab, runners, Harbor, Argo CD), l'identité (FreeIPA, Keycloak), le coffre (OpenBao), les sauvegardes (PBS sur PAR2) et les applications MédiAgenda et MédiDoc.

**Hors périmètre** : sécurité physique des salles, postes de travail des personnes (traités par la DSI), réseau domestique qui héberge le lab, fournisseurs SaaS.

**Hypothèses** : l'hyperviseur `pve01` et PBS sont sains ; la clé de la racine hors ligne (M06) n'a pas fui ; les parts de descellement d'OpenBao sont réparties comme prévu (M25) ; les images de base viennent de nos caches Harbor et sont analysées (M13).

## 2. Actifs

| Actif | Où | Qui y accède | Criticité |
|---|---|---|---|
| Données de santé (rendez-vous, documents) | bases CNPG de `mediagenda-*`, compartiments S3 de MédiDoc (Ceph RGW), sauvegardes Velero et PBS | applications, équipes via leurs droits, sauvegardes | **critique** (HDS) |
| Racine de la PKI, CA intermédiaires | `~/pki-racine` hors ligne ; `ca01` (step-ca) ; CA de FreeIPA ; « Services CA » d'OpenBao | officiants de cérémonie ; services d'émission | critique |
| Coffre OpenBao et ses parts | `vault01-03`, `kms01`, parts chiffrées `age` | `plateforme-admins`, ESO, CI par JWT | critique |
| Clé de signature Cosign | `transit/cosign-medisphere` (M25) | job de signature du runner protégé | critique (intégrité de la livraison) |
| Accès d'administration du cluster | `admin.conf` (bris de glace), OIDC `plateforme-admins` | équipe Plateforme | critique |
| Identités | `ipa01` (annuaire), `idp01` (Keycloak), comptes de bris de glace | toutes les personnes | critique |
| Chaîne de livraison | `git01`, `runner01/02`, runners du cluster, `reg01` (Harbor), Argo CD | développeurs, CI, Argo CD | élevée |
| Journaux d'audit | Loki locataire `audit`, `/var/log/openbao/audit.log`, journal d'audit de l'API | équipe Sécurité, Plateforme | élevée (preuve) |

## 3. Acteurs

| Acteur | Moyens | Objectif probable |
|---|---|---|
| Opportuniste externe | balayages, failles publiques connues, mots de passe réutilisés | ressources (minage), rebond |
| Groupe ciblé (rançongiciel « santé ») | hameçonnage, accès initial acheté, outillage d'élévation | chiffrer données et sauvegardes, exfiltrer, extorquer |
| Compte de développeur compromis | jeton GitLab, session SSO, poste infecté | pousser du code, lire des secrets de CI, déployer |
| Initié malveillant ou négligent | droits légitimes | consulter des dossiers, désactiver un contrôle « pour aller vite » |
| Dépendance compromise | image, chart, paquet, action de CI piégés | exécution dans nos pods ou nos runners |
| Erreur d'administration | droits élevés, fatigue | panne, exposition involontaire (politique trop large, port ouvert) |

## 4. Frontières de confiance

```
 Internet ──(NAT, VPN wg1)── gw01/gw02 ─────────────────────────────── [F1 bordure]
                               │ DMZ : lb01/lb02 (sso, apps) ────────── [F2 DMZ → INFRA, VLAN 40]
                               │ MGMT : adm01, pve01 ────────────────── [F3 administration → tout]
                               │ INFRA : git01, reg01, ipa01, idp01, vault01-03, s3-01, mon01…
                               │ VLAN 40 : k8s-par1
                               │     API (6443/8443) ───────────────── [F4 personnes et CI → API]
                               │     espaces de plateforme │ espaces d'équipes ── [F5 entre espaces]
                               │     conteneur ↔ nœud (noyau partagé) ──────────── [F6 conteneur → hôte]
                               └ PAR2 : pbs01 (tunnel wg0) ─────────── [F7 sauvegardes]
```

| Frontière | Ce qui la traverse | Contrôles existants | Manques |
|---|---|---|---|
| F1 bordure | VPN d'administration, NAT sortant, publication | nftables par rôle `pare_feu` (M00, M07), VPN WireGuard | détection d'intrusion sur la bordure ; mesure du durcissement de `gw01` |
| F2 DMZ → INFRA | HAProxy vers services | matrice des flux, TLS re-chiffré | — |
| F3 MGMT → tout | SSH, API Proxmox, `kubectl` | certificats SSH (M06), SSO + OTP (M24) | durcissement SSH homogène, journal des commandes (auditd) |
| F4 → API Kubernetes | personnes, CI, Argo CD | OIDC, RBAC, audit de l'API (M14, M22) | admission riche (signatures, limites), alertes sur `exec` en prod |
| F5 entre espaces | trafic réseau, objets partagés | NetworkPolicy par défaut des équipes (M15), RBAC | génération automatique de la politique par défaut (Kyverno) |
| F6 conteneur → nœud | appels système | PSA partielle (M14), images non-root (M17) | PSA `restricted` partout, seccomp par défaut, détection à l'exécution |
| F7 sauvegardes | PBS, Velero | chiffrement, PAR2 isolé (M00, M16) | — (hors module) |

## 5. STRIDE par composant

| Composant | Menaces (STRIDE) |
|---|---|
| `gw01`/`gw02` | **S** usurpation VRRP sur un VLAN ; **T** modification des règles nftables ; **D** saturation de la bordure ; **E** compromission de la VM = contrôle de tout le trafic |
| `git01` + runners | **S** jeton de CI volé ; **T** pipeline modifié qui signe une image piégée ; **I** variables de CI lues par un job non protégé ; **E** runner `shell` utilisé pour rebondir sur INFRA |
| Harbor (`reg01`) | **T** image remplacée sous la même étiquette ; **I** projets privés lisibles par un robot trop large ; **R** pas de trace de qui a poussé |
| API de `k8s-par1` | **S** jeton de compte de service volé ; **T** objet modifié hors GitOps ; **R** `exec` en production sans trace exploitable ; **E** création d'un pod privilégié |
| Nœud travailleur | **T** binaire déposé sur l'hôte ; **I** lecture des jetons de tous les pods du nœud ; **E** évasion de conteneur par `hostPath` ou capacité |
| Pod de MédiAgenda | **I** lecture du jeton de compte de service, des variables d'environnement ; **T** écriture dans le système de fichiers ; **D** consommation sans limite ; **E** exécution de code par une faille applicative |
| OpenBao | **S** jeton d'une identité ESO détourné ; **I** lecture de secrets hors périmètre par une politique trop large ; **R** audit désactivé ; **D** scellement |

## 6. Les dix menaces prioritaires

Vraisemblance (V) et impact (I) de 1 à 3 ; risque = V × I.

| # | Menace | Composant | V | I | R | Contrôles existants | Manques | Traité par |
|---|---|---|---|---|---|---|---|---|
| 1 | Exécution de code dans un pod applicatif puis évasion vers le nœud | pod, nœud | 2 | 3 | 6 | images non-root (M17), PSA sur une partie des espaces (M14) | PSA `restricted` partout, seccomp par défaut, détection | E06, E08, E16, E21, E29 |
| 2 | Image non signée ou piégée déployée en production | Harbor, API | 2 | 3 | 6 | signature Cosign dans la CI (M13), VAP sur le registre (M14) | vérification de signature à l'admission | E15 |
| 3 | Jeton de compte de service volé utilisé contre l'API | pod, API | 2 | 3 | 6 | RBAC minimal (M14), audit de l'API (M22) | `automountServiceAccountToken: false`, détection de lecture du jeton | E08, E19, E21 |
| 4 | Rançongiciel sur les VMs du socle par un accès SSH | socle | 2 | 3 | 6 | SSO + OTP, certificats SSH (M24, M06), sauvegardes PBS | durcissement SSH/PAM/sudo homogène, auditd, mesure continue | E03, E10-E14, E24 |
| 5 | Shell interactif ouvert en production sans que personne ne le sache | API, pod | 3 | 2 | 6 | audit de l'API (M22) | alerte en minutes (Falco, règle d'audit) | E08, E19, E28 |
| 6 | Pod privilégié ou `hostPath` créé par erreur dans un espace d'équipe | API | 2 | 3 | 6 | PSA partielle | PSA `restricted`, exceptions écrites, admission native | E06, E17, E18 |
| 7 | Trafic entre nœuds intercepté (données de santé en clair dans le VLAN 40) | réseau | 1 | 3 | 3 | VLAN isolé, TLS applicatif partiel (M25) | chiffrement WireGuard de Cilium | E26 |
| 8 | Port d'un nœud exposé au-delà du nécessaire (kubelet, etcd) | nœud | 2 | 2 | 4 | pare-feu de bordure | pare-feu d'hôte de Cilium, certificats de kubelet vérifiés | E25, E27 |
| 9 | Dérive silencieuse du durcissement (un réglage défait à la main) | socle | 3 | 2 | 6 | Ansible idempotent | analyse OpenSCAP hebdomadaire et alerte, AIDE | E12, E24 |
| 10 | Pas de procédure le jour d'une compromission (preuves détruites, isolement tardif) | tout | 2 | 3 | 6 | runbooks d'astreinte (M21-M23) | quarantaine préparée, collecte de preuves, exercice | E33, E42 |

## 7. Ce que ce modèle ne dit pas

Il ne chiffre pas un risque financier, ne remplace pas l'analyse de risques ISO 27005 de la RSSI, et suppose que les correctifs de sécurité sont appliqués (E30 le vérifie). Les menaces sur la PKI et les sauvegardes sont acceptées comme couvertes par les modules 06, 16 et 25.

# Politique de certification de la PKI interne MédiSphère

| | |
|---|---|
| Version | 1.0 — AAAA-MM-JJ |
| Propriétaire | Responsable de la PKI : <NOM> (équipe Plateforme) |
| Approbation | Sophie Laurent (RSSI), Claire Morel (responsable infrastructure) |
| Revue | annuelle, et à chaque changement d'autorité, d'algorithme ou de durée |
| Emplacement | `plateforme/medisphere` : `docs/socle/pki/politique-certification.md` |
| Inspiration | RFC 3647 (plan simplifié pour une PKI **interne**) |

## 1. Objet et périmètre

Ce document fixe les engagements de la PKI interne de MédiSphère : qui peut obtenir quel certificat, comment, pour combien de temps, comment il est retiré, et comment les clés des autorités sont protégées. Les procédures détaillées sont dans les runbooks cités.

**Dans le périmètre** : certificats TLS serveur des services internes (`*.par1.medisphere.internal`, `*.par2.medisphere.internal`), certificats TLS client entre composants internes (ex. haute disponibilité de Kea), certificats SSH d'hôte et d'utilisateur.

**Hors périmètre** : certificats exposés sur Internet (autorité publique), signature de code et d'images (module 13), messagerie (S/MIME), identités des personnes pour l'authentification web (fédération d'identité, module 24).

## 2. Rôles

| Rôle | Qui | Responsabilités |
|---|---|---|
| Responsable de la PKI | un ingénieur Plateforme nommé | tient ce document, la configuration de `ca01`, les revues |
| Opérateurs | équipe Plateforme | émissions manuelles exceptionnelles, révocations (RB-063), restaurations (RB-061) |
| Porteurs de la racine | **deux** personnes au moins, dont une hors de l'équipe Plateforme (RSSI) | présents ensemble à toute cérémonie de la racine ; chacun connaît une moitié du secret de l'archive |
| Auditeur | RSSI ou auditeur externe | revue annuelle, contrôle des journaux |

Séparation des tâches : personne ne peut seul utiliser la clé racine ; le pipeline d'automatisation n'a aucun accès aux provisioners manuels (`admin`).

## 3. Hiérarchie et protection des clés

| Autorité | Nom distinctif | Algorithme | Durée | Clé |
|---|---|---|---|---|
| Racine | CN=MédiSphère Root CA | ECDSA P-256 | <durée réelle de M06-E02> | **hors ligne** : archive chiffrée (`~/pki-racine/`, 700) sur `adm01` le temps du lab, deux copies hors ligne en lieux distincts ; jamais sur `ca01` (contrôlé par la sauvegarde, RB-061) |
| Intermédiaire | CN=MédiSphère Intermediate CA | ECDSA P-256 | <durée réelle> | en ligne sur `ca01`, **chiffrée** ; mot de passe dans Vault (`critique`), pas dans les sauvegardes |
| CA SSH (hôtes, utilisateurs) | clés de step-ca | ECDSA | sans expiration (clés brutes OpenSSH) | en ligne sur `ca01`, chiffrées |

Contraintes : longueur de chemin de l'intermédiaire = 0 (il ne peut pas créer d'autre autorité). Contraintes de noms : <appliquées ou non, avec le ticket> — à défaut, la politique de noms de step-ca limite l'ACME à `*.medisphere.internal` (ticket SEC-7xx).

**Limite assumée** : la clé de l'intermédiaire est sur disque (chiffrée) et son mot de passe est lisible par le service. Un attaquant administrateur de `ca01` peut émettre. Compensation : `ca01` est filtré (M06-E30), surveillé, sauvegardé ; module HSM/KMS à étudier (module 25, OpenBao).

## 4. Enregistrement et émission

| Certificat | Mécanisme (provisioner) | Preuve demandée | Qui peut demander |
|---|---|---|---|
| TLS serveur d'un hôte du socle | ACME (`acme`), défi HTTP-01 | contrôle du nom : `ca01` résout le nom par le DNS interne (zone signée, M06-E26) et joint l'hôte sur le port 80 | tout hôte du lab joignable par `ca01` ; la politique de noms limite les noms |
| TLS client/serveur avec adresse IP (Kea HA) | ACME, identifiant IP | contrôle de l'adresse (HTTP-01 sur l'IP) | `dns01`, `dns02` |
| TLS « à la main » (essais, outils) | JWK `admin` | mot de passe du provisioner (gestionnaire de l'équipe, accès tracé) | opérateurs |
| SSH d'hôte | provisioner SSH de M06-E19 (puis `sshpop` pour le renouvellement) | <jeton d'amorçage déposé par Ansible / identité de la VM> | rôle `ssh_ca_hote` |
| SSH d'utilisateur | provisioner SSH de M06-E20 | <authentification de l'utilisateur> ; principaux `admin`, `astreinte` | membres de l'équipe Plateforme |

Les certificats TLS portent les usages `serverAuth` et `clientAuth` (gabarit par défaut de step-ca).

## 5. Durées et renouvellement

| Certificat | Défaut | Maximum | Renouvellement |
|---|---|---|---|
| TLS ACME | 30 jours | 30 jours | automatique, `cert-renewer@<service>`, à **15 jours** de l'expiration |
| TLS `admin` | 24 h | 7 jours | aucun (usage ponctuel) |
| SSH hôte | 30 jours | 30 jours | automatique (`sshpop`) |
| SSH utilisateur | 16 h | 16 h | nouvelle connexion à la CA chaque jour |

Ces valeurs sont **appliquées** par `ca.json` (rôle `step_ca`, `group_vars/role_pki/step_ca.yml`, M06-E27). Un renouvellement après expiration est refusé (`allowRenewalAfterExpiry: false`) : un certificat expiré se réémet. La supervision (M06-E29) alerte quand un certificat en service expire dans moins de **10 jours**, soit 5 jours après l'échec du renouvellement.

## 6. Révocation

- Motifs : compromission (ou suspicion) de la clé, retrait de l'hôte ou du service, informations erronées, départ d'un collaborateur (SSH).
- Décision : RSSI ou astreinte pour une compromission (immédiat), responsable du service sinon (dans la journée).
- Mécanismes : révocation **passive** (renouvellement refusé) pour tout certificat ; **CRL** publiée à `http://ca01.par1.medisphere.internal/1.0/crl`, régénérée à chaque révocation, validité 24 h ; liste `RevokedKeys` de sshd pour SSH.
- **Limites, écrites** : aucun OCSP ; la CRL n'est consultée d'office par aucun client du socle à ce jour ; la protection effective repose sur les **durées courtes** et le remplacement immédiat. Procédure : RB-063.

## 7. Continuité

- Sauvegarde quotidienne chiffrée de `ca01` vers PAR2 (RB-061), sans clé racine ni mot de passe de l'intermédiaire ; restauration testée deux fois par an.
- Cérémonies (création de la racine, renouvellement de l'intermédiaire) : deux porteurs, machine hors réseau, procès-verbal signé et archivé ; renouvellement de l'intermédiaire au plus tard un an avant son expiration (rappels dans RB-063 §7).
- Compromission de l'intermédiaire : RB-063 §6 (nouvel intermédiaire signé par la racine, réémission complète). Perte de la racine : nouvelle PKI complète, redistribution de l'ancre sur tous les hôtes (rôle `ca_lab`), période de recouvrement comme en M06-E03.

## 8. Journalisation et contrôle

- Journaux de step-ca (émissions, renouvellements, révocations, refus) conservés <durée> (journal persistant de `ca01`, puis centralisation au module 22).
- Revue trimestrielle : liste des provisioners et de leurs durées (`step ca provisioner list`), certificats révoqués de la période, accès au mot de passe `admin`.
- Indicateurs : nombre de certificats en service, échecs de renouvellement, délai entre alerte et correction, âge de la dernière restauration testée.

## 9. Gestion du document

| Version | Date | Auteur | Changement |
|---|---|---|---|
| 1.0 | AAAA-MM-JJ | <apprenant> | Première version (M06-E33), relue par la RSSI |

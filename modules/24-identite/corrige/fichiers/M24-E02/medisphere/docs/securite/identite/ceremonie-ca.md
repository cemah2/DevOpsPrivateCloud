# Cérémonie de signature d'une autorité subordonnée par la racine MédiSphère

> Procédure et procès-verbaux. Créé en M24-E02 (CA de FreeIPA, ticket PLAT-2502) ; réutilisé au
> M25 pour « MédiSphère Services CA » (OpenBao). Racine : M06-E02 (`docs/socle/pki/ceremonie-racine.md`).
> Propriétaire : équipe Plateforme. Relecture : RSSI (Sophie Laurent).

## Pourquoi une cérémonie

La clé de « MédiSphère Root CA » permet de **fabriquer une autorité** à qui tout le lab fait confiance. Elle ne vit que dans `~/pki-racine` d'`adm01` (dossier 700, clé chiffrée par une phrase de passe qu'on saisit au clavier) et dans des archives chiffrées hors ligne. On ne la sort que pour signer une autorité **subordonnée**, en suivant cette procédure, et chaque signature laisse un procès-verbal ci-dessous.

Une autorité subordonnée signée par la racine est valable partout sans rien distribuer de nouveau : les VMs, les navigateurs du lab et les outils font déjà confiance à la racine (M06-E03).

## Rôles

| Rôle | Au lab | En production |
|---|---|---|
| Officiant (tape les commandes) | toi | un ingénieur Plateforme |
| Témoin (relit le sujet, l'empreinte, la durée) | toi, en relisant à voix haute | une seconde personne (RSSI ou Karim Benali) |
| Détenteur de la phrase de passe de la racine | toi (gestionnaire de mots de passe) | deux détenteurs, phrase scindée |

## Procédure

1. **Avant** : ticket ouvert ; la CSR est produite **sur la machine qui gardera la clé** (jamais de clé générée sur `adm01` puis copiée) ; la CSR est versionnée dans `pki/` de `plateforme/ansible` (pièce publique).
2. **Relire la CSR** sur `adm01`, hors de toute session partagée :
   ```
   admin@adm01:~/src/ansible/pki$ step certificate inspect <FICHIER>.csr --short
   admin@adm01:~/src/ansible/pki$ openssl req -in <FICHIER>.csr -noout -subject -pubkey | openssl pkey -pubin -noout -text | head -n 1
   ```
   Le témoin confirme : sujet attendu, algorithme et taille de clé, aucune extension inattendue.
3. **Signer** avec le script de la racine (M06-E02) : profil `intermediate-ca`, longueur de chemin 0, cinq ans :
   ```
   admin@adm01:~/src/ansible/pki$ ceremonie-pki.sh signer <FICHIER>.csr
   ```
   Le script redemande confirmation du sujet, puis la phrase de passe de la racine (au clavier, jamais en argument ni dans un fichier). Il vérifie la chaîne et écrit `<FICHIER>.crt` et une ligne dans `~/pki-racine/journal-ceremonies.log`.
4. **Contrôler** le résultat :
   ```
   admin@adm01:~/src/ansible/pki$ step certificate inspect <FICHIER>.crt --short
   admin@adm01:~/src/ansible/pki$ openssl x509 -in <FICHIER>.crt -noout -ext basicConstraints,keyUsage -enddate -fingerprint -sha256
   admin@adm01:~/src/ansible/pki$ openssl verify -CAfile medisphere-root-ca.crt <FICHIER>.crt
   ```
5. **Archiver** : `ceremonie-pki.sh archiver` (le journal des cérémonies a changé), copie de l'archive sur le support hors ligne.
6. **Versionner** le certificat signé (MR, relu par le témoin) et remplir le procès-verbal ci-dessous.
7. **Planifier le renouvellement** : un rappel daté au calendrier de l'équipe **un an avant** l'échéance.

## Procès-verbaux

### 2026-10 — CA de FreeIPA (`ipa01`), M24-E02

| Élément | Valeur |
|---|---|
| Date, lieu | `<AAAA-MM-JJ>`, `adm01` (session locale) |
| Officiant / témoin | `<MOI>` / `<MOI>` (relecture à voix haute) — en production : deux personnes |
| CSR | `pki/ipa01-ipa.csr`, produite par `ipa-server-install --external-ca` sur `ipa01` (clé RSA 3072 générée et gardée par Dogtag) |
| Sujet | `CN=Certificate Authority,O=PAR1.MEDISPHERE.INTERNAL` |
| Profil | `intermediate-ca`, `CA:TRUE, pathlen:0`, `keyCertSign, cRLSign` |
| Durée | 5 ans (`43800h`) : valide jusqu'au `<DATE-FIN>` |
| Empreinte SHA-256 | `<EMPREINTE-SHA256>` |
| Numéro de série | `<NUMÉRO-DE-SÉRIE>` (aussi dans `~/pki-racine/journal-ceremonies.log`) |
| Certificat | `pki/ipa01-ipa.crt` (MR `!<NUMÉRO>`) ; installé par `ipa-server-install --external-cert-file` (phase 2) |
| Archive | `pki-racine-<AAAAMMJJ-HHMMSS>.tar.gpg`, copiée sur `<SUPPORT>` |
| Renouvellement | rappel posé au `<DATE-FIN moins un an>` ; procédure : `ipa-cacert-manage renew --external-ca` sur `ipa01`, nouvelle cérémonie avec la CSR produite, puis `ipa-cacert-manage renew --external-cert-file=…` et `ipa-certupdate` sur les clients |

Conséquence retenue : `pathlen:0` interdit à la CA de FreeIPA de créer des sous-autorités (*lightweight sub-CAs* de FreeIPA). Le lab n'en a pas besoin ; si un jour c'était le cas, il faudrait une nouvelle cérémonie avec un autre profil, décidée par ADR.

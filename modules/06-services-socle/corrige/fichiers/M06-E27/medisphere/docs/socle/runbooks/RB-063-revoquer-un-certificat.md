# RB-063 — Révoquer un certificat (TLS ou SSH) de la PKI interne

| | |
|---|---|
| PKI | step-ca sur `ca01` (10.10.20.11) : intermédiaire « MédiSphère Intermediate CA », racine hors ligne |
| Rédigé | M06-E27 (SEC-753) — exercice réalisé le AAAA-MM-JJ sur `essai-revocation.par1.medisphere.internal` |
| Politique | `docs/socle/pki/politique-certification.md` (M06-E33), §6 Révocation |
| Liens | RB-061 (restaurer `ca01`), RB-062 §5 (certificats de Kea), M06-E29 (supervision) |

## Ce que la révocation fait, et ne fait pas

| Mécanisme | Effet | Limite |
|---|---|---|
| **Passive** (par défaut) : le numéro de série est inscrit comme révoqué dans la base de `ca01` | `ca01` refuse tout **renouvellement** de ce certificat | Le certificat reste **valide** pour tout client jusqu'à son expiration (30 jours au plus pour un serveur, 16 h pour un utilisateur SSH) |
| **CRL** : `http://ca01.par1.medisphere.internal/1.0/crl`, régénérée à chaque révocation, valable 24 h | Un client qui **consulte** la CRL refuse le certificat | Aucun client du socle ne la consulte d'office aujourd'hui (navigateurs, `curl`, GitLab, NetBox : pas de point de distribution dans nos certificats). Utile pour les vérifications explicites (`openssl verify -crl_check`), les audits, et les clients qu'on configurera pour la lire |
| **Durée courte** | Borne la fenêtre d'exposition | La seule protection universelle : c'est pour cela que la politique fixe 30 jours / 16 h |
| **SSH** : clés révoquées côté serveur (`RevokedKeys` de sshd) | sshd refuse immédiatement le certificat ou la clé | Fichier à distribuer sur chaque hôte (Ansible) ; step-ca, lui, ne fait que refuser le renouvellement |

**Conséquence** : révoquer ne suffit jamais. On révoque **et** on remplace **et**, si la clé est compromise, on retire la confiance là où elle est accordée (service arrêté, `RevokedKeys`, rotation des secrets que le certificat protégeait).

## 1. Décider (5 minutes)

| Motif (code RFC 5280) | Qui décide | Délai |
|---|---|---|
| Clé compromise ou suspectée (1, `keyCompromise`) | RSSI (Sophie Laurent) ou l'astreinte, qui l'informe | immédiat |
| Hôte retiré (5, `cessationOfOperation`) | responsable du service | dans la journée |
| Nom ou usage erroné (4, `superseded`) | responsable du service | dans la semaine |
| Compromission de l'intermédiaire | RSSI + responsable infrastructure | voir §6, procédure de crise |

Ouvre un ticket (INC pour une compromission, CHG sinon) et note : sujet, numéro de série, motif.

## 2. Identifier le certificat

```
admin@adm01:~$ echo | openssl s_client -connect <HÔTE>:<PORT> -servername <NOM> 2>/dev/null | openssl x509 -noout -serial -subject -enddate
admin@adm01:~$ step certificate inspect <FICHIER.crt> --short           # numéro de série en décimal
```

`openssl` affiche le numéro de série en hexadécimal, `step` en décimal : `step ca revoke` attend la forme décimale (conversion : `python3 -c 'print(int("<HEX>", 16))'`).

## 3. Révoquer (TLS)

Avec le certificat **et** sa clé (le porteur révoque lui-même, aucun mot de passe de provisioner) :

```
admin@<HÔTE>:~$ sudo step ca revoke --cert <FICHIER.crt> --key <FICHIER.key> --reasonCode 4 --reason "remplacé"
```

Par numéro de série (clé perdue, ou révocation par l'équipe PKI) : il faut un jeton d'un provisioner, donc le mot de passe d'`admin` (gestionnaire de mots de passe de l'équipe, accès tracé) :

```
admin@adm01:~$ step ca revoke <NUMÉRO-DÉCIMAL> --reasonCode 1 --reason "clé compromise, INC-33xx"
```

Vérifier :

```
admin@adm01:~$ step crl inspect --ca /usr/local/share/ca-certificates/medisphere-root-ca.crt http://ca01.par1.medisphere.internal/1.0/crl | grep -A2 '<NUMÉRO-HEX-OU-DÉCIMAL>'
admin@adm01:~$ curl -s http://ca01.par1.medisphere.internal/1.0/crl -o /tmp/crl.der && openssl crl -inform DER -in /tmp/crl.der -out /tmp/crl.pem
admin@adm01:~$ cat <INTERMÉDIAIRE.crt> /usr/local/share/ca-certificates/medisphere-root-ca.crt > /tmp/chaine.pem
admin@adm01:~$ openssl verify -crl_check -CAfile /tmp/chaine.pem -CRLfile /tmp/crl.pem <FICHIER.crt>   # « certificate revoked »
```

## 4. Remplacer

- Certificat ACME d'un service : supprimer le certificat et la clé, relancer le pipeline Ansible du service (`--limit <HÔTE> --tags <rôle>`) : le rôle refait une émission ACME (nouvelle clé). Vérifier que le service présente le nouveau certificat (empreinte avant/après).
- Kea : RB-062 §5.
- Ne **jamais** renouveler un certificat dont la clé est compromise : un renouvellement garde la même clé.

## 5. Révoquer (SSH)

- Certificat d'utilisateur (départ, poste perdu) : `step ssh revoke <NUMÉRO>` (empêche le renouvellement), **et** ajouter la clé publique ou le numéro de série à la liste `RevokedKeys` des hôtes (variable du rôle `ssh_ca_hote`, M06-E19 ; format KRL produit par `ssh-keygen -k`), pipeline. Le certificat de 16 h expire de toute façon dans la journée.
- Certificat d'hôte (hôte compromis) : `step ssh revoke`, retrait de l'hôte du socle, nouvelle clé d'hôte signée sur l'hôte reconstruit.

## 6. Compromission de l'intermédiaire (crise)

1. Arrêter `step-ca` sur `ca01` (plus aucune émission).
2. Cérémonie avec la racine hors ligne (`~/pki-racine/`, deux porteurs) : nouvel intermédiaire, nouvelle clé.
3. Révoquer l'ancien intermédiaire dans une CRL signée par la **racine** (étape de la cérémonie), publiée à côté de la CRL de `ca01`.
4. Réémettre tous les certificats du socle (pipeline complet), et les certificats SSH (la CA SSH a ses propres clés : vérifier si elles étaient sur le même disque).
5. Post-mortem. La racine n'étant pas touchée, aucun client n'a à changer d'ancre de confiance : c'est **l'intérêt** de la racine hors ligne.

## 7. Dates de fin de vie de la CA (à jour)

| Élément | Expire le | Plus de certificat de 30 jours valide jusqu'au bout après le | Rappels posés |
|---|---|---|---|
| Intermédiaire | <AAAA-MM-JJ> | <date d'expiration − 30 jours> | <expiration − 1 an>, <expiration − 3 mois> |
| Racine | <AAAA-MM-JJ> | — | <expiration − 2 ans> |

step-ca n'émet pas de certificat qui dépasse la validité de son intermédiaire : dans les 30 derniers jours, les certificats émis sont **raccourcis** (ou refusés selon la version, ⚠️ à vérifier), et les renouvellements se rapprochent. La cérémonie de renouvellement de l'intermédiaire a lieu **au plus tard** au premier rappel.

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création (M06-E27), exercice sur le certificat d'essai |

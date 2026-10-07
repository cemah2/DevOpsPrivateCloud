# Changements de medisphere.socle

## 1.1.0 — M06-E03

- Rôle `ca_lab` : variable `ca_lab_retirer` (autorités à retirer du magasin système, avec
  reconstruction `--fresh`), contrôle du magasin consolidé après reconstruction
  (`ca_lab_verifier`), refus d'une autorité à la fois installée et retirée.
- Rôle `ca_lab` : autorité par défaut = racine step-ca « MédiSphère Root CA »
  (`pki/medisphere-root-ca.crt` du projet) au lieu de la CA provisoire. Changement
  compatible : les inventaires qui fixaient `ca_lab_certificats` ne voient aucune différence.

## 1.0.0 — M04-E18

- Filtre `regle_nft` : un flux de la matrice des flux devient une règle nftables (remplace la macro
  Jinja du rôle `pare_feu`), avec refus des champs inconnus et des combinaisons incohérentes.
- Rôle `ca_lab` : autorités de certification du lab dans le magasin système.

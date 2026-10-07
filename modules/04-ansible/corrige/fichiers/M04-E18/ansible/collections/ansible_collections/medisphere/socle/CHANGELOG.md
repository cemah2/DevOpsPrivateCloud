# Changements de medisphere.socle

## 1.0.0 — M04-E18

- Filtre `regle_nft` : un flux de la matrice des flux devient une règle nftables (remplace la macro
  Jinja du rôle `pare_feu`), avec refus des champs inconnus et des combinaisons incohérentes.
- Rôle `ca_lab` : autorités de certification du lab dans le magasin système.

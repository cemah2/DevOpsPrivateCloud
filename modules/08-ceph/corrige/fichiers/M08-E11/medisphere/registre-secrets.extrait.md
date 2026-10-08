<!-- registre-secrets.extrait.md — M08-E11 : lignes à ajouter au registre des secrets
     (docs/socle/registre-secrets.md de plateforme/medisphere). -->
| Secret | Usage | Emplacement | Copie de secours | Propriétaire | Rotation |
|---|---|---|---|---|---|
| Clé du provisioner step-ca `ceph-ingress` (JWK, chiffrée) | Émission du certificat de `rgw.par1.medisphere.internal` | `ca.json` de `ca01` (chiffrée), `vault_step_ca_ceph_ingress_cle_chiffree` | Vault `critique` | Équipe Plateforme | Annuelle, ou immédiate si le mot de passe fuit |
| Mot de passe du provisioner `ceph-ingress` | Déchiffrer la clé ci-dessus (réémission après expiration) | `adm01:~/.config/workbook/step-ceph-ingress.pass` (600) | Vault `critique` | Équipe Plateforme | Avec la clé |
| Clé privée TLS de `rgw.par1.medisphere.internal` | haproxy du service `ingress.rgw.par1` | `adm01:~/.config/workbook/ceph-ingress/cle.pem` (600) ; base de configuration des moniteurs (cephadm) | Aucune (réémise au besoin) | Équipe Plateforme | Tous les 30 jours (renouvellement) |
| Clé SSH `id_ed25519_ceph_auto` | Unité `ceph-cert-ingress` : `adm01` → `ceph01` (sudo cephadm) | `adm01:~admin/.ssh/` (600) ; autorisée sur `ceph01` avec `from="10.10.10.10"` | Aucune (recréée au besoin) | Équipe Plateforme | Annuelle |

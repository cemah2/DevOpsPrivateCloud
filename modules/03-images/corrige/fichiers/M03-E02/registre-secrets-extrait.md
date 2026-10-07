<!-- EXTRAIT (M03-E02) — ligne à ajouter au tableau des jetons de
     docs/socle/registre-secrets.md dans plateforme/medisphere (par MR). Aucune valeur. -->

| Identifiant | Type | Propriétaire | Portée / rôle | Stockage | Expiration | Rotation |
|---|---|---|---|---|---|---|
| `wb-packer@pve!packer` | jeton d'API Proxmox (privsep) | équipe Plateforme (`<MOI>`) | rôle `WBPacker` sur `/pool/lab`, `PVEDatastoreUser` sur `/storage/local-nvme`, `WBLectureISO` sur `/storage/hdd-bulk`, `PVESDNUser` sur `/sdn/zones/lab/vsandbox` | `adm01:~/.config/workbook/pve-packer.env` (600) ; variable CI `PKR_VAR_proxmox_token` protégée et masquée de `plateforme/images` (M03-E15) | ≤ 1 an (`--expire`) | créer `wb-packer@pve!packer2` avec les mêmes ACL, mettre à jour le fichier et la variable CI, construire une image, supprimer l'ancien jeton |

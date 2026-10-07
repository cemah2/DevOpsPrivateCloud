<!-- EXTRAIT (M05-E03) — ligne à ajouter au tableau des jetons de
     docs/socle/registre-secrets.md dans plateforme/medisphere (par MR). Aucune valeur. -->

| Identifiant | Type | Propriétaire | Portée / rôle | Stockage | Expiration | Rotation |
|---|---|---|---|---|---|---|
| `wb-tofu@pve!tofu` | jeton d'API Proxmox (privsep) | équipe Plateforme (`<MOI>`) | rôle `WBTofu` sur `/pool/lab`, `PVEDatastoreUser` sur `/storage/local-nvme`, `PVESDNUser` sur `/sdn/zones/lab/vsandbox` (élargi en M05-E10 : `hdd-bulk`, `vinfra`) | `adm01:~/.config/workbook/pve-tofu.env` (600) ; variable CI `PROXMOX_VE_API_TOKEN` protégée et masquée de `plateforme/infra` (M05-E26) | ≤ 1 an (`--expire`) | créer `wb-tofu@pve!tofu2` avec les mêmes ACL (`JETON=tofu2` dans le script), mettre à jour le fichier et la variable CI, `tofu plan` vide sur chaque état, supprimer l'ancien jeton |

# capi/revue-lucas/ — pas de `identifiants.yaml`

Le Secret d'identifiants **ne vit pas dans le dépôt**. Il se crée depuis `adm01` par
`capi/identifiants.sh` (adapté : `ESPACE=recette-agenda`, nom `recette-agenda-proxmox`), qui lit
`~/.config/workbook/pve-capi.env` (jeton `wb-capi@pve!capi`, pas `root@pam`) et l'ancre de `pve01`,
et écrit `insecure: "false"` + `root_ca`. Le jeton exposé dans la MR !7 doit être **révoqué**
(`pveum user token remove root@pam capi`) et la branche purgée de l'historique.

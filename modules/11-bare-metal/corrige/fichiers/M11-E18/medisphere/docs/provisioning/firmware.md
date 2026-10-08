# Firmwares du parc (PLAT-1235)

> M11-E18. Source : iLO, par `outils/inventaire-redfish.py` (job hebdomadaire de `plateforme/provisioning`), reporté dans NetBox (champs `firmware_bios`, `firmware_ilo`, `inventaire_maj`). Versions publiées : page de support HPE du modèle.

| Équipement | Composant | Installé | Dernier publié | Écart | Avis de sécurité connus | Décision |
|---|---|---|---|---|---|---|
| `hp01` | iLO 4 | <ex. 2.55> | 2.82 | <n> versions | <références HPE (HPESBHF…) corrigées entre les deux> | CHG-1235 : mise à jour planifiée hors fenêtre PBS, ou acceptation motivée |
| `hp01` | ROM système (BIOS) | <ex. J06 2019-xx-xx> | <dernière ROM du modèle> | <…> | <…> | <…> |
| `hp01` | Contrôleur de stockage, cartes réseau | <lu dans FirmwareInventory> | <…> | <…> | <…> | <…> |

Règles :
- Lecture seule dans ce ticket : aucune mise à jour sans fiche de changement (CHG) ni fenêtre hors sauvegardes PBS.
- Une mise à jour de l'iLO redémarre l'iLO, pas le serveur ; une mise à jour de la ROM système exige un redémarrage de `hp01` (donc de PBS) : fenêtre annoncée, `proxmox-backup-manager task list` vérifié avant.
- La comparaison aux versions publiées est manuelle : l'automatiser demande une source lisible par machine (catalogue du constructeur, outil de gestion de parc) — action ouverte.

Essai de droits (critère du ticket) : `PATCH /api/dcim/devices/<id de pve01>/` avec le jeton `svc-automatisation` → `403` (contrainte limitée à `hp01` et aux équipements `serveur-bm`), le <date>.

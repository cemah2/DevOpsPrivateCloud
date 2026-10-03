#!/usr/bin/env bash
# notifications-pbs.sh — Cible SMTP + filtre de notification sur pbs01 (M00-E29).
# À lancer sur pbs01 en root (PBS 3.2+ / 4.x). Vérifie la syntaxe avec
# « proxmox-backup-manager notification --help » sur ta version.
set -euo pipefail

CIBLE=smtp-astreinte
read -r -s -p "Mot de passe SMTP : " MDP; echo

proxmox-backup-manager notification endpoint smtp create "$CIBLE" \
  --server "<SERVEUR-SMTP>" --port 587 --mode starttls \
  --username "<UTILISATEUR-SMTP>" --password "$MDP" \
  --from-address "<ADRESSE-EXPEDITEUR>" --mailto "<ADRESSE-ASTREINTE>" \
  --author "pbs01 (PAR2)" --comment "Astreinte plateforme - PLAT-129"
unset MDP

# Erreurs des tâches de maintenance du datastore ds-lab uniquement
proxmox-backup-manager notification matcher create ds-lab-erreurs \
  --mode all --match-severity error \
  --match-field 'regex:type=^(gc|prune|verify|sync)$' \
  --match-field exact:datastore=ds-lab \
  --target "$CIBLE" --comment "Erreurs GC/prune/verify/sync de ds-lab"

# Le datastore passe par le système de notifications (et non l'envoi direct au courriel de l'utilisateur)
proxmox-backup-manager datastore update ds-lab --notification-mode notification-system

# Test de la cible
proxmox-backup-manager notification target test "$CIBLE"

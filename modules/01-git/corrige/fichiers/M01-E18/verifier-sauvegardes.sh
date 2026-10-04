#!/usr/bin/env bash
# verifier-sauvegardes.sh — alerte si la dernière sauvegarde d'une VM est trop ancienne.
# Lancé par cron à 2 h 30 sur adm01, après la tâche PBS « lab-nuit » de 1 h.
# Entrée : lignes « VMID HORODATAGE_UNIX » (dernière sauvegarde de chaque VM) sur l'entrée standard.
# Sortie : une ligne « ALERTE » par VM en retard ; code 1 s'il y a au moins une alerte.
set -euo pipefail

SEUIL_HEURES=26   # une sauvegarde par nuit, avec deux heures de marge

maintenant="$(date +%s)"
alertes=0
while read -r vmid horodatage; do
  [[ -n "$vmid" ]] || continue
  age=$(( (maintenant - horodatage) / 3600 ))
  if (( age > SEUIL_HEURES )); then
    echo "ALERTE : VM $vmid, dernière sauvegarde il y a $age h (seuil : $SEUIL_HEURES h)"
    alertes=$(( alertes + 1 ))
  fi
done
(( alertes == 0 ))

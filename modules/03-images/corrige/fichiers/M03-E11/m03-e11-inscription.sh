#!/bin/sh
# m03-e11-inscription.sh — vendor-data MédiAgenda, partie 2 : script (M03-E11).
# Partie « text/x-shellscript » du vendor-data : exécutée une fois par instance, à l'étape
# Final (module scripts_vendor). Simule l'inscription de la VM dans l'inventaire de l'équipe.
set -eu
mkdir -p /var/lib/mediagenda
{
  echo "inscrite le $(date --iso-8601=seconds)"
  echo "instance $(cloud-init query instance_id)"
  echo "adresses $(hostname -I)"
} > /var/lib/mediagenda/inscription

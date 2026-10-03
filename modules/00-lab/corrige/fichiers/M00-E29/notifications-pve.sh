#!/usr/bin/env bash
# notifications-pve.sh — Cible SMTP + filtres de notification sur pve01 (M00-E29, PLAT-129).
# À lancer sur pve01 en root. Les paramètres en <MAJUSCULES> sont à adapter.
# Syntaxe vérifiée sur PVE 8.1+ ; contrôle-la avec « pvesh usage <chemin> -v » sur ta version.
set -euo pipefail

CIBLE=smtp-astreinte
SERVEUR="<SERVEUR-SMTP>"        # ex. smtp.fournisseur.example
PORT=587
EXPEDITEUR="<ADRESSE-EXPEDITEUR>"
DESTINATAIRE="<ADRESSE-ASTREINTE>"
UTILISATEUR="<UTILISATEUR-SMTP>"

read -r -s -p "Mot de passe SMTP (ne sera pas affiché) : " MDP; echo

# 1. Cible SMTP (le mot de passe est stocké dans /etc/pve/priv/notifications.cfg)
pvesh create /cluster/notifications/endpoints/smtp \
  --name "$CIBLE" --server "$SERVEUR" --port "$PORT" --mode starttls \
  --username "$UTILISATEUR" --password "$MDP" \
  --from-address "$EXPEDITEUR" --mailto "$DESTINATAIRE" \
  --author "pve01 (PAR1)" --comment "Astreinte plateforme - PLAT-129"
unset MDP

# 2. Test de la cible
pvesh create "/cluster/notifications/targets/$CIBLE/test"

# 3. Filtre : échecs de sauvegarde uniquement
pvesh create /cluster/notifications/matchers \
  --name vzdump-erreurs --mode all \
  --match-field exact:type=vzdump --match-severity error \
  --target "$CIBLE" --comment "Echecs de sauvegarde vers l'astreinte"

# 4. Filtre : autres alertes de l'hyperviseur (réplication, fencing), sévérité warning/error
#    (syntaxe regex: à vérifier selon ta version ; valeurs de « type » dans la doc Notifications)
pvesh create /cluster/notifications/matchers \
  --name alertes-hyperviseur --mode all \
  --match-field 'regex:type=^(replication|fencing)$' --match-severity warning,error \
  --target "$CIBLE" --comment "Alertes hors sauvegarde"

# 5. Filtre par défaut : désactivé (il enverrait tout, y compris les succès, vers root@pam)
pvesh set /cluster/notifications/matchers/default-matcher --disable 1

# 6. Tâches de sauvegarde : passer par le système de notifications
#    (repère l'ID de ta tâche avec : pvesh get /cluster/backup)
# pvesh set /cluster/backup/<ID-TACHE> --notification-mode notification-system

pvesh get /cluster/notifications/matchers

# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E22.sh — M13-E22 « Panne : Harbor ne démarre plus » (sur reg01, Harbor de PRODUCTION)
#
# Garde-fou : refus d'injecter si la dernière sauvegarde (wb-backup-harbor.service, M13-E15) n'a pas
# réussi il y a moins de 26 h, ou si Harbor n'est pas « healthy ».
#
# Variantes (puis « systemctl restart harbor ») :
#   1. /data rempli par un fichier préalloué (fallocate, aucune écriture de données : rien n'est consommé
#      sur le stockage de pve01) laissé dans /data/tmp-export/ → PostgreSQL (uid 999) ne peut plus écrire ;
#   2. /data/database rendu propriété de root, mode 700 → harbor-db refuse de démarrer ;
#   3. clé du certificat du proxy (/data/secret/cert/server.key) rendue illisible (root, 000) → nginx
#      ne démarre plus, plus rien sur 443 ;
#   4. « prepare » qui a échoué : harbor.yml modifié (chemin de certificat inexistant) et configuration
#      générée (common/config) mise de côté, comme le fait prepare avant de valider → docker compose
#      refuse de démarrer (fichiers env introuvables).
# Rien n'est effacé : fichier de remplissage, droits d'origine, harbor.yml et common/config sont
# sauvegardés dans /var/lib/workbook/ de reg01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m13-commun.sh
source "$WB_ROOT/modules/13-registre-supply-chain/corrige/pannes/_m13-commun.sh"

# Fonctions communes aux scripts distants (dossier d'installation et volume de données).
read -r -d '' _E22_AIDE <<'AIDE' || true
INSTALL="$(systemctl show -p WorkingDirectory --value harbor.service)"
[ -n "$INSTALL" ] && [ -f "$INSTALL/harbor.yml" ] || INSTALL=/opt/harbor
DATA="$(sed -nE 's/^data_volume:[[:space:]]*([^[:space:]#]+).*/\1/p' "$INSTALL/harbor.yml" | head -n 1)"
DATA="${DATA:-/data}"
AIDE

_e22_exec() {
  local script
  script="$(cat)"
  printf '%s\n%s\n' "$_E22_AIDE" "$script" | wb_exec "$_M13_REG01"
}

_e22_sauvegarde_recente() {
  # shellcheck disable=SC2016  # évalué sur reg01
  remote "$_M13_REG01" '
    r=$(systemctl show -p Result --value wb-backup-harbor.service); t=$(systemctl show -p ExecMainExitTimestamp --value wb-backup-harbor.service)
    [ "$r" = success ] && [ -n "$t" ] && [ $(( $(date +%s) - $(date -d "$t" +%s) )) -lt 93600 ]' >/dev/null 2>&1
}

_e22_preparer() {
  m13_sante || { wb_avert "Harbor n'est pas « healthy » avant l'injection : rien n'a été cassé"; return 1; }
  _e22_sauvegarde_recente || {
    wb_avert "aucune sauvegarde réussie de moins de 26 h sur reg01 (wb-backup-harbor.service, M13-E15) : panne refusée"
    return 1
  }
}

_e22_poser() {
  case "$1" in
    1)
      _e22_exec <<'EOF' || return 1
set -e
dispo=$(df --output=avail -B1 "$DATA" | tail -n 1)
[ "$dispo" -gt 1073741824 ] || exit 10
install -d -m 0755 "$DATA/tmp-export"
f="$DATA/tmp-export/harbor-export-$(date +%Y%m%d).tar"
echo "$f" > "$WB_DIR/$WB_EX.remplissage"
# Tout l'espace libre de /data (disque séparé du système : la session SSH n'est pas touchée ; XFS,
# rôle harbor, n'a pas de réserve pour root). Un second fichier comble le reste éventuel.
fallocate -l "$dispo" "$f" 2>/dev/null || fallocate -l $((dispo - 4194304)) "$f"
reste=$(df --output=avail -B1 "$DATA" | tail -n 1)
[ "$reste" -le 0 ] || fallocate -l "$reste" "$f.2" 2>/dev/null || true
journal "fichier de remplissage $f ($dispo octets)"
# harbor.service attend que les conteneurs soient sains (--wait) : son échec est le symptôme attendu.
systemctl restart harbor || true
EOF
      ;;
    2)
      _e22_exec <<'EOF' || return 1
set -e
stat -c '%u:%g:%a' "$DATA/database" > "$WB_DIR/$WB_EX.droits-database"
systemctl stop harbor
chown root:root "$DATA/database"
chmod 0700 "$DATA/database"
journal "$DATA/database : root:root 700"
systemctl start harbor || true
EOF
      ;;
    3)
      _e22_exec <<'EOF' || return 1
set -e
k="$DATA/secret/cert/server.key"
[ -f "$k" ]
stat -c '%u:%g:%a' "$k" > "$WB_DIR/$WB_EX.droits-cle"
chown root:root "$k"
chmod 0000 "$k"
journal "$k : root:root 000"
docker restart nginx >/dev/null
EOF
      ;;
    4)
      _e22_exec <<'EOF' || return 1
set -e
[ -d "$INSTALL/common/config" ]
systemctl stop harbor
sauver "$INSTALL/harbor.yml"
tar -C "$INSTALL/common" -cpf "$WB_DIR/$WB_EX.config.tar" config
echo "$INSTALL" > "$WB_DIR/$WB_EX.install"
# La « modification » : nouveau chemin du certificat, fichier jamais créé.
sed -i -E '/^https:/,/^[^[:space:]#]/ s|^([[:space:]]+certificate:[[:space:]]*).*|\1/etc/harbor/tls/registry-2026.crt|' "$INSTALL/harbor.yml"
grep -q 'registry-2026.crt' "$INSTALL/harbor.yml"
# Ce que fait prepare avant de valider : la configuration générée disparaît.
rm -rf "$INSTALL/common/config"
journal "harbor.yml modifié (certificat inexistant), common/config retiré (copie dans $WB_EX.config.tar)"
systemctl start harbor || true
EOF
      ;;
  esac
  m13_journal E22 "variante $1 posée"
}

_e22_defaire() {
  case "$1" in
    1)
      _e22_exec <<'EOF' || wb_avert "annulation : fichier de remplissage non retiré"
if [ -f "$WB_DIR/$WB_EX.remplissage" ]; then
  f="$(cat "$WB_DIR/$WB_EX.remplissage")"
  if [ -f "$f" ]; then rm -f "$f" "$f.2"; rmdir "$(dirname "$f")" 2>/dev/null || true; systemctl restart harbor; fi
  rm -f "$WB_DIR/$WB_EX.remplissage"
  journal "remplissage retiré"
fi
EOF
      ;;
    2)
      _e22_exec <<'EOF' || wb_avert "annulation : droits de la base non rétablis"
if [ -f "$WB_DIR/$WB_EX.droits-database" ]; then
  if [ "$(stat -c '%u' "$DATA/database")" = 0 ]; then
    IFS=: read -r u g m < "$WB_DIR/$WB_EX.droits-database"
    chown "$u:$g" "$DATA/database"; chmod "$m" "$DATA/database"
    systemctl restart harbor
  fi
  rm -f "$WB_DIR/$WB_EX.droits-database"
  journal "droits de la base rétablis"
fi
EOF
      ;;
    3)
      _e22_exec <<'EOF' || wb_avert "annulation : droits de la clé non rétablis"
if [ -f "$WB_DIR/$WB_EX.droits-cle" ]; then
  k="$DATA/secret/cert/server.key"
  if [ -f "$k" ] && [ "$(stat -c '%a' "$k")" = 0 ]; then
    IFS=: read -r u g m < "$WB_DIR/$WB_EX.droits-cle"
    chown "$u:$g" "$k"; chmod "$m" "$k"
    docker restart nginx >/dev/null || systemctl restart harbor
  fi
  rm -f "$WB_DIR/$WB_EX.droits-cle"
  journal "droits de la clé rétablis"
fi
EOF
      ;;
    4)
      _e22_exec <<'EOF' || wb_avert "annulation : configuration de Harbor non rétablie"
if [ -f "$WB_DIR/$WB_EX.install" ]; then
  I="$(cat "$WB_DIR/$WB_EX.install")"
  if grep -q 'registry-2026.crt' "$I/harbor.yml" 2>/dev/null || [ ! -d "$I/common/config" ]; then
    systemctl stop harbor || true
    restaurer_fichiers
    [ -d "$I/common/config" ] || tar -C "$I/common" -xpf "$WB_DIR/$WB_EX.config.tar"
    systemctl start harbor
  fi
  rm -f "$WB_DIR/$WB_EX.install" "$WB_DIR/$WB_EX.config.tar" "$WB_DIR/$WB_EX.manifeste"
  journal "harbor.yml et configuration générée rétablis"
fi
EOF
      ;;
  esac
}

_e22_injecter() { _e22_preparer || return 1; _e22_poser "$1"; }
panne_E22_v1() { _e22_injecter 1; }
panne_E22_v2() { _e22_injecter 2; }
panne_E22_v3() { _e22_injecter 3; }
panne_E22_v4() { _e22_injecter 4; }

_e22_hs() { ! m13_sante; }
# La panne est constatée si Harbor reste hors service pendant 30 s après l'avoir été (pas un simple
# redémarrage en cours).
verifier_E22() {
  m13_attendre 240 _e22_hs || return 1
  sleep 30
  _e22_hs
}

annuler_E22() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e22_defaire "$WB_VAR" ;;
    *) _e22_defaire 4; _e22_defaire 3; _e22_defaire 2; _e22_defaire 1 ;;
  esac
  m13_attendre 240 m13_sante || wb_avert "Harbor n'est pas encore « healthy » : vérifie reg01 (RB-135)"
  m13_journal E22 "annulation"
  rm -rf -- "$(m13_etat E22)"
}

resume_E22() { echo "Harbor (reg01) ne revient pas après un redémarrage : plus aucun pipeline ne passe."; }

symptome_E22() {
  local l
  case "$WB_VAR" in
    4) l="Karim avait aussi prévu « une petite modification de configuration » pour le renouvellement des certificats." ;;
    *) l="Karim n'a rien noté d'autre." ;;
  esac
  wb_symptome "Ticket INC-4022 — De : Nadia Roussel (priorité critique)" \
    "Après la maintenance de cette nuit sur reg01, Harbor ne revient pas : l'interface ne répond pas" \
    "ou renvoie une erreur, tous les pipelines échouent. Karim : « j'ai juste redémarré Harbor »." \
    "$l" \
    "La sauvegarde de cette nuit est là, mais je préfère qu'on ne restaure que si c'est nécessaire." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 13 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 13 E22 4 "$@"; }
fi

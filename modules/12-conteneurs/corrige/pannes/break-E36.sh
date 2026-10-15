# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M12-E36 « Panne : "permission denied" sur le volume »
#
# Variantes :
#   1. ctr01, pile de recette : la « restauration » de Lucas a laissé les fichiers du volume
#      recette_pgdata à root:root (docker cp sans -a crée les fichiers en root) ; PostgreSQL tourne
#      en UID 999 sans capacité → « could not access directory "/var/lib/postgresql/18/docker":
#      Permission denied », base en boucle, /pret à 503 ;
#   2. ctr02, témoin rootless recette-cache (compte app, User=999) : le répertoire de données
#      ~app/recette/cache a été recréé par app (« mkdir » + « cp ») → il appartient à l'UID 0 de
#      l'espace de noms de l'utilisateur, l'UID 999 du conteneur ne peut plus écrire l'AOF → Valkey
#      s'arrête, systemd le relance puis abandonne ;
#   3. ctr03 (SELinux enforcing), même témoin : l'option :Z a été retirée du Volume= et le contexte
#      du répertoire remis à celui du dossier personnel (restorecon) → container_t ne peut pas écrire
#      dans user_home_t : refus AVC. Sautée si ctr03 ne répond pas.
# Annulation : variante 1, propriétaire 999:999 rendu au volume puis pile de référence ; variantes 2
# et 3, témoin réinstallé dans sa version de référence (propriétaire, :Z, contexte).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_e36_hote() {
  case "$1" in
    2) echo "$_M12_CTR02" ;;
    3) echo "$_M12_CTR03" ;;
    *) echo "$_M12_CTR01" ;;
  esac
}

_mE36_une() {
  local h
  h="$(_e36_hote "$1")"
  case "$1" in
    1)
      [[ -n "${_M12_ASTREINTE:-}" ]] || m12_recette_preparer || return 1
      m12_exec "$_M12_CTR01" <<'EOF' || return $?
m="$(docker volume inspect -f '{{.Mountpoint}}' recette_pgdata 2>/dev/null)"
[ -n "$m" ] && [ -d "$m/18/docker" ] || exit 10
dc stop db >/dev/null 2>&1
chown -R 0:0 "$m"
journal "volume recette_pgdata : propriétaire root:root"
dc start db >/dev/null 2>&1 || true
EOF
      ;;
    2 | 3)
      m12_existe "$h" || return 10
      m12_cache_preparer "$h" || return 1
      m12_exec "$h" VAR="$1" <<'EOF' || return $?
Q="$H_APP/.config/containers/systemd"
if [ "$VAR" = 2 ]; then
  # Répertoire « recréé » par app : il appartient à app sur l'hôte, donc à root dans l'espace de noms.
  chown -R app:app "$H_APP/recette/cache"
  journal "~app/recette/cache rendu à app:app (UID 0 du conteneur)"
else
  command -v getenforce >/dev/null && [ "$(getenforce)" = Enforcing ] || exit 10
  sauver "$Q/recette-cache.container"
  remplacer_ "$Q/recette-cache.container" "Volume=%h/recette/cache:/data:Z" "Volume=%h/recette/cache:/data" || exit 10
  en_app systemctl --user daemon-reload
  en_app systemctl --user stop recette-cache.service
  restorecon -RF "$H_APP/recette/cache"
  journal ":Z retiré, contexte de ~app/recette/cache remis par restorecon"
fi
en_app systemctl --user restart recette-cache.service >/dev/null 2>&1 || true
EOF
      ;;
  esac
}

_e36_casse() {
  local h e
  h="$(_e36_hote "$WB_VAR")"
  if [[ "$WB_VAR" == 1 ]]; then
    e="$(m12_etat_service db)"
    [[ "$e" != "running healthy"* ]] && [[ "$(m12_api_pret_code)" != 200 ]]
  else
    ! m12_cache_sain "$h"
  fi
}

panne_E36_v1() { m12_essayer E36 3 1; }
panne_E36_v2() { m12_essayer E36 3 2; }
panne_E36_v3() { m12_essayer E36 3 3; }

verifier_E36() { sleep 15; m12_attendre 60 _e36_casse; }

_e36_defaire() {
  local h
  h="$(_e36_hote "$1")"
  case "$1" in
    1)
      m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
m="$(docker volume inspect -f '{{.Mountpoint}}' recette_pgdata 2>/dev/null)"
if [ -n "$m" ] && [ -d "$m" ]; then
  chown -R 999:999 "$m"
  [ -d "$m/18/docker" ] && chmod 700 "$m/18/docker"
fi
rm -f "$WB_DIR/$WB_EX".*
journal "annulation : volume recette_pgdata rendu à 999:999"
dc restart db >/dev/null 2>&1 || true
EOF
      m12_recette_reinitialiser
      ;;
    2 | 3)
      if m12_existe "$h"; then
        m12_exec "$h" <<'EOF' >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
        m12_cache_installer "$h" >/dev/null || wb_avert "témoin recette-cache de $h non réinstallé"
      fi
      ;;
  esac
}

annuler_E36() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e36_defaire "$WB_VAR" ;;
    *) _e36_defaire 1; _e36_defaire 2; _e36_defaire 3 ;;
  esac
  m12_oublier E36
}

resume_E36() {
  echo "La base de recette ne redémarre plus depuis la « restauration » de Lucas : /pret répond 503."
}

symptome_E36() {
  local detail
  case "$WB_VAR" in
    2) detail="Sur ctr02, le cache de recette (service recette-cache du compte app) ne démarre plus depuis que Lucas a « refait proprement » son répertoire de données. Lucas : « le répertoire appartient bien à app, je ne vois pas ce qui manque »." ;;
    3) detail="Sur ctr03, le cache de recette (service recette-cache du compte app) ne démarre plus depuis que Lucas a « nettoyé » le fichier Quadlet et « remis les droits par défaut » sur le répertoire de données. Les droits Unix lui semblent bons." ;;
    *) detail="Lucas a restauré hier soir la base de recette de MédiAgenda sur ctr01 (« docker cp » de la sauvegarde dans le volume). Depuis, le conteneur de la base redémarre sans cesse et http://ctr01.par1.medisphere.internal:18000/pret répond 503." ;;
  esac
  wb_symptome "Ticket INC-3936 — De : Nadia Roussel" \
    "$detail" \
    "Les journaux parlent de « Permission denied ». Répare sans perdre les données, et ne te contente pas" \
    "d'un chmod 777 : Sophie relira." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 12 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E36 3 "$@"; }
fi

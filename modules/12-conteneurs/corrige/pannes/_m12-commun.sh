# shellcheck shell=bash
# _m12-commun.sh — fonctions partagées par les scripts de panne du module 12 (M12-E35 à M12-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_avert, wb_symptome, WB_EX, WB_VAR…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 « Pannes du bloc C ») :
#   - les pannes n'agissent que sur ctr01, ctr02, ctr03 (variante SELinux de E36) et runner02, par SSH
#     (utilisateur admin + sudo) ; jamais sur pve01, pbs01, git01, ni sur une VM hors du pool lab ;
#   - aucune donnée n'est détruite : le volume de la base de recette est au plus « rechowné », les
#     fichiers modifiés sont sauvegardés (sauver/restaurer_fichiers du prélude) ou remis à leur
#     version de référence ; seuls les objets créés par la panne elle-même sont supprimés ;
#   - l'annulation d'une panne de runner02 ou du registre ne rétablit que ce qui porte encore la
#     marque de la panne (une réparation de l'apprenant n'est jamais défaite).
#
# Les TÉMOINS du palier 4 (voir l'en-tête de enonce/04-expert.md) :
#   - ctr01 : la pile de recette Compose « recette » dans /srv/recette (db PostgreSQL 18, valkey,
#     migrations, api MédiAgenda, doc MédiDoc), construite depuis apps/ du workbook et les fichiers de
#     référence de _m12-plateau/ctr01/ ; elle est remise à sa version de référence avant chaque panne
#     (fichiers de l'apprenant archivés dans /srv/recette-archives/<date>/ ; .env, secrets/ et volumes
#     conservés) ;
#   - ctr02 et ctr03 : le service Quadlet « recette-cache » (Valkey) du compte app, fichiers de
#     référence _m12-plateau/ctr02/ et ctr03/ (le second avec :Z), données dans ~app/recette/cache.
#
# État sur adm01 : ~/.local/state/workbook/M12-EXX/ (clé = fichier) ; marqueurs de pannes actives :
# ~/.local/state/workbook/pannes-actives/M12-EXX (pannes-lib).

_M12_CTR01="${WB_M12_CTR01:-ctr01}"
_M12_CTR02="${WB_M12_CTR02:-ctr02}"
_M12_CTR03="${WB_M12_CTR03:-ctr03}"
_M12_RUNNER02="${WB_M12_RUNNER02:-runner02}"
_M12_PLATEAU="$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-plateau"

# ---------------------------------------------------------------------------
# État local (adm01)
# ---------------------------------------------------------------------------
m12_etat() { printf '%s/workbook/M12-%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"; }
m12_ecrire() { mkdir -p "$(m12_etat "$1")" && printf '%s\n' "$3" > "$(m12_etat "$1")/$2"; }
m12_lire() { if [[ -f "$(m12_etat "$1")/$2" ]]; then cat "$(m12_etat "$1")/$2"; fi; }
m12_oublier() { rm -rf -- "$(m12_etat "$1")"; }

# m12_attendre SECONDES commande… — 0 dès que la commande réussit, 1 au bout du délai.
m12_attendre() {
  local delai="$1" t=0; shift
  while ((t < delai)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5; t=$((t + 5))
  done
  return 1
}

# m12_autres_pannes — 0 si une AUTRE panne M12 est marquée active (hors WB_EX et hors astreinte).
m12_autres_pannes() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" f
  for f in "$d"/M12-E*; do
    [[ -e "$f" ]] || continue
    [[ "${f##*/}" == "$WB_EX" ]] && continue
    return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Exécution distante : aide commune ajoutée devant chaque script (exécuté en root)
# ---------------------------------------------------------------------------
read -r -d '' _M12_AIDE <<'AIDE' || true
R=/srv/recette
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
dc() { (cd "$R" && docker compose "$@" </dev/null); }
# etat_ SERVICE — « statut santé redémarrages » du conteneur recette-SERVICE-1
etat_() {
  docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}} {{.RestartCount}}' "recette-$1-1" 2>/dev/null || echo "absent - 0"
}
# http_ URL [délai] — code HTTP (0 si pas de réponse)
http_() {
  python3 - "$@" <<'PY' 2>/dev/null || echo 0
import sys, urllib.request, urllib.error
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=float(sys.argv[2]) if len(sys.argv) > 2 else 5).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print(0)
PY
}
# remplacer_ FICHIER ANCIEN NOUVEAU — remplace une occurrence exacte (code 10 si absente)
remplacer_() {
  python3 - "$@" <<'PY'
import sys
f, a, n = sys.argv[1:4]
t = open(f, encoding="utf-8").read()
if a not in t:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(t.replace(a, n, 1))
PY
}
# Compte applicatif sans privilège (ctr02, ctr03)
UID_APP="$(id -u app 2>/dev/null || echo 0)"
H_APP="$(getent passwd app 2>/dev/null | cut -d: -f6)"
en_app() {
  (cd /tmp && sudo -u app env XDG_RUNTIME_DIR="/run/user/$UID_APP" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_APP/bus" "$@" </dev/null)
}
cache_actif_() {
  [ "$(en_app systemctl --user is-active recette-cache.service 2>/dev/null)" = active ] &&
    [ "$(en_app podman exec recette-cache valkey-cli ping 2>/dev/null)" = PONG ]
}
AIDE

# m12_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec avec l'aide ci-dessus.
m12_exec() {
  local h="$1"; shift
  { printf '%s\n' "$_M12_AIDE"; cat; } | wb_exec "$h" "$@"
}

# m12_existe HÔTE — l'hôte répond en SSH.
m12_existe() { remote "$1" true >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Témoin ctr01 : pile de recette Compose
# ---------------------------------------------------------------------------
# m12_reference_envoyer — copie sur ctr01 (/var/lib/workbook/m12-reference/recette) les fichiers de
# référence et les sources de MédiAgenda et MédiDoc (apps/ du workbook, sans les environnements locaux).
m12_reference_envoyer() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/recette/api" "$tmp/recette/doc"
  (cd "$WB_ROOT/apps/mediagenda" && tar --exclude=.venv --exclude=.pytest_cache --exclude=.ruff_cache \
    --exclude=__pycache__ -cf - .) | tar -C "$tmp/recette/api" -xf - || rc=1
  (cd "$WB_ROOT/apps/medidoc" && tar --exclude=./medidoc -cf - .) | tar -C "$tmp/recette/doc" -xf - || rc=1
  cp -a "$_M12_PLATEAU/ctr01/recette/." "$tmp/recette/" || rc=1
  if ((rc == 0)); then
    tar -C "$tmp" -czf - recette | remote "$_M12_CTR01" \
      "sudo -n bash -c 'rm -rf /var/lib/workbook/m12-reference && mkdir -p /var/lib/workbook/m12-reference && chmod 700 /var/lib/workbook && tar -xzf - -C /var/lib/workbook/m12-reference'" || rc=1
  fi
  rm -rf -- "$tmp"
  return "$rc"
}

# m12_recette_installer — (ré)installe la pile de recette de référence et attend qu'elle soit saine.
#   La première fois, la construction des deux images prend quelques minutes (téléchargements).
m12_recette_installer() {
  m12_existe "$_M12_CTR01" || { wb_avert "$_M12_CTR01 ne répond pas en SSH"; return 1; }
  echo "Préparation de la pile de recette sur $_M12_CTR01 (la première fois : 5 à 10 minutes)…" >&2
  m12_reference_envoyer || { wb_avert "envoi des fichiers de référence impossible"; return 1; }
  m12_exec "$_M12_CTR01" <<'EOF'
command -v docker >/dev/null || { echo "Docker absent de ctr01" >&2; exit 1; }
REF=/var/lib/workbook/m12-reference/recette
mkdir -p "$R"
chmod 750 "$R"
# Archive des fichiers de l'apprenant (petits fichiers seulement, ni .env ni secrets)
if [ -e "$R/compose.yaml" ] && ! cmp -s "$R/compose.yaml" "$REF/compose.yaml" || [ -e "$R/compose.override.yaml" ]; then
  arch="/srv/recette-archives/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$arch"
  (cd "$R" && find . -path ./secrets -prune -o -path ./.env -prune -o -type f -size -1024k -print0 \
    | xargs -0 -r cp --parents -t "$arch" 2>/dev/null) || true
  journal "fichiers de /srv/recette archivés dans $arch"
fi
rm -rf "$R/api" "$R/doc" "$R/compose.override.yaml" "$R/compose.yaml" "$R/LISEZMOI.md"
cp -a "$REF/." "$R/"
mkdir -p "$R/secrets"
if [ ! -s "$R/.env" ] || [ ! -s "$R/secrets/db_password.txt" ]; then
  if [ -s "$R/.env" ]; then
    mdp="$(sed -n 's/^DB_MOT_DE_PASSE=//p' "$R/.env")"
  else
    mdp="$(openssl rand -hex 16)"
  fi
  umask 077
  printf 'DB_MOT_DE_PASSE=%s\n' "$mdp" > "$R/.env"
  printf '%s' "$mdp" > "$R/secrets/db_password.txt"
fi
chmod 600 "$R/.env"
chown 999:999 "$R/secrets/db_password.txt"
chmod 400 "$R/secrets/db_password.txt"
if ! dc up -d --build --remove-orphans --wait --wait-timeout 300 >/var/lib/workbook/m12-recette-up.log 2>&1; then
  echo "La pile de recette ne démarre pas (voir /var/lib/workbook/m12-recette-up.log sur ctr01)" >&2
  exit 1
fi
journal "pile de recette (ré)installée"
EOF
}

# m12_recette_saine — 0 si les quatre services tournent (sains quand ils ont une sonde), /pret de l'API
#   répond 200 et /healthz de MédiDoc répond 200 (vu depuis ctr01).
m12_recette_saine() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1
for s in db valkey api; do
  set -- $(etat_ "$s"); [ "$1" = running ] && [ "$2" = healthy ] || exit 1
done
set -- $(etat_ doc); [ "$1" = running ] || exit 1
[ "$(http_ http://127.0.0.1:18000/pret 8)" = 200 ] && [ "$(http_ http://127.0.0.1:18080/healthz 5)" = 200 ]
EOF
}

# m12_recette_preparer — garde-fous communs aux pannes de la pile de recette (hors astreinte).
m12_recette_preparer() {
  if [[ -n "${_M12_ASTREINTE:-}" ]]; then return 0; fi
  if m12_autres_pannes; then
    echo "Une autre panne du module 12 est encore active : répare-la ou annule-la d'abord." >&2
    return 1
  fi
  m12_recette_installer || return 1
  m12_recette_saine || { wb_avert "la pile de recette n'est pas saine après installation"; return 1; }
}

# m12_recette_reinitialiser — annulation : remet la pile de référence (sauf pendant l'astreinte, qui
#   le fait une fois à la fin).
m12_recette_reinitialiser() {
  if [[ -n "${_M12_ASTREINTE:-}" ]]; then return 0; fi
  m12_recette_installer >/dev/null || wb_avert "pile de recette non réinstallée : relance lab/bin/break 12 ${WB_EX#M12-E} --annuler"
}

# m12_compose_remplacer "ancien" "nouveau" — modifie /srv/recette/compose.yaml (sauvegardé avant).
#   Code 10 si le texte attendu est absent (la variante ne s'applique pas).
m12_compose_remplacer() {
  m12_exec "$_M12_CTR01" ANCIEN="$1" NOUVEAU="$2" <<'EOF'
sauver "$R/compose.yaml"
remplacer_ "$R/compose.yaml" "$ANCIEN" "$NOUVEAU"
rc=$?
[ "$rc" = 0 ] && journal "compose.yaml modifié"
exit "$rc"
EOF
}

# m12_compose ARGS… — docker compose ARGS dans /srv/recette (sortie dans le journal de ctr01).
m12_compose() {
  m12_exec "$_M12_CTR01" ARGS="$*" <<'EOF'
dc $ARGS >>/var/lib/workbook/m12-compose.log 2>&1
EOF
}

# m12_etat_service SERVICE — « statut santé redémarrages » vu de ctr01.
m12_etat_service() {
  m12_exec "$_M12_CTR01" S="$1" <<'EOF'
etat_ "$S"
EOF
}

# m12_api_pret_code — code HTTP de /pret vu de ctr01 (0 si pas de réponse).
m12_api_pret_code() {
  m12_exec "$_M12_CTR01" <<'EOF'
http_ http://127.0.0.1:18000/pret 8
EOF
}

# ---------------------------------------------------------------------------
# Témoins ctr02 / ctr03 : service Quadlet recette-cache du compte app
# ---------------------------------------------------------------------------
# m12_cache_installer HÔTE — (ré)installe les fichiers Quadlet de référence et démarre le service.
m12_cache_installer() {
  local h="$1" ref
  case "$h" in
    "$_M12_CTR03") ref="$_M12_PLATEAU/ctr03" ;;
    *) ref="$_M12_PLATEAU/ctr02" ;;
  esac
  m12_existe "$h" || { wb_avert "$h ne répond pas en SSH"; return 1; }
  echo "Préparation du témoin recette-cache sur $h…" >&2
  m12_exec "$h" CONTAINER="$(cat "$ref/recette-cache.container")" NETWORK="$(cat "$ref/recette.network")" <<'EOF'
[ "$UID_APP" != 0 ] && [ -n "$H_APP" ] || { echo "compte app absent" >&2; exit 1; }
command -v podman >/dev/null || { echo "Podman absent" >&2; exit 1; }
loginctl enable-linger app
for i in $(seq 1 30); do [ -S "/run/user/$UID_APP/bus" ] && break; sleep 1; done
Q="$H_APP/.config/containers/systemd"
install -d -o app -g app "$H_APP/.config" "$H_APP/.config/containers" "$Q" "$H_APP/recette"
if [ -e "$Q/recette-cache.container" ] && [ "$(cat "$Q/recette-cache.container")" != "$CONTAINER" ]; then
  arch="$H_APP/recette-archives/$(date +%Y%m%d-%H%M%S)"
  install -d -o app -g app "$H_APP/recette-archives" "$arch"
  cp -a "$Q"/recette* "$arch/" 2>/dev/null || true
  chown -R app:app "$arch"
fi
rm -f "$Q"/recette-cache.container* "$Q"/recette.network* "$Q"/recette-net*.network
printf '%s\n' "$CONTAINER" > "$Q/recette-cache.container"
printf '%s\n' "$NETWORK" > "$Q/recette.network"
chown app:app "$Q/recette-cache.container" "$Q/recette.network"
install -d -o app -g app "$H_APP/recette/cache"
en_app podman pull -q docker.io/valkey/valkey:8-trixie >/dev/null || exit 1
en_app podman unshare chown -R 999:999 "$H_APP/recette/cache" || exit 1
en_app systemctl --user daemon-reload
en_app systemctl --user reset-failed recette-cache.service 2>/dev/null || true
en_app systemctl --user restart recette-cache.service || exit 1
for i in $(seq 1 30); do cache_actif_ && break; sleep 2; done
cache_actif_ || exit 1
journal "témoin recette-cache (ré)installé"
EOF
}

# m12_cache_sain HÔTE — 0 si recette-cache est actif et répond PONG.
m12_cache_sain() {
  m12_exec "$1" <<'EOF' >/dev/null 2>&1
cache_actif_
EOF
}

# m12_cache_preparer HÔTE — garde-fous + (ré)installation du témoin (hors astreinte).
m12_cache_preparer() {
  if m12_autres_pannes; then
    echo "Une autre panne du module 12 est encore active : répare-la ou annule-la d'abord." >&2
    return 1
  fi
  m12_cache_installer "$1" || return 1
}

# m12_essayer EXX NB DÉPART — essaie la variante DÉPART puis les suivantes tant que _mEXX_une renvoie 10
#   (variante sans effet sur ce lab) ; WB_VAR reçoit la variante injectée.
m12_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    # shellcheck disable=SC2034  # lue par les fonctions de panne et par wb_main
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      # shellcheck disable=SC2034
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M12-$ex ne s'applique à ce lab (configuration inattendue)"
  return 1
}

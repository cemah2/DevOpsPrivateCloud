# shellcheck shell=bash
# _m12-expert.sh — fonctions partagées par les vérifications du palier 4 du module 12 (check-E35 à
# check-E44). Sourcé par ces scripts, jamais lancé seul. Lecture seule : docker inspect/ps/events/
# system df, systemctl --user status/show, podman exec … valkey-cli ping, nft list, stat, ausearch.
# Préfixe _m12x_ : évite les collisions quand check-E43 charge plusieurs checks.
#
# Hôtes (variables de lab/lab.env, facultatives) : WB_M12_CTR01, WB_M12_CTR02, WB_M12_CTR03,
# WB_M12_RUNNER02 (noms SSH, défaut ctr01…) ; WB_M12_CTR01_NOM (nom HTTP de ctr01, défaut
# ctr01.par1.medisphere.internal).

_m12x_ctr01="${WB_M12_CTR01:-ctr01}"
_m12x_ctr02="${WB_M12_CTR02:-ctr02}"
_m12x_ctr03="${WB_M12_CTR03:-ctr03}"
# shellcheck disable=SC2034  # utilisée par check-E42 et check-E46
_m12x_runner02="${WB_M12_RUNNER02:-runner02}"
_m12x_nom01="${WB_M12_CTR01_NOM:-ctr01.par1.medisphere.internal}"
# shellcheck disable=SC2034
_m12x_url_api="http://$_m12x_nom01:${WB_M12_PORT_API:-8000}"
# shellcheck disable=SC2034
_m12x_url_doc="http://$_m12x_nom01:${WB_M12_PORT_DOC:-8080}"

# _m12x_root HÔTE <<'EOF' … EOF — script de lecture exécuté en root (sudo -n) sur l'hôte.
_m12x_root() {
  remote "$1" "sudo -n bash -s" 2>/dev/null
}

# _m12x_joignable HÔTE — l'hôte répond en SSH avec sudo.
_m12x_joignable() { remote "$1" "sudo -n true" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------------------------------
# Instantané de la pile de recette de ctr01 (mis en cache pour tout le check, y compris check-E43)
# ---------------------------------------------------------------------------------------------------
_M12X_RECETTE="${_M12X_RECETTE:-}"
_m12x_recette_charger() {
  if [[ -z "$_M12X_RECETTE" ]]; then
    # shellcheck disable=SC2016  # script évalué sur ctr01
    _M12X_RECETTE="$(_m12x_root "$_m12x_ctr01" <<'EOF'
command -v docker >/dev/null || { echo '{"docker":false}'; exit 0; }
ids="$(docker ps -aq 2>/dev/null)"
{
  if [ -n "$ids" ]; then docker inspect $ids 2>/dev/null; else echo '[]'; fi
  echo '@@'
  docker system df --format '{{json .}}' 2>/dev/null
  echo '@@'
  df --output=avail,size,pcent -B1 / | tail -n 1
  echo '@@'
  nft list ruleset 2>/dev/null | python3 -c 'import sys
t = sys.stdin.read()
import re
print("1" if re.search(r"table bridge [^{]*\{[^}]*?(5432)[^}]*?drop", t, re.S) else "0")' 2>/dev/null || echo 0
  echo '@@'
  m="$(docker volume inspect -f '{{.Mountpoint}}' recette_pgdata 2>/dev/null)"
  if [ -n "$m" ] && [ -d "$m/18/docker" ]; then stat -c '%u %a' "$m/18/docker"; else echo "absent"; fi
  echo '@@'
  cat /etc/docker/daemon.json 2>/dev/null || echo '{}'
} | python3 -c '
import json, sys
parts = sys.stdin.read().split("@@\n")
cont = json.loads(parts[0] or "[]")
svc = {}
autres = []
for c in cont:
    lab = c["Config"].get("Labels") or {}
    s = c.get("State", {})
    h = s.get("Health") or {}
    hc = c["Config"].get("Healthcheck") or {}
    hl = c["HostConfig"]
    d = {
        "nom": c["Name"].lstrip("/"),
        "statut": s.get("Status"),
        "sante": h.get("Status", "-"),
        "sante_derniere": (h.get("Log") or [{}])[-1].get("ExitCode") if h.get("Log") else None,
        "redemarrages": c.get("RestartCount", 0),
        "oom": s.get("OOMKilled", False),
        "code": s.get("ExitCode"),
        "debut": s.get("StartedAt"),
        "reseaux": sorted((c.get("NetworkSettings", {}).get("Networks") or {}).keys()),
        "memoire": hl.get("Memory", 0),
        "pids": hl.get("PidsLimit") or 0,
        "journal": hl.get("LogConfig", {}),
        "sonde": hc.get("Test") or [],
        "image": c["Config"].get("Image"),
        "etiquettes": lab,
    }
    if lab.get("com.docker.compose.project") == "recette" and lab.get("com.docker.compose.service"):
        svc[lab["com.docker.compose.service"]] = d
    else:
        autres.append(d)
df = {}
for l in parts[1].splitlines():
    try:
        x = json.loads(l); df[x.get("Type")] = x
    except Exception:
        pass
av, taille, pc = (parts[2].split() + ["0", "1", "0%"])[:3]
try:
    daemon = json.loads(parts[5])
except Exception:
    daemon = {}
print(json.dumps({"docker": True, "services": svc, "autres": autres, "df": df,
                  "libre": int(av), "taille": int(taille), "occupation": int(pc.rstrip("%")),
                  "nft_bridge_5432": parts[3].strip() == "1", "pgdata": parts[4].strip(),
                  "daemon": daemon}))
'
EOF
)"
    jq -e . >/dev/null 2>&1 <<<"$_M12X_RECETTE" || _M12X_RECETTE='{"docker":null}'
  fi
}

# _m12x_jq 'filtre' — 0 si le filtre jq, appliqué à l'instantané de la recette, est vrai.
_m12x_jq() {
  _m12x_recette_charger
  jq -e "$1" >/dev/null 2>&1 <<<"$_M12X_RECETTE"
}

# _m12x_recette_repond — garde-fou : Docker répond sur ctr01 et la pile « recette » existe.
_m12x_recette_repond() { _m12x_jq '.docker == true and (.services | length) > 0'; }

# _m12x_sain SERVICE — le service tourne, et il est « healthy » s'il a une sonde.
_m12x_sain() {
  _m12x_jq ".services.\"$1\" as \$s | \$s.statut == \"running\" and (\$s.sante == \"-\" or \$s.sante == \"healthy\")"
}

# _m12x_stable SERVICE [SECONDES] — aucun redémarrage du conteneur pendant SECONDES (défaut 30).
_m12x_stable() {
  local s="$1" d="${2:-30}" avant apres
  avant="$(_m12x_root "$_m12x_ctr01" <<<"docker inspect -f '{{.RestartCount}} {{.State.StartedAt}}' recette-$s-1")" || return 1
  sleep "$d"
  apres="$(_m12x_root "$_m12x_ctr01" <<<"docker inspect -f '{{.State.Status}} {{.RestartCount}} {{.State.StartedAt}}' recette-$s-1")" || return 1
  [[ "$apres" == "running $avant" ]]
}

# _m12x_dans_api 'code python' — exécute du Python (lecture) dans le conteneur de l'API.
_m12x_dans_api() {
  _m12x_root "$_m12x_ctr01" <<EOF >/dev/null
timeout 20 docker exec recette-api-1 python -c $(printf '%q' "$1")
EOF
}

# ---------------------------------------------------------------------------------------------------
# Témoin recette-cache (Quadlet, compte app) sur ctr02 / ctr03
# ---------------------------------------------------------------------------------------------------
# _m12x_cache_json HÔTE — état du témoin : actif, PONG, linger, générateur, cible par défaut,
#   propriétaire du répertoire de données, contexte SELinux, refus AVC récents.
_m12x_cache_json() {
  # shellcheck disable=SC2016  # script évalué sur l'hôte
  _m12x_root "$1" <<'EOF'
u="$(id -u app 2>/dev/null)" || { echo '{"app":false}'; exit 0; }
h="$(getent passwd app | cut -d: -f6)"
ea() { (cd /tmp && sudo -u app env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" "$@" </dev/null 2>/dev/null); }
actif="$(ea systemctl --user is-active recette-cache.service)"
pong="$(ea timeout 10 podman exec recette-cache valkey-cli ping)"
linger="$(loginctl show-user app -p Linger --value 2>/dev/null)"
gen=/usr/libexec/podman/quadlet
[ -x "$gen" ] || gen=/usr/lib/systemd/user-generators/podman-user-generator
d="$(mktemp -d)"; chmod 755 "$d"
if [ -x /usr/libexec/podman/quadlet ]; then
  ea /usr/libexec/podman/quadlet -dryrun -user > "$d/sortie" 2> "$d/erreurs"; rcg=$?
else
  ea "$gen" -dryrun -user > "$d/sortie" 2> "$d/erreurs"; rcg=$?
fi
genok=0; { [ "$rcg" = 0 ] && grep -q 'recette-cache' "$d/sortie" && ! grep -qiE 'error|unsupported|not found' "$d/erreurs"; } && genok=1
rm -rf "$d"
voulu=0; ea systemctl --user list-dependencies --plain default.target | grep -q 'recette-cache.service' && voulu=1
proprio="$(stat -c %u "$h/recette/cache" 2>/dev/null || echo -1)"
ctx="$(stat -c %C "$h/recette/cache" 2>/dev/null || echo -)"
avc=0
if command -v ausearch >/dev/null && command -v getenforce >/dev/null && [ "$(getenforce)" = Enforcing ]; then
  ausearch -m avc -ts recent 2>/dev/null | grep -q 'valkey' && avc=1
fi
printf '{"app":true,"uid_app":%s,"actif":"%s","pong":"%s","linger":"%s","generateur":%s,"voulu":%s,"proprietaire":%s,"contexte":"%s","avc":%s}\n' \
  "$u" "$actif" "$pong" "$linger" "$genok" "$voulu" "$proprio" "$ctx" "$avc"
EOF
}

# _m12x_cache_jq HÔTE 'filtre' — 0 si le filtre appliqué à l'état du témoin de l'hôte est vrai.
#   (Un cache par hôte, rempli dans le shell courant.)
declare -A _M12X_CACHE=()
_m12x_cache_jq() {
  local h="$1"
  if [[ -z "${_M12X_CACHE[$h]:-}" ]]; then
    _M12X_CACHE[$h]="$(_m12x_cache_json "$h")"
    jq -e . >/dev/null 2>&1 <<<"${_M12X_CACHE[$h]}" || _M12X_CACHE[$h]='{"app":null}'
  fi
  jq -e "$2" >/dev/null 2>&1 <<<"${_M12X_CACHE[$h]}"
}

# ---------------------------------------------------------------------------------------------------
# Pannes
# ---------------------------------------------------------------------------------------------------
# _m12x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M12-* si aucune) n'est marquée.
_m12x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M12-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M12-$e" ]] || return 1
  done
}

# _m12x_marqueur_date EXX — date (secondes) d'injection de la panne active, vide si aucune.
_m12x_marqueur_date() {
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M12-$1"
  if [[ -e "$f" ]]; then stat -c %Y "$f"; fi
}

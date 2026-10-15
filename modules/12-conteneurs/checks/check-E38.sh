# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M12-E38 « Panne : la construction échoue ou ignore le cache » : l'image de l'API de
# recette se reconstruit (contexte léger, aucun mandataire injoignable) et une modification du code
# ne relance pas l'installation des dépendances. La seconde construction d'essai se fait dans une
# COPIE temporaire du contexte (/srv/recette/api n'est jamais modifié) ; les essais n'ajoutent que du
# cache de construction, et l'image d'essai wb-check/e38:essai est supprimée. Durée : 1 à 3 minutes.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E38 — L'image de recette se construit, vite et avec le cache"
require_cmd jq ssh

# shellcheck disable=SC2016  # script évalué sur ctr01
_m12_e38_res="$(_m12x_root "$_m12x_ctr01" <<'SCRIPT'
R=/srv/recette
[ -f "$R/api/Dockerfile" ] || { echo "dockerfile=absent"; exit 0; }
echo "dockerfile=ok"
# Arguments de construction déclarés pour l'API dans compose.yaml (mandataires compris)
args="$(cd "$R" && docker compose config --format json 2>/dev/null </dev/null | python3 -c '
import json, sys
a = json.load(sys.stdin)["services"]["api"].get("build", {}).get("args") or {}
print(" ".join("--build-arg %s=%s" % (k, v) for k, v in a.items() if v is not None))' 2>/dev/null)"
mandataire=ok
for p in $(printf '%s\n' $args | sed -n 's/^\(HTTPS\{0,1\}_PROXY\|https\{0,1\}_proxy\)=//p'); do
  hp="${p#*://}"; hp="${hp%%/*}"
  timeout 5 bash -c "exec 3<>/dev/tcp/${hp%%:*}/${hp##*:}" 2>/dev/null || mandataire=injoignable
done
echo "mandataire=$mandataire"
d="$(mktemp -d)"
trap 'rm -rf "$d"; docker image rm -f wb-check/e38:essai >/dev/null 2>&1' EXIT
taille="$(du -sb --exclude=.git "$R/api" | cut -f1)"
# Premier essai : depuis le vrai contexte (lecture seule)
if timeout 900 docker build --progress=plain $args -t wb-check/e38:essai "$R/api" > "$d/1.log" 2>&1 </dev/null; then
  echo "construction=ok"
else
  echo "construction=echec"; exit 0
fi
ctx="$(grep -E 'transferring context: [0-9.]+[kMG]?B' "$d/1.log" | tail -n 1 | sed -E 's/.*transferring context: ([0-9.]+)([kMG]?B).*/\1 \2/')"
echo "contexte=$(echo "$ctx" | awk '{m=1; if($2=="kB")m=1e3; if($2=="MB")m=1e6; if($2=="GB")m=1e9; printf "%d", $1*m}')"
# Second essai : une ligne de code modifiée, dans une copie du contexte (s'il est raisonnable)
if [ "$taille" -lt $((500 * 1024 * 1024)) ]; then
  mkdir -p "$d/ctx" && cp -a "$R/api/." "$d/ctx/"
  f="$(find "$d/ctx/src" -name '__init__.py' 2>/dev/null | head -n 1)"
  [ -n "$f" ] && printf '\n# essai de cache %s\n' "$(date +%s)" >> "$f"
  timeout 900 docker build --progress=plain $args -t wb-check/e38:essai "$d/ctx" > "$d/2.log" 2>&1 </dev/null
  python3 - "$d/2.log" <<'PY'
import re, sys
etapes, cache = {}, set()
for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"#(\d+) \[[^\]]+\] RUN (.*)", l)
    if m:
        etapes[m.group(1)] = m.group(2)
    m = re.match(r"#(\d+) CACHED", l)
    if m:
        cache.add(m.group(1))
dep = [i for i, c in etapes.items() if re.search(r"uv sync|uv pip|pip install", c)]
print("cache_dependances=" + ("ok" if any(i in cache for i in dep) else "non"))
PY
else
  echo "cache_dependances=contexte-trop-gros"
fi
SCRIPT
)" || true

check_output "Dockerfile de l'API présent dans /srv/recette/api" '^dockerfile=ok' printf '%s\n' "$_m12_e38_res"
check_output "aucun mandataire injoignable transmis à la construction" '^mandataire=ok' printf '%s\n' "$_m12_e38_res"
check_output "la construction de l'image de l'API réussit" '^construction=ok' printf '%s\n' "$_m12_e38_res"
_m12_e38_ctx() { local c; c="$(sed -n 's/^contexte=//p' <<<"$_m12_e38_res")"; [[ -n "$c" ]] && ((c < 50000000)); }
check_cmd "contexte envoyé au constructeur inférieur à 50 Mo" _m12_e38_ctx
check_output "une modification du code ne relance pas l'installation des dépendances (étape en cache)" \
  '^cache_dependances=ok' printf '%s\n' "$_m12_e38_res"
check_cmd "panne M12-E38 close (lab/bin/break 12 38 --annuler après réparation)" _m12x_aucune_panne_active E38

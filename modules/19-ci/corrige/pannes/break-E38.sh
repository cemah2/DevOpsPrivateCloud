# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions perl, yq et jq entre apostrophes
# break-E38.sh — M19-E38 « Panne : le cache ne sert plus »
#
# Les jobs réussissent toujours : un cache qui échoue n'est qu'un avertissement dans le journal. Le
# canari du témoin affiche « CANARI cache restauré : oui|non ». Variantes :
#   1. s3-01 : l'identité S3 ci-cache perd tous ses droits (fichier d'identités de la passerelle S3 de
#      SeaweedFS, copie gardée dans /var/lib/workbook/, service redémarré) ;
#   2. gabarit TOML du runner k8s-par1 : BucketName « ci-cache » devenu « ci-caches » (compartiment
#      inexistant), gestionnaire redémarré ;
#   3. Lucas publie une version du composant canari dont la clé de cache vaut canari-$CI_PIPELINE_ID
#      (« pour éviter les caches périmés ») et la fait consommer par le témoin ;
#   4. Lucas publie une version dont le cache est rangé dans /tmp/cache-canari (hors du répertoire du
#      projet : le runner ne l'archive pas).
# Vérification : deux pipelines du témoin après l'injection, le second ne restaure toujours rien.
# Rien n'est supprimé dans le compartiment ci-cache.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

# Aide distante sur s3-01 (reprise de M05) : processus weed qui écoute sur 8333 et son option -s3.config.
read -r -d '' _E38_AIDE <<'AIDE' || true
pid8333() { ss -Hltnp 'sport = :8333' 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1; }
unite_8333() { local p; p="$(pid8333)"; [ -n "$p" ] || return 1; ps -o unit= -p "$p" 2>/dev/null | awk 'NF { print $1; exit }'; }
option_weed() {
  local p; p="$(pid8333)"; [ -n "$p" ] || return 1
  tr '\0' '\n' <"/proc/$p/cmdline" | awk -v n="-$1" -v nn="--$1" '
    prendre { print; exit }
    index($0, n "=") == 1 { print substr($0, length(n) + 2); exit }
    index($0, nn "=") == 1 { print substr($0, length(nn) + 2); exit }
    $0 == n || $0 == nn { prendre = 1 }'
}
attendre_8333() { local t=0; while [ "$t" -lt 60 ]; do [ -n "$(pid8333)" ] && return 0; sleep 2; t=$((t + 2)); done; return 1; }
AIDE

_e38_s3() { { printf '%s\n' "$_E38_AIDE"; cat; } | wb_exec "$_M19_S3"; }

# _e38_cache_inutile — deux pipelines du canari : le second ne restaure toujours pas le cache.
_e38_cache_inutile() {
  local st id
  read -r st id < <(m19_temoin_cycle 420)
  [[ "$st" == success ]] || return 1
  read -r st id < <(m19_temoin_cycle 420)
  [[ "$st" == success && -n "$id" ]] || return 1
  m19_ecraser E38 dernier-job "$id"
  m19_temoin_trace_contient "$id" 'CANARI cache restauré : non'
}

# _e38_cache_sert — le dernier pipeline du canari restaure le cache (précondition).
_e38_cache_sert() {
  local st id i
  for i in 1 2; do
    read -r st id < <(m19_temoin_cycle 420)
    [[ "$st" == success ]] || return 1
    m19_temoin_trace_contient "$id" 'CANARI cache restauré : oui' && return 0
    : "$i"
  done
  return 1
}

_m19E38_une() {
  local n="$1" rc=0
  m19_debut E38
  if [[ -z "${_M19_ASTREINTE:-}" ]] && ! _e38_cache_sert; then
    echo "Le cache du canari ne sert déjà pas avant l'injection : répare d'abord (lab/bin/check 19 38)." >&2
    return 1
  fi
  case "$n" in
    1)
      _e38_s3 >/dev/null <<'EOF' || rc=$?
conf="$(option_weed s3.config)"; [ -n "$conf" ] || conf="$(option_weed config)"
[ -n "$conf" ] && [ -f "$conf" ] || exit 10
u="$(unite_8333)"; [ -n "$u" ] || exit 10
t="$(mktemp)"
python3 - "$conf" "$t" <<'PY' || { rm -f "$t"; exit 10; }
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    conf = json.load(f)
change = False
for ident in conf.get("identities", []):
    if ident.get("name") == "ci-cache" and ident.get("actions"):
        ident["actions"] = []
        change = True
if not change:
    sys.exit(1)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(conf, f, indent=2)
    f.write("\n")
PY
sauver "$conf"
cat "$t" > "$conf"; rm -f "$t"
sha256sum "$conf" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.empreinte"
printf '%s\n' "$u" > "$WB_DIR/$WB_EX.unite"
systemctl restart "$u" || exit 1
attendre_8333 || exit 1
journal "$conf : droits de l'identité ci-cache retirés, $u redémarré"
EOF
      ((rc == 0)) || { _e38_defaire 1; return "$rc"; }
      m19_ecrire E38 s3 1
      ;;
    2)
      m19_toml_modifier E38 's{(BucketName\s*=\s*")ci-cache(")}{${1}ci-caches${2}}' || return $?
      ;;
    3)
      m19_canari_publier E38 "perf(canari): clé de cache par pipeline, plus de cache périmé" \
        '(select(documentIndex == 1) | .canari.cache.key) = "canari-$CI_PIPELINE_ID"' >/dev/null || return $?
      ;;
    4)
      m19_canari_publier E38 "refactor(canari): cache dans /tmp, hors de l'arborescence du projet" \
        '(select(documentIndex == 1) | .canari.cache.paths) = ["/tmp/cache-canari/"] | (select(documentIndex == 1) | .canari.variables.CANARI_CACHE_DIR) = "/tmp/cache-canari"' >/dev/null || return $?
      ;;
  esac
  m19_journal E38 "variante $n posée"
  _e38_cache_inutile || { _e38_defaire "$n"; return 10; }
  m19_journal E38 "variante $n constatée"
}

_e38_defaire() {
  local n="$1"
  case "$n" in
    1)
      _e38_s3 >/dev/null <<'EOF' || wb_avert "$_M19_S3 : identités S3 à vérifier (copies dans /var/lib/workbook/)"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
conf="$(cut -f1 "$WB_DIR/$WB_EX.manifeste" | head -n 1)"
u="$(cat "$WB_DIR/$WB_EX.unite" 2>/dev/null)"
if [ "$(sha256sum "$conf" | cut -d' ' -f1)" = "$(cat "$WB_DIR/$WB_EX.empreinte" 2>/dev/null)" ]; then
  restaurer_fichiers
  [ -z "$u" ] || { systemctl restart "$u" && attendre_8333; }
  journal "annulation : identités S3 rétablies, $u redémarré"
else
  rm -f "$WB_DIR/$WB_EX".*.orig "$WB_DIR/$WB_EX.manifeste"
  journal "annulation : $conf modifié depuis l'injection (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/$WB_EX.unite" "$WB_DIR/$WB_EX.empreinte"
EOF
      m19_oublier E38 s3
      ;;
    2) m19_toml_retablir E38 ;;
    3 | 4) m19_temoin_retablir E38 ;;
  esac
}

panne_E38_v1() { m19_preparer && m19_essayer E38 4 1; }
panne_E38_v2() { m19_preparer && m19_essayer E38 4 2; }
panne_E38_v3() { m19_preparer && m19_essayer E38 4 3; }
panne_E38_v4() { m19_preparer && m19_essayer E38 4 4; }

verifier_E38() {
  case "${WB_VAR:-}" in
    1) [[ -n "$(m19_lire E38 s3)" ]] ;;
    2) m19_toml "$(m19_lire E38 toml-cm)" | grep -q '"ci-caches"' ;;
    3 | 4) m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main | grep -q "canari@$(m19_lire E38 canari-version)" ;;
    *) return 1 ;;
  esac
}

annuler_E38() {
  case "${WB_VAR:-}" in
    [1-4]) _e38_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e38_defaire "$v"; done ;;
  esac
  m19_oublier E38 canari-version
  m19_oublier E38 dernier-job
  m19_oublier E38 debut
  m19_journal E38 "annulation"
}

resume_E38() { echo "Le cache de CI ne sert plus : le canari repart de zéro à chaque pipeline (« cache restauré : non »)."; }

symptome_E38() {
  wb_symptome "Ticket INC-4638 — De : Julien Petit" \
    "Nos pipelines ont pris plusieurs minutes d'un coup : les dépendances sont retéléchargées à" \
    "chaque fois. Les jobs sont verts, mais le cache ne sert plus. Le canari de la plateforme" \
    "(formation/ci-pannes) le montre aussi : « CANARI cache restauré : non », pipeline après" \
    "pipeline. Je ne sais pas ce qui a changé ; Lucas a travaillé sur « l'optimisation des caches »." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 19 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E38 4 "$@"; }
fi

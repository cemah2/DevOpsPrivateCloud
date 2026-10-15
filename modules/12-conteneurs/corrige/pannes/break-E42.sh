# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M12-E42 « Panne : le pipeline ne publie plus l'image »
#
# Cibles : le registre de travail de ctr01 (conteneur registry:3 qui publie le port 5000, M12-E15)
# et runner02 (GitLab Runner, exécuteur docker, M12-E20/E21). Jamais git01 : les variables de CI ne
# sont pas touchées. Le registre est retrouvé par son port publié, ses fichiers par ses montages
# (variables REGISTRY_AUTH_HTPASSWD_PATH, REGISTRY_HTTP_TLS_CERTIFICATE/KEY ou montages nommés
# *htpasswd*, *.crt/*.key). Variantes :
#   1. identifiants : le mot de passe du compte « ci » du registre a été « renouvelé » par Lucas
#      (nouvelle empreinte bcrypt, mot de passe inconnu) sans mise à jour de la CI → 401 à la poussée ;
#   2. certificat : le certificat du registre a été remplacé par un certificat auto-signé « en
#      attendant le renouvellement » → x509: certificate signed by unknown authority ;
#   3. exécuteur : les exceptions security_opt « …unconfined » de runner02 ont été retirées
#      (« durcissement CIS ») → la construction sans privilège (BuildKit rootless, Buildah) échoue
#      (espaces de noms, montages refusés) ; la proposition de Lucas, privileged = true, est refusée
#      par Sophie ;
#   4. cache d'images : pull_policy = ["never"] sur runner02 et images locales purgées (« ne plus
#      dépendre de Docker Hub ») → « failed to pull image … with specified policies [never] ».
# Annulation : ne rétablit que ce qui porte encore la marque de la panne (empreinte posée, empreinte
# du certificat posé, config.toml inchangé depuis l'injection).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

# Empreinte bcrypt d'un mot de passe aléatoire jeté aussitôt (personne ne le connaît).
# shellcheck disable=SC2016  # empreinte littérale
_E42_EMPREINTE='$2y$10$rZpUxE61dZJj4fwKz3k55OtIiU5tnxbnY.a2MZBlj/jRVoNMdFaQW'

# Aide distante (ctr01) : retrouve le conteneur du registre et le chemin, sur l'hôte, d'un fichier.
read -r -d '' _E42_AIDE_REGISTRE <<'AIDE' || true
REG="$(docker ps -q --filter publish=5000 | head -n 1)"
# hote_ VARIABLE MOTIF — chemin sur l'hôte du fichier désigné par la variable d'environnement du
#   conteneur (ou, à défaut, du premier fichier monté dont le nom correspond au motif).
hote_() {
  docker inspect "$REG" | python3 -c '
import json, os, sys, fnmatch
c = json.load(sys.stdin)[0]
var, motif = sys.argv[1], sys.argv[2]
env = dict(e.split("=", 1) for e in c["Config"]["Env"] if "=" in e)
cible = env.get(var)
mounts = sorted(c.get("Mounts", []), key=lambda m: -len(m.get("Destination", "")))
def vers_hote(p):
    for m in mounts:
        d = m.get("Destination", "").rstrip("/")
        if p == d or p.startswith(d + "/"):
            return m.get("Source", "") + p[len(d):]
    return ""
if cible:
    print(vers_hote(cible)); sys.exit(0)
for m in mounts:
    s = m.get("Source", "")
    if os.path.isfile(s) and fnmatch.fnmatch(os.path.basename(s), motif):
        print(s); sys.exit(0)
    if os.path.isdir(s):
        for r, _, fs in os.walk(s):
            for f in fs:
                if fnmatch.fnmatch(f, motif):
                    print(os.path.join(r, f)); sys.exit(0)
' "$1" "$2"
}
empreinte_servie_() {
  openssl s_client -connect 127.0.0.1:5000 -servername "$(hostname -f)" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2
}
AIDE

# _e42_reg_exec [VAR=valeur…] <<'EOF' … EOF — script sur ctr01 avec l'aide du registre.
_e42_reg_exec() {
  { printf '%s\n' "$_E42_AIDE_REGISTRE"; cat; } | m12_exec "$_M12_CTR01" "$@"
}

_mE42_une() {
  case "$1" in
    1 | 2)
      m12_existe "$_M12_CTR01" || return 10
      _e42_reg_exec VAR="$1" EMPREINTE="$_E42_EMPREINTE" <<'EOF' || return $?
[ -n "$REG" ] || exit 10
if [ "$VAR" = 1 ]; then
  f="$(hote_ REGISTRY_AUTH_HTPASSWD_PATH '*htpasswd*')"
  [ -n "$f" ] && [ -f "$f" ] && grep -q '^ci:' "$f" || exit 10
  sauver "$f"
  python3 - "$f" "$EMPREINTE" <<'PY' || exit 1
import sys
f, e = sys.argv[1], sys.argv[2]
l = open(f).read().splitlines()
open(f, "w").write("\n".join(("ci:" + e) if x.startswith("ci:") else x for x in l) + "\n")
PY
  printf '%s\n' "$f" > "$WB_DIR/$WB_EX.htpasswd"
  journal "empreinte du compte ci changée dans $f"
else
  crt="$(hote_ REGISTRY_HTTP_TLS_CERTIFICATE '*.crt')"
  key="$(hote_ REGISTRY_HTTP_TLS_KEY '*.key')"
  [ -n "$crt" ] && [ -f "$crt" ] && [ -n "$key" ] && [ -f "$key" ] || exit 10
  sauver "$crt"; sauver "$key"
  n="$(hostname -f)"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
    -subj "/CN=$n" -addext "subjectAltName=DNS:$n" -keyout "$key.wb" -out "$crt.wb" >/dev/null 2>&1 || exit 1
  cat "$key.wb" > "$key"; cat "$crt.wb" > "$crt"; rm -f "$key.wb" "$crt.wb"
  journal "certificat du registre remplacé par un auto-signé ($crt)"
fi
docker restart "$REG" >/dev/null || exit 1
sleep 3
[ "$VAR" = 2 ] && empreinte_servie_ > "$WB_DIR/$WB_EX.empreinte"
exit 0
EOF
      ;;
    3 | 4)
      m12_existe "$_M12_RUNNER02" || return 10
      m12_exec "$_M12_RUNNER02" VAR="$1" <<'EOF' || return $?
f=/etc/gitlab-runner/config.toml
[ -f "$f" ] || exit 10
sauver "$f"
python3 - "$f" "$VAR" <<'PY' || exit $?
import re, sys
f, var = sys.argv[1], sys.argv[2]
t = open(f, encoding="utf-8").read()
if var == "3":
    def nettoie(m):
        elems = [e for e in re.findall(r'"[^"]*"', m.group(2)) if "unconfined" not in e]
        return m.group(1) + "[" + ", ".join(elems) + "]"
    n = re.sub(r'(security_opt\s*=\s*)\[([^\]]*)\]', nettoie, t)
else:
    lignes, n, dans = t.splitlines(), [], False
    for l in lignes:
        if re.match(r'\s*\[', l):
            dans = re.match(r'\s*\[runners\.docker\]\s*$', l) is not None
            n.append(l)
            if dans:
                n.append('    pull_policy = ["never"]')
            continue
        if dans and re.match(r'\s*pull_policy\s*=', l):
            continue
        n.append(l)
    n = "\n".join(n) + "\n"
if n == t:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(n)
PY
if [ "$VAR" = 4 ]; then
  docker image prune -af >/dev/null 2>&1 || true
  journal "pull_policy never et images locales purgées"
else
  journal "exceptions security_opt unconfined retirées"
fi
sha256sum "$f" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.config-sha"
# GitLab Runner relit config.toml tout seul (quelques secondes).
sleep 5
EOF
      ;;
  esac
}

_e42_casse() {
  case "$WB_VAR" in
    1)
      m12_exec "$_M12_CTR01" EMPREINTE="$_E42_EMPREINTE" <<'EOF' >/dev/null 2>&1
f="$(cat "$WB_DIR/$WB_EX.htpasswd")"
grep -qxF "ci:$EMPREINTE" "$f" && [ -n "$(docker ps -q --filter publish=5000)" ]
EOF
      ;;
    2)
      _e42_reg_exec <<'EOF' >/dev/null 2>&1
[ -s "$WB_DIR/$WB_EX.empreinte" ] && [ "$(empreinte_servie_)" = "$(cat "$WB_DIR/$WB_EX.empreinte")" ]
EOF
      ;;
    *)
      m12_exec "$_M12_RUNNER02" <<'EOF' >/dev/null 2>&1
[ "$(sha256sum /etc/gitlab-runner/config.toml | cut -d' ' -f1)" = "$(cat "$WB_DIR/$WB_EX.config-sha")" ]
EOF
      ;;
  esac
}

panne_E42_v1() { _e42_garde && m12_essayer E42 4 1; }
panne_E42_v2() { _e42_garde && m12_essayer E42 4 2; }
panne_E42_v3() { _e42_garde && m12_essayer E42 4 3; }
panne_E42_v4() { _e42_garde && m12_essayer E42 4 4; }

_e42_garde() {
  if m12_autres_pannes; then
    echo "Une autre panne du module 12 est encore active : répare-la ou annule-la d'abord." >&2
    return 1
  fi
}

verifier_E42() { _e42_casse; }

_e42_defaire() {
  case "$1" in
    1)
      m12_exec "$_M12_CTR01" EMPREINTE="$_E42_EMPREINTE" <<'EOF' >/dev/null 2>&1 || true
f="$(cat "$WB_DIR/$WB_EX.htpasswd" 2>/dev/null)"
if [ -n "$f" ] && grep -qxF "ci:$EMPREINTE" "$f"; then
  restaurer_fichiers
  docker restart "$(docker ps -q --filter publish=5000 | head -n 1)" >/dev/null 2>&1 || true
  journal "annulation : htpasswd d'origine remis"
else
  journal "annulation : empreinte modifiée depuis la panne (réparation conservée)"
fi
rm -f "$WB_DIR/$WB_EX".*
EOF
      ;;
    2)
      _e42_reg_exec <<'EOF' >/dev/null 2>&1 || true
if [ -s "$WB_DIR/$WB_EX.empreinte" ] && [ "$(empreinte_servie_)" = "$(cat "$WB_DIR/$WB_EX.empreinte")" ]; then
  restaurer_fichiers
  [ -n "$REG" ] && docker restart "$REG" >/dev/null 2>&1
  journal "annulation : certificat d'origine remis"
else
  journal "annulation : certificat changé depuis la panne (réparation conservée)"
fi
rm -f "$WB_DIR/$WB_EX".*
EOF
      ;;
    3 | 4)
      m12_exec "$_M12_RUNNER02" <<'EOF' >/dev/null 2>&1 || true
f=/etc/gitlab-runner/config.toml
if [ -s "$WB_DIR/$WB_EX.config-sha" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$(cat "$WB_DIR/$WB_EX.config-sha")" ]; then
  restaurer_fichiers
  journal "annulation : config.toml d'origine remis"
else
  journal "annulation : config.toml modifié depuis la panne (réparation conservée)"
fi
rm -f "$WB_DIR/$WB_EX".*
EOF
      ;;
  esac
}

annuler_E42() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e42_defaire "$WB_VAR" ;;
    *) _e42_defaire 1; _e42_defaire 2; _e42_defaire 3 ;;
  esac
  m12_oublier E42
}

resume_E42() {
  echo "Les pipelines d'images (mediagenda/api…) échouent : plus aucune image n'arrive dans le registre de travail."
}

symptome_E42() {
  wb_symptome "Ticket INC-3942 — De : Julien Petit" \
    "Depuis ce matin, le pipeline de mediagenda/api (et ceux des autres applications) ne publie plus" \
    "l'image dans le registre de travail de ctr01 : le job de construction ou de publication échoue" \
    "sur runner02. Personne n'a touché au .gitlab-ci.yml. Lucas propose de « passer le runner en" \
    "privileged = true, comme tout le monde » : Sophie a déjà dit non." \
    "" \
    "Relance le pipeline de main de mediagenda/api pour constater, trouve la cause, corrige-la là" \
    "où elle est, et fais repasser le pipeline au vert. Temps cible : 45 min. Contrôle : lab/bin/check 12 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E42 4 "$@"; }
fi

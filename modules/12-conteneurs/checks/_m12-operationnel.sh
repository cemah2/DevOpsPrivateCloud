# shellcheck shell=bash
# _m12-operationnel.sh — fonctions partagées par les checks M12-E10 à M12-E21 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m12o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Hôtes (SSH en admin, noms courts résolus par le domaine de recherche de adm01) : ctr01 (Docker),
# ctr02 et ctr03 (Podman, compte « app »), runner02 (socle, M12-E20).
# Registre de travail : https://ctr01.par1.medisphere.internal:5000, identifiants du compte
# « plateforme » dans ~/.config/workbook/registre-travail.env (variable WB_REGISTRE_ENV) ; ils sont
# passés à curl par un fichier de configuration anonyme (-K <(…)), jamais en argument.
# Aucune fonction ne crée, ne modifie ni ne supprime de conteneur, d'image ou de fichier distant.

# shellcheck disable=SC2034  # constantes utilisées par les check-EXX.sh qui sourcent ce fichier
_M12O_DOMAINE="par1.medisphere.internal"
_M12O_CTR01="${WB_M12_CTR01:-ctr01}"
_M12O_CTR02="${WB_M12_CTR02:-ctr02}"
_M12O_CTR03="${WB_M12_CTR03:-ctr03}"
_M12O_RUNNER02="${WB_M12_RUNNER02:-runner02}"
_M12O_NOM01="${WB_M12_CTR01_NOM:-ctr01.par1.medisphere.internal}"
_M12O_NOM02="${WB_M12_CTR02_NOM:-ctr02.par1.medisphere.internal}"
_M12O_REGISTRE="$_M12O_NOM01:5000"
_M12O_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M12O_REGISTRE_ENV="${WB_REGISTRE_ENV:-$HOME/.config/workbook/registre-travail.env}"
_M12O_APP=app
_M12O_APP_UID=1001

# --- Exécution distante (lecture) ------------------------------------------------------------------

# _m12o_ssh HÔTE "COMMANDE" — commande distante en admin ; sortie standard, jamais d'échec.
_m12o_ssh() { remote "$1" "$2" 2>/dev/null || true; }

# _m12o_root HÔTE <<'EOF' … EOF — script de LECTURE exécuté en root (sudo -n) ; jamais d'échec.
_m12o_root() { remote "$1" "sudo -n bash -s" 2>/dev/null || true; }

# _m12o_docker "ARGUMENTS" — docker sur ctr01 (admin est dans le groupe docker).
_m12o_docker() { remote "$_M12O_CTR01" "docker $1" 2>/dev/null || true; }

# _m12o_app HÔTE "COMMANDE" — commande sous le compte app, avec sa session (linger) : XDG_RUNTIME_DIR
# et bus D-Bus de /run/user/<UID>.
_m12o_app() {
  remote "$1" "cd /tmp && sudo -n -u $_M12O_APP env XDG_RUNTIME_DIR=/run/user/$_M12O_APP_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_M12O_APP_UID/bus $2" 2>/dev/null || true
}

# --- Texte et JSON ---------------------------------------------------------------------------------

# _m12o_correspond TEXTE REGEX — le texte correspond à la regex étendue (grep -E, multi-lignes).
_m12o_correspond() { [[ -n "$1" ]] && grep -Eq -- "$2" <<<"$1"; }

# _m12o_absent TEXTE REGEX — le texte est NON VIDE et ne contient pas la regex.
_m12o_absent() { [[ -n "$1" ]] && ! grep -Eq -- "$2" <<<"$1"; }

# _m12o_json JSON FILTRE [ARGS jq…] — vrai si le filtre jq (-e) est vrai sur le JSON.
_m12o_json() {
  local d="$1" f="$2"
  shift 2
  [[ -n "$d" && "$d" != null ]] && jq -e "$@" "$f" <<<"$d" >/dev/null 2>&1
}

# --- GitLab (jeton des checks, lecture) -------------------------------------------------------------

# _m12o_enc TEXTE — encodage URL (mediagenda/api → mediagenda%2Fapi).
_m12o_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# _m12o_projet PROJET — JSON du projet GitLab (vide s'il n'existe pas).
_m12o_projet() { gitlab_api "projects/$(_m12o_enc "$1")" 2>/dev/null || true; }

# _m12o_fichier PROJET CHEMIN [RÉF] — contenu brut d'un fichier (vide s'il n'existe pas).
_m12o_fichier() {
  gitlab_api "projects/$(_m12o_enc "$1")/repository/files/$(_m12o_enc "$2")/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m12o_dernier_pipeline PROJET [RÉF] — JSON du dernier pipeline de la référence.
_m12o_dernier_pipeline() {
  gitlab_api "projects/$(_m12o_enc "$1")/pipelines?ref=${2:-main}&per_page=1&order_by=id&sort=desc" 2>/dev/null \
    | jq -c '.[0] // empty' 2>/dev/null || true
}

# _m12o_jobs_pipeline PROJET ID — JSON des jobs d'un pipeline.
_m12o_jobs_pipeline() {
  [[ "$2" =~ ^[0-9]+$ ]] || return 0
  gitlab_api "projects/$(_m12o_enc "$1")/pipelines/$2/jobs?per_page=100" 2>/dev/null || true
}

# --- Registre de travail ------------------------------------------------------------------------------

# _m12o_registre_lisible — le fichier d'identifiants du compte plateforme est lisible.
_m12o_registre_lisible() { [[ -r "$_M12O_REGISTRE_ENV" ]]; }

# _m12o_registre CHEMIN [ACCEPT] — GET sur l'API du registre (/v2/…), TLS vérifié contre la racine
# MédiSphère, identifiants du compte plateforme passés par un fichier anonyme (pas d'argument).
_m12o_registre() {
  local u="" m="" accept="${2:-application/json}"
  _m12o_registre_lisible || return 0
  # shellcheck disable=SC1090
  u="$(. "$_M12O_REGISTRE_ENV" && printf '%s' "${REGISTRE_UTILISATEUR:-}")"
  # shellcheck disable=SC1090
  m="$(. "$_M12O_REGISTRE_ENV" && printf '%s' "${REGISTRE_MOT_DE_PASSE:-}")"
  [[ -n "$u" && -n "$m" ]] || return 0
  curl -s --max-time "${WB_TIMEOUT:-5}" --cacert "$_M12O_RACINE" -H "Accept: $accept" \
    -K <(printf 'user = "%s:%s"\n' "$u" "$m") "https://$_M12O_REGISTRE/v2/$1" 2>/dev/null || true
}

# _m12o_etiquettes DÉPÔT — étiquettes d'un dépôt du registre, une par ligne.
_m12o_etiquettes() { _m12o_registre "$1/tags/list" | jq -r '.tags[]?' 2>/dev/null || true; }

# _m12o_plateformes DÉPÔT ÉTIQUETTE — plateformes « os/arch » de l'index désigné (hors attestations).
_m12o_plateformes() {
  _m12o_registre "$1/manifests/$2" \
    "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    | jq -r '.manifests[]? | select(.platform.os != "unknown") | "\(.platform.os)/\(.platform.architecture)"' 2>/dev/null \
    | sort -u || true
}

# _m12o_multi_plateformes DÉPÔT ÉTIQUETTE — l'index contient linux/amd64 ET linux/arm64.
_m12o_multi_plateformes() {
  local p
  p="$(_m12o_plateformes "$1" "$2")"
  grep -qx 'linux/amd64' <<<"$p" && grep -qx 'linux/arm64' <<<"$p"
}

# --- Archives OCI sur un hôte -------------------------------------------------------------------------

# _m12o_oci_plateformes HÔTE FICHIER — plateformes de l'index (ou des index imbriqués) d'une archive
# OCI distante ; lue en place par Python (lecture seule), sans extraction sur le disque.
_m12o_oci_plateformes() {
  # shellcheck disable=SC2016  # script Python évalué sur l'hôte distant
  remote "$1" "python3 - \"$2\"" 2>/dev/null <<'PY' || true
import json, sys, tarfile
try:
    t = tarfile.open(sys.argv[1].replace("~", __import__("os").path.expanduser("~"), 1))
except Exception:
    sys.exit(0)
def lire(nom):
    try:
        return json.load(t.extractfile(nom))
    except Exception:
        return None
def visiter(doc, vus):
    for m in (doc or {}).get("manifests", []):
        p = m.get("platform") or {}
        if p.get("os") and p.get("os") != "unknown":
            vus.add(p["os"] + "/" + p.get("architecture", "?"))
        if "index" in m.get("mediaType", "") or "manifest.list" in m.get("mediaType", ""):
            visiter(lire("blobs/sha256/" + m["digest"].split(":", 1)[1]), vus)
vus = set()
visiter(lire("index.json"), vus)
print("\n".join(sorted(vus)))
PY
}

# _m12o_oci_empreinte HÔTE FICHIER — empreinte du premier document de index.json d'une archive OCI.
_m12o_oci_empreinte() {
  remote "$1" "python3 - \"$2\"" 2>/dev/null <<'PY' || true
import json, os, sys, tarfile
try:
    t = tarfile.open(sys.argv[1].replace("~", os.path.expanduser("~"), 1))
    print(json.load(t.extractfile("index.json"))["manifests"][0]["digest"])
except Exception:
    pass
PY
}

# --- Dockerfiles ---------------------------------------------------------------------------------------

# _m12o_from_epingles DOCKERFILE — chaque FROM désigne une étape précédente, scratch, ou une image
# épinglée par empreinte (@sha256:) ; une image donnée par un ARG est résolue par sa valeur par défaut.
_m12o_from_epingles() {
  local df="$1" etapes img nom defaut ligne
  [[ -n "$df" ]] || return 1
  grep -Eiq '^FROM ' <<<"$df" || return 1
  etapes="$(grep -Eio '^FROM .* AS +[A-Za-z0-9_.-]+' <<<"$df" | awk '{print tolower($NF)}')"
  while read -r ligne; do
    img="$(sed -E 's/^FROM +//I; s/--platform=[^ ]+ +//I; s/ +AS +.*$//I; s/ +$//' <<<"$ligne")"
    if [[ "$img" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]; then
      nom="${BASH_REMATCH[1]}"
      defaut="$(sed -nE "s/^ARG +$nom=\"?([^\" ]+)\"?.*$/\1/p" <<<"$df" | head -n 1)"
      img="$defaut"
    fi
    [[ -n "$img" ]] || return 1
    [[ "${img,,}" == scratch ]] && continue
    grep -qx "${img,,}" <<<"$etapes" && continue
    [[ "$img" == *@sha256:* ]] || return 1
  done < <(grep -Ei '^FROM ' <<<"$df")
}

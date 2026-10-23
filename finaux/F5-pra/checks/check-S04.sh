# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes (développés à distance)
# shellcheck source-path=SCRIPTDIR
# check-S04.sh — F5-S04 « Les données partent à PAR2 » : archive de la base copiée à PAR2 et son âge,
# compartiments de s3-02, filer.sync et copie de MédiDoc, miroirs Git de adm02, images signées de reg02,
# mesures et alertes de retard, RB-354. Lecture seule (API S3 de s3-02 en wb-checks, SSH admin vers
# s3-02 et adm02, GitLab, kubectl wb-checks de k8s-par1, API v2 de reg02, API du Prometheus témoin).

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S04 — Les données partent à PAR2"
require_cmd ssh jq curl aws

_f5_s04_temoin="${WB_F5_PROM_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"

# --- Objets ------------------------------------------------------------------------------------------
_f5_s04_age="$(_f5p_s3_age_dernier cnpg-k8s-par1 "$_f5p_serveur_prod/wals/" 2>/dev/null || true)"
check_cmd "s3-02 : dernier WAL de $_f5p_serveur_prod copié il y a ${_f5_s04_age:-∞} s (≤ ${_f5p_retard_max} s)" \
  test -n "$_f5_s04_age" -a "${_f5_s04_age:-999999}" -le "$_f5p_retard_max"
_f5_s04_cpt="$(_f5p_s3_compartiments 2>/dev/null || true)"
for _f5_s04_b in cnpg-k8s-par1 velero-k8s-par1 openbao-instantanes mariadb-legacy-rdv tofu-par2 medidoc-documents; do
  check_cmd "s3-02 : compartiment $_f5_s04_b présent" grep -qx -- "$_f5_s04_b" <<<"$_f5_s04_cpt"
done
_f5_s04_sans_ci_cache() { [[ -n "$_f5_s04_cpt" ]] && ! grep -qx ci-cache <<<"$_f5_s04_cpt"; }
check_cmd "s3-02 : ci-cache n'est PAS copié (minimisation)" _f5_s04_sans_ci_cache
_f5_s04_medidoc_objets() { _f5p_s3 list-objects-v2 --bucket medidoc-documents --max-items 1 2>/dev/null | jq -e '(.Contents // []) | length > 0' >/dev/null; }
check_cmd "s3-02 : medidoc-documents contient des documents" _f5_s04_medidoc_objets

_f5_s04_s3hote="$_f5p_s302_hote"
check_cmd "s3-02 : les unités qui lancent weed filer.sync (simples ou instances d'un modèle @) sont actives" \
  _f5p_filersync_ok
check_cmd "s3-02 : une minuterie de copie de MédiDoc (nom contenant « medidoc ») est active" \
  _f5p_unite_active "$_f5_s04_s3hote" 'medidoc.*\.timer'
_f5_s04_medidoc_ok() {
  _f5p_ssh "$_f5_s04_s3hote" 'u=$(systemctl list-units --type=service --all --no-legend --plain | awk "{print \$1}" | grep -m1 medidoc); \
    [ -n "$u" ] && [ "$(systemctl show -p Result --value "$u")" = success ] && \
    [ "$(systemctl show -p ExecMainStatus --value "$u")" = 0 ] && \
    [ "$(systemctl show -p ExecMainExitTimestampMonotonic --value "$u")" != 0 ]'
}
check_cmd "s3-02 : la dernière copie de MédiDoc s'est terminée sans erreur" _f5_s04_medidoc_ok

# --- Miroirs Git ---------------------------------------------------------------------------------------
_f5_s04_miroir() {
  local p="$1" g m age
  g="$(gitlab_api "projects/$(_f5p_enc "$p")/repository/branches/main" 2>/dev/null)" || return 1
  m="$(_f5p_adm02 "git --git-dir='$_f5p_miroirs/$p.git' rev-parse --verify -q refs/heads/main" 2>/dev/null)" || return 1
  [[ "$(jq -r .commit.id <<<"$g")" == "$m" ]] && return 0
  # main a avancé dans GitLab depuis la dernière poussée : toléré si ce commit est récent.
  age="$(_f5p_age "$(jq -r .commit.committed_date <<<"$g")")" || return 1
  ((age <= _f5p_miroir_retard_max))
}
if gitlab_api "version" >/dev/null 2>&1; then
  for _f5_s04_p in $_F5P_PROJETS_MIROIRS; do
    check_cmd "miroir $_f5_s04_p sur adm02 : main identique à GitLab (ou retard < ${_f5p_miroir_retard_max} s)" \
      _f5_s04_miroir "$_f5_s04_p"
  done
else
  skip "comparaison des miroirs avec GitLab" "GitLab injoignable"
fi
check_cmd "adm02 : le compte miroir n'a pas de shell interactif" \
  _f5p_adm02 'getent passwd miroir | awk -F: "{print \$7}" | grep -Eq "git-shell|nologin|false"'

# --- Images ----------------------------------------------------------------------------------------------
_f5_s04_image="$(kube -n mediagenda-prod get pods -o json 2>/dev/null \
  | jq -r '[.items[].spec.containers[].image | select(test("/medisphere/mediagenda-api@sha256:"))] | first // empty' || true)"
_f5_s04_digest="${_f5_s04_image##*@}"
if [[ -n "$_f5_s04_image" ]]; then
  check_cmd "reg02 : medisphere/mediagenda-api@${_f5_s04_digest:7:12}… (déployée en prod) présente" \
    _f5p_reg02_digest_existe medisphere/mediagenda-api "$_f5_s04_digest"
  _f5_s04_signature() {
    local tag="sha256-${_f5_s04_digest#sha256:}"
    # Cosign : signature en étiquette « sha256-<hex>.sig » (format historique) ou en référent OCI 1.1.
    _f5p_reg02 "medisphere/mediagenda-api/tags/list" | jq -e --arg t "$tag" '.tags // [] | any(startswith($t))' >/dev/null && return 0
    _f5p_reg02 "medisphere/mediagenda-api/referrers/$_f5_s04_digest" | jq -e '(.manifests // []) | length > 0' >/dev/null
  }
  check_cmd "reg02 : une signature (ou un référent) accompagne cette image" _f5_s04_signature
else
  skip "image de MédiAgenda sur reg02" "aucun pod de mediagenda-prod avec une image par digest (kube de k8s-par1)"
fi

# --- Mesures, alertes, runbook --------------------------------------------------------------------------
check_cmd "mesures/retard-replication.md : retards des quatre flux (WAL, MédiDoc, miroirs, images)" \
  _f5p_doc mesures/retard-replication.md 'wal|cnpg' 'm(é|e)didoc' 'miroir|git' 'image|reg02' '[0-9]+ ?(s|min|h)\b'
check_cmd "RB-354 : suppression propagée, sauvegarde réelle, conduite en PRA et au retour" \
  _f5p_doc runbooks/RB-354-replication-par2.md 'suppr' 'sauvegarde' 'PRA|bascule|sinistre' 'retour'
_f5_s04_alertes() {
  curl -sf --max-time "$WB_TIMEOUT" "$_f5_s04_temoin/api/v1/rules?type=alert" \
    | jq -e '[.data.groups[].rules[] | select(((.name // "") + " " + (.query // "")) | test("par2|s3-02|reg02|adm02|miroir|r[ée]plication"; "i"))] | length >= 4' >/dev/null
}
check_cmd "Prometheus témoin : au moins quatre alertes sur la réplication vers PAR2" _f5_s04_alertes

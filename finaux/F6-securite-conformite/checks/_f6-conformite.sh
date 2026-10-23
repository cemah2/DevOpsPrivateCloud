# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f6-conformite.sh — fonctions partagées par les vérifications des phases 1 et 2 du final F6
# (check-S01 à check-S07 : préparer l'audit, auditer). Sourcé, jamais lancé seul. Préfixe _f6c_
# (les phases 3 à 5 ont leur propre fichier, _f6-incident.sh, préfixe _f6i_ : mêmes variables).
#
# Lecture seule :
#   - GitLab en GET (jeton des checks) : documents de docs/conformite/ de plateforme/medisphere, code de
#     plateforme/outils, pipelines planifiés ;
#   - Kubernetes par « kube » (compte wb-checks : jamais les Secrets) ;
#   - compartiment de preuves du RGW avec l'identité de LECTURE des checks (preuves-lecture : liste,
#     lecture, configuration du verrou ; jamais d'écriture) ;
#   - FreeIPA (ipa_ldap), Alertmanager (am_api), passerelles en SSH de lecture (sudo -n nft list).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée.
#
# Variables de lab/lab.env (défauts ci-dessous ; mêmes noms que _f6-incident.sh) ; préfixe WB_F6_ :
#   WB_F6_PROJET_DOC      projet GitLab de la doc MédiSphère       (défaut : plateforme/medisphere)
#   WB_F6_DOC             dossier de la conformité                 (défaut : docs/conformite)
#   WB_F6_PROJET_OUTILS   projet des outils ms-*                   (défaut : plateforme/outils)
#   WB_F6_RGW_URL         point d'accès S3 du RGW de ceph-par1     (défaut : https://rgw.par1.medisphere.internal)
#   WB_F6_PREUVES_BUCKET  compartiment de preuves verrouillé       (défaut : preuves-conformite)
#   WB_F6_PREUVES_ENV     identité S3 de LECTURE des preuves       (défaut : ~/.config/workbook/s3-preuves-conformite-lecture.env,
#                         variables AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY de l'utilisateur RGW preuves-lecture)
#   WB_F6_RETENTION_MIN   rétention par défaut minimale exigée en COMPLIANCE, en jours (défaut : 365)
#   WB_F6_LOT_AGE_MAX_H   âge maximal du dernier lot de preuves, en heures (défaut : 36)
#   WB_F6_PASSERELLES     passerelles de la bordure                (défaut : « gw01 gw02 »)
#   WB_F6_EXTERNES        identifiants des personnes d'AxiomDev    (défaut : « marc.vidal yanis.perrin »)
# + WB_GITLAB_*, WB_K8S_KUBECONFIG, WB_IPA_*, WB_AM_URL, WB_TIMEOUT (lab/lib/check-lib.sh).

_f6c_doc_projet="${WB_F6_PROJET_DOC:-plateforme/medisphere}"
_f6c_doc_dir="${WB_F6_DOC:-docs/conformite}"
_f6c_outils="${WB_F6_PROJET_OUTILS:-plateforme/outils}"
_f6c_rgw="${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}"
_f6c_bucket="${WB_F6_PREUVES_BUCKET:-preuves-conformite}"
_f6c_preuves_env="${WB_F6_PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-conformite-lecture.env}"
_f6c_retention_min="${WB_F6_RETENTION_MIN:-365}"
_f6c_lot_age_max="${WB_F6_LOT_AGE_MAX_H:-36}"
_f6c_passerelles="${WB_F6_PASSERELLES:-gw01 gw02}"
_f6c_externes="${WB_F6_EXTERNES:-marc.vidal yanis.perrin}"

# --- GitLab (lecture) ------------------------------------------------------------------------------

_f6c_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f6c_fichier PROJET CHEMIN [RÉF=main] — contenu brut du fichier.
_f6c_fichier() {
  gitlab_api "projects/$(_f6c_enc "$1")/repository/files/$(_f6c_enc "$2")/raw?ref=$(_f6c_enc "${3:-main}")"
}

# _f6c_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main.
_f6c_arbre() {
  local p page=1 r
  p="$(_f6c_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(_f6c_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f6c_contenu CHEMIN_RELATIF — contenu d'un document de docs/conformite/ (vide si absent).
_f6c_contenu() { _f6c_fichier "$_f6c_doc_projet" "$_f6c_doc_dir/$1" 2>/dev/null || true; }

# _f6c_contient TEXTE REGEX… — le texte (non vide) contient chaque motif (casse ignorée).
_f6c_contient() {
  local c="$1" m
  shift
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f6c_doc SOUS-DOSSIER MOTIF_NOM REGEX… — un document sous docs/conformite/SOUS-DOSSIER (« . » pour
# la racine) dont le nom correspond au motif contient chaque motif. Chemin trouvé : _F6C_TROUVE.
_F6C_TROUVE=""
_f6c_doc() {
  local d="$_f6c_doc_dir" motif="$2" f
  [[ "$1" != "." ]] && d="$d/$1"
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    if _f6c_contient "$(_f6c_fichier "$_f6c_doc_projet" "$f" 2>/dev/null || true)" "$@"; then
      _F6C_TROUVE="$f"
      return 0
    fi
  done < <(_f6c_arbre "$_f6c_doc_projet" "$d")
  return 1
}

# _f6c_compte_docs SOUS-DOSSIER MOTIF_NOM — nombre de documents dont le nom correspond.
_f6c_compte_docs() {
  local d="$_f6c_doc_dir/$1"
  _f6c_arbre "$_f6c_doc_projet" "$d" | awk -F/ -v m="$2" '$NF ~ m' | wc -l
}

# _f6c_pipelines_planifies_ok PROJET [N=5] — au moins un pipeline planifié réussi parmi les N derniers
# pipelines planifiés de main, et le plus récent n'a pas échoué.
_f6c_pipelines_planifies_ok() {
  gitlab_api "projects/$(_f6c_enc "$1")/pipelines?ref=main&source=schedule&per_page=${2:-5}" 2>/dev/null |
    jq -e 'length > 0 and any(.[]; .status == "success") and (.[0].status != "failed")' >/dev/null 2>&1
}

# --- ISO/IEC 27001:2022, annexe A : les 93 identifiants ---------------------------------------------
_f6c_mesures_iso() {
  local i
  for i in $(seq 1 37); do echo "5.$i"; done
  for i in $(seq 1 8); do echo "6.$i"; done
  for i in $(seq 1 14); do echo "7.$i"; done
  for i in $(seq 1 34); do echo "8.$i"; done
}

# _f6c_soa_manquantes TEXTE — affiche les mesures de l'annexe A absentes de la SoA, ou dont la ligne n'a
# pas de décision (Oui/Non dans la 3e colonne), ou exclues (Non) sans justification (4e colonne de
# moins de 15 caractères). Format attendu (énoncé F6-S01) :
#   | Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
#   | 5.1 | … | Oui | … | … | … |        (« A.5.1 » accepté)
_f6c_soa_manquantes() {
  local texte="$1"
  awk -F'|' '
    NR == FNR { attendu[$0] = 1; next }
    /^[[:space:]]*\|/ {
      id = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id); sub(/^A\./, "", id)
      if (!(id in attendu)) next
      app = $4; gsub(/^[[:space:]]+|[[:space:]]+$|\*/, "", app); app = tolower(app)
      just = $5; gsub(/^[[:space:]]+|[[:space:]]+$/, "", just)
      if (app ~ /^(oui|applicable)/) vu[id] = 1
      else if (app ~ /^(non|exclue?)/ && length(just) >= 15) vu[id] = 1
      else if (!(id in vu)) defaut[id] = 1
    }
    END { for (id in attendu) if (!(id in vu)) print id }' <(_f6c_mesures_iso) - <<<"$texte" | sort -V
}

# --- Compartiment de preuves (RGW, identité de LECTURE) ----------------------------------------------

_f6c_preuves_identite() { [[ -r "$_f6c_preuves_env" ]]; }

# _f6c_s3 ARGS… — commande aws avec l'identité de lecture (sous-shell : rien ne fuit dans le check).
_f6c_s3() {
  _f6c_preuves_identite || return 1
  (
    set -a
    # shellcheck disable=SC1090
    source "$_f6c_preuves_env"
    set +a
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
    aws --endpoint-url "$_f6c_rgw" "$@" 2>/dev/null
  )
}

# _f6c_verrou — configuration du verrouillage d'objets du compartiment (JSON).
_f6c_verrou() { _f6c_s3 s3api get-object-lock-configuration --bucket "$_f6c_bucket"; }

# _f6c_dernier_lot — préfixe du lot de preuves le plus récent (lots/AAAA/MM/JJ/<LOT>), vide si aucun.
_f6c_dernier_lot() {
  local mois
  for mois in "$(date -u +%Y/%m)" "$(date -u -d "$(date -u +%Y-%m-15) -1 month" +%Y/%m)"; do
    _f6c_s3 s3 ls --recursive "s3://$_f6c_bucket/lots/$mois/" | awk '$4 ~ /\/lot\.json$/ { sub(/\/lot\.json$/, "", $4); print $4 }'
  done | sort | tail -n 1
}

# --- Kubernetes ------------------------------------------------------------------------------------

_f6c_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _f6c_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f6c_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# --- Passerelles (lecture) -------------------------------------------------------------------------

# _f6c_bordure_conforme GW — chaque règle ACTIVE de « inet filter » qui porte un commentaire a ce
# commentaire dans la configuration persistée /etc/nftables.conf (une règle posée à chaud, commentée
# pour mémoire, n'y est pas). Code 2 si la passerelle n'est pas lisible.
_f6c_bordure_conforme() {
  local actif persiste c
  actif="$(remote "$1" "sudo -n nft list table inet filter" 2>/dev/null)" || return 2
  persiste="$(remote "$1" "sudo -n cat /etc/nftables.conf" 2>/dev/null)" || return 2
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    grep -qF -- "$c" <<<"$persiste" || return 1
  done < <(grep -o 'comment "[^"]*"' <<<"$actif" | sort -u)
  return 0
}

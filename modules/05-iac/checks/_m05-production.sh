# shellcheck shell=bash
# _m05-production.sh — fonctions partagées par les vérifications du palier 3 du module 05
# (check-E24 à check-E34). Sourcé par ces scripts, jamais lancé seul.
#
# Lecture seule : API GitLab en GET (jeton des checks), Proxmox lu en root sur pve01, S3 en
# lecture (identité tofu-etat de l'apprenant), OpenTofu seulement pour « plan -lock=false »
# (rien n'est écrit, aucun verrou n'est pris, aucun plan n'est enregistré).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
# Préfixe _m05p_ : pas de collision avec _m05-expert.sh (préfixe _m05x_).
#
# Variables de lab/lab.env utilisées : WB_PVE_HOST, WB_SRC, WB_DEPOT, WB_GITLAB_URL,
# WB_GITLAB_TOKEN_FILE, WB_S3_ENDPOINT.

_M05P_PROJET="projects/plateforme%2Finfra"
_M05P_INFRA="${WB_SRC:-$HOME/src}/infra"
_M05P_DOC="${WB_DEPOT:-$HOME/medisphere}/docs/socle"
_M05P_CFG="$HOME/.config/workbook"
_M05P_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M05P_BUCKET=tofu-state

# --- Environnement OpenTofu / S3 de l'apprenant (toujours dans un sous-shell) ------------------

# _m05p_env — charge les accès de adm01 comme outils/charger-acces.sh (E27), sans rien afficher.
_m05p_env() {
  local f
  set -a
  for f in "$_M05P_CFG/pve-tofu.env" "$_M05P_CFG/s3-tofu.env"; do
    # shellcheck source=/dev/null
    if [[ -r "$f" ]]; then source "$f"; fi
  done
  set +a
  # Chiffrement de l'état (M05-E27) : TF_ENCRYPTION (fournisseur de clé « pbkdf2 etat »), jamais
  # une variable TF_VAR_ (recopiée en clair dans chaque plan). Source de référence : le chargeur
  # de l'apprenant, outils/charger-acces.sh (il suit une rotation de phrase) ; à défaut, la
  # phrase de tofu-chiffrement.pass. Une valeur héritée du shell appelant est ignorée.
  unset TF_ENCRYPTION
  if [[ -r "$_M05P_INFRA/outils/charger-acces.sh" ]]; then
    # shellcheck source=/dev/null
    . "$_M05P_INFRA/outils/charger-acces.sh" >/dev/null 2>&1 || unset TF_ENCRYPTION
  fi
  if [[ -z "${TF_ENCRYPTION:-}" && -r "$_M05P_CFG/tofu-chiffrement.pass" ]]; then
    # Guillemets voulus : le contenu est du HCL.
    # shellcheck disable=SC2089,SC2090
    printf -v TF_ENCRYPTION 'key_provider "pbkdf2" "etat" { passphrase = "%s" }' "$(tr -d '\n' < "$_M05P_CFG/tofu-chiffrement.pass")"
    # shellcheck disable=SC2090
    export TF_ENCRYPTION
  fi
  export AWS_CA_BUNDLE="${AWS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  export TF_IN_AUTOMATION=1 TF_INPUT=0 NO_COLOR=1
}

# _m05p_aws args… — AWS CLI v2 vers s3-01 (lecture seulement).
_m05p_aws() {
  (
    _m05p_env
    exec aws --endpoint-url "$_M05P_S3" --output json "$@" </dev/null
  )
}

# _m05p_cle_existe CLÉ — l'objet existe (version courante, pas un marqueur de suppression).
_m05p_cle_existe() { _m05p_aws s3api head-object --bucket "$_M05P_BUCKET" --key "$1" >/dev/null 2>&1; }

# _m05p_objet_chiffre CLÉ — l'objet d'état est chiffré par OpenTofu (aucune ressource lisible).
_m05p_objet_chiffre() {
  local tmp rc=1
  tmp="$(mktemp)"
  if _m05p_aws s3api get-object --bucket "$_M05P_BUCKET" --key "$1" "$tmp" >/dev/null 2>&1 \
     && jq -e 'has("encrypted_data") and (has("resources") | not)' "$tmp" >/dev/null 2>&1; then
    rc=0
  fi
  rm -f "$tmp"
  return "$rc"
}

# _m05p_aucune_cle_prefixe PRÉFIXE — aucun objet sous ce préfixe (versions courantes).
_m05p_aucune_cle_prefixe() {
  local r
  r="$(_m05p_aws s3api list-objects-v2 --bucket "$_M05P_BUCKET" --prefix "$1" 2>/dev/null)" || return 1
  [[ -n "$r" ]] || return 0
  jq -e '(.Contents // []) | length == 0' >/dev/null 2>&1 <<<"$r"
}

# _m05p_nb_versions CLÉ — nombre de versions (hors marqueurs) de la clé exacte.
_m05p_nb_versions() {
  _m05p_aws s3api list-object-versions --bucket "$_M05P_BUCKET" --prefix "$1" 2>/dev/null \
    | jq -r --arg k "$1" '[(.Versions // [])[] | select(.Key == $k)] | length' 2>/dev/null
}

# _m05p_plan_vide DOSSIER — « tofu plan » sans verrou ni enregistrement : aucun changement.
_m05p_plan_vide() {
  [[ -d "$1" ]] || return 1
  (
    cd "$1" || exit 1
    _m05p_env
    exec tofu plan -lock=false -input=false -no-color -detailed-exitcode </dev/null
  ) >/dev/null 2>&1
}

# --- Proxmox (root sur pve01 : ne dépend d'aucun jeton de l'apprenant) ---------------------------

_M05P_VMS_CACHE=""
# _m05p_vms — JSON de /cluster/resources (VMs et templates), mis en cache pour le check.
_m05p_vms() {
  if [[ -z "$_M05P_VMS_CACHE" ]]; then
    _M05P_VMS_CACHE="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" \
      || _M05P_VMS_CACHE="indisponible"
    jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$_M05P_VMS_CACHE" || _M05P_VMS_CACHE="indisponible"
  fi
  [[ "$_M05P_VMS_CACHE" != "indisponible" ]] || return 1
  printf '%s\n' "$_M05P_VMS_CACHE"
}
# _m05p_charger — remplit le cache dans le shell courant (à appeler en tête des checks concernés).
_m05p_charger() { _m05p_vms >/dev/null || true; }

# _m05p_vm_filtre VMID 'filtre jq' — la VM existe et satisfait le filtre (champs de /cluster/resources).
_m05p_vm_filtre() {
  local v
  v="$(_m05p_vms)" || return 1
  jq -e --argjson v "$1" "any(.[]; .vmid == \$v and ($2))" >/dev/null <<<"$v"
}

# _m05p_vm_etiquettes VMID ÉTIQUETTE… — la VM tourne et porte toutes les étiquettes.
_m05p_vm_etiquettes() {
  local id="$1" e filtre='.status == "running"'
  shift
  for e in "$@"; do filtre+=" and ((.tags // \"\") | split(\";\") | index(\"$e\") != null)"; done
  _m05p_vm_filtre "$id" "$filtre"
}

# _m05p_aucune_vm DEBUT FIN — aucune VM dans la plage (échoue si pve01 ne répond pas).
_m05p_aucune_vm() {
  local v
  v="$(_m05p_vms)" || return 1
  jq -e --argjson a "$1" --argjson b "$2" 'all(.[]; .vmid < $a or .vmid > $b)' >/dev/null <<<"$v"
}

# _m05p_vm_conf VMID 'regex' — la configuration Proxmox de la VM correspond (qm config).
_m05p_vm_conf() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null | grep -Eq -- "$2"; }

# _m05p_tache_pve TYPE VMID — une tâche Proxmox TYPE (qmstart, qmdestroy…) réussie existe pour VMID.
#   Attention : une tâche qmclone porte le VMID de la source (template), pas celui de la copie.
_m05p_tache_pve() {
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/tasks --typefilter $1 --vmid $2 --limit 50 --output-format json" 2>/dev/null \
    | jq -e 'any(.[]; .status == "OK")' >/dev/null
}

# --- GitLab (jeton des checks, lecture) ------------------------------------------------------

# _m05p_api_ok "chemin" 'filtre jq' — la réponse de l'API GitLab satisfait le filtre.
_m05p_api_ok() {
  local r
  r="$(gitlab_api "$1" 2>/dev/null)" || return 1
  jq -e "$2" >/dev/null 2>&1 <<<"$r"
}

# _m05p_fichier_main CHEMIN — le fichier existe sur la branche main de plateforme/infra.
_m05p_fichier_main() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M05P_PROJET/repository/files/$p?ref=main" >/dev/null 2>&1
}

# _m05p_contenu_main CHEMIN — contenu brut du fichier sur main (vide si absent).
_m05p_contenu_main() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M05P_PROJET/repository/files/$p/raw?ref=main" 2>/dev/null || true
}

# _m05p_main_contient CHEMIN 'regex'… — le fichier sur main contient chaque motif (grep -E).
_m05p_main_contient() {
  local contenu m
  contenu="$(_m05p_contenu_main "$1")"
  [[ -n "$contenu" ]] || return 1
  shift
  for m in "$@"; do grep -Eq -- "$m" <<<"$contenu" || return 1; done
}

# _m05p_main_sans CHEMIN 'regex' — le fichier existe sur main et ne contient PAS le motif.
_m05p_main_sans() {
  local contenu
  contenu="$(_m05p_contenu_main "$1")"
  [[ -n "$contenu" ]] || return 1
  ! grep -Eq -- "$2" <<<"$contenu"
}

# _m05p_nb_fichiers_main DOSSIER 'regex du nom' MIN — au moins MIN fichiers du dossier (récursif) sur main.
_m05p_nb_fichiers_main() {
  local p n
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  n="$(gitlab_api "$_M05P_PROJET/repository/tree?path=$p&ref=main&recursive=true&per_page=100" 2>/dev/null \
    | jq -r --arg r "$2" '[.[] | select(.type == "blob" and (.name | test($r)))] | length' 2>/dev/null)" || return 1
  [[ "${n:-0}" -ge "$3" ]]
}

# _m05p_variable_ok CLÉ 'filtre jq' — une variable CI du projet satisfait le filtre
#   (champs : protected, masked, masked_and_hidden, variable_type, environment_scope…).
_m05p_variable_ok() {
  local r
  r="$(gitlab_api "$_M05P_PROJET/variables?per_page=100" 2>/dev/null)" || return 1
  jq -e --arg k "$1" "any(.[]; .key == \$k and ($2))" >/dev/null 2>&1 <<<"$r"
}

# _m05p_job_dans_pipelines 'requête pipelines' 'regex du nom' 'statuts jq' — dans les pipelines
#   renvoyés par la requête, un job du nom donné a un statut de la liste (ex. '["success"]').
_m05p_job_dans_pipelines() {
  local ids pid
  ids="$(gitlab_api "$_M05P_PROJET/pipelines?$1" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    gitlab_api "$_M05P_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -e --arg n "$2" --argjson s "$3" 'any(.[]; (.name | test($n)) and (.status as $x | $s | index($x)))' \
        >/dev/null && return 0
  done
  return 1
}

# _m05p_planif VALEUR — une planification active sur main porte la variable PLANIF=VALEUR.
_m05p_planif() {
  local ids id
  ids="$(gitlab_api "$_M05P_PROJET/pipeline_schedules?scope=active" 2>/dev/null \
    | jq -r '.[] | select(.ref == "main" or .ref == "refs/heads/main") | .id')" || return 1
  for id in $ids; do
    gitlab_api "$_M05P_PROJET/pipeline_schedules/$id" 2>/dev/null \
      | jq -e --arg v "$1" 'any(.variables[]?; .key == "PLANIF" and .value == $v)' >/dev/null && return 0
  done
  return 1
}

# _m05p_dernier_job_planifie 'regex du nom' — JSON du dernier job terminé de ce nom dans un
#   pipeline planifié de main (vide si aucun).
_m05p_dernier_job_planifie() {
  local ids pid j
  ids="$(gitlab_api "$_M05P_PROJET/pipelines?source=schedule&ref=main&per_page=30" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    j="$(gitlab_api "$_M05P_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -c --arg n "$1" '[.[] | select((.name | test($n)) and (.status == "success" or .status == "failed"))][0] // empty')" || continue
    if [[ -n "$j" ]]; then printf '%s\n' "$j"; return 0; fi
  done
  return 1
}

# _m05p_artefacts_conserves 'JSON du job' JOURS — le job a des artefacts conservés au moins JOURS.
_m05p_artefacts_conserves() {
  jq -e --argjson j "$2" 'def t: sub("\\.[0-9]+"; "") | fromdateiso8601;
    ((.artifacts // []) | length > 0) and .artifacts_expire_at != null and .finished_at != null
    and ((.artifacts_expire_at | t) - (.finished_at | t)) >= $j * 86400' >/dev/null 2>&1 <<<"$1"
}

# --- Poste et documentation --------------------------------------------------------------------

# _m05p_doc_contient FICHIER 'regex'… — le document contient chaque motif (grep -Ei).
_m05p_doc_contient() {
  local f="$1" m
  shift
  [[ -s "$f" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" "$f" || return 1; done
}

# _m05p_droits FICHIER MODE — le fichier existe avec exactement ce mode (ex. 600).
_m05p_droits() { [[ -f "$1" && "$(stat -c %a "$1")" == "$2" ]]; }

# shellcheck shell=bash
# _m05-commun.sh — fonctions partagées par les scripts de panne du module 05 (M05-E35 à M05-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_avert, WB_EX, remote…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande n'y échoue sans « || true ».
#
# 1. OpenTofu et S3 comme l'apprenant :
#      m05_tofu DOSSIER args…   lance tofu depuis DOSSIER avec ~/.config/workbook/pve-tofu.env,
#                               s3-tofu.env et la phrase de chiffrement (TF_VAR_phrase_chiffrement,
#                               lue dans tofu-chiffrement.pass) ; jamais d'interaction (TF_INPUT=0).
#      m05_aws args…            AWS CLI v2 vers s3-01 (endpoint, ancre TLS système, région factice).
# 2. Copie de travail ~/src/infra : m05_sauver / m05_noter / m05_poser / m05_restaurer
#    (sauvegarde exacte avant modification ; l'annulation ne restaure que ce qui est ENCORE dans
#    l'état posé par la panne : une réparation de l'apprenant n'est jamais écrasée).
# 3. État distant (compartiment tofu-state, versionné) : m05_s3_sauver copie l'objet courant et la
#    liste de ses versions dans /var/lib/workbook/M05-EXX/ (root, 700) AVANT toute modification ;
#    m05_s3_noter retient la version posée par la panne ; m05_s3_restaurer remet la version
#    d'avant SEULEMENT si la version courante est encore celle de la panne (sinon : réparation).
# 4. Règles nftables sur gw01 repérées par leur commentaire (et non par leur handle, qui change
#    après un rechargement complet du jeu de règles) : m05_nft_poser / m05_nft_retirer.
# 5. m05_essayer : essai des variantes (certaines sont sans effet selon les choix de l'apprenant).

_M05_INFRA="${WB_SRC:-$HOME/src}/infra"
_M05_SOCLE="$_M05_INFRA/socle"
_M05_ENVS="$_M05_INFRA/envs/lab-m05"
_M05_CFG="$HOME/.config/workbook"
_M05_S3="${WB_S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
_M05_BUCKET=tofu-state
_M05_CLE_SOCLE=socle/terraform.tfstate
_M05_CLE_ENVS=envs/lab-m05/terraform.tfstate
_M05_COFFRE=/var/lib/workbook
# shellcheck disable=SC2034  # utilisé par les scripts qui sourcent ce fichier
_M05_IP_S3=10.10.20.14

# ---------------------------------------------------------------------------
# État local et journal
# ---------------------------------------------------------------------------

# m05_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m05_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M05-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m05_journal EXX "message" — journal local (et /var/lib/workbook/pannes.log de adm01 si sudo -n).
m05_journal() {
  local ex="$1" d ligne
  shift
  d="$(m05_etat "$ex")"
  ligne="$(date -Is) $(hostname -s) [M05-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$d/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# m05_lire EXX NOM — contenu d'un petit fichier d'état (vide s'il n'existe pas).
m05_lire() {
  local f
  f="$(m05_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
# m05_ecrire EXX NOM VALEUR
m05_ecrire() { printf '%s\n' "$3" >"$(m05_etat "$1")/$2"; }

# ---------------------------------------------------------------------------
# OpenTofu et S3 comme l'apprenant
# ---------------------------------------------------------------------------

# m05_charger_env — à appeler dans un sous-shell : exporte l'environnement de travail OpenTofu.
m05_charger_env() {
  local f
  set -a
  for f in "$_M05_CFG/pve-tofu.env" "$_M05_CFG/s3-tofu.env"; do
    # shellcheck source=/dev/null
    if [[ -r "$f" ]]; then source "$f"; fi
  done
  set +a
  # La phrase de chiffrement de l'état (M05-E27) est lue dans son fichier, qui fait référence.
  if [[ -r "$_M05_CFG/tofu-chiffrement.pass" ]]; then
    TF_VAR_phrase_chiffrement="$(<"$_M05_CFG/tofu-chiffrement.pass")"
    export TF_VAR_phrase_chiffrement
  fi
  export AWS_CA_BUNDLE="${AWS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  # AWS CLI ≥ 2.23 calcule des sommes de contrôle CRC par défaut : inutile (et parfois refusé)
  # par un stockage compatible S3.
  export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
  export AWS_RESPONSE_CHECKSUM_VALIDATION="${AWS_RESPONSE_CHECKSUM_VALIDATION:-when_required}"
  export TF_IN_AUTOMATION=1 TF_INPUT=0 NO_COLOR=1
}

# m05_tofu DOSSIER args… — OpenTofu dans DOSSIER (racine d'une configuration de ~/src/infra).
m05_tofu() {
  local dir="$1"
  shift
  (
    cd "$dir" || exit 1
    m05_charger_env
    exec tofu "$@" </dev/null
  )
}

# m05_aws args… — AWS CLI vers s3-01, avec les identifiants de l'état (s3-tofu.env).
m05_aws() {
  (
    m05_charger_env
    exec aws --endpoint-url "$_M05_S3" --output json "$@" </dev/null
  )
}

# m05_dossier_cle CLÉ — dossier de configuration correspondant à une clé d'état.
m05_dossier_cle() {
  case "$1" in
    "$_M05_CLE_SOCLE") printf '%s\n' "$_M05_SOCLE" ;;
    *) printf '%s\n' "$_M05_ENVS" ;;
  esac
}

# m05_prerequis [socle] [envs] — outils, configurations initialisées, copie de travail propre,
# état lisible avec l'environnement standard (sinon les vérifications des pannes mentiraient).
m05_prerequis() {
  local c d nom
  for c in tofu aws jq git; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c (M05-E02, M05-E10)"; return 1; }
  done
  if ! git -C "$_M05_INFRA" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    wb_avert "$_M05_INFRA n'est pas un dépôt Git (clone de plateforme/infra, M05-E02)"
    return 1
  fi
  if [[ -z "${_M05_ASTREINTE:-}" && -n "$(git -C "$_M05_INFRA" status --porcelain 2>/dev/null)" ]]; then
    wb_avert "la copie de travail $_M05_INFRA contient des modifications non commitées : commite-les ou mets-les de côté (git stash) avant d'injecter une panne"
    return 1
  fi
  for nom in "$@"; do
    case "$nom" in
      socle) d="$_M05_SOCLE" ;;
      envs) d="$_M05_ENVS" ;;
      *) continue ;;
    esac
    if [[ ! -d "$d/.terraform" ]]; then
      wb_avert "$d n'est pas initialisé (tofu init)"
      return 1
    fi
    if ! m05_tofu "$d" state list >/dev/null 2>&1; then
      wb_avert "« tofu state list » échoue dans $d avec l'environnement standard (~/.config/workbook/pve-tofu.env, s3-tofu.env, tofu-chiffrement.pass) : le lab doit être sain avant l'injection"
      return 1
    fi
  done
}

# m05_show_json DOSSIER — état courant en JSON (tofu show -json), vide en cas d'échec.
m05_show_json() { m05_tofu "$1" show -json 2>/dev/null || true; }

# m05_vms_etat JSON — « adresse vm_id nom_de_bloc racine(0/1) » de chaque VM de l'état.
m05_vms_etat() {
  jq -r '
    def res: (.resources // []) + ((.child_modules // []) | map(res) | add // []);
    (.values.root_module // {}) as $r
    | ($r | res)[]
    | select(.mode == "managed" and .type == "proxmox_virtual_environment_vm")
    | "\(.address) \(.values.vm_id // 0) \(.name) \(if (.address | startswith("module.")) then 0 else 1 end)"' <<<"$1" 2>/dev/null || true
}

# m05_plan_dangereux DOSSIER [fichier_sortie] — 0 si le plan détruit ou remplace une VM du socle
# (VMID 1000-1099), ou s'il échoue sur prevent_destroy. Plan sans verrou, rien n'est écrit.
m05_plan_dangereux() {
  local dir="$1" sortie="${2:-/dev/null}" d plan out rc=0
  d="$(mktemp -d)"
  plan="$d/plan.bin"
  out="$(m05_tofu "$dir" plan -lock=false -no-color -input=false -out="$plan" 2>&1)" || rc=$?
  printf '%s\n' "$out" >"$sortie"
  if grep -q 'prevent_destroy' <<<"$out"; then
    rm -rf -- "$d"
    return 0
  fi
  if ((rc != 0)) || [[ ! -s "$plan" ]]; then
    rm -rf -- "$d"
    return 1
  fi
  rc=1
  if m05_tofu "$dir" show -json "$plan" 2>/dev/null | jq -e '
      [.resource_changes[]? | select(.type == "proxmox_virtual_environment_vm")
       | select(.change.actions | index("delete"))
       | select(((.change.before.vm_id // 0) >= 1000) and ((.change.before.vm_id // 0) <= 1099))]
      | length > 0' >/dev/null 2>&1; then
    rc=0
  fi
  rm -rf -- "$d"
  return "$rc"
}

# m05_plan_vide DOSSIER — 0 si le plan ne propose aucun changement (sans verrou).
m05_plan_vide() {
  m05_tofu "$1" plan -lock=false -no-color -input=false -detailed-exitcode >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Copie de travail (~/src/infra) et fichiers de ~/.config/workbook
# ---------------------------------------------------------------------------

# m05_empreinte CHEMIN — « absent », « lien:<cible> », « fichier:<sha256>:<mode> » ou « dossier:<sha256> ».
m05_empreinte() {
  local p="$1"
  if [[ -L "$p" ]]; then
    printf 'lien:%s\n' "$(readlink "$p")"
  elif [[ -f "$p" ]]; then
    printf 'fichier:%s:%s\n' "$(sha256sum <"$p" | cut -d' ' -f1)" "$(stat -c %a "$p")"
  elif [[ -d "$p" ]]; then
    printf 'dossier:%s\n' "$(cd "$p" && {
      find . -print0 | sort -z | xargs -0 -r stat -c '%n %a %s'
      find . -type f -print0 | sort -z | xargs -0 -r sha256sum
    } | sha256sum | cut -d' ' -f1)"
  else
    printf 'absent\n'
  fi
}

# m05_sauver EXX CHEMIN — une seule sauvegarde par chemin et par panne (jamais un état déjà cassé).
m05_sauver() {
  local ex="$1" p="$2" d n
  d="$(m05_etat "$ex")"
  mkdir -p "$d/sauvegardes"
  if [[ -f "$d/manifeste" ]] && awk -F'\t' -v p="$p" '$1 == p { f = 1 } END { exit !f }' "$d/manifeste"; then
    return 0
  fi
  if [[ -e "$p" || -L "$p" ]]; then
    n=1
    if [[ -f "$d/manifeste" ]]; then n="$(($(wc -l <"$d/manifeste") + 1))"; fi
    cp -a -- "$p" "$d/sauvegardes/$n" || return 1
    printf '%s\t%s\n' "$p" "$d/sauvegardes/$n" >>"$d/manifeste"
  else
    printf '%s\tABSENT\n' "$p" >>"$d/manifeste"
  fi
}

# m05_noter EXX CHEMIN — empreinte de l'état posé par la panne (sert à reconnaître une réparation).
m05_noter() {
  local d
  d="$(m05_etat "$1")"
  printf '%s\t%s\n' "$2" "$(m05_empreinte "$2")" >>"$d/injecte"
}

# m05_poser EXX CHEMIN — écrit l'entrée standard dans CHEMIN (sauvegarde, puis empreinte).
m05_poser() {
  local ex="$1" p="$2"
  m05_sauver "$ex" "$p" || return 1
  cat >"$p" || return 1
  m05_noter "$ex" "$p"
}

# m05_restaurer EXX — restaure ce qui est encore dans l'état posé par la panne. Idempotent.
m05_restaurer() {
  local ex="$1" d src dst attendu actuel
  d="$(m05_etat "$ex")"
  [[ -f "$d/manifeste" ]] || return 0
  while IFS=$'\t' read -r src dst; do
    [[ -n "$src" ]] || continue
    attendu=""
    if [[ -f "$d/injecte" ]]; then
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$d/injecte")"
    fi
    actuel="$(m05_empreinte "$src")"
    if [[ -n "$attendu" && "$actuel" != "$attendu" ]]; then
      m05_journal "$ex" "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
      continue
    fi
    rm -rf -- "$src"
    if [[ "$dst" != ABSENT ]]; then
      cp -a -- "$dst" "$src" || wb_avert "restauration impossible : $src (copie dans $dst)"
    fi
    m05_journal "$ex" "annulation : $src restauré"
  done <"$d/manifeste"
  rm -rf -- "$d/manifeste" "$d/injecte" "$d/sauvegardes"
}

# m05_fichier_modifie EXX CHEMIN — 0 si CHEMIN n'est plus dans l'état posé par la panne.
m05_fichier_modifie() {
  local d attendu
  d="$(m05_etat "$1")"
  [[ -f "$d/injecte" ]] || return 0
  attendu="$(awk -F'\t' -v s="$2" '$1 == s { v = $2 } END { print v }' "$d/injecte")"
  [[ -z "$attendu" || "$(m05_empreinte "$2")" != "$attendu" ]]
}

# ---------------------------------------------------------------------------
# Coffre des copies d'état sur adm01 (/var/lib/workbook/M05-EXX, root, 700)
# ---------------------------------------------------------------------------

# m05_coffre_deposer EXX FICHIER NOM — copie FICHIER dans le coffre (sudo), sinon le garde en local.
m05_coffre_deposer() {
  local ex="$1" f="$2" nom="$3" d
  if sudo -n true 2>/dev/null &&
    sudo -n install -d -m 700 "$_M05_COFFRE/M05-$ex" 2>/dev/null &&
    sudo -n install -m 600 "$f" "$_M05_COFFRE/M05-$ex/$nom" 2>/dev/null; then
    return 0
  fi
  d="$(m05_etat "$ex")/coffre"
  mkdir -p "$d" && chmod 700 "$d" && install -m 600 "$f" "$d/$nom"
}

# ---------------------------------------------------------------------------
# État distant : versions d'objets (compartiment versionné)
# ---------------------------------------------------------------------------

m05_versionnage_actif() {
  m05_aws s3api get-bucket-versioning --bucket "$_M05_BUCKET" 2>/dev/null | jq -e '.Status == "Enabled"' >/dev/null
}

# m05_s3_versions CLÉ — liste JSON des versions et marqueurs de suppression de CLÉ (clé exacte).
m05_s3_versions() {
  m05_aws s3api list-object-versions --bucket "$_M05_BUCKET" --prefix "$1" 2>/dev/null \
    | jq -c --arg k "$1" '{v: [(.Versions // [])[] | select(.Key == $k)], m: [(.DeleteMarkers // [])[] | select(.Key == $k)]}'
}

# m05_s3_dernier CLÉ — « version:<id> », « marqueur:<id> » ou « absent ».
m05_s3_dernier() {
  local j
  j="$(m05_s3_versions "$1")" || { printf 'erreur\n'; return 1; }
  [[ -n "$j" ]] || { printf 'erreur\n'; return 1; }
  jq -r '
    ([.v[] | select(.IsLatest) | "version:\(.VersionId)"] + [.m[] | select(.IsLatest) | "marqueur:\(.VersionId)"])
    | if length == 0 then "absent" else .[0] end' <<<"$j"
}

# m05_s3_sauver EXX CLÉ — AVANT toute modification : copie de l'objet courant et de la liste de ses
# versions dans le coffre ; retient la version courante (une seule fois par clé et par panne).
m05_s3_sauver() {
  local ex="$1" cle="$2" d nom dernier tmp
  d="$(m05_etat "$ex")"
  nom="$(tr '/' '_' <<<"$cle")"
  if [[ -f "$d/s3-avant" ]] && awk -F'\t' -v k="$cle" '$1 == k { f = 1 } END { exit !f }' "$d/s3-avant"; then
    return 0
  fi
  m05_versionnage_actif || { wb_avert "versionnage du compartiment $_M05_BUCKET inactif : panne refusée (M05-E11, M05-E29)"; return 1; }
  dernier="$(m05_s3_dernier "$cle")" || return 1
  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  m05_s3_versions "$cle" >"$tmp/versions.json"
  if [[ "$dernier" == version:* ]]; then
    m05_aws s3api get-object --bucket "$_M05_BUCKET" --key "$cle" "$tmp/objet.bin" >/dev/null 2>&1 \
      || { rm -rf -- "$tmp"; wb_avert "copie de s3://$_M05_BUCKET/$cle impossible : panne refusée"; return 1; }
    m05_coffre_deposer "$ex" "$tmp/objet.bin" "$nom.$(date +%Y%m%dT%H%M%S).bin" || { rm -rf -- "$tmp"; return 1; }
  fi
  m05_coffre_deposer "$ex" "$tmp/versions.json" "$nom.versions.json" || true
  rm -rf -- "$tmp"
  printf '%s\t%s\n' "$cle" "$dernier" >>"$d/s3-avant"
  m05_journal "$ex" "état distant $cle copié avant modification ($dernier)"
}

# m05_s3_noter EXX CLÉ — retient la version (ou le marqueur) courante après injection.
m05_s3_noter() {
  printf '%s\t%s\n' "$2" "$(m05_s3_dernier "$2")" >>"$(m05_etat "$1")/s3-injecte"
}

# m05_s3_restaurer EXX — pour chaque clé modifiée : si la version courante est encore celle posée
# par la panne, remet la version d'avant (suppression du marqueur, ou copie de la version d'avant
# comme nouvelle version courante). Sinon l'apprenant a réparé : rien n'est touché. Idempotent.
m05_s3_restaurer() {
  local ex="$1" d cle avant injecte actuel id
  d="$(m05_etat "$ex")"
  [[ -f "$d/s3-avant" ]] || return 0
  while IFS=$'\t' read -r cle avant; do
    [[ -n "$cle" ]] || continue
    injecte=""
    if [[ -f "$d/s3-injecte" ]]; then
      injecte="$(awk -F'\t' -v k="$cle" '$1 == k { v = $2 } END { print v }' "$d/s3-injecte")"
    fi
    actuel="$(m05_s3_dernier "$cle" 2>/dev/null || true)"
    if [[ "$actuel" == erreur || -z "$actuel" ]]; then
      wb_avert "état distant $cle illisible : restauration à faire à la main (copies dans $_M05_COFFRE/M05-$ex/)"
      continue
    fi
    if [[ "$actuel" == "$avant" ]]; then
      m05_journal "$ex" "annulation : $cle déjà dans sa version d'avant la panne"
      continue
    fi
    if [[ -n "$injecte" && "$actuel" != "$injecte" ]]; then
      m05_journal "$ex" "annulation : $cle modifié depuis l'injection ($actuel), laissé tel quel"
      continue
    fi
    if [[ "$actuel" == marqueur:* && "$avant" == version:* ]]; then
      id="${actuel#marqueur:}"
      m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "$cle" --version-id "$id" >/dev/null 2>&1 \
        && m05_journal "$ex" "annulation : marqueur de suppression $id de $cle retiré"
      if [[ "$(m05_s3_dernier "$cle" 2>/dev/null || true)" == "$avant" ]]; then continue; fi
    fi
    if [[ "$avant" == version:* ]]; then
      id="${avant#version:}"
      if m05_aws s3api copy-object --bucket "$_M05_BUCKET" --key "$cle" \
        --copy-source "$_M05_BUCKET/$cle?versionId=$id" >/dev/null 2>&1; then
        m05_journal "$ex" "annulation : $cle restauré depuis la version $id"
      else
        wb_avert "restauration de $cle impossible : version $id (copie dans $_M05_COFFRE/M05-$ex/)"
      fi
    elif [[ "$avant" == absent ]]; then
      m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "$cle" >/dev/null 2>&1 || true
      m05_journal "$ex" "annulation : $cle (absent avant la panne) supprimé"
    fi
  done <"$d/s3-avant"
  rm -f -- "$d/s3-avant" "$d/s3-injecte"
}

# ---------------------------------------------------------------------------
# pve01 : images dorées et étiquettes
# ---------------------------------------------------------------------------

# m05_tpl_gold — « VMID étiquettes_triées » des templates gold + debian13.
m05_tpl_gold() {
  remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null | jq -r '
    .[] | select(.template == 1)
    | ((.tags // "") | split(";") | map(select(length > 0)) | sort) as $t
    | select(($t | index("gold")) and ($t | index("debian13")))
    | "\(.vmid) \($t | join(";"))"' 2>/dev/null || true
}

# m05_tpl_current — VMID des templates gold + debian13 + current (un par ligne).
m05_tpl_current() { m05_tpl_gold | awk '$2 ~ /(^|;)current(;|$)/ { print $1 }'; }

# m05_tags_lire VMID — étiquettes triées, séparées par « ; ».
m05_tags_lire() {
  remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null | sed -n 's/^tags: //p' | tr ',;' '\n' | sed '/^$/d' | sort | paste -sd ';' -
}

# m05_tags_ecrire VMID ÉTIQUETTES — pose les étiquettes (journal sur pve01).
m05_tags_ecrire() {
  wb_exec "$WB_PVE_HOST" VMID="$1" TAGS="$2" >/dev/null <<'EOF'
if [ -n "$TAGS" ]; then qm set "$VMID" --tags "$TAGS" >/dev/null; else qm set "$VMID" --delete tags >/dev/null; fi
journal "étiquettes de $VMID : ${TAGS:-aucune}"
EOF
}

# m05_vmid_libre PRÉFÉRÉ… — premier VMID libre de la plage du module (2050-2059), préférés d'abord.
m05_vmid_libre() {
  local liste id
  liste="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null | jq -r '.[].vmid' 2>/dev/null)" || return 1
  for id in "$@" 2059 2058 2057 2056 2055 2054 2053 2052 2051 2050; do
    if ! grep -qx "$id" <<<"$liste"; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# gw01 : règles nftables temporaires repérées par leur commentaire
# ---------------------------------------------------------------------------

# m05_nft_poser EXX TABLE CHAÎNE "règle" "commentaire" — insère en tête de chaîne (inet TABLE).
m05_nft_poser() {
  local ex="$1"
  wb_exec gw01 TABLE="$2" CHAINE="$3" REGLE="$4" COMM="$5" >/dev/null <<'EOF' || return 1
nft list ruleset | grep -qF "comment \"$COMM\"" && exit 0
nft insert rule inet "$TABLE" "$CHAINE" $REGLE comment "\"$COMM\"" || exit 1
printf '%s\t%s\t%s\n' "$TABLE" "$CHAINE" "$COMM" >> "$WB_DIR/$WB_EX.nft-commentaires"
journal "règle insérée en tête de inet $TABLE $CHAINE : $REGLE ($COMM)"
EOF
  m05_ecrire "$ex" nft "$5"
}

# m05_nft_present COMMENTAIRE — 0 si une règle portant ce commentaire est chargée sur gw01.
m05_nft_present() {
  remote gw01 "sudo -n nft list ruleset" 2>/dev/null | grep -qF "comment \"$1\""
}

# m05_nft_retirer EXX — (WB_EX = M05-EXX) retire les règles posées par la panne (par commentaire, jamais par un
# handle mémorisé : après un rechargement complet, un ancien handle peut désigner une autre règle).
m05_nft_retirer() {
  wb_exec gw01 >/dev/null <<'EOF' || wb_avert "gw01 : retrait des règles temporaires à vérifier"
f="$WB_DIR/$WB_EX.nft-commentaires"
[ -f "$f" ] || exit 0
while IFS="$(printf '\t')" read -r t c comm; do
  for h in $(nft -a list chain inet "$t" "$c" 2>/dev/null | grep -F "comment \"$comm\"" | sed -n 's/.*# handle \([0-9][0-9]*\)$/\1/p'); do
    nft delete rule inet "$t" "$c" handle "$h" && journal "annulation : règle « $comm » retirée de inet $t $c"
  done
done < "$f"
rm -f "$f"
EOF
  rm -f -- "$(m05_etat "$1")/nft" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Hôtes distants : aide ajoutée au script envoyé (après le prélude de wb_exec)
# ---------------------------------------------------------------------------
read -r -d '' _M05_AIDE_DISTANTE <<'AIDE' || true
empreinte() {
  if [ -L "$1" ]; then
    printf 'lien:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'sha256:%s:%s\n' "$(sha256sum <"$1" | cut -d' ' -f1)" "$(stat -c %a "$1")"
  else
    printf 'absent\n'
  fi
}
noter_injecte() { printf '%s\t%s\n' "$1" "$(empreinte "$1")" >>"$WB_DIR/$WB_EX.injecte"; }
# garder_reparations — avant restaurer_fichiers : tout fichier qui n'est plus celui que la panne a
# posé est une réparation ; il sort du manifeste et reste tel quel.
garder_reparations() {
  local m="$WB_DIR/$WB_EX.manifeste" e="$WB_DIR/$WB_EX.injecte" t src dst attendu
  [ -f "$e" ] || return 0
  if [ -f "$m" ]; then
    t="$(mktemp)"
    while IFS="$(printf '\t')" read -r src dst; do
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$e")"
      if [ -n "$attendu" ] && [ "$(empreinte "$src")" != "$attendu" ]; then
        journal "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
        continue
      fi
      printf '%s\t%s\n' "$src" "$dst" >>"$t"
    done <"$m"
    cat "$t" >"$m"
    rm -f -- "$t"
  fi
  rm -f -- "$e"
}
# unite_8333 — unité systemd du processus qui écoute sur TCP/8333 (passerelle S3 de SeaweedFS).
unite_8333() {
  local pid
  pid="$(ss -Hltnp 'sport = :8333' 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  [ -n "$pid" ] || return 1
  ps -o unit= -p "$pid" 2>/dev/null | awk 'NF { print $1; exit }'
}
# option_weed NOM — valeur d'une option (-NOM=valeur ou -NOM valeur) du processus weed sur 8333.
option_weed() {
  local pid
  pid="$(ss -Hltnp 'sport = :8333' 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  [ -n "$pid" ] || return 1
  tr '\0' '\n' <"/proc/$pid/cmdline" | awk -v n="-$1" -v nn="--$1" '
    prendre { print; exit }
    index($0, n "=") == 1 { print substr($0, length(n) + 2); exit }
    index($0, nn "=") == 1 { print substr($0, length(nn) + 2); exit }
    $0 == n || $0 == nn { prendre = 1 }'
}
AIDE

# m05_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (root), avec l'aide ci-dessus.
m05_wb_exec() {
  { printf '%s\n' "$_M05_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# ---------------------------------------------------------------------------
# Essai de variantes : certaines peuvent être sans effet selon les choix de l'apprenant
# ---------------------------------------------------------------------------

# m05_essayer EXX NB DÉPART — appelle _m05EXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m05_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m05${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      m05_ecrire "$ex" variante "$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M05-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

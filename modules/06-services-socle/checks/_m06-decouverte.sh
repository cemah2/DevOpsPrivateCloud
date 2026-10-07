# shellcheck shell=bash
# _m06-decouverte.sh — fonctions partagées par les checks M06-E02 à M06-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m06d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
# Les clés et jetons sont lus dans leurs fichiers et passés à curl par l'entrée standard
# (-H @-) : ils n'apparaissent ni dans ps, ni dans la sortie.

_M06D_CFG="$HOME/.config/workbook"
_M06D_ANSIBLE="${WB_SRC:-$HOME/src}/ansible"
_M06D_INFRA="${WB_SRC:-$HOME/src}/infra"
_M06D_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M06D_PKI_RACINE="$HOME/pki-racine"
_M06D_DNS="10.10.20.10"

# _m06d_racine — chemin du certificat PUBLIC de la racine (dépôt Ansible, sinon ~/pki-racine).
_m06d_racine() {
  local f
  for f in "$_M06D_ANSIBLE/pki/medisphere-root-ca.crt" "$_M06D_PKI_RACINE/medisphere-root-ca.crt"; do
    [[ -s "$f" ]] && { echo "$f"; return 0; }
  done
  echo "/nonexistent/medisphere-root-ca.crt"
}

# _m06d_empreinte FICHIER_PEM — empreinte SHA-256 en hexadécimal minuscule sans « : »
# (forme affichée par « step certificate fingerprint »).
_m06d_empreinte() {
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null \
    | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f'
}

# _m06d_qm VMID — configuration Proxmox de la VM (qm config, lu en root sur pve01).
_m06d_qm() {
  remote "${WB_PVE_HOST:-pve01}" "qm config $1" 2>/dev/null || true
}

# _m06d_qm_a CONFIG CLE REGEX — la ligne « CLE: valeur » de la configuration correspond à la regex.
_m06d_qm_a() {
  grep -Eq -- "^$2: $3" <<<"$1"
}

# _m06d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m06d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m06d_dans_pool VMID — la VM est membre du pool lab.
_m06d_dans_pool() {
  remote "${WB_PVE_HOST:-pve01}" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m06d_declaree_iac VMID — un fichier .tf de l'état socle (copie de travail de plateforme/infra)
# déclare ce VMID (module vm-debian : vm_id = N ; ressource directe : vm_id = N).
_m06d_declaree_iac() {
  grep -rEq "vm_id[[:space:]]*=[[:space:]]*$1([^0-9]|$)" "$_M06D_INFRA/socle" --include='*.tf' 2>/dev/null
}

# _m06d_dig SERVEUR[:PORT] ARGS… — réponse courte (dig +short).
_m06d_dig() {
  local cible="$1" hote port
  shift
  hote="${cible%%:*}"
  port="53"
  [[ "$cible" == *:* ]] && port="${cible##*:}"
  dig +short +time=3 +tries=2 -p "$port" "@$hote" "$@" 2>/dev/null || true
}

# _m06d_dig_complet SERVEUR[:PORT] ARGS… — réponse complète (statut, drapeaux).
_m06d_dig_complet() {
  local cible="$1" hote port
  shift
  hote="${cible%%:*}"
  port="53"
  [[ "$cible" == *:* ]] && port="${cible##*:}"
  dig +time=3 +tries=2 -p "$port" "@$hote" "$@" 2>/dev/null || true
}

# _m06d_cert HÔTE PORT — certificat présenté (texte d'openssl x509 : émetteur, sujet, dates, SAN).
_m06d_cert() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" -servername "$1" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName -nameopt utf8,sep_comma_plus_space 2>/dev/null || true
}

# _m06d_chaine_ok HÔTE PORT [NOM] — la chaîne PRÉSENTÉE par le serveur (certificat + intermédiaires)
# se vérifie avec la SEULE racine MédiSphère (ni magasin système, ni CA provisoire) et le
# certificat est valable pour NOM (défaut : HÔTE).
_m06d_chaine_ok() {
  local hote="$1" port="$2" nom="${3:-$1}" d rc=1
  d="$(mktemp -d)"
  timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:$port" -servername "$nom" -showcerts </dev/null 2>/dev/null \
    | awk -v d="$d" '/BEGIN CERTIFICATE/ {n++; dedans=1} dedans {print > (d "/c" n ".pem")} /END CERTIFICATE/ {dedans=0}'
  if [[ -s "$d/c1.pem" ]]; then
    cat "$d"/c[2-9].pem >"$d/inter.pem" 2>/dev/null || true
    openssl verify -no-CApath -no-CAstore -CAfile "$(_m06d_racine)" -untrusted "$d/inter.pem" \
      -verify_hostname "$nom" "$d/c1.pem" >/dev/null 2>&1 && rc=0
  fi
  rm -rf "$d"
  return "$rc"
}

# _m06d_jours_restants TEXTE_X509 — jours avant expiration (0 si illisible).
_m06d_jours_restants() {
  local fin
  fin="$(sed -n 's/^notAfter=//p' <<<"$1")"
  [[ -n "$fin" ]] || { echo 0; return 0; }
  echo $(( ($(date -d "$fin" +%s) - $(date +%s)) / 86400 ))
}

# _m06d_fichier_main CHEMIN — le fichier existe sur la branche main de plateforme/ansible.
_m06d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$1" '$v | @uri')"
  gitlab_api "$_M06D_PROJET_ANSIBLE/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m06d_vault_critique CHEMIN — fichier de la copie de travail chiffré sous l'identité « critique ».
_m06d_vault_critique() {
  # shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête
  head -n 1 "$_M06D_ANSIBLE/$1" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;1\.2;AES256;critique'
}

# _m06d_mode FICHIER MODE — le fichier existe, n'est pas vide, et a exactement ce mode.
_m06d_mode() {
  [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == "$2" ]]
}

# _m06d_pdns_api CHEMIN — code HTTP d'un GET sur l'API PowerDNS avec la clé de
# ~/.config/workbook/powerdns-api.env (PDNS_SERVER_URL, PDNS_API_KEY ; lu sans être exécuté).
_m06d_pdns_api() {
  local f="$_M06D_CFG/powerdns-api.env" url cle
  [[ -r "$f" ]] || { echo 000; return 0; }
  url="$(sed -nE 's/^(export[[:space:]]+)?PDNS_SERVER_URL="?([^"]*)"?.*/\2/p' "$f" | head -n 1)"
  cle="$(sed -nE 's/^(export[[:space:]]+)?PDNS_API_KEY="?([^"]*)"?.*/\2/p' "$f" | head -n 1)"
  [[ -n "$url" && -n "$cle" ]] || { echo 000; return 0; }
  printf 'X-API-Key: %s\n' "$cle" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --noproxy '*' -H @- \
      "${url%/}/api/v1/servers/localhost/$1" || true
}

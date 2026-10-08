# shellcheck shell=bash
# _m11-commun.sh — fonctions partagées par les scripts de panne du module 11 (M11-E19 à M11-E22).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Périmètre (PLAN §4.9, pannes du bloc B) : pxe01, Kea (dns01, dns02), relais du VLAN 60 sur les
# passerelles (gw01, gw02 : lignes du VLAN 60 seulement), maas01 ; sur pve01, uniquement le compte
# wb-maas@pve, son jeton, le rôle WBMaas et le nom des VMs 2112-2115. Jamais l'iLO de hp01, pbs01,
# ni le réseau de pve01.
#
# 1. Hôtes distants : _M11_AIDE_DISTANTE est préfixée aux scripts envoyés par m11_wb_exec. Elle
#    fournit : empreinte / noter_injecte / garder_reparations (fichiers remplacés ou dont les droits
#    changent : une réparation n'est jamais écrasée) ; subst / defaire_subst (modification
#    « chirurgicale » mémorisée, défaite seulement là où le texte posé est encore présent) ;
#    service_kea4, nginx_racine, nginx_certificat, tftp_racine, tftp_lire (sonde TFTP en Python).
# 2. Outils locaux (adm01) : m11_etat / m11_journal / m11_lire / m11_ecrire, m11_existe,
#    m11_essayer (variantes sans effet sur ce lab : on passe à la suivante), m11_maas (API de MAAS
#    signée OAuth 1.0 PLAINTEXT, clé lue dans un fichier, jamais en argument).

_M11_ZONE="par1.medisphere.internal"
_M11_PXE_FQDN="pxe01.$_M11_ZONE"
_M11_PXE_IP=10.10.60.10
_M11_MAAS_URL="${WB_MAAS_URL:-http://10.10.60.11:5240/MAAS}"
_M11_MAAS_CLE="${WB_MAAS_APIKEY_FILE:-$HOME/.config/workbook/maas-api.key}"
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M11_VMID=([pxe01]=2111 [bm01]=2112 [bm02]=2113 [bm03]=2114 [bm04]=2115 [maas01]=2116)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m11_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m11_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M11-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m11_journal EXX "message" — journal local de la panne.
m11_journal() {
  local ex="$1" d
  shift
  d="$(m11_etat "$ex")"
  printf '%s %s [M11-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m11_lire EXX CLÉ / m11_ecrire EXX CLÉ VALEUR — petites valeurs d'état (cible tirée, valeur d'origine…).
m11_lire() {
  local f
  f="$(m11_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m11_ecrire() {
  local d
  d="$(m11_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}
m11_effacer() {
  local d
  d="$(m11_etat "$1")"
  rm -f -- "$d/$2"
}

# m11_existe HÔTE — l'hôte répond en SSH (gw02, dns02, maas01 selon l'avancement).
m11_existe() {
  remote "$1" true >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# API de MAAS (OAuth 1.0, signature PLAINTEXT) — clé « consommateur:jeton:secret » (maas apikey)
# ---------------------------------------------------------------------------

# m11_maas MÉTHODE CHEMIN [données…] — affiche le corps et termine par une ligne « HTTP <code> ».
#   CHEMIN relatif à $_M11_MAAS_URL/api/2.0/ (ex. « machines/ », « machines/abc123/?op=query_power_state »).
#   L'en-tête d'authentification est écrit dans un fichier temporaire 600 (jamais dans argv).
m11_maas() {
  local methode="$1" chemin="$2" ck tk ts entete rc=0
  shift 2
  [[ -r "$_M11_MAAS_CLE" ]] || { echo "HTTP 000"; return 1; }
  IFS=: read -r ck tk ts <"$_M11_MAAS_CLE"
  entete="$(mktemp)"
  chmod 600 "$entete"
  printf 'Authorization: OAuth oauth_version="1.0", oauth_signature_method="PLAINTEXT", oauth_consumer_key="%s", oauth_token="%s", oauth_signature="&%s", oauth_nonce="%s", oauth_timestamp="%s"\n' \
    "$ck" "$tk" "$ts" "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" "$(date +%s)" >"$entete"
  curl -sS --max-time 30 -X "$methode" -H @"$entete" -w '\nHTTP %{http_code}\n' "$@" \
    "$_M11_MAAS_URL/api/2.0/$chemin" 2>/dev/null || rc=$?
  rm -f -- "$entete"
  return "$rc"
}

# m11_maas_json MÉTHODE CHEMIN [données…] — corps seul si le code HTTP est 2xx, sinon échec.
m11_maas_json() {
  local sortie code
  sortie="$(m11_maas "$@")" || return 1
  code="$(tail -n 1 <<<"$sortie" | sed -nE 's/^HTTP ([0-9]{3})$/\1/p')"
  [[ "$code" =~ ^2 ]] || return 1
  sed '$d' <<<"$sortie"
}

# m11_maas_bm — lignes « system_id nom » des machines bm01-bm04 connues de MAAS.
m11_maas_bm() {
  m11_maas_json GET "machines/" | jq -r '.[] | select(.hostname | test("^bm0[1-4]$")) | "\(.system_id) \(.hostname)"' 2>/dev/null
}

# m11_maas_alim_ok SYSTEM_ID — 0 si MAAS interroge avec succès l'alimentation (état on ou off).
m11_maas_alim_ok() {
  local etat
  etat="$(m11_maas_json GET "machines/$1/?op=query_power_state" | jq -r '.state // empty' 2>/dev/null)"
  [[ "$etat" == on || "$etat" == off ]]
}

# ---------------------------------------------------------------------------
# Variantes sans effet sur un lab donné
# ---------------------------------------------------------------------------

# m11_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
m11_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M11-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

# ---------------------------------------------------------------------------
# Hôtes distants : aide ajoutée au script envoyé (après le prélude de wb_exec)
# ---------------------------------------------------------------------------
read -r -d '' _M11_AIDE_DISTANTE <<'AIDE' || true
# empreinte CHEMIN — « lien:<cible> », « sha256:<somme>:<mode>:<propriétaire> » ou « absent »
empreinte() {
  if [ -L "$1" ]; then
    printf 'lien:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'sha256:%s:%s\n' "$(sha256sum <"$1" | cut -d' ' -f1)" "$(stat -c '%a:%U:%G' "$1")"
  else
    printf 'absent\n'
  fi
}
noter_injecte() { printf '%s\t%s\n' "$1" "$(empreinte "$1")" >>"$WB_DIR/$WB_EX.injecte"; }
# garder_reparations — avant restaurer_fichiers : tout fichier qui n'est plus celui que la panne a
# posé (contenu, droits ou propriétaire) est une réparation ; il sort du manifeste et reste tel quel.
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
# copie_securite FICHIER — copie unique, hors manifeste (consultation en cas de doute).
copie_securite() {
  local c="$WB_DIR/$WB_EX.$(printf '%s' "$1" | tr '/' '_').copie"
  [ -e "$c" ] || cp -a "$1" "$c"
}
# subst FICHIER REGEX REMPLACEMENT — première correspondance (Python, re.M), mémorisée.
subst() {
  [ -f "$1" ] || return 10
  copie_securite "$1"
  python3 - "$1" "$2" "$3" "$WB_DIR/$WB_EX.subst" <<'PY'
import base64, re, sys
f, rx, repl, m = sys.argv[1:5]
t = open(f, encoding="utf-8").read()
mo = re.search(rx, t, re.M)
if not mo:
    sys.exit(10)
avant, apres = mo.group(0), mo.expand(repl)
if avant == apres or not apres:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(t[:mo.start()] + apres + t[mo.end():])
b = lambda s: base64.b64encode(s.encode()).decode()
with open(m, "a", encoding="utf-8") as h:
    h.write("%s\t%s\t%s\n" % (f, b(avant), b(apres)))
PY
}
# defaire_subst — dans l'ordre inverse : remet le texte d'origine là où le texte posé est encore là ;
# affiche les fichiers rétablis (pour relancer les services concernés).
defaire_subst() {
  local m="$WB_DIR/$WB_EX.subst"
  [ -f "$m" ] || return 0
  python3 - "$m" <<'PY' | while IFS="$(printf '\t')" read -r etat fichier; do
import base64, sys
d = lambda s: base64.b64decode(s).decode()
lignes = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
for f, avant, apres in reversed(lignes):
    avant, apres = d(avant), d(apres)
    try:
        t = open(f, encoding="utf-8").read()
    except OSError:
        print("absent\t" + f)
        continue
    if apres in t:
        open(f, "w", encoding="utf-8").write(t.replace(apres, avant, 1))
        print("retabli\t" + f)
    else:
        print("repare\t" + f)
PY
    case "$etat" in
      retabli) journal "annulation : $fichier rétabli"; printf '%s\n' "$fichier" ;;
      repare) journal "annulation : $fichier modifié depuis l'injection (réparation), laissé tel quel" ;;
      *) journal "annulation : $fichier introuvable" ;;
    esac
  done
  rm -f -- "$m" "$WB_DIR/$WB_EX".*.copie
}
# service_kea4 — nom réel de l'unité kea-dhcp4 (paquets ISC : isc-kea-dhcp4-server).
service_kea4() {
  for s in isc-kea-dhcp4-server kea-dhcp4-server kea-dhcp4; do
    if systemctl cat "$s" >/dev/null 2>&1; then echo "$s"; return 0; fi
  done
  return 1
}
# kea_relancer — teste la configuration puis redémarre Kea (code ≠ 0 si la configuration est refusée).
kea_relancer() {
  local s
  s="$(service_kea4)" || return 1
  kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null 2>&1 || return 1
  systemctl restart "$s"
  sleep 2
  systemctl is-active -q "$s"
}
# nginx_racine — racine (root) du serveur nginx de pxe01 (premier « root » de la configuration chargée).
nginx_racine() {
  nginx -T 2>/dev/null | sed -nE 's/^[[:space:]]*root[[:space:]]+([^;]+);.*/\1/p' | head -n 1
}
# nginx_certificat — fichier ssl_certificate du serveur HTTPS (vide si pas de HTTPS).
nginx_certificat() {
  nginx -T 2>/dev/null | sed -nE 's/^[[:space:]]*ssl_certificate[[:space:]]+([^;]+);.*/\1/p' | head -n 1
}
nginx_cle() {
  nginx -T 2>/dev/null | sed -nE 's/^[[:space:]]*ssl_certificate_key[[:space:]]+([^;]+);.*/\1/p' | head -n 1
}
# tftp_racine — dossier servi par tftpd-hpa.
tftp_racine() {
  sed -nE 's/^[[:space:]]*TFTP_DIRECTORY="?([^"]*)"?.*/\1/p' /etc/default/tftpd-hpa 2>/dev/null | tail -n 1
}
# tftp_lire IP FICHIER — 0 si le serveur TFTP envoie le premier bloc de données (opcode 3).
tftp_lire() {
  python3 - "$1" "$2" <<'PY'
import socket, sys
ip, f = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(4)
s.sendto(b"\x00\x01" + f.encode() + b"\x00octet\x00", (ip, 69))
try:
    data, _ = s.recvfrom(1024)
except OSError:
    sys.exit(1)
sys.exit(0 if data[:2] == b"\x00\x03" else 1)
PY
}
AIDE

# m11_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (SSH, root), avec l'aide ci-dessus.
m11_wb_exec() {
  { printf '%s\n' "$_M11_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

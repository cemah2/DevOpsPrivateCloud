# shellcheck shell=bash
# _m06-commun.sh — fonctions partagées par les scripts de panne du module 06 (M06-E35 à M06-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# 1. Hôtes distants : _M06_AIDE_DISTANTE est préfixée aux scripts envoyés par m06_wb_exec (SSH) et
#    m06_wb_exec_invite (agent QEMU, quand SSH est en cause). Elle fournit :
#      empreinte / noter_injecte / garder_reparations  remplacement de fichiers entiers : avant
#                       restaurer_fichiers, tout fichier qui n'est plus celui posé par la panne est une
#                       réparation de l'apprenant et reste tel quel ;
#      subst FICHIER REGEX REMPLACEMENT   modification « chirurgicale » d'un fichier de configuration
#                       (première correspondance, regex Python multiligne) ; le texte d'origine et le
#                       texte posé sont mémorisés (code 10 si rien ne correspond) ;
#      defaire_subst    remet le texte d'origine là où le texte posé est ENCORE présent, laisse le
#                       reste (réparation) ; affiche les fichiers rétablis (pour relancer les services).
#    Les modifications par subst composent entre pannes (astreinte M06-E43 : deux pannes peuvent
#    toucher le même fichier, chacune ne défait que son propre texte).
# 2. Copie de travail ~/src/ansible (M06-E40) : m06_sauver / m06_poser / m06_noter / m06_restaurer,
#    même logique que le module 04 (état dans ~/.local/state/workbook/M06-EXX/).
# 3. Outils locaux (adm01) : m06_ansible (Ansible comme l'apprenant), m06_dig_statut, m06_curl_code,
#    m06_ssh_ok, m06_fermer_ssh, m06_essayer (variantes sans effet sur ce lab : on passe à la suivante).

_M06_SRC="${WB_SRC:-$HOME/src}"
_M06_ANSIBLE="$_M06_SRC/ansible"
_M06_CFG="$HOME/.config/workbook"
_M06_NETBOX_URL="${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}"
_M06_ZONE="par1.medisphere.internal"
# VM jetable des pannes du module (sonde DHCP de M06-E36), plage env-m06 2060-2069
_M06_VMID_SONDE=2069

# Adresses (PLAN.md §4.5) et VMID du socle
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M06_IP=([gw01]=10.10.10.1 [adm01]=10.10.10.10 [dns01]=10.10.20.10 [ca01]=10.10.20.11
  [git01]=10.10.20.12 [nbx01]=10.10.20.13 [s3-01]=10.10.20.14 [runner01]=10.10.20.15 [dns02]=10.10.20.16)
# shellcheck disable=SC2034
declare -A _M06_VMID=([gw01]=1000 [adm01]=1001 [dns01]=1002 [ca01]=1003 [git01]=1004 [nbx01]=1005
  [s3-01]=1006 [runner01]=1007 [dns02]=1008)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m06_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m06_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M06-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m06_journal EXX "message" — journal local de la panne (et /var/lib/workbook/pannes.log si sudo -n).
m06_journal() {
  local ex="$1" d ligne
  shift
  d="$(m06_etat "$ex")"
  ligne="$(date -Is) $(hostname -s) [M06-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$d/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# m06_lire EXX CLÉ / m06_ecrire EXX CLÉ VALEUR — petites valeurs d'état (cible tirée, compte…).
m06_lire() {
  local f
  f="$(m06_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m06_ecrire() {
  local d
  d="$(m06_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}

# ---------------------------------------------------------------------------
# Copie de travail ~/src/ansible (sauvegarde et restauration exactes, comme au module 04)
# ---------------------------------------------------------------------------

# m06_empreinte CHEMIN — « absent », « lien:<cible> », « fichier:<sha256>:<mode> » ou « dossier:<sha256> ».
m06_empreinte() {
  local p="$1"
  if [[ -L "$p" ]]; then
    printf 'lien:%s\n' "$(readlink "$p")"
  elif [[ -f "$p" ]]; then
    printf 'fichier:%s:%s\n' "$(sha256sum <"$p" | cut -d' ' -f1)" "$(stat -c %a "$p")"
  elif [[ -d "$p" ]]; then
    printf 'dossier:%s\n' "$(cd "$p" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)"
  else
    printf 'absent\n'
  fi
}

# m06_sauver EXX CHEMIN — une seule sauvegarde par chemin et par panne (jamais un état déjà cassé).
m06_sauver() {
  local ex="$1" p="$2" d n
  d="$(m06_etat "$ex")"
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

# m06_noter EXX CHEMIN — empreinte de l'état posé par la panne (sert à reconnaître une réparation).
m06_noter() {
  local d
  d="$(m06_etat "$1")"
  printf '%s\t%s\n' "$2" "$(m06_empreinte "$2")" >>"$d/injecte"
}

# m06_restaurer EXX — restaure ce qui est encore dans l'état posé par la panne. Idempotent.
m06_restaurer() {
  local ex="$1" d src dst attendu actuel
  d="$(m06_etat "$ex")"
  [[ -f "$d/manifeste" ]] || return 0
  while IFS=$'\t' read -r src dst; do
    [[ -n "$src" ]] || continue
    attendu=""
    if [[ -f "$d/injecte" ]]; then
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$d/injecte")"
    fi
    actuel="$(m06_empreinte "$src")"
    if [[ -n "$attendu" && "$actuel" != "$attendu" ]]; then
      m06_journal "$ex" "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
      continue
    fi
    rm -rf -- "$src"
    if [[ "$dst" != ABSENT ]]; then
      cp -a -- "$dst" "$src" || wb_avert "restauration impossible : $src (copie dans $dst)"
    fi
    m06_journal "$ex" "annulation : $src restauré"
  done <"$d/manifeste"
  rm -rf -- "$d/manifeste" "$d/injecte" "$d/sauvegardes"
}

# ---------------------------------------------------------------------------
# Outils locaux (adm01)
# ---------------------------------------------------------------------------

# m06_ansible COMMANDE [args…] — ansible-inventory, ansible-playbook… comme l'apprenant : racine du
# projet, environnement uv du projet, accès Proxmox de M04 et jeton NetBox (NETBOX_TOKEN de ton
# environnement, à défaut le jeton en lecture des checks ; NETBOX_API à défaut WB_NETBOX_URL).
m06_ansible() {
  local cmd="$1"
  shift
  (
    cd "$_M06_ANSIBLE" || exit 1
    if [[ -r "$_M06_CFG/pve-ansible.env" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$_M06_CFG/pve-ansible.env"
      set +a
    fi
    if [[ -z "${NETBOX_TOKEN:-}" && -r "${WB_NETBOX_TOKEN_FILE:-$_M06_CFG/netbox-checks.token}" ]]; then
      NETBOX_TOKEN="$(<"${WB_NETBOX_TOKEN_FILE:-$_M06_CFG/netbox-checks.token}")"
      export NETBOX_TOKEN
    fi
    export NETBOX_API="${NETBOX_API:-$_M06_NETBOX_URL}"
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    if [[ -x ".venv/bin/$cmd" ]]; then
      exec ".venv/bin/$cmd" "$@" </dev/null
    fi
    exec uv run --frozen --quiet "$cmd" "$@" </dev/null
  )
}

# m06_inv_netbox — chemin (relatif au projet) du fichier d'inventaire NetBox (M06-E12).
m06_inv_netbox() {
  local f
  f="$(grep -rlE '^[[:space:]]*plugin:[[:space:]]*["'\'']?netbox\.netbox\.nb_inventory' \
    "$_M06_ANSIBLE/inventories" 2>/dev/null | sort | head -n 1)"
  [[ -n "$f" ]] || return 1
  printf '%s\n' "${f#"$_M06_ANSIBLE"/}"
}

# m06_hotes_groupe JSON GROUPE — hôtes d'un groupe (récursivement) d'une sortie ansible-inventory --list.
m06_hotes_groupe() {
  jq -r --arg g "$2" '. as $inv
    | def h($g): ($inv[$g].hosts // []) + (($inv[$g].children // []) | map(h(.)) | add // []);
    h($g) | unique | .[]' <<<"$1" 2>/dev/null
}

# m06_dig_statut SERVEUR NOM TYPE [options dig…] — affiche le statut DNS (NOERROR, NXDOMAIN, SERVFAIL,
# REFUSED…) ou TIMEOUT. Interroge directement le serveur, sans le résolveur système.
m06_dig_statut() {
  local srv="$1" nom="$2" type="$3" o s
  shift 3
  o="$(dig +time=3 +tries=1 "@$srv" "$nom" "$type" "$@" 2>&1)" || true
  s="$(sed -nE 's/.*status: ([A-Z]+).*/\1/p' <<<"$o" | head -n 1)"
  printf '%s\n' "${s:-TIMEOUT}"
}

# m06_dig_court SERVEUR NOM TYPE — réponse courte (+short).
m06_dig_court() {
  dig +short +time=3 +tries=1 "@$1" "$2" "$3" 2>/dev/null || true
}

# m06_resout_bien NOM IP [SERVEUR] — 0 si le résolveur (dns01 par défaut) répond IP pour NOM.
m06_resout_bien() {
  m06_dig_court "${3:-10.10.20.10}" "$1" A | grep -qx "$2"
}

# m06_curl_code FQDN IP [CHEMIN] — code de sortie de curl en HTTPS vérifié, sans dépendre du DNS
# (60 = certificat non vérifiable, 35 = échec TLS, 7 = connexion refusée, 0 = OK).
m06_curl_code() {
  local rc=0
  curl -sS -o /dev/null --max-time 10 --resolve "$1:443:$2" "https://$1${3:-/}" 2>/dev/null || rc=$?
  printf '%s\n' "$rc"
}

# m06_ssh_ok HÔTE — 0 si une NOUVELLE connexion SSH (sans multiplexage) aboutit.
m06_ssh_ok() {
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1
}

# m06_fermer_ssh HÔTE… — ferme les connexions maîtresses (multiplexage de ~/.ssh/config), sinon
# une panne SSH reste masquée par une connexion déjà ouverte.
m06_fermer_ssh() {
  local h
  for h in "$@"; do
    ssh -O exit -o BatchMode=yes "$h" >/dev/null 2>&1 || true
    if [[ -n "${_M06_IP[$h]:-}" ]]; then
      ssh -O exit -o BatchMode=yes "${_M06_IP[$h]}" >/dev/null 2>&1 || true
      ssh -O exit -o BatchMode=yes "admin@${_M06_IP[$h]}" >/dev/null 2>&1 || true
    fi
  done
}

# m06_agent_ok VMID — l'agent QEMU de la VM répond (accès de secours, depuis pve01).
m06_agent_ok() {
  remote "$WB_PVE_HOST" "qm guest cmd $1 ping" >/dev/null 2>&1
}

# m06_existe HÔTE — l'hôte répond en SSH (sert aux hôtes facultatifs : dns02 avant M06-E24…).
m06_existe() {
  remote "$1" true >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Hôtes distants : aide ajoutée au script envoyé (après le prélude de wb_exec)
# ---------------------------------------------------------------------------
read -r -d '' _M06_AIDE_DISTANTE <<'AIDE' || true
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
# copie_securite FICHIER — copie unique, hors manifeste (consultation en cas de doute, jamais
# restaurée automatiquement : subst/defaire_subst s'en chargent sans écraser une réparation).
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
# defaire_subst — dans l'ordre inverse : remet le texte d'origine là où le texte posé est encore là.
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
# service_kea4 / service_d2 — noms réels des unités des paquets ISC (alias kea-dhcp4… selon version)
service_existe() { systemctl cat "$1" >/dev/null 2>&1; }
service_kea4() {
  for s in isc-kea-dhcp4-server kea-dhcp4-server kea-dhcp4; do
    if service_existe "$s"; then echo "$s"; return 0; fi
  done
  return 1
}
service_d2() {
  for s in isc-kea-dhcp-ddns-server kea-dhcp-ddns-server kea-dhcp-ddns; do
    if service_existe "$s"; then echo "$s"; return 0; fi
  done
  return 1
}
# pdns_fichiers — fichiers de configuration de PowerDNS Authoritative (principal + include-dir)
pdns_fichiers() {
  local d
  echo /etc/powerdns/pdns.conf
  d="$(sed -nE 's/^[[:space:]]*include-dir[[:space:]]*=[[:space:]]*(.+)$/\1/p' /etc/powerdns/pdns.conf 2>/dev/null | tail -n 1)"
  if [ -n "$d" ] && [ -d "$d" ]; then ls "$d"/*.conf 2>/dev/null; fi
}
# pdns_reglage CLÉ — valeur effective (dernière occurrence, fichiers lus dans l'ordre de pdns)
pdns_reglage() {
  # shellcheck disable=SC2046
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*)\$/\1/p" $(pdns_fichiers) 2>/dev/null | tail -n 1
}
# pdns_fichier_de CLÉ — fichier qui porte la dernière occurrence de CLÉ
pdns_fichier_de() {
  # shellcheck disable=SC2046
  grep -lE "^[[:space:]]*$1[[:space:]]*=" $(pdns_fichiers) 2>/dev/null | tail -n 1
}
# rec_vider ZONE — vide le cache du récurseur local pour toute la zone (sans erreur s'il est absent)
rec_vider() {
  if command -v rec_control >/dev/null 2>&1; then rec_control wipe-cache "$1\$" >/dev/null 2>&1 || true; fi
}
AIDE

# m06_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (SSH, root), avec l'aide ci-dessus.
m06_wb_exec() {
  { printf '%s\n' "$_M06_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# m06_wb_exec_invite VMID [VAR=valeur…] <<'EOF' … EOF — par l'agent QEMU (quand SSH est coupé).
m06_wb_exec_invite() {
  { printf '%s\n' "$_M06_AIDE_DISTANTE"; cat; } | wb_exec_invite "$@"
}

# m06_vider_caches_rec ZONE — vide le cache des récurseurs (dns01, et dns02 s'il existe).
m06_vider_caches_rec() {
  local h
  for h in dns01 dns02; do
    m06_wb_exec "$h" ZONE="$1" >/dev/null 2>&1 <<'EOF' || true
rec_vider "$ZONE"
EOF
  done
}

# ---------------------------------------------------------------------------
# Variantes sans effet sur un lab donné
# ---------------------------------------------------------------------------

# m06_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
# La variante retenue est mise dans WB_VAR (enregistrée par wb_main ou par l'astreinte).
m06_essayer() {
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
  wb_avert "aucune variante de M06-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

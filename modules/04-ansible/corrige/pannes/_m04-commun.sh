# shellcheck shell=bash
# _m04-commun.sh — fonctions partagées par les scripts de panne du module 04 (M04-E35 à M04-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# 1. Copie de travail ~/src/ansible (WB_SRC) — sauvegarde et restauration EXACTES, côté utilisateur :
#      m04_sauver EX CHEMIN      copie le fichier/dossier (ou note son absence) avant modification ;
#      m04_noter EX CHEMIN       mémorise l'empreinte de ce que la panne vient de poser ;
#      m04_poser EX CHEMIN       écrit l'entrée standard dans CHEMIN (dossiers créés compris) ;
#      m04_restaurer EX          remet en place ce qui est ENCORE dans l'état posé par la panne ;
#                                ce que l'apprenant a modifié depuis (réparation) est laissé tel quel.
#    État : ~/.local/state/workbook/M04-EXX/ (700) : manifeste, injecte, sauvegardes/, journal,
#    et un instantané de l'arbre de travail (arbre-avant.tar.gz) pris à la première injection.
#    Aucun commit, aucun « git reset » : la panne n'écrit que dans l'arbre de travail.
# 2. Lancer Ansible comme l'apprenant : m04_ansible COMMANDE args… (depuis la racine du projet,
#    avec ~/.config/workbook/pve-ansible.env exporté s'il existe ; .venv/bin du projet, sinon uv run).
# 3. Hôtes distants : _M04_AIDE_DISTANTE (empreinte avec droits, noter_injecte, garder_reparations)
#    préfixée aux scripts envoyés par m04_wb_exec (SSH) et m04_wb_exec_invite (agent QEMU).

_M04_SRC="${WB_SRC:-$HOME/src}/ansible"
_M04_CFG="$HOME/.config/workbook"
_M04_ENV_ANSIBLE="$_M04_CFG/pve-ansible.env"
_M04_VAULT_PASS="$_M04_CFG/ansible-vault.pass"
_M04_VAULT_FICHIER="inventories/lab/group_vars/all/vault.yml"
_M04_INV_DYN="inventories/lab/proxmox.yml"

# Adresses du socle (PLAN.md §4.5) et VMID
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M04_IP=([gw01]=10.10.10.1 [adm01]=10.10.10.10 [dns01]=10.10.20.10 [git01]=10.10.20.12 [runner01]=10.10.20.15)
# shellcheck disable=SC2034
declare -A _M04_VMID=([gw01]=1000 [adm01]=1001 [dns01]=1002 [git01]=1004 [runner01]=1007)

# ---------------------------------------------------------------------------
# État local et journal
# ---------------------------------------------------------------------------

# m04_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m04_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M04-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m04_journal EXX "message" — journal local de la panne (et /var/lib/workbook/pannes.log si sudo -n).
m04_journal() {
  local ex="$1" d ligne
  shift
  d="$(m04_etat "$ex")"
  ligne="$(date -Is) $(hostname -s) [M04-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$d/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Projet Ansible de l'apprenant
# ---------------------------------------------------------------------------

# m04_ansible COMMANDE [args…] — lance ansible, ansible-playbook, ansible-inventory, ansible-vault…
# comme l'apprenant : depuis la racine du projet (ansible.cfg du projet), environnement du projet.
m04_ansible() {
  local cmd="$1"
  shift
  (
    cd "$_M04_SRC" || exit 1
    if [[ -r "$_M04_ENV_ANSIBLE" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$_M04_ENV_ANSIBLE"
      set +a
    fi
    export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    if [[ -x ".venv/bin/$cmd" ]]; then
      exec ".venv/bin/$cmd" "$@" </dev/null
    fi
    exec uv run --frozen --quiet "$cmd" "$@" </dev/null
  )
}

# m04_prerequis — projet présent, dépôt Git, arbre de travail propre, Ansible utilisable.
m04_prerequis() {
  if [[ ! -f "$_M04_SRC/ansible.cfg" ]]; then
    wb_avert "projet Ansible introuvable : $_M04_SRC/ansible.cfg (M04-E02)"
    return 1
  fi
  if ! git -C "$_M04_SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    wb_avert "$_M04_SRC n'est pas un dépôt Git"
    return 1
  fi
  # En astreinte (M04-E43), l'arbre est contrôlé une fois au départ : la première panne le salit.
  if [[ -z "${_M04_ASTREINTE:-}" && -n "$(git -C "$_M04_SRC" status --porcelain 2>/dev/null)" ]]; then
    wb_avert "la copie de travail $_M04_SRC contient des modifications non commitées : commite-les ou mets-les de côté (git stash) avant d'injecter une panne"
    return 1
  fi
  if ! m04_ansible ansible --version >/dev/null 2>&1; then
    wb_avert "Ansible ne se lance pas depuis $_M04_SRC (environnement uv du projet, M04-E02)"
    return 1
  fi
}

# m04_instantane EXX — archive de l'arbre de travail (fichiers suivis et non ignorés) avant la panne.
m04_instantane() {
  local d
  d="$(m04_etat "$1")"
  [[ -f "$d/arbre-avant.tar.gz" ]] && return 0
  (cd "$_M04_SRC" && git ls-files -co --exclude-standard -z | tar --null -T - -czf "$d/arbre-avant.tar.gz") 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Sauvegarde / restauration de fichiers locaux (copie de travail, ~/.config/workbook)
# ---------------------------------------------------------------------------

# m04_empreinte CHEMIN — « absent », « lien:<cible> », « fichier:<sha256>:<mode> » ou « dossier:<sha256> ».
m04_empreinte() {
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

# m04_sauver EXX CHEMIN — une seule sauvegarde par chemin et par panne (jamais un état déjà cassé).
m04_sauver() {
  local ex="$1" p="$2" d n
  d="$(m04_etat "$ex")"
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

# m04_noter EXX CHEMIN — empreinte de l'état posé par la panne (sert à reconnaître une réparation).
m04_noter() {
  local d
  d="$(m04_etat "$1")"
  printf '%s\t%s\n' "$2" "$(m04_empreinte "$2")" >>"$d/injecte"
}

# m04_poser EXX CHEMIN — écrit l'entrée standard dans CHEMIN. Si des dossiers parents manquent,
# c'est le plus haut dossier créé qui est sauvegardé (absent) et noté : l'annulation le retire.
m04_poser() {
  local ex="$1" p="$2" haut="" a
  a="$(dirname "$p")"
  while [[ ! -e "$a" ]]; do
    haut="$a"
    a="$(dirname "$a")"
  done
  if [[ -n "$haut" ]]; then
    m04_sauver "$ex" "$haut" || return 1
    mkdir -p "$(dirname "$p")" && cat >"$p" || return 1
    m04_noter "$ex" "$haut"
  else
    m04_sauver "$ex" "$p" || return 1
    cat >"$p" || return 1
    m04_noter "$ex" "$p"
  fi
}

# m04_restaurer EXX — restaure ce qui est encore dans l'état posé par la panne. Idempotent.
m04_restaurer() {
  local ex="$1" d src dst attendu actuel
  d="$(m04_etat "$ex")"
  [[ -f "$d/manifeste" ]] || return 0
  while IFS=$'\t' read -r src dst; do
    [[ -n "$src" ]] || continue
    attendu=""
    if [[ -f "$d/injecte" ]]; then
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$d/injecte")"
    fi
    actuel="$(m04_empreinte "$src")"
    if [[ -n "$attendu" && "$actuel" != "$attendu" ]]; then
      m04_journal "$ex" "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
      continue
    fi
    rm -rf -- "$src"
    if [[ "$dst" != ABSENT ]]; then
      cp -a -- "$dst" "$src" || wb_avert "restauration impossible : $src (copie dans $dst)"
    fi
    m04_journal "$ex" "annulation : $src restauré"
  done <"$d/manifeste"
  rm -rf -- "$d/manifeste" "$d/injecte" "$d/sauvegardes"
}

# m04_ini_set FICHIER SECTION CLÉ VALEUR [COMMENTAIRE] — fixe une clé INI en ne touchant qu'à sa
# ligne (section créée en fin de fichier si absente ; commentaire inséré au-dessus de la clé).
m04_ini_set() {
  python3 - "$@" <<'PY'
import re, sys
fichier, section, cle, valeur = sys.argv[1:5]
commentaire = sys.argv[5] if len(sys.argv) > 5 else ""
lignes = open(fichier, encoding="utf-8").read().splitlines()
entete = re.compile(r"^\s*\[(.+?)\]\s*$")
cle_re = re.compile(r"^\s*" + re.escape(cle) + r"\s*[=:]")
neuves = ([("# " + commentaire)] if commentaire else []) + ["%s = %s" % (cle, valeur)]
debut = None
for i, l in enumerate(lignes):
    m = entete.match(l)
    if m and m.group(1).strip() == section:
        debut = i
        break
if debut is None:
    lignes += ["", "[%s]" % section] + neuves
else:
    fin = len(lignes)
    for j in range(debut + 1, len(lignes)):
        if entete.match(lignes[j]):
            fin = j
            break
    for j in range(debut + 1, fin):
        if cle_re.match(lignes[j]):
            lignes[j:j + 1] = neuves
            break
    else:
        lignes[debut + 1:debut + 1] = neuves
open(fichier, "w", encoding="utf-8").write("\n".join(lignes) + "\n")
PY
}

# m04_ini_sections_avec FICHIER CLÉ — sections qui définissent CLÉ (une par ligne).
m04_ini_sections_avec() {
  awk -v k="$2" '
    /^[[:space:]]*\[/ { s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s) }
    $0 ~ "^[[:space:]]*" k "[[:space:]]*[=:]" { print s }' "$1"
}

# ---------------------------------------------------------------------------
# SSH depuis adm01
# ---------------------------------------------------------------------------

# m04_fermer_ssh HÔTE… — ferme les connexions maîtresses (multiplexage de ~/.ssh/config et
# sockets de contrôle d'Ansible), sinon une panne SSH reste masquée par une connexion existante.
m04_fermer_ssh() {
  local h s
  for h in "$@"; do
    ssh -O exit -o BatchMode=yes "$h" >/dev/null 2>&1 || true
    if [[ -n "${_M04_IP[$h]:-}" ]]; then
      ssh -O exit -o BatchMode=yes "${_M04_IP[$h]}" >/dev/null 2>&1 || true
      ssh -O exit -o BatchMode=yes "admin@${_M04_IP[$h]}" >/dev/null 2>&1 || true
    fi
  done
  for s in "$HOME"/.ansible/cp/*; do
    [[ -S "$s" ]] || continue
    ssh -O exit -o ControlPath="$s" -o BatchMode=yes sonde >/dev/null 2>&1 || true
  done
}

# m04_ssh_ok HÔTE — 0 si une NOUVELLE connexion SSH (sans multiplexage) aboutit.
m04_ssh_ok() {
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Hôtes distants : aide ajoutée au script envoyé (après le prélude de wb_exec)
# ---------------------------------------------------------------------------
read -r -d '' _M04_AIDE_DISTANTE <<'AIDE' || true
# empreinte CHEMIN — « lien:<cible> », « sha256:<somme>:<mode> » ou « absent »
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
oublier_injecte() { rm -f -- "$WB_DIR/$WB_EX.injecte"; }
# garder_reparations — avant restaurer_fichiers : tout fichier qui n'est plus celui que la panne a
# posé (contenu ou droits) est une réparation ; il sort du manifeste et reste tel quel.
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
AIDE

# m04_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (SSH, root), avec l'aide ci-dessus.
m04_wb_exec() {
  { printf '%s\n' "$_M04_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# m04_wb_exec_invite VMID [VAR=valeur…] <<'EOF' … EOF — par l'agent QEMU (quand SSH est coupé).
m04_wb_exec_invite() {
  { printf '%s\n' "$_M04_AIDE_DISTANTE"; cat; } | wb_exec_invite "$@"
}

# ---------------------------------------------------------------------------
# Essai de variantes : certaines peuvent être sans effet selon les choix de l'apprenant
# ---------------------------------------------------------------------------

# m04_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
# La variante retenue est mise dans WB_VAR (enregistrée par wb_main ou par l'astreinte).
m04_essayer() {
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
  wb_avert "aucune variante de M04-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

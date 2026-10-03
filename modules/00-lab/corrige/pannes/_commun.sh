# shellcheck shell=bash
# _commun.sh — fonctions partagées par les scripts de panne du module 00 (palier 4).
#
# Sourcé par break-EXX.sh (lui-même sourcé par lab/bin/break, qui a déjà chargé
# lab/lib/check-lib.sh et donc la fonction `remote`). Ne s'exécute jamais seul.
#
# Organisation d'un script de panne :
#   panne_EXX_vN   injecte la variante N (silencieux, code retour ≠ 0 si échec)
#   annuler_EXX    remet l'état sain (idempotent, fondé sur les sauvegardes faites)
#   symptome_EXX   affiche le symptôme tel qu'un utilisateur le rapporterait
#   resume_EXX     une phrase de symptôme (utilisée par l'astreinte E46)
#   main           appelle wb_main EXX <nb_variantes> "$@" (sauf en mode bibliothèque)
#
# Conventions d'état :
#   - sur chaque hôte modifié : /var/lib/workbook/pannes.log (journal) et
#     /var/lib/workbook/EXX.* (sauvegardes avant modification) ;
#   - sur adm01 (poste qui lance les pannes) : un marqueur par panne active dans
#     ~/.local/state/workbook/pannes-actives/EXX (contient le numéro de variante).

WB_ETAT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"

# VMID et noms fixés par PLAN.md (utilisés par les scripts qui sourcent ce fichier)
# shellcheck disable=SC2034
{
  WB_VMID_GW01=1000
  WB_VMID_ADM01=1001
  WB_VMID_DNS01=1002
  WB_VMID_TPL=9000
}

# ---------------------------------------------------------------------------
# Prélude envoyé avant chaque script distant (exécuté en root sur l'hôte cible)
# ---------------------------------------------------------------------------
read -r -d '' _WB_PRELUDE <<'PRELUDE' || true
set -u
WB_DIR=/var/lib/workbook
mkdir -p "$WB_DIR" && chmod 700 "$WB_DIR"

journal() {
  printf '%s %s [%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$WB_EX" "$WB_VAR" "$*" >> "$WB_DIR/pannes.log"
}

# sauver FICHIER — copie le fichier (ou note son absence) avant modification.
# Une seule sauvegarde par fichier et par panne : on ne capture jamais un état déjà cassé.
sauver() {
  local src="$1" dst
  dst="$WB_DIR/$WB_EX.$(printf '%s' "$src" | tr '/' '_').orig"
  if grep -qsF "$(printf '%s\t' "$src")" "$WB_DIR/$WB_EX.manifeste"; then return 0; fi
  if [ -e "$src" ] || [ -L "$src" ]; then
    cp -a "$src" "$dst"
  else
    dst="ABSENT"
  fi
  printf '%s\t%s\n' "$src" "$dst" >> "$WB_DIR/$WB_EX.manifeste"
}

# restaurer_fichiers — remet en place tous les fichiers sauvegardés par sauver().
restaurer_fichiers() {
  local m="$WB_DIR/$WB_EX.manifeste" src dst
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r src dst; do
    if [ "$dst" = "ABSENT" ]; then
      rm -f "$src"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
      rm -f "$src" && cp -a "$dst" "$src" && rm -f "$dst"
    fi
  done < "$m"
  rm -f "$m"
}

# nft_inserer FAMILLE TABLE CHAÎNE "règle" — insère en tête de chaîne et mémorise le handle.
nft_inserer() {
  local fam="$1" tab="$2" ch="$3" regle="$4" h
  h="$(nft -e -a insert rule "$fam" "$tab" "$ch" "$regle" | sed -n 's/.*# handle \([0-9][0-9]*\).*/\1/p' | tail -n 1)"
  if [ -z "$h" ]; then
    # Repli : la règle insérée est la première de la chaîne
    h="$(nft -a list chain "$fam" "$tab" "$ch" | sed -n 's/.*# handle \([0-9][0-9]*\)$/\1/p' | head -n 1)"
  fi
  [ -n "$h" ] || return 1
  printf '%s %s %s %s\n' "$fam" "$tab" "$ch" "$h" >> "$WB_DIR/$WB_EX.nft-ajouts"
}

# nft_remplacer FAMILLE TABLE CHAÎNE HANDLE "nouvelle règle" — mémorise l'ancienne règle.
nft_remplacer() {
  local fam="$1" tab="$2" ch="$3" h="$4" neuve="$5" ancienne
  ancienne="$(nft -a list chain "$fam" "$tab" "$ch" | grep -E "# handle $h\$" | sed -E 's/^[[:space:]]+//; s/ # handle [0-9]+$//')"
  [ -n "$ancienne" ] || return 1
  nft replace rule "$fam" "$tab" "$ch" handle "$h" "$neuve" || return 1
  printf 'replace rule %s %s %s handle %s %s\n' "$fam" "$tab" "$ch" "$h" "$ancienne" >> "$WB_DIR/$WB_EX.nft-remplacements"
}

# nft_annuler — supprime les règles ajoutées et rétablit les règles remplacées.
nft_annuler() {
  local f="$WB_DIR/$WB_EX.nft-ajouts" fam tab ch h
  if [ -f "$f" ]; then
    while read -r fam tab ch h; do
      nft delete rule "$fam" "$tab" "$ch" handle "$h" 2>/dev/null || true
    done < "$f"
    rm -f "$f"
  fi
  f="$WB_DIR/$WB_EX.nft-remplacements"
  if [ -f "$f" ]; then
    nft -f "$f" 2>/dev/null || echo "avertissement : règle nftables non rétablie (déjà modifiée ?)" >&2
    rm -f "$f"
  fi
}
PRELUDE

# ---------------------------------------------------------------------------
# Exécution distante
# ---------------------------------------------------------------------------

# _wb_est_hote_root HÔTE — pve01 et pbs01 sont joints en root, les VMs en admin + sudo.
_wb_est_hote_root() {
  [[ "$1" == "$WB_PVE_HOST" || "$1" == "$WB_PBS_HOST" || "$1" == pve01 || "$1" == pbs01 ]]
}

# _wb_entete VAR=valeur... — construit l'en-tête de variables passé au script distant.
_wb_entete() {
  local kv
  for kv in "$@"; do
    printf '%s=%q\n' "${kv%%=*}" "${kv#*=}"
  done
  printf 'WB_EX=%q\nWB_VAR=%q\n' "${WB_EX:-?}" "${WB_VAR:-0}"
}

# wb_exec HÔTE [VAR=valeur...] <<'EOF' ... EOF
#   Exécute en root sur HÔTE le script lu sur l'entrée standard, précédé du prélude.
wb_exec() {
  local host="$1"; shift
  local shell="sudo -n bash -s"
  if _wb_est_hote_root "$host"; then shell="bash -s"; fi
  { printf '%s\n' "$_WB_PRELUDE"; _wb_entete "$@"; cat; } | remote "$host" "$shell"
}

# wb_exec_invite VMID [VAR=valeur...] <<'EOF' ... EOF
#   Exécute le script DANS la VM via l'agent QEMU (depuis pve01) : sert quand la panne
#   coupe l'accès SSH à la VM. Renvoie 0 si le script s'est terminé avec le code 0.
wb_exec_invite() {
  local vmid="$1"; shift
  local sortie
  sortie="$({ printf '%s\n' "$_WB_PRELUDE"; _wb_entete "$@"; cat; } \
    | remote "$WB_PVE_HOST" "qm guest exec $vmid --pass-stdin 1 --timeout 60 -- bash -s" 2>&1)" || return 1
  grep -Eq '"exitcode"[[:space:]]*:[[:space:]]*0([^0-9]|$)' <<<"$sortie"
}

# ---------------------------------------------------------------------------
# Marqueurs locaux de pannes actives (sur adm01)
# ---------------------------------------------------------------------------
wb_marqueur_existe() { [[ -f "$WB_ETAT_DIR/$1" ]]; }
wb_marqueur_lire()   { if [[ -f "$WB_ETAT_DIR/$1" ]]; then cat "$WB_ETAT_DIR/$1"; fi; }
wb_marqueur_ecrire() { mkdir -p "$WB_ETAT_DIR" && printf '%s\n' "$2" > "$WB_ETAT_DIR/$1"; }
wb_marqueur_suppr()  { rm -f "$WB_ETAT_DIR/$1"; }

wb_avert() { printf 'avertissement : %s\n' "$*" >&2; }

# wb_symptome "titre" "ligne" ... — affichage normalisé du symptôme
wb_symptome() {
  local titre="$1"; shift
  printf '\n=== %s ===\n\n' "$titre"
  local l
  for l in "$@"; do printf '  %s\n' "$l"; done
  printf '\n'
}

# ---------------------------------------------------------------------------
# Boucle principale commune
# ---------------------------------------------------------------------------
# wb_main EXX NB_VARIANTES [--variante N] [--annuler]
wb_main() {
  local ex="$1" nb="$2"; shift 2
  local var="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        var="$2"; shift 2 ;;
      --variante=*) var="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done

  WB_EX="$ex"
  if ((annuler)); then
    WB_VAR="$(wb_marqueur_lire "$ex")"
    WB_VAR="${WB_VAR:-annulation}"
    "annuler_$ex"
    wb_marqueur_suppr "$ex"
    echo "Panne $ex annulée : l'état sain a été restauré. Contrôle : lab/bin/check 00 ${ex#E}"
    return 0
  fi

  if wb_marqueur_existe "$ex"; then
    echo "Une panne $ex est déjà active. Répare-la (ou lance --annuler) avant d'en injecter une autre." >&2
    return 1
  fi
  if [[ -z "$var" ]]; then
    var=$((RANDOM % nb + 1))
  fi
  if ! [[ "$var" =~ ^[0-9]+$ ]] || ((var < 1 || var > nb)); then
    echo "Variante invalide : $var (1 à $nb)" >&2
    return 2
  fi
  WB_VAR="$var"
  echo "Injection en cours…"
  if ! "panne_${ex}_v${var}"; then
    echo "L'injection a échoué (état du lab inattendu ?). Remise en état…" >&2
    "annuler_$ex" || true
    return 1
  fi
  # La fonction de panne peut avoir basculé sur une autre variante (WB_VAR modifié).
  wb_marqueur_ecrire "$ex" "$WB_VAR"
  "symptome_$ex"
}

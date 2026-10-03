# shellcheck shell=bash
# pannes-lib.sh — bibliothèque commune des scripts de panne (break & fix), modules 01 et suivants.
#
# Sourcée par modules/NN-slug/corrige/pannes/break-EXX.sh, eux-mêmes sourcés par lab/bin/break
# (qui a déjà chargé lab/lib/check-lib.sh, donc `remote`, et exporté WB_ROOT).
# Le module 00 garde sa propre copie (modules/00-lab/corrige/pannes/_commun.sh).
#
# Organisation d'un script de panne break-EXX.sh :
#   source "$WB_ROOT/lab/lib/pannes-lib.sh"
#   panne_EXX_vN   injecte la variante N (silencieux, code retour ≠ 0 si échec)
#   verifier_EXX   (facultatif mais recommandé) contrôle sur place que la panne est réellement
#                  active ; code ≠ 0 → la panne est annulée et l'injection signalée en échec
#                  (CONVENTIONS §11.10 : jamais de ticket pour une panne inexistante)
#   annuler_EXX    remet l'état sain (idempotent, fondé sur les sauvegardes faites)
#   symptome_EXX   affiche le symptôme tel qu'un utilisateur le rapporterait
#   resume_EXX     une phrase de symptôme (utilisée par les exercices d'astreinte)
#   main           if [[ -z "${WB_PANNES_LIB:-}" ]]; then main() { wb_main <NN> EXX <nb_variantes> "$@"; }; fi
#
# Conventions d'état :
#   - sur chaque hôte modifié : /var/lib/workbook/pannes.log (journal) et
#     /var/lib/workbook/M<NN>-EXX.* (sauvegardes avant modification) ;
#   - sur adm01 (poste qui lance les pannes) : un marqueur par panne active dans
#     ~/.local/state/workbook/pannes-actives/M<NN>-EXX (contient le numéro de variante).
#   Dans les fonctions, WB_EX vaut « M<NN>-EXX » (ex. M04-E41) et WB_VAR la variante.

WB_ETAT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"

# VMID et noms fixés par PLAN.md (utilisés par les scripts qui sourcent ce fichier)
# shellcheck disable=SC2034
{
  WB_VMID_GW01=1000
  WB_VMID_ADM01=1001
  WB_VMID_DNS01=1002
  WB_VMID_TPL=9000
  WB_VMID_GIT01=1004
  WB_VMID_RUNNER01=1007
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
# wb_main NN EXX NB_VARIANTES [--variante N] [--annuler]
wb_main() {
  local mod="$1" ex="$2" nb="$3"; shift 3
  local var="" annuler=0 cle
  mod="$(printf '%02d' "$((10#$mod))")"
  cle="M${mod}-${ex}"
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

  # shellcheck disable=SC2034  # utilisable par les fonctions de panne
  WB_MODULE="$mod"
  WB_EX="$cle"
  if ((annuler)); then
    WB_VAR="$(wb_marqueur_lire "$cle")"
    WB_VAR="${WB_VAR:-annulation}"
    "annuler_$ex"
    wb_marqueur_suppr "$cle"
    echo "Panne $cle annulée : l'état sain a été restauré. Contrôle : lab/bin/check $mod ${ex#E}"
    return 0
  fi

  if wb_marqueur_existe "$cle"; then
    echo "Une panne $cle est déjà active. Répare-la (ou lance --annuler) avant d'en injecter une autre." >&2
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
  # Contrôle sur place que la panne est effective (si le script le prévoit).
  if declare -F "verifier_$ex" >/dev/null && ! "verifier_$ex"; then
    echo "La panne n'a pas pu être constatée après injection : annulation, rien n'est cassé." >&2
    echo "Vérifie que le lab est sain (lab/bin/check $mod ${ex#E}) puis relance." >&2
    "annuler_$ex" || true
    return 1
  fi
  # La fonction de panne peut avoir basculé sur une autre variante (WB_VAR modifié).
  wb_marqueur_ecrire "$cle" "$WB_VAR"
  "symptome_$ex"
}

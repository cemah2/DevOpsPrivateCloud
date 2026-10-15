# shellcheck shell=bash
# _m18-commun.sh — fonctions partagées par les pannes du module 18 (break-E19 à break-E22).
# Sourcé APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_avert, wb_symptome, wb_main).
#
# 1. Accès : kubeconfig et talosconfig des clusters d'essai sous ~/.config/workbook/m18/ (comme les checks).
#    m18_k KUBECONFIG ARGS…           kubectl (lecture ET écriture) sur un cluster d'essai
#    m18_gestion ARGS…                kubectl sur le cluster de gestion k3s01
#    m18_talos ARGS…                  talosctl avec le talosconfig d'administration
# 2. Nœuds : m18_exec HÔTE [VAR=v…] <<'EOF' (SSH + sudo, prélude de pannes-lib), m18_exec_invite HÔTE
#    (agent QEMU depuis pve01, pour les pannes qui peuvent couper SSH), VMID des VMs du module.
# 3. Variantes : m18_essayer EXX NB VARIANTE (une variante sans effet sur ce lab renvoie 10 : on essaie
#    la suivante), m18_attendre SECONDES COMMANDE…
# 4. Git : m18_git_propre, m18_branche_lucas, m18_branche_annuler (comme au M17 : branche locale,
#    jamais de push, commit au nom de Lucas Martin).
# 5. État local : ~/.local/state/workbook/M18-EXX/ (700) — m18_ecrire, m18_lire, m18_oublier, m18_journal.

_M18_DIR="${WB_M18_DIR:-$HOME/.config/workbook/m18}"
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M18_KC_GESTION="$_M18_DIR/k3s01.kubeconfig"
  _M18_KC_CAPI="$_M18_DIR/capi-essai.kubeconfig"
  _M18_KC_RKE2="$_M18_DIR/rke2.kubeconfig"
  _M18_KC_TALOS="$_M18_DIR/talos.kubeconfig"
  _M18_KC_K3SHA="$_M18_DIR/k3s-ha.kubeconfig"
  _M18_TALOSCONFIG="$_M18_DIR/talosconfig"
  _M18_DEPOT="${WB_SRC:-$HOME/src}/distributions"
  _M18_LUCAS_NOM="Lucas Martin"
  _M18_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
  _M18_ESPACE_CAPI=capi-essai
}
declare -A _M18_VMID=([k3s01]=2181 [rke2-01]=2182 [rke2-02]=2183 [rke2-03]=2184
  [talos-01]=2185 [talos-02]=2186 [talos-03]=2187 [m18-dev01]=2188
  [k3s-ha01]=5191 [k3s-ha02]=5192 [k3s-ha03]=5193)
# shellcheck disable=SC2034
declare -A _M18_TALOS_IP=([talos-01]=10.10.99.85 [talos-02]=10.10.99.86 [talos-03]=10.10.99.87)

# ---------------------------------------------------------------------------
# État local et journal
# ---------------------------------------------------------------------------
m18_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M18-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m18_ecrire() { printf '%s\n' "$3" >"$(m18_etat "$1")/$2"; }
m18_lire() {
  local f
  f="$(m18_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m18_oublier() { rm -f "$(m18_etat "$1")/$2"; }

# m18_journal EXX "message" — journal local (et /var/lib/workbook/pannes.log de adm01 si sudo -n).
m18_journal() {
  local ex="$1" ligne
  shift
  ligne="$(date -Is) $(hostname -s) [M18-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$(m18_etat "$ex")/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# m18_outils OUTIL… — 0 si tous les outils sont présents sur adm01.
m18_outils() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }
  done
}

# m18_essayer EXX NB VARIANTE — lance _mEXX_une VARIANTE ; si elle renvoie 10 (sans effet sur ce lab),
# essaie les autres variantes dans l'ordre et met WB_VAR à celle qui a pris.
m18_essayer() {
  local ex="$1" nb="$2" v="$3" i rc
  for ((i = 0; i < nb; i++)); do
    rc=0
    "_m${ex}_une" "$v" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$v"
      return 0
    fi
    ((rc == 10)) || return "$rc"
    v=$((v % nb + 1))
  done
  wb_avert "aucune variante de M18-$ex ne s'applique à l'état actuel du lab"
  return 1
}

# m18_attendre SECONDES COMMANDE… — répète COMMANDE toutes les 5 s jusqu'à ce qu'elle réussisse.
m18_attendre() {
  local t="$1" d=0
  shift
  while ((d < t)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5
    d=$((d + 5))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Accès aux clusters d'essai
# ---------------------------------------------------------------------------
m18_k() {
  local kc="$1"
  shift
  [[ -r "$kc" ]] || { wb_avert "kubeconfig illisible : $kc"; return 1; }
  kubectl --kubeconfig "$kc" --request-timeout=20s "$@"
}
m18_gestion() { m18_k "$_M18_KC_GESTION" "$@"; }
m18_talos() {
  [[ -r "$_M18_TALOSCONFIG" ]] || { wb_avert "talosconfig illisible : $_M18_TALOSCONFIG"; return 1; }
  timeout 60 talosctl --talosconfig "$_M18_TALOSCONFIG" "$@"
}

# m18_noeud_pret KUBECONFIG NŒUD — 0 si le nœud est Ready.
m18_noeud_pret() {
  [[ "$(m18_k "$1" get node "$2" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == True ]]
}
m18_noeud_pas_pret() { ! m18_noeud_pret "$@"; }

# ---------------------------------------------------------------------------
# Nœuds
# ---------------------------------------------------------------------------
# m18_exec HÔTE [VAR=v…] <<'EOF' — script en root sur HÔTE par SSH (prélude : journal, sauver, restaurer_fichiers).
m18_exec() { wb_exec "$@"; }

# m18_exec_invite HÔTE [VAR=v…] <<'EOF' — même chose par l'agent QEMU (sans SSH). Code 0 si le script a réussi.
m18_exec_invite() {
  local h="$1"
  shift
  [[ -n "${_M18_VMID[$h]:-}" ]] || { wb_avert "VMID inconnu pour $h"; return 1; }
  wb_exec_invite "${_M18_VMID[$h]}" "$@"
}

# ---------------------------------------------------------------------------
# Git (copie de travail de plateforme/distributions)
# ---------------------------------------------------------------------------
m18_git_propre() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { wb_avert "$1 n'est pas une copie de travail Git"; return 1; }
  if [[ -n "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    wb_avert "la copie de travail $1 contient des modifications non commitées : commite-les ou mets-les de côté (git stash) avant d'injecter une panne"
    return 1
  fi
}

# m18_branche_lucas DÉPÔT BRANCHE "message" — l'appelant a modifié l'arbre de travail : commit sur une
# NOUVELLE branche partie de HEAD, au nom de Lucas, et mémorisation de quoi annuler.
m18_branche_lucas() {
  local depot="$1" br="$2" msg="$3" origine commit
  origine="$(git -C "$depot" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$depot" rev-parse HEAD)"
  git -C "$depot" switch --quiet -c "$br" || return 1
  git -C "$depot" add -A || return 1
  GIT_AUTHOR_NAME="$_M18_LUCAS_NOM" GIT_AUTHOR_EMAIL="$_M18_LUCAS_COURRIEL" \
    GIT_COMMITTER_NAME="$_M18_LUCAS_NOM" GIT_COMMITTER_EMAIL="$_M18_LUCAS_COURRIEL" \
    GIT_AUTHOR_DATE="$(date -d 'yesterday 17:42' -Iseconds)" \
    git -C "$depot" -c commit.gpgsign=false commit --quiet --no-verify -m "$msg" || return 1
  commit="$(git -C "$depot" rev-parse HEAD)"
  m18_ecrire "${WB_EX#M18-}" git "$depot $br $origine $commit"
}

# m18_branche_annuler EXX — revient à la branche d'origine ; supprime la branche de Lucas seulement si
# son sommet est encore le commit injecté (sinon elle porte les corrections de l'apprenant).
m18_branche_annuler() {
  local ex="$1" depot br origine commit courante
  read -r depot br origine commit <<<"$(m18_lire "$ex" git)"
  [[ -n "${depot:-}" && -d "$depot" ]] || { m18_oublier "$ex" git; return 0; }
  courante="$(git -C "$depot" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ "$courante" == "$br" ]]; then
    if [[ -z "$(git -C "$depot" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
      git -C "$depot" switch --quiet "$origine" 2>/dev/null || git -C "$depot" switch --quiet --detach "$origine" 2>/dev/null || true
    else
      wb_avert "la branche $br de $depot contient des modifications non commitées : je la laisse en place"
    fi
  fi
  if git -C "$depot" rev-parse --verify --quiet "refs/heads/$br" >/dev/null; then
    if [[ "$(git -C "$depot" rev-parse "refs/heads/$br")" == "$commit" && "$(git -C "$depot" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "$br" ]]; then
      git -C "$depot" branch --quiet -D "$br" 2>/dev/null || true
    else
      wb_avert "la branche $br de $depot porte tes commits : je la laisse (supprime-la toi-même après la MR)"
    fi
  fi
  m18_oublier "$ex" git
}

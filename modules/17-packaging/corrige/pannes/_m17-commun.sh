# shellcheck shell=bash
# _m17-commun.sh — fonctions partagées par les scripts de panne du module 17 (M17-E19 à M17-E22).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_k8s_sauver, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# 1. Helm avec le kubeconfig d'administration (WB_K8S_ADMIN_KUBECONFIG) : m17_helm ARGS…
# 2. Secrets de release Helm (pilote « secret ») :
#      m17_rel_lister ESPACE RELEASE      « nom version statut » de chaque Secret de révision (étiquettes)
#      m17_rel_decoder ESPACE SECRET      JSON de la révision (base64 de l'API, base64 de Helm, gzip)
#      m17_rel_lisible ESPACE SECRET      0 si la révision se décode
#      m17_rel_creer ESPACE RELEASE N STATUT < JSON   crée le Secret de la révision N
#      m17_rel_statut ESPACE RELEASE      statut de la release vu par Helm (helm status)
#      m17_rel_ssa ESPACE RELEASE         0 si la dernière révision « deployed » est en SSA
# 3. Copies de travail (WB_SRC, défaut ~/src) — jamais de commit sur la branche courante, jamais de push :
#      m17_git_propre DÉPÔT               0 si la copie existe et ne contient aucune modification
#      m17_branche_lucas DÉPÔT BRANCHE "message"   crée BRANCHE depuis HEAD, commite l'arbre modifié
#                                         par la fonction _m17_modifier (déjà appelée) au nom de Lucas
#      m17_branche_annuler DÉPÔT EX       revient à la branche d'origine et supprime la branche de la
#                                         panne seulement si son sommet est encore le commit injecté
# 4. État local : ~/.local/state/workbook/M17-EXX/ (700) — m17_ecrire, m17_lire, m17_oublier, m17_journal.

_M17_SRC="${WB_SRC:-$HOME/src}"
_M17_CHART="$_M17_SRC/mediagenda-chart"
_M17_DEPLOIEMENT="$_M17_SRC/mediagenda-deploiement"
_M17_GESTIONNAIRE="mediagenda-deploiement"
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
_M17_LUCAS_NOM="Lucas Martin"
# shellcheck disable=SC2034
_M17_LUCAS_COURRIEL="lucas.martin@medisphere.internal"

# ---------------------------------------------------------------------------
# État local et journal
# ---------------------------------------------------------------------------
m17_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M17-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m17_ecrire() { printf '%s\n' "$3" >"$(m17_etat "$1")/$2"; }
m17_lire() {
  local f
  f="$(m17_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m17_oublier() { rm -f "$(m17_etat "$1")/$2"; }

# m17_journal EXX "message" — journal local (et /var/lib/workbook/pannes.log de adm01 si sudo -n).
m17_journal() {
  local ex="$1" ligne
  shift
  ligne="$(date -Is) $(hostname -s) [M17-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$(m17_etat "$ex")/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# m17_outils OUTIL… — 0 si tous les outils sont présents sur adm01.
m17_outils() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }
  done
}

# m17_essayer EXX NB VARIANTE — lance _mEXX_une VARIANTE ; si elle renvoie 10 (sans effet sur ce
# lab), essaie les autres variantes dans l'ordre et met WB_VAR à celle qui a pris.
m17_essayer() {
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
  wb_avert "aucune variante de M17-$ex ne s'applique à l'état actuel du lab"
  return 1
}

# ---------------------------------------------------------------------------
# Helm et Secrets de release
# ---------------------------------------------------------------------------
m17_helm() {
  helm --kubeconfig "${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}" "$@"
}

m17_rel_lister() {
  wb_kubectl get secret -n "$1" -l "owner=helm,name=$2" \
    -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.version} {.metadata.labels.status}{"\n"}{end}' 2>/dev/null \
    | sort -k2,2n
}

m17_rel_decoder() {
  wb_kubectl get secret "$2" -n "$1" -o jsonpath='{.data.release}' 2>/dev/null \
    | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gzip -dc 2>/dev/null
}

m17_rel_lisible() {
  m17_rel_decoder "$1" "$2" | jq -e '.version' >/dev/null 2>&1
}

# m17_rel_creer ESPACE RELEASE N STATUT < JSON
m17_rel_creer() {
  local ns="$1" rel="$2" n="$3" st="$4" donnees
  donnees="$(gzip -c | base64 -w0)" || return 1
  wb_kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
type: helm.sh/release.v1
metadata:
  name: sh.helm.release.v1.${rel}.v${n}
  namespace: ${ns}
  labels:
    name: "${rel}"
    owner: helm
    status: ${st}
    version: "${n}"
    modifiedAt: "$(date +%s)"
stringData:
  release: ${donnees}
EOF
}

m17_rel_statut() {
  m17_helm status "$2" -n "$1" -o json 2>/dev/null | jq -r '.info.status // empty' 2>/dev/null
}

# m17_rel_derniere ESPACE RELEASE STATUT — nom du Secret de la plus haute révision portant ce statut.
m17_rel_derniere() {
  m17_rel_lister "$1" "$2" | awk -v s="$3" '$3 == s { n = $1 } END { if (n != "") print n }'
}

m17_rel_ssa() {
  local s
  s="$(m17_rel_derniere "$1" "$2" deployed)"
  [[ -n "$s" ]] && m17_rel_decoder "$1" "$s" | jq -e '.apply_method == "ssa"' >/dev/null 2>&1
}

# m17_rel_saine ESPACE RELEASE — la release existe, est « deployed », et toutes ses révisions se lisent.
m17_rel_saine() {
  local ns="$1" rel="$2" nom _v _s
  [[ "$(m17_rel_statut "$ns" "$rel")" == deployed ]] || return 1
  while read -r nom _v _s; do
    [[ -n "$nom" ]] || continue
    m17_rel_lisible "$ns" "$nom" || return 1
  done < <(m17_rel_lister "$ns" "$rel")
}

# ---------------------------------------------------------------------------
# Copies de travail
# ---------------------------------------------------------------------------
m17_git_propre() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { wb_avert "$1 n'est pas une copie de travail Git"; return 1; }
  if [[ -n "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    wb_avert "la copie de travail $1 contient des modifications non commitées : commite-les ou mets-les de côté (git stash) avant d'injecter une panne"
    return 1
  fi
}

# m17_branche_lucas DÉPÔT BRANCHE "message" — la fonction appelante a modifié l'arbre de travail.
# Commite sur une NOUVELLE branche partie de HEAD, au nom de Lucas, et mémorise de quoi annuler.
m17_branche_lucas() {
  local depot="$1" br="$2" msg="$3" origine commit
  origine="$(git -C "$depot" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$depot" rev-parse HEAD)"
  git -C "$depot" switch --quiet -c "$br" || return 1
  git -C "$depot" add -A || return 1
  GIT_AUTHOR_NAME="$_M17_LUCAS_NOM" GIT_AUTHOR_EMAIL="$_M17_LUCAS_COURRIEL" \
    GIT_COMMITTER_NAME="$_M17_LUCAS_NOM" GIT_COMMITTER_EMAIL="$_M17_LUCAS_COURRIEL" \
    GIT_AUTHOR_DATE="$(date -d 'yesterday 17:42' -Iseconds)" \
    git -C "$depot" -c commit.gpgsign=false commit --quiet --no-verify -m "$msg" || return 1
  commit="$(git -C "$depot" rev-parse HEAD)"
  m17_ecrire "${WB_EX#M17-}" git "$depot $br $origine $commit"
}

m17_branche_annuler() {
  local ex="$1" depot br origine commit courante
  read -r depot br origine commit <<<"$(m17_lire "$ex" git)"
  [[ -n "${depot:-}" && -d "$depot" ]] || { m17_oublier "$ex" git; return 0; }
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
  m17_oublier "$ex" git
}

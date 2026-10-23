# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S01.sh — F3-S01 « Prendre l'astreinte ».
# C'est AUSSI le contrôle de santé exigé avant chaque incident injecté (lab/bin/check F3 1) : nœuds,
# Argo CD, Ceph, alertes critiques, témoin de mon01 (dead man's switch). S'y ajoutent les livrables de la
# prise de poste : accès, route d'astreinte éprouvée, index des runbooks, trousse, main courante ouverte.
# Lecture seule.

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S01 — Prendre l'astreinte (et contrôle de santé du lab)"
require_cmd kubectl jq curl ssh

# --- 1. Santé : le lab tel qu'on le reçoit -------------------------------------------------------------
_f3s_sante

# --- 2. Accès ------------------------------------------------------------------------------------------
_f3d_s01_kubelogin() {
  kubectl config view -o json 2>/dev/null |
    jq -e '[.users[]?.user.exec? | select(. != null) | (.command + " " + ((.args // []) | join(" ")))] | any(test("oidc-login"))' >/dev/null 2>&1
}
check_cmd "accès au cluster par SSO (kubelogin, oidc-login dans ~/.kube/config)" _f3d_s01_kubelogin
_f3d_s01_bao_oidc() { bao_api "sys/auth" 2>/dev/null | jq -e '.data // . | has("oidc/")' >/dev/null 2>&1; }
check_cmd "OpenBao : méthode oidc disponible pour l'astreinte" _f3d_s01_bao_oidc

# --- 3. Les alertes arrivent -------------------------------------------------------------------------
if command -v amtool >/dev/null 2>&1; then
  check_cmd "une alerte critique de la plateforme est routée vers astreinte-mail (configuration chargée)" \
    _f3d_route_contient astreinte-mail alertname=EssaiPriseDePoste gravite=critique equipe=plateforme
else
  _ko "amtool absent d'adm01 (M21) : impossible de rejouer l'arbre de routage chargé"
fi
_f3d_s01_essai_recu() {
  local j
  j="$(mailpit_api "search?query=$(_f3s_enc 'to:astreinte@medisphere.internal subject:EssaiPriseDePoste')" 2>/dev/null)" || return 1
  jq -e '(.messages_count // 0) >= 1' <<<"$j" >/dev/null 2>&1
}
check_cmd "alerte d'essai EssaiPriseDePoste reçue par astreinte@medisphere.internal (Mailpit)" _f3d_s01_essai_recu

# --- 4. Index des runbooks ---------------------------------------------------------------------------
_f3d_s01_index="$_f3s_doc/index-runbooks.md"
_f3s_doc_present "$_f3d_s01_index" "index des runbooks publié ($_f3d_s01_index)"
_f3d_s01_rb_manquants() {
  local idx ids id
  idx="$(_f3s_fichier "$_f3d_s01_index" 2>/dev/null)" || return 1
  ids="$(_f3s_arbre docs | grep -E '/runbooks/RB-[0-9]{3}[^/]*\.md$' | sed -E 's|.*/(RB-[0-9]{3}).*|\1|' | sort -u)"
  [[ -n "$ids" ]] || { echo "aucun runbook trouvé"; return 1; }
  for id in $ids; do
    grep -q -- "$id" <<<"$idx" || printf '%s ' "$id"
  done
}
_f3d_s01_rb_ok() { local m; m="$(_f3d_s01_rb_manquants)" || return 1; [[ -z "$m" ]]; }
if _f3d_s01_rb_ok; then
  _ok "l'index cite tous les runbooks RB-NNN présents dans docs/**/runbooks/"
else
  _ko "l'index ne cite pas tous les runbooks du dépôt (manquants : $(_f3d_s01_rb_manquants 2>/dev/null | cut -c1-120))"
fi
_f3s_doc_contient "$_f3d_s01_index" 'RB-24[0-9].*(bris|glace)|(bris|glace).*RB-24[0-9]' "l'index signale le runbook de bris de glace"

# --- 5. Trousse d'astreinte --------------------------------------------------------------------------
_f3d_s01_trousse="$_f3s_doc/trousse-astreinte.md"
_f3s_doc_present "$_f3d_s01_trousse" "trousse d'astreinte publiée ($_f3d_s01_trousse)"
_f3s_doc_contient "$_f3d_s01_trousse" 'kubelogin|oidc-login' "trousse : accès au cluster par SSO"
_f3s_doc_contient "$_f3d_s01_trousse" 'openbao|bao login' "trousse : accès à OpenBao"
_f3s_doc_contient "$_f3d_s01_trousse" 'RB-240' "trousse : comptes de bris de glace (RB-240)"
_f3s_doc_contient "$_f3d_s01_trousse" '(bris de glace|RB-240).*20[0-9]{2}-[0-9]{2}-[0-9]{2}|20[0-9]{2}-[0-9]{2}-[0-9]{2}.*(bris de glace|RB-240)' \
  "trousse : date du dernier essai en lecture des comptes de bris de glace"
_f3s_doc_contient "$_f3d_s01_trousse" 'watchdog|dead man' "trousse : vérification du dead man's switch de mon01"
_f3s_doc_contient "$_f3d_s01_trousse" 'lab/bin/check F3 1|contr(ô|o)le de sant(é|e)' "trousse : contrôle de santé de début de journée"

# --- 6. Main courante ouverte ---------------------------------------------------------------------------
_f3d_s01_journal() { _f3s_arbre "$_f3s_doc/journal" | grep -Eq '/20[0-9]{2}-[0-9]{2}-[0-9]{2}\.md$'; }
check_cmd "main courante ouverte ($_f3s_doc/journal/AAAA-MM-JJ.md sur main)" _f3d_s01_journal

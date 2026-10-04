# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M01-E39 « Panne : la release automatique échoue »
#
# Toutes les variantes ouvrent aussi, au nom de Karim Benali (jeton d'emprunt d'identité),
# une MR « fix(docs): … » sur plateforme/medisphere : sa fusion déclenche le job release.
# Variantes :
#   1. jeton de projet « bot-release » renouvelé (rotation) : l'ancien, encore dans la variable
#      CI GITLAB_TOKEN, est révoqué → EINVALIDGLTOKEN — API ;
#   2. étiquettes protégées « v* » : création réservée à « personne » (No one) → la poussée de
#      l'étiquette vX.Y.Z par semantic-release est refusée — API ;
#   3. plugin @semantic-release/gitlab retiré de /opt/release-tools sur runner01 (déplacé dans
#      /var/lib/workbook) → « Cannot find module » — runner01 ;
#   4. variable CI GITLAB_TOKEN du projet restreinte à l'environnement « production » : le job
#      release ne la reçoit plus → ENOGLTOKEN — API (si la variable n'est pas au niveau du
#      projet, la panne bascule sur la variante 1).
# Sauvegardes : ~/.local/state/workbook/M01-E39/ sur adm01 (700 ; en variante 1 il contient le
#   NOUVEAU jeton du bot, fichier 600, supprimé à l'annulation) ; /var/lib/workbook/M01-E39.* sur runner01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

_E39_BRANCHE="fix/fiche-escalade"
_E39_FICHIER="docs/socle/escalade.md"
_E39_TITRE="fix(docs): mettre à jour la fiche d'escalade"
_E39_DESCRIPTION="Petite mise à jour de la fiche d'escalade. Une fois fusionnée, la release patch doit sortir toute seule : on vérifie au passage que la chaîne de release fonctionne. — Karim"

# Emplacement de la variable GITLAB_TOKEN : « projects/<id> » ou « groups/<id> » (affiché).
_E39_porteur_variable() {
  local pid gid
  pid="$(m01_projet_id)" || return 1
  if m01_api GET "projects/$pid/variables/GITLAB_TOKEN" >/dev/null 2>&1; then
    echo "projects/$pid"; return 0
  fi
  gid="$(m01_api GET "groups/plateforme" | jq -r '.id // empty')" || return 1
  if [[ -n "$gid" ]] && m01_api GET "groups/$gid/variables/GITLAB_TOKEN" >/dev/null 2>&1; then
    echo "groups/$gid"; return 0
  fi
  return 1
}

# Jeton de projet actif nommé bot-release : affiche son identifiant.
_E39_bot_id() {
  local pid
  pid="$(m01_projet_id)" || return 1
  m01_api GET "projects/$pid/access_tokens?state=active&per_page=100" \
    | jq -r '[.[] | select(.name == "bot-release" and .active and (.revoked | not))] | if length == 1 then .[0].id else empty end'
}

# MR de reproduction ouverte au nom de Karim (repli : au nom de l'apprenant).
_E39_ouvrir_mr() {
  local pid etat emprunt="" uid="" tid="" contenu actions r iid
  pid="$(m01_projet_id)" || return 1
  etat="$(m01_etat E39)"
  [[ -s "$etat/mr-iid" ]] && return 0
  m01_api DELETE "projects/$pid/repository/branches/$(m01_enc "$_E39_BRANCHE")" >/dev/null 2>&1 || true
  if emprunt="$(m01_jeton_emprunt karim.benali)"; then
    read -r uid tid _M01_JETON <<<"$emprunt"
  fi
  contenu="$(printf '%s\n' \
    "# Fiche d'escalade de la plateforme" "" \
    "| Niveau | Qui | Comment |" "|---|---|---|" \
    "| 1 | Astreinte plateforme | canal #astreinte, téléphone d'astreinte |" \
    "| 2 | Karim Benali | canal #plateforme |" \
    "| 3 | Claire Morel | téléphone, après accord de l'astreinte |" "" \
    "Dernière revue : $(date +%F).")"
  actions="$(jq -nc --arg f "$_E39_FICHIER" --arg c "$contenu" --arg b "$_E39_BRANCHE" --arg m "$_E39_TITRE" '{
      branch: $b, start_branch: "main", commit_message: $m,
      actions: [{action: "create", file_path: $f, content: $c}]}')"
  if m01_api GET "projects/$pid/repository/files/$(m01_enc "$_E39_FICHIER")?ref=main" >/dev/null 2>&1; then
    actions="$(jq -c '.actions[0].action = "update"' <<<"$actions")"
  fi
  r=0
  m01_api_json POST "projects/$pid/repository/commits" "$actions" >/dev/null || r=1
  if ((r == 0)); then
    iid="$(m01_api_json POST "projects/$pid/merge_requests" "$(jq -nc --arg b "$_E39_BRANCHE" \
        --arg t "$_E39_TITRE" --arg d "$_E39_DESCRIPTION" '{
        source_branch: $b, target_branch: "main", remove_source_branch: true, title: $t, description: $d}')" \
      | jq -r '.iid // empty')" || r=1
  fi
  _M01_JETON=""
  [[ -n "$tid" ]] && m01_jeton_emprunt_revoquer "$uid" "$tid"
  ((r == 0)) && [[ -n "${iid:-}" ]] || return 1
  printf '%s\n' "$iid" > "$etat/mr-iid"
}

panne_E39_v1() {
  m01_prerequis || return 1
  local pid etat tid porteur r jeton expire
  pid="$(m01_projet_id)" || return 1
  etat="$(m01_etat E39)"
  tid="$(_E39_bot_id)"
  [[ -n "$tid" ]] || { wb_avert "jeton de projet bot-release actif introuvable sur $_M01_PROJET"; return 1; }
  porteur="$(_E39_porteur_variable)" || { wb_avert "variable CI GITLAB_TOKEN introuvable"; return 1; }
  expire="$(m01_api GET "projects/$pid/access_tokens/$tid" | jq -r '.expires_at // empty')" || return 1
  _E39_ouvrir_mr || return 1
  # Rotation : l'ancien jeton (celui de la variable CI) est révoqué immédiatement.
  # Sans expires_at, le nouveau jeton expirerait dans une semaine : on garde l'échéance d'origine.
  r="$(m01_api POST "projects/$pid/access_tokens/$tid/rotate" ${expire:+--data-urlencode "expires_at=$expire"})" || return 1
  jeton="$(jq -r '.token // empty' <<<"$r")"
  [[ -n "$jeton" ]] || return 1
  ( umask 077; printf '%s' "$jeton" > "$etat/bot-release.nouveau" )
  jq -r '.id' <<<"$r" > "$etat/bot-release.id"
  printf '%s\n' "$porteur" > "$etat/porteur"
}

panne_E39_v2() {
  m01_prerequis || return 1
  local pid etat avant
  pid="$(m01_projet_id)" || return 1
  etat="$(m01_etat E39)"
  avant="$(m01_api GET "projects/$pid/protected_tags/$(m01_enc 'v*')")" \
    || { wb_avert "étiquettes « v* » non protégées sur $_M01_PROJET (M01-E25)"; return 1; }
  _E39_ouvrir_mr || return 1
  [[ -f "$etat/tag-protege.orig" ]] || printf '%s\n' "$avant" > "$etat/tag-protege.orig"
  m01_api DELETE "projects/$pid/protected_tags/$(m01_enc 'v*')" >/dev/null || return 1
  m01_api POST "projects/$pid/protected_tags" --data-urlencode 'name=v*' -d create_access_level=0 >/dev/null
}

panne_E39_v3() {
  _E39_ouvrir_mr || return 1
  wb_exec runner01 >/dev/null <<'EOF'
p=/opt/release-tools/node_modules/@semantic-release/gitlab
[ -d "$p" ] || { echo "plugin introuvable : $p" >&2; exit 1; }
[ -e "$WB_DIR/$WB_EX.plugin-gitlab" ] && exit 1
mv "$p" "$WB_DIR/$WB_EX.plugin-gitlab"
journal "plugin @semantic-release/gitlab déplacé de $p vers $WB_DIR/$WB_EX.plugin-gitlab"
EOF
}

panne_E39_v4() {
  m01_prerequis || return 1
  local porteur etat portee
  porteur="$(_E39_porteur_variable)" || { wb_avert "variable CI GITLAB_TOKEN introuvable"; return 1; }
  if [[ "$porteur" != projects/* ]]; then
    # Portée d'environnement des variables de groupe : fonction Premium. On bascule.
    WB_VAR=1
    panne_E39_v1
    return
  fi
  etat="$(m01_etat E39)"
  portee="$(m01_api GET "$porteur/variables/GITLAB_TOKEN" | jq -r '.environment_scope')" || return 1
  [[ "$portee" == "*" ]] || return 1
  _E39_ouvrir_mr || return 1
  printf '%s\n' "$porteur" > "$etat/porteur-portee"
  m01_api PUT "$porteur/variables/GITLAB_TOKEN" -d environment_scope=production >/dev/null
}

verifier_E39() {
  local pid etat
  pid="$(m01_projet_id)" || return 1
  etat="$(m01_etat E39)"
  [[ -s "$etat/mr-iid" ]] || return 1
  case "${WB_VAR:-}" in
    1) [[ -s "$etat/bot-release.nouveau" ]] ;;
    2) m01_api GET "projects/$pid/protected_tags/$(m01_enc 'v*')" \
         | jq -e '[.create_access_levels[].access_level] == [0]' >/dev/null ;;
    3) remote runner01 "test ! -e /opt/release-tools/node_modules/@semantic-release/gitlab" ;;
    4) m01_api GET "projects/$pid/variables/GITLAB_TOKEN" | jq -e '.environment_scope == "production"' >/dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E39() {
  local etat pid porteur tid niveau iid etatmr
  etat="$(m01_etat E39)"
  pid="$(m01_projet_id)" || { wb_avert "GitLab injoignable : relance l'annulation plus tard"; return 0; }
  # v1 : si le jeton actif est toujours celui issu de la rotation, on remet la variable d'aplomb.
  if [[ -s "$etat/bot-release.nouveau" ]]; then
    tid="$(_E39_bot_id)" || tid=""
    porteur="$(<"$etat/porteur")"
    if [[ "$tid" == "$(<"$etat/bot-release.id")" ]]; then
      m01_api PUT "$porteur/variables/GITLAB_TOKEN" --data-urlencode "value@$etat/bot-release.nouveau" >/dev/null \
        || wb_avert "variable GITLAB_TOKEN non mise à jour : fais-le à la main (jeton du bot à renouveler)"
    else
      wb_avert "le jeton bot-release a été modifié depuis l'injection : variable GITLAB_TOKEN laissée telle quelle"
    fi
    rm -f "$etat/bot-release.nouveau" "$etat/bot-release.id" "$etat/porteur"
  fi
  # v2
  if [[ -f "$etat/tag-protege.orig" ]]; then
    niveau="$(jq -r '[.create_access_levels[].access_level] | max // 40' "$etat/tag-protege.orig")"
    m01_api DELETE "projects/$pid/protected_tags/$(m01_enc 'v*')" >/dev/null 2>&1 || true
    if m01_api POST "projects/$pid/protected_tags" --data-urlencode 'name=v*' -d "create_access_level=$niveau" >/dev/null; then
      rm -f "$etat/tag-protege.orig"
    else
      wb_avert "protection des étiquettes v* non rétablie (niveau d'origine : $niveau)"
    fi
  fi
  # v4
  if [[ -f "$etat/porteur-portee" ]]; then
    porteur="$(<"$etat/porteur-portee")"
    if m01_api GET "$porteur/variables/GITLAB_TOKEN?filter%5Benvironment_scope%5D=production" >/dev/null 2>&1; then
      m01_api PUT "$porteur/variables/GITLAB_TOKEN?filter%5Benvironment_scope%5D=production" \
        -d 'environment_scope=*' >/dev/null || wb_avert "portée de GITLAB_TOKEN non rétablie"
    fi
    rm -f "$etat/porteur-portee"
  fi
  # v3
  if [[ "${WB_VAR:-}" == 3 || "${WB_VAR:-}" == annulation ]]; then
    wb_exec runner01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01"
p=/opt/release-tools/node_modules/@semantic-release/gitlab
if [ -d "$WB_DIR/$WB_EX.plugin-gitlab" ]; then
  if [ -e "$p" ]; then rm -rf "$WB_DIR/$WB_EX.plugin-gitlab"; else mv "$WB_DIR/$WB_EX.plugin-gitlab" "$p"; fi
  journal "annulation : plugin @semantic-release/gitlab remis en place"
fi
exit 0
EOF
  fi
  # MR de reproduction : fermée si elle est encore ouverte (fusionnée : c'est un vrai changement).
  if [[ -s "$etat/mr-iid" ]]; then
    iid="$(<"$etat/mr-iid")"
    etatmr="$(m01_api GET "projects/$pid/merge_requests/$iid" | jq -r '.state')" || etatmr=""
    if [[ "$etatmr" == opened ]]; then
      m01_api PUT "projects/$pid/merge_requests/$iid" -d state_event=close >/dev/null || true
      m01_api DELETE "projects/$pid/repository/branches/$(m01_enc "$_E39_BRANCHE")" >/dev/null 2>&1 || true
    fi
    rm -f "$etat/mr-iid"
  fi
  return 0
}

resume_E39() {
  echo "Karim a ouvert une MR de correctif sur plateforme/medisphere ; après fusion, aucune nouvelle version n'est publiée (job release en échec)."
}

symptome_E39() {
  wb_symptome "Ticket INC-2784 — De : Karim Benali" \
    "Lucas me signale que la release automatique de plateforme/medisphere est cassée depuis" \
    "l'intervention d'hier. Je viens d'ouvrir une petite MR « fix(docs): … » : relis-la," \
    "fusionne-la, et vérifie qu'une version patch sort toute seule (étiquette + Release GitLab)." \
    "Si le job release échoue, trouve pourquoi et répare sans contourner la chaîne." \
    "" \
    "Temps cible : 45 min (hors durée des pipelines). Contrôle : lab/bin/check 01 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E39 4 "$@"; }
fi

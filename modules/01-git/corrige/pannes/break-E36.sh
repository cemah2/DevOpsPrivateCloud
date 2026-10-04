# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M01-E36 « Panne : git push est refusé »
#
# Variantes (cible : pousser une nouvelle branche de ~/medisphere vers plateforme/medisphere) :
#   1. règle de branche protégée générique « * » (push : personne, merge : Maintainers) créée
#      sur plateforme/medisphere — API GitLab ;
#   2. hook global pre-receive « 00-quota-depots » déposé dans le custom_hooks_dir de Gitaly sur
#      git01 : il refuse toute poussée faute de trouver son fichier de configuration — git01 ;
#   3. projet plateforme/medisphere archivé (lecture seule) — API GitLab ;
#   4. URL de push distincte (remote.origin.pushurl) vers l'ancien espace de noms du
#      prestataire dans le clone ~/medisphere de l'apprenant — adm01.
# Sauvegardes : ~/.local/state/workbook/M01-E36/ sur adm01 (état API, ancienne pushurl) ;
#               /var/lib/workbook/M01-E36.* sur git01 (variante 2).
# Vérification : poussée réelle d'une branche jetable « wb-verif-e36 » (option ci.skip),
# supprimée aussitôt si elle passe (la panne n'est alors pas effective).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

_E36_PUSHURL="git@git01.par1.medisphere.internal:infoger/medisphere.git"
_E36_HOOK="00-quota-depots"

_E36_depot() { printf '%s\n' "${WB_DEPOT:-$HOME/medisphere}"; }

panne_E36_v1() {
  m01_prerequis || return 1
  local id etat
  id="$(m01_projet_id)" || return 1
  etat="$(m01_etat E36)"
  # Une règle « * » existante rendrait l'annulation destructive : on refuse.
  if m01_api GET "projects/$id/protected_branches/$(m01_enc '*')" >/dev/null 2>&1; then
    wb_avert "une règle de protection « * » existe déjà sur $_M01_PROJET"
    return 1
  fi
  m01_api POST "projects/$id/protected_branches" \
    --data-urlencode 'name=*' -d push_access_level=0 -d merge_access_level=40 >/dev/null || return 1
  printf '%s\n' "$id" > "$etat/protection-generique"
}

panne_E36_v2() {
  wb_exec git01 HOOK="$_E36_HOOK" >/dev/null <<'EOF'
cfg=/var/opt/gitlab/gitaly/config.toml
dir="$(sed -nE 's/^[[:space:]]*custom_hooks_dir[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$cfg" | head -n 1)"
[ -n "$dir" ] && [ -d "$dir/pre-receive.d" ] || { echo "hooks globaux non configurés (M01-E26)" >&2; exit 1; }
f="$dir/pre-receive.d/$HOOK"
sauver "$f"
cat > "$f" <<'HOOK'
#!/bin/bash
# Contrôle de quota des dépôts — déployé par InfoGér (lot INF-4417).
# Lit les quotas par espace de noms dans /etc/gitlab/quota-depots.conf.
set -u
CONF=/etc/gitlab/quota-depots.conf
if [ ! -r "$CONF" ]; then
  echo "GL-HOOK-ERR: quota-depots : configuration $CONF illisible, poussée refusée par sécurité."
  exit 1
fi
while read -r _ancien _nouveau _ref; do
  : # contrôle du quota (non implémenté dans cette version)
done
exit 0
HOOK
chown git:git "$f"
chmod 755 "$f"
journal "hook global pre-receive $f déposé (refuse tout : configuration absente)"
EOF
}

panne_E36_v3() {
  m01_prerequis || return 1
  local id etat
  id="$(m01_projet_id)" || return 1
  etat="$(m01_etat E36)"
  [[ "$(m01_api GET "projects/$id" | jq -r '.archived')" == "false" ]] || return 1
  m01_api POST "projects/$id/archive" >/dev/null || return 1
  printf '%s\n' "$id" > "$etat/projet-archive"
}

panne_E36_v4() {
  local d etat
  d="$(_E36_depot)"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git -C "$d" remote get-url origin >/dev/null 2>&1 || return 1
  etat="$(m01_etat E36)"
  if [[ ! -f "$etat/pushurl.orig" ]]; then
    git -C "$d" config --get-all remote.origin.pushurl > "$etat/pushurl.orig" || true
  fi
  git -C "$d" config --unset-all remote.origin.pushurl 2>/dev/null || true
  git -C "$d" config remote.origin.pushurl "$_E36_PUSHURL"
}

# Poussée de contrôle : 0 si la poussée est REFUSÉE (panne effective).
verifier_E36() {
  local d sha
  d="$(_E36_depot)"
  sha="$(git -C "$d" rev-parse --verify -q origin/main 2>/dev/null || git -C "$d" rev-parse --verify -q HEAD)" || return 1
  if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" \
     git -C "$d" push --no-verify -o ci.skip origin "$sha:refs/heads/wb-verif-e36" >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" \
      git -C "$d" push --no-verify origin :refs/heads/wb-verif-e36 >/dev/null 2>&1 || true
    return 1
  fi
  return 0
}

annuler_E36() {
  local etat d id
  etat="$(m01_etat E36)"
  d="$(_E36_depot)"
  # Variante 1 : on ne retire la règle « * » que si c'est la panne qui l'a créée.
  if [[ -f "$etat/protection-generique" ]]; then
    id="$(<"$etat/protection-generique")"
    m01_api DELETE "projects/$id/protected_branches/$(m01_enc '*')" >/dev/null 2>&1 || true
    if m01_api GET "projects/$id/protected_branches/$(m01_enc '*')" >/dev/null 2>&1; then
      wb_avert "la règle de protection « * » n'a pas pu être retirée"
    else
      rm -f "$etat/protection-generique"
    fi
  fi
  # Variante 3
  if [[ -f "$etat/projet-archive" ]]; then
    id="$(<"$etat/projet-archive")"
    if m01_api POST "projects/$id/unarchive" >/dev/null 2>&1 \
       || [[ "$(m01_api GET "projects/$id" | jq -r '.archived')" == "false" ]]; then
      rm -f "$etat/projet-archive"
    else
      wb_avert "le projet $_M01_PROJET n'a pas pu être désarchivé"
    fi
  fi
  # Variante 4 : on ne touche à pushurl que si elle vaut encore la valeur injectée.
  if [[ -f "$etat/pushurl.orig" ]]; then
    if git -C "$d" config --get-all remote.origin.pushurl 2>/dev/null | grep -qxF "$_E36_PUSHURL"; then
      git -C "$d" config --unset-all remote.origin.pushurl 2>/dev/null || true
      local u
      while IFS= read -r u; do
        [[ -n "$u" ]] && git -C "$d" config --add remote.origin.pushurl "$u"
      done < "$etat/pushurl.orig"
    fi
    rm -f "$etat/pushurl.orig"
  fi
  # Variante 2 (sur git01) : restaurer_fichiers ne fait rien s'il n'y a pas de manifeste.
  if [[ "${WB_VAR:-}" == 2 || "${WB_VAR:-}" == annulation ]]; then
    wb_exec git01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01"
restaurer_fichiers
journal "annulation : hooks globaux remis dans leur état d'origine"
EOF
  fi
  return 0
}

resume_E36() {
  echo "Depuis adm01, impossible de pousser une nouvelle branche de ~/medisphere vers plateforme/medisphere (le fetch fonctionne)."
}

symptome_E36() {
  wb_symptome "Ticket INC-2781 — De : Karim Benali" \
    "Tu m'as dit ce matin que tu ne pouvais plus pousser ta branche de travail sur" \
    "plateforme/medisphere depuis ~/medisphere : « git push » est refusé, alors que" \
    "« git fetch » fonctionne. Je ne peux pas tester de mon poste avant ce soir." \
    "Trouve la cause, corrige, et dis-moi si d'autres personnes sont touchées." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 01 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E36 4 "$@"; }
fi

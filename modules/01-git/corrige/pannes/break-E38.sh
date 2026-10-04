# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M01-E38 « Panne : le runner ne prend plus les jobs »
#
# Variantes :
#   1. entrée /etc/hosts sur runner01 qui envoie git01.par1.medisphere.internal vers une ancienne
#      adresse (10.10.20.120), service gitlab-runner redémarré — runner01 ;
#   2. jeton d'authentification (glrt-) du runner altéré d'un caractère dans
#      /etc/gitlab-runner/config.toml (rechargé automatiquement par le runner) — runner01 ;
#   3. étiquette « shell » du runner renommée « bash » dans GitLab — API (admin) ;
#   4. runner passé en « protégé » (access_level ref_protected) : il ne prend plus que les jobs
#      des branches protégées, les pipelines de MR restent en attente — API (admin).
# Sauvegardes : /var/lib/workbook/M01-E38.* sur runner01 (v1, v2) ;
#               ~/.local/state/workbook/M01-E38/ sur adm01 (identifiant du runner, étiquettes,
#               niveau d'accès d'origine).
# ⚠️ Le redémarrage du service (v1) interrompt un job en cours : injecter hors pipeline.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

# Identifiant du runner d'instance du socle (étiquettes shell + socle). Mémorisé dans l'état.
_E38_runner_id() {
  local etat ids
  etat="$(m01_etat E38)"
  if [[ -s "$etat/runner-id" ]]; then cat "$etat/runner-id"; return 0; fi
  ids="$(m01_api GET "runners/all?type=instance_type&tag_list=shell,socle&per_page=100" | jq -r '.[].id')" || return 1
  if [[ "$(grep -c . <<<"$ids")" -ne 1 ]]; then
    wb_avert "il faut exactement un runner d'instance étiqueté shell et socle (trouvés : $(grep -c . <<<"$ids"))"
    return 1
  fi
  printf '%s\n' "$ids" | tee "$etat/runner-id"
}

panne_E38_v1() {
  wb_exec runner01 >/dev/null <<'EOF'
grep -q 'git01\.par1\.medisphere\.internal' /etc/hosts && { echo "/etc/hosts mentionne déjà git01" >&2; exit 1; }
sauver /etc/hosts
printf '\n# Migration forge (InfoGér, INF-4402) — à retirer après bascule\n10.10.20.120\tgit01.par1.medisphere.internal git01\n' >> /etc/hosts
systemctl restart gitlab-runner
journal "/etc/hosts : git01.par1.medisphere.internal → 10.10.20.120, gitlab-runner redémarré"
EOF
}

panne_E38_v2() {
  wb_exec runner01 >/dev/null <<'EOF'
f=/etc/gitlab-runner/config.toml
grep -Eq '^[[:space:]]*token[[:space:]]*=[[:space:]]*"glrt-' "$f" || { echo "jeton glrt- introuvable" >&2; exit 1; }
sauver "$f"
# Dernier caractère du premier jeton changé (a → b, sinon → a) : même longueur, même préfixe.
perl -pi -e 'if (!$fait && s/^(\s*token\s*=\s*"glrt-[^"]*)(.)"/$1.($2 eq "a" ? "b" : "a")."\""/e) { $fait = 1 }' "$f"
cmp -s "$f" "$WB_DIR/$WB_EX._etc_gitlab-runner_config.toml.orig" && { restaurer_fichiers; exit 1; }
# Empreinte de l'état injecté : l'annulation ne restaure que si le fichier est encore celui-là
# (si l'apprenant a réinitialisé le jeton dans GitLab, l'ancien config.toml ne vaut plus rien).
sha256sum "$f" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.config-injecte"
journal "config.toml : dernier caractère du jeton glrt- modifié"
EOF
}

panne_E38_v3() {
  m01_prerequis || return 1
  local id etat tags neuf
  id="$(_E38_runner_id)" || return 1
  etat="$(m01_etat E38)"
  tags="$(m01_api GET "runners/$id" | jq -c '.tag_list')" || return 1
  jq -e 'index("shell")' <<<"$tags" >/dev/null || return 1
  [[ -f "$etat/tags.orig" ]] || printf '%s\n' "$tags" > "$etat/tags.orig"
  neuf="$(jq -c 'map(if . == "shell" then "bash" else . end)' <<<"$tags")"
  m01_api_json PUT "runners/$id" "$(jq -nc --argjson t "$neuf" '{tag_list: $t}')" >/dev/null
}

panne_E38_v4() {
  m01_prerequis || return 1
  local id etat niveau
  id="$(_E38_runner_id)" || return 1
  etat="$(m01_etat E38)"
  niveau="$(m01_api GET "runners/$id" | jq -r '.access_level')" || return 1
  [[ "$niveau" == not_protected ]] || return 1
  [[ -f "$etat/access-level.orig" ]] || printf '%s\n' "$niveau" > "$etat/access-level.orig"
  m01_api PUT "runners/$id" -d access_level=ref_protected >/dev/null
}

verifier_E38() {
  local id etat
  etat="$(m01_etat E38)"
  case "${WB_VAR:-}" in
    1)
      remote runner01 "getent hosts git01.par1.medisphere.internal | grep -q '^10\.10\.20\.120[[:space:]]'" ;;
    2)
      wb_exec runner01 >/dev/null <<'EOF'
! cmp -s /etc/gitlab-runner/config.toml "$WB_DIR/$WB_EX._etc_gitlab-runner_config.toml.orig"
EOF
      ;;
    3)
      id="$(<"$etat/runner-id")"
      m01_api GET "runners/$id" | jq -e '(.tag_list | index("shell")) == null' >/dev/null ;;
    4)
      id="$(<"$etat/runner-id")"
      m01_api GET "runners/$id" | jq -e '.access_level == "ref_protected"' >/dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E38() {
  local etat id
  etat="$(m01_etat E38)"
  if [[ "${WB_VAR:-}" != 3 && "${WB_VAR:-}" != 4 ]]; then
    wb_exec runner01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur runner01"
m="$WB_DIR/$WB_EX.manifeste"
if [ -f "$m" ]; then
  # On ne restaure que ce qui porte encore la marque de la panne : une réparation faite
  # entre-temps par l'apprenant (jeton réinitialisé, /etc/hosts nettoyé) est conservée.
  panne=0
  grep -q '^10\.10\.20\.120[[:space:]]' /etc/hosts && panne=1
  if [ -f "$WB_DIR/$WB_EX.config-injecte" ] \
     && [ "$(sha256sum /etc/gitlab-runner/config.toml | cut -d' ' -f1)" = "$(cat "$WB_DIR/$WB_EX.config-injecte")" ]; then
    panne=1
  fi
  if [ "$panne" = 1 ]; then
    restaurer_fichiers
    systemctl restart gitlab-runner
    journal "annulation : /etc/hosts et config.toml rétablis, gitlab-runner redémarré"
  else
    while IFS="$(printf '\t')" read -r _src dst; do
      [ "$dst" = ABSENT ] || rm -f "$dst"
    done < "$m"
    rm -f "$m"
    journal "annulation : panne déjà réparée, sauvegardes supprimées sans rien restaurer"
  fi
fi
rm -f "$WB_DIR/$WB_EX.config-injecte"
exit 0
EOF
  fi
  if [[ -s "$etat/runner-id" ]]; then
    id="$(<"$etat/runner-id")"
    if [[ -f "$etat/tags.orig" ]]; then
      if m01_api_json PUT "runners/$id" "$(jq -nc --argjson t "$(<"$etat/tags.orig")" '{tag_list: $t}')" >/dev/null; then
        rm -f "$etat/tags.orig"
      else
        wb_avert "étiquettes du runner $id non rétablies"
      fi
    fi
    if [[ -f "$etat/access-level.orig" ]]; then
      if m01_api PUT "runners/$id" -d "access_level=$(<"$etat/access-level.orig")" >/dev/null; then
        rm -f "$etat/access-level.orig"
      else
        wb_avert "niveau d'accès du runner $id non rétabli"
      fi
    fi
    [[ -f "$etat/tags.orig" || -f "$etat/access-level.orig" ]] || rm -f "$etat/runner-id"
  fi
  return 0
}

resume_E38() {
  echo "Les jobs des pipelines de MR restent « en attente » (pending) et ne démarrent jamais."
}

symptome_E38() {
  wb_symptome "Ticket INC-2783 — De : Julien Petit" \
    "Depuis ce matin, les jobs du pipeline de ma MR restent « en attente » (pending) et ne" \
    "démarrent jamais. J'ai relancé deux fois, rien. Tu peux regarder ? Sans pipeline vert," \
    "on ne peut plus rien fusionner. (Pour reproduire : ouvre une MR sur plateforme/medisphere.)" \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 01 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E38 4 "$@"; }
fi

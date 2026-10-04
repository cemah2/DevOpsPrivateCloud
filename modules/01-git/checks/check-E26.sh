# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E26.sh — M01-E26 « Hooks côté serveur : imposer les règles même sans pre-commit »
# Lancé depuis adm01. Lecture seule : les hooks installés sur git01 sont exécutés
# sur un dépôt JETABLE créé dans un dossier temporaire de git01 (supprimé ensuite),
# jamais sur un dépôt de GitLab. Rien n'est poussé.

title "M01-E26 — Hooks côté serveur"
require_cmd ssh jq curl base64

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }

# Dossier des hooks globaux, tel que Gitaly l'utilise (configuration générée).
_m01_DIR_CMD='sudo -n sed -nE "s/^[[:space:]]*custom_hooks_dir[[:space:]]*=[[:space:]]*[\"'"'"']([^\"'"'"']+)[\"'"'"'].*/\1/p" /var/opt/gitlab/gitaly/config.toml | head -n 1'

check_ssh "git01 : custom_hooks_dir présent dans la configuration de Gitaly" git01 "test -n \"\$($_m01_DIR_CMD)\""
check_ssh "git01 : réglages de concurrence de Gitaly conservés (s'ils sont dans gitlab.rb)" git01 \
  '! sudo -n grep -q "max_per_repo" /etc/gitlab/gitlab.rb || sudo -n grep -q "max_per_repo" /var/opt/gitlab/gitaly/config.toml'
check_ssh "git01 : au moins un hook exécutable dans pre-receive.d, propriétaire git" git01 \
  "d=\"\$($_m01_DIR_CMD)/pre-receive.d\"; sudo -n find \"\$d\" -maxdepth 1 -type f -user git -perm -u+x 2>/dev/null | grep -q ."
check_ssh "git01 : aucun hook de pre-receive.d n'appartient à un autre utilisateur que git" git01 \
  "d=\"\$($_m01_DIR_CMD)/pre-receive.d\"; sudo -n test -d \"\$d\" && ! sudo -n find \"\$d\" -mindepth 1 ! -user git 2>/dev/null | grep -q ."

# --- Simulation : la chaîne des hooks installés, comme Gitaly l'appelle -------------------
# Arguments : DOSSIER_HOOKS PROJET SCÉNARIO ATTENDU(accepte|refuse)
read -r -d '' _m01_SIM <<'SIM' || true
set -u
hooks="$1"; projet="$2"; scenario="$3"; attendu="$4"
G="$(command -v git || echo /opt/gitlab/embedded/bin/git)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=check GIT_AUTHOR_EMAIL=check@medisphere.internal GIT_COMMITTER_NAME=check GIT_COMMITTER_EMAIL=check@medisphere.internal
"$G" init -q --bare "$T/s.git" && "$G" init -q "$T/w" || exit 9
cd "$T/w" && echo a > a && "$G" add a && "$G" commit -q -m "chore: base" && "$G" push -q "$T/s.git" HEAD:refs/heads/main || exit 9
base="$("$G" rev-parse HEAD)"
case "$scenario" in
  conforme)     echo b >> a; "$G" commit -qam "feat(socle): ajoute un contrôle" ;;
  non-conforme) echo b >> a; "$G" commit -qam "Ajoute un contrôle" ;;
  fusion)       echo b >> a; "$G" commit -qam "Merge branch 'feat/x' into 'main'" ;;
  gros-fichier) head -c 6291456 /dev/urandom > gros.bin; "$G" add gros.bin; "$G" commit -qm "chore: ajoute un binaire" ;;
  gros-retire)  head -c 6291456 /dev/urandom > gros.bin; "$G" add gros.bin; "$G" commit -qm "chore: ajoute un binaire"
                "$G" rm -q gros.bin; "$G" commit -qm "chore: retire le binaire" ;;
esac
neuf="$("$G" rev-parse HEAD)"
rc=0
for h in "$hooks"/*; do
  [ -f "$h" ] && [ -x "$h" ] || continue
  case "$h" in *~) continue ;; esac
  (cd "$T/s.git" && printf '%s %s refs/heads/essai\n' "$base" "$neuf" | env GIT_DIR="$T/s.git" \
     GIT_ALTERNATE_OBJECT_DIRECTORIES="$T/w/.git/objects" GL_PROJECT_PATH="$projet" GL_USERNAME=check \
     GL_ID=user-1 GL_PROTOCOL=ssh GL_REPOSITORY=project-1 GIT_PUSH_OPTION_COUNT=0 "$h") > "$T/sortie" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || break
done
if [ "$attendu" = accepte ]; then [ "$rc" -eq 0 ]; else [ "$rc" -ne 0 ] && grep -q '^GL-HOOK-ERR:' "$T/sortie"; fi
SIM
_m01_SIM64="$(printf '%s\n' "$_m01_SIM" | base64 -w0)"

_m01_simuler() {   # _m01_simuler "description" PROJET SCÉNARIO ATTENDU
  check_ssh "$1" git01 \
    "d=\"\$($_m01_DIR_CMD)/pre-receive.d\"; sudo -n test -d \"\$d\" && echo $_m01_SIM64 | base64 -d | sudo -n -u git -H bash -s -- \"\$d\" '$2' '$3' '$4'"
}
_m01_simuler "simulation : message conforme accepté (plateforme/medisphere)"         plateforme/medisphere conforme     accepte
_m01_simuler "simulation : message non conforme refusé avec GL-HOOK-ERR (plateforme/)" plateforme/medisphere non-conforme refuse
_m01_simuler "simulation : commit de fusion de GitLab accepté"                       plateforme/medisphere fusion       accepte
_m01_simuler "simulation : fichier de 6 Mio refusé (plateforme/)"                    plateforme/medisphere gros-fichier refuse
_m01_simuler "simulation : fichier de 6 Mio ajouté puis retiré : refusé quand même"   plateforme/medisphere gros-retire  refuse
_m01_simuler "simulation : hors périmètre (formation/git-labo), message libre accepté" formation/git-labo   non-conforme accepte
_m01_simuler "simulation : hors périmètre (formation/git-labo), gros fichier accepté"  formation/git-labo   gros-fichier accepte

# --- Versionnage -----------------------------------------------------------------------------
check_cmd "plateforme/medisphere : hooks versionnés sous forge/hooks/ (branche main)" \
  jq -e 'length > 0' <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=forge%2Fhooks&recursive=true&per_page=50")"

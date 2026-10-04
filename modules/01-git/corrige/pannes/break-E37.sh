# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M01-E37 « Panne : GitLab répond 502 »
#
# Variantes (toutes sur git01, chaîne nginx → gitlab-workhorse → puma) :
#   1. fichier GÉNÉRÉ /var/opt/gitlab/gitlab-rails/etc/puma.rb modifié à la main : Puma écoute
#      sur « gitlab.sock » au lieu de « gitlab.socket », Workhorse ne le trouve plus (puma redémarré) ;
#   2. dossier des sockets de Puma (/var/opt/gitlab/gitlab-rails/sockets) passé en root:root 0700 :
#      Puma ne peut plus créer sa socket et redémarre en boucle (puma redémarré) ;
#   3. amont « gitlab-workhorse » de la configuration nginx GÉNÉRÉE pointant vers une socket
#      inexistante (nginx rechargé) : nginx répond 502, Git en SSH fonctionne encore.
# Sauvegardes : /var/lib/workbook/M01-E37.* sur git01 (fichiers, propriétaire et droits d'origine).
# Aucune variante ne lance « gitlab-ctl reconfigure » ; c'est en revanche un correctif légitime.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

panne_E37_v1() {
  wb_exec git01 >/dev/null <<'EOF'
f=/var/opt/gitlab/gitlab-rails/etc/puma.rb
grep -q "gitlab-rails/sockets/gitlab\.socket'" "$f" || { echo "puma.rb inattendu" >&2; exit 1; }
sauver "$f"
sed -i "s#gitlab-rails/sockets/gitlab\.socket'#gitlab-rails/sockets/gitlab.sock'#" "$f"
gitlab-ctl restart puma >/dev/null
journal "puma.rb : bind unix vers gitlab.sock (au lieu de gitlab.socket), puma redémarré"
EOF
}

panne_E37_v2() {
  wb_exec git01 >/dev/null <<'EOF'
d=/var/opt/gitlab/gitlab-rails/sockets
[ -d "$d" ] || exit 1
[ -f "$WB_DIR/$WB_EX.droits-sockets" ] || stat -c '%U:%G %a' "$d" > "$WB_DIR/$WB_EX.droits-sockets"
chown root:root "$d"
chmod 0700 "$d"
gitlab-ctl restart puma >/dev/null
journal "$d passé en root:root 0700 (Puma ne peut plus y créer sa socket), puma redémarré"
EOF
}

panne_E37_v3() {
  wb_exec git01 >/dev/null <<'EOF'
f="$(grep -rl 'gitlab-workhorse/sockets/socket' /var/opt/gitlab/nginx/conf/ 2>/dev/null | head -n 1)"
[ -n "$f" ] || { echo "amont gitlab-workhorse introuvable" >&2; exit 1; }
sauver "$f"
# Seul un chemin change : la syntaxe reste valide (nginx ne teste pas l'existence des sockets amont).
sed -i 's#gitlab-workhorse/sockets/socket#gitlab-workhorse/socket#' "$f"
gitlab-ctl hup nginx >/dev/null
journal "$f : amont gitlab-workhorse vers une socket inexistante, nginx rechargé"
EOF
}

# La page d'accueil doit répondre 502 (on laisse à Puma le temps de redémarrer : jusqu'à 4 min).
verifier_E37() {
  local i code
  for ((i = 0; i < 24; i++)); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_M01_GITLAB/users/sign_in" 2>/dev/null)" || true
    if [[ "$code" == 502 ]]; then
      sleep 20
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_M01_GITLAB/users/sign_in" 2>/dev/null)" || true
      [[ "$code" == 502 ]] && return 0
    fi
    sleep 10
  done
  return 1
}

annuler_E37() {
  wb_exec git01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01"
m="$WB_DIR/$WB_EX.manifeste"
puma=0; nginx=0
if [ -f "$m" ]; then
  grep -q 'puma\.rb' "$m" && puma=1
  grep -q 'nginx' "$m" && nginx=1
fi
restaurer_fichiers
if [ -f "$WB_DIR/$WB_EX.droits-sockets" ]; then
  read -r proprio droits < "$WB_DIR/$WB_EX.droits-sockets"
  chown "$proprio" /var/opt/gitlab/gitlab-rails/sockets && chmod "$droits" /var/opt/gitlab/gitlab-rails/sockets \
    && rm -f "$WB_DIR/$WB_EX.droits-sockets"
  puma=1
fi
[ "$puma" = 1 ] && gitlab-ctl restart puma >/dev/null
[ "$nginx" = 1 ] && gitlab-ctl hup nginx >/dev/null
journal "annulation : configuration de puma/nginx et droits des sockets rétablis"
exit 0
EOF
  echo "GitLab redémarre : compte 1 à 3 minutes avant que la page d'accueil réponde de nouveau."
}

resume_E37() {
  echo "L'interface web de GitLab affiche une erreur 502 pour tout le monde."
}

symptome_E37() {
  wb_symptome "Ticket INC-2782 — De : Nadia Roussel" \
    "Depuis une dizaine de minutes, https://git01.par1.medisphere.internal affiche une page" \
    "d'erreur 502 pour tout le monde. Julien demande si ses « git push » sont concernés." \
    "Personne n'a annoncé d'intervention. Rétablis le service et donne-moi la cause." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 01 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E37 3 "$@"; }
fi

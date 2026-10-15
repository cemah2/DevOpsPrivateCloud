# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M12-E40 « Panne : le service Quadlet ne démarre pas »
#
# Témoin : service Quadlet recette-cache du compte app sur ctr02 (réinstallé dans sa version de
# référence avant l'injection). Variantes :
#   1. syntaxe : « PublishPort= » devient « PublishPorts= » → le générateur Quadlet rejette le
#      fichier (clé non prise en charge) et ne produit aucune unité : « Unit recette-cache.service not
#      found » ;
#   2. dépendance réseau : recette.network a été supprimé (« fichier inutile ») → l'unité référence un
#      réseau Quadlet qui n'existe plus (selon la version : unité non générée, ou dépendance
#      recette-network.service introuvable) ;
#   3. linger : la persistance de session du compte app est désactivée (loginctl disable-linger) →
#      sans session ouverte, le gestionnaire systemd de app s'arrête et le conteneur avec lui ;
#   4. [Install] : la section [Install] a été retirée et ctr02 redémarré (maintenance) → le service
#      n'est plus tiré par default.target : il ne revient pas au démarrage (« systemctl --user enable »
#      refuse une unité générée).
# Annulation : linger réactivé, témoin réinstallé dans sa version de référence.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_mE40_une() {
  m12_exec "$_M12_CTR02" VAR="$1" <<'EOF' || return $?
Q="$H_APP/.config/containers/systemd"
f="$Q/recette-cache.container"
case "$VAR" in
  1)
    sauver "$f"
    remplacer_ "$f" "PublishPort=127.0.0.1:6379:6379" "PublishPorts=127.0.0.1:6379:6379" || exit 10
    en_app systemctl --user stop recette-cache.service >/dev/null 2>&1 || true
    en_app systemctl --user daemon-reload
    en_app systemctl --user start recette-cache.service >/dev/null 2>&1 || true
    journal "clé PublishPorts= (inconnue) dans recette-cache.container"
    ;;
  2)
    [ -f "$Q/recette.network" ] || exit 10
    sauver "$Q/recette.network"
    en_app systemctl --user stop recette-cache.service >/dev/null 2>&1 || true
    rm -f "$Q/recette.network"
    en_app systemctl --user daemon-reload
    en_app systemctl --user start recette-cache.service >/dev/null 2>&1 || true
    journal "recette.network supprimé"
    ;;
  3)
    loginctl disable-linger app
    # Sans session ouverte, logind arrête user@UID ; on termine les sessions résiduelles de app.
    loginctl terminate-user app >/dev/null 2>&1 || true
    journal "linger désactivé pour app"
    ;;
  4)
    sauver "$f"
    python3 - "$f" <<'PY' || exit 10
import re, sys
f = sys.argv[1]
t = open(f, encoding="utf-8").read()
n = re.sub(r"\n\[Install\]\n[^\[]*", "\n", t)
if n == t:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(n)
PY
    en_app systemctl --user daemon-reload
    journal "section [Install] retirée, redémarrage de ctr02"
    systemd-run --quiet --on-active=5s /bin/systemctl reboot >/dev/null 2>&1 || exit 1
    ;;
esac
EOF
  if [[ "$1" == 4 ]]; then
    echo "Redémarrage de $_M12_CTR02…" >&2
    sleep 20
    m12_attendre 240 m12_existe "$_M12_CTR02" || { wb_avert "$_M12_CTR02 ne revient pas après le redémarrage"; return 1; }
    sleep 20
  fi
}

panne_E40_v1() { m12_cache_preparer "$_M12_CTR02" && m12_essayer E40 4 1; }
panne_E40_v2() { m12_cache_preparer "$_M12_CTR02" && m12_essayer E40 4 2; }
panne_E40_v3() { m12_cache_preparer "$_M12_CTR02" && m12_essayer E40 4 3; }
panne_E40_v4() { m12_cache_preparer "$_M12_CTR02" && m12_essayer E40 4 4; }

_e40_casse() { ! m12_cache_sain "$_M12_CTR02"; }
verifier_E40() { sleep 10; m12_attendre 60 _e40_casse; }

annuler_E40() {
  if m12_existe "$_M12_CTR02"; then
    m12_exec "$_M12_CTR02" <<'EOF' >/dev/null 2>&1 || true
loginctl enable-linger app
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
    m12_cache_installer "$_M12_CTR02" >/dev/null || wb_avert "témoin recette-cache de ctr02 non réinstallé"
  fi
  m12_oublier E40
}

resume_E40() {
  echo "Sur ctr02, le cache de recette (service Quadlet recette-cache du compte app) ne tourne plus."
}

symptome_E40() {
  local detail
  case "$WB_VAR" in
    3) detail="Depuis que Lucas s'est déconnecté de ctr02 hier soir, le cache de recette (service Quadlet recette-cache du compte app) ne tourne plus. Il dit n'avoir modifié aucun fichier." ;;
    4) detail="ctr02 a été redémarré cette nuit pour maintenance. Depuis, le cache de recette (service Quadlet recette-cache du compte app) n'est pas revenu. Lucas l'a « réparé » hier en éditant le fichier." ;;
    *) detail="Lucas a retouché hier les fichiers Quadlet du compte app sur ctr02. Depuis, le service recette-cache ne démarre plus et « systemctl --user status recette-cache » ne le trouve même pas." ;;
  esac
  wb_symptome "Ticket INC-3940 — De : Karim Benali" \
    "$detail" \
    "Remets-le en service de façon durable (il doit survivre à un redémarrage de ctr02 et à la" \
    "déconnexion de tout le monde), et dis-moi comment tu l'as diagnostiqué." \
    "" \
    "Accès : ssh ctr02 puis « sudo machinectl shell app@ » (ou sudo -iu app). Temps cible : 45 min." \
    "Contrôle : lab/bin/check 12 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E40 4 "$@"; }
fi

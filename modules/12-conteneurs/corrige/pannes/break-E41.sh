# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M12-E41 « Panne : le conteneur est tué sans prévenir »
#
# Pile de recette de ctr01, remise à sa version de référence avant l'injection. Variantes :
#   1. mémoire : mem_limit et memswap_limit de l'API passés de 256m à 24m (« optimisation ») →
#      le noyau tue le processus dès l'import des bibliothèques (OOMKilled: true, code 137), boucle ;
#   2. processus : pids_limit de l'API passé de 128 à 4 (« durcissement ») → la réserve de connexions
#      PostgreSQL ne peut pas créer ses fils d'exécution (RuntimeError: can't start new thread),
#      l'application s'arrête au démarrage, boucle ;
#   3. santé + redémarrage : la sonde de l'API devient « curl -fsS http://127.0.0.1:8000/sante »
#      (curl absent de l'image → toujours en échec) et un « autoheal » maison (minuterie systemd
#      recette-autoheal.timer sur ctr01) redémarre tout conteneur étiqueté autoheal=true et
#      « unhealthy » → l'API est redémarrée toutes les une à deux minutes, sans erreur dans ses journaux.
# Annulation : minuterie et script retirés, pile de recette de référence.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_mE41_une() {
  case "$1" in
    1)
      m12_compose_remplacer '    mem_limit: 256m
    memswap_limit: 256m' '    mem_limit: 24m
    memswap_limit: 24m' || return $?
      ;;
    2)
      m12_compose_remplacer '    pids_limit: 128' '    pids_limit: 4' || return $?
      ;;
    3)
      m12_compose_remplacer '      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('"'"'http://127.0.0.1:8000/sante'"'"', timeout=3)"]
      interval: 15s' '      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/sante"]
      interval: 15s' || return $?
      m12_compose_remplacer '    mem_limit: 256m
    memswap_limit: 256m' '    labels:
      autoheal: "true"
    mem_limit: 256m
    memswap_limit: 256m' || return $?
      m12_exec "$_M12_CTR01" <<'EOF' || return 1
cat > /usr/local/sbin/recette-autoheal <<'SH'
#!/bin/sh
# recette-autoheal — redémarre les conteneurs « unhealthy » étiquetés autoheal=true (Lucas, « en
# attendant Kubernetes »).
for c in $(docker ps -q --filter label=autoheal=true --filter health=unhealthy); do
  logger -t recette-autoheal "redémarrage de $(docker inspect -f '{{.Name}}' "$c")"
  docker restart -t 10 "$c" >/dev/null
done
SH
chmod 755 /usr/local/sbin/recette-autoheal
cat > /etc/systemd/system/recette-autoheal.service <<'U'
[Unit]
Description=Redémarrage des conteneurs en mauvaise santé (recette)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/recette-autoheal
U
cat > /etc/systemd/system/recette-autoheal.timer <<'U'
[Unit]
Description=Redémarrage des conteneurs en mauvaise santé (recette), toutes les 30 s

[Timer]
OnBootSec=1min
OnUnitActiveSec=30s
AccuracySec=5s

[Install]
WantedBy=timers.target
U
touch -d '3 days ago' /usr/local/sbin/recette-autoheal /etc/systemd/system/recette-autoheal.service /etc/systemd/system/recette-autoheal.timer
systemctl daemon-reload
systemctl enable --now recette-autoheal.timer >/dev/null 2>&1 || exit 1
journal "minuterie recette-autoheal posée"
EOF
      ;;
  esac
  m12_compose up -d --no-deps --no-build api || true
}

# _e41_casse — 0 si l'API a été tuée ou redémarrée depuis l'injection.
_e41_casse() {
  local e
  e="$(m12_etat_service api)"
  [[ "$e" != "running healthy"* ]] || (( ${e##* } >= 1 ))
}

panne_E41_v1() { m12_recette_preparer && m12_essayer E41 3 1; }
panne_E41_v2() { m12_recette_preparer && m12_essayer E41 3 2; }
panne_E41_v3() { m12_recette_preparer && m12_essayer E41 3 3; }

verifier_E41() {
  if [[ "$WB_VAR" == 3 ]]; then
    echo "Attente du premier redémarrage par la minuterie (jusqu'à 3 minutes)…" >&2
    m12_attendre 180 _e41_redemarree
  else
    sleep 10
    m12_attendre 60 _e41_casse
  fi
}

# _e41_redemarree — 0 si le conteneur de l'API a été redémarré au moins une fois (variante 3).
_e41_redemarree() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1
journalctl -t recette-autoheal --since "-10 min" -q --no-pager | grep -q "redémarrage"
EOF
}

annuler_E41() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
systemctl disable --now recette-autoheal.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/recette-autoheal.timer /etc/systemd/system/recette-autoheal.service /usr/local/sbin/recette-autoheal
systemctl daemon-reload
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
  m12_recette_reinitialiser
  m12_oublier E41
}

resume_E41() {
  case "${WB_VAR:-1}" in
    3) echo "L'API de recette disparaît puis revient toutes les une à deux minutes ; ses journaux ne montrent pas d'erreur." ;;
    *) echo "L'API de recette redémarre sans cesse depuis la « passe d'optimisation » de Lucas ; rien de clair dans ses journaux." ;;
  esac
}

symptome_E41() {
  local detail
  case "$WB_VAR" in
    3) detail="Depuis deux jours, l'API de recette (ctr01) est coupée toutes les une à deux minutes pendant quelques secondes : les tests automatiques de Julien échouent au hasard. Ses journaux ne montrent aucune erreur : elle s'arrête proprement, puis redémarre." ;;
    *) detail="Depuis la « passe d'optimisation des ressources » de Lucas hier soir, l'API de recette (ctr01) ne tient plus : « docker compose ps » la montre qui redémarre sans cesse, et Lucas ne trouve « rien dans les journaux qui explique pourquoi elle est tuée »." ;;
  esac
  wb_symptome "Ticket INC-3947 — De : Julien Petit" \
    "$detail" \
    "Trouve qui ou quoi arrête le conteneur, prouve-le, et corrige sans retirer les protections utiles." \
    "" \
    "Pile : ctr01, /srv/recette. Temps cible : 45 min. Contrôle : lab/bin/check 12 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E41 3 "$@"; }
fi

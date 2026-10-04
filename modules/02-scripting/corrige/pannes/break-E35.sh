# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M02-E35 « Panne : le script marche à la main mais pas la nuit »
#
# Cible : l'unité ms-verif-sauvegardes.service de adm01 (M02-E26). Le script contrôlé
# n'est jamais modifié : c'est son ENVIRONNEMENT D'EXÉCUTION sous systemd qui change.
# Variantes (drop-ins dans /etc/systemd/system/ms-verif-sauvegardes.service.d/) :
#   1. 20-durcissement.conf : ProtectHome=yes (+ ProtectSystem=strict, PrivateTmp) —
#      /home est invisible pour le service (secret et, le cas échéant, script du clone) ;
#   2. 10-journal.conf : User=root — HOME=/root, le fichier de secret de admin introuvable ;
#   3. 30-proxy.conf : http(s)_proxy vers 10.10.20.250:3128 (rien n'y écoute) ; le no_proxy
#      fourni ne couvre que des noms, pas l'adresse IP de l'API Proxmox ;
#   4. override.conf : ExecStart redirigé vers une vieille copie 0.3.0 déposée dans
#      /usr/local/sbin, qui utilise le jeton wb-automation@pve!lab (pas de droit sur pbs-par2).
# Si une variante reste sans effet sur ce lab (le service réussit encore), la suivante est
# essayée : la variante enregistrée est celle qui a réellement cassé le service.
# Sauvegardes : /var/lib/workbook/M02-E35.* sur adm01 (fichiers créés notés ABSENT).
# L'injection lance une fois le service (l'échec « de la nuit » apparaît dans le journal).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E35_SVC=ms-verif-sauvegardes.service
_E35_FICHIERS="$WB_ROOT/modules/02-scripting/corrige/fichiers/M02-E35/panne"

# _e35_precondition — le contrôle doit réussir AVANT la panne (sinon le diagnostic est faussé).
_e35_precondition() {
  wb_exec localhost SVC="$_E35_SVC" >/dev/null <<'EOF'
systemctl cat "$SVC" >/dev/null 2>&1 || { echo "unité $SVC absente (M02-E26 non fait ?)" >&2; exit 1; }
if ! timeout 300 systemctl start "$SVC"; then
  echo "le contrôle $SVC échoue déjà avant la panne : lab/bin/check 02 26" >&2
  exit 1
fi
EOF
}

# _e35_une N — injecte la variante N et lance le service. Codes : 0 panne effective,
# 10 variante sans effet (déjà annulée), autre = erreur.
_e35_une() {
  local n="$1" ancien=""
  if ((n == 4)); then
    ancien="$(base64 -w0 "$_E35_FICHIERS/ms-verif-sauvegardes-0.3.0")" || return 1
  fi
  WB_VAR="$n" wb_exec localhost SVC="$_E35_SVC" N="$n" ANCIEN="$ancien" >/dev/null <<'EOF'
d="/etc/systemd/system/$SVC.d"
mkdir -p "$d"
case "$N" in
  1)
    f="$d/20-durcissement.conf"; sauver "$f"
    cat >"$f" <<'UNIT'
# SEC-380 : durcissement des services planifiés de adm01 (revue S. Laurent / K. Benali)
[Service]
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
UNIT
    ;;
  2)
    f="$d/10-journal.conf"; sauver "$f"
    cat >"$f" <<'UNIT'
# CHG-380 : le rapport du contrôle doit aussi pouvoir être écrit dans /var/log/ms-outils (L. Martin)
[Service]
User=root
UNIT
    ;;
  3)
    f="$d/30-proxy.conf"; sauver "$f"
    cat >"$f" <<'UNIT'
# Modèle commun des services de l'équipe : sortie Internet par le proxy d'entreprise (CHG-381)
[Service]
Environment=http_proxy=http://10.10.20.250:3128 https_proxy=http://10.10.20.250:3128 no_proxy=localhost,127.0.0.1,.medisphere.internal
UNIT
    ;;
  4)
    sauver /usr/local/sbin/ms-verif-sauvegardes
    printf '%s' "$ANCIEN" | base64 -d >/usr/local/sbin/ms-verif-sauvegardes
    chmod 755 /usr/local/sbin/ms-verif-sauvegardes
    touch -d '2026-05-12 16:40' /usr/local/sbin/ms-verif-sauvegardes
    f="$d/override.conf"; sauver "$f"
    cat >"$f" <<'UNIT'
[Service]
ExecStart=
ExecStart=/usr/local/sbin/ms-verif-sauvegardes
UNIT
    ;;
esac
systemctl daemon-reload
journal "drop-in $f posé sur $SVC"
# Le passage « de la nuit » : il doit échouer.
if timeout 300 systemctl start "$SVC" 2>/dev/null; then
  journal "variante $N sans effet sur ce lab : retrait"
  restaurer_fichiers
  systemctl daemon-reload
  exit 10
fi
exit 0
EOF
}

# _e35_injecter N — essaie N, puis les autres variantes, jusqu'à en trouver une effective.
_e35_injecter() {
  local depart="$1" i n rc
  _e35_precondition || return 1
  for ((i = 0; i < 4; i++)); do
    n=$(((depart - 1 + i) % 4 + 1))
    rc=0
    _e35_une "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante n'a d'effet sur ce service (environnement inattendu)"
  return 1
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

verifier_E35() {
  local res
  res="$(systemctl show "$_E35_SVC" -p Result --value 2>/dev/null)"
  [[ -n "$res" && "$res" != success ]] \
    && [[ -n "$(find "/etc/systemd/system/$_E35_SVC.d" -maxdepth 1 -name '*.conf' 2>/dev/null)" ]]
}

annuler_E35() {
  wb_exec localhost SVC="$_E35_SVC" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
restaurer_fichiers
rmdir "/etc/systemd/system/$SVC.d" 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed "$SVC" 2>/dev/null || true
journal "annulation : environnement d'origine de $SVC rétabli"
# Un passage réussi efface le statut d'échec (le contrôle redevient vert).
timeout 300 systemctl start "$SVC" || echo "le contrôle échoue encore après annulation" >&2
exit 0
EOF
}

resume_E35() {
  echo "Le contrôle planifié des sauvegardes de 07:30 est en échec alors que le script lancé à la main dit que tout va bien."
}

symptome_E35() {
  wb_symptome "Ticket INC-2841 — De : Nadia Roussel" \
    "Ce matin, le contrôle des sauvegardes de 07:30 sur adm01 est en échec (notification reçue," \
    "« systemctl status ms-verif-sauvegardes » en rouge). Lucas a relancé le script à la main :" \
    "tout est vert, les sauvegardes de la nuit sont bien là. Il dit que « ça marche chez lui »." \
    "Je ne veux pas d'un contrôle qui crie au loup : il doit passer en planifié, pas à la main." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 02 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E35 4 "$@"; }
fi

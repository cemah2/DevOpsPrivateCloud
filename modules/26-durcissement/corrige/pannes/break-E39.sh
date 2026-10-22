# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M26-E39 « Panne : un service confiné ne démarre plus »
#
# Le confinement (MAC ou durcissement systemd) a coupé un service non critique. Variantes :
#   1. profil AppArmor de Mailpit en « enforce » sans le chemin de données : Mailpit ne démarre plus
#      (mon01, Debian) ;
#   2. contexte SELinux faux après une « copie » sur la clé TLS de node_exporter : il ne peut plus la
#      lire, l'unité échoue (ceph01, Rocky, enforcing) ;
#   3. unité systemd durcie (ProtectSystem=strict sans ReadWritePaths) : node_exporter ne peut plus
#      écrire et redémarre en boucle (mon01, Debian).
#
# Injection et annulation par SSH+sudo (sudo n'est pas cassé ici). Sauvegardes sur la VM.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_e39_cible() { case "$1" in 2) printf '%s\n' "$_M26_ROCKY" ;; *) printf '%s\n' "$_M26_MON01" ;; esac; }

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }

_e39_injecter() {
  local n="$1" cible
  cible="$(_e39_cible "$n")"
  m26_hote_sain "$cible" || return 1
  m26_ecrire E39 variante "$n"
  m26_ecrire E39 cible "$cible"
  case "$n" in
    1)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 10
p=/etc/apparmor.d/usr.local.bin.mailpit
command -v apparmor_parser >/dev/null 2>&1 || { echo "AppArmor absent" >&2; exit 10; }
[ -f "$p" ] || { echo "profil AppArmor de Mailpit absent (M26-E13 non fait ?)" >&2; exit 10; }
u="$(unite_de mailpit)" || { echo "unité mailpit introuvable" >&2; exit 10; }
sauver "$p"
# Retire la ligne qui autorise la lecture/écriture du répertoire de données (/var/lib/mailpit).
sed -i '/\/var\/lib\/mailpit/d' "$p"
apparmor_parser -r "$p"
systemctl restart "$u" 2>/dev/null || true
journal "profil AppArmor de Mailpit en enforce sans /var/lib/mailpit ; $u redémarré"
EOF
      ;;
    2)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 10
[ "$(getenforce 2>/dev/null)" = Enforcing ] || { echo "SELinux pas en enforcing" >&2; exit 10; }
k=/etc/node_exporter/tls/key.pem
[ -f "$k" ] || k="$(ls /etc/node_exporter/tls/*key*.pem 2>/dev/null | head -n1)"
[ -n "$k" ] && [ -f "$k" ] || { echo "clé TLS de node_exporter introuvable" >&2; exit 10; }
u="$(unite_de node_exporter)" || { echo "unité node_exporter introuvable" >&2; exit 10; }
sauver "$k"
chcon -t user_tmp_t "$k"
systemctl restart "$u" 2>/dev/null || true
journal "contexte SELinux de $k passé à user_tmp_t ; $u redémarré"
EOF
      ;;
    3)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 10
u="$(unite_de node_exporter)" || { echo "unité node_exporter introuvable" >&2; exit 10; }
d="/etc/systemd/system/${u}.d"
f="$d/90-durcissement.conf"
sauver "$f"
mkdir -p "$d"
printf '[Service]\nProtectSystem=strict\nReadWritePaths=\n' > "$f"
systemctl daemon-reload
systemctl restart "$u" 2>/dev/null || true
journal "drop-in ProtectSystem=strict sans ReadWritePaths sur $u ; redémarré"
EOF
      ;;
  esac
  m26_journal E39 "variante $n posée sur $cible"
}

_e39_unite() { case "$1" in 1) echo mailpit ;; *) echo node_exporter ;; esac; }

verifier_E39() {
  local cible bin
  cible="$(m26_lire E39 cible)"
  bin="$(_e39_unite "$WB_VAR")"
  [[ -n "$cible" ]] || return 1
  # La panne est effective si l'unité n'est pas « active ».
  ! m26_ssh "$cible" "u=\$(systemctl list-units --all --type=service --no-legend --plain | awk '/$bin/{print \$1; exit}'); systemctl is-active \"\$u\"" >/dev/null 2>&1
}

annuler_E39() {
  local cible
  cible="$(m26_lire E39 cible)"
  if [[ -n "$cible" ]]; then
    m26_wb_exec "$cible" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $cible"
restaurer_fichiers
if command -v apparmor_parser >/dev/null 2>&1 && [ -f /etc/apparmor.d/usr.local.bin.mailpit ]; then
  apparmor_parser -r /etc/apparmor.d/usr.local.bin.mailpit 2>/dev/null || true
fi
[ "$(getenforce 2>/dev/null)" = Enforcing ] && restorecon -F /etc/node_exporter/tls/* 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true
for b in mailpit node_exporter; do
  u="$(unite_de "$b" 2>/dev/null)" && systemctl restart "$u" 2>/dev/null || true
done
journal "annulation : confinement rétabli, services redémarrés"
EOF
  fi
  m26_oublier E39 variante
  m26_oublier E39 cible
  m26_journal E39 "annulation"
}

resume_E39() { echo "Un service confiné (Mailpit ou node_exporter) ne démarre plus depuis le durcissement."; }

symptome_E39() {
  local cible
  cible="$(m26_lire E39 cible)"
  wb_symptome "Ticket INC-5339 — De : Nadia Roussel" \
    "Sur ${cible:-une VM du socle}, un service refuse de démarrer depuis la vague de durcissement :" \
    "« systemctl status » le montre en échec (failed), et le journal parle de permission refusée" \
    "alors que les droits du fichier ont l'air bons. On a posé du MAC (AppArmor/SELinux) et durci des" \
    "unités systemd cette semaine. Ne désactive pas le MAC pour « voir » : trouve ce qui manque." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 26 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E39 3 "$@"; }
fi

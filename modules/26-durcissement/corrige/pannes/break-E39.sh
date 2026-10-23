# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M26-E39 « Panne : un service confiné ne démarre plus »
#
# Le confinement (MAC ou durcissement systemd) a coupé un service non critique. Variantes :
#   1. profil AppArmor de Mailpit en « enforce » sans le chemin de données : Mailpit ne démarre plus
#      (mon01, Debian) ;
#   2. contexte SELinux faux après une « copie » sur le dossier de journal d'AIDE (/var/log/aide passé
#      en user_tmp_t) : la vérification d'intégrité, qui tourne CONFINÉE (aide_t, M26-E12/E13), ne peut
#      plus écrire son rapport et l'unité aide-verification.service échoue (hôte Rocky, enforcing).
#      (Pas node_exporter : installé dans /usr/local/bin, il tourne en unconfined_service_t, E13 ; un
#      mauvais contexte sur ses fichiers ne lui fait rien) ;
#   3. drop-in systemd qui VIDE ReadWritePaths de Mailpit (ProtectSystem=strict sans exception) : sa
#      base devient en lecture seule, Mailpit échoue (mon01). (Pas node_exporter : il n'écrit rien, il
#      a déjà ProtectSystem=strict depuis M21.)
# Chaque variante vérifie son effet (unité en échec) ; sans effet sur ce lab, la suivante est essayée.
#
# Injection et annulation par SSH+sudo (sudo n'est pas cassé ici). Sauvegardes sur la VM.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_e39_cible() { case "$1" in 2) printf '%s\n' "$_M26_ROCKY" ;; *) printf '%s\n' "$_M26_MON01" ;; esac; }
_e39_unite() { case "$1" in 2) echo aide-verification ;; *) echo mailpit ;; esac; }

panne_E39_v1() { m26_essayer E39 3 1; }
panne_E39_v2() { m26_essayer E39 3 2; }
panne_E39_v3() { m26_essayer E39 3 3; }

_m26E39_une() {
  local n="$1" cible
  cible="$(_e39_cible "$n")"
  m26_hote_sain "$cible" || return 10
  m26_ecrire E39 variante "$n"
  m26_ecrire E39 cible "$cible"
  case "$n" in
    1)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || { _e39_defaire; return 10; }
p=/etc/apparmor.d/usr.local.bin.mailpit
command -v apparmor_parser >/dev/null 2>&1 || { echo "AppArmor absent" >&2; exit 10; }
[ -f "$p" ] || { echo "profil AppArmor de Mailpit absent (M26-E13 non fait ?)" >&2; exit 10; }
grep -q 'flags=(complain)' "$p" && { echo "profil en complain : sans effet" >&2; exit 10; }
u="$(unite_de mailpit)" || { echo "unité mailpit introuvable" >&2; exit 10; }
sauver "$p"
# Retire les lignes qui autorisent le répertoire de données (/var/lib/mailpit).
sed -i '/\/var\/lib\/mailpit/d' "$p"
apparmor_parser -r "$p"
systemctl restart "$u" 2>/dev/null || true
journal "profil AppArmor de Mailpit en enforce sans /var/lib/mailpit ; $u redémarré"
EOF
      ;;
    2)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || { _e39_defaire; return 10; }
[ "$(getenforce 2>/dev/null)" = Enforcing ] || { echo "SELinux pas en enforcing" >&2; exit 10; }
systemctl cat aide-verification.service >/dev/null 2>&1 || { echo "aide-verification.service absent (M26-E12)" >&2; exit 10; }
d=/var/log/aide
[ -d "$d" ] || { echo "$d absent" >&2; exit 10; }
# Mémorise le contexte actuel (restorecon le remet de toute façon : c'est le contexte de la politique).
ls -dZ "$d" > "$WB_DIR/$WB_EX.contexte" 2>/dev/null
chcon -R -t user_tmp_t "$d"
systemctl reset-failed aide-verification.service 2>/dev/null || true
systemctl start --no-block aide-verification.service
journal "contexte SELinux de $d passé à user_tmp_t ; aide-verification.service lancé"
EOF
      ;;
    3)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || { _e39_defaire; return 10; }
u="$(unite_de mailpit)" || { echo "unité mailpit introuvable" >&2; exit 10; }
d="/etc/systemd/system/${u}.d"
f="$d/90-durcissement.conf"
sauver "$f"
mkdir -p "$d"
# « ReadWritePaths= » vide REMET À ZÉRO la liste de l'unité (dont /var/lib/mailpit).
printf '[Service]\nProtectSystem=strict\nReadWritePaths=\n' > "$f"
systemctl daemon-reload
systemctl restart "$u" 2>/dev/null || true
journal "drop-in ProtectSystem=strict + ReadWritePaths vide sur $u ; redémarré"
EOF
      ;;
  esac
  m26_journal E39 "variante $n posée sur $cible"
  m26_attendre 120 _e39_effet || { _e39_defaire; return 10; }
}

# Effet : l'unité visée est en échec (« failed », ou plus « active » pour un service permanent).
_e39_effet() {
  local cible unite
  cible="$(m26_lire E39 cible)"
  unite="$(_e39_unite "$(m26_lire E39 variante)")"
  [[ -n "$cible" ]] || return 1
  m26_ssh "$cible" "u=\$(systemctl list-units --all --type=service --no-legend --plain | awk '/$unite/{print \$1; exit}'); [ -n \"\$u\" ] && systemctl is-failed --quiet \"\$u\"" >/dev/null 2>&1
}

verifier_E39() { _e39_effet; }

_e39_defaire() {
  local cible
  cible="$(m26_lire E39 cible)"
  [[ -n "$cible" ]] || return 0
  m26_wb_exec "$cible" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $cible"
restaurer_fichiers
if command -v apparmor_parser >/dev/null 2>&1 && [ -f /etc/apparmor.d/usr.local.bin.mailpit ]; then
  apparmor_parser -r /etc/apparmor.d/usr.local.bin.mailpit 2>/dev/null || true
fi
if [ -f "$WB_DIR/$WB_EX.contexte" ]; then
  restorecon -RF /var/log/aide 2>/dev/null || true
  systemctl reset-failed aide-verification.service 2>/dev/null || true
  rm -f "$WB_DIR/$WB_EX.contexte"
fi
systemctl daemon-reload 2>/dev/null || true
u="$(unite_de mailpit 2>/dev/null)" && { systemctl reset-failed "$u" 2>/dev/null; systemctl restart "$u" 2>/dev/null; } || true
journal "annulation : confinement rétabli, services relancés"
EOF
}

annuler_E39() {
  _e39_defaire
  m26_oublier E39 variante
  m26_oublier E39 cible
  m26_journal E39 "annulation"
}

resume_E39() { echo "Un service confiné (Mailpit, ou la vérification d'intégrité AIDE sur un hôte Rocky) est en échec depuis le durcissement."; }

symptome_E39() {
  local cible
  cible="$(m26_lire E39 cible)"
  wb_symptome "Ticket INC-5339 — De : Nadia Roussel" \
    "Sur ${cible:-une VM du socle}, un service est en échec depuis la vague de durcissement :" \
    "« systemctl --failed » le montre, et le journal parle de permission refusée (ou d'écriture" \
    "impossible) alors que les droits du fichier ont l'air bons. On a posé du MAC (AppArmor/SELinux)" \
    "et durci des unités systemd cette semaine. Ne désactive pas le MAC pour « voir » : trouve ce qui manque." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 26 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E39 3 "$@"; }
fi

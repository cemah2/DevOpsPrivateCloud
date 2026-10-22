# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E42.sh — M21-E42 « Panne : la supervision hors cluster est aveugle »
#
# Tout se passe sur mon01 (supervision témoin, rôle supervision_temoin ; fichiers retrouvés par la ligne
# de commande des unités systemd, sauvegardés avant modification dans /var/lib/workbook/) :
#   1. blackbox_exporter : les modules de type http passés en IPv6 seulement (preferred_ip_protocol: ip6,
#      ip_protocol_fallback: false, « préparation IPv6 » de Lucas) : le lab est en IPv4, toutes les
#      sondes HTTPS échouent alors que les services répondent ;
#   2. nftables local de mon01 : table « durcissement_sortie » qui jette tout ce qui part vers
#      10.10.41.60 et 10.10.41.61 : le témoin ne voit plus la supervision du cluster (Watchdog absent,
#      sondes /-/healthy en échec) et crie à la panne générale ;
#   3. fichier de cibles (file_sd) du Prometheus témoin qui en contient le plus, vidé (« désactivé le
#      temps de la migration ») : les sondes disparaissent sans aucune alerte ;
#   4. Alertmanager témoin : smarthost passé en :587 (Mailpit n'écoute que le 25), puis une alerte
#      d'essai EssaiTemoinAstreinte est envoyée à l'Alertmanager témoin : elle ne part jamais.
# Annulation seulement si le fichier est encore celui de la panne (empreinte) ou si la table existe.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_m21E42_une() {
  local n="$1" rc=0
  m21_ecrire E42 variante "$n"
  case "$n" in
    1)
      m21_wb_exec "$_M21_MON01" >/dev/null <<'EOF' || rc=$?
u="$(unite_de blackbox_exporter)" || exit 10
f="$(option_de "$u" config.file)"; [ -n "$f" ] && [ -f "$f" ] || exit 10
python3 -c 'import yaml' 2>/dev/null || exit 10
sauver "$f"
python3 - "$f" <<'PY' || exit 10
import sys, yaml
chemin = sys.argv[1]
with open(chemin, encoding="utf-8") as fic:
    conf = yaml.safe_load(fic)
n = 0
for nom, module in (conf.get("modules") or {}).items():
    if module.get("prober") == "http":
        http = module.setdefault("http", {}) or {}
        module["http"] = http
        http["preferred_ip_protocol"] = "ip6"
        http["ip_protocol_fallback"] = False
        n += 1
if n == 0:
    sys.exit(1)
with open(chemin, "w", encoding="utf-8") as fic:
    fic.write("# PLAT-2242 (Lucas) : préparation IPv6 des sondes\n")
    yaml.safe_dump(conf, fic, sort_keys=False, allow_unicode=True)
PY
sha256sum "$f" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.empreinte"
systemctl kill -s HUP "$u"
journal "blackbox : modules http passés en IPv6 seulement ($f)"
EOF
      ;;
    2)
      m21_wb_exec "$_M21_MON01" >/dev/null <<'EOF' || rc=$?
command -v nft >/dev/null || exit 10
nft list table inet durcissement_sortie >/dev/null 2>&1 && exit 10
nft -f - <<'NFT' || exit 1
table inet durcissement_sortie {
  chain sortie {
    type filter hook output priority -10; policy accept;
    ip daddr { 10.10.41.60, 10.10.41.61 } counter drop comment "PLAT-2242 sorties de mon01 limitées (Lucas)"
  }
}
NFT
journal "table nftables durcissement_sortie ajoutée (10.10.41.60-61 injoignables)"
EOF
      ;;
    3)
      m21_wb_exec "$_M21_MON01" >/dev/null <<'EOF' || rc=$?
u="$(unite_de prometheus)" || exit 10
c="$(option_de "$u" config.file)"; [ -n "$c" ] && [ -f "$c" ] || exit 10
python3 -c 'import yaml' 2>/dev/null || exit 10
best="$(python3 - "$c" <<'PY'
import glob, os, sys, yaml
conf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
base = os.path.dirname(sys.argv[1])
meilleur, nb = "", 0
for sc in conf.get("scrape_configs") or []:
    for sd in sc.get("file_sd_configs") or []:
        for motif in sd.get("files") or []:
            for f in glob.glob(motif if os.path.isabs(motif) else os.path.join(base, motif)):
                try:
                    groupes = yaml.safe_load(open(f, encoding="utf-8")) or []
                    n = sum(len(g.get("targets") or []) for g in groupes)
                except Exception:
                    continue
                if n > nb:
                    meilleur, nb = f, n
print(meilleur)
PY
)"
[ -n "$best" ] && [ -f "$best" ] || exit 10
sauver "$best"
{ printf '# PLAT-2242 (Lucas) : sondes désactivées le temps de la migration, à remettre après\n'
  sed 's/^/# /' "$WB_DIR/$WB_EX.$(printf '%s' "$best" | tr '/' '_').orig"
  printf '[]\n'; } > "$best.tmp" && cat "$best.tmp" > "$best" && rm -f "$best.tmp"
sha256sum "$best" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.empreinte"
printf '%s\n' "$best" > "$WB_DIR/$WB_EX.fichier"
journal "cibles du témoin vidées : $best"
EOF
      ;;
    4)
      m21_wb_exec "$_M21_MON01" >/dev/null <<'EOF' || rc=$?
u="$(unite_de alertmanager)" || exit 10
f="$(option_de "$u" config.file)"; [ -n "$f" ] && [ -f "$f" ] || exit 10
grep -q 'smtp\.par1\.medisphere\.internal:25' "$f" || exit 10
sauver "$f"
sed -i 's/smtp\.par1\.medisphere\.internal:25\b/smtp.par1.medisphere.internal:587/' "$f"
sha256sum "$f" | cut -d' ' -f1 > "$WB_DIR/$WB_EX.empreinte"
systemctl kill -s HUP "$u"
sleep 3
debut="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"; fin="$(date -u -d '+3 hours' +%Y-%m-%dT%H:%M:%S.000Z)"
curl -sf --max-time 10 -X POST -H 'Content-Type: application/json' http://127.0.0.1:9093/api/v2/alerts \
  --data "[{\"labels\":{\"alertname\":\"EssaiTemoinAstreinte\",\"gravite\":\"critique\",\"equipe\":\"plateforme\",\"origine\":\"mon01\"},\"annotations\":{\"resume\":\"Essai mensuel de l'Alertmanager témoin\"},\"startsAt\":\"$debut\",\"endsAt\":\"$fin\"}]" >/dev/null || exit 1
journal "Alertmanager témoin : smarthost en :587, alerte d'essai envoyée"
EOF
      ;;
  esac
  ((rc == 0)) || { _e42_defaire "$n"; return "$rc"; }
  m21_journal E42 "variante $n posée"
  m21_attendre 240 _e42_effet "$n" || { _e42_defaire "$n"; return 10; }
}

# _e42_effet N — constat sur mon01 (lecture seule).
_e42_effet() {
  case "$1" in
    1) m21_ssh "$_M21_MON01" 'curl -sf --max-time 5 http://127.0.0.1:9115/config | grep -q "preferred_ip_protocol: ip6"' >/dev/null 2>&1 ;;
    2) ! m21_ssh "$_M21_MON01" 'curl -sf --max-time 5 -o /dev/null http://10.10.41.60:9090/-/healthy' >/dev/null 2>&1 ;;
    3)
      m21_ssh "$_M21_MON01" 'f="$(cat /var/lib/workbook/M21-E42.fichier 2>/dev/null)"; [ -n "$f" ] &&
        curl -sf --max-time 5 http://127.0.0.1:9090/api/v1/targets | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if not any(\"$f\" in json.dumps(t.get(\"discoveredLabels\", {})) for t in d[\"data\"][\"activeTargets\"]) else 1)"' >/dev/null 2>&1
      ;;
    4) m21_ssh "$_M21_MON01" 'curl -sf --max-time 5 http://127.0.0.1:9093/api/v2/status | grep -q "medisphere.internal:587"' >/dev/null 2>&1 ;;
  esac
}

_e42_defaire() {
  case "$1" in
    1 | 3 | 4)
      m21_wb_exec "$_M21_MON01" WB_E42_N="$1" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur mon01"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
e="$(cat "$WB_DIR/$WB_EX.empreinte" 2>/dev/null)"
f="$(cut -f1 "$WB_DIR/$WB_EX.manifeste" | head -n 1)"
if [ -n "$e" ] && [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$e" ]; then
  restaurer_fichiers
  journal "annulation : $f rétabli"
  case "$WB_E42_N" in
    1) u="$(unite_de blackbox_exporter)" && systemctl kill -s HUP "$u" ;;
    4) u="$(unite_de alertmanager)" && systemctl kill -s HUP "$u" ;;
  esac
else
  oublier_fichiers
fi
if [ "$WB_E42_N" = 4 ]; then
  maintenant="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  curl -sf --max-time 10 -X POST -H 'Content-Type: application/json' http://127.0.0.1:9093/api/v2/alerts \
    --data "[{\"labels\":{\"alertname\":\"EssaiTemoinAstreinte\",\"gravite\":\"critique\",\"equipe\":\"plateforme\",\"origine\":\"mon01\"},\"endsAt\":\"$maintenant\"}]" >/dev/null || true
fi
rm -f "$WB_DIR/$WB_EX.empreinte" "$WB_DIR/$WB_EX.fichier"
EOF
      ;;
    2)
      m21_wb_exec "$_M21_MON01" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur mon01 (nftables)"
if nft list table inet durcissement_sortie >/dev/null 2>&1; then
  nft delete table inet durcissement_sortie && journal "annulation : table durcissement_sortie retirée"
fi
EOF
      ;;
  esac
  return 0
}

panne_E42_v1() { m21_preparer && m21_essayer E42 4 1; }
panne_E42_v2() { m21_preparer && m21_essayer E42 4 2; }
panne_E42_v3() { m21_preparer && m21_essayer E42 4 3; }
panne_E42_v4() { m21_preparer && m21_essayer E42 4 4; }

verifier_E42() { _e42_effet "$WB_VAR"; }

annuler_E42() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-4]$ ]] || v="$(m21_lire E42 variante)"
  [[ -n "$v" ]] && _e42_defaire "$v"
  m21_oublier E42 variante
  m21_journal E42 "annulation"
}

resume_E42() {
  case "${WB_VAR:-}" in
    1) echo "Le témoin de mon01 annonce toutes les sondes HTTPS en échec alors que les services répondent." ;;
    2) echo "Le témoin de mon01 annonce que la supervision du cluster est morte, alors que Grafana répond." ;;
    3) echo "Des sondes ont disparu de la page des cibles du témoin de mon01, sans la moindre alerte." ;;
    *) echo "L'essai mensuel de l'Alertmanager témoin (EssaiTemoinAstreinte) n'a produit aucun courriel." ;;
  esac
}

symptome_E42() {
  local l
  case "${WB_VAR:-}" in
    1) l="Le témoin de mon01 me mitraille : toutes les sondes HTTPS (GitLab, NetBox, Grafana…) en échec. Or tout répond depuis mon poste." ;;
    2) l="Le témoin de mon01 m'annonce que la supervision du cluster est morte (Watchdog absent). Grafana et les alertes du cluster marchent." ;;
    3) l="Karim a remarqué que des sondes ont disparu de la page des cibles du témoin (mon01:9090). Aucune alerte, rien." ;;
    *) l="Essai mensuel : j'ai injecté EssaiTemoinAstreinte dans l'Alertmanager témoin de mon01 à $(date +%H:%M). Rien reçu." ;;
  esac
  wb_symptome "Ticket INC-4842 — De : Nadia Roussel" \
    "$l" \
    "Le témoin est ce qui doit me prévenir quand le cluster entier tombe : s'il est faux, je n'ai plus" \
    "rien. Lucas est intervenu sur mon01 cette semaine." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 21 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E42 4 "$@"; }
fi

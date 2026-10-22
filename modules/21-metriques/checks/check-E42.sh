# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M21-E42 « Panne : la supervision hors cluster est aveugle » : sur mon01, les trois
# services du témoin tournent, blackbox sonde en IPv4, le témoin joint la vue globale et Alertmanager du
# cluster, chaque fichier de cibles contient des cibles et toutes sont up, l'Alertmanager témoin envoie
# par smtp…:25, RB-218, panne close. Lecture seule (SSH + sudo -n : systemctl, curl locaux, lecture).

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E42 — La supervision témoin voit juste"
require_cmd ssh jq

if ! _m21x_mon01 'true'; then
  skip "mon01" "SSH + sudo -n vers $_m21x_mon01 impossible depuis ce poste"
else
  for _m21_e42_b in prometheus alertmanager blackbox_exporter; do
    check_cmd "mon01 : service du binaire $_m21_e42_b actif" \
      _m21x_mon01 "$_M21X_UNITE
u=\"\$(unite_de $_m21_e42_b)\" && systemctl is-active -q \"\$u\""
  done
  check_cmd "mon01 : blackbox ne force pas l'IPv6 sans repli (le lab est en IPv4)" \
    _m21x_mon01 'c="$(curl -sf --max-time 5 http://127.0.0.1:9115/config)" && ! grep -q "ip_protocol_fallback: false" <<<"$c"'
  check_cmd "mon01 joint la vue globale du cluster (10.10.41.60:9090/-/healthy)" \
    _m21x_mon01 'curl -sf --max-time 5 -o /dev/null http://10.10.41.60:9090/-/healthy'
  check_cmd "mon01 joint Alertmanager du cluster (10.10.41.61:9093/-/healthy)" \
    _m21x_mon01 'curl -sf --max-time 5 -o /dev/null http://10.10.41.61:9093/-/healthy'
  check_cmd "mon01 : chaque fichier de cibles (file_sd) du témoin contient au moins une cible" \
    _m21x_mon01 "$_M21X_UNITE"'
u="$(unite_de prometheus)" && c="$(option_de "$u" config.file)" && [ -f "$c" ] &&
python3 - "$c" <<'"'PY'"'
import glob, os, sys, yaml
conf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
base = os.path.dirname(sys.argv[1])
ok = True
for sc in conf.get("scrape_configs") or []:
    for sd in sc.get("file_sd_configs") or []:
        for motif in sd.get("files") or []:
            fichiers = glob.glob(motif if os.path.isabs(motif) else os.path.join(base, motif))
            for f in fichiers:
                g = yaml.safe_load(open(f, encoding="utf-8")) or []
                if sum(len(x.get("targets") or []) for x in g) == 0:
                    ok = False
sys.exit(0 if ok else 1)
PY'
  check_cmd "mon01 : toutes les cibles du Prometheus témoin sont up" \
    _m21x_mon01 'curl -sf --max-time 5 "http://127.0.0.1:9090/api/v1/targets?state=active" |
      python3 -c "import json,sys; t=[x[\"health\"] for x in json.load(sys.stdin)[\"data\"][\"activeTargets\"]]; sys.exit(0 if t and all(h == \"up\" for h in t) else 1)"'
  check_cmd "mon01 : sondes du témoin en succès (probe_success)" \
    _m21x_mon01 'curl -sf --max-time 5 --data-urlencode "query=min(probe_success)" http://127.0.0.1:9090/api/v1/query |
      python3 -c "import json,sys; r=json.load(sys.stdin)[\"data\"][\"result\"]; sys.exit(0 if r and r[0][\"value\"][1] == \"1\" else 1)"'
  check_cmd "mon01 : l'Alertmanager témoin envoie par smtp.par1.medisphere.internal:25" \
    _m21x_mon01 'c="$(curl -sf --max-time 5 http://127.0.0.1:9093/api/v2/status)" && grep -q "smtp.par1.medisphere.internal:25" <<<"$c" && ! grep -q "medisphere.internal:587" <<<"$c"'
  check_cmd "mon01 : aucune règle nftables locale ne coupe la sortie vers 10.10.41.60-61" \
    _m21x_mon01 '! nft list ruleset 2>/dev/null | grep -E "daddr.*10\.10\.41\.6[01].*(drop|reject)"'
fi
check_cmd "RB-218 : section sur le témoin de mon01" _m21x_doc_contient "$_m21x_rb/RB-218-*.md" '^#+ .*(t[ée]moin|mon01)'
check_cmd "panne M21-E42 close (lab/bin/break 21 42 --annuler après réparation)" _m21x_aucune_panne_active E42

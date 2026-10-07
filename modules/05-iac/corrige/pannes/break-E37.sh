# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M05-E37 « Panne : le backend d'état est inaccessible »
#
# Depuis adm01, OpenTofu n'atteint plus (ou plus complètement) le backend S3 de s3-01. Variantes :
#   1. adm01 : /etc/hosts reçoit « 10.10.20.41 s3-01.par1.medisphere.internal s3-01 » (reste d'une
#      « migration » : 10.10.20.41 était sem01, détruite en M04) — dig répond juste, getent faux ;
#   2. s3-01 : le certificat servi sur 8333 est remplacé par un certificat auto-signé (même nom,
#      même SAN) : « x509: certificate signed by unknown authority » ;
#   3. gw01 : règle nftables en tête de la chaîne forward qui jette MGMT → s3-01:8333 (depuis
#      runner01, même VLAN, rien ne change : la CI fonctionne, adm01 non) ;
#   4. s3-01 : l'identité S3 tofu-etat perd ses droits Write (fichier d'identités de la passerelle,
#      service redémarré) : lectures et « state list » fonctionnent, la prise de verrou échoue
#      (AccessDenied).
# Les variantes 2 et 4 ne s'appliquent que si la passerelle est lancée avec -s3.cert.file /
# -s3.config (sinon une autre variante est essayée). Sauvegardes : /var/lib/workbook/M05-E37.*
# sur adm01 et s3-01, règle repérée par son commentaire sur gw01. L'annulation ne restaure que ce
# qui est encore dans l'état posé par la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E37_FQDN=s3-01.par1.medisphere.internal
_E37_COMM="temp LM 0412 : isolement s3-01 pendant tests de charge"

# _e37_curl — code de sortie de curl vers la passerelle S3 (TLS vérifié par le magasin système).
_e37_curl() {
  local rc=0
  curl -s -o /dev/null --max-time 10 "https://$_E37_FQDN:8333/" || rc=$?
  printf '%s\n' "$rc"
}

# Script distant commun (s3-01) : attendre que la passerelle réécoute après un redémarrage.
read -r -d '' _E37_ATTENDRE <<'SH' || true
attendre_8333() {
  local i
  for i in $(seq 1 60); do
    ss -Hltn 'sport = :8333' 2>/dev/null | grep -q . && return 0
    sleep 2
  done
  return 1
}
SH

_e37_s3() {
  { printf '%s\n' "$_E37_ATTENDRE"; cat; } | m05_wb_exec s3-01 "$@"
}

_m05E37_une() {
  local n="$1" rc=0 sonde
  case "$n" in
    1)
      m05_wb_exec adm01 FQDN="$_E37_FQDN" >/dev/null <<'EOF' || rc=$?
grep -Eq "[[:space:]]$FQDN([[:space:]]|$)" /etc/hosts && exit 10
sauver /etc/hosts
printf '%s\n' "10.10.20.41  $FQDN s3-01   # migration stockage S3 (InfoGér, ne pas retirer)" >> /etc/hosts
noter_injecte /etc/hosts
journal "/etc/hosts : $FQDN -> 10.10.20.41"
EOF
      ((rc == 0)) || return "$rc"
      [[ "$(getent hosts "$_E37_FQDN" | awk '{ print $1; exit }')" == 10.10.20.41 ]] || { annuler_E37; return 10; }
      ;;
    2)
      _e37_s3 FQDN="$_E37_FQDN" >/dev/null <<'EOF' || rc=$?
cert="$(option_weed s3.cert.file)"; cle="$(option_weed s3.key.file)"
[ -n "$cert" ] && [ -f "$cert" ] && [ -n "$cle" ] && [ -f "$cle" ] || exit 10
u="$(unite_8333)"; [ -n "$u" ] || exit 10
t="$(mktemp -d)"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
  -subj "/CN=$FQDN" -addext "subjectAltName=DNS:$FQDN,IP:10.10.20.14" \
  -keyout "$t/cle.pem" -out "$t/cert.pem" >/dev/null 2>&1 || { rm -rf "$t"; exit 1; }
sauver "$cert"; sauver "$cle"
cat "$t/cert.pem" > "$cert"; cat "$t/cle.pem" > "$cle"
rm -rf "$t"
noter_injecte "$cert"; noter_injecte "$cle"
printf '%s\n' "$u" > "$WB_DIR/$WB_EX.unite"
systemctl restart "$u" || exit 1
attendre_8333 || exit 1
journal "$cert et $cle remplacés par un certificat auto-signé, $u redémarré"
EOF
      ((rc == 0)) || { annuler_E37; return "$rc"; }
      [[ "$(_e37_curl)" == 60 ]] || { annuler_E37; return 10; }
      ;;
    3)
      m05_nft_poser E37 filter forward \
        "ip saddr 10.10.10.0/24 ip daddr $_M05_IP_S3 tcp dport 8333 counter drop" "$_E37_COMM" || return 1
      [[ "$(_e37_curl)" == 28 ]] || { annuler_E37; return 10; }
      ;;
    4)
      _e37_s3 >/dev/null <<'EOF' || rc=$?
conf="$(option_weed s3.config)"; [ -n "$conf" ] || conf="$(option_weed config)"
[ -n "$conf" ] && [ -f "$conf" ] || exit 10
u="$(unite_8333)"; [ -n "$u" ] || exit 10
t="$(mktemp)"
python3 - "$conf" "$t" <<'PY' || { rm -f "$t"; exit 10; }
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    conf = json.load(f)
change = False
for ident in conf.get("identities", []):
    if ident.get("name") != "tofu-etat":
        continue
    avant = list(ident.get("actions", []))
    ident["actions"] = [a for a in avant if a.split(":", 1)[0] not in ("Write", "Admin")]
    change = change or ident["actions"] != avant
if not change:
    sys.exit(1)
with open(dst, "w", encoding="utf-8") as f:
    json.dump(conf, f, indent=2)
    f.write("\n")
PY
sauver "$conf"
cat "$t" > "$conf"; rm -f "$t"
noter_injecte "$conf"
printf '%s\n' "$u" > "$WB_DIR/$WB_EX.unite"
systemctl restart "$u" || exit 1
attendre_8333 || exit 1
journal "$conf : droits Write retirés à l'identité tofu-etat, $u redémarré"
EOF
      ((rc == 0)) || { annuler_E37; return "$rc"; }
      sonde="$(m05_etat E37)/sonde"
      printf 'sonde M05-E37\n' >"$sonde"
      if m05_aws s3api put-object --bucket "$_M05_BUCKET" --key "_sondes/M05-E37" --body "$sonde" >/dev/null 2>&1; then
        m05_aws s3api delete-object --bucket "$_M05_BUCKET" --key "_sondes/M05-E37" >/dev/null 2>&1 || true
        annuler_E37
        return 10
      fi
      ;;
  esac
}

panne_E37_v1() { m05_prerequis socle && m05_essayer E37 4 1; }
panne_E37_v2() { m05_prerequis socle && m05_essayer E37 4 2; }
panne_E37_v3() { m05_prerequis socle && m05_essayer E37 4 3; }
panne_E37_v4() { m05_prerequis socle && m05_essayer E37 4 4; }

verifier_E37() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) [[ "$(getent hosts "$_E37_FQDN" | awk '{ print $1; exit }')" == 10.10.20.41 ]] ;;
    2) [[ "$(_e37_curl)" == 60 ]] ;;
    3) m05_nft_present "$_E37_COMM" ;;
    4) ! m05_tofu "$_M05_SOCLE" plan -lock-timeout=5s -refresh=false -no-color >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_E37() {
  m05_wb_exec adm01 >/dev/null <<'EOF' || wb_avert "adm01 : /etc/hosts à vérifier"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
journal "annulation : /etc/hosts rétabli (sauf réparation)"
EOF
  _e37_s3 >/dev/null <<'EOF' || wb_avert "s3-01 : certificat ou identités à vérifier (copies dans /var/lib/workbook/)"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
reste="$(wc -l < "$WB_DIR/$WB_EX.manifeste")"
restaurer_fichiers
u="$(cat "$WB_DIR/$WB_EX.unite" 2>/dev/null)"
rm -f "$WB_DIR/$WB_EX.unite"
if [ "$reste" -gt 0 ] && [ -n "$u" ]; then
  systemctl restart "$u" && attendre_8333
  journal "annulation : fichiers de la passerelle S3 rétablis, $u redémarré"
fi
EOF
  m05_nft_retirer E37 || true
  rm -f -- "$(m05_etat E37)/sonde" "$(m05_etat E37)/variante"
}

resume_E37() {
  echo "Depuis adm01, OpenTofu n'arrive plus à travailler avec l'état stocké sur s3-01 (init, plan ou verrou en échec)."
}

symptome_E37() {
  wb_symptome "Ticket INC-3243 — De : Nadia Roussel" \
    "Alerte remontée par Julien : depuis adm01, « tofu plan » dans ~/src/infra/socle échoue avant" \
    "même de comparer quoi que ce soit, sur une erreur liée au backend d'état (s3-01). Il n'a pas" \
    "réussi à savoir si c'est le stockage, le réseau ou OpenTofu, et il n'est pas sûr non plus que" \
    "le pipeline de plateforme/infra soit touché." \
    "Rétablis l'accès à l'état, explique-moi la cause et la première commande qui l'aurait révélée." \
    "Interdit : -lock=false, contourner TLS, ou mettre une IP en dur à la place du nom." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 05 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E37 4 "$@"; }
fi

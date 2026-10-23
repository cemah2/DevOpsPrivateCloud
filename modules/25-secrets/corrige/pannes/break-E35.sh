# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E35.sh — M25-E35 « Panne : le coffre est scellé après un redémarrage »
#
# Après la « maintenance de la nuit », un des trois nœuds de la grappe garde une erreur de
# configuration. Toujours UN nœud EN ATTENTE tiré au hasard (jamais l'actif, jamais kms01), aucune
# donnée touchée (ni /var/lib/openbao, ni Raft, ni le seal). Variantes :
#   1. openbao.hcl : « address » de l'écouteur passée de 0.0.0.0:8200 à 127.0.0.1:8200, puis
#      redémarrage du service : le nœud est descellé et en attente, mais plus personne ne le joint
#      par le réseau (Raft passe par cluster_address:8201, inchangé : la grappe le croit sain) ;
#   2. surcharge systemd override.conf (celle que crée « systemctl edit ») avec LimitNOFILE=64, puis
#      daemon-reload et redémarrage. Elle est lue APRÈS medisphere.conf (ordre alphabétique des
#      surcharges) et l'emporte sur son LimitNOFILE=65536 : le service tombe sous charge, ou ne
#      démarre plus ;
#   3. certificat et clé du nœud remplacés par ceux d'un AUTRE nœud du coffre (valides, même racine,
#      mais émis pour vault0Y et le nom du service), puis SIGHUP : le nœud se présente sous un autre
#      nom ; tout client qui le joint par SON nom (supervision, keepalived local) le refuse.
#
# Sauvegardes : sur le nœud, /var/lib/workbook/M25-E35.* (sauver() de pannes-lib) ; sur adm01,
# ~/.local/state/workbook/M25-E35/noeud (nœud touché). La clé privée copiée en variante 3 transite
# par la mémoire d'adm01 et l'entrée de ssh, jamais par un argument ni par un fichier d'adm01.
# Annulation (idempotente) : fichiers sauvegardés remis (sauf un certificat déjà réémis pour le bon
# nom par l'apprenant, qui est gardé), daemon-reload, redémarrage ou rechargement du seul nœud
# touché s'il le faut, puis attente d'une grappe saine (2 min au plus).
# Pas de jeton OpenBao nécessaire : la panne ne touche ni la configuration logique ni les données.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun.sh"

_E35_HCL=/etc/openbao/openbao.hcl
_E35_SURCHARGE=/etc/systemd/system/openbao.service.d/override.conf
_E35_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt

# _e35_pret — grappe saine ; choisit le nœud en attente et le note (une seule fois par panne).
_e35_pret() {
  local n
  m25_grappe_saine || { wb_avert "grappe pas saine (un actif, deux en attente, kms01 descellé) : rien n'est cassé"; return 1; }
  n="$(m25_en_attente_au_hasard)" || { wb_avert "aucun nœud en attente : rien n'est cassé"; return 1; }
  [[ "$n" != "$_M25_KMS" ]] || return 1
  m25_ecrire E35 noeud "$n"
  printf '%s\n' "$n"
}

# _e35_noeud — nœud touché (vide si inconnu).
_e35_noeud() { m25_lire E35 noeud; }

# _e35_local_sante HÔTE — code de sys/health vu DEPUIS le nœud, par la boucle locale et sous son nom
#   (comme le script chk_openbao_actif de keepalived) ; 000 si rien.
_e35_local_sante() {
  m25_exec "$1" NOM="$1.$_M25_DOMAINE" PORT="$_M25_PORT" RACINE="$_E35_RACINE" 2>/dev/null <<'EOF' || true
curl -s -o /dev/null -w '%{http_code}' --max-time 5 --cacert "$RACINE" \
  --resolve "$NOM:$PORT:127.0.0.1" "https://$NOM:$PORT/v1/sys/health" || true
EOF
}
_e35_local_en_service() { local c; c="$(_e35_local_sante "$1")"; [[ "$c" == 200 || "$c" == 429 ]]; }

panne_E35_v1() {
  local n
  n="$(_e35_pret)" || return 1
  m25_exec "$n" HCL="$_E35_HCL" >/dev/null <<'EOF' || return 1
motif='^[[:space:]]*address[[:space:]]*=[[:space:]]*"0\.0\.0\.0:[0-9]+"'
[ "$(grep -Ec "$motif" "$HCL")" = 1 ] || { echo "écouteur inattendu dans $HCL" >&2; exit 1; }
sauver "$HCL"
sed -i -E 's/^([[:space:]]*address[[:space:]]*=[[:space:]]*")0\.0\.0\.0:/\1127.0.0.1:/' "$HCL"
journal "écouteur API de openbao.hcl limité à 127.0.0.1"
EOF
  m25_journal E35 "$n : address de l'écouteur = 127.0.0.1:$_M25_PORT"
  m25_redemarrer_noeud "$n"
}

panne_E35_v2() {
  local n
  n="$(_e35_pret)" || return 1
  m25_exec "$n" F="$_E35_SURCHARGE" >/dev/null <<'EOF' || return 1
[ ! -e "$F" ] || { echo "$F existe déjà : état inattendu" >&2; exit 1; }
sauver "$F"
cat >"$F" <<'CONF'
# Essai de charge (maintenance de nuit) — à retirer après l'essai
[Service]
LimitNOFILE=64
CONF
chmod 0644 "$F"
systemctl daemon-reload
journal "surcharge $F posée (LimitNOFILE=64)"
EOF
  m25_journal E35 "$n : $_E35_SURCHARGE, LimitNOFILE=64"
  m25_redemarrer_noeud "$n"
}

panne_E35_v3() {
  local n src paquet
  n="$(_e35_pret)" || return 1
  # Source : un autre nœud du coffre (lecture seule), tiré au hasard.
  src="$(printf '%s\n' "${_M25_NOEUDS[@]}" | grep -vx "$n" | shuf -n 1)"
  [[ -n "$src" ]] || return 1
  paquet="$(m25_ssh "$src" 'openssl x509 -in /etc/openbao/tls/cert.pem -noout -checkend 7200 >/dev/null && tar -C /etc/openbao/tls -cf - cert.pem key.pem | base64 -w0')" \
    || { wb_avert "certificat de $src illisible ou trop proche de l'échéance : rien n'est cassé"; return 1; }
  [[ -n "$paquet" ]] || return 1
  m25_exec "$n" NOM="$n.$_M25_DOMAINE" PAQUET="$paquet" >/dev/null <<'EOF' || return 1
cert=/etc/openbao/tls/cert.pem
cle=/etc/openbao/tls/key.pem
# Le certificat apporté ne doit PAS couvrir ce nœud (sinon la panne n'en est pas une).
printf '%s' "$PAQUET" | base64 -d | tar -xOf - cert.pem | openssl x509 -noout -checkhost "$NOM" 2>/dev/null \
  | grep -q 'does NOT match' || { echo "certificat apporté inattendu" >&2; exit 1; }
sauver "$cert"
sauver "$cle"
# Réécriture en place : propriétaire, groupe et droits des fichiers d'origine conservés.
printf '%s' "$PAQUET" | base64 -d | tar -xOf - cert.pem >"$cert"
printf '%s' "$PAQUET" | base64 -d | tar -xOf - key.pem >"$cle"
systemctl reload openbao
journal "certificat et clé d'un autre nœud posés, openbao rechargé (SIGHUP)"
EOF
  paquet=""
  m25_journal E35 "$n : certificat et clé de $src posés, SIGHUP"
}

# _e35_v2_effectif HÔTE — la limite de 64 descripteurs s'applique au processus, ou le service ne tourne pas.
_e35_v2_effectif() {
  m25_exec "$1" >/dev/null 2>&1 <<'EOF'
[ "$(systemctl show -p LimitNOFILE --value openbao)" = 64 ] || exit 1
pid="$(systemctl show -p MainPID --value openbao)"
if [ -z "$pid" ] || [ "$pid" = 0 ] || ! systemctl is-active --quiet openbao; then exit 0; fi
awk '/^Max open files/ { exit !($4 == 64) }' "/proc/$pid/limits"
EOF
}

# _e35_v3_refuse HÔTE — le certificat présenté par le nœud ne couvre pas son nom.
_e35_v3_refuse() {
  local nom="$1.$_M25_DOMAINE"
  openssl s_client -connect "$nom:$_M25_PORT" -servername "$nom" </dev/null 2>/dev/null \
    | openssl x509 -noout -checkhost "$nom" 2>/dev/null | grep -q 'does NOT match'
}

verifier_E35() {
  local n
  n="$(_e35_noeud)"
  [[ -n "$n" ]] || return 1
  case "$WB_VAR" in
    1) # Processus revenu, descellé, en attente vu de la boucle locale ; injoignable de l'extérieur.
       m25_attendre 90 _e35_local_en_service "$n" || return 1
       m25_hors_service "$n" ;;
    2) m25_attendre 90 _e35_v2_effectif "$n" ;;
    3) m25_attendre 30 _e35_v3_refuse "$n" || return 1
       m25_hors_service "$n" ;;
    *) return 1 ;;
  esac
}

annuler_E35() {
  local n sortie
  local -a cibles=()
  n="$(_e35_noeud)"
  if [[ -n "$n" ]]; then cibles=("$n"); else cibles=("${_M25_NOEUDS[@]}"); fi
  for n in "${cibles[@]}"; do
    [[ "$n" != "$_M25_KMS" ]] || continue
    sortie="$(m25_exec "$n" NOM="$n.$_M25_DOMAINE" 2>/dev/null <<'EOF'
m="$WB_DIR/$WB_EX.manifeste"
[ -f "$m" ] || { echo rien; exit 0; }
cert=/etc/openbao/tls/cert.pem
cle=/etc/openbao/tls/key.pem
action=""
# Certificat : déjà réémis pour le bon nom (réparation de l'apprenant) → on garde le neuf.
if grep -qF "$(printf '%s\t' "$cert")" "$m"; then
  if openssl x509 -in "$cert" -noout -checkhost "$NOM" 2>/dev/null | grep -q ' does match'; then
    for f in "$cert" "$cle"; do
      o="$(awk -F '\t' -v f="$f" '$1 == f { print $2 }' "$m")"
      if [ -n "$o" ] && [ "$o" != ABSENT ]; then rm -f "$o"; fi
    done
    grep -vF -e "$(printf '%s\t' "$cert")" -e "$(printf '%s\t' "$cle")" "$m" >"$m.tmp" || true
    mv "$m.tmp" "$m"
  else
    action=recharger
  fi
fi
# Configuration et surcharge : un écart avec la sauvegarde impose un redémarrage.
while IFS="$(printf '\t')" read -r src dst; do
  case "$src" in "$cert" | "$cle") continue ;; esac
  if [ "$dst" = ABSENT ]; then
    if [ -e "$src" ]; then action=redemarrer; fi
  elif ! cmp -s "$src" "$dst"; then
    action=redemarrer
  fi
done <"$m"
restaurer_fichiers
systemctl daemon-reload
# Réparé sur disque mais pas redémarré : la limite fautive vit encore dans le processus.
pid="$(systemctl show -p MainPID --value openbao)"
if [ -n "$pid" ] && [ "$pid" != 0 ] && awk '/^Max open files/ { exit !($4 == 64) }' "/proc/$pid/limits" 2>/dev/null; then
  action=redemarrer
fi
if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then echo certificat-expire; fi
case "$action" in
  redemarrer)
    systemctl reset-failed openbao 2>/dev/null || true
    systemctl restart openbao 2>/dev/null || true
    journal "annulation : fichiers remis, openbao redémarré" ;;
  recharger)
    if systemctl is-active --quiet openbao; then systemctl reload openbao 2>/dev/null || true; fi
    journal "annulation : certificat d'origine remis, openbao rechargé" ;;
  *) journal "annulation : rien à remettre en service" ;;
esac
echo "${action:-rien}"
EOF
)" || { wb_avert "$n injoignable : sauvegardes M25-E35 non vérifiées (relance --annuler)"; continue; }
    if [[ "$sortie" == *certificat-expire* ]]; then
      wb_avert "$n : le certificat d'origine a expiré pendant la panne ; réémets-le :"
      wb_avert "  uv run ansible-playbook playbooks/coffre.yml --limit $n   (rôle certificats_acme)"
    fi
    m25_relancer_si_besoin "$n"
  done
  if ! m25_attendre 120 m25_grappe_saine; then
    wb_avert "grappe pas encore saine après 2 min : relis sys/health des trois nœuds (RB-251)"
  fi
  m25_journal E35 "annulation"
  m25_oublier E35 noeud
}

# _e35_visible — le nœud touché ne répond plus normalement par son nom (vu d'adm01).
_e35_visible() { local n; n="$(_e35_noeud)"; [[ -n "$n" ]] && m25_hors_service "$n"; }

symptome_E35() {
  if _e35_visible; then
    wb_symptome "INC-5235 — De : Nadia Roussel — le coffre répond mal depuis la maintenance" \
      "Cette nuit, Lucas a fait la maintenance des nœuds du coffre (mises à jour, un redémarrage par" \
      "nœud, « deux ou trois réglages »). Depuis, OpenBaoScelle a sonné pour un des nœuds, et mon" \
      "contrôle du matin (sys/health de vault01, vault02, vault03 et de openbao.par1.medisphere.internal:8200)" \
      "rate une requête sur trois. Le coffre est-il scellé ? Lucas redémarre le nœud actif cet" \
      "après-midi (noyau) : est-ce que tout va tomber ? Il est en congé demain." \
      "Temps cible : 40 min. Contrôle : lab/bin/check 25 35"
  else
    wb_symptome "INC-5235 — De : Nadia Roussel — le coffre répond mal depuis la maintenance" \
      "Cette nuit, Lucas a fait la maintenance des nœuds du coffre (mises à jour, un redémarrage par" \
      "nœud, « deux ou trois réglages »). Mon contrôle du matin (sys/health des trois nœuds et de" \
      "openbao.par1.medisphere.internal:8200) est vert à cette heure-ci, mais Lucas m'écrit avoir laissé" \
      "« un réglage d'essai de charge » sur un des nœuds, sans savoir lequel. Il redémarre le nœud" \
      "actif cet après-midi (noyau) : est-ce que tout va tomber ? Il est en congé demain." \
      "Temps cible : 40 min. Contrôle : lab/bin/check 25 35"
  fi
}

resume_E35() {
  if _e35_visible; then
    echo "un nœud du coffre ne répond plus par son nom depuis la maintenance (alerte OpenBaoScelle)"
  else
    echo "un réglage d'essai laissé sur un nœud du coffre pendant la maintenance, nœud inconnu"
  fi
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E35 3 "$@"; }
fi

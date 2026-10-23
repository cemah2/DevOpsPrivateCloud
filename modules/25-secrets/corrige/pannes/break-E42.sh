# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E42.sh — M25-E42 « Panne : l'auto-descellement échoue »
#
# Un nœud EN ATTENTE (jamais l'actif, jamais kms01) est redémarré après qu'un maillon de son seal
# transit a été cassé. Variantes :
#   1. jeton du seal remplacé dans /etc/openbao/kms.env du nœud par un jeton inconnu de kms01 (révoqué) :
#      « Error configuring seal "transit" … 403 permission denied », le processus s'arrête, systemd
#      abandonne (start-limit-hit) ;
#   2. [kms01] politique kms-autodescellement sans transit/decrypt : le seal se configure (chiffrement
#      d'essai), le DÉCHIFFREMENT de la clé racine est refusé ; processus vivant, scellé, réessaie / 5 s ;
#   3. [kms01] clé autodescellement-par1 tournée puis min_decryption_version relevée à la nouvelle
#      version : la clé racine (chiffrée par une version plus ancienne) n'est plus déchiffrable
#      (« disallowed by policy (too old) ») ; processus vivant, scellé ;
#   4. sortie du nœud vers kms01:8200 rejetée par une table nftables locale (« durcissement des sorties »
#      de Lucas) : « connection refused » au démarrage, le processus s'arrête, start-limit-hit.
# Les variantes 2 et 3 exigent BAO_KMS_TOKEN (jeton d'administration de kms01, M25-E28) ; sans lui,
# une variante 1 ou 4 est tirée. Elles créent d'abord sur kms01 un jeton d'ANNULATION orphelin (72 h,
# politique « wb-pannes » limitée à ce que l'annulation rétablit), rangé en 600 dans l'état local.
#
# Ne touche jamais : l'état scellé de kms01, les parts, les clés de récupération, /var/lib/openbao.
# La rotation de la clé de transit (variante 3) n'est pas défaite (une version de plus, sans effet une
# fois le minimum rétabli) : elle est consignée dans le journal de la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun.sh"

_E42_CLE=autodescellement-par1
_E42_POL=kms-autodescellement
_E42_POL_ANNUL=wb-pannes
_E42_KMS_IP="${WB_M25_KMS_IP:-10.10.20.24}"

_e42_pret() {
  local n
  m25_grappe_saine || { wb_avert "grappe pas saine (un actif, deux en attente, kms01 descellé) : rien n'est cassé"; return 1; }
  n="$(m25_lire E42 noeud)"
  if [[ -z "$n" ]]; then
    n="$(m25_en_attente_au_hasard)" || { wb_avert "aucun nœud en attente"; return 1; }
    m25_ecrire E42 noeud "$n"
  fi
  m25_ssh "$n" 'test -s /etc/openbao/kms.env && systemctl is-active --quiet openbao' >/dev/null 2>&1 \
    || { wb_avert "$n : kms.env absent ou openbao inactif (M25-E25 fait ?)"; return 1; }
}

# _e42_jeton_annulation — crée (une fois) sur kms01 la politique et le jeton d'annulation.
_e42_jeton_annulation() {
  local d f
  d="$(m25_etat E42)"
  f="$d/jeton-annulation"
  [[ -s "$f" ]] && return 0
  printf '%s\n' \
    '# wb-pannes — jeton d annulation d une panne du workbook (M25-E42). À supprimer si elle traîne.' \
    "path \"sys/policies/acl/$_E42_POL\" {" '  capabilities = ["read", "update"]' '}' \
    "path \"transit/keys/$_E42_CLE\" {" '  capabilities = ["read"]' '}' \
    "path \"transit/keys/$_E42_CLE/config\" {" '  capabilities = ["update"]' '}' \
    "path \"sys/policies/acl/$_E42_POL_ANNUL\" {" '  capabilities = ["delete"]' '}' \
    | jq -Rs '{policy: .}' | m25_kms_api PUT "sys/policies/acl/$_E42_POL_ANNUL" - >/dev/null || return 1
  (umask 077 && jq -nc --arg p "$_E42_POL_ANNUL" '{policies: [$p], ttl: "72h", display_name: "wb-pannes-m25", no_parent: true}' \
    | m25_kms_api POST auth/token/create-orphan - | jq -r '.auth.client_token // empty' >"$f") || return 1
  [[ -s "$f" ]]
}

# _e42_redemarrer — redémarre le nœud choisi (en attente) et note l'heure.
_e42_redemarrer() {
  local n
  n="$(m25_lire E42 noeud)"
  m25_redemarrer_noeud "$n" || return 1
  m25_journal E42 "$n redémarré"
}

panne_E42_v1() {
  local n
  _e42_pret || return 1
  n="$(m25_lire E42 noeud)"
  m25_exec "$n" >/dev/null <<'EOF' || return 1
f=/etc/openbao/kms.env
sauver "$f"
faux="s.$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
tmp="$(mktemp /etc/openbao/.kms.env.XXXXXX)"
sed "s/^BAO_TOKEN=.*/BAO_TOKEN=$faux/" "$f" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$f"
journal "kms.env : jeton du seal remplacé par un jeton inconnu de kms01"
EOF
  _e42_redemarrer
}

panne_E42_v2() {
  local p
  _e42_pret || return 1
  m25_kms_disponible || { wb_avert "BAO_KMS_TOKEN absent ou refusé par kms01 : variante 2 impossible"; return 1; }
  p="$(m25_kms_api GET "sys/policies/acl/$_E42_POL" | jq -r '.data.policy // empty')"
  grep -qF "transit/decrypt/$_E42_CLE" <<<"$p" || { wb_avert "politique $_E42_POL de kms01 inattendue"; return 1; }
  _e42_jeton_annulation || { wb_avert "jeton d'annulation impossible à créer sur kms01"; return 1; }
  m25_ecrire_si_absent E42 politique-kms.hcl "$p"
  # Retire le bloc decrypt (de sa ligne « path » jusqu'à l'accolade fermante, sur une ou plusieurs lignes).
  awk -v c="transit/decrypt/$_E42_CLE" 'index($0, c) {dedans = 1} dedans {if (index($0, "}")) dedans = 0; next} {print}' <<<"$p" \
    | sed '1i # Revue des droits (SEC-2642) : le coffre ne fait que chiffrer, « decrypt » retiré.' \
    | jq -Rs '{policy: .}' | m25_kms_api PUT "sys/policies/acl/$_E42_POL" - >/dev/null || return 1
  m25_journal E42 "kms01 : politique $_E42_POL sans decrypt"
  _e42_redemarrer
}

panne_E42_v3() {
  local k dern
  _e42_pret || return 1
  m25_kms_disponible || { wb_avert "BAO_KMS_TOKEN absent ou refusé par kms01 : variante 3 impossible"; return 1; }
  k="$(m25_kms_api GET "transit/keys/$_E42_CLE")" || { wb_avert "clé $_E42_CLE illisible sur kms01"; return 1; }
  _e42_jeton_annulation || { wb_avert "jeton d'annulation impossible à créer sur kms01"; return 1; }
  m25_ecrire_si_absent E42 min-dechiffrement "$(jq -r '.data.min_decryption_version' <<<"$k")"
  m25_kms_api POST "transit/keys/$_E42_CLE/rotate" >/dev/null || return 1
  dern="$(m25_kms_api GET "transit/keys/$_E42_CLE" | jq -r '.data.latest_version')"
  jq -nc --argjson v "$dern" '{min_decryption_version: $v}' \
    | m25_kms_api POST "transit/keys/$_E42_CLE/config" - >/dev/null || return 1
  m25_journal E42 "kms01 : clé $_E42_CLE tournée (version $dern), min_decryption_version = $dern (rotation NON défaite)"
  _e42_redemarrer
}

panne_E42_v4() {
  local n
  _e42_pret || return 1
  n="$(m25_lire E42 noeud)"
  m25_exec "$n" IP_KMS="$_E42_KMS_IP" >/dev/null <<'EOF' || return 1
command -v nft >/dev/null || exit 1
nft add table inet durcissement_sortie
nft 'add chain inet durcissement_sortie sortie { type filter hook output priority filter - 10 ; policy accept ; }'
nft add rule inet durcissement_sortie sortie ip daddr "$IP_KMS" tcp dport 8200 counter reject with tcp reset \
  comment '"SEC-2642 sorties du coffre limitées (Lucas)"'
journal "table nftables inet durcissement_sortie : sortie vers $IP_KMS:8200 rejetée"
EOF
  _e42_redemarrer
}

verifier_E42() {
  local n
  n="$(m25_lire E42 noeud)"
  [[ -n "$n" ]] || return 1
  [[ "$(m25_kms_code)" == 200 ]] || return 1
  # Le nœud doit rester hors service (arrêté ou scellé) : 25 s après le redémarrage, puis contrôle.
  sleep 25
  m25_hors_service "$n" || return 1
  sleep 10
  m25_hors_service "$n"
}

annuler_E42() {
  local n f m
  n="$(m25_lire E42 noeud)"
  f="$(m25_etat E42)/jeton-annulation"
  # 1. kms01 (variantes 2 et 3) : avec le jeton d'annulation, sinon BAO_KMS_TOKEN.
  if m25_existe E42 politique-kms.hcl; then
    if [[ -s "$f" ]]; then
      m25_lire E42 politique-kms.hcl | jq -Rs '{policy: .}' | m25_kms_api_jeton "$f" PUT "sys/policies/acl/$_E42_POL" - >/dev/null \
        || wb_avert "politique $_E42_POL de kms01 non restaurée (jeton d'annulation expiré ?)"
    else
      m25_lire E42 politique-kms.hcl | jq -Rs '{policy: .}' | m25_kms_api PUT "sys/policies/acl/$_E42_POL" - >/dev/null \
        || wb_avert "politique $_E42_POL de kms01 non restaurée : remets-la depuis kms01/kms-autodescellement.hcl"
    fi
  fi
  m="$(m25_lire E42 min-dechiffrement)"
  if [[ -n "$m" ]]; then
    if [[ -s "$f" ]]; then
      jq -nc --argjson v "$m" '{min_decryption_version: $v}' | m25_kms_api_jeton "$f" POST "transit/keys/$_E42_CLE/config" - >/dev/null \
        || wb_avert "min_decryption_version de $_E42_CLE non restaurée (valeur d'origine : $m)"
    else
      jq -nc --argjson v "$m" '{min_decryption_version: $v}' | m25_kms_api POST "transit/keys/$_E42_CLE/config" - >/dev/null \
        || wb_avert "min_decryption_version de $_E42_CLE non restaurée (valeur d'origine : $m)"
    fi
  fi
  if [[ -s "$f" ]]; then
    m25_kms_api_jeton "$f" DELETE "sys/policies/acl/$_E42_POL_ANNUL" >/dev/null || true
    m25_kms_api_jeton "$f" POST auth/token/revoke-self >/dev/null || true
    rm -f -- "$f"
  fi
  # 2. Le nœud : fichiers restaurés, table nftables retirée.
  if [[ -n "$n" ]]; then
    m25_exec "$n" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur le nœud"
restaurer_fichiers
nft delete table inet durcissement_sortie 2>/dev/null || true
journal "annulation : kms.env restauré, table durcissement_sortie retirée"
EOF
    m25_relancer_si_besoin "$n"
  fi
  m25_journal E42 "annulation ($n)"
  m25_oublier E42 noeud
  m25_oublier E42 politique-kms.hcl
  m25_oublier E42 min-dechiffrement
}

# e42_variantes — variantes possibles dans l'état du poste (sans BAO_KMS_TOKEN : 1 et 4 seulement).
#   Sert à break-E43.sh ; le tirage de main() suit la même règle.
e42_variantes() { if m25_kms_disponible; then echo "1 2 3 4"; else echo "1 4"; fi; }

symptome_E42() {
  local n
  n="$(m25_lire E42 noeud)"
  wb_symptome "INC-5242 — De : Nadia Roussel — $n ne revient pas après un redémarrage" \
    "$n a été redémarré (mise à jour du noyau) et ne sert plus : alerte OpenBaoScelle, tolérance aux" \
    "pannes d'autopilot à zéro. Les deux autres nœuds servent. kms01 a l'air de répondre." \
    "Ne redémarre aucun autre nœud ; ne touche pas à l'état de kms01." \
    "Temps cible : 45 min. Contrôle : lab/bin/check 25 42"
}

resume_E42() { echo "$(m25_lire E42 noeud) ne se descelle plus après un redémarrage (auto-descellement)"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() {
    local a forcee=0
    for a in "$@"; do [[ "$a" == --variante* ]] && forcee=1; done
    if ((forcee == 0)) && [[ " $* " != *" --annuler "* ]] && ! m25_kms_disponible; then
      # Tirage restreint aux variantes sans kms01 : on force 1 ou 4.
      wb_main 25 E42 4 --variante $(( (RANDOM % 2) ? 4 : 1 )) "$@"
      return
    fi
    wb_main 25 E42 4 "$@"
  }
fi

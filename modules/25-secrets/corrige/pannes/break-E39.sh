# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E39.sh — M25-E39 « Panne : la grappe n'a plus de leader »
#
# La grappe Raft vault01-03 perd son quorum (2 sur 3) après une « maintenance ». Variantes :
#   1. openbao ARRÊTÉ (systemctl stop, pas la VM) sur les deux nœuds en attente : le nœud actif reste
#      seul, perd la direction Raft et ne sert plus rien ;
#   2. port de grappe 8201 filtré sur deux nœuds tirés au hasard (table nftables dédiée « inet
#      maintenance », en entrée : dport 8201 ET sport 8201, donc ni connexion reçue ni réponse aux
#      connexions émises) : chaque nœud est isolé des deux autres, personne n'a de majorité ;
#   3. un nœud en attente arrêté ET le 8201 filtré sur l'autre nœud en attente : l'actif reste seul.
#      Redémarrer le nœud arrêté rend le service, mais pas la marge (le troisième reste isolé).
#
# Règles (PLAN §4.12, fiche du module : seule panne du module qui assume la perte de quorum) :
#   - jamais les données Raft (/var/lib/openbao), jamais remove-peer, jamais kms01, jamais les VMs ;
#   - perte de quorum seulement si la grappe est saine, kms01 descellé, un instantané horaire de moins
#     de 2 h existe (sinon on en déclenche un et on le vérifie), et si les nœuds qu'on arrête savent
#     se desceller seuls (essai de chiffrement avec LEUR jeton de seal sur kms01) ;
#   - le nœud ACTIF n'est jamais arrêté (seulement isolé en variante 2) ;
#   - état local : ~/.local/state/workbook/M25-E39/ (nœuds arrêtés, nœuds filtrés, journal).
# Annulation (idempotente) : table « inet maintenance » supprimée sur les trois nœuds, openbao relancé
# là où il ne sert pas, attente d'un actif et d'une grappe saine (2 min au plus).
# Pas de jeton OpenBao nécessaire : la panne ne touche ni la configuration ni les données du coffre.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun-b.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun-b.sh"

_E39_TABLE=maintenance
_E39_INSTANTANE_MAX=7200 # âge maximal (s) du dernier instantané horaire avant de couper le quorum

# _e39_age_instantane HÔTE — âge en secondes du dernier instantané envoyé par ce nœud (vide si aucun).
_e39_age_instantane() {
  m25b_exec "$1" 2>/dev/null <<'EOF' || true
f=/var/lib/openbao-instantane/dernier-succes
if [ -r "$f" ]; then t="$(cut -d' ' -f1 "$f")"; [ -n "$t" ] && echo $(( $(date +%s) - t )); fi
EOF
}

# _e39_instantane_recent — un des trois nœuds a envoyé un instantané il y a moins de 2 h.
_e39_instantane_recent() {
  local n a
  for n in "${_M25B_NOEUDS[@]}"; do
    a="$(_e39_age_instantane "$n")"
    [[ "$a" =~ ^[0-9]+$ ]] && ((a < _E39_INSTANTANE_MAX)) && return 0
  done
  return 1
}

# _e39_instantane_garanti — sinon, lance l'unité d'instantané sur l'actif et revérifie.
_e39_instantane_garanti() {
  local a
  _e39_instantane_recent && return 0
  a="$(m25b_actif)" || return 1
  wb_avert "aucun instantané de moins de 2 h : lancement de openbao-instantane sur $a"
  m25b_exec "$a" >/dev/null 2>&1 <<'EOF' || true
systemctl start openbao-instantane.service
EOF
  _e39_instantane_recent
}

# _e39_seal_autonome HÔTE — le jeton du seal du nœud (kms.env) chiffre encore avec la clé de kms01 :
#   le nœud redémarré se descellera seul. Le jeton est lu et utilisé SUR le nœud, jamais transmis.
_e39_seal_autonome() {
  m25b_exec "$1" ADRESSE="$_M25B_KMS_URL" >/dev/null 2>&1 <<'EOF'
jeton="$(sed -n 's/^BAO_TOKEN=//p' /etc/openbao/kms.env 2>/dev/null)"
[ -n "$jeton" ] || exit 1
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
  -K <(printf 'header = "X-Vault-Token: %s"\n' "$jeton") -H 'Content-Type: application/json' \
  --data '{"plaintext":"ZXNzYWkgZGUgZGVzY2VsbGVtZW50"}' \
  "$ADRESSE/v1/transit/encrypt/autodescellement-par1")"
[ "$code" = 200 ]
EOF
}

# _e39_pret — grappe saine, instantané récent, au plus une fois par injection.
_e39_pret() {
  m25b_grappe_saine || { wb_avert "grappe pas saine (un actif, deux en attente, kms01 descellé) : rien n'est cassé"; return 1; }
  _e39_instantane_garanti || { wb_avert "pas d'instantané vérifié de moins de 2 h (M25-E26) : rien n'est cassé"; return 1; }
}

# _e39_attente — les deux nœuds en attente, un par ligne (ordre aléatoire).
_e39_attente() {
  local n
  local -a l=()
  for n in "${_M25B_NOEUDS[@]}"; do [[ "$(m25b_code "$n")" == 429 ]] && l+=("$n"); done
  ((${#l[@]} == 2)) || return 1
  if ((RANDOM % 2)); then printf '%s\n%s\n' "${l[0]}" "${l[1]}"; else printf '%s\n%s\n' "${l[1]}" "${l[0]}"; fi
}

# _e39_arreter HÔTE — arrête openbao sur un nœud (jamais l'actif, jamais kms01).
_e39_arreter() {
  local h="$1" l
  [[ "$h" != "$_M25B_KMS" && "$(m25b_code "$h")" == 429 ]] || { wb_avert "$h n'est pas en attente : pas d'arrêt"; return 1; }
  _e39_seal_autonome "$h" || { wb_avert "$h : son jeton de seal ne chiffre plus sur kms01 (il ne redémarrerait pas seul, voir M25-E42) : rien n'est cassé"; return 1; }
  l="$(m25b_lire E39 arretes)"
  m25b_ecrire E39 arretes "$(printf '%s\n%s\n' "$l" "$h" | grep -v '^$' | sort -u)"
  m25b_exec "$h" >/dev/null <<'EOF'
systemctl stop openbao
journal "openbao arrêté (maintenance)"
EOF
  m25b_journal E39 "openbao arrêté sur $h"
}

# _e39_filtrer HÔTE — isole le nœud sur le port de grappe (table nftables dédiée, rien d'autre touché).
_e39_filtrer() {
  local h="$1" l
  l="$(m25b_lire E39 filtres)"
  m25b_ecrire E39 filtres "$(printf '%s\n%s\n' "$l" "$h" | grep -v '^$' | sort -u)"
  m25b_exec "$h" TABLE="$_E39_TABLE" >/dev/null <<'EOF'
nft list table inet "$TABLE" >/dev/null 2>&1 && nft delete table inet "$TABLE"
nft -f - <<NFT
table inet $TABLE {
	chain entree {
		type filter hook input priority -10; policy accept;
		tcp dport 8201 drop
		tcp sport 8201 drop
	}
}
NFT
journal "table inet $TABLE : port 8201 filtré"
EOF
  m25b_journal E39 "8201 filtré sur $h (table inet $_E39_TABLE)"
}

panne_E39_v1() {
  local -a a
  _e39_pret || return 1
  mapfile -t a < <(_e39_attente) || true
  ((${#a[@]} == 2)) || { wb_avert "il faut exactement deux nœuds en attente"; return 1; }
  # Les deux essais de seal AVANT le premier arrêt : on ne s'arrête pas à mi-chemin.
  if ! _e39_seal_autonome "${a[0]}" || ! _e39_seal_autonome "${a[1]}"; then
    wb_avert "un jeton de seal ne chiffre plus sur kms01 (voir M25-E42) : rien n'est cassé"
    return 1
  fi
  _e39_arreter "${a[0]}" || return 1
  sleep 5
  _e39_arreter "${a[1]}"
}

panne_E39_v2() {
  local -a n
  _e39_pret || return 1
  mapfile -t n < <(printf '%s\n' "${_M25B_NOEUDS[@]}" | shuf -n 2)
  ((${#n[@]} == 2)) || return 1
  _e39_filtrer "${n[0]}" || return 1
  _e39_filtrer "${n[1]}"
}

panne_E39_v3() {
  local -a a
  _e39_pret || return 1
  mapfile -t a < <(_e39_attente) || true
  ((${#a[@]} == 2)) || { wb_avert "il faut exactement deux nœuds en attente"; return 1; }
  _e39_seal_autonome "${a[0]}" || { wb_avert "${a[0]} : jeton de seal refusé par kms01 (voir M25-E42) : rien n'est cassé"; return 1; }
  _e39_filtrer "${a[1]}" || return 1
  sleep 5
  _e39_arreter "${a[0]}"
}

# _e39_aucun_actif — aucun nœud ne répond 200 (trois relevés de suite, à 3 s d'intervalle).
_e39_aucun_actif() {
  local i
  for i in 1 2 3; do
    m25b_actif >/dev/null && return 1
    ((i < 3)) && sleep 3
  done
  return 0
}

_e39_arrete() { ! m25b_exec "$1" >/dev/null 2>&1 <<<'systemctl is-active --quiet openbao'; }
_e39_filtre() { m25b_exec "$1" TABLE="$_E39_TABLE" >/dev/null 2>&1 <<<'nft list table inet "$TABLE" | grep -q "dport 8201 drop"'; }

verifier_E39() {
  local n
  # Le chef Raft isolé ne lâche la main qu'après son délai de bail : on attend jusqu'à 90 s.
  m25b_attendre 90 _e39_aucun_actif || return 1
  while IFS= read -r n; do [[ -z "$n" ]] || _e39_arrete "$n" || return 1; done < <(m25b_lire E39 arretes)
  while IFS= read -r n; do [[ -z "$n" ]] || _e39_filtre "$n" || return 1; done < <(m25b_lire E39 filtres)
  case "$WB_VAR" in
    1) [[ "$(m25b_lire E39 arretes | grep -c .)" == 2 ]] || return 1
       # Le survivant tourne toujours, descellé, en attente (429) : c'est le piège.
       for n in "${_M25B_NOEUDS[@]}"; do m25b_lire E39 arretes | grep -qx "$n" || [[ "$(m25b_code "$n")" == 429 ]] || return 1; done ;;
    2) [[ "$(m25b_lire E39 filtres | grep -c .)" == 2 ]] || return 1 ;;
    3) [[ "$(m25b_lire E39 arretes | grep -c .)" == 1 && "$(m25b_lire E39 filtres | grep -c .)" == 1 ]] || return 1 ;;
    *) return 1 ;;
  esac
}

annuler_E39() {
  local n
  # 1. Filtrage retiré partout (la table ne sert qu'à cette panne ; absente = rien à faire).
  for n in "${_M25B_NOEUDS[@]}"; do
    m25b_exec "$n" TABLE="$_E39_TABLE" >/dev/null 2>&1 <<'EOF' || wb_avert "$n injoignable : table inet maintenance non vérifiée"
if nft list table inet "$TABLE" >/dev/null 2>&1; then
  nft delete table inet "$TABLE" && journal "annulation : table inet $TABLE supprimée"
fi
EOF
  done
  # 2. openbao relancé là où il ne sert pas (arrêté, en échec) ; un nœud qui répond n'est pas touché.
  for n in "${_M25B_NOEUDS[@]}"; do m25b_relancer_si_besoin "$n"; done
  # 3. Un actif, deux en attente, kms01 descellé.
  if ! m25b_attendre 120 m25b_grappe_saine; then
    wb_avert "grappe pas encore saine après 2 min : relis sys/health des trois nœuds et RB-255 § 4"
    wb_avert "(un pair retiré à la main par remove-peer ne revient pas seul : il doit rejoindre la grappe)"
  fi
  m25b_journal E39 "annulation"
  m25b_oublier E39 arretes
  m25b_oublier E39 filtres
}

symptome_E39() {
  wb_symptome "INC-5239 — De : Nadia Roussel — Le coffre ne répond plus (alerte OpenBaoSansLeader)" \
    "06 h 52 : OpenBaoSansLeader a sonné, puis OpenBaoScelle sur un ou plusieurs nœuds." \
    "« bao status » par openbao.par1.medisphere.internal ne répond pas ; les pipelines tombent sur" \
    "« bao kv get » ; ESO marque ses ExternalSecret en erreur. Lucas a fait cette nuit la maintenance" \
    "des nœuds du coffre (mises à jour, « un essai de filtrage ») et il est en congé jusqu'à lundi." \
    "Rétablis le coffre sans rien perdre, et dis-moi ce qui s'est passé." \
    "Temps cible : 60 min. Contrôle : lab/bin/check 25 39"
}

resume_E39() { echo "plus aucun nœud actif dans la grappe OpenBao : la VIP ne répond plus, alerte OpenBaoSansLeader"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E39 3 "$@"; }
fi

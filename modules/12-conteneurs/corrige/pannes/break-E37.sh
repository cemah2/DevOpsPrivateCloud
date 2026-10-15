# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M12-E37 « Panne : l'application ne joint plus sa base »
#
# Pile de recette de ctr01, remise à sa version de référence avant l'injection. Variantes :
#   1. « isolement de la base » : le service db quitte le réseau « donnees » pour un nouveau réseau
#      « base » (internal: true) que l'API ne rejoint pas → le nom base-recette ne se résout plus
#      depuis l'API (internal: true est un leurre : il ne bloque que la sortie vers l'extérieur) ;
#   2. « débogage » : l'API est détachée à chaud du réseau recette_donnees (docker network
#      disconnect) ; compose.yaml est intact → PostgreSQL ET Valkey injoignables ;
#   3. « nettoyage » : l'alias réseau base-recette du service db est supprimé de compose.yaml
#      → l'URL de l'API (…@base-recette:5432) ne se résout plus, alors que « db » se résout ;
#   4. « durcissement de l'hôte » : une table nftables de la famille bridge jette (drop) le trafic
#      TCP 5432 vers le sous-réseau de recette_donnees → les connexions déjà ouvertes de la réserve
#      restent pendues, /pret ne répond plus (délai dépassé) ; la résolution DNS fonctionne.
# Annulation : table nftables supprimée (variante 4), puis pile de recette de référence.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_mE37_une() {
  case "$1" in
    1)
      m12_compose_remplacer '    networks:
      donnees:
        aliases:
          - base-recette' '    networks:
      base:
        aliases:
          - base-recette' || return $?
      m12_compose_remplacer '  donnees:
    internal: true' '  donnees:
    internal: true
  # Isolement de la base (Lucas, « ticket SEC ») : réseau interne dédié
  base:
    internal: true' || return $?
      m12_compose up -d --no-deps --no-build db || true
      ;;
    2)
      m12_exec "$_M12_CTR01" <<'EOF' || return $?
docker network disconnect recette_donnees recette-api-1 >/dev/null 2>&1 || exit 10
journal "recette-api-1 détaché de recette_donnees"
EOF
      ;;
    3)
      m12_compose_remplacer '    networks:
      donnees:
        aliases:
          - base-recette' '    networks:
      - donnees' || return $?
      m12_compose up -d --no-deps --no-build db || true
      ;;
    4)
      m12_exec "$_M12_CTR01" <<'EOF' || return $?
command -v nft >/dev/null || exit 10
sub="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' recette_donnees 2>/dev/null | awk '{print $1}')"
case "$sub" in *.*/*) ;; *) exit 10 ;; esac
nft list table bridge filtrage_est_ouest >/dev/null 2>&1 && exit 10
nft -f - <<NFT || exit 1
table bridge filtrage_est_ouest {
	comment "durcissement InfoGér : pas de flux est-ouest vers les bases"
	chain transit {
		type filter hook forward priority filter; policy accept;
		ip daddr $sub tcp dport 5432 drop
	}
}
NFT
journal "table bridge filtrage_est_ouest posée ($sub, TCP 5432)"
EOF
      ;;
  esac
}

# _e37_casse — 0 si /pret ne répond plus 200 (503, ou plus de réponse) alors que l'API est vivante.
_e37_casse() {
  local e
  e="$(m12_etat_service api)"
  [[ "$e" == running* ]] && [[ "$(m12_api_pret_code)" != 200 ]]
}

panne_E37_v1() { m12_recette_preparer && m12_essayer E37 4 1; }
panne_E37_v2() { m12_recette_preparer && m12_essayer E37 4 2; }
panne_E37_v3() { m12_recette_preparer && m12_essayer E37 4 3; }
panne_E37_v4() { m12_recette_preparer && m12_essayer E37 4 4; }

verifier_E37() { sleep 5; m12_attendre 60 _e37_casse; }

annuler_E37() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
nft delete table bridge filtrage_est_ouest 2>/dev/null || true
if ! docker inspect -f '{{json .NetworkSettings.Networks}}' recette-api-1 2>/dev/null | grep -q recette_donnees; then
  docker network connect recette_donnees recette-api-1 2>/dev/null || true
fi
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
  m12_recette_reinitialiser
  m12_oublier E37
}

resume_E37() {
  echo "L'API de recette répond sur /sante, mais /pret échoue : elle ne joint plus PostgreSQL."
}

symptome_E37() {
  local detail
  case "$WB_VAR" in
    1) detail="Lucas a appliqué hier soir une demande de Sophie (« isoler la base de recette sur un réseau interne »)." ;;
    2) detail="Lucas a « débogué le réseau » de la recette hier soir, directement sur ctr01, et jure n'avoir modifié aucun fichier." ;;
    3) detail="Lucas a « nettoyé » compose.yaml de la recette hier soir (« des lignes qui ne servaient à rien »)." ;;
    *) detail="InfoGér a passé son script de « durcissement réseau » sur ctr01 cette nuit ; Lucas n'a rien touché à la pile." ;;
  esac
  wb_symptome "Ticket INC-3937 — De : Julien Petit" \
    "Depuis ce matin, l'API de recette (ctr01) répond sur /sante mais /pret échoue (503, ou plus de réponse du tout) et toute" \
    "création de rendez-vous échoue : elle ne joint plus PostgreSQL. La base, elle, est saine." \
    "$detail" \
    "Rétablis le service, puis dis-moi ce qu'il fallait faire à la place." \
    "" \
    "Pile : ctr01, /srv/recette. Temps cible : 45 min. Contrôle : lab/bin/check 12 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E37 4 "$@"; }
fi

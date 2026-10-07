# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M06-E41 « Panne : SERVFAIL sur la zone signée »
#
# Préalable : la zone par1.medisphere.internal est signée (M06-E26) et VALIDÉE par le récurseur de
# dns01 (ancre de confiance : réponse avec le drapeau ad). Variantes :
#   1. récurseur : l'empreinte du DS de l'ancre de confiance (dnssec.trustanchors de recursor.yml)
#      modifiée d'un caractère (« recopiée à la main après le roulement de clé ») ;
#   2. autoritaire : la zone passée en mode PRESIGNED sur dns01 (commande destinée au secondaire),
#      série incrémentée → plus de signature à la volée, ni RRSIG ni DNSKEY servis ;
#   3. autoritaire : roulement de KSK raté — nouvelle clé ajoutée et activée, anciennes clés
#      DÉSACTIVÉES (pas supprimées) sans mettre à jour l'ancre → DNSKEY ne correspond plus au DS.
# ⚠️ Clés de zone : la variante 3 exporte d'abord TOUTES les clés de la zone (pdnsutil zone
# export-key) dans /var/lib/workbook/M06-E41.cle-* (600, sur dns01) ; aucune clé existante n'est
# supprimée. L'annulation réactive les anciennes clés et retire seulement la clé ajoutée par la panne,
# et seulement si l'état est encore celui laissé par la panne (sinon : réparation, rien n'est touché).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

# _e41_valide — la zone est résolue ET validée (drapeau ad) par le récurseur de dns01.
_e41_valide() {
  dig +dnssec +time=3 +tries=1 @10.10.20.10 "$_M06_ZONE" SOA 2>/dev/null | grep -Eq '^;; flags:[a-z ]* ad[ ;]'
}

_e41_statut() { m06_dig_statut 10.10.20.10 "$_M06_ZONE" SOA +dnssec; }

_e41_precondition() {
  if ! _e41_valide; then
    wb_avert "la zone $_M06_ZONE n'est pas validée par le récurseur de dns01 (pas de drapeau ad) : M06-E26, lab/bin/check 06 41"
    return 1
  fi
  m06_wb_exec dns01 ZONE="$_M06_ZONE" >/dev/null <<'EOF' || { wb_avert "dns01 : pdnsutil ne voit pas de clé active pour $_M06_ZONE"; return 1; }
pdnsutil zone show "$ZONE" 2>/dev/null | grep -Eq '^ID = [0-9]+ .*[[:space:]]Active'
EOF
}

_mE41_une() {
  local n="$1" rc=0
  m06_wb_exec dns01 N="$n" ZONE="$_M06_ZONE" >/dev/null <<'EOF' || rc=$?
cles() { pdnsutil zone show "$ZONE" 2>/dev/null | sed -nE 's/^ID = ([0-9]+) \(([A-Z]+)\).*[[:space:]](Active|Inactive).*/\1 \2 \3/p'; }
case "$N" in
  1)
    f=/etc/powerdns/recursor.yml
    # Premier DS SHA-256 hors racine (étiquettes 20326 et 38696 de la racine exclues).
    orig="$(grep -oE '\b[0-9]{1,5} [0-9]{1,3} 2 [0-9a-fA-F]{64}\b' "$f" | grep -vE '^(20326|38696) ' | head -n 1)"
    [ -n "$orig" ] || exit 10
    case "${orig: -1}" in 0) nv=1 ;; *) nv=0 ;; esac
    subst "$f" "$orig" "${orig%?}$nv" || exit $?
    systemctl restart pdns-recursor
    journal "recursor.yml : DS de l'ancre modifié ($orig → …$nv)"
    ;;
  2)
    [ "$(pdnsutil metadata get "$ZONE" PRESIGNED 2>/dev/null | grep -c '= 1')" = 0 ] || exit 10
    pdnsutil zone set-presigned "$ZONE" >/dev/null || exit 1
    : >"$WB_DIR/M06-E41.presigned"
    journal "zone $ZONE passée en PRESIGNED"
    ;;
  3)
    anciennes="$(cles | awk '$3 == "Active" { print $1 }')"
    [ -n "$anciennes" ] || exit 10
    for id in $(cles | awk '{ print $1 }'); do
      umask 077
      pdnsutil zone export-key "$ZONE" "$id" >"$WB_DIR/M06-E41.cle-$id" || exit 1
    done
    avant="$(cles | awk '{ print $1 }' | sort)"
    pdnsutil zone add-key "$ZONE" ksk active published ecdsa256 >/dev/null || exit 1
    nouvelle="$(cles | awk '{ print $1 }' | sort | comm -13 <(printf '%s\n' "$avant") - | head -n 1)"
    [ -n "$nouvelle" ] || exit 1
    printf '%s\n' "$anciennes" >"$WB_DIR/M06-E41.anciennes"
    printf '%s\n' "$nouvelle" >"$WB_DIR/M06-E41.nouvelle"
    for id in $anciennes; do pdnsutil zone deactivate-key "$ZONE" "$id" >/dev/null || exit 1; done
    journal "roulement raté : clé $nouvelle ajoutée, clés $(echo "$anciennes" | tr '\n' ' ')désactivées (exportées avant)"
    ;;
esac
if [ "$N" != 1 ]; then
  pdnsutil zone rectify "$ZONE" >/dev/null 2>&1 || true
  pdnsutil zone increase-serial "$ZONE" >/dev/null 2>&1 || true
  systemctl restart pdns
  sleep 2
  pdns_control notify "$ZONE" >/dev/null 2>&1 || true
fi
EOF
  ((rc == 0)) || { _e41_defaire "$n"; return "$rc"; }
  m06_vider_caches_rec "$_M06_ZONE"
  sleep 3
  if [[ "$(_e41_statut)" != SERVFAIL ]]; then
    m06_journal E41 "variante $n sans effet (statut $(_e41_statut))"
    _e41_defaire "$n"
    return 10
  fi
}

_e41_defaire() {
  m06_wb_exec dns01 N="$1" ZONE="$_M06_ZONE" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01 (zone $_M06_ZONE)"
cles() { pdnsutil zone show "$ZONE" 2>/dev/null | sed -nE 's/^ID = ([0-9]+) \(([A-Z]+)\).*[[:space:]](Active|Inactive).*/\1 \2 \3/p'; }
change=0
if [ -f "$WB_DIR/$WB_EX.subst" ]; then
  if [ -n "$(defaire_subst)" ]; then systemctl restart pdns-recursor; fi
fi
if [ -f "$WB_DIR/M06-E41.presigned" ]; then
  if pdnsutil metadata get "$ZONE" PRESIGNED 2>/dev/null | grep -q '= 1'; then
    pdnsutil zone unset-presigned "$ZONE" >/dev/null && change=1
    journal "annulation : PRESIGNED retiré"
  else
    journal "annulation : PRESIGNED déjà retiré (réparation)"
  fi
  rm -f "$WB_DIR/M06-E41.presigned"
fi
if [ -f "$WB_DIR/M06-E41.nouvelle" ]; then
  nouvelle="$(cat "$WB_DIR/M06-E41.nouvelle")"
  anciennes="$(cat "$WB_DIR/M06-E41.anciennes")"
  inactives=1
  for id in $anciennes; do
    cles | awk -v i="$id" '$1 == i && $3 == "Inactive" { f = 1 } END { exit !f }' || inactives=0
  done
  if [ "$inactives" = 1 ] && cles | awk -v i="$nouvelle" '$1 == i && $3 == "Active" { f = 1 } END { exit !f }'; then
    for id in $anciennes; do pdnsutil zone activate-key "$ZONE" "$id" >/dev/null; done
    pdnsutil zone remove-key "$ZONE" "$nouvelle" >/dev/null
    change=1
    journal "annulation : clés $(echo "$anciennes" | tr '\n' ' ')réactivées, clé $nouvelle retirée"
  else
    journal "annulation : clés de zone modifiées depuis l'injection (réparation), laissées telles quelles ; exports conservés dans $WB_DIR/M06-E41.cle-*"
  fi
  rm -f "$WB_DIR/M06-E41.nouvelle" "$WB_DIR/M06-E41.anciennes"
fi
if [ "$change" = 1 ]; then
  pdnsutil zone rectify "$ZONE" >/dev/null 2>&1 || true
  pdnsutil zone increase-serial "$ZONE" >/dev/null 2>&1 || true
  systemctl restart pdns
  sleep 2
  pdns_control notify "$ZONE" >/dev/null 2>&1 || true
fi
EOF
  m06_vider_caches_rec "$_M06_ZONE"
}

_e41_injecter() {
  _e41_precondition || return 1
  m06_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

verifier_E41() {
  [[ "$(_e41_statut)" == SERVFAIL ]]
}

annuler_E41() {
  _e41_defaire "${WB_VAR:-0}"
}

resume_E41() {
  echo "Tous les noms de par1.medisphere.internal répondent SERVFAIL sur dns01 ; le reste d'Internet se résout."
}

symptome_E41() {
  wb_symptome "Ticket INC-3347 — De : Nadia Roussel" \
    "Alerte P1 : plus aucun nom en par1.medisphere.internal ne se résout via dns01 (SERVFAIL)." \
    "La CI, Ansible et les sauvegardes échouent en cascade. Internet se résout normalement." \
    "Karim travaillait hier sur la signature de la zone (« préparation du roulement de clé »)." \
    "⚠️ Ne supprime aucune clé de zone sans l'avoir exportée : Sophie veut pouvoir tout rejouer." \
    "" \
    "Temps cible : 60 min. Contrôle : lab/bin/check 06 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E41 3 "$@"; }
fi

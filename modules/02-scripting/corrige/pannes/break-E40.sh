# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M02-E40 « Panne : l'inventaire met dix minutes »
#
# Dépose dans /opt/workbook/m02/e40/ de adm01 le script d'inventaire repris d'InfoGér par
# Lucas (bin/ms-inventaire-lab + etc/inventaire.conf). Il interroge le VRAI Proxmox, en
# lecture seule (jeton wb-automation@pve!lab de ~/.config/workbook/pve-api.env).
# Variantes (corrige/fichiers/M02-E40/panne/ms-inventaire-lab.vN) :
#   1. balayage de toute la plage de VMID 1000-9999 (≈ 9 000 appels refusés) au lieu de lister ;
#   2. reprises à délai exponentiel (6 essais, 31 s d'attente cumulée par appel) sur TOUTES les erreurs, y compris les
#      réponses définitives (403 sur pbs-par2, 500 « VM not running » sur l'agent) ;
#   3. un « ssh pve01 pvesh get » par champ et par VM (connexion SSH + démarrage de pvesh) ;
#   4. résolution DNS sur la passerelle 10.10.10.1 (DNS_INVENTAIRE de inventaire.conf) :
#      gw01 jette en silence, chaque requête attend le délai complet de dig.
# Vérification : le script ne termine pas en 30 s (le seuil du contrôle et du ticket). Annulation : la zone
# encore cassée est déplacée (e40.annule-<date>) ; rien n'est supprimé, rien n'est modifié sur pve01 ;
# une zone réparée reste en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E40_ZONE=/opt/workbook/m02/e40
_E40_MOD="$WB_ROOT/modules/02-scripting"

_e40_injecter() {
  local v="$1" z="$_E40_ZONE" dns=10.10.20.10 env="$HOME/.config/workbook/pve-api.env"
  [[ -r "$env" ]] || { wb_avert "$env illisible"; return 1; }
  if ((v == 3)) && ! remote "$WB_PVE_HOST" true >/dev/null 2>&1; then
    wb_avert "accès SSH à $WB_PVE_HOST impossible : variante 3 inapplicable"
    return 1
  fi
  wb_exec localhost U="$(id -un)" Z="$z" >/dev/null <<'EOF' || return 1
mkdir -p /opt/workbook/m02
chown "$U:" /opt/workbook/m02
if [ -e "$Z" ]; then
  mv -- "$Z" "$Z.precedent-$(date +%Y%m%d-%H%M%S)"
fi
journal "préparation de la zone $Z"
EOF
  mkdir -p "$z/bin" "$z/etc" "$z/sortie" || return 1
  install -m 755 "$_E40_MOD/corrige/fichiers/M02-E40/panne/ms-inventaire-lab.v$v" "$z/bin/ms-inventaire-lab" || return 1
  if ((v == 4)); then dns=10.10.10.1; fi
  {
    echo '# Configuration de l'"'"'inventaire (reprise du script InfoGér, PLAT-381)'
    # shellcheck disable=SC2016  # $HOME doit rester littéral dans le fichier de configuration
    echo 'API_ENV="$HOME/.config/workbook/pve-api.env"'
    echo 'POOL=lab'
    echo 'DOMAINE=par1.medisphere.internal'
    echo '# DNS de référence pour les noms de l'"'"'inventaire'
    echo "DNS_INVENTAIRE=$dns"
    echo "SORTIE=$z/sortie/inventaire-lab.md"
  } >"$z/etc/inventaire.conf"
  touch -d 'yesterday 11:05' "$z/bin/ms-inventaire-lab" "$z/etc/inventaire.conf"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }
panne_E40_v4() { _e40_injecter 4; }

# verifier_E40 — l'inventaire ne se termine pas en 30 secondes (seuil du contrôle check-E40).
verifier_E40() {
  local rc=0
  echo "Mesure de la durée de l'inventaire (30 s au plus)…" >&2
  (cd "$_E40_ZONE" && timeout 30 bin/ms-inventaire-lab -o /dev/null) >/dev/null 2>&1 || rc=$?
  ((rc == 124))
}

# annuler_E40 — script (et, en variante 4, configuration) encore tels que la panne les a déposés :
# zone mise de côté. Modifiés par l'apprenant (réparation) : zone laissée en place.
annuler_E40() {
  local z="$_E40_ZONE" v
  [[ -e "$z" ]] || return 0
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  v="${WB_VAR:-}"
  if [[ ! "$v" =~ ^[1-4]$ ]] || {
    cmp -s "$z/bin/ms-inventaire-lab" "$_E40_MOD/corrige/fichiers/M02-E40/panne/ms-inventaire-lab.v$v" \
      && { [[ "$v" != 4 ]] || grep -q '^DNS_INVENTAIRE=10\.10\.10\.1$' "$z/etc/inventaire.conf" 2>/dev/null; }
  }; then
    mv -- "$z" "$z.annule-$(date +%Y%m%d-%H%M%S)" || wb_avert "zone $z non déplacée"
  else
    echo "Zone $z réparée (script modifié) : laissée en place." >&2
  fi
}

resume_E40() {
  echo "L'inventaire du lab (/opt/workbook/m02/e40/bin/ms-inventaire-lab) met plusieurs minutes au lieu de quelques secondes."
}

symptome_E40() {
  wb_symptome "Ticket PLAT-381 — De : Karim Benali" \
    "Lucas a repris le script d'inventaire d'InfoGér : /opt/workbook/m02/e40/bin/ms-inventaire-lab." \
    "Le résultat est juste, mais il met une dizaine de minutes pour une dizaine de VMs. Je veux" \
    "le lancer avant chaque intervention et pendant les astreintes : il doit tenir en moins de 30 s." \
    "Mesure d'abord où passe le temps (pas d'optimisation à l'aveugle), corrige, et montre-moi" \
    "les chiffres avant/après." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 02 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E40 4 "$@"; }
fi

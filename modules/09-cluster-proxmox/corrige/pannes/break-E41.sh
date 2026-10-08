# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M09-E41 « Panne : la sauvegarde nocturne a échoué »
#
# Côté cluster SEULEMENT (stockage pbs-par2 de /etc/pve/storage.cfg et son secret) : pbs01 n'est
# jamais touché (PLAN §4.9). Variantes :
#   1. empreinte : la propriété « fingerprint » de pbs-par2 remplacée par une autre empreinte
#      (« le certificat de PBS a été renouvelé », dit le changement de Lucas… mais pas celle-là) ;
#   2. secret du jeton : /etc/pve/priv/storage/pbs-par2.pw remplacé par un ancien secret révoqué
#      (même forme, autre valeur) → authentification refusée par PBS ;
#   3. namespace : « par1/hv » devenu « par1/hyperviseurs » (renommage « pour la lisibilité ») →
#      le namespace n'existe pas sur le datastore : liste vide, sauvegardes refusées.
# Sauvegardes : /var/lib/workbook/M09-E41.* sur hv01 (fichier de secret d'origine en 600, dans le
# dossier 700 du workbook), état local ~/.local/state/workbook/M09-E41/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m09-commun.sh
source "$WB_ROOT/modules/09-cluster-proxmox/corrige/pannes/_m09-commun.sh"

_E41_STO=pbs-par2

# _e41_nb_sauvegardes — nombre de sauvegardes listées par hv01 dans pbs-par2 (vide si erreur).
_e41_nb_sauvegardes() {
  m09_ssh hv01 "timeout 60 pvesm list $_E41_STO --content backup" 2>/dev/null | awk 'NR > 1' | wc -l
}

_e41_liste_ok() {
  m09_ssh hv01 "timeout 60 pvesm list $_E41_STO --content backup" >/dev/null 2>&1
}

_e41_effet() {
  ! _e41_liste_ok || [[ "$(_e41_nb_sauvegardes)" == 0 ]]
}

_e41_precondition() {
  m09_cluster_sain || return 1
  m09_stockage_actif hv01 "$_E41_STO" || { wb_avert "stockage $_E41_STO inactif sur hv01 (M09-E15)"; return 1; }
  if ! _e41_liste_ok || [[ "$(_e41_nb_sauvegardes)" == 0 ]]; then
    wb_avert "aucune sauvegarde listée dans $_E41_STO : fais d'abord M09-E15 (au moins une sauvegarde)"
    return 1
  fi
}

_mE41_une() {
  local n="$1" rc=0
  case "$n" in
    1)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || rc=$?
v="$(stockage_section "$STO" fingerprint)"
printf '%s\n' "${v:-ABSENTE}" >"$WB_DIR/$WB_EX.empreinte"
neuve="$(head -c 32 /dev/urandom | od -An -tx1 | tr -s ' \n' ':' | sed 's/^://; s/:$//')"
pvesm set "$STO" --fingerprint "$neuve" >/dev/null || exit 1
printf '%s\n' "$neuve" >"$WB_DIR/$WB_EX.empreinte-posee"
journal "empreinte de $STO remplacée"
EOF
      ;;
    2)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || rc=$?
f="/etc/pve/priv/storage/$STO.pw"
[ -f "$f" ] || exit 10
garder "$f"
# Ancien secret « révoqué » : même forme qu'un secret de jeton PBS (UUID), autre valeur.
cat /proc/sys/kernel/random/uuid >"$f"
pose "$f"
journal "secret du jeton de $STO remplacé"
EOF
      ;;
    3)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || rc=$?
v="$(stockage_section "$STO" namespace)"
[ -n "$v" ] || exit 10
printf '%s\n' "$v" >"$WB_DIR/$WB_EX.namespace"
pvesm set "$STO" --namespace par1/hyperviseurs >/dev/null || exit 1
journal "namespace de $STO : $v → par1/hyperviseurs"
EOF
      ;;
  esac
  ((rc == 0)) || { _e41_defaire "$n"; return "$rc"; }
  if ! m09_attendre 30 _e41_effet; then
    _e41_defaire "$n"
    return 10
  fi
}

_e41_defaire() {
  case "$1" in
    1)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || wb_avert "annulation incomplète (empreinte de pbs-par2)"
[ -f "$WB_DIR/$WB_EX.empreinte" ] || exit 0
orig="$(cat "$WB_DIR/$WB_EX.empreinte")"
posee="$(cat "$WB_DIR/$WB_EX.empreinte-posee" 2>/dev/null)"
if [ "$(stockage_section "$STO" fingerprint)" = "$posee" ]; then
  if [ "$orig" = ABSENTE ]; then pvesm set "$STO" --delete fingerprint >/dev/null
  else pvesm set "$STO" --fingerprint "$orig" >/dev/null
  fi
  journal "annulation : empreinte d'origine remise"
else
  journal "annulation : empreinte modifiée depuis l'injection (réparation), laissée telle quelle"
fi
rm -f "$WB_DIR/$WB_EX.empreinte" "$WB_DIR/$WB_EX.empreinte-posee"
EOF
      ;;
    2)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || wb_avert "annulation incomplète (secret de pbs-par2)"
f="/etc/pve/priv/storage/$STO.pw"
[ -f "$WB_DIR/$WB_EX.$(_cle "$f").pose" ] || exit 0
rendre "$f" >/dev/null
EOF
      ;;
    3)
      m09_exec hv01 STO="$_E41_STO" >/dev/null <<'EOF' || wb_avert "annulation incomplète (namespace de pbs-par2)"
[ -f "$WB_DIR/$WB_EX.namespace" ] || exit 0
if [ "$(stockage_section "$STO" namespace)" = par1/hyperviseurs ]; then
  pvesm set "$STO" --namespace "$(cat "$WB_DIR/$WB_EX.namespace")" >/dev/null
  journal "annulation : namespace d'origine remis"
else
  journal "annulation : namespace modifié depuis l'injection (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/$WB_EX.namespace"
EOF
      ;;
  esac
}

_e41_injecter() {
  _e41_precondition || return 1
  m09_essayer E41 3 "$1"
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

verifier_E41() {
  _e41_effet
}

annuler_E41() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e41_defaire "$WB_VAR" ;;
    *) _e41_defaire 1; _e41_defaire 2; _e41_defaire 3 ;;
  esac
}

resume_E41() {
  echo "Le job de sauvegarde nocturne du cluster vers pbs-par2 a échoué pour toutes les VMs."
}

symptome_E41() {
  wb_symptome "Ticket INC-3647 — De : Nadia Roussel" \
    "Courriel de 2 h 14 : « vzdump backup status : backup failed » pour toutes les VMs du cluster" \
    "hv-par1 vers pbs-par2. Le PBS de PAR2 est en bonne santé (les sauvegardes de pve01 sont" \
    "passées cette nuit) : le problème est de notre côté. Sophie rappelle qu'une nuit sans" \
    "sauvegarde se déclare au registre des écarts ; deux nuits, c'est un incident HDS." \
    "Interdiction de toucher à pbs01 sans fiche de changement." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 09 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 09 E41 3 "$@"; }
fi

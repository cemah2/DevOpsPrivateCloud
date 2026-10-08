# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M10-E35 « Panne : No valid host was found »
#
# Variantes :
#   1. les deux nova-compute désactivés par l'API (« maintenance » jamais close) → le filtre
#      ComputeFilter (et le pré-filtre des services désactivés) ne laisse aucun hôte ;
#   2. nova.conf des deux calculs (/etc/kolla/nova-compute/nova.conf, hors du code) :
#      reserved_host_memory_mb = 7680 → l'inventaire MEMORY_MB envoyé à Placement ne laisse plus
#      de place pour 1 Gio → « Got no allocation candidates from the Placement API » ;
#   3. image Debian 13 publique : propriété hw_architecture=aarch64 → ImagePropertiesFilter rejette
#      les deux calculs x86_64 ;
#   4. gabarit m1.petit : propriété trait:HW_GPU_API_VULKAN=required → aucun fournisseur de
#      ressources n'a ce trait, Placement ne renvoie aucun candidat.
# Constat : une instance sonde m10-e35-sonde (projet plateforme, m1.petit, image Debian 13, sans
# réseau) doit finir en ERROR avec « No valid host ». Elle est supprimée ensuite.
# Sauvegardes : /var/lib/workbook/M10-E35.* sur les calculs (variante 2) ; valeurs d'origine des
# propriétés dans ~/.local/state/workbook/M10-E35/ (variantes 3 et 4). Rien n'est rétabli qui a
# déjà été réparé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m10-commun.sh
source "$WB_ROOT/modules/10-openstack/corrige/pannes/_m10-commun.sh"

_E35_RAISON="maintenance noyau CHG-1172"
_E35_TRAIT="trait:HW_GPU_API_VULKAN"

# _e35_sonde — crée l'instance sonde, garde son état et son message d'erreur, puis la supprime.
# Affiche « ACTIVE », « ERROR <message> » ou « ECHEC ».
_e35_sonde() {
  local img j etat msg
  img="$(m10_image_sonde)" || { echo ECHEC; return 0; }
  m10_osp server create --flavor "$_M10_GABARIT" --image "$img" --no-network --wait m10-e35-sonde >/dev/null 2>&1 || true
  j="$(m10_osp server show m10-e35-sonde -f json 2>/dev/null)" || true
  etat="$(jq -r '.status // empty' <<<"$j" 2>/dev/null)"
  msg="$(jq -r '.fault.message // empty' <<<"$j" 2>/dev/null)"
  m10_osp server delete --wait m10-e35-sonde >/dev/null 2>&1 || true
  printf '%s %s\n' "${etat:-ECHEC}" "$msg"
}

_e35_precondition() {
  m10_prerequis || return 1
  if ! m10_calculs_sains; then
    wb_avert "les nova-compute ne sont pas tous « enabled up » avant la panne : lab/bin/check 10 35"
    return 1
  fi
  if ! m10_image_sonde >/dev/null; then
    wb_avert "image debian-13 introuvable (M10-E06)"
    return 1
  fi
  if ! m10_os flavor show "$_M10_GABARIT" >/dev/null 2>&1; then
    wb_avert "gabarit $_M10_GABARIT introuvable (M10-E07)"
    return 1
  fi
}

_mE35_une() {
  local n="$1" rc=0 h img
  case "$n" in
    1)
      for h in "${_M10_CMP[@]}"; do
        m10_os compute service set --disable --disable-reason "$_E35_RAISON" "$h" nova-compute >/dev/null || rc=1
      done
      m10_journal E35 "nova-compute désactivés sur ${_M10_CMP[*]} (raison : $_E35_RAISON)"
      ;;
    2)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/kolla/nova-compute/nova.conf
[ -f "$f" ] || exit 10
# La réserve de M10-E20 (2048) est déjà dans [DEFAULT] : la remplacer (oslo.config retient la
# dernière valeur d'une option répétée) ; sinon, l'ajouter en tête de [DEFAULT].
if grep -q '^reserved_host_memory_mb[ \t]*=' "$f"; then
  subst "$f" '^reserved_host_memory_mb[ \t]*=.*$' 'reserved_host_memory_mb = 7680' || exit $?
else
  subst "$f" '^\[DEFAULT\][ \t]*\n' '[DEFAULT]\nreserved_host_memory_mb = 7680\n' || exit $?
fi
ctr_redemarrer nova_compute || exit 1
journal "$f : reserved_host_memory_mb = 7680 posé, nova_compute redémarré"
EOF
        ((rc == 0)) || break
      done
      # Le nova-compute redémarré renvoie son inventaire à Placement au démarrage.
      ((rc != 0)) || sleep 45
      ;;
    3)
      img="$(m10_image_sonde)" || return 1
      m10_ecrire E35 image "$img"
      m10_ecrire E35 image-arch "$(m10_os image show "$img" -f json 2>/dev/null | jq -r '.properties.hw_architecture // "ABSENT"')"
      m10_os image set --property hw_architecture=aarch64 "$img" >/dev/null || rc=1
      m10_journal E35 "image $img : hw_architecture=aarch64"
      ;;
    4)
      m10_ecrire E35 trait "$(m10_os flavor show "$_M10_GABARIT" -f json 2>/dev/null \
        | jq -r --arg k "$_E35_TRAIT" '.properties[$k] // "ABSENT"')"
      m10_os flavor set --property "$_E35_TRAIT=required" "$_M10_GABARIT" >/dev/null || rc=1
      m10_journal E35 "gabarit $_M10_GABARIT : $_E35_TRAIT=required"
      ;;
  esac
  ((rc == 0)) || return "$rc"
  local r
  r="$(_e35_sonde)"
  m10_ecrire E35 constat "$r"
  if [[ "$r" != ERROR* ]] || ! grep -qi 'no valid host' <<<"$r"; then
    # Sans effet sur ce lab (ou autre erreur) : défaire et passer à la suivante.
    _e35_defaire "$n"
    return 10
  fi
}

# _e35_defaire N — retire la variante N (annulation, ou variante sans effet).
_e35_defaire() {
  local h v img
  case "$1" in
    1)
      for h in "${_M10_CMP[@]}"; do
        v="$(m10_os compute service list --service nova-compute -f json 2>/dev/null \
          | jq -r --arg h "$h" '.[] | select(.Host == $h) | .Status' 2>/dev/null)"
        # Ne réactive que ce que la panne a désactivé (raison identique) : une désactivation
        # décidée ensuite par l'apprenant (autre raison) est laissée telle quelle.
        if [[ "$v" == disabled ]] && m10_os compute service list --long --service nova-compute -f json 2>/dev/null \
          | jq -e --arg h "$h" --arg r "$_E35_RAISON" '.[] | select(.Host == $h and ."Disabled Reason" == $r)' >/dev/null 2>&1; then
          m10_os compute service set --enable "$h" nova-compute >/dev/null 2>&1 || wb_avert "réactivation de nova-compute sur $h impossible"
          m10_journal E35 "annulation : nova-compute réactivé sur $h"
        fi
      done
      ;;
    2)
      for h in "${_M10_CMP[@]}"; do
        m10_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (nova.conf)"
if [ -n "$(defaire_subst)" ]; then ctr_redemarrer nova_compute; fi
EOF
      done
      ;;
    3)
      img="$(m10_lire E35 image)"
      v="$(m10_lire E35 image-arch)"
      if [[ -n "$img" ]] && [[ "$(m10_os image show "$img" -f json 2>/dev/null | jq -r '.properties.hw_architecture // empty')" == aarch64 ]]; then
        if [[ "$v" == ABSENT || -z "$v" ]]; then
          m10_os image unset --property hw_architecture "$img" >/dev/null 2>&1 || true
        else
          m10_os image set --property "hw_architecture=$v" "$img" >/dev/null 2>&1 || true
        fi
        m10_journal E35 "annulation : propriété hw_architecture de l'image $img rétablie"
      fi
      rm -f -- "$(m10_etat E35)/image" "$(m10_etat E35)/image-arch"
      ;;
    4)
      v="$(m10_lire E35 trait)"
      if [[ "$(m10_os flavor show "$_M10_GABARIT" -f json 2>/dev/null | jq -r --arg k "$_E35_TRAIT" '.properties[$k] // empty')" == required ]]; then
        if [[ "$v" == ABSENT || -z "$v" ]]; then
          m10_os flavor unset --property "$_E35_TRAIT" "$_M10_GABARIT" >/dev/null 2>&1 || true
        else
          m10_os flavor set --property "$_E35_TRAIT=$v" "$_M10_GABARIT" >/dev/null 2>&1 || true
        fi
        m10_journal E35 "annulation : propriété $_E35_TRAIT du gabarit rétablie"
      fi
      rm -f -- "$(m10_etat E35)/trait"
      ;;
  esac
  m10_osp server delete --wait m10-e35-sonde >/dev/null 2>&1 || true
}

_e35_injecter() {
  _e35_precondition || return 1
  m10_essayer E35 4 "$1"
}

panne_E35_v1() { _e35_injecter 1; }
panne_E35_v2() { _e35_injecter 2; }
panne_E35_v3() { _e35_injecter 3; }
panne_E35_v4() { _e35_injecter 4; }

# Le constat (instance sonde en ERROR « No valid host ») est fait dans _mE35_une : ici, on
# revérifie seulement qu'il a été enregistré.
verifier_E35() {
  grep -qi 'no valid host' <<<"$(m10_lire E35 constat)"
}

annuler_E35() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e35_defaire "$WB_VAR" ;;
    *) _e35_defaire 4; _e35_defaire 3; _e35_defaire 2; _e35_defaire 1 ;;
  esac
  rm -f -- "$(m10_etat E35)/constat"
}

resume_E35() {
  echo "Plus aucune instance ne se crée (m1.petit, Debian 13) : ERROR « No valid host was found »."
}

symptome_E35() {
  wb_symptome "Ticket INC-3741 — De : Julien Petit" \
    "Depuis ce matin, toutes mes créations d'instance échouent dans mediagenda-dev :" \
    "l'instance passe en ERROR au bout de quelques secondes, avec « No valid host was found »." \
    "Gabarit m1.petit, image Debian 13, rien d'exotique. Hier soir tout marchait. Le quota du" \
    "projet n'est pas atteint (j'ai vérifié). Pour reproduire depuis le projet plateforme :" \
    "  openstack server create --flavor m1.petit --image <Debian 13> --no-network --wait test" \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 10 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 10 E35 4 "$@"; }
fi

# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E20.sh — M18-E20 « Panne : le nœud Talos refuse sa configuration »
#
# Cluster talos-essai (talos-01 10.10.99.85 plan de contrôle, talos-02/03 .86/.87 travailleurs). Variantes :
#   1. CLIENT : le contexte courant de ~/.config/workbook/m18/talosconfig reçoit la CA, le certificat et
#      la clé d'un talosconfig généré pour un AUTRE cluster (« talosctl gen config » d'essai de Lucas) :
#      TLS mutuel refusé des deux côtés. Le fichier d'origine est copié avant (état local en 700).
#   2. CONFIGURATION : branche locale lucas/talos-zones dans ~/src/distributions ; talos/noeuds/talos-02.yaml
#      et talos-03.yaml reçoivent un document KubeNodeConfig (zone de baie) avec un champ inconnu
#      (« nodeLabels » au lieu de « labels ») : la validation stricte de Talos refuse le correctif.
#   3. NŒUD : talos-03 est réinitialisé (STATE et EPHEMERAL effacés, redémarrage) : il repart en mode
#      maintenance, sans configuration, à la même adresse (réseau par le lecteur nocloud). Sa
#      configuration de machine est sauvegardée avant (600, état local) pour l'annulation.
# Annulation : talosconfig d'origine remis s'il porte encore le certificat injecté ; branche de Lucas
# supprimée si elle n'a pas bougé ; talos-03 reconfiguré avec sa configuration sauvegardée s'il est
# encore en maintenance.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m18-commun.sh
source "$WB_ROOT/modules/18-distributions/corrige/pannes/_m18-commun.sh"

_E20_CP=10.10.99.85
_E20_T3=10.10.99.87

_e20_cp_repond() { m18_talos -n "$_E20_CP" version >/dev/null 2>&1; }
_e20_t3_maintenance() {
  timeout 30 talosctl -n "$_E20_T3" --insecure get disks >/dev/null 2>&1 \
    && ! m18_talos -n "$_E20_T3" version >/dev/null 2>&1
}
_e20_t3_configure() { m18_talos -n "$_E20_T3" version >/dev/null 2>&1; }

# Empreinte du certificat client du contexte courant d'un talosconfig.
_e20_crt() {
  local ctx
  ctx="$(yq -r '.context' "$1" 2>/dev/null)" || return 1
  yq -r ".contexts[\"$ctx\"].crt" "$1" 2>/dev/null | sha256sum | cut -d' ' -f1
}

_e20_patch_refuse() {
  local f
  for f in talos-02 talos-03; do
    if m18_talos -n "${_M18_TALOS_IP[$f]}" patch mc --dry-run -p "@$_M18_DEPOT/talos/noeuds/$f.yaml" >/dev/null 2>&1; then
      return 1
    fi
  done
}

_mE20_une() {
  local v="$1" d tmp ctx neuf zone f
  d="$(m18_etat E20)"
  case "$v" in
    1)
      m18_outils yq || return 10
      tmp="$(mktemp -d)"
      talosctl gen config wb-lucas https://10.10.99.250:6443 --output-types talosconfig -o "$tmp/talosconfig" >/dev/null 2>&1 \
        || { rm -rf "$tmp"; return 1; }
      ctx="$(yq -r '.context' "$_M18_TALOSCONFIG")" || { rm -rf "$tmp"; return 1; }
      [[ -n "$ctx" && "$ctx" != null ]] || { rm -rf "$tmp"; return 10; }
      cp -a "$_M18_TALOSCONFIG" "$d/talosconfig.orig" && chmod 600 "$d/talosconfig.orig"
      neuf="$(yq -r '.context' "$tmp/talosconfig")"
      for champ in ca crt key; do
        VAL="$(yq -r ".contexts[\"$neuf\"].$champ" "$tmp/talosconfig")" \
          yq -i ".contexts[\"$ctx\"].$champ = strenv(VAL)" "$_M18_TALOSCONFIG" || { rm -rf "$tmp"; return 1; }
      done
      rm -rf "$tmp"
      m18_ecrire E20 crt "$(_e20_crt "$_M18_TALOSCONFIG")"
      m18_ecrire E20 variante 1
      m18_journal E20 "talosconfig : CA, certificat et clé d'un autre cluster dans le contexte $ctx"
      ;;
    2)
      [[ -f "$_M18_DEPOT/talos/noeuds/talos-02.yaml" && -f "$_M18_DEPOT/talos/noeuds/talos-03.yaml" ]] || return 10
      m18_git_propre "$_M18_DEPOT" || return 10
      git -C "$_M18_DEPOT" rev-parse --verify --quiet refs/heads/lucas/talos-zones >/dev/null && return 10
      for f in talos-02 talos-03; do
        if [[ "$f" == talos-02 ]]; then zone=par1-baie-b; else zone=par1-baie-c; fi
        cat >>"$_M18_DEPOT/talos/noeuds/$f.yaml" <<EOF
---
# Zone de baie du nœud, comme sur k8s-par1 (M14-E14) : pour les topologySpreadConstraints. (Lucas)
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeLabels:
  topology.kubernetes.io/zone: $zone
EOF
      done
      m18_branche_lucas "$_M18_DEPOT" lucas/talos-zones "feat(talos): zone de baie sur les travailleurs" \
        || { git -C "$_M18_DEPOT" checkout --quiet -- talos/noeuds 2>/dev/null || true; return 1; }
      m18_ecrire E20 variante 2
      m18_journal E20 "branche lucas/talos-zones : KubeNodeConfig avec un champ inconnu sur talos-02 et talos-03"
      ;;
    3)
      m18_outils yq || return 10
      _e20_t3_configure || return 10
      ( umask 077; m18_talos -n "$_E20_T3" get mc v1alpha1 -o yaml | yq -r '.spec' >"$d/talos-03.yaml" ) || return 1
      if ! { [[ -s "$d/talos-03.yaml" ]] && grep -q 'kind' "$d/talos-03.yaml"; }; then
        rm -f "$d/talos-03.yaml"
        return 1
      fi
      m18_ecrire E20 variante 3
      m18_talos -n "$_E20_T3" reset --graceful=true --reboot \
        --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --wait=false >/dev/null 2>&1 || return 1
      m18_journal E20 "talos-03 réinitialisé (STATE, EPHEMERAL) : mode maintenance attendu"
      ;;
  esac
}

_e20_sain() {
  _e20_cp_repond && m18_noeud_pret "$_M18_KC_TALOS" talos-01 \
    && m18_noeud_pret "$_M18_KC_TALOS" talos-02 && m18_noeud_pret "$_M18_KC_TALOS" talos-03
}

_e20_injecter() {
  m18_outils talosctl kubectl git || return 1
  if ! _e20_sain; then
    wb_avert "talos-essai n'est pas sain avant la panne (talosctl vers 10.10.99.85 et trois nœuds Ready : M18-E05, E06)"
    return 1
  fi
  m18_essayer E20 3 "$1"
}

panne_E20_v1() { _e20_injecter 1; }
panne_E20_v2() { _e20_injecter 2; }
panne_E20_v3() { _e20_injecter 3; }

verifier_E20() {
  case "$(m18_lire E20 variante)" in
    1) ! _e20_cp_repond ;;
    2) _e20_patch_refuse ;;
    3) m18_attendre 420 _e20_t3_maintenance ;;
    *) return 1 ;;
  esac
}

annuler_E20() {
  local d o
  d="$(m18_etat E20)"
  if [[ -f "$d/talosconfig.orig" ]]; then
    o="$(m18_lire E20 crt)"
    if [[ -n "$o" && "$(_e20_crt "$_M18_TALOSCONFIG")" == "$o" ]]; then
      cp -a "$d/talosconfig.orig" "$_M18_TALOSCONFIG" && chmod 600 "$_M18_TALOSCONFIG"
      m18_journal E20 "annulation : talosconfig d'origine remis"
    fi
    rm -f "$d/talosconfig.orig"
    m18_oublier E20 crt
  fi
  m18_branche_annuler E20
  if [[ -f "$d/talos-03.yaml" ]]; then
    if _e20_t3_maintenance; then
      timeout 60 talosctl apply-config --insecure -n "$_E20_T3" --file "$d/talos-03.yaml" >/dev/null 2>&1 \
        || wb_avert "talos-03 : configuration non appliquée (talos/appliquer.sh talos-03 --maintenance)"
      m18_attendre 600 m18_noeud_pret "$_M18_KC_TALOS" talos-03 || wb_avert "talos-03 n'est pas revenu Ready : talosctl -n $_E20_T3 health"
      m18_journal E20 "annulation : talos-03 reconfiguré depuis sa configuration sauvegardée"
    fi
    rm -f "$d/talos-03.yaml"
  fi
  m18_oublier E20 variante
}

resume_E20() { echo "Un nœud ou le poste d'administration de talos-essai ne s'accorde plus sur sa configuration."; }

symptome_E20() {
  local l1 l2
  case "$(m18_lire E20 variante)" in
    1) l1="Depuis ce matin, plus aucune commande talosctl ne passe vers talos-essai depuis adm01,"
       l2="alors que les trois nœuds sont Ready dans Kubernetes. Lucas « testait talosctl » hier soir." ;;
    2) l1="Lucas a préparé un correctif pour les travailleurs (branche lucas/talos-zones, dans ta copie)."
       l2="« talos/appliquer.sh talos-02 --essai » le refuse. Je veux ce correctif en place aujourd'hui." ;;
    3) l1="talos-03 a disparu des nœuds Ready, et talosctl ne lui parle plus. Les pods ont été déplacés."
       l2="La VM tourne, d'après Proxmox. Personne n'a touché à Proxmox." ;;
  esac
  wb_symptome "Ticket INC-4520 — De : Karim Benali" "$l1" "$l2" \
    "Pas de SSH sur Talos : talosctl, le code de plateforme/distributions et le paquet de secrets, rien d'autre." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 18 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 18 E20 3 "$@"; }
fi

# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-S08.sh — F5-S08 « Panne : la reprise qui ne reprend pas » (BF, répétition à blanc AVANT le
# sinistre). Lancé depuis adm01 : lab/bin/break F5 08. Pannes sur les objets de PAR2 SEULEMENT.
#
# Variantes :
#   1. s3-02 : l'unité systemd qui lance « weed filer.sync » est arrêtée et désactivée (« Karim l'a
#      coupée pour la montée de SeaweedFS de s3-02 et ne l'a pas relancée ») → plus rien n'arrive de
#      s3-01 : l'archive de mediagenda-db n'avance plus à PAR2, la réplique de PAR2 prend du retard, le
#      RPO réel dérive sans bruit ;
#   2. k8s-par2 : le nœud unique k8s-par2-n01 est cordonné (« la maintenance de hp01 du mois dernier »)
#      et annoté medisphere.internal/panne=F5-S08 → aucun pod nouveau ne se planifie : le démarrage
#      d'essai des applications de PAR2 reste « Pending » ;
#   3. hp01 : la VM 1055 bao-par2 porte un verrou « backup » (sauvegarde vzdump interrompue) → « qm start »
#      refuse de la démarrer : pas de secrets à PAR2.
#
# Règles (CONVENTIONS §8, §11.10-11.11 ; PLAN §4.15 « Pannes de F5 ») : contrôle préalable (PAR2 prêt,
# aucune autre panne active) ; jamais ds-lab, la configuration de PBS, le réseau de hp01 ; aucune donnée
# touchée (filer.sync reprend à son point de contrôle ; un cordon et un verrou ne modifient aucun disque).
# Sauvegarde de l'état : /var/lib/workbook/F5-S08.* sur l'hôte modifié ; annulation seulement si l'état
# injecté est encore là (une réparation de l'apprenant n'est jamais défaite).
# Outils sur adm01 : kubectl, jq, curl, dig, ssh ; kubeconfig d'administration de k8s-par2
# (WB_F5_PAR2_ADMIN_KUBECONFIG, défaut ~/.kube/k8s-par2.config) pour la variante 2.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=../../checks/_f5-exercice.sh
source "$WB_ROOT/finaux/F5-pra/checks/_f5-exercice.sh"

_S08_K2ADMIN="${WB_F5_PAR2_ADMIN_KUBECONFIG:-$HOME/.kube/k8s-par2.config}"
_S08_ANNOT='medisphere.internal/panne'

_S08_REFUS=0

_s08_k2() { kubectl --kubeconfig "$_S08_K2ADMIN" --request-timeout=20s "$@"; }

_s08_prealable() {
  local a ko=0 d
  for a in kubectl jq curl dig ssh; do
    command -v "$a" >/dev/null 2>&1 || { echo "  - outil manquant sur adm01 : $a" >&2; ko=1; }
  done
  [[ -r "$_S08_K2ADMIN" ]] || { echo "  - kubeconfig d'administration de k8s-par2 illisible : $_S08_K2ADMIN" >&2; ko=1; }
  d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  if [[ -d "$d" ]] && find "$d" -maxdepth 1 -type f ! -name F5-S08 | grep -q .; then
    echo "  - une autre panne est active (une seule à la fois)" >&2
    ko=1
  fi
  echo "Contrôle préalable : PAR2 prêt…"
  _f5e_par2_pret || ko=1
  if ((ko)); then
    echo "Injection refusée : PAR2 doit être prêt avant la répétition (lab/bin/check F5 7). Rien n'a été touché." >&2
    return 1
  fi
}

panne_S08_v1() {
  local u
  _s08_prealable || { _S08_REFUS=1; return 1; }
  u="$(_f5e_filersync_unite)"
  [[ -n "$u" ]] || return 1
  wb_exec "$_f5e_s302" UNITE="$u" <<'EOF'
if systemctl is-enabled --quiet "$UNITE"; then echo active > "$WB_DIR/$WB_EX.etait-activee"; fi
echo "$UNITE" > "$WB_DIR/$WB_EX.unite"
systemctl disable --now "$UNITE" >/dev/null 2>&1 || exit 1
journal "$UNITE arrêtée et désactivée"
EOF
}

panne_S08_v2() {
  _s08_prealable || { _S08_REFUS=1; return 1; }
  _s08_k2 annotate node "$_F5E_NOEUD_PAR2" "$_S08_ANNOT=F5-S08" --overwrite >/dev/null || return 1
  _s08_k2 cordon "$_F5E_NOEUD_PAR2" >/dev/null || return 1
}

panne_S08_v3() {
  _s08_prealable || { _S08_REFUS=1; return 1; }
  wb_exec "$WB_PBS_HOST" VMID="$_F5E_VMID_BAO_PAR2" <<'EOF'
qm config "$VMID" >/dev/null 2>&1 || exit 1
if qm config "$VMID" | grep -q '^lock:'; then exit 1; fi
if [ "$(qm status "$VMID" | awk '{print $2}')" = running ]; then exit 1; fi
qm set "$VMID" --lock backup >/dev/null || exit 1
echo backup > "$WB_DIR/$WB_EX.verrou"
journal "VM $VMID verrouillée (lock backup)"
EOF
}

verifier_S08() {
  case "$WB_VAR" in
    1) ! _f5e_p_filersync >/dev/null 2>&1 ;;
    2) _s08_k2 get node "$_F5E_NOEUD_PAR2" -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -qx true ;;
    3) remote "$WB_PBS_HOST" "qm config $_F5E_VMID_BAO_PAR2" 2>/dev/null | grep -qx 'lock: backup' ;;
    *) return 1 ;;
  esac
}

annuler_S08() {
  # Injection refusée par le contrôle préalable : rien n'a été touché, rien à défaire.
  if ((_S08_REFUS)); then return 0; fi
  # Variante 1 : relancée seulement si l'unité est encore arrêtée.
  wb_exec "$_f5e_s302" <<'EOF' >/dev/null 2>&1 || wb_avert "s3-02 : filer.sync à vérifier (systemctl status)"
[ -f "$WB_DIR/$WB_EX.unite" ] || exit 0
u="$(cat "$WB_DIR/$WB_EX.unite")"
if [ -f "$WB_DIR/$WB_EX.etait-activee" ] && ! systemctl is-enabled --quiet "$u"; then systemctl enable "$u" >/dev/null 2>&1; fi
systemctl is-active --quiet "$u" || systemctl start "$u"
journal "$u rétablie"
rm -f -- "${WB_DIR:?}/${WB_EX:?}.unite" "${WB_DIR:?}/${WB_EX:?}.etait-activee"
EOF
  # Variante 2 : décordonné seulement si le nœud porte encore l'annotation de la panne.
  if [[ -r "$_S08_K2ADMIN" ]] &&
    [[ "$(_s08_k2 get node "$_F5E_NOEUD_PAR2" -o jsonpath="{.metadata.annotations.medisphere\.internal/panne}" 2>/dev/null)" == F5-S08 ]]; then
    _s08_k2 uncordon "$_F5E_NOEUD_PAR2" >/dev/null 2>&1 || wb_avert "k8s-par2 : uncordon de $_F5E_NOEUD_PAR2 à faire"
    _s08_k2 annotate node "$_F5E_NOEUD_PAR2" "$_S08_ANNOT-" >/dev/null 2>&1 || true
  fi
  # Variante 3 : déverrouillée seulement si le verrou posé est encore là.
  wb_exec "$WB_PBS_HOST" VMID="$_F5E_VMID_BAO_PAR2" <<'EOF' >/dev/null 2>&1 || wb_avert "hp01 : verrou de la VM 1055 à vérifier"
[ -f "$WB_DIR/$WB_EX.verrou" ] || exit 0
if qm config "$VMID" | grep -qx 'lock: backup'; then qm unlock "$VMID" && journal "VM $VMID déverrouillée"; fi
rm -f -- "${WB_DIR:?}/${WB_EX:?}.verrou"
EOF
}

symptome_S08() {
  case "$WB_VAR" in
    1)
      wb_symptome "Ticket INC-6108 — De : Karim Benali — Copie : Nadia Roussel" \
        "Répétition à blanc de RB-350 ce matin, sans toucher à PAR1. Les voyants étaient verts, mais" \
        "le relevé du témoin à PAR2 ne bouge plus : le dernier rendez-vous PRA-TEMOIN que voit la" \
        "réplique de PAR2 date d'avant la répétition, alors que PAR1 en écrit un par minute. Si PAR1" \
        "brûlait maintenant, on perdrait combien ? Aucune alerte n'a sonné." \
        "" \
        "Temps cible : 1 h (diagnostic, réparation, compte rendu). Contrôle : lab/bin/check F5 8"
      ;;
    2)
      wb_symptome "Ticket INC-6108 — De : Karim Benali — Copie : Julien Petit" \
        "Répétition à blanc de RB-350 : à l'étape « démarrage d'essai des applications de PAR2 », rien" \
        "ne démarre. Les pods restent en attente depuis vingt minutes, la base de PAR2 tourne," \
        "le nœud est « Ready ». Julien demande si on aurait vraiment pu reprendre en quatre heures." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check F5 8"
      ;;
    *)
      wb_symptome "Ticket INC-6108 — De : Karim Benali — Copie : Sophie Laurent" \
        "Répétition à blanc de RB-350 : à l'étape « démarrer bao-par2 », Proxmox refuse de démarrer la" \
        "VM. Sans OpenBao à PAR2, pas de secrets pour les applications. Sophie veut savoir si ça" \
        "nous serait arrivé un jour de sinistre, et pourquoi personne ne l'a vu avant." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check F5 8"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F5 S08 3 "$@"; }
fi

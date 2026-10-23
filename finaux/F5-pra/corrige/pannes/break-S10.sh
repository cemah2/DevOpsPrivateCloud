# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-S10.sh — F5-S10 « Panne : les surprises de la crise » (BF, PENDANT le PRA). Lancé depuis adm02
# (PAR1 est isolé) : admin@adm02:~/DevOpsPrivateCloud$ lab/bin/break F5 10
# Prérequis sur adm02 : alias SSH s3-02 et dns03 (admin + sudo -n), sudo -n local ; dig, curl, chronyc.
#
# Variantes (chacune une vraie surprise de PRA, sur des objets de PAR2 seulement) :
#   1. HORLOGE — s3-02 : chrony ne garde comme source que la passerelle de PAR1 (10.10.20.1, injoignable
#      depuis le sinistre) et l'horloge est avancée de 25 min (« la VM a redémarré avec une horloge
#      matérielle fausse, sans source de temps joignable »). SeaweedFS refuse les requêtes S3 signées à
#      plus de 15 min de son heure (RequestTimeTooSkewed) : MédiDoc n'enregistre plus, l'archivage des
#      WAL de la nouvelle production échoue. /etc/chrony/chrony.conf sauvegardé ;
#   2. DÉPENDANCE OUBLIÉE — dns03 : le récurseur (/etc/powerdns/recursor.yml) renvoie de nouveau les
#      zones medisphere.internal, par1 et par2 vers les autoritaires de PAR1 (10.10.20.10 et .16, port 5300)
#      (« le rôle Ansible de site_par2, rejoué cette nuit par Lucas, a remis la configuration de temps
#      normal ») : plus aucun nom interne ne se résout par dns03, dès l'expiration des caches ;
#   3. SECRET/ACCÈS — adm02 : un durcissement SSH (/etc/ssh/sshd_config.d/10-durcissement-f5.conf,
#      « AllowUsers <compte d'administration> ») bloque le compte « miroir » : Argo CD de k8s-par2 ne lit
#      plus les miroirs Git, plus aucun changement GitOps ne s'applique à PAR2.
#
# Contrôle préalable : lancé sur adm02, sinistre en cours (/var/lib/workbook/f5-t0 présent et PAR1
# injoignable), PAR2 sert les trois noms globaux, horloge de s3-02 synchronisée, dns03 résout, sshd de
# adm02 sans AllowUsers. Annulation : seulement si l'état injecté est encore là. Jamais ds-lab, PBS, ni
# le réseau de hp01 ; aucune donnée touchée.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=../../checks/_f5-exercice.sh
source "$WB_ROOT/finaux/F5-pra/checks/_f5-exercice.sh"

_S10_DROPIN=/etc/ssh/sshd_config.d/10-durcissement-f5.conf
_S10_REFUS=0

_s10_prealable() {
  local a ko=0 n s
  if [[ "$(hostname -s)" != adm02 ]]; then
    echo "Injection refusée : lance cette panne depuis adm02 (pendant le PRA)." >&2
    return 1
  fi
  for a in dig curl ssh sudo; do
    command -v "$a" >/dev/null 2>&1 || { echo "  - outil manquant sur adm02 : $a" >&2; ko=1; }
  done
  [[ -n "$(_f5e_t0 2>/dev/null)" ]] || { echo "  - aucun sinistre en cours (T0 absent de adm02) : S10 se joue pendant le PRA" >&2; ko=1; }
  for n in "${_F5E_NOMS[@]}"; do
    s="$(_f5e_site "$n" 2>/dev/null)" || s=""
    [[ "$s" == par2 ]] || { echo "  - $n n'est pas servi par PAR2 (réponse : ${s:-aucune}) : termine S09 d'abord" >&2; ko=1; }
  done
  remote "$_f5e_s302" "chronyc tracking 2>/dev/null | grep -q 'Leap status *: Normal'" 2>/dev/null \
    || { echo "  - s3-02 : horloge non synchronisée" >&2; ko=1; }
  dig +short +time=3 +tries=1 "@$_F5E_DNS03" s3-02.par2.medisphere.internal A 2>/dev/null | grep -q . \
    || { echo "  - dns03 ne résout pas s3-02.par2.medisphere.internal" >&2; ko=1; }
  sudo -n test ! -e "$_S10_DROPIN" 2>/dev/null || { echo "  - adm02 : $_S10_DROPIN existe déjà (ou sudo -n refusé)" >&2; ko=1; }
  if ((ko)); then
    echo "Injection refusée : PAR2 n'est pas dans l'état attendu. Rien n'a été touché." >&2
    return 1
  fi
}

panne_S10_v1() {
  _s10_prealable || { _S10_REFUS=1; return 1; }
  wb_exec "$_f5e_s302" <<'EOF'
f=/etc/chrony/chrony.conf
[ -f "$f" ] || exit 1
sauver "$f"
if [ -d /etc/chrony/sources.d ]; then
  for s in /etc/chrony/sources.d/*.sources; do
    [ -e "$s" ] || continue
    sauver "$s"
    rm -f -- "$s"
  done
fi
{
  echo "# Ansible managed — rôle base (chrony, client de temps du lab MédiSphère)"
  echo "server 10.10.20.1 iburst"
  echo "keyfile /etc/chrony/chrony.keys"
  echo "driftfile /var/lib/chrony/chrony.drift"
  echo "logdir /var/log/chrony"
  echo "maxupdateskew 100.0"
  echo "rtcsync"
  echo "makestep 1 3"
} > "$f"
cp -a "$f" "${WB_DIR:?}/${WB_EX:?}.chrony-injecte"
systemctl restart chrony || exit 1
date -s '+25 minutes' >/dev/null || exit 1
journal "chrony : source unique 10.10.20.1 ; horloge avancée de 25 min"
EOF
}

panne_S10_v2() {
  _s10_prealable || { _S10_REFUS=1; return 1; }
  wb_exec "$_f5e_dns03" <<'EOF'
f=/etc/powerdns/recursor.yml
[ -f "$f" ] || exit 1
command -v python3 >/dev/null || exit 1
python3 -c 'import yaml' 2>/dev/null || exit 1
sauver "$f"
python3 - "$f" <<'PY' || exit 1
import sys, yaml
chemin = sys.argv[1]
with open(chemin) as f:
    conf = yaml.safe_load(f) or {}
rec = conf.setdefault("recursor", {})
zones = rec.get("forward_zones") or []
cibles = {"medisphere.internal", "par1.medisphere.internal", "par2.medisphere.internal"}
par1 = ["10.10.20.10:5300", "10.10.20.16:5300"]
vues = set()
for z in zones:
    if z.get("zone", "").rstrip(".") in cibles:
        z["forwarders"] = par1
        vues.add(z["zone"].rstrip("."))
for c in sorted(cibles - vues):
    zones.append({"zone": c, "forwarders": par1})
rec["forward_zones"] = zones
with open(chemin, "w") as f:
    f.write("# Ansible managed\n# /etc/powerdns/recursor.yml — PowerDNS Recursor (rôle powerdns_recursor).\n")
    yaml.safe_dump(conf, f, default_flow_style=False, sort_keys=False)
PY
cp -a "$f" "${WB_DIR:?}/${WB_EX:?}.recursor-injecte"
systemctl restart pdns-recursor || exit 1
journal "recursor.yml : zones internes renvoyées vers PAR1"
EOF
}

panne_S10_v3() {
  local qui
  _s10_prealable || { _S10_REFUS=1; return 1; }
  qui="$(id -un)"
  wb_exec localhost QUI="$qui" DROPIN="$_S10_DROPIN" <<'EOF'
id miroir >/dev/null 2>&1 || exit 1
[ -n "$QUI" ] && [ "$QUI" != root ] || exit 1
printf '# Ansible managed — durcissement SSH (comptes autorisés à se connecter)\nAllowUsers %s\n' "$QUI" > "$DROPIN"
chmod 644 "$DROPIN"
if ! sshd -t; then rm -f -- "${DROPIN:?}"; exit 1; fi
cp -a "$DROPIN" "${WB_DIR:?}/${WB_EX:?}.dropin-injecte"
systemctl reload ssh || exit 1
journal "sshd : AllowUsers $QUI (miroir exclu)"
EOF
}

verifier_S10() {
  local d
  case "$WB_VAR" in
    1)
      d="$(remote "$_f5e_s302" 'date +%s' 2>/dev/null)" || return 1
      (($(date +%s) + 900 < d))
      ;;
    2)
      ! dig +short +time=3 +tries=1 "@$_F5E_DNS03" s3-02.par2.medisphere.internal A 2>/dev/null | grep -q '^[0-9]'
      ;;
    3)
      sudo -n sshd -T -C user=miroir,host=k8s-par2-n01,addr=10.20.20.50 2>/dev/null | grep -qi '^allowusers'
      ;;
    *) return 1 ;;
  esac
}

annuler_S10() {
  # Injection refusée par le contrôle préalable : rien n'a été touché, rien à défaire.
  if ((_S10_REFUS)); then return 0; fi
  # 1 : restaure chrony seulement si la configuration injectée est encore en place.
  wb_exec "$_f5e_s302" <<'EOF' >/dev/null 2>&1 || wb_avert "s3-02 : horloge et chrony à vérifier (chronyc tracking)"
t="${WB_DIR:?}/${WB_EX:?}"
[ -f "$t.manifeste" ] || exit 0
if cmp -s /etc/chrony/chrony.conf "$t.chrony-injecte"; then
  restaurer_fichiers
  systemctl restart chrony
  sleep 5
  chronyc -a makestep >/dev/null 2>&1 || true
  journal "chrony restauré, horloge recalée"
else
  rm -f -- "$t.manifeste" "$t".*.orig
fi
rm -f -- "$t.chrony-injecte"
EOF
  # 2 : restaure recursor.yml seulement s'il est identique à l'état injecté.
  wb_exec "$_f5e_dns03" <<'EOF' >/dev/null 2>&1 || wb_avert "dns03 : recursor.yml à vérifier"
t="${WB_DIR:?}/${WB_EX:?}"
[ -f "$t.manifeste" ] || exit 0
if cmp -s /etc/powerdns/recursor.yml "$t.recursor-injecte"; then
  restaurer_fichiers
  systemctl restart pdns-recursor
  journal "recursor.yml restauré"
else
  rm -f -- "$t.manifeste" "$t".*.orig
fi
rm -f -- "$t.recursor-injecte"
EOF
  # 3 : retire le fichier de durcissement seulement s'il est intact.
  wb_exec localhost DROPIN="$_S10_DROPIN" <<'EOF' >/dev/null 2>&1 || wb_avert "adm02 : $_S10_DROPIN à vérifier"
t="${WB_DIR:?}/${WB_EX:?}"
[ -f "$t.dropin-injecte" ] || exit 0
if cmp -s "$DROPIN" "$t.dropin-injecte"; then
  rm -f -- "${DROPIN:?}"
  sshd -t && systemctl reload ssh
  journal "durcissement SSH injecté retiré"
fi
rm -f -- "$t.dropin-injecte"
EOF
}

symptome_S10() {
  case "$WB_VAR" in
    1)
      wb_symptome "INC-6110 — De : Julien Petit — pendant le PRA" \
        "Les cabinets peuvent consulter les documents de MédiDoc, mais plus aucun dépôt ne passe :" \
        "erreur à chaque envoi depuis une dizaine de minutes. Et Karim me dit que la base de PAR2" \
        "signale des erreurs d'archivage. On était pourtant bons il y a une heure." \
        "" \
        "Temps cible : 45 min. Contrôle (depuis adm02) : lab/bin/check F5 10"
      ;;
    2)
      wb_symptome "INC-6110 — De : Nadia Roussel — pendant le PRA" \
        "Ça se dégrade par vagues depuis le début de matinée : d'abord MédiDoc qui ne trouve plus son" \
        "stockage, puis la base qui n'archive plus, et depuis adm02 « ssh s3-02 » répond « Could not" \
        "resolve hostname ». Personne n'a touché à la configuration… d'après le canal de crise." \
        "" \
        "Temps cible : 45 min. Contrôle (depuis adm02) : lab/bin/check F5 10"
      ;;
    *)
      wb_symptome "INC-6110 — De : Julien Petit — pendant le PRA" \
        "On a poussé dans le miroir l'augmentation des réplicas de l'API demandée par la cellule de" \
        "crise il y a quarante minutes : à PAR2, rien n'a bougé. Argo CD est rouge sur toutes les" \
        "applications. Les applications tournent encore, mais on ne peut plus rien changer." \
        "" \
        "Temps cible : 45 min. Contrôle (depuis adm02) : lab/bin/check F5 10"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F5 S10 3 "$@"; }
fi

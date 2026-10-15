# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E22.sh — M18-E22 « Panne : RKE2 ne démarre plus »
#
# Trois serveurs RKE2 (etcd à trois membres, profil CIS, Rocky Linux 10, RPM). La panne ne touche QUE
# rke2-03 (le quorum reste à deux membres) puis redémarre rke2-server : le service échoue en boucle et le
# nœud passe NotReady. Variantes :
#   1. paramètres noyau CIS : /etc/sysctl.d/60-rke2-cis.conf retiré et kernel.panic=0,
#      vm.overcommit_memory=0 (valeurs par défaut) : la vérification de l'hôte du profil échoue ;
#   2. utilisateur etcd supprimé (« nettoyage des comptes système » d'un vieux rôle de durcissement) :
#      le profil exige l'utilisateur et le groupe etcd. /etc/passwd, group, shadow, gshadow sont sauvegardés ;
#   3. /etc/rancher/rke2/config.yaml invalide : une étiquette de nœud ajoutée avec une tabulation ;
#   4. registre : « system-default-registry: registry.par1.medisphere.internal » ajouté (Harbor sans projet
#      « rancher ») : les images du plan de contrôle deviennent introuvables.
# Annulation : fichiers d'origine remis (prélude), paramètres noyau rechargés depuis le seul fichier CIS,
# rke2-server redémarré, attente du nœud Ready.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m18-commun.sh
source "$WB_ROOT/modules/18-distributions/corrige/pannes/_m18-commun.sh"

_E22_H=rke2-03

_mE22_une() {
  local v="$1" rc=0
  case "$v" in
    1)
      m18_exec "$_E22_H" <<'EOF' || rc=$?
f=/etc/sysctl.d/60-rke2-cis.conf
[ -f "$f" ] || exit 10
[ "$(sysctl -n kernel.panic)" = 10 ] || exit 10
sauver "$f"
rm -f "$f"
sysctl -w kernel.panic=0 vm.overcommit_memory=0 >/dev/null
journal "fichier sysctl CIS retiré, kernel.panic=0 et vm.overcommit_memory=0"
systemctl restart --no-block rke2-server
EOF
      ;;
    2)
      m18_exec "$_E22_H" <<'EOF' || rc=$?
getent passwd etcd >/dev/null || exit 10
for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do sauver "$f"; done
systemctl stop rke2-server
userdel -f etcd 2>/dev/null || true
getent group etcd >/dev/null && groupdel etcd 2>/dev/null
getent passwd etcd >/dev/null && { restaurer_fichiers; systemctl start rke2-server; exit 1; }
journal "utilisateur et groupe etcd supprimés"
systemctl start --no-block rke2-server
EOF
      ;;
    3)
      m18_exec "$_E22_H" <<'EOF' || rc=$?
f=/etc/rancher/rke2/config.yaml
[ -f "$f" ] || exit 10
grep -q '^node-label:' "$f" && exit 10
sauver "$f"
printf 'node-label:\n\t- "medisphere.fr/baie=par1-baie-c"\n' >> "$f"
journal "config.yaml : étiquette de nœud ajoutée avec une tabulation"
systemctl restart --no-block rke2-server
EOF
      ;;
    4)
      m18_exec "$_E22_H" <<'EOF' || rc=$?
f=/etc/rancher/rke2/config.yaml
[ -f "$f" ] || exit 10
grep -q '^system-default-registry:' "$f" && exit 10
sauver "$f"
printf '# Toutes les images par Harbor (ADR en cours, Lucas)\nsystem-default-registry: registry.par1.medisphere.internal\n' >> "$f"
journal "config.yaml : system-default-registry vers la racine de Harbor"
systemctl restart --no-block rke2-server
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  m18_ecrire E22 variante "$v"
  m18_journal E22 "variante $v injectée sur $_E22_H"
}

_e22_sain() {
  local n
  for n in rke2-01 rke2-02 rke2-03; do
    m18_noeud_pret "$_M18_KC_RKE2" "$n" || return 1
  done
}

_e22_injecter() {
  m18_outils kubectl || return 1
  if ! _e22_sain; then
    wb_avert "RKE2 n'est pas sain avant la panne (rke2-01, rke2-02, rke2-03 Ready : M18-E04, reconstruction du palier 3)"
    return 1
  fi
  m18_essayer E22 4 "$1"
}

panne_E22_v1() { _e22_injecter 1; }
panne_E22_v2() { _e22_injecter 2; }
panne_E22_v3() { _e22_injecter 3; }
panne_E22_v4() { _e22_injecter 4; }

# La panne a pris quand rke2-03 n'est plus Ready (kubelet arrêté avec le service : 40 à 60 s, plus le
# temps d'échec du démarrage) et que les deux autres serveurs le restent.
_e22_constat() {
  m18_noeud_pas_pret "$_M18_KC_RKE2" "$_E22_H" && m18_noeud_pret "$_M18_KC_RKE2" rke2-01
}
verifier_E22() { m18_attendre 240 _e22_constat; }

annuler_E22() {
  m18_exec "$_E22_H" <<'EOF' || wb_avert "annulation incomplète sur rke2-03 : regarde « journalctl -u rke2-server »"
if [ -f "$WB_DIR/$WB_EX.manifeste" ]; then
  restaurer_fichiers
  journal "annulation : fichiers d'origine remis"
fi
# Paramètres noyau : seul le fichier du profil, jamais un redémarrage de systemd-sysctl.
[ -f /etc/sysctl.d/60-rke2-cis.conf ] && sysctl -p /etc/sysctl.d/60-rke2-cis.conf >/dev/null
systemctl restart rke2-server || true
EOF
  m18_attendre 300 m18_noeud_pret "$_M18_KC_RKE2" "$_E22_H" || wb_avert "rke2-03 n'est pas revenu Ready : journalctl -u rke2-server -b sur le nœud"
  m18_oublier E22 variante
  m18_journal E22 "annulation terminée"
}

resume_E22() { echo "rke2-server ne démarre plus sur rke2-03, le nœud est NotReady."; }

symptome_E22() {
  wb_symptome "Ticket INC-4522 — De : Sophie Laurent — Copie : Nadia Roussel" \
    "Après une intervention sur rke2-03 (Lucas a « appliqué les recommandations de la semaine »)," \
    "rke2-server ne repart plus et le nœud est NotReady. rke2-01 et rke2-02 tiennent le quorum." \
    "Je ne veux aucune solution qui affaiblisse le profil CIS : pas de profile retiré," \
    "pas de protect-kernel-defaults à false, pas de SELinux en permissif." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 18 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 18 E22 4 "$@"; }
fi

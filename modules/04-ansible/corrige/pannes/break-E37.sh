# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M04-E37 « Panne : la variable n'a pas la valeur attendue »
#
# Le fuseau horaire du socle est porté par une variable du rôle base (valeur Europe/Paris, cherchée
# dans roles/base/defaults/main.yml puis inventories/lab/group_vars/all/*.yml). La panne passe dns01
# en UTC (« passage du playbook de Lucas ») ET pose une surcharge de cette variable à UTC, à un
# niveau de précédence qui l'emporte sur la valeur d'origine :
#   1. inventories/lab/host_vars/dns01/zz-infoger.yml           (host_vars > group_vars) ;
#   2. roles/base/vars/main.yml                                  (vars du rôle > tout l'inventaire) ;
#   3. playbooks/group_vars/all/zz-lucas.yml                     (group_vars du playbook > group_vars/all de l'inventaire) ;
#   4. inventories/lab/group_vars/role_dns/zz-dns.yml            (groupe enfant > all).
# Chaque variante est constatée par une sonde (playbook temporaire en --check, seule une tâche
# debug étiquetée s'exécute) ; une variante sans effet (valeur d'origine placée plus haut) est
# défaite et la suivante est essayée.
# Sauvegardes : ~/.local/state/workbook/M04-E37/ (copie de travail), /var/lib/workbook/M04-E37.tz
# sur dns01. Annulation : fuseau rétabli seulement si dns01 est encore en UTC ; fichiers de la
# copie de travail rétablis seulement s'ils sont encore tels que posés.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# _e37_variable — nom de la variable de fuseau du rôle base (valeur Europe/Paris).
_e37_variable() {
  local f v
  for f in "$_M04_SRC/roles/base/defaults/main.yml" "$_M04_SRC"/inventories/lab/group_vars/all/*.yml; do
    [[ -f "$f" ]] || continue
    v="$(sed -nE "s/^([a-z_][a-z0-9_]*):[[:space:]]*[\"']?Europe\/Paris[\"']?[[:space:]]*(#.*)?\$/\1/p" "$f" | head -n 1)"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  done
  return 1
}

# _e37_sonde VARIABLE — valeur EFFECTIVE de la variable pour dns01 dans un jeu qui applique le rôle
# base (mêmes règles de précédence qu'un vrai passage). Seule la tâche debug est exécutée.
_e37_sonde() {
  local var="$1" pb="$_M04_SRC/playbooks/.wb-sonde-m04.yml" sortie
  cat >"$pb" <<YML
---
- name: Sonde du workbook (M04-E37), supprimée après usage
  hosts: dns01
  gather_facts: false
  roles:
    - role: base
  tasks:
    - name: Valeur effective
      ansible.builtin.debug:
        msg: "WBSONDE={{ $var }}"
      tags: [wb_sonde]
YML
  sortie="$(m04_ansible ansible-playbook "playbooks/.wb-sonde-m04.yml" --check --tags wb_sonde 2>&1)" || true
  rm -f -- "$pb"
  sed -nE 's/.*"WBSONDE=([^"]*)".*/\1/p' <<<"$sortie" | head -n 1
}

_mE37_une() {
  local n="$1" var f
  var="$(_e37_variable)" || { wb_avert "aucune variable de fuseau valant Europe/Paris dans le rôle base"; return 1; }
  case "$n" in
    1) f="$_M04_SRC/inventories/lab/host_vars/dns01/zz-infoger.yml" ;;
    2) f="$_M04_SRC/roles/base/vars/main.yml" ;;
    3) f="$_M04_SRC/playbooks/group_vars/all/zz-lucas.yml" ;;
    4) f="$_M04_SRC/inventories/lab/group_vars/role_dns/zz-dns.yml" ;;
  esac
  if [[ -e "$f" ]]; then
    # Fichier existant (seul cas prévu : roles/base/vars/main.yml) : ajout en fin, si la clé n'y est pas.
    [[ "$n" == 2 ]] || return 10
    grep -Eq "^${var}:" "$f" && return 10
    m04_sauver E37 "$f" || return 1
    printf '\n# Lucas : forcé en UTC pour les journaux (corrélation avec ceux d'"'"'InfoGér)\n%s: UTC\n' "$var" >>"$f"
    m04_noter E37 "$f"
  else
    case "$n" in
      1) printf -- "---\n# Héritage InfoGér : les serveurs de noms restent en temps universel.\n%s: UTC\n" "$var" ;;
      2) printf -- "---\n# Lucas : forcé en UTC pour les journaux (corrélation avec ceux d'InfoGér)\n%s: UTC\n" "$var" ;;
      3) printf -- "---\n# Lucas : essais du rôle base, journaux en UTC\n%s: UTC\n" "$var" ;;
      4) printf -- "---\n# Serveurs DNS : horodatage des requêtes en UTC (demande InfoGér)\n%s: UTC\n" "$var" ;;
    esac | m04_poser E37 "$f" || return 1
  fi
  m04_journal E37 "surcharge de $var à UTC dans ${f#"$_M04_SRC"/}"
  if [[ "$(_e37_sonde "$var")" != UTC ]]; then
    m04_restaurer E37
    return 10
  fi
}

_e37_injecter() {
  m04_prerequis || return 1
  local tz
  tz="$(remote dns01 'timedatectl show -p Timezone --value' 2>/dev/null)" || true
  [[ "$tz" == Europe/Paris ]] || { wb_avert "dns01 n'est pas en Europe/Paris avant la panne ($tz) : lab/bin/check 04 37"; return 1; }
  m04_instantane E37
  m04_essayer E37 4 "$1" || return 1
  wb_exec dns01 >/dev/null <<'EOF' || return 1
[ -f "$WB_DIR/M04-E37.tz" ] || timedatectl show -p Timezone --value >"$WB_DIR/M04-E37.tz"
timedatectl set-timezone UTC
journal "fuseau passé à UTC (ancien : $(cat "$WB_DIR/M04-E37.tz"))"
EOF
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }
panne_E37_v4() { _e37_injecter 4; }

verifier_E37() {
  local var
  var="$(_e37_variable)" || return 1
  [[ "$(remote dns01 'timedatectl show -p Timezone --value' 2>/dev/null)" == UTC ]] \
    && [[ "$(_e37_sonde "$var")" == UTC ]]
}

annuler_E37() {
  m04_restaurer E37
  wb_exec dns01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
[ -f "$WB_DIR/M04-E37.tz" ] || exit 0
if [ "$(timedatectl show -p Timezone --value)" = UTC ]; then
  timedatectl set-timezone "$(cat "$WB_DIR/M04-E37.tz")" && journal "annulation : fuseau rétabli"
else
  journal "annulation : fuseau déjà corrigé (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/M04-E37.tz"
EOF
}

resume_E37() {
  echo "dns01 est passé en UTC et y revient même quand on rejoue le rôle base, alors que le socle doit être en Europe/Paris."
}

symptome_E37() {
  wb_symptome "Ticket INC-3143 — De : Nadia Roussel" \
    "En corrélant les journaux de cette nuit, dns01 a deux heures de décalage avec le reste" \
    "du socle : il est en UTC, les autres en Europe/Paris. Lucas dit qu'il a « juste rejoué le" \
    "rôle base » sur dns01 hier, et que le rôle force pourtant Europe/Paris. Remets dns01 à" \
    "l'heure de Paris DE FAÇON DURABLE (un nouveau passage du rôle ne doit pas le casser)," \
    "et explique-moi d'où vient cette valeur. ⚠️ Avant de rejouer quoi que ce soit, regarde ce" \
    "que le rôle ferait sur les AUTRES machines." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 04 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E37 4 "$@"; }
fi

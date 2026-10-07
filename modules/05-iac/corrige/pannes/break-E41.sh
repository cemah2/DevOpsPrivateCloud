# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M05-E41 « Panne : le plan est cassé du jour au lendemain »
#
# Aucun commit dans plateforme/infra depuis la veille, et pourtant « tofu plan » échoue sur adm01
# (et, selon la variante, dans le pipeline). Le ticket cite quatre événements de la veille : un seul
# est en cause. Variantes (une variante sans effet sur ce lab est défaite et la suivante essayée) :
#   1. pve01 : l'image dorée Debian « current » perd son étiquette current (publication d'image
#      interrompue entre « retirer l'ancienne » et « poser la nouvelle ») : la source de données
#      ne trouve plus d'image, le plan échoue partout (adm01 ET CI) ;
#   2. copie de travail : socle/.terraform.lock.hcl réécrit avec des empreintes d'une autre
#      plateforme (« Lucas a régénéré le lock depuis son Mac ») : le paquet du provider installé ne
#      correspond plus à aucune empreinte enregistrée ;
#   3. socle/.terraform/providers : le binaire du provider bpg/proxmox est tronqué (« nettoyage »
#      d'un disque plein) : mêmes erreurs de cohérence de paquet, mais git status est propre ;
#   4. ~/.config/workbook/tofu-chiffrement.pass contient une NOUVELLE phrase (rotation commencée et
#      pas terminée) : l'état, chiffré avec l'ancienne, n'est plus déchiffrable depuis adm01 (la CI,
#      qui a encore l'ancienne phrase, fonctionne).
# Sauvegardes : ~/.local/state/workbook/M05-E41/. Annulation : seulement ce qui est encore dans
# l'état posé par la panne ; en v4, l'ancienne phrase n'est remise que si l'état n'est toujours pas
# déchiffrable avec la nouvelle (si l'apprenant a terminé la rotation, la nouvelle phrase reste).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E41_LOCK="$_M05_SOCLE/.terraform.lock.hcl"
_E41_PASS="$_M05_CFG/tofu-chiffrement.pass"

_e41_plan_casse() {
  ! m05_tofu "$1" plan -lock=false -refresh=false -no-color -input=false >/dev/null 2>&1
}

_e41_binaire() {
  find "$_M05_SOCLE/.terraform/providers" -type f -path '*bpg/proxmox*' -name 'terraform-provider-proxmox*' 2>/dev/null | head -n 1
}

_e41_v1() {
  local cur t
  cur="$(m05_tpl_current)"
  [[ "$(wc -l <<<"$cur")" -eq 1 && -n "$cur" ]] || return 10
  t="$(m05_tags_lire "$cur")"
  printf '%s\t%s\n' "$cur" "$t" >"$(m05_etat E41)/tags-avant"
  m05_tags_ecrire "$cur" "$(tr ';' '\n' <<<"$t" | grep -vx current | paste -sd ';' -)" || return 1
  printf '%s\t%s\n' "$cur" "$(m05_tags_lire "$cur")" >"$(m05_etat E41)/tags-injecte"
  m05_journal E41 "étiquette current retirée de $cur"
  if _e41_plan_casse "$_M05_SOCLE" || _e41_plan_casse "$_M05_ENVS"; then return 0; fi
  return 10
}

_e41_v1_annuler() {
  local d id avant injecte actuel
  d="$(m05_etat E41)"
  [[ -f "$d/tags-avant" ]] || return 0
  IFS=$'\t' read -r id avant <"$d/tags-avant"
  injecte="$(cut -f2 "$d/tags-injecte" 2>/dev/null || true)"
  actuel="$(m05_tags_lire "$id" || true)"
  if [[ -n "$(m05_tpl_current)" ]]; then
    m05_journal E41 "annulation : une image porte de nouveau current, étiquettes laissées telles quelles"
  elif [[ -n "$injecte" && "$actuel" != "$injecte" ]]; then
    m05_journal E41 "annulation : étiquettes de $id modifiées depuis l'injection, laissées telles quelles"
  else
    m05_tags_ecrire "$id" "$avant" || wb_avert "étiquettes de $id à rétablir à la main : $avant"
  fi
  rm -f -- "$d/tags-avant" "$d/tags-injecte"
}

_e41_v2() {
  [[ -f "$_E41_LOCK" ]] || return 10
  grep -q 'bpg/proxmox' "$_E41_LOCK" || return 10
  m05_sauver E41 "$_E41_LOCK" || return 1
  python3 - "$_E41_LOCK" <<'PY' || return 1
import base64, os, re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
def faux():
    return '"h1:' + base64.b64encode(os.urandom(32)).decode() + '"'
bloc = re.compile(r'(provider\s+"[^"]*bpg/proxmox"\s*\{.*?hashes\s*=\s*\[)(.*?)(\])', re.S)
m = bloc.search(s)
if not m:
    sys.exit(1)
neuf = "\n    " + ",\n    ".join([faux(), faux()]) + ",\n  "
s = s[:m.start(2)] + neuf + s[m.end(2):]
open(p, "w", encoding="utf-8").write(s)
PY
  m05_noter E41 "$_E41_LOCK"
  m05_journal E41 "$_E41_LOCK : empreintes de bpg/proxmox remplacées"
  if m05_tofu "$_M05_SOCLE" validate -no-color >/dev/null 2>&1; then return 10; fi
}

_e41_v3() {
  local b
  b="$(_e41_binaire)"
  [[ -n "$b" ]] || return 10
  m05_sauver E41 "$b" || return 1
  truncate -s 1M "$b" || return 1
  m05_noter E41 "$b"
  m05_journal E41 "$b tronqué à 1 Mio"
  if m05_tofu "$_M05_SOCLE" validate -no-color >/dev/null 2>&1; then return 10; fi
}

_e41_v4() {
  local out
  [[ -f "$_E41_PASS" ]] || return 10
  m05_sauver E41 "$_E41_PASS" || return 1
  # Même forme que la phrase d'origine (openssl rand -hex 32, M05-E27) : 64 caractères
  # hexadécimaux, acceptés par outils/ci-preparer.sh si l'apprenant la reporte en variable CI.
  (umask 077 && head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$_E41_PASS") || return 1
  chmod 600 "$_E41_PASS"
  m05_noter E41 "$_E41_PASS"
  m05_journal E41 "$_E41_PASS : nouvelle phrase (rotation non terminée)"
  out="$(m05_tofu "$_M05_ENVS" state list 2>&1)" && return 10
  grep -qi 'decrypt' <<<"$out" || return 10
}

_m05E41_une() {
  local n="$1" rc=0
  case "$n" in
    1) _e41_v1 || rc=$? ;;
    2) _e41_v2 || rc=$? ;;
    3) _e41_v3 || rc=$? ;;
    4) _e41_v4 || rc=$? ;;
  esac
  if ((rc != 0)); then
    annuler_E41
    return "$rc"
  fi
}

panne_E41_v1() { m05_prerequis socle envs && m05_essayer E41 4 1; }
panne_E41_v2() { m05_prerequis socle envs && m05_essayer E41 4 2; }
panne_E41_v3() { m05_prerequis socle envs && m05_essayer E41 4 3; }
panne_E41_v4() { m05_prerequis socle envs && m05_essayer E41 4 4; }

verifier_E41() {
  local b
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) [[ -z "$(m05_tpl_current)" ]] ;;
    2) ! m05_fichier_modifie E41 "$_E41_LOCK" ;;
    3) b="$(_e41_binaire)"; [[ -n "$b" ]] && [[ "$(stat -c %s "$b")" -eq 1048576 ]] ;;
    4) ! m05_fichier_modifie E41 "$_E41_PASS" && ! m05_tofu "$_M05_ENVS" state list >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_E41() {
  _e41_v1_annuler || true
  # v4 : si l'apprenant a terminé la rotation (état lisible avec la nouvelle phrase), on la garde.
  if [[ -f "$(m05_etat E41)/manifeste" ]] && grep -q "^$_E41_PASS"$'\t' "$(m05_etat E41)/manifeste" \
    && ! m05_fichier_modifie E41 "$_E41_PASS" \
    && m05_tofu "$_M05_ENVS" state list >/dev/null 2>&1; then
    m05_journal E41 "annulation : l'état se déchiffre avec la nouvelle phrase (rotation terminée), phrase conservée"
    awk -F'\t' -v p="$_E41_PASS" '$1 != p' "$(m05_etat E41)/manifeste" >"$(m05_etat E41)/manifeste.tmp" || true
    mv -f -- "$(m05_etat E41)/manifeste.tmp" "$(m05_etat E41)/manifeste" || true
  fi
  m05_restaurer E41 || true
  rm -f -- "$(m05_etat E41)/variante"
}

resume_E41() {
  echo "Sans aucun commit depuis hier, « tofu plan » échoue sur adm01 (et peut-être en CI) avant de proposer quoi que ce soit."
}

symptome_E41() {
  wb_symptome "Ticket INC-3244 — De : Karim Benali" \
    "Ce matin, « tofu plan » échoue sur adm01 dans ~/src/infra (au moins dans socle ou dans" \
    "envs/lab-m05) avant même d'afficher un plan. Aucun commit dans plateforme/infra depuis hier." \
    "Ce qui s'est passé hier, d'après le canal #plateforme :" \
    "  - le pipeline de plateforme/images a publié (ou tenté de publier) une nouvelle image dorée ;" \
    "  - Lucas a « fait de la place » sur adm01 et préparé la mise à jour des providers ;" \
    "  - Sophie a commencé la rotation trimestrielle des secrets (nouvelles valeurs déposées sur" \
    "    adm01, la suite est prévue aujourd'hui) ;" \
    "  - les mises à jour de sécurité de la nuit sont passées sur adm01 et runner01." \
    "Trouve lequel de ces événements nous casse (et pourquoi les autres sont hors de cause)," \
    "répare sans régénérer à l'aveugle ce que tu ne comprends pas, et vérifie aussi le pipeline." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 05 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E41 4 "$@"; }
fi

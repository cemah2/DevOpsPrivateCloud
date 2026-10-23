# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f7-capstone.sh — fonctions partagées par les vérifications du final F7 (capstone). Sourcé par les
# checks, jamais lancé seul. Préfixe _f7c_ (évite les collisions si un check charge plusieurs fichiers
# de fonctions, par exemple ceux du F4 ou du F5).
#
# Lecture seule : GitLab en GET (jeton des checks, gitlab_api de lab/lib/check-lib.sh) ; lecture locale
# des ressources du final (cahier des charges) dans le dépôt du workbook.
#
# Variables de lab/lab.env (toutes facultatives, défauts adaptés au lab) :
#   WB_F7_DOC               dossier de la documentation du capstone (défaut docs/capstone)
#   WB_F7_PROJET_DOC        projet de la documentation (défaut plateforme/medisphere)
#   WB_F7_MIN_QUESTIONS     S01 : nombre minimal de questions Q-nn (défaut 10)
#   WB_F7_MIN_EXIGENCES     S02 : nombre minimal d'exigences NF-nn (défaut 15)
#   WB_F7_TRACABILITE_MIN   S02 : part minimale des exigences ENF/ESC du CDC reprises (défaut 0.8)
#   WB_F7_MIN_ADR           S04 : nombre minimal d'ADR-037x (défaut 4)
#   WB_F7_MIN_RISQUES       S06 : nombre minimal de risques RSQ-nn (défaut 10)
#
# ---------------------------------------------------------------------------------------------------
# FONCTIONS (à utiliser depuis un check, en général dans check_cmd / check_output)
# ---------------------------------------------------------------------------------------------------
# Lecture de GitLab :
#   _f7c_fichier PROJET CHEMIN [RÉF=main]     contenu brut du fichier (code ≠ 0 s'il manque)
#   _f7c_arbre PROJET [DOSSIER] [RÉF=main]    chemins des fichiers sous DOSSIER (récursif, 1 000 au plus)
#   _f7c_charger NOM…                         lit les documents docs/capstone/NOM une fois (cache), en tête
#                                             du check
#   _f7c_doc NOM                              contenu de docs/capstone/NOM sur main (cache, sinon GitLab)
#   _f7c_doc_present NOM                      le document existe sur main et n'est pas vide
#   _f7c_doc_contient NOM REGEX…              le document contient chaque motif (ERE, casse ignorée)
#   _f7c_doc_sections NOM REGEX…              le document a, pour chaque motif, un titre Markdown
#                                             (« # … » à « ###### … ») qui lui correspond
#   _f7c_docs_dossier SOUS-DOSSIER MOTIF_NOM  chemins (relatifs au dépôt) des documents de
#                                             docs/capstone/SOUS-DOSSIER dont le NOM correspond au motif
# Comptages (sur un texte passé en argument ou sur un document) :
#   _f7c_ids TEXTE REGEX                      identifiants distincts correspondant à REGEX, un par ligne
#   _f7c_nb_ids TEXTE REGEX                   nombre de ces identifiants distincts
#   _f7c_doc_nb_ids_min NOM REGEX MIN         le document contient au moins MIN identifiants distincts
#   _f7c_lignes_liees TEXTE REGEX_ID REGEX_REF  sur les lignes qui contiennent un identifiant REGEX_ID,
#                                             affiche « liées/total » (une ligne est « liée » si elle
#                                             contient aussi REGEX_REF ; tableaux Markdown : une ligne =
#                                             une exigence)
#   _f7c_part_liees_min TEXTE REGEX_ID REGEX_REF PART  au moins PART (0 à 1) des identifiants REGEX_ID
#                                             apparaissent sur une ligne qui contient REGEX_REF
# Cahier des charges (fichier local du workbook) :
#   _f7c_cdc_ids PREFIXE                      identifiants du CDC de ce préfixe (ENF, ESC, EF…), un par ligne
#   _f7c_part_cdc_citee TEXTE PREFIXE…        affiche la part (0 à 1) des exigences du CDC de ces préfixes
#                                             citées dans TEXTE
# Tableur :
#   _f7c_csv_valide TEXTE                     CSV à séparateur virgule ou point-virgule, même nombre de
#                                             champs sur chaque ligne non vide (hors champs entre guillemets)
#   _f7c_csv_colonnes TEXTE COLONNE…          l'en-tête contient chaque colonne (casse ignorée)
# Exemple (check d'un RED publié) :
#   source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"
#   check_cmd "analyse-cdc.md présent sur main" _f7c_doc_present analyse-cdc.md
#   check_cmd "analyse : au moins 15 exigences du CDC citées" _f7c_doc_nb_ids_min analyse-cdc.md \
#     "$_F7C_RE_CDC" 15
# ---------------------------------------------------------------------------------------------------

_f7c_doc_dir="${WB_F7_DOC:-docs/capstone}"
_f7c_projet_doc="${WB_F7_PROJET_DOC:-plateforme/medisphere}"
_f7c_min_questions="${WB_F7_MIN_QUESTIONS:-10}"
_f7c_min_exigences="${WB_F7_MIN_EXIGENCES:-15}"
_f7c_tracabilite_min="${WB_F7_TRACABILITE_MIN:-0.8}"
_f7c_min_adr="${WB_F7_MIN_ADR:-4}"
_f7c_min_risques="${WB_F7_MIN_RISQUES:-10}"

# Ressources du final (dépôt du workbook, lu localement).
_f7c_ressources="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ressources" 2>/dev/null && pwd)"
_f7c_cdc="${_f7c_ressources:-.}/S01/cahier-des-charges.md"

# Identifiants (ERE). Bornes de mot explicites : « ENF-03 » ne doit pas compter dans « NF-03 ».
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
_F7C_RE_CDC='(^|[^A-Za-z])(EF|ENF|ESC|ERV|EXP|MES)-[0-9]{2}'
# shellcheck disable=SC2034
_F7C_RE_NF='(^|[^A-Za-z])NF-[0-9]{2}'
# Risques du registre (S06) : RSQ-nn. « R-nn » désigne les réponses du GHSV aux candidats (S02).
# shellcheck disable=SC2034
_F7C_RE_RSQ='(^|[^A-Za-z])RSQ-[0-9]{2}'

# --- GitLab (lecture) ------------------------------------------------------------------------------

_f7c_enc() { jq -rn --arg s "$1" '$s|@uri'; }

_f7c_fichier() {
  gitlab_api "projects/$(_f7c_enc "$1")/repository/files/$(_f7c_enc "$2")/raw?ref=$(_f7c_enc "${3:-main}")"
}

_f7c_arbre() {
  local p page=1 r ref
  p="$(_f7c_enc "$1")"
  ref="$(_f7c_enc "${3:-main}")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${2:+&path=$(_f7c_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r" 2>/dev/null
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# Cache des documents lus (un check relit souvent le même document pour plusieurs contrôles). Le cache
# n'est rempli que par _f7c_charger, appelé dans le shell du check (une substitution « $(…) » tourne
# dans un sous-shell et ne peut pas le remplir) ; _f7c_doc lit le cache, sinon GitLab.
declare -A _F7C_CACHE=()

_f7c_lire_gitlab() {
  local c
  c="$(_f7c_fichier "$_f7c_projet_doc" "$_f7c_doc_dir/$1" 2>/dev/null)" || c=""
  # Une réponse d'erreur de l'API (JSON {"message": …}) n'est pas un document.
  [[ "$c" =~ ^\{\"(message|error)\" ]] && c=""
  printf '%s' "$c"
}

# _f7c_charger NOM… — lit les documents une fois et les garde en cache (à appeler en tête du check).
_f7c_charger() {
  local nom
  for nom in "$@"; do _F7C_CACHE[$nom]="$(_f7c_lire_gitlab "$nom")"; done
}

_f7c_doc() {
  if [[ -n "${_F7C_CACHE[$1]+x}" ]]; then
    printf '%s' "${_F7C_CACHE[$1]}"
  else
    _f7c_lire_gitlab "$1"
  fi
}

_f7c_doc_present() {
  local c
  c="$(_f7c_doc "$1")"
  [[ -n "${c//[[:space:]]/}" ]]
}

_f7c_doc_contient() {
  local c m nom="$1"
  shift
  c="$(_f7c_doc "$nom")"
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

_f7c_doc_sections() {
  local c m nom="$1"
  shift
  c="$(_f7c_doc "$nom")"
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "^#{1,6}[[:space:]].*($m)" <<<"$c" || return 1; done
}

_f7c_docs_dossier() {
  local d="$_f7c_doc_dir/$1" motif="$2" f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] && printf '%s\n' "$f"
  done < <(_f7c_arbre "$_f7c_projet_doc" "$d")
}

# --- Comptages -------------------------------------------------------------------------------------

# Les motifs commencent par une borne « (^|[^A-Za-z]) » : on retire le caractère de tête capturé.
_f7c_ids() {
  grep -Eo -- "$2" <<<"$1" 2>/dev/null | sed -E 's/^[^A-Za-z]//' | sort -u
}

_f7c_nb_ids() {
  local n
  n="$(_f7c_ids "$1" "$2" | grep -c . || true)"
  printf '%s\n' "${n:-0}"
}

_f7c_doc_nb_ids_min() {
  local c
  c="$(_f7c_doc "$1")"
  [[ -n "$c" ]] || return 1
  (($(_f7c_nb_ids "$c" "$2") >= $3))
}

_f7c_lignes_liees() {
  local total liees
  total="$(grep -Ec -- "$2" <<<"$1" || true)"
  liees="$(grep -E -- "$2" <<<"$1" | grep -Ec -- "$3" || true)"
  printf '%s/%s\n' "${liees:-0}" "${total:-0}"
}

# Part des identifiants REGEX_ID (distincts) dont au moins une ligne porte aussi REGEX_REF.
_f7c_part_liees_min() {
  local texte="$1" re_id="$2" re_ref="$3" part="$4" total ok id
  total=0
  ok=0
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    total=$((total + 1))
    if grep -E -- "(^|[^A-Za-z])${id}([^0-9]|$)" <<<"$texte" | grep -Eq -- "$re_ref"; then
      ok=$((ok + 1))
    fi
  done < <(_f7c_ids "$texte" "$re_id")
  ((total > 0)) || return 1
  awk -v o="$ok" -v t="$total" -v p="$part" 'BEGIN { exit !(o / t >= p) }'
}

# --- Cahier des charges ------------------------------------------------------------------------------

_f7c_cdc_ids() {
  [[ -r "$_f7c_cdc" ]] || return 1
  grep -Eo -- "\*\*$1-[0-9]{2} " "$_f7c_cdc" | tr -d '* ' | sort -u
}

_f7c_part_cdc_citee() {
  local texte="$1" total=0 cites=0 id p
  shift
  for p in "$@"; do
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      total=$((total + 1))
      grep -Eq -- "(^|[^A-Za-z])${id}([^0-9]|$)" <<<"$texte" && cites=$((cites + 1))
    done < <(_f7c_cdc_ids "$p")
  done
  ((total > 0)) || { echo 0; return 1; }
  awk -v c="$cites" -v t="$total" 'BEGIN { printf "%.2f\n", c / t }'
}

# --- Tableur -----------------------------------------------------------------------------------------

_f7c_csv_sep() {
  local entete
  entete="$(head -n 1 <<<"$1")"
  if [[ "$entete" == *";"* ]]; then printf ';'; else printf ','; fi
}

_f7c_csv_valide() {
  local sep
  [[ -n "$1" ]] || return 1
  sep="$(_f7c_csv_sep "$1")"
  # Retire les champs entre guillemets (qui peuvent contenir le séparateur), compte les champs.
  sed -E 's/"([^"]|"")*"/X/g' <<<"$1" | awk -F"$sep" 'NF > 0 && $0 !~ /^[[:space:]]*$/ { n[NF]++ } END { c = 0; for (k in n) c++; exit !(c == 1) }'
}

_f7c_csv_colonnes() {
  local entete c texte="$1"
  shift
  entete="$(head -n 1 <<<"$texte" | tr '[:upper:]' '[:lower:]' | tr -d '"\r')"
  for c in "$@"; do
    grep -Eq -- "(^|[,;])[[:space:]]*${c}[[:space:]]*([,;]|$)" <<<"$entete" || return 1
  done
}

# _f7c_csv_valeurs TEXTE COLONNE — valeurs (sans guillemets) d'une colonne, une par ligne (hors en-tête).
_f7c_csv_valeurs() {
  local sep
  sep="$(_f7c_csv_sep "$1")"
  sed -E 's/"([^"]|"")*"/X/g' <<<"$1" | awk -F"$sep" -v col="$2" '
    NR == 1 { for (i = 1; i <= NF; i++) { h = tolower($i); gsub(/[[:space:]\r]/, "", h); if (h == col) k = i } next }
    k && NF > 1 { v = $k; gsub(/[[:space:]\r]/, "", v); print v }'
}

# --- Sections et contrat d'interface -----------------------------------------------------------------

# _f7c_section TEXTE REGEX — texte de la première section dont le titre correspond à REGEX (casse
# ignorée), jusqu'au titre suivant de niveau supérieur ou égal (sous-sections comprises).
_f7c_section() {
  awk -v re="$2" '
    BEGIN { re = tolower(re) }
    /^#{1,6}[[:space:]]/ {
      n = match($0, /^#+/); niv = RLENGTH
      if (dedans && niv <= niveau) exit
      if (!dedans && tolower($0) ~ re) { dedans = 1; niveau = niv }
    }
    dedans { print }' <<<"$1"
}

# _f7c_section_contient NOM REGEX_TITRE REGEX… — la section du document contient chaque motif.
_f7c_section_contient() {
  local s m nom="$1" titre="$2"
  shift 2
  s="$(_f7c_section "$(_f7c_doc "$nom")" "$titre")"
  [[ -n "$s" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$s" || return 1; done
}

# _f7c_operation_ids — operationId de l'annexe A1 (ressources/S01/api-rendez-vous-v1.yaml), un par ligne.
_f7c_operation_ids() {
  local f="${_f7c_ressources:-.}/S01/api-rendez-vous-v1.yaml"
  [[ -r "$f" ]] || return 1
  sed -nE 's/^[[:space:]]*operationId:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$f" | sort -u
}

# _f7c_doc_cite_operations NOM — le document cite chaque operationId de l'annexe A1.
_f7c_doc_cite_operations() {
  local c o n=0
  c="$(_f7c_doc "$1")"
  [[ -n "$c" ]] || return 1
  while IFS= read -r o; do
    [[ -n "$o" ]] || continue
    n=$((n + 1))
    grep -Fq -- "$o" <<<"$c" || return 1
  done < <(_f7c_operation_ids)
  ((n > 0))
}

# _f7c_max_nombre_avant TEXTE REGEX_UNITÉ — plus grand nombre (entier ou décimal à virgule ou point,
# espaces de milliers acceptés) immédiatement suivi de l'unité (ex. « req/s »). Affiche 0 si aucun.
_f7c_max_nombre_avant() {
  grep -Eoi -- "[0-9][0-9  ]*([,.][0-9]+)?[[:space:]]*($2)" <<<"$1" 2>/dev/null |
    sed -E 's/[^0-9,.]//g; s/,/./g' | awk 'BEGIN { m = 0 } { v = $0 + 0; if (v > m) m = v } END { print m }'
}

# _f7c_csv_totaux_ok TEXTE — sur chaque ligne de données, total_5_ans = annee_1 + … + annee_5 (écart ≤ 1).
_f7c_csv_totaux_ok() {
  local sep
  sep="$(_f7c_csv_sep "$1")"
  sed -E 's/"([^"]|"")*"/X/g' <<<"$1" | awk -F"$sep" '
    function num(v) { gsub(/[[:space:]\r]/, "", v); gsub(/,/, ".", v); return v + 0 }
    NR == 1 {
      for (i = 1; i <= NF; i++) { h = tolower($i); gsub(/[[:space:]\r"]/, "", h); c[h] = i }
      if (!("total_5_ans" in c)) exit 1
      for (a = 1; a <= 5; a++) if (!(("annee_" a) in c)) exit 1
      next
    }
    NF > 1 {
      n++; s = 0
      for (a = 1; a <= 5; a++) s += num($(c["annee_" a]))
      d = s - num($(c["total_5_ans"])); if (d < 0) d = -d
      if (d > 1) bad++
    }
    END { exit !(n > 0 && bad == 0) }'
}

# _f7c_csv_nb_distinct TEXTE COLONNE — nombre de valeurs distinctes non vides d'une colonne.
_f7c_csv_nb_distinct() {
  _f7c_csv_valeurs "$1" "$2" | grep -v '^$' | sort -u | grep -c . || true
}

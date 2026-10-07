# shellcheck shell=bash
# _m02-reparations.sh — aide commune aux pannes du module 02 qui posent ou remplacent des
# fichiers (break-E35, break-E36, break-E41, break-E42). Sourcé par ces scripts, jamais lancé.
#
# Règle : « lab/bin/break 02 XX --annuler » sert aussi à CLORE une panne que l'apprenant a
# réparée ; l'annulation ne doit jamais écraser sa réparation. Chaque fichier posé par la panne
# est donc noté avec son empreinte au moment de l'injection (noter_injecte) ; à l'annulation,
# garder_reparations retire du manifeste de sauvegarde (cf. sauver/restaurer_fichiers de
# lab/lib/pannes-lib.sh) tout fichier qui n'est plus celui que la panne a posé : restaurer_fichiers
# ne touche alors qu'aux fichiers encore dans l'état cassé.

# Fonctions exécutées sur l'hôte ciblé, ajoutées au script distant après le prélude de wb_exec.
read -r -d '' _M02_AIDE_DISTANTE <<'AIDE' || true
# empreinte CHEMIN — « lien:<cible> », « sha256:<somme> » ou « absent »
empreinte() {
  if [ -L "$1" ]; then
    printf 'lien:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'sha256:%s\n' "$(sha256sum <"$1" | cut -d' ' -f1)"
  else
    printf 'absent\n'
  fi
}

# noter_injecte CHEMIN — mémorise l'état du fichier tel que la panne vient de le poser.
noter_injecte() {
  printf '%s\t%s\n' "$1" "$(empreinte "$1")" >>"$WB_DIR/$WB_EX.injecte"
}

# oublier_injecte — la panne n'a pas pris (variante sans effet) : rien à protéger.
oublier_injecte() {
  rm -f -- "$WB_DIR/$WB_EX.injecte"
}

# garder_reparations — avant restaurer_fichiers : un fichier modifié (ou remplacé) depuis
# l'injection est une réparation de l'apprenant ; il sort du manifeste et reste tel quel.
garder_reparations() {
  local m="$WB_DIR/$WB_EX.manifeste" e="$WB_DIR/$WB_EX.injecte" t src dst attendu
  [ -f "$e" ] || return 0
  if [ -f "$m" ]; then
    t="$(mktemp)"
    while IFS="$(printf '\t')" read -r src dst; do
      attendu="$(awk -F'\t' -v s="$src" '$1 == s { v = $2 } END { print v }' "$e")"
      if [ -n "$attendu" ] && { [ -e "$src" ] || [ -L "$src" ]; } \
        && [ "$(empreinte "$src")" != "$attendu" ]; then
        journal "annulation : $src modifié depuis l'injection (réparation), laissé tel quel"
        if [ "$dst" != ABSENT ]; then rm -f -- "$dst"; fi
        continue
      fi
      printf '%s\t%s\n' "$src" "$dst" >>"$t"
    done <"$m"
    cat "$t" >"$m"
    rm -f -- "$t"
  fi
  rm -f -- "$e"
}
AIDE

# _m02_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec, avec les fonctions ci-dessus.
_m02_wb_exec() {
  { printf '%s\n' "$_M02_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M12-E39 « Panne : le disque de l'hôte est plein »
#
# Hôte : ctr01 (système de fichiers racine, qui porte /var/lib/docker et /var/lib/containerd).
# Le remplissage s'arrête quand l'espace disponible pour un utilisateur non privilégié est épuisé
# (il reste la réserve de root d'ext4 : dockerd et sudo fonctionnent encore, PostgreSQL — UID 999 —
# n'écrit plus). Variantes :
#   1. journaux : conteneur « trace-lucas » (débogage oublié) lancé avec --log-opt max-size=100g ;
#      son journal json-file grossit jusqu'à remplir le disque (lignes JSON valides, écrites en bloc) ;
#   2. images et cache : des constructions répétées d'une image d'essai (« lucas/import-essai »,
#      couche de données préallouée) laissent des images orphelines (<none>) et du cache de
#      construction ;
#   3. volume : un volume nommé « recette_exports » (étiquettes Compose du projet recette) rempli
#      d'exports quotidiens jamais purgés, monté par un conteneur arrêté « recette-exports-lucas ».
# Rien n'est écrit dans les volumes ou images de l'apprenant ; seuls les objets créés par la panne
# sont supprimés à l'annulation (étiquette wb.panne=M12-E39).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_mE39_une() {
  [[ -n "${_M12_ASTREINTE:-}" ]] || m12_recette_preparer || return 1
  echo "Remplissage du disque de $_M12_CTR01 (une à trois minutes)…" >&2
  m12_exec "$_M12_CTR01" VAR="$1" <<'EOF'
# libre_ : octets disponibles pour un utilisateur non privilégié sur /
libre_() { df --output=avail -B1 / | tail -n 1 | tr -d ' '; }
marge=$((48 * 1024 * 1024))
[ "$(libre_)" -gt $((2 * 1024 * 1024 * 1024)) ] || exit 10
IMG=recette/mediagenda-api:plateau
case "$VAR" in
  1)
    docker run -d --name trace-lucas --label wb.panne=M12-E39 --restart unless-stopped \
      --log-driver json-file --log-opt max-size=100g --entrypoint sh "$IMG" \
      -c 'while :; do echo "trace $(date -Is) requete=GET /api/v1/creneaux statut=200"; sleep 1; done' >/dev/null || exit 1
    lp="$(docker inspect -f '{{.LogPath}}' trace-lucas)"
    [ -n "$lp" ] || exit 1
    python3 - "$lp" "$marge" <<'PY' || true
import os, sys, datetime
chemin, marge = sys.argv[1], int(sys.argv[2])
horo = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000000000Z")
ligne = ('{"log":"trace %s requete=GET /api/v1/creneaux?date=2026-10-08 praticien=dr-morel statut=200 duree_ms=12 %s\\n","stream":"stdout","time":"%s"}\n'
         % (horo, "x" * 200, horo)).encode()
bloc = ligne * (8 * 1024 * 1024 // len(ligne))
with open(chemin, "ab", buffering=0) as f:
    while True:
        st = os.statvfs("/")
        if st.f_bavail * st.f_frsize <= marge:
            break
        try:
            f.write(bloc)
        except OSError:
            break
PY
    journal "conteneur trace-lucas, journal sans rotation : disque rempli"
    ;;
  2)
    d="$(mktemp -d)"
    cat > "$d/Dockerfile" <<'DF'
FROM debian:trixie-slim
ARG ESSAI=0
ARG TAILLE=1G
LABEL wb.panne=M12-E39
RUN fallocate -l "$TAILLE" "/var/tmp/jeu-import-$ESSAI.bin"
DF
    docker pull -q debian:trixie-slim >/dev/null 2>&1 || true
    # Taille de chaque essai ajustée à la consommation mesurée (couche + image dépaquetée).
    python3 - "$d" "$marge" <<'PY' || true
import os, subprocess, sys
rep, marge = sys.argv[1], int(sys.argv[2])
def libre():
    st = os.statvfs("/")
    return st.f_bavail * st.f_frsize
def construire(essai, taille):
    return subprocess.run(["docker", "build", "-q", "--build-arg", f"ESSAI={essai}", "--build-arg",
                           f"TAILLE={taille}", "-t", "lucas/import-essai:latest", rep],
                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode
facteur = 2.0
for essai in range(1, 10):
    l = libre()
    if l <= 4 * marge:
        break
    taille = min(int((l - marge) / facteur * 0.95), 6 * 1024**3)
    if taille < 32 * 1024**2:
        break
    if construire(essai, taille) != 0:
        break
    consomme = l - libre()
    if consomme > 0:
        facteur = max(1.0, consomme / taille)
PY
    rm -rf "$d"
    journal "constructions répétées de lucas/import-essai : images orphelines et cache"
    ;;
  3)
    docker volume create --label wb.panne=M12-E39 --label com.docker.compose.project=recette \
      --label com.docker.compose.volume=exports recette_exports >/dev/null || exit 1
    docker create --name recette-exports-lucas --label wb.panne=M12-E39 -v recette_exports:/exports \
      --entrypoint sh "$IMG" -c 'pg_dump > /exports/export.sql' >/dev/null || exit 1
    m="$(docker volume inspect -f '{{.Mountpoint}}' recette_exports)"
    n=1
    while [ "$n" -le 60 ]; do
      l="$(libre_)"
      [ "$l" -le "$marge" ] && break
      t=$((l - marge))
      [ "$t" -gt $((3 * 1024 * 1024 * 1024)) ] && t=$((3 * 1024 * 1024 * 1024))
      f="$m/export-mediagenda-$(date -d "-$n days" +%F).sql"
      fallocate -l "$t" "$f" || break
      touch -d "-$n days" "$f"
      n=$((n + 1))
    done
    journal "volume recette_exports rempli d'exports non purgés"
    ;;
esac
exit 0
EOF
}

_e39_plein() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1
[ "$(df --output=avail -B1 / | tail -n 1 | tr -d ' ')" -lt $((256 * 1024 * 1024)) ]
EOF
}

panne_E39_v1() { m12_essayer E39 3 1; }
panne_E39_v2() { m12_essayer E39 3 2; }
panne_E39_v3() { m12_essayer E39 3 3; }

verifier_E39() { _e39_plein; }

annuler_E39() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
docker rm -f trace-lucas recette-exports-lucas >/dev/null 2>&1 || true
docker volume rm recette_exports >/dev/null 2>&1 || true
docker image rm lucas/import-essai:latest >/dev/null 2>&1 || true
docker image ls -q --filter label=wb.panne=M12-E39 | xargs -r docker image rm -f >/dev/null 2>&1 || true
docker builder prune -af >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX".*
journal "annulation : objets wb.panne=M12-E39 supprimés"
EOF
  m12_recette_reinitialiser
  m12_oublier E39
}

resume_E39() {
  echo "Sur ctr01, plus rien ne s'écrit : les créations de rendez-vous de la recette échouent, « No space left on device »."
}

symptome_E39() {
  wb_symptome "Ticket INC-3939 — De : Nadia Roussel" \
    "Alerte de cette nuit : le disque de ctr01 est plein. Les créations de rendez-vous de la recette" \
    "échouent, la base de recette se plaint de « No space left on device ». Lucas propose de « faire" \
    "un docker system prune -a --volumes et on n'en parle plus » : surtout pas avant d'avoir compris" \
    "ce qui a rempli le disque et ce qu'on peut supprimer sans rien perdre." \
    "" \
    "Libère de l'espace sans toucher aux données de la recette, trouve la cause, et empêche que ça" \
    "recommence. Temps cible : 30 min. Contrôle : lab/bin/check 12 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E39 3 "$@"; }
fi

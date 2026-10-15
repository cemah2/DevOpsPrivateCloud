# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2031  # filtres jq et scripts entre apostrophes ; le sous-shell du registre ne modifie rien
#
# check-E46.sh — M12-E46 « Mini-projet : conteneurs MédiSphère v1 »
# Contrôle global de la livraison conteneurs-v1, à lancer depuis adm01. Deux moments :
#   - RECETTE (ctr02, VM 2122, existe encore) : en plus du reste, les images du registre de travail
#     (non-root, multi-architecture pour MédiAgenda) et la pile de recette de ctr02 (quatre
#     applications qui répondent, conteneurs sans privilège tirés du registre de travail) ;
#   - CLÔTURE (ctr02 détruite) : les VMs d'environnement ont disparu (ctr01 peut rester si
#     WB_M12_CTR01_CONSERVE=1 dans lab/lab.env, jusqu'à la fin de M13-E03) ; les contrôles « en direct » sont
#     alors sautés, la preuve de la recette est docs/conteneurs/recette-v1.md.
# Toujours : CI des quatre applications (Hadolint, construction sur runner02), runner02 dans le socle
# (Proxmox, NetBox, DNS, PBS, supervision, sans privilège), documentation et étiquette conteneurs-v1.
# Lecture seule : qm/pvesm en lecture sur pve01, API GitLab et NetBox en GET, API du registre en GET,
# HTTP vers ctr02, podman inspect en lecture (sudo), dig. Durée : 2 à 4 minutes.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E46 — Conteneurs MédiSphère v1 : contrôle global"
require_cmd jq curl dig git python3 ssh

_m12_e46_depot="${WB_DEPOT:-$HOME/medisphere}"
_m12_e46_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_m12_e46_reg="https://$_m12x_nom01:5000"
_m12_e46_nom02="${WB_M12_CTR02_NOM:-ctr02.par1.medisphere.internal}"
_m12_e46_apps=("mediagenda/api" "medidoc/medidoc" "medinotif/worker" "legacy/legacy-rdv")

# Liste des VMID de pve01 (vide si pve01 ne répond pas : rien n'est alors déclaré « détruit »).
_m12_e46_vmids="$(remote "$WB_PVE_HOST" "qm list" 2>/dev/null | awk 'NR > 1 {print $1}' || true)"
_m12_e46_pve_ok() { [[ -n "$_m12_e46_vmids" ]]; }
_m12_e46_vm_existe() { grep -qx "$1" <<<"$_m12_e46_vmids"; }
_m12_e46_vm_absente() { _m12_e46_pve_ok && ! _m12_e46_vm_existe "$1"; }
_m12_e46_enc() { jq -rn --arg s "$1" '$s | @uri'; }

if ! _m12_e46_pve_ok; then
  _m12_e46_phase=inconnue
elif _m12_e46_vm_existe 2122; then
  _m12_e46_phase=recette
else
  _m12_e46_phase=cloture
fi
check_cmd "pve01 répond (qm list) : la phase recette/clôture est déterminable" _m12_e46_pve_ok
printf '  (phase constatée : %s)\n' "$_m12_e46_phase"

# --- 1. Applications et CI ------------------------------------------------------------------------
title "1/6 Les quatre applications construites en CI sans privilège"
_m12_e46_fichier_conteneur() {
  gitlab_api "projects/$(_m12_e46_enc "$1")/repository/tree?ref=main&per_page=100" \
    | jq -e '[.[] | select(.name == "Dockerfile" or .name == "Containerfile")] | length >= 1' >/dev/null
}
_m12_e46_dernier_pipeline() {
  gitlab_api "projects/$(_m12_e46_enc "$1")/pipelines?ref=main&per_page=1&order_by=id&sort=desc"
}
_m12_e46_pipeline_ok() { _m12_e46_dernier_pipeline "$1" | jq -e '.[0].status == "success"' >/dev/null; }
_m12_e46_job() {
  local p="$1" motif="$2" id
  id="$(_m12_e46_dernier_pipeline "$p" | jq -r '.[0].id')" || return 1
  [[ "$id" =~ ^[0-9]+$ ]] || return 1
  gitlab_api "projects/$(_m12_e46_enc "$p")/pipelines/$id/jobs?per_page=100" \
    | jq -e --arg m "$motif" '[.[] | select((.name | test($m; "i")) and .status == "success")] | length >= 1' >/dev/null
}
_m12_e46_job_docker() {
  local p="$1" id
  id="$(_m12_e46_dernier_pipeline "$p" | jq -r '.[0].id')" || return 1
  gitlab_api "projects/$(_m12_e46_enc "$p")/pipelines/$id/jobs?per_page=100" \
    | jq -e '[.[] | select((.name | test("image|constru|build|publi|push"; "i")) and .status == "success"
              and ((.tag_list // []) | index("docker")))] | length >= 1' >/dev/null
}
for _m12_e46_p in "${_m12_e46_apps[@]}"; do
  check_cmd "$_m12_e46_p : Dockerfile ou Containerfile sur main" _m12_e46_fichier_conteneur "$_m12_e46_p"
  check_cmd "$_m12_e46_p : dernier pipeline de main réussi" _m12_e46_pipeline_ok "$_m12_e46_p"
  check_cmd "$_m12_e46_p : job Hadolint réussi dans ce pipeline" _m12_e46_job "$_m12_e46_p" hadolint
  check_cmd "$_m12_e46_p : image construite et publiée par un job d'étiquette docker (runner02)" \
    _m12_e46_job_docker "$_m12_e46_p"
done

# --- 2. runner02 dans le socle -----------------------------------------------------------------------
title "2/6 runner02 dans le socle"
check_ssh_output "Proxmox : VM 1012 (runner02) étiquetée socle" "$WB_PVE_HOST" 'socle' 'qm config 1012 | sed -n "s/^tags: //p"'
_m12_e46_pbs() {
  local l
  l="$(remote "$WB_PVE_HOST" "pvesm list ${WB_PBS_STORAGE:-pbs-par2} --vmid 1012 2>/dev/null")" || return 1
  python3 -c '
import re, sys, datetime
t = sys.stdin.read()
d = re.findall(r"vm/1012/(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)Z", t)
if not d: sys.exit(1)
age = datetime.datetime.utcnow() - datetime.datetime.strptime(max(d), "%Y-%m-%dT%H:%M:%S")
sys.exit(0 if age.days < 8 else 1)' <<<"$l"
}
check_cmd "PBS : sauvegarde de la VM 1012 de moins de 8 jours" _m12_e46_pbs
_m12_e46_nb() {
  netbox_api "virtualization/virtual-machines/?name=runner02" \
    | jq -e '.count == 1 and (.results[0].status.value == "active") and ((.results[0].primary_ip4.address // "") | startswith("10.10.20.17/"))' >/dev/null
}
check_cmd "NetBox : runner02 actif, 10.10.20.17 en adresse primaire" _m12_e46_nb
check_dns "DNS : runner02.par1.medisphere.internal → 10.10.20.17" runner02.par1.medisphere.internal A '^10\.10\.20\.17$' 10.10.20.10
_m12_e46_runner() {
  gitlab_api "runners/all?tag_list=docker&per_page=100" \
    | jq -e '[.[] | select(.online == true or .status == "online")] | length >= 1' >/dev/null
}
check_cmd "GitLab : runner d'étiquette docker en ligne" _m12_e46_runner
check_ssh "runner02 : aucun runner en mode privilégié" "$_m12x_runner02" \
  '! sudo -n grep -Eq "^[[:space:]]*privileged[[:space:]]*=[[:space:]]*true" /etc/gitlab-runner/config.toml && sudo -n test -f /etc/gitlab-runner/config.toml'
_m12_e46_supervise() {
  gitlab_api "projects/plateforme%2Foutils/search?scope=blobs&search=runner02&ref=main" | jq -e 'length >= 1' >/dev/null
}
check_cmd "plateforme/outils : runner02 cité par la supervision (ms-verif-…)" _m12_e46_supervise
check_cmd "aucune panne M12 encore active (lab/bin/break)" _m12x_aucune_panne_active

# --- 3. Registre de travail et images ------------------------------------------------------------------
title "3/6 Images dans le registre de travail"
# _m12_e46_registre — instantané JSON (une entrée par application : dernière version, utilisateur,
#   plateformes) ; identifiants lus dans ~/.config/workbook/registre-travail.env (variables
#   REGISTRE_UTILISATEUR / REGISTRE_MOT_DE_PASSE, ou REGISTRY_USER / REGISTRY_PASSWORD).
_m12_e46_registre() {
  local f="${WB_REGISTRE_ENV:-$HOME/.config/workbook/registre-travail.env}"
  [[ -r "$f" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    python3 - "$_m12_e46_reg" "$_m12_e46_racine" "${_m12_e46_apps[@]}" <<'PY'
import base64, json, os, re, ssl, sys, urllib.request
reg, ca, apps = sys.argv[1], sys.argv[2], sys.argv[3:]
u = os.environ.get("REGISTRE_UTILISATEUR") or os.environ.get("REGISTRY_USER") or ""
p = os.environ.get("REGISTRE_MOT_DE_PASSE") or os.environ.get("REGISTRY_PASSWORD") or ""
ctx = ssl.create_default_context(cafile=ca)
auth = "Basic " + base64.b64encode(f"{u}:{p}".encode()).decode()
ACC = ", ".join(["application/vnd.oci.image.index.v1+json", "application/vnd.oci.image.manifest.v1+json",
                 "application/vnd.docker.distribution.manifest.list.v2+json",
                 "application/vnd.docker.distribution.manifest.v2+json"])
def get(chemin, accept=ACC):
    r = urllib.request.Request(reg + chemin, headers={"Authorization": auth, "Accept": accept})
    with urllib.request.urlopen(r, timeout=15, context=ctx) as x:
        return json.load(x)
def version(t):
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", t)
    return tuple(int(i) for i in m.groups()) if m else None
res = {}
for a in apps:
    e = {"tags": 0}
    try:
        tags = get(f"/v2/{a}/tags/list").get("tags") or []
        e["tags"] = len(tags)
        v = sorted((t for t in tags if version(t)), key=version)
        if v:
            e["version"] = v[-1]
            m = get(f"/v2/{a}/manifests/{v[-1]}")
            plats = []
            if "manifests" in m:
                plats = [f'{x["platform"]["os"]}/{x["platform"]["architecture"]}' for x in m["manifests"]
                         if x.get("platform") and x["platform"].get("os") != "unknown"]
                cible = next((x for x in m["manifests"] if x.get("platform", {}).get("architecture") == "amd64"), None)
                m = get(f"/v2/{a}/manifests/{cible['digest']}") if cible else {}
            e["plateformes"] = plats
            if m.get("config"):
                c = get(f"/v2/{a}/blobs/{m['config']['digest']}", "*/*")
                e["utilisateur"] = (c.get("config") or {}).get("User", "")
    except Exception as x:
        e["erreur"] = str(x)[:80]
    res[a] = e
print(json.dumps(res))
PY
  )
}
if _m12_e46_vm_existe 2121 || ! _m12_e46_pve_ok; then
  _m12_e46_img="$(_m12_e46_registre 2>/dev/null || echo '{}')"
  for _m12_e46_p in "${_m12_e46_apps[@]}"; do
    check_cmd "$_m12_e46_p : au moins une version X.Y.Z dans le registre de travail" \
      bash -c 'jq -e --arg a "$2" ".[\$a].version != null" >/dev/null <<<"$1"' _ "$_m12_e46_img" "$_m12_e46_p"
    check_cmd "$_m12_e46_p : image de cette version sans utilisateur root (USER non vide, ni 0 ni root)" \
      bash -c 'jq -e --arg a "$2" ".[\$a].utilisateur as \$u | \$u != null and \$u != \"\" and (\$u | test(\"^(0|root)(:|\$)\") | not)" >/dev/null <<<"$1"' \
      _ "$_m12_e46_img" "$_m12_e46_p"
  done
  check_cmd "mediagenda/api : index multi-architecture linux/amd64 et linux/arm64" \
    bash -c 'jq -e ".[\"mediagenda/api\"].plateformes | (index(\"linux/amd64\") != null) and (index(\"linux/arm64\") != null)" >/dev/null <<<"$1"' _ "$_m12_e46_img"
else
  skip "images du registre de travail" "ctr01 (2121) détruite : registre de travail retiré (Harbor au M13)"
fi

# --- 4. Pile de recette de ctr02 -------------------------------------------------------------------------
title "4/6 Pile de recette sur ctr02"
if [[ "$_m12_e46_phase" == recette ]]; then
  check_http "MédiAgenda : http://$_m12_e46_nom02:8000/pret → 200" "http://$_m12_e46_nom02:8000/pret" 200
  check_http "MédiDoc : http://$_m12_e46_nom02:8080/readyz → 200 (S3 joint)" "http://$_m12_e46_nom02:8080/readyz" 200
  check_http "Legacy-RDV : http://$_m12_e46_nom02:8081/ → 200" "http://$_m12_e46_nom02:8081/" 200
  check_http "MédiNotif : http://$_m12_e46_nom02:9100/metrics → 200" "http://$_m12_e46_nom02:9100/metrics" 200
  _m12_e46_pods="$(_m12x_root "$_m12x_ctr02" <<'EOF'
u="$(id -u app)"
cd /tmp && sudo -u app env XDG_RUNTIME_DIR="/run/user/$u" podman ps --format json </dev/null 2>/dev/null | python3 -c '
import json, subprocess, sys
r = []
for c in json.load(sys.stdin):
    i = json.loads(subprocess.run(["podman", "inspect", c["Id"]], capture_output=True, text=True).stdout or "[{}]")[0]
    r.append({"image": c.get("Image", ""), "utilisateur": (i.get("Config") or {}).get("User", ""),
              "privilegie": (i.get("HostConfig") or {}).get("Privileged", False),
              "unite": (i.get("Config", {}).get("Labels") or {}).get("PODMAN_SYSTEMD_UNIT", ""),
              "compose": (i.get("Config", {}).get("Labels") or {}).get("com.docker.compose.project", "")})
print(json.dumps(r))'
EOF
)" || true
  _m12_e46_pods="${_m12_e46_pods:-[]}"
  for _m12_e46_p in "${_m12_e46_apps[@]}"; do
    check_cmd "ctr02 : un conteneur du compte app exécute $_m12_e46_p tirée du registre de travail" \
      bash -c 'jq -e --arg i "$2/$3" "[.[] | select((.image | startswith(\$i + \":\")) or (.image | startswith(\$i + \"@\")))] | length >= 1" >/dev/null <<<"$1"' \
      _ "$_m12_e46_pods" "$_m12x_nom01:5000" "$_m12_e46_p"
  done
  check_cmd "ctr02 : aucun conteneur privilégié" bash -c 'jq -e "all(.[]; .privilegie == false) and length > 0" >/dev/null <<<"$1"' _ "$_m12_e46_pods"
  check_cmd "ctr02 : conteneurs des applications pilotés par systemd (Quadlet) ou par Compose" \
    bash -c 'jq -e --arg r "$2:5000/" "[.[] | select(.image | startswith(\$r)) | select(.unite == \"\" and .compose == \"\")] | length == 0" >/dev/null <<<"$1"' \
    _ "$_m12_e46_pods" "$_m12x_nom01"
elif [[ "$_m12_e46_phase" == inconnue ]]; then
  check_http "MédiAgenda : http://$_m12_e46_nom02:8000/pret → 200" "http://$_m12_e46_nom02:8000/pret" 200
else
  skip "pile de recette de ctr02" "phase de clôture : environnement détruit, preuve dans docs/conteneurs/recette-v1.md"
fi

# --- 5. Environnement du module ---------------------------------------------------------------------------
title "5/6 Environnement du module"
_m12_e46_nb_inactif() {
  netbox_api "virtualization/virtual-machines/?name=$1" | jq -e '.count == 0 or (.results[0].status.value != "active")' >/dev/null
}
if [[ "$_m12_e46_phase" == cloture ]]; then
  for _m12_e46_v in "2122 ctr02" "2123 ctr03" "2124 legacy01"; do
    read -r _m12_e46_id _m12_e46_h <<<"$_m12_e46_v"
    check_cmd "VM $_m12_e46_id ($_m12_e46_h) détruite" _m12_e46_vm_absente "$_m12_e46_id"
    check_cmd "NetBox : $_m12_e46_h absent ou non actif" _m12_e46_nb_inactif "$_m12_e46_h"
  done
  if [[ "${WB_M12_CTR01_CONSERVE:-0}" == 1 ]]; then
    skip "VM 2121 (ctr01) détruite" "conservée jusqu'à la fin de M13-E03 (WB_M12_CTR01_CONSERVE=1)"
  else
    check_cmd "VM 2121 (ctr01) détruite (ou WB_M12_CTR01_CONSERVE=1 si gardée jusqu'à la fin de M13-E03)" _m12_e46_vm_absente 2121
  fi
elif [[ "$_m12_e46_phase" == inconnue ]]; then
  skip "destruction des VMs d'environnement" "pve01 ne répond pas"
else
  skip "destruction des VMs d'environnement" "phase de recette : à faire après la revue, par OpenTofu (état m12-conteneurs)"
fi

# --- 6. Documentation et livraison ----------------------------------------------------------------------------
title "6/6 Documentation et livraison (plateforme/medisphere)"
_m12_e46_doc() {
  local f="$_m12_e46_depot/$1" m; shift
  [[ -s "$f" ]] || return 1
  for m in "$@"; do grep -Eiq -- "$m" "$f" || return 1; done
}
_m12_e46_doc_prefixe() { compgen -G "$_m12_e46_depot/$1/$2*.md" >/dev/null; }
check_cmd "docs/conteneurs/architecture.md (hôtes, registre, runner, recette, flux)" \
  _m12_e46_doc docs/conteneurs/architecture.md 'runner02' '5000' 'ctr02' 'Harbor'
check_cmd "docs/conteneurs/normes.md présent" _m12_e46_doc docs/conteneurs/normes.md 'USER|root'
check_cmd "ADR-0120 présent" _m12_e46_doc_prefixe docs/conteneurs/adr ADR-0120
for _m12_e46_r in RB-120 RB-123 RB-124 RB-125; do
  check_cmd "$_m12_e46_r présent" _m12_e46_doc_prefixe docs/conteneurs/runbooks "$_m12_e46_r"
done
check_cmd "procès-verbal de recette (docs/conteneurs/recette-v1.md : résultats et date)" \
  _m12_e46_doc docs/conteneurs/recette-v1.md 'check 12 46' '20[0-9]{2}-[0-9]{2}-[0-9]{2}'
check_cmd "matrice des flux : runner02 et registre de travail (5000)" \
  _m12_e46_doc docs/socle/matrice-flux.md '10\.10\.20\.17|runner02' '5000'
check_cmd "inventaire du socle : runner02 (1012, 10.10.20.17)" \
  _m12_e46_doc docs/socle/inventaire.md 'runner02' '10\.10\.20\.17'
check_cmd "registre des secrets : registre de travail et jeton du runner (emplacements)" \
  _m12_e46_doc docs/socle/registre-secrets.md 'registre|htpasswd' 'runner'
_m12_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/conteneurs-v1' | jq -e '.name == "conteneurs-v1"' >/dev/null; }
check_cmd "plateforme/medisphere : étiquette conteneurs-v1 publiée" _m12_e46_etiquette
check_output "dépôt de documentation local : aucune modification non commitée" '^$' git -C "$_m12_e46_depot" status --porcelain
check_cmd "aucun secret évident dans docs/ (clé privée, empreinte htpasswd, jeton glrt-)" bash -c \
  '[ -d "$1/docs" ] && ! grep -REq "(BEGIN [A-Z ]*PRIVATE KEY|:\\\$2[aby]\\\$[0-9]{2}\\\$|glrt-[A-Za-z0-9_-]{15,})" "$1/docs"' _ "$_m12_e46_depot"

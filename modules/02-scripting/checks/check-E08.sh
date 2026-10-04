# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E08.sh — M02-E08 : Premier client Python de l'API Proxmox, TLS vérifié
# À lancer depuis adm01. Importe medictl.pve dans l'environnement du projet et fait
# uniquement des GET sur l'API. Lecture seule.

title "M02-E08 — Premier client Python de l'API Proxmox, TLS vérifié"
require_cmd git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_py="$_m02_r/.venv/bin/python"

check_cmd "src/medictl/pve.py versionné" git -C "$_m02_r" ls-files --error-unmatch src/medictl/pve.py
check_cmd "aucune désactivation de la vérification TLS dans src/" \
  bash -c '! grep -rEn "verify(_ssl)?[[:space:]]*=[[:space:]]*False|disable_warnings|CERT_NONE|check_hostname[[:space:]]*=[[:space:]]*False" "$1/src"' \
  _ "$_m02_r"
check_cmd "environnement du projet présent (.venv)" test -x "$_m02_py"
check_output "fichier d'accès pve-api.env toujours en mode 600" '^600$' \
  stat -c %a "$HOME/.config/workbook/pve-api.env"

# Le programme de test affiche une ligne « clé:ok » ou « clé:ko <raison> » par contrôle.
# Il ne reçoit aucun secret en argument et n'en affiche aucun.
_m02_test="$(cat <<'PY'
import dataclasses, os, sys
from pathlib import Path

def dire(cle, ok, raison=""):
    print(cle + ":" + ("ok" if ok else "ko " + raison))

try:
    from medictl.pve import ConfigError, charger_config, connexion
except Exception as exc:
    print(f"import:ko {type(exc).__name__}"); sys.exit(0)
print("import:ok")

import requests

try:
    cfg = charger_config()
    dire("config", True)
except Exception as exc:
    dire("config", False, type(exc).__name__); sys.exit(0)

dire("repr", cfg.token_secret not in repr(cfg) and cfg.token_secret not in str(cfg))

try:
    v = connexion(cfg).version.get()
    dire("version", isinstance(v, dict) and "version" in v)
except Exception as exc:
    dire("version", False, type(exc).__name__)

try:
    vms = connexion(cfg).cluster.resources.get(type="vm")
    dire("ressources", any(vm.get("vmid") == 1001 for vm in vms))
except Exception as exc:
    dire("ressources", False, type(exc).__name__)

# Même configuration, mais une autorité qui n'a PAS signé le certificat de pve01 :
# la connexion doit être refusée.
autre = Path("/etc/ssl/certs/ca-certificates.crt")
try:
    connexion(dataclasses.replace(cfg, cacert=autre)).version.get()
    dire("tls", False, "connexion acceptée avec une autorité étrangère")
except requests.exceptions.SSLError:
    dire("tls", True)
except Exception as exc:
    dire("tls", False, type(exc).__name__)

os.environ["MEDICTL_ENV_FILE"] = "/nonexistent/pve-api.env"
try:
    charger_config()
    dire("absent", False, "aucune erreur")
except ConfigError as exc:
    dire("absent", "/nonexistent/pve-api.env" in str(exc))
except Exception as exc:
    dire("absent", False, type(exc).__name__)
PY
)"
_m02_res="$(cd "$_m02_r" 2>/dev/null && "$_m02_py" -c "$_m02_test" 2>&1)" || true

check_output "medictl.pve importable (charger_config, connexion, ConfigError)" '^import:ok$' \
  printf '%s\n' "$_m02_res"
check_output "charger_config() lit le fichier d'accès par défaut (pve-api.env)" '^config:ok$' printf '%s\n' "$_m02_res"
check_output "le secret du jeton n'apparaît pas dans repr()/str() de la configuration" '^repr:ok$' \
  printf '%s\n' "$_m02_res"
check_output "GET /version répond, certificat vérifié" '^version:ok$' printf '%s\n' "$_m02_res"
check_output "GET /cluster/resources?type=vm liste adm01 (1001)" '^ressources:ok$' printf '%s\n' "$_m02_res"
check_output "une autorité qui n'a pas signé le certificat de pve01 est refusée (erreur TLS)" '^tls:ok$' \
  printf '%s\n' "$_m02_res"
check_output "MEDICTL_ENV_FILE vers un fichier absent : ConfigError qui nomme le fichier" '^absent:ok$' \
  printf '%s\n' "$_m02_res"
_m02_res=""

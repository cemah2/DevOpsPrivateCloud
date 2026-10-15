# k3s (M18-E03)

Rôle Ansible `k3s` (`plateforme/ansible`) ; variables de `k3s01` dans `host_vars/k3s01/k3s.yml`.
Manifestes de l'agence : `agence/`.

## Le script d'installation

Téléchargé **au tag** de la version (`https://raw.githubusercontent.com/k3s-io/k3s/v1.36.5%2Bk3s1/install.sh`),
lu, empreinte SHA-256 fixée dans le rôle (`k3s_script_sha256`). Le script télécharge le binaire
k3s de la version et vérifie son empreinte (`sha256sum-amd64.txt`), écrit `/usr/local/bin/k3s`,
les liens `kubectl`, `crictl`, `ctr`, le service `k3s.service` (ou `k3s-agent.service`), son
fichier d'environnement, et `k3s-killall.sh`, `k3s-uninstall.sh` (ou `k3s-agent-uninstall.sh`).

Variables utilisées par le rôle :

| Variable | Valeur | Pourquoi |
|---|---|---|
| `INSTALL_K3S_VERSION` | `v1.36.5+k3s1` | une version précise, pas le canal (sinon le binaire change d'une exécution à l'autre) |
| `INSTALL_K3S_EXEC` | `server` ou `agent` | le type de service ; toutes les options sont dans `config.yaml`, pas sur la ligne de commande |
| `INSTALL_K3S_SKIP_START` | `true` | le rôle démarre le service après avoir écrit configuration, jeton et miroirs |

Le jeton n'est **pas** passé au script (`K3S_TOKEN` finirait dans le fichier d'environnement du
service) : `config.yaml` porte `token-file: /etc/rancher/k3s/jeton` (600).

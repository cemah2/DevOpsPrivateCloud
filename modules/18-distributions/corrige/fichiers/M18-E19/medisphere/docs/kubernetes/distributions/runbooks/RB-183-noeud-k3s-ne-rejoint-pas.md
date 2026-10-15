# RB-183 — Un nœud k3s ne rejoint plus son cluster

| | |
|---|---|
| Portée | Agents et serveurs k3s (banc `k3s-ha`, agence de Lyon) |
| Symptôme | Nœud `NotReady` / absent, `k3s-agent` (ou `k3s`) en redémarrage en boucle |
| Rédigé par | Équipe Plateforme — M18-E19 (INC-4519) |

## 1. Séquence d'enregistrement d'un agent (à garder en tête)

1. Lecture de la configuration : `/etc/rancher/k3s/config.yaml`, `config.yaml.d/`, fichier d'environnement de l'unité (`K3S_URL`, `K3S_TOKEN`).
2. `GET https://<serveur>:6443/cacerts` **sans** authentification, comparaison de l'empreinte SHA-256 avec celle du jeton (`K10<empreinte>::…`).
3. Demande des certificats au superviseur (port **6443** pour k3s ; 9345 c'est RKE2) avec le jeton et le mot de passe de nœud (`/etc/rancher/node/password` ↔ Secret `<nœud>.node-password.k3s`).
4. Démarrage de containerd et du kubelet, tunnel vers le serveur, répartiteur local.

## 2. Vérifications, dans l'ordre (aucune ne modifie rien)

| # | Vérification | Commande | Si KO |
|---|---|---|---|
| 1 | Service et première erreur | `systemctl status k3s-agent` ; `journalctl -u k3s-agent -b --no-pager \| grep -m 20 -Ei 'error\|fatal\|x509\|refused\|timeout'` | lire la ligne, aller à l'étape correspondante |
| 2 | Adresse du serveur | `sudo grep -rE '^(server:\|K3S_URL)' /etc/rancher/k3s/ /etc/systemd/system/k3s-agent.service.env` | port 6443, nom résolu (`getent hosts`) |
| 3 | Superviseur joignable | `curl -sk --max-time 5 https://<serveur>:6443/ping` → `pong` | refus : mauvais port/service arrêté ; délai : filtrage (pare-feu du serveur, bordure) |
| 4 | Jeton | empreinte du jeton (`cut -c4-67`) = `curl -sk https://<serveur>:6443/cacerts \| sha256sum` | jeton d'un autre cluster : remettre celui du Vault |
| 5 | Horloge | `timedatectl` ; `date` comparé au serveur | service de temps arrêté : `systemctl start chrony && chronyc makestep` |
| 6 | Identité du nœud | journal : *Node password rejected* | nom d'hôte en double, ou nœud réinstallé : voir §4 |

Messages typiques (à compléter avec ceux de ta version) :
- `token CA hash does not match the Cluster CA certificate hash` → jeton d'un autre cluster ;
- `connect: connection refused` vers `:9345` → port de RKE2 ;
- `i/o timeout` vers `:6443` → filtrage ;
- `x509: certificate has expired or is not yet valid` → horloge ;
- `Node password rejected` → identité du nœud.

## 3. Correctifs

Toujours par le rôle `k3s` (variables `k3s_url`, `vault_k3s_jeton_<cluster>`, service de temps du rôle de base), puis second passage `changed=0`. Une correction à la main n'est qu'un dépannage, reporté au code dans la journée.

## 4. Ce qu'on ne fait jamais

- Réinstaller l'agent (`k3s-agent-uninstall.sh`, `curl | sh`) : la cause reste.
- Supprimer le Secret `<nœud>.node-password.k3s` sans avoir prouvé que le nœud a été réinstallé sous le même nom (sinon on ouvre la porte à une usurpation d'identité).
- Copier le jeton du serveur dans un ticket, un journal ou une note.
- Ouvrir le pare-feu « en grand » : seuls 6443 (superviseur et API), 8472/udp (Flannel VXLAN), 10250 (kubelet) et, entre serveurs, 2379-2380 sont nécessaires.

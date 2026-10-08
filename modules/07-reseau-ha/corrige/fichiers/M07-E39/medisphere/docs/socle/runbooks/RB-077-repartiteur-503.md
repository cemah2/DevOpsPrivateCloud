# RB-077 — Un répartiteur répond 503

| | |
|---|---|
| **Portée** | HAProxy de `lb01`/`lb02` (GitLab, NetBox, entrées de la plateforme) et de la maquette (`hap01`) |
| **Déclencheur** | 503 « No server is available to handle this request » ; sonde « backend sans serveur UP » |
| **Durée cible** | 5 min jusqu'au diagnostic |
| **Issu de** | INC-3405 (M07-E39) ; complète RB-070 (maintenance d'un répartiteur) |

## 1. Qui répond 503 ?

```
$ curl -si https://<service>/ | head -n 5
admin@<répartiteur actif>:~$ sudo journalctl -u haproxy --since -1h --no-pager | grep -E 'is DOWN|no server available'
```

Page intégrée de HAProxy et « has no server available » : aucun serveur utilisable. Sinon, le 503 vient d'un serveur (aller à §3).

## 2. État des serveurs (socket d'administration)

```
admin@<répartiteur>:~$ echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18,37,38 | column -ts,
```

| `check_status` | Couche | Pistes |
|---|---|---|
| `L4CON` / `L4TOUT` | TCP | Service arrêté, écoute sur 127.0.0.1, port faux (`check port`), filtrage |
| `L6RSP` / `L6TOUT` | TLS | `check-ssl` vers un serveur en clair, certificat refusé (`verify required`, `ca-file`, SNI) |
| `L7STS` (+ code) | HTTP | Chemin de santé faux (404), fichier de maintenance (503), `Host` attendu |
| `L7TOUT` | HTTP | Serveur saturé, `timeout check` trop court |

## 3. Rejouer le contrôle à l'identique

Lire `option httpchk`, `http-check send/expect` et les options `check*` de la ligne `server`, puis depuis le répartiteur :

```
$ curl -sv -H 'Host: <hôte du contrôle>' http://<adresse du serveur>:<port>/<chemin>
$ openssl s_client -connect <adresse>:<port> -servername <nom> </dev/null     # si check-ssl
```

## 4. Corriger sans couper

- Configuration de HAProxy : par le rôle `haproxy` ; `haproxy -c -f …` puis **rechargement** (*handler*), jamais `restart`.
- Serveur : par son rôle (`nginx_web`…) ; fichier de maintenance oublié : vérifier qu'aucune maintenance n'est en cours avant de le retirer.
- Action ponctuelle : `set server <backend>/<serveur> state ready` par la socket.

## 5. Clôture

Tous les serveurs `UP` (`show stat`), le service répond 200, `lab/bin/check 07 39` (maquette) ou `ms-verif-reseau` (socle) au vert ; RB-070 : la maintenance se termine **toujours** par le retrait du fichier et la vérification `UP`.

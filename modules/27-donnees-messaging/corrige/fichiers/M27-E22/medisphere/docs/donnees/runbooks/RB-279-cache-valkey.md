# RB-279 — Le cache Valkey ne sert plus

| | |
|---|---|
| Symptôme | MédiAgenda lent (créneaux recalculés depuis la base), journaux « cache indisponible » ou « écriture en cache impossible », `/pret` à 503 si Valkey ne répond plus au `PING` |
| Alertes | `MediagendaCacheEnErreur`, `ValkeyInjoignable`, `ValkeyCachePlein` (RB-274) |
| Objets | StatefulSet `valkey` de l'espace, utilisateur ACL `mediagenda` (API), utilisateur d'administration (OpenBao `kv/mediagenda/<env>/valkey-admin`), certificat TLS (cert-manager), exportateur en *sidecar* |

Valkey est un **cache** : sa perte dégrade, ne casse pas. On peut le redémarrer (il repart vide) ; on ne le « répare » pas en désactivant l'ACL ou le TLS.

## 1. Quel message ?

```
admin@adm01:~$ kubectl -n mediagenda-<ENV> logs deploy/mediagenda --since=10m | grep -i -m5 cache   # ou Loki
```

| Message | Famille | §
|---|---|---|
| `NOPERM … no permissions to access one of the keys` / `… to run the '…' command` | ACL | 2 |
| `WRONGPASS`, `NOAUTH` | identifiants (Secret, rotation) | 2 |
| `OOM command not allowed when used memory > 'maxmemory'` | mémoire et éviction | 3 |
| `certificate verify failed`, `SSL: …`, `Connection reset` | TLS | 4 |
| `Timeout`, `Connection refused` | Valkey arrêté, réseau | pods, CNP |

Connexion d'administration (le mot de passe par l'environnement, jamais en argument) :
```
admin@adm01:~$ kubectl -n mediagenda-<ENV> exec -it valkey-0 -c valkey -- sh -c 'read -rs VALKEYCLI_AUTH; export VALKEYCLI_AUTH; exec valkey-cli --tls --cacert <CA-DU-POD> --user admin'
```

## 2. ACL

`ACL LIST` (règles **en vigueur**), `ACL LOG 10` (refus récents : utilisateur, commande, clé), puis comparer à l'ACL **déclarée** (fichier `aclfile` monté dans le pod, généré depuis OpenBao). Une différence = modification à chaud (`ACL SETUSER`) : remettre la règle déclarée (`ACL LOAD` relit le fichier), et chercher qui l'a faite (`ACL LOG`, journaux d'audit). Ne jamais lancer `ACL SAVE` pour « figer » une correction : la vérité est dans la configuration déclarée.

## 3. Mémoire et éviction

```
CONFIG GET maxmemory
CONFIG GET maxmemory-policy
INFO memory          # used_memory, maxmemory
INFO stats           # evicted_keys, keyspace_hits / misses
INFO errorstats      # errorstat_OOM:count=…
```
`noeviction` sur un cache = toute écriture refusée dès le plafond atteint. Rétablir la politique et le plafond **déclarés** (`allkeys-lru`, `maxmemory` de la configuration montée) : `CONFIG SET maxmemory-policy allkeys-lru`, `CONFIG SET maxmemory <valeur déclarée>`, puis vérifier que `CONFIG GET` égale le fichier ; un redémarrage de `valkey-0` relit la configuration et efface tout réglage à chaud. Si le plafond est **vraiment** trop bas (`ValkeyCachePlein` récurrent), le relever par MR (et la limite mémoire du conteneur avec).

## 4. TLS

```
admin@adm01:~$ kubectl -n mediagenda-<ENV> get certificate -o wide
admin@adm01:~$ kubectl -n mediagenda-<ENV> get certificate <CERT> -o jsonpath='{.spec.issuerRef}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-<ENV> get secret <SECRET-TLS> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -subject -ext subjectAltName -enddate
```
Le certificat servi doit être signé par l'autorité qu'attend MédiAgenda (racine MédiSphère, émetteur de M27-E07) et porter le nom utilisé dans `MEDIAGENDA_VALKEY_URL`. Corriger le `Certificate` là où il est déclaré, attendre la réémission (`kubectl get certificate` → `Ready`), puis **redémarrer `valkey-0`** : Valkey ne recharge pas seul ses fichiers de certificat.

## 5. Après

`redis_up = 1`, plus d'erreur `mediagenda_cache_total{resultat="erreur"}`, des `hit` qui reviennent, `/pret` à 200, et `CONFIG GET` / `ACL LIST` égaux à la configuration déclarée.

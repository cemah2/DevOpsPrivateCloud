# Valkey de MédiAgenda

> `docs/donnees/valkey.md` — M27-E07 (PLAT-2807). Responsable : équipe MédiAgenda (Julien Petit) ; plateforme : Karim Benali.

## Ce que c'est

Un **cache** de créneaux (`mediagenda:creneaux:<praticien>:<jour>`, durée de vie `MEDIAGENDA_CACHE_TTL`). Sa perte coûte des lectures en base, **pas** des données. Pas de persistance, pas de réplication. `/pret` de l'API échoue tant que Valkey ne répond pas (les pods sortent du Service) ; les requêtes en cours passent en mode dégradé (`mediagenda_cache_total{resultat="erreur"}`).

| Élément | Valeur |
|---|---|
| Version | Valkey **9.1.2** (`registry.par1.medisphere.internal/dockerhub/valkey/valkey:9.1.2-trixie`, par condensé en prod) ; `INFO server` : `valkey_version:9.1.2` (et `redis_version:7.2.4`, valeur figée pour les clients qui testent la version de Redis) |
| Objets | component `valkey` de `mediagenda/deploiement` : StatefulSet `valkey` (conteneurs `valkey` et `exportateur`), Service `valkey` (6379), ConfigMap `valkey-config`, NetworkPolicy `valkey`, PodMonitor `valkey` ; par overlay : Certificate `valkey-tls` |
| Configuration | `port 0`, `tls-port 6379`, `tls-auto-reload-interval 3600`, `aclfile /etc/valkey/acl/users.acl`, `maxmemory 96mb` (limite du conteneur 160 Mio), `maxmemory-policy allkeys-lru`, `save ""`, `appendonly no` |
| Comptes | `default` désactivé ; `mediagenda` (clés `mediagenda:*`, `+@read +@write +@connection -@dangerous`) ; `exportateur` ; `sonde` (`PING`) ; `admin` (bris de glace) |
| Secrets | OpenBao `kv/mediagenda/<env>/valkey` (`mot_de_passe`, `mot_de_passe_admin`, `mot_de_passe_exportateur`, `mot_de_passe_sonde`, `url`) → ExternalSecrets `valkey-comptes` (fichier ACL avec empreintes SHA-256), `valkey-admin`, `mediagenda-valkey` (URL de l'API) |
| TLS | `rediss://` ; l'API vérifie chaîne **et** nom (`SSL_CERT_FILE` = racine MédiSphère, component `racine-medisphere`) ; certificat de 72 h relu par Valkey sans redémarrage |
| Supervision | exportateur `redis_exporter` v1.95.0 (9121) : `redis_up`, `redis_instance_info{valkey_version, maxmemory_policy}`, `redis_memory_used_bytes`, `redis_memory_max_bytes`, `redis_evicted_keys_total` ; règle d'équipe `MediagendaValkeyMemoireHaute` ; alertes de plateforme (M27-E14) |

## Se connecter (bris de glace)

```
admin@adm01:~$ ENV=recette
admin@adm01:~$ kubectl -n mediagenda-$ENV get secret valkey-admin -o jsonpath='{.data.mot_de_passe}' | base64 -d \
  | kubectl -n mediagenda-$ENV exec -i valkey-0 -c valkey -- sh -c 'read -r VALKEYCLI_AUTH; export VALKEYCLI_AUTH;
      valkey-cli --tls --cacert /etc/medisphere/racine/medisphere-root-ca.crt --user admin --no-auth-warning INFO memory'
```

Le mot de passe passe par l'entrée standard (jamais en argument, jamais dans l'historique). `valkey-cli` rend 0 même sur `NOAUTH` : lis la réponse.

## Sauvegarde (avant une montée de version)

Un cache ne se sauvegarde pas en routine. Avant une montée de version, on garde de quoi **relire** l'état si la nouvelle version refusait de démarrer :

```
… --user admin BGSAVE                                    # puis attendre :
… --user admin INFO persistence | grep rdb_last_bgsave_status   # rdb_last_bgsave_status:ok
admin@adm01:~$ kubectl -n mediagenda-$ENV cp -c valkey valkey-0:/data/dump.rdb ~/m27/e07/valkey-$ENV-$(date +%F).rdb
```

Relecture par la **nouvelle** version, dans un pod jetable de `wb-essais` (image cible) : `valkey-check-rdb /data/dump.rdb` → « RDB looks OK! ». Le format RDB monte en version avec Valkey : une version ne relit pas forcément un fichier écrit par une version **plus récente** — on ne revient pas en arrière avec une RDB écrite après la montée.

## Montée de version

1. Notes de version (changements incompatibles, comportements par défaut) ; image dans Harbor (cache `dockerhub`), condensé relevé.
2. Sauvegarde ci-dessus.
3. MR sur `mediagenda/deploiement` (étiquette dans `components/valkey/statefulset.yaml`, condensé dans `overlays/prod`), recette d'abord (synchronisation automatique), prod ensuite (MR approuvée, synchronisation manuelle).
4. Le pod redémarre : `/pret` en 503 quelques secondes (mesuré en recette lors du passage 8.1 → 9.1 : <DURÉE> s), cache vide, montée en charge de la base pendant quelques minutes.
5. Vérifications : `INFO server`, `MODULE LIST` (module `lua`), `ACL LIST`, `redis_instance_info`, taux de réussite du cache qui remonte.

## Pourquoi ni Sentinel ni réplique (réponse à Julien, PLAT-2807)

1. Sentinel élit un nouveau primaire, mais il faut un **client qui interroge Sentinel** pour le trouver ; le client `redis` de MédiAgenda est configuré par une URL fixe : il ne suivrait pas la bascule.
2. Une réplique sans Sentinel n'apporte que des lectures : MédiAgenda écrit à chaque lecture manquée.
3. Le cache se reconstruit tout seul : une perte coûte quelques minutes de charge sur `mediagenda-db`, mesurées acceptables (pooler, E02).
4. Le vrai risque est `/pret` qui dépend de Valkey : si l'indisponibilité de Valkey devient un problème, on retire Valkey de `/pret` (l'API sait servir sans cache) plutôt que d'ajouter trois pods.
5. À revoir si Valkey porte un jour des données qu'on ne peut pas reconstruire (sessions, files) : ce ne serait plus un cache.

## Valkey perdu

Pod en échec : `kubectl -n mediagenda-<env> describe pod valkey-0`, journaux du conteneur `valkey` (`TLS materials` : certificat ; `aclfile` : comptes), état de `valkey-tls` et des ExternalSecrets. Rien à restaurer : on répare, le cache se remplit. Runbook des pannes : `runbooks/RB-279-cache-valkey.md` (M27-E22).

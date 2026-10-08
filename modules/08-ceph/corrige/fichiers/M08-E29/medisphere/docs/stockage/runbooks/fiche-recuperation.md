# Fiche réflexe — la récupération de Ceph et les clients

> Propriétaire : équipe Plateforme · Créée : M08-E29 (PLAT-955) · Liée à : RB-080 (remplacer un disque), RB-081 (ajouter un nœud), RB-082 (mise à jour)

## Reconnaître la situation

```
[admin@ceph01 ~]$ sudo ceph -s                    # ligne « recovery: … MiB/s, … objects/s », PG degraded / backfilling
[admin@ceph01 ~]$ sudo ceph progress              # estimation de fin
[admin@ceph01 ~]$ sudo ceph config show osd.0 osd_mclock_profile
```

## Cas 1 — « la récupération gêne les clients » (latences, plaintes)

1. Vérifier que c'est bien elle : la gêne a commencé avec la récupération (`ceph -s`, horodatage de l'événement), et aucun OSD n'est saturé pour une autre raison (`ceph osd perf`).
2. Favoriser les clients, **à chaud, pour tout le cluster** :
   ```
   [admin@ceph01 ~]$ sudo ceph config set osd osd_mclock_profile high_client_ops
   ```
3. Noter l'heure dans le ticket. La récupération sera plus longue : la redondance reste réduite plus longtemps ; ne pas laisser durer au-delà de la fin de la période sensible.
4. Retour au nominal **dès** la fin de la gêne ou de la récupération (même commande avec le profil nominal : `balanced`).

## Cas 2 — « la récupération est trop lente » (fenêtre de risque trop longue)

1. Vérifier qu'elle progresse (`ceph progress`, nombre d'objets dégradés qui baisse) ; si elle ne progresse pas, ce n'est pas un réglage : PG bloqués, OSD plein (`ceph health detail`) → RB du palier 4.
2. Accélérer, en sachant que les clients ralentiront :
   ```
   [admin@ceph01 ~]$ sudo ceph config set osd osd_mclock_profile high_recovery_ops
   ```
3. Retour au profil nominal dès que tous les PG sont `active+clean`.

## Ce qu'on ne fait pas

- Pas de réglage par OSD (`osd.N`) « pour voir » : oublié, il fausse tout le reste.
- Pas de `osd_max_backfills` / `osd_recovery_max_active` : mClock les verrouille ; les déverrouiller (`osd_mclock_override_recovery_settings`) n'est justifié que sur avis documenté, et se retire ensuite.
- Pas de `nobackfill` / `norecover` pour « calmer » le cluster : la redondance ne revient jamais tant qu'ils sont posés.

## Maintenance planifiée d'un nœud (redémarrage noyau)

```
[admin@ceph01 ~]$ sudo ceph orch host ok-to-stop ceph03
[admin@ceph01 ~]$ sudo ceph orch host maintenance enter ceph03      # arrête ses démons, noout pour cet hôte
… redémarrage …
[admin@ceph01 ~]$ sudo ceph orch host maintenance exit ceph03
[admin@ceph01 ~]$ sudo ceph -s                                      # attendre HEALTH_OK avant le nœud suivant
```
`ceph osd set noout` (global) est à éviter : il couvre aussi une vraie panne survenant ailleurs pendant la maintenance.

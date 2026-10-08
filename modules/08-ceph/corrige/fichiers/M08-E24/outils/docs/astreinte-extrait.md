## Ceph (`ms-verif-ceph`) — ajout M08-E24

La sonde tourne toutes les 5 minutes sur `adm01` et écrit une ligne par anomalie (`journalctl -u ms-verif-ceph -n 40`). Toutes les commandes ci-dessous se lancent sur `ceph01` (hôte `_admin`) et sont **en lecture**.

**Les trois premières commandes**

```
[admin@ceph01 ~]$ sudo ceph -s
[admin@ceph01 ~]$ sudo ceph health detail
[admin@ceph01 ~]$ sudo ceph osd tree down     # ou : ceph pg dump_stuck, ceph df selon le message
```

**Réveiller quelqu'un tout de suite** (perte de service ou risque de perte de données imminent)

| Message de la sonde / contrôle | Pourquoi c'est urgent |
|---|---|
| `aucun mgr actif` + `HEALTH_ERR` | plus de vue, et souvent plus que ça : regarder `ceph -s` à la main |
| `quorum` incomplet (`MON_DOWN` avec 2 sur 3) | encore un MON et le cluster se fige |
| `PG_AVAILABILITY` (PG inactifs), `pg` « inactif(s) » | des écritures sont bloquées maintenant |
| `OSD_FULL`, `POOL_FULL`, pool plein à 95 % et plus | les écritures sont refusées |
| `OSD_DOWN` sur **deux hôtes** différents | `min_size=2` : un PG de plus et l'écriture s'arrête |
| `s3` en erreur, certificat expiré | MédiDoc est en panne pour les utilisateurs |
| `MON_CLOCK_SKEW` important (> 1 s) et qui grossit | risque de perte du quorum |

**Peut attendre le matin** (le cluster sert, la redondance est réduite ou un seuil approche)

| Contrôle | Action du matin |
|---|---|
| `OSD_DOWN` d'un seul OSD (ou un seul hôte) | RB-080 ; vérifier que la reconstruction progresse (ou qu'il n'y en a pas : 3 hôtes) |
| `PG_DEGRADED`, `PG_RECOVERY_FULL` non critique | suivre `ceph -s` ; fiche réflexe récupération (E29) |
| `OSD_NEARFULL`, `POOL_NEARFULL`, `capacite` | ticket d'extension (RB-081), politique de stockage |
| `RECENT_CRASH` | `ceph crash info <id>`, ticket, puis `ceph crash archive <id>` |
| `AUTH_INSECURE_*` | ticket SEC (E27) ; jamais de sourdine sans durée |
| certificat à moins de 10 jours | sur `adm01` : `systemctl status ceph-cert-dashboard.timer ceph-cert-ingress.timer`, journal du dernier passage ; `outils/cert-dashboard.sh --force` ou `cert-ingress.sh --force` |

**Mise en sourdine** : seulement avec une durée et un ticket, jamais `--sticky` : `ceph health mute <CODE> 4h`.

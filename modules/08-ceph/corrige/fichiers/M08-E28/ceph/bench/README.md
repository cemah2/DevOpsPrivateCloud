# Profils de mesure (plateforme/ceph, M08-E28)

Profils `fio` lancés depuis `cephcli01` sur un périphérique krbd **dédié à la mesure** (`bench/fio01`, 10 Gio, pool jetable `bench`). Ils écrivent sur tout le périphérique : jamais sur une image qui porte des données.

```
admin@cephcli01:~$ sudo rbd device map bench/fio01 --id bench -o ms_mode=secure    # identité jetable client.bench (pool bench)
admin@cephcli01:~$ sudo FIO_DEV=/dev/rbd0 fio --output-format=json --output=base-de-donnees.json base-de-donnees.fio
```

| Profil | Ressemble à | Lecture |
|---|---|---|
| `base-de-donnees.fio` | PostgreSQL de MédiAgenda : 4 Kio aléatoire, 70 % lecture, profondeur 16 | IOPS et centiles p95/p99 de la complétion |
| `sequentiel.fio` | exports, sauvegardes, images : 1 Mio, profondeur 4 | débit (Mio/s) |
| `latence.fio` | journal de base de données : 4 Kio en écriture synchrone, profondeur 1 | latence moyenne et p99 (borne basse du cluster) |

Méthode complète et résultats : `docs/stockage/performances.md` de `plateforme/medisphere`.

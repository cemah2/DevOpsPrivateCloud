# patroni-essai — grappe Patroni de comparaison (M27-E13)

Essai **jetable** : trois VMs `pg-patroni01..03` (VMID 2271-2273, `vsandbox` 10.10.99.71-73) créées par
`plateforme/infra` (`envs/m27`), configurées ici : PostgreSQL 18 (PGDG), etcd (Debian 13, API v3),
Patroni 4.1.5 (PyPI, `/opt/patroni`), HAProxy de démonstration sur `pg-patroni01` (5000 → primaire, 7000 statistiques).

```
admin@adm01:~/src/donnees/patroni-essai$ ansible-playbook -i inventaire.yml patroni-essai.yml --vault-id lab@<SOURCE-DU-MOT-DE-PASSE>
admin@adm01:~$ ssh pg-patroni01 sudo -u postgres /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
```

Rien ici n'est durci (HTTP en clair pour etcd et l'API REST) : c'est dit dans
`docs/donnees/comparatif-patroni-cnpg.md`. Les VMs sont détruites en fin d'exercice ; ce dossier reste
comme trace de l'essai et point de départ si la décision changeait.

# plateforme/ceph — docs/supervision/prometheus-mgr.md (M21-E10, PLAT-2210)

Module `prometheus` du mgr de `ceph-par1` (Ceph Tentacle 20.2), activé pour le Prometheus de
`k8s-par1`. Commandes passées depuis `ceph01` (shell cephadm) ; tout réglage `ceph config` est
**consigné ici** : c'est la référence en cas de reconstruction.

```
[admin@ceph01 ~]$ sudo cephadm shell -- ceph mgr module enable prometheus
[admin@ceph01 ~]$ sudo cephadm shell -- ceph mgr services
{
    "dashboard": "https://ceph01.par1.medisphere.internal:8443/",
    "prometheus": "http://10.10.30.51:9283/"
}
[admin@ceph01 ~]$ sudo cephadm shell -- ceph config get mgr mgr/prometheus/standby_behaviour
default
```

Réglages retenus (valeurs par défaut, écrites pour être lues) :

| Clé | Valeur | Pourquoi |
|---|---|---|
| `mgr/prometheus/server_addr` | défaut (toutes les adresses) | le mgr suit le nœud actif ; filtrage par firewalld |
| `mgr/prometheus/server_port` | 9283 | port enregistré pour Ceph |
| `mgr/prometheus/standby_behaviour` | `default` | les mgr en attente répondent 200 et un corps vide sur `/metrics` (dans les deux modes : `error` ne change que la page `/`, pour un répartiteur) : les trois cibles restent `up`, et une bascule du mgr ne déclenche aucune alerte « cible injoignable » |
| `mgr/prometheus/cache` | `true` | le mgr ne recalcule pas ses métriques à chaque collecte |
| `mgr/prometheus/exclude_perf_counters` | défaut (`true`) | les compteurs de performance des démons relèvent de `ceph-exporter` (non déployé : pile de supervision de cephadm désactivée au M08) |

Pare-feu local des nœuds (firewalld, Rocky 10) : `9283/tcp` depuis les travailleurs
(10.10.30.81-83, carte `eth1`) et `adm01` (essais, par la bordure). cephadm ouvre parfois
lui-même les ports des modules du mgr : vérifie avant d'ajouter une règle.

```
[admin@ceph01 ~]$ sudo firewall-cmd --list-all
[admin@ceph01 ~]$ sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.10.30.80/29 port port=9283 protocol=tcp accept'
[admin@ceph01 ~]$ sudo firewall-cmd --reload
```
(⚠️ À vérifier sur ton lab : zone active de l'interface du VLAN 30 et règles déjà posées par cephadm.)

# Supervision des conteneurs

| | |
|---|---|
| **Version** | 1.0 — 2026-10 (M12-E28, ticket PLAT-1354) |
| **Propriétaire** | Équipe Plateforme ; astreinte : Nadia Roussel |

## Aujourd'hui (avant le module 21)

- **Sonde `ms-verif-conteneurs`** (`plateforme/outils`, sur `adm01`, toutes les 5 minutes, alerte `ms-alerte@`) : hôtes joignables, conteneurs attendus présents et `running`, aucun `unhealthy` ni `restarting`, compteur de redémarrages stable entre deux passages, sonde de santé présente (sauf exception écrite), métriques du démon Docker joignables. Accès aux hôtes : compte `supervision`, clé à commande forcée, lecture seule (rôle `supervision_conteneurs`).
- **Métriques du démon Docker** (`metrics-addr`, port 9323 de `ctr01`) : état du moteur (nombre de conteneurs par état, échecs de sondes de santé, durée des actions), lues en ligne de commande. Elles ne disent **rien** d'un conteneur en particulier (ni mémoire, ni CPU par conteneur).
- **En dépannage** : `docker events` / `podman events` (arrêts, `die`, `oom`, `health_status`), `docker stats` / `podman stats`, `systemctl --user status` des unités Quadlet, RB-120.

## Ce que Prometheus apportera (module 21)

- Historique et tendances (la sonde ne voit que l'instant et le passage précédent) : mémoire et CPU par conteneur (cAdvisor ou exportateur du moteur), redémarrages sur 24 h, saturation progressive d'un disque.
- Alertes fines et regroupées (Alertmanager) : seuils avec durée (« unhealthy depuis 5 min »), silences, routage par équipe.
- Métriques **applicatives** (`/metrics` de MédiAgenda, MédiDoc, MédiNotif, MédiAnnuaire) : latences, erreurs, files d'attente.

## Ce que la sonde continuera de faire

Un contrôle **de bout en bout indépendant** de la plateforme d'observabilité (si Prometheus tombe, la sonde alerte encore), sur une liste explicite de conteneurs attendus : un conteneur qui **disparaît** ne produit plus de métrique, et seule une liste d'attendus le remarque.

## Comparaison rapide (E28, étape 2)

| Source | Granularité | Accès nécessaire sur l'hôte | Usage |
|---|---|---|---|
| `docker ps` / `inspect` / `events` | conteneur, instantané | socket du démon (= root) ou sudo d'un script | sonde, dépannage |
| `metrics-addr` | moteur | aucun (HTTP en lecture) | santé du moteur |
| cAdvisor `v0.60.6` | conteneur, séries temporelles | lecture de `/`, `/sys`, `/var/lib/docker`, `/var/run`, `/dev/disk` (et souvent `--privileged`) | métriques par conteneur pour Prometheus |
| `podman stats` / `events` | conteneur | le compte propriétaire | dépannage sans privilège |

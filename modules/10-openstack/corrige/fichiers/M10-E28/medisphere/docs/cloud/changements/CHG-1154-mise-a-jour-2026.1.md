# CHG-1154 — Mise à jour d'OpenStack 2026.1 (Kolla-Ansible et images)

| | |
|---|---|
| Demandeur | Karim Benali |
| Exécutant | <MOI> (équipe Plateforme) ; relecture Karim ; astreinte informée : Nadia Roussel |
| Type | Changement **normal** (planifié, fenêtre annoncée), procédure RB-101 |
| Fenêtre | 2026-10-22, 12:30-13:30 (pause déjeuner des équipes de MédiAgenda) |
| Statut | **Clos — réussi** (2026-10-22 13:12) |

## 1. Objet

Appliquer les correctifs de la série 2026.1 : Kolla-Ansible 22.1.0 → **22.2.0** et images `2026.1-debian-trixie` reconstruites depuis le déploiement initial (correctifs de sécurité Debian et OpenStack). Pas de changement de série (2026.2 : Kolla-Ansible seulement en version candidate).

## 2. Ce qui change (notes de version 22.1.0 → 22.2.0, relues)

- *Bug fixes* : liste relevée dans les notes de version (RabbitMQ, OVN, Octavia…) — recopier ici les entrées qui touchent nos services activés.
- *Upgrade notes* : aucune action manuelle requise pour notre configuration (à confirmer à la lecture : sinon, l'action est ajoutée aux étapes).
- Inventaire et `globals.yml` comparés aux exemples livrés : aucun écart qui nous concerne.
- Images téléchargées (`pull`, sans interruption, la veille) : `outils/photographier-images.sh --perimes` → **31 conteneurs** sur une image plus ancienne que l'étiquette (dont `mariadb`, `rabbitmq`, `nova_*`, `neutron_server`, `ovn_*`, `openvswitch_*`).

## 3. Impact attendu

| Quoi | Effet | Durée estimée (mesures de E24) |
|---|---|---|
| Recréation de `mariadb` | toutes les API en erreur | 1 à 2 min |
| Recréation de `rabbitmq` | créations et actions bloquées, calculs « down » temporairement | 2 min + reconnexions |
| Recréation des API, d'HAProxy | erreurs 503 ponctuelles | quelques secondes chacune |
| Recréation de `openvswitch_*`, `ovn_controller` sur les calculs et la passerelle | coupure **possible** du trafic des instances pendant le redémarrage d'OVS | quelques secondes (à mesurer) |
| Instances | doivent continuer de tourner pendant la recréation de `nova_libvirt` (les processus QEMU ne doivent pas être rattachés au conteneur) : **point à prouver** par la mesure de continuité et `virsh list` avant/après ; en cas de doute, migrer les instances critiques hors du calcul (RB-102) | — |

## 4. Étapes

Celles de RB-101 §3 à §5 : sauvegarde vérifiée, instantanés `avant-maj` des trois nœuds, mesures de continuité, fusion de la MR, `uv sync --frozen`, `kolla-ansible deploy`, vérifications.

## 5. Critères de réussite

- `photographier-images.sh --perimes` : 0 conteneur ; aucun `unhealthy`.
- `ms-verif-openstack` : tout OK.
- Test fonctionnel : instance créée, volume attaché, répartiteur OVN qui répond, connexion à Horizon.
- Plan de données : aucune coupure de plus de 10 s sur la mesure nord-sud.

## 6. Critères d'abandon et retour arrière

Abandon si : `deploy` en échec sur MariaDB ou RabbitMQ non résolu en 15 min ; API indisponibles plus de 20 min ; une instance de production arrêtée ; Ceph en `HEALTH_ERR`. Retour arrière : RB-101 §6 (de la correction ciblée jusqu'au retour aux instantanés des trois nœuds). **Limite** : les instantanés ne couvrent pas Ceph ; toute ressource créée pendant la fenêtre (aucune autorisée) deviendrait orpheline.

## 7. Communication

- J-2 : annonce aux équipes (Julien), à l'astreinte (Nadia).
- T-15 min : rappel, début.
- Fin : message de clôture avec durée réelle et éventuels effets observés.

## 8. Exécution (journal)

| Heure | Étape |
|---|---|
| 12:15 | Sauvegarde Mariabackup + `preparer-sauvegarde.sh verifier` : restaurable |
| 12:20 | `ms-snapshot --prefix avant-maj 2101 2102 2103` |
| 12:24 | Mesures de continuité lancées (`maj-essai01`, IP flottante) |
| 12:30 | Fusion de la MR, `uv sync --frozen`, `kolla-ansible deploy` |
| 12:41 | Redémarrage de `mariadb` (API en erreur 12:41:10 → 12:42:35) |
| 12:43 | Redémarrage de `rabbitmq` (actions bloquées 12:43:02 → 12:45:20) |
| 12:58 | Fin de `deploy` (28 min) |
| 13:00 | Vérifications : `--perimes` 0, sonde OK, tests fonctionnels OK |
| 13:12 | Clôture, message aux équipes |

**Mesures** : API indisponibles 9 min au total (dont 1 min 25 MariaDB, 2 min 18 RabbitMQ, le reste en erreurs ponctuelles) ; nord-sud : deux coupures de 3 s et 4 s (redémarrage d'`openvswitch_vswitchd` sur `osctl01`) ; est-ouest : une coupure de 2 s.

**Après clôture** : instantanés `avant-maj` supprimés à J+7 sans incident ; `kolla-ansible prune-images` à J+7 (12 images supprimées par nœud, 9 Go libérés sur `osctl01`).

Photographies : `CHG-1154-avant.tsv`, `CHG-1154-apres.tsv` (même dossier).

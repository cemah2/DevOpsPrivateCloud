# Volumes de l'ancien `k8s-par1` dans `ceph-par1`

> Décision du corrigé de F1-S07 (CHG-3107). Les chiffres sont à relever sur ton lab avec
> `plateforme/k8s/outils/volumes-orphelins.sh lister`.

| | |
|---|---|
| Décideurs | Claire Morel (responsable), Sophie Laurent (données de santé), Nadia Roussel (exploitation) |
| Date | <AAAA-MM-JJ> |
| Revue | <AAAA-MM-JJ> (J+30 après la recette `day0-v1`) |

## Constat

Les PV de l'ancien cluster ont une politique `Delete` (`ceph-rbd`) ou `Retain` (`ceph-rbd-retain`), mais
personne ne les a supprimés : le cluster a disparu avant. Leurs images restent dans le pool **`k8s-rbd`**
(préfixe **`csi-vol-`**, une par PV), avec la correspondance PV → image dans l'objet omap de ceph-csi
(`csi.volumes.default`). Le nouveau cluster crée d'**autres** PV (noms `pvc-<uid>` neufs) et d'**autres**
images : aucune collision, mais de la place prise et des **données de santé** sans propriétaire.

| Élément | Valeur relevée |
|---|---|
| Images orphelines | `<N>` (`volumes-orphelins.sh lister`) |
| Capacité provisionnée | `<N>` Gio ; occupation réelle `rbd du -p k8s-rbd` : `<N>` Gio |
| Contenu | volumes des bases CNPG (copies périmées : les données font foi dans `cnpg-k8s-par1`), Prometheus local, RabbitMQ (files vides au gel), Valkey (cache), divers |
| Sous-volumes CephFS (groupe `csi`) | `<N>` (`ceph fs subvolume ls <fs> --group_name csi`) |

## Décision

1. **Rien n'est supprimé avant la recette `day0-v1` + 30 jours.** Pendant ce délai, une image orpheline
   peut encore servir d'appoint (lecture d'un volume par `rbd map` sur une VM jetable, sous contrôle de Sophie).
2. À la revue : les images orphelines vont dans la **corbeille RBD** avec une date d'expiration de 30 jours
   (`volumes-orphelins.sh corbeille <AAAA-MM-JJ>`) ; restaurables par `rbd trash restore` jusque-là.
3. La **purge définitive** (`rbd trash purge` ou `rbd trash rm`) est un geste séparé, après la date, tracé
   dans un ticket (preuve d'effacement de données de santé pour l'HDS).
4. Les sous-volumes CephFS suivent la même règle (mise à l'écart, puis suppression datée).

## Ce qu'on ne fait pas

- Supprimer « à vue » pendant la fenêtre : le retour arrière (restauration PBS des six VMs) **a besoin**
  de ces images, puisque les anciens PV y renvoient.
- Réattacher une image orpheline au nouveau cluster comme PV statique : les données font foi dans les
  archives (CNPG) et dans Git ; une copie périmée réinjectée serait une seconde vérité.

# Dossier M09-E34 — Remplacement planifié de `hv02` (exercice chronométré)

> À ouvrir à T0 seulement. Note l'heure maintenant dans la feuille de temps (en bas).

## Le besoin

> **Ticket CHG-1060 (suite)** — *De : Nadia Roussel*
> Alerte SMART (simulée) sur le disque système de `hv02` : secteurs réalloués en hausse, le fournisseur recommande un remplacement sous 48 h. Le serveur de remplacement est livré « nu » : même modèle, disques neufs. On le monte ce soir à la place de `hv02`, sous le même nom et les mêmes adresses.
> Dans le lab, « changer le matériel » = détruire la VM 2092 et ses disques, puis la recréer, **par le code**.

## Exigences

| # | Exigence | Détail |
|---|---|---|
| 1 | Continuité | Les VMs HA (dont 120 `fence01` et 121 `fence02`, recréées si besoin) ne subissent **aucune** interruption : lance `mesure-coupure.sh` (M09-E24) sur chacune avant T1, et garde le bilan. Aucune ressource HA ne passe par `fence` ni `recovery`. |
| 2 | Retrait propre | Avant la destruction : plus aucune VM sur `hv02`, plus aucune tâche de réplication dont `hv02` est la source, OSD de `hv02` sortis de Ceph **sans** perte de redondance au-delà de ce que `size 3` sur trois hôtes impose (dis-le dans le retour d'expérience), MON et MGR de `hv02` retirés, `hv02` retiré du cluster. Le cluster reste quorate à deux nœuds pendant toute l'opération. |
| 3 | Nouveau matériel | VM 2092 recréée par OpenTofu (état `hv`) avec des disques **neufs** ; installation automatique (fichier de réponse de `hv02`), sans clavier. |
| 4 | Réintégration | `hv02` rejoint `hv-par1` avec ses deux liens Corosync ; Ceph : MON, MGR et deux OSD neufs ; chien de garde émulé actif (E24) ; pare-feu (E26) ; certificat 8006 de la PKI (E26) ; SDN et VIP opérationnels ; pool ZFS `tank` ; tâches de réplication vers `hv02` rétablies. Tout ce qui est propre au nœud vient du code. |
| 5 | Retour au nominal | Ceph en `HEALTH_OK` (récupération terminée), cluster à trois nœuds, aucun reste de l'ancien `hv02` (OSD, clé d'hôte, entrée SSH connue), `fence01` revenue sur `hv02` par sa règle d'affinité, sonde `ms-verif-cluster` au vert. |
| 6 | Traçabilité | Chaque modification du code passe par une MR fusionnée après pipeline vert. Les commandes de cluster et de Ceph lancées à la main sont recopiées dans la feuille de temps. |

## Vérification

À T5, depuis `adm01` : `lab/bin/check 09 34`. Tout doit être vert.

## Feuille de temps

| Jalon | Définition | Heure | Écart depuis T0 | Gestes manuels / commentaire |
|---|---|---|---|---|
| T0 | Ouverture du dossier | | 0 | |
| T1 | Sondes de coupure lancées, état initial relevé (`pvecm status`, `ceph -s`, `ha-manager status`) | | | |
| T2 | `hv02` vidé (VMs, réplication, Ceph) et retiré du cluster | | | |
| T3 | VM 2092 recréée et Proxmox VE installé | | | |
| T4 | `hv02` réintégré (cluster, Ceph, rôles appliqués) | | | |
| T5 | Retour au nominal, `lab/bin/check 09 34` entièrement vert | | | |

**Bilans des sondes de coupure** (à coller) :

```
fence01 :
fence02 :
```

**Retour d'expérience** (une demi-page, dans `docs/virtualisation/tests/reprise-hv-par1.md`) : ce qui a pris le plus de temps (attente de la récupération Ceph ?), chaque geste manuel et l'outillage qui l'aurait évité, ce que tu changes dans RB-091 (section « remplacement planifié »), ce qui différait de la perte brutale d'E29, comment descendre sous une heure.

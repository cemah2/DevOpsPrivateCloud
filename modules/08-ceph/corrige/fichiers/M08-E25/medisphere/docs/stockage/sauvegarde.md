# Sauvegarde de ceph-par1

> Propriétaire : équipe Plateforme · Ticket d'origine : PLAT-951 (M08-E25) · Revue : annuelle et à chaque changement de chaîne.

## Principe

Trois copies dans `ceph-par1` assurent la **disponibilité**, pas la sauvegarde : une suppression, un chiffrement malveillant ou la perte du cluster se répliquent ou emportent tout. La sauvegarde quitte le cluster et le site : elle va sur `pbs01` (PAR2), chiffrée côté client par une clé que PBS ne connaît pas.

| Quoi | Comment | Où | Fréquence | RPO |
|---|---|---|---|---|
| Volumes RBD désignés | instantané `sauv-AAAAMMJJ` + `rbd export-diff` (complet le dimanche, incrémental sinon) | PBS `ds-lab`, espace `par1/ceph`, sauvegarde `host/ceph-par1-rbd` | quotidienne, 01:30 | 24 h |
| Configuration du cluster | archive produite sur `ceph01` (commande forcée), envoyée telle quelle | PBS, `host/ceph-par1-config` | quotidienne, 01:30 | 24 h |
| Compartiments S3 | hors périmètre v1 (ADR-0080, action induite) | — | — | — |
| CephFS | hors périmètre v1 : instantanés de sous-volumes seulement (pas hors site) | — | — | — |

## Volumes : la chaîne

- **Désignation** : liste explicite (`host_vars/cephcli01/sauvegarde_ceph.yml`) pour les usages de la Plateforme ; pour les équipes, métadonnée RBD `medisphere.sauvegarde = oui` posée par l'équipe sur son image (`rbd image-meta set …`), découverte dans `rbd-equipes` (tous les espaces de noms).
- **Nommage** : `sauv-AAAAMMJJ`. Un seul instantané de sauvegarde reste sur le cluster après un envoi réussi : celui du jour, base de l'incrémental du lendemain. Garder plus d'instantanés coûterait de la place (les blocs réécrits sont conservés) sans rien apporter : l'historique est dans PBS.
- **Complet** : `rbd export-diff <image>@sauv-J` sans `--from-snap` = tous les blocs écrits depuis la création (les zones jamais écrites ne sont pas transportées). Le dimanche, ou si l'instantané de base a disparu.
- **Incrémental** : `rbd export-diff --from-snap sauv-J-1 <image>@sauv-J` = blocs modifiés entre les deux instantanés.
- **Cohérence** : instantané pris à chaud, **cohérent en cas de panne** (comme une coupure de courant). Pour une base de données, l'équipe ajoute sa propre sauvegarde logique, ou gèle le système de fichiers (`fsfreeze`) autour de l'instantané depuis la VM cliente : la Plateforme ne peut pas le faire pour elle.
- **Chaîne rompue** : si `sauv-J-1` a été supprimé à la main, l'export de J part en complet (le script le détecte et le journalise), le RPO n'est pas dégradé. Si un incrémental manque dans PBS (purge, échec non corrigé), seule la restauration à une date **antérieure** au trou reste possible jusqu'au complet suivant.
- **Rétention** : tâche de purge PBS de `par1` : au moins 14 quotidiennes et 8 hebdomadaires ; une restauration à J-n a besoin du complet du dimanche précédent et de tous les incrémentaux jusqu'à J-n, d'où 14 jours minimum.

## Restaurer un volume à J-n

1. `proxmox-backup-client snapshot list --ns par1/ceph` puis `catalog dump` des sauvegardes `host/ceph-par1-rbd` de J-n et des jours précédents jusqu'au dernier complet ;
2. `proxmox-backup-client restore … rbd.pxar <dossier> --keyfile <clé>` pour chacune ; vérifier `MANIFESTE.tsv` (sommes de contrôle) ;
3. `rbd create --size <taille> <pool>/restau-<image>` (taille dans `rbd info` de l'original ou `MANIFESTE.tsv`) ;
4. `rbd import-diff <complet> <pool>/restau-<image>`, puis chaque incrémental **dans l'ordre** (chacun vérifie que l'image est à l'état de départ attendu et crée l'instantané de fin) ;
5. vérifier (`rbd export …@sauv-<J-n> - | sha256sum` contre la somme notée à l'origine ou contre l'original s'il existe), puis remettre en service sous le bon nom, ou rendre à l'équipe ;
6. supprimer les copies de travail (`shred` n'a pas de sens sur un SSD : supprimer le dossier et compter sur le chiffrement de PBS et des OSD).

## Configuration : ce qu'elle permet

Elle permet de **reconstruire un cluster équivalent** (spécifications cephadm, configuration centrale, règles et pools, identités cephx avec leurs clés pour que les clients existants s'authentifient), pas de retrouver les données : celles-ci reviennent par les exports RBD. Elle exclut volontairement le magasin clé-valeur des moniteurs (clés LUKS des OSD, clé SSH de cephadm, secrets des modules) : inutile sans les disques, et c'est le contenu le plus sensible du cluster.

## Comparaison : export complet quotidien vers PBS

Exporter chaque jour l'image complète en `.img` vers PBS : PBS découpe en blocs de 4 Mio et ne stocke que les blocs nouveaux (déduplication), chaque sauvegarde est restaurable seule (pas de chaîne). Mais chaque nuit relit **toute** l'image dans le cluster et la transfère jusqu'au client de sauvegarde (le client PBS n'envoie pas les blocs déjà connus, il doit quand même les lire) : acceptable pour quelques dizaines de Gio, pas pour plusieurs To. Retenu : les incrémentaux, qui ne lisent que ce qui a changé ; à revoir si la chaîne pose problème en exploitation.

# RB-131 — Restaurer Harbor

| | |
|---|---|
| Quand | perte ou corruption de `reg01` (base, `/data`), ou essai périodique sur une VM jetable |
| Durée | `<RTO mesuré>` (dernier essai : `tests/restauration-harbor.md`) |
| Prérequis | sauvegarde `host/reg01` dans `par1/registre` ; clé de chiffrement de `reg01` et jeton PBS en Vault `critique` ; RB-130 (installer Harbor) |
| Risques | écrase les données de la cible ; une instance restaurée a les robots et politiques de production |

## Décider

1. Harbor ne démarre plus mais `/data` est intact ? → **RB-135** d'abord (réparer est plus rapide que restaurer).
2. Une image ou un projet supprimés par erreur ? → la restauration complète ramène **toute** l'instance à la veille : préférer une restauration sur une VM jetable, puis la copie de l'image par `skopeo copy --all` (ou une réplication *pull* ponctuelle) vers `reg01`.
3. Perte de `reg01` → restauration complète ci-dessous, sur `reg01` reconstruite.

## Restaurer

1. **Cible prête** (RB-130) : VM par OpenTofu, rôles `docker_engine`, `certificats_acme`, `harbor` dans **la version de la sauvegarde** (`versions.txt` de l'archive `base`) ; Harbor démarre vide.
2. **Outillage** : rôle `sauvegarde_harbor` en mode `restauration` (`host_vars/<cible>/sauvegarde_harbor.yml`) : client PBS, clé de chiffrement de `reg01`, jeton de lecture, script `wb-restaurer-harbor.sh`.
3. **Choisir la sauvegarde** :
   ```
   root@<cible>:~# source /etc/wb-backup/pbs-<cible>.env && export PBS_REPOSITORY PBS_PASSWORD PBS_FINGERPRINT
   root@<cible>:~# proxmox-backup-client snapshot list --ns par1/registre
   ```
4. **Restaurer** (arrête Harbor, restaure blobs et clés, remet le certificat **de la cible** dans `secret/cert/`, base seule, `pg_restore`, désactive les réplications, redémarre) :
   ```
   root@<cible>:~# wb-restaurer-harbor.sh --instantane host/reg01/<date> --je-sais-ce-que-je-fais
   ```
5. **Vérifier** : liste de `tests/restauration-harbor.md`.
6. **Si la cible remplace `reg01`** : réactiver les politiques de réplication par le code (`tofu apply` de l'état `registre`), relancer l'analyse complète (base de Trivy fraîche), vérifier la sonde `ms-verif-registre`, prévenir les équipes (les images poussées après la sauvegarde sont **perdues** : les republier par leurs pipelines).
7. **Si c'était un essai** : supprimer `*.avant-restauration`, retirer la clé de `reg01` et le jeton de lecture de la cible, reconstruire la cible vide ou la détruire.

## Pièges

- Version de Harbor différente entre source et cible : refus du script (le schéma de base doit correspondre).
- `secretkey` non restaurée : robots et projets fonctionnent, mais les identifiants des endpoints sont illisibles.
- Politiques de réplication restaurées actives : la cible pousse vers la production (ou vers elle-même) à l'heure dite.
- `secret/cert/` restauré tel quel sur une autre machine : le proxy présente le certificat de la source (nom de `reg01` sur `reg02`) ; le script recopie celui de la cible par `harbor-recharger-certificat`.
- Blobs plus anciens que la base : `blob unknown` au tirage — refaire la restauration avec la même sauvegarde pour les deux.

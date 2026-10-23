# Final F4 — Phase 4 : Bilan (corrigé)

> ⚠️ Corrigé : à n'ouvrir qu'après avoir cherché. Solution de référence ; fichiers dans [`fichiers/S14/`](fichiers/S14/).

**Points non testés en conditions réelles** : protection d'une sauvegarde PBS par `pvesh set …/content/<volid> --protected 1` depuis `pve01` (à vérifier sur ta version ; l'interface de PVE propose aussi « Protéger ») ; `tofu state rm` sur une instance d'un `for_each` (forme exacte de l'adresse entre apostrophes) ; durée de `shred` sur un volume LVM-thin de 8 Gio (quelques minutes).

---

### F4-S14 — Revue des changements et décommissionnement

**Solution**

Fichiers : [`S14/medisphere/docs/changements/`](fichiers/S14/medisphere/docs/changements/) (`revue-trimestre.md` structure de référence, `runbooks/RB-347-…`, `fiches/CHG-3414.md`, `adr/ADR-0340-avenir-legacy-rdv.md`), [`S14/pve01/decommissionner-legacy-rdv01.sh`](fichiers/S14/pve01/decommissionner-legacy-rdv01.sh), [`S14/infra/envs/f4-infoger/LISEZMOI-S14.md`](fichiers/S14/infra/envs/f4-infoger/LISEZMOI-S14.md).

1. **Revue** : pour chaque fiche, ce qui était écrit (fenêtre, interruption promise, retour arrière) face à ce qui a été mesuré ; les chiffres viennent de la sonde de S02 sur la fenêtre réelle (`increase` des secondes en erreur entre le début et la fin du changement). Un no-go (Kubernetes bloqué par Cilium) est un résultat du processus, pas un échec. Leçons formulées comme des mécanismes (« la fiche d'inventaire du prestataire n'était pas la source de vérité »), actions avec un responsable et une date.
2. **Politique de conservation** proposée et validée par Sophie : sauvegarde finale de `legacy-rdv01` conservée **3 ans** sur `pbs-par2` (site PAR2), protégée contre l'élagage, restaurable par `plateforme-admins`, expiration inscrite au calendrier de l'équipe (à adapter à ta propre analyse : obligations de conservation du dossier médical, finalité, minimisation RGPD — c'est un choix argumenté, pas une valeur réglementaire unique).
3. **Décommissionnement** (CHG-3414, RB-347), sur `pve01` :
   ```
   root@pve01:~# ./decommissionner-legacy-rdv01.sh sauvegarde --conserver-jusqu-au <AAAA-MM-JJ>
   root@pve01:~# ./decommissionner-legacy-rdv01.sh essai
   root@pve01:~# ./decommissionner-legacy-rdv01.sh effacer
   ```
   puis le **code** (MR `plateforme/infra`, voir `LISEZMOI-S14.md`) :
   ```
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu state rm 'proxmox_virtual_environment_vm.infoger["legacy-rdv01"]'
   admin@adm01:~/src/infra/envs/f4-infoger$ tofu plan     # seulement NetBox et DNS de legacy-rdv01 détruits
   ```
   (`apply` par le pipeline), répartiteurs (`legacy_rdv_cible: k8s` seule, cible `vm` retirée), `group_vars/env_f4/infoger.yml`, sonde de `mon01`, travail PBS `f4-infoger` réduit à `3402,3403` (`pvesh set /cluster/backup/f4-infoger --vmid 3402,3403`), exceptions EXC-H-034 (pour 3401) et EXC-H-035 closes ; puis :
   ```
   root@pve01:~# ./decommissionner-legacy-rdv01.sh detruire
   root@pve01:~# ./decommissionner-legacy-rdv01.sh export
   ```
   Les preuves (`/root/decommissionnement-legacy-rdv01/journal.txt` et son empreinte) sont jointes à CHG-3414 : elles ne contiennent aucune donnée de santé (commandes, résultats, sommes).
4. **ADR-0340** : options A (maintien), B (migration des cabinets vers MédiAgenda), C (réécriture) ; décision de référence : B, avec A borné à 12 mois en maintenance de sécurité seulement.
5. **Étiquette** `changements-v1` sur `plateforme/medisphere` une fois tout sur `main` et `lab/bin/check F4 1` à `F4 14` verts (S11 : panne annulée ou réparée).

**Explications**
Un serveur qui a porté des données de santé ne se « supprime » pas : on garde **une** copie maîtrisée (sauvegarde finale protégée, durée écrite, restauration prouvée), on détruit **toutes** les autres, et on le prouve. Sur LVM-thin, supprimer un volume rend ses blocs au pool sans les effacer ; `blkdiscard` les désalloue (lectures à zéro) mais ne garantit rien sur le support physique selon le *passdown* du pool et le SSD : réécrire le volume puis vérifier des échantillons est la preuve la plus simple à fournir. La VM d'essai et l'export de migration portent les mêmes données : même traitement. Le code suit : la VM sort de l'état sans être détruite par OpenTofu (`prevent_destroy` protège les deux autres VMs de la même ressource), puis les enregistrements NetBox et DNS partent par `apply`.

**Alternatives**
- Garder la VM **arrêtée** quelques semaines au lieu de la supprimer : acceptable avec une décision écrite et une date (le check l'accepte), mais c'est une copie de plus à surveiller.
- Chiffrement des disques dès l'import (LUKS dans l'invité ou stockage chiffré) : l'effacement devient la destruction de la clé (*crypto-shredding*), immédiat et prouvable ; non disponible ici (disques importés en clair).
- Sauvegarde finale **hors PBS** (export chiffré `age` vers `s3-01`, compartiment à rétention verrouillée) : indépendante de PBS, mais restauration plus longue.

**Pièges classiques**
- Supprimer la VM avant d'avoir **restauré** la sauvegarde finale (une sauvegarde jamais restaurée n'est pas une sauvegarde).
- Laisser la sauvegarde finale non protégée : l'élagage du travail PBS la supprime à la prochaine passe (`keep-daily=7`).
- Oublier l'export d'InfoGér, la VM d'essai, les vidages de `/var/backups/infoger/` (dans le disque : effacés avec lui).
- `tofu apply` après avoir retiré la VM du `for_each` sans `state rm` : `prevent_destroy` bloque tout le plan (bien), ou, si quelqu'un l'a retiré, OpenTofu détruit la VM **avant** l'effacement.
- Une revue qui nomme des personnes (« Lucas a cassé… ») au lieu de mécanismes (« une consigne d'un tiers a été appliquée sans relecture »).

**En production chez MédiSphère**
Le décommissionnement est un pipeline (job manuel protégé) qui refuse de détruire tant que la sauvegarde finale protégée n'est pas vérifiée ; l'expiration des sauvegardes finales est suivie par un tableau de conformité ; la revue trimestrielle est présentée au comité HDS avec les chiffres de la sonde.

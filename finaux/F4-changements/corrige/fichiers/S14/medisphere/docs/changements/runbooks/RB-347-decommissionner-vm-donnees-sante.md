# RB-347 — Décommissionner une VM porteuse de données de santé

> Générique ; appliqué à `legacy-rdv01` (3401) par CHG-3414 (F4-S14). Outil de référence :
> `decommissionner-legacy-rdv01.sh` (étapes `sauvegarde`, `essai`, `effacer`, `detruire`, `export`).

## Conditions préalables (go)
- Le service est servi ailleurs depuis au moins la durée de garde convenue (48 h pour Legacy-RDV) et le retour arrière est officiellement clos (fiche du changement précédent).
- **Inventaire des copies** : disque(s) de la VM, instantanés Proxmox, sauvegardes PBS existantes, vidages locaux (ex. `/var/backups/infoger/`), exports de migration (`import/infoger-export/`), clones et restaurations d'essai, copies sur des postes. Chacune a un sort écrit.
- Politique de conservation **validée par la RSSI** : durée, lieu (`pbs-par2`, site PAR2), protection contre l'élagage, qui peut restaurer, date d'expiration et qui supprime à l'expiration.

## Étapes
1. **Sauvegarde finale**, VM **arrêtée** (cohérence), vers PBS, avec une note qui dit « finale, protégée, jusqu'au … » ; **protection** de la sauvegarde (`pvesh set /nodes/<nœud>/storage/<pbs>/content/<volid> --protected 1`) ; vérification (`pvesm list`, attribut protégé).
2. **Restauration d'essai** sur un VMID jetable, réseau coupé (`link_down=1`) : la base démarre et répond. Puis effacement **et** suppression de la VM d'essai (elle porte les mêmes données).
3. **Effacement** des disques de la VM : sur LVM-thin, supprimer le volume ne réécrit rien (les blocs reviennent au pool et peuvent rester lisibles par un autre volume tant qu'ils ne sont pas réécrits) : on **réécrit** le volume (une passe aléatoire, une passe de zéros, `shred -n 1 -z`) puis on **prouve** (lecture d'échantillons au début, au milieu et à la fin : tout est nul). `blkdiscard` seul ne garantit rien sur le support physique (dépend du *passdown* du pool et du SSD).
4. **Code et référentiels** : retrait de l'état OpenTofu sans destruction (`tofu state rm`), objets NetBox et DNS détruits par `tofu apply`, répartiteurs, supervision (sondes, cibles), journaux, travail de sauvegarde, inventaire Ansible (suit NetBox), registre des exceptions (closes), pare-feu (flux retirés).
5. **Suppression** de la VM (`qm destroy <vmid> --purge 1 --destroy-unreferenced-disks 1`).
6. **Autres copies** : export de migration effacé (`shred -z -u`), vidages et copies de travail effacés, preuves recueillies.
7. **Preuves** : journal horodaté des commandes et de leurs résultats (sans aucune donnée de santé), empreinte du journal, jointes à la fiche ; date d'expiration de la sauvegarde finale inscrite au calendrier de l'équipe (rappel).

## À l'expiration de la conservation
Retrait de la protection, suppression de la sauvegarde finale, `garbage collection` du datastore, mention dans la fiche (qui, quand).

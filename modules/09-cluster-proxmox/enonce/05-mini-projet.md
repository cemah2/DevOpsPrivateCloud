# Module 09 — Palier 5 : Mini-projet

Le cluster `hv-par1` a été construit exercice après exercice : installé sans clavier, formé, arbitré, agrandi, doté de Ceph puis monté en Tentacle, de la HA et de ses règles, de la réplication, des sauvegardes, du SDN, de droits, d'un pare-feu, de certificats, d'une sonde, de runbooks. Mais il porte aussi les traces de son histoire : des réglages faits à la main un soir de panne, des décisions prises en cours de route et jamais reportées dans le code, un Ceph installé en Squid. La preuve qu'une plateforme est maîtrisée, c'est qu'on sait la **reconstruire** : depuis le code, sans mémoire humaine, en un temps connu. Ce mini-projet livre « virtualisation MédiSphère v1 » : le cluster détruit, reconstruit depuis le code et chronométré, recetté par l'équipe, puis retiré proprement pour rendre la mémoire de `pve01` aux modules suivants.

---

### M09-E46 — Mini-projet : virtualisation MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1090** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du cluster de virtualisation dans deux semaines. Je ne veux pas voir le cluster que tu as monté pendant deux mois : je veux voir **un cluster neuf**, reconstruit devant nous depuis le dépôt, et savoir combien de temps ça prend. Karim lira le code et le chronométrage, Sophie vérifiera pare-feu, double authentification, certificats et secrets, Nadia testera la perte d'un nœud avec ses runbooks, Julien demandera une VM et voudra savoir où elle va. Format habituel : 10 minutes de présentation, la démonstration, nos questions. Après la recette, on libère `pve01` : le cluster est détruit, et rien ne doit traîner sur `pbs01`.

**Objectifs pédagogiques**
- Prouver que le cluster est entièrement décrit par le code (OpenTofu, fichier de réponse, Ansible) en le reconstruisant de zéro, et mesurer ce temps.
- Livrer un cluster de production complet : trois nœuds, Ceph Tentacle, HA avec règles, réplication, sauvegardes testées, SDN, droits, sécurité, supervision, documentation.
- Retirer proprement un environnement et ses dépendances (PAR2 compris), et documenter ce qui est conservé.

**Prérequis** : M09-E01 à M09-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; mini-projets M06-E46 (`socle-v1`), M07 (`socle-v2`) et M08 (`stockage-v1`).
**Durée indicative** : 16 à 24 h, plus 30 min de revue.

**Contexte technique**
- Cluster `hv-par1` : nœuds `hv01-03` (2091-2093), adresses et réseaux de PLAN §4.9, Proxmox VE 9.2 par l'installateur automatique, VIP 10.10.10.200 `hv.par1.medisphere.internal` (VRID 110). Ceph hyperconvergé **installé directement en Tentacle** dans la v1 (la montée Squid → Tentacle d'E28 reste documentée : c'était un exercice de maintenance, pas un état cible). Pas de QDevice (trois nœuds).
- Code : `plateforme/infra` (états `hv` et `hv-invites`), `plateforme/ansible` (rôles `pve_noeud`, `pve_cluster`, `pve_pare_feu`, `sauvegarde_pbs`, `certificats_acme`… et leurs playbooks), `plateforme/outils` (`ms-verif-cluster`, `ms-capacite-cluster`). Le stockage externe `ceph-par1-rbd` (E12) ne fait **pas** partie de la v1 : le pool `hv-par1` et le client `client.hv-par1` ont été supprimés de `ceph-par1` à la fin d'E12, et `ceph01-03` restent arrêtées.
- Sauvegardes : `pbs01`, datastore `ds-lab`, espace de noms `par1/hv`, jeton du cluster et clé de chiffrement d'E15 (Vault `critique`).
- Documentation : `plateforme/medisphere`, `docs/virtualisation/` ; étiquette de livraison `virtualisation-v1`.
- Le contrôle global `lab/bin/check 09 46` vérifie le cluster **pendant la recette** (il ne peut pas exiger à la fois le cluster et son absence). Le nettoyage d'après-recette (étape 10) est auto-évalué avec la grille du corrigé.

> ⚠️ **Attention** : (1) la destruction du cluster existant détruit aussi tout ce qui n'est **que** dans le cluster : invités imbriqués, configuration faite à la main, sauvegardes locales ; avant de détruire, vérifie que chaque invité à conserver a une sauvegarde PBS **restaurée avec succès au moins une fois**, et que la clé de chiffrement est dans Vault et sur papier ; (2) la destruction passe par le code (`tofu destroy` ciblé sur l'état `hv`, plan relu : uniquement 2091-2093) ; (3) toute action sur `pbs01` est annoncée, faite à la main avec une commande de retour arrière notée, jamais par un script de panne.

**Travail demandé**
1. **Inventaire des écarts.** Liste tout ce qui, dans le cluster actuel, n'est pas décrit par le code : comparer la configuration réelle (`/etc/pve`, `pvesh`, nœuds) à ce que produisent tes rôles et tes états. Chaque écart est corrigé dans le code, ou documenté comme volontairement manuel (avec sa raison et son runbook).
2. **Préparer la reconstruction.** Une seule procédure, outillée (un Taskfile ou un pipeline), qui enchaîne : VMs des nœuds, installation automatique, configuration des nœuds, cluster, Ceph Tentacle, sécurité (pare-feu, SSH, certificats), sauvegardes, SDN, droits, HA et règles, réplication, supervision, invités durables. Chaque étape est horodatée dans un journal ; aucune ne demande de saisie au clavier, hors validation d'un plan dans une MR.
3. **Sauvegarder pour reconstruire.** Sauvegardes PBS à jour des invités à conserver (au minimum : une VM HA de « production » sur `ceph-vm` et une VM répliquée sur `zfs-local`), sauvegarde de configuration des nœuds (E29), puis **test de restauration** de l'une d'elles sur le cluster actuel (VMID libre), consigné.
4. **Détruire et reconstruire, chronomètre en main.** Destruction des trois nœuds par le code, puis reconstruction complète par ta procédure. Les invités durables sont restaurés depuis PBS (ou recréés par `hv-invites` s'ils sont sans état). Le temps total et le temps de chaque étape vont dans `docs/virtualisation/tests/reconstruction-hv-par1.md`, avec chaque geste manuel et sa raison.
5. **Recette fonctionnelle.** Sur le cluster reconstruit, rejoue en les chronométrant : une migration à chaud sur le réseau de migration ; une perte de nœud (arrêt brutal, E24) avec RTO mesuré ; un basculement de réplication ; une restauration PBS ; une montée de version mineure d'un nœud selon RB-092 si une mise à jour est disponible (sinon, la procédure à blanc jusqu'à `apt full-upgrade -s`). Résultats dans le même document.
6. **Sécurité.** Pare-feu de cluster actif (matrice à jour), TOTP pour les humains, certificats de la PKI sur les nœuds et la VIP, SSH sans mot de passe, comptes et jetons revus (aucun jeton sans motif, chaque jeton dans le registre des secrets avec sa portée et son échéance).
7. **Supervision et capacité.** `ms-verif-cluster` au vert et branchée sur `ms-alerte@` ; `ms-capacite-cluster` intégré à la revue de capacité ; un tableau des indicateurs que le module 21 devra collecter.
8. **Documentation.** `docs/virtualisation/hv-par1.md` (architecture, réseaux, stockages, HA, sauvegardes, sécurité, dépendances au socle, ce qui se passe quand chaque composant tombe, points uniques de défaillance restants, liens vers les runbooks) ; RB-090, RB-091, RB-092 et les runbooks du palier 4 à jour ; ADR-0090 ; matrice des flux du cluster et matrice de la bordure à jour ; registre des secrets complété.
9. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, aucune panne `M09` n'est active, `lab/bin/check 09 46` est vert, l'étiquette `virtualisation-v1` est posée sur `plateforme/medisphere` par un commit qui documente la livraison.
10. **Après la recette : nettoyage.** Destruction du cluster par le code (VMs 2091-2093, objets NetBox, enregistrements DNS, entrées de supervision), `pbs01` remis dans son état d'avant module (`corosync-qnetd` désinstallé s'il ne l'a pas été en E08, règles de pare-feu ajoutées pour lui retirées, port 5403 refermé dans la matrice de la bordure), décision **écrite** sur l'espace de noms `par1/hv` (purgé ou conservé, avec quelle rétention, pour quel usage, et où est la clé). Le cluster pourra être reconstruit au besoin par la même procédure (workbooks finaux).

**Contraintes**
- La reconstruction ne s'appuie sur **aucun** reste de l'ancien cluster (pas de copie de `/etc/pve`, pas de clé d'hôte réutilisée) ; seules les sauvegardes PBS des invités et les secrets de Vault traversent.
- Aucun secret dans un dépôt, un journal de CI, le journal de reconstruction ou la documentation.
- Toute action manuelle pendant la reconstruction est consignée et devient une action corrective (code ou runbook).
- La mémoire de `pve01` reste dans le budget du profil infra (`ceph01-03` arrêtées pendant tout le mini-projet).

**Critères de réussite**
- [ ] `lab/bin/check 09 46` est entièrement vert pendant la recette.
- [ ] Le journal de reconstruction montre une reconstruction complète depuis le code, chaque étape horodatée, avec le temps total et la liste des gestes manuels (idéalement : aucun).
- [ ] Les essais de recette (migration, perte de nœud, réplication, restauration, mise à jour) sont consignés avec leurs mesures.
- [ ] La documentation dit ce qui n'est **pas** encore redondant ou automatisé, et ce que les modules suivants traiteront.
- [ ] Après la recette, le nettoyage est fait et la décision sur `par1/hv` est écrite (auto-évaluation, grille du corrigé).

**Vérification** : `lab/bin/check 09 46` (pendant la recette, avant le nettoyage).

<details><summary>Indice 1</summary>

Lance `lab/bin/check 09 46` dès le début, sur le cluster actuel : la liste des points rouges est ton plan de travail pour l'étape 1. Les contrôles des exercices (`lab/bin/check 09 XX`) donnent le détail par brique.
</details>

<details><summary>Indice 2</summary>

Fais une **répétition** de la reconstruction avant la vraie, et note chaque endroit où tu as dû intervenir : chacun est un défaut du code ou d'un runbook. Une reconstruction qui demande trois corrections en direct n'est pas une reconstruction depuis le code. Les étapes longues (installation, récupération Ceph) laissent du temps pour vérifier les précédentes.
</details>

<details><summary>Indice 3</summary>

Ce qui casse le plus souvent une reconstruction : l'ordre (Ceph avant le pare-feu ? la VIP avant les certificats ?), une version de paquet différente entre deux nœuds, une valeur codée en dur qui désignait l'ancien cluster (empreinte de certificat, identifiant Ceph, clé d'hôte SSH connue), un secret qui n'était que sur l'ancien nœud. Pour chaque étape, demande-toi : « d'où vient cette valeur, et existe-t-elle avant que l'étape tourne ? »
</details>

**Pour aller plus loin** (facultatif) : faire tourner la reconstruction entière par le pipeline de `plateforme/infra`, déclenché par une étiquette ; mesurer la reconstruction sur une semaine (trois essais) et publier la médiane ; préparer le workbook F1 (« Day 0 ») qui reconstruira le cluster avec le reste de la plateforme.

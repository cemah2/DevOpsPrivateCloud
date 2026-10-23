# Final F1 — Phase 2 : Socle et usine

Avant de détruire six nœuds, on s'échauffe sur deux VMs du socle dont la perte ne coûte rien, parce qu'elles ont une jumelle : `lb02` et `dns02`. Si le code ne sait pas les refaire sans une main humaine, il ne saura pas refaire un cluster. Puis l'usine de provisioning du M11 apprend à installer un nœud Kubernetes, pour que `k8s-w03` renaisse en phase 3 comme un serveur sorti du carton.

---

### F1-S05 — Reconstruire `lb02` et `dns02` depuis le code  `LIBRE` `★★★`

> **Changement CHG-3105** — *De : Karim Benali* — *Copie : Claire Morel, Nadia Roussel*
> Répétition générale sur le socle. `lb02` et `dns02` sont redondantes : leur jumelle tient le service pendant qu'on les refait. Je veux qu'on les détruise pour de vrai et qu'elles reviennent par OpenTofu et la CI, avec tout ce qu'une VM du socle doit avoir : annuaire, durcissement, supervision, journaux. Zéro geste à la main, sauf ceux qu'on aura listés avant de commencer comme dette connue. Et je veux les temps : c'est notre premier vrai chiffre de reconstruction.

**Objectifs pédagogiques**
- Détruire et reconstruire une VM du socle par le code, à travers les garde-fous mis en place pour l'en empêcher.
- Faire revenir une VM dans tous ses rattachements (annuaire, certificats, supervision, conformité, inventaire) sans geste caché.
- Préserver la continuité de service grâce à la redondance, et le prouver.
- Mesurer une reconstruction et en extraire la dette.

**Prérequis** : F1-S01 à F1-S04 ; M06 (`dns02`, PowerDNS secondaire, Kea en *hot-standby*), M07 (`lb01`/`lb02`, keepalived, HAProxy, ACME), M21-M22 (`node_exporter`, `alloy`), M24 (inscription FreeIPA), M26 (rôle `durcissement`, conformité), M29 (règles conftest sur les plans).
**Durée indicative** : 5 à 7 h.

**Contexte technique**
- `lb02` : VMID **1011**, 10.10.70.11 (DMZ, VNet `vdmz`), état `socle` (`socle/repartiteurs.tf`, module `vm-debian`), étiquettes `socle` et `role-lb`. Secours VRRP de la VIP 10.10.70.200 (VRID 170, `nopreempt`), `lb01` maître.
- `dns02` : VMID **1008**, 10.10.20.16 (VNet `vinfra`), état `socle` (`socle/dns02.tf`), étiquettes `socle` et `role-dns`. Autoritaire secondaire (AXFR/NOTIFY signés TSIG `axfr-par1`), récurseur, Kea de secours (HA *hot-standby* avec `dns01`).
- Garde-fous en place, à respecter et non à contourner : règles conftest de `plateforme/politiques` sur les plans de `plateforme/infra` (une destruction de VM du socle exige une décision visible, M29), contrôle des destructions dans le job de plan s'il est encore là (M05-E46), registre des exceptions.
- L'annuaire refuse d'inscrire un hôte dont l'entrée existe déjà avec un *keytab* (rôle `freeipa_client`, M24-E19).
- Ordre de démarrage Proxmox des VMs du socle : posé à la main en root après création (commentaire de `socle/dns02.tf` et `socle/repartiteurs.tf`).
- Les certificats d'hôte SSH, les certificats ACME et les clés d'hôte changent avec la VM : pense aux postes et aux runners qui les ont mémorisés.

**Travail demandé**
1. **Avant** : liste dans la fiche `docs/day0/changements/CHG-3105-lb02-dns02.md` les gestes que tu sais encore manuels (ce sont la dette connue), l'ordre, les contrôles de redondance (la jumelle porte seule le service) et le retour arrière (restauration PBS de la VM du socle).
2. **`lb02` d'abord** : détruis-la et recrée-la par OpenTofu (état `socle`) et la CI, puis configure-la par les pipelines de `plateforme/ansible` : tout ce qu'elle avait (répartiteur, VRRP en secours, certificats, durcissement, inscription à l'annuaire, supervision, journaux, conformité). Vérifie que la VIP n'a jamais quitté `lb01`.
3. **`dns02` ensuite**, seulement quand `lb02` est entièrement revenue : même chose, avec les zones secondaires au même numéro de série que `dns01`, le récurseur, Kea de secours revenu en HA.
4. Chronomètre chaque étape (création, premier SSH, chaque playbook, retour complet) et note chaque intervention qui n'était pas listée.
5. Écris `docs/day0/reconstruction-socle.md` : déroulé réel, durées mesurées, gestes manuels (prévus ou découverts) inscrits comme **dette** avec un ticket chacun, écarts au plan.

**Contraintes**
- Une VM à la fois ; la seconde ne commence qu'avec la première revenue et vérifiée.
- Aucune interruption de la résolution DNS du lab ni des points d'entrée publiés.
- Création et configuration par les pipelines ; une exception est listée dans la fiche **avant** d'être faite.
- Aucun garde-fou désactivé « le temps de » : s'il bloque, il se lève par la voie prévue, tracée.

**Critères de réussite**
- [ ] `lb02` et `dns02` ont été recréées (instances nées après le début de la phase 1), dans le pool `lab`, avec leurs VMID, adresses et étiquettes.
- [ ] `lb02` est en secours VRRP, `lb01` porte la VIP, HAProxy de `lb02` est valide et actif ; les noms publiés répondent.
- [ ] Les zones de `dns02` ont le même numéro de série que celles de `dns01`, son récurseur répond, son Kea est actif.
- [ ] Les deux VMs sont inscrites dans l'annuaire, supervisées (`node_exporter`), et ont un score de conformité calculé après leur reconstruction.
- [ ] `reconstruction-socle.md` est sur `main`, avec les durées et la dette.

**Vérification** : `lab/bin/check F1 5`

<details><summary>Indice 1</summary>

Avant de détruire, fais la liste de tout ce qui « connaît » la VM ailleurs qu'en elle-même : NetBox, DNS, annuaire, certificats, `known_hosts`, supervision, sauvegardes, matrice des flux. Chaque entrée de la liste est soit recréée par le code, soit un geste manuel à écrire.
</details>

<details><summary>Indice 2</summary>

Le pipeline de `plateforme/infra` n'a pas de bouton « remplacer ». Il y a plusieurs façons d'obtenir une destruction suivie d'une création par une MR ; choisis-en une qui reste lisible pour le relecteur et qui passe les règles de `plateforme/politiques` par leur voie prévue.
</details>

<details><summary>Indice 3</summary>

Pour l'annuaire, regarde ce que dit le rôle `freeipa_client` quand l'hôte existe déjà, et la différence entre supprimer l'hôte et le désactiver (que deviennent ses appartenances aux groupes d'hôtes et aux règles HBAC ?). Pour la conformité, l'analyse est hebdomadaire : elle ne tournera pas toute seule cette semaine.
</details>

**Pour aller plus loin** (facultatif) : refais `lb02` une seconde fois en appliquant ta propre dette corrigée, et compare les temps.

---

### F1-S06 — L'usine prépare un nœud Kubernetes  `LIBRE` `★★★★`

> **Ticket PLAT-3106** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> Le jour où on aura du vrai matériel, les nœuds Kubernetes ne seront pas des clones d'une image dorée : ils sortiront du carton et passeront par l'usine du M11. Je veux qu'on le prouve pendant la reconstruction : `k8s-w03` renaîtra par la chaîne NetBox → PXE → installation, sur le VLAN 60, puis rejoindra le VLAN 40 et le cluster. Avant d'y toucher, ajoute à l'usine un profil de nœud Kubernetes, essaie-le sur une machine jetable, et prépare le code de `k8s-w03` sans rien changer au cluster qui tourne. Sophie demandera qui peut allumer quoi avec le jeton de l'usine.

**Objectifs pédagogiques**
- Étendre une chaîne de provisioning existante d'un nouveau profil, sans régression pour les profils existants.
- Concilier deux identités réseau d'un même serveur : celle d'installation (VLAN 60) et celle de service (VLAN 40).
- Décrire dans OpenTofu un nœud installé par l'usine plutôt que cloné, et sa bascule de réseau.
- Limiter les droits de l'automatisation au strict nécessaire et le tracer.

**Prérequis** : F1-S01 à F1-S04 ; M11 (usine : `plateforme/provisioning`, rendu NetBox, preseed, iPXE, `outils/provisionner.py`, compte `wb-provision`), M14 (état `envs/k8s`, règle d'adressage des nœuds, rôles `containerd`, `k8s_noeud`…), M16 (carte de stockage des travailleurs, rôle `k8s_reseau_stockage`), M29 (plages de VMID des politiques).
**Durée indicative** : 6 à 8 h (dont 20 à 40 min d'installation par essai).

**Contexte technique**
- Usine (M11) : `pxe01` (2111, 10.10.60.10), VLAN 60 (`vprov`), Kea (sous-réseau `id: 60`, plage 10.10.60.100-199, réservations rendues depuis NetBox), iPXE construit avec la racine MédiSphère, HTTPS de bout en bout, fichiers de réponse rendus par `outils/netbox-provision.py`, orchestrateur `outils/provisionner.py` (job manuel `provisionner`, variable `EQUIPEMENT`), statuts NetBox `planned` → `staged` → `active`, champ `pxe_action`. Aujourd'hui, l'usine ne connaît que des **équipements** du rôle `serveur-bm`.
- Nœuds de `k8s-par1` (M14) : VMs **clonées** par le module `vm-noeud` (état `envs/k8s`), déclarées dans NetBox comme **machines virtuelles** (étiquettes `env-k8s`, `role-k8s-cp` / `role-k8s-worker`), lues par l'inventaire `inventories/lab/netbox-k8s.yml` (VMs `active`). Règle d'adressage : suffixe = dernier octet ; VLAN 40 en `10.10.40.<suffixe>`, MAC `bc:24:11:40:00:<suffixe>` ; carte de stockage des travailleurs `10.10.30.<suffixe+20>` (M16). Dans l'invité : cartes `eth0`, `eth1`, netplan (systemd-networkd).
- `k8s-w03` : VMID **2146**, 10.10.40.63, travailleur (taint `dedie=bdd:NoSchedule`, M14). **Il reste en service pendant toute la phase 2** : le cluster n'est détruit qu'en phase 3 (S07).
- Profil à créer : **`k8s-noeud`** (nom imposé : S07 et les checks l'emploient).
- Machine d'essai : VMID **3101** `f1-usine-essai`, VLAN 60, MAC `02:4d:53:60:31:01`, dans un état OpenTofu du final (`envs/f1`, plage 3100-3199, étiquette `env-f1`) ; elle est **détruite** à la fin de l'essai.
- Compte de l'orchestrateur : `wb-provision@pve!provision`, rôle `WBProvision` limité aujourd'hui aux VMs 2112-2115.
- Mémoire : `pxe01` (1 Go) et la machine d'essai (2 Go) en plus du profil de travail ; rien d'autre de temporaire en même temps.

**Travail demandé**
1. **Le profil** : ajoute à `plateforme/provisioning` un profil `k8s-noeud` (plate-forme NetBox du même nom) qui installe un Debian 13 conforme à ce que les rôles Kubernetes attendent d'un nœud cloné (disque, réseau, comptes, racine de la PKI, agent, nom). Ce qui relève des rôles Ansible n'est pas dupliqué dans l'installateur. Les profils existants (`serveur-bm`) restent inchangés, tests compris.
2. **Deux adresses** : décide comment NetBox porte l'adresse d'installation (VLAN 60, réservée) et l'adresse de service (VLAN 40) d'un même nœud, et adapte le rendu (fichiers de réponse, scripts iPXE, réservations Kea) et l'orchestrateur en conséquence. Écris la décision.
3. **L'essai** : crée `f1-usine-essai` par OpenTofu, déclare-la dans NetBox avec le profil, lance l'usine par son pipeline, et prouve le résultat sur la machine (démarrage, réseau, comptes, ce que ton profil promet). Chronomètre. Puis **détruis**-la par le code (VM, objets NetBox, enregistrements DNS, réservation).
4. **`k8s-w03`** : prépare dans `envs/k8s` ce qu'il faut pour qu'en phase 3 OpenTofu crée `k8s-w03` **vide, en démarrage réseau sur le VLAN 60**, puis le repasse sur le **VLAN 40** (avec sa carte de stockage) après l'installation. Le code est fusionné, mais **désactivé** : le plan de `envs/k8s` reste vide aujourd'hui.
5. **Droits** : élargis le rôle de l'orchestrateur aux seules VMs nécessaires (et retire ce qui ne sert plus après l'essai) ; mets le registre des secrets à jour.
6. **Documentation** : `docs/day0/usine-k8s.md` : le profil, la décision sur les deux adresses, l'essai chronométré, la procédure prévue pour `k8s-w03` en phase 3 (étapes, commandes de pipeline, vérifications), les droits accordés.

**Contraintes**
- Aucune modification de `k8s-w03` ni d'aucun nœud en service ; le plan de `envs/k8s` est vide après fusion.
- Les profils existants de l'usine passent toujours leurs tests et leur pipeline.
- La machine d'essai n'existe plus à la fin (Proxmox, NetBox, DNS, réservations).
- Aucun secret dans un fichier servi par `pxe01`, un dépôt ou la documentation.
- Les politiques de `plateforme/politiques` acceptent les plans de `envs/f1` par une déclaration explicite, pas par une exception générale.

**Critères de réussite**
- [ ] `plateforme/provisioning` (main) a un gabarit et des outils qui connaissent `k8s-noeud`, et son pipeline est vert.
- [ ] La plate-forme `k8s-noeud` existe dans NetBox.
- [ ] `pxe01` a servi le script iPXE et le fichier de réponse de `f1-usine-essai` ; l'installation est allée au bout et le résultat a été vérifié sur la machine.
- [ ] La VM 3101 et ses objets NetBox n'existent plus.
- [ ] `envs/k8s` (main) sait démarrer un nœud sur le VLAN 60, sans que `k8s-w03` ait été touché (toujours `Ready`).
- [ ] `docs/day0/usine-k8s.md` est sur `main`, avec l'essai chronométré et la procédure de phase 3.

**Vérification** : `lab/bin/check F1 6`

<details><summary>Indice 1</summary>

Compare un nœud cloné et un Debian installé par le preseed du M11 : nom des cartes, outil de configuration du réseau, présence de swap, agent QEMU, `cloud-init`… Chaque différence que les rôles Kubernetes remarqueraient doit être réglée par le profil, ou par un rôle qui la règle déjà.
</details>

<details><summary>Indice 2</summary>

Pour les deux adresses, plusieurs modèles tiennent : deux adresses sur la même interface NetBox (une réservée), un champ personnalisé, une règle de calcul. Choisis celui qui laisse NetBox **dire** ce qui se passe, et qui garde la même MAC dans les deux phases (réservation Kea, script iPXE par MAC).
</details>

<details><summary>Indice 3</summary>

L'orchestrateur du M11 enchaîne installation, premier démarrage et accueil. Pour `k8s-w03`, le premier démarrage ne peut pas avoir lieu sur le VLAN 60 avec une configuration du VLAN 40 : où s'arrête l'usine, qui fait la bascule (OpenTofu), et comment confirmes-tu la clé d'hôte au premier contact après la bascule ? Pour le plan vide, une variable dont la valeur par défaut ne change rien est un bon point de départ.
</details>

**Pour aller plus loin** (facultatif) : écris le test de non-régression de la chaîne (pytest sur des données NetBox simulées) qui couvre le profil `k8s-noeud` à côté des tests du M11, et ajoute un essai d'installation nocturne de `f1-usine-essai` à la façon de Terratest (M29), détruit par le test.

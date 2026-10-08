# Module 11 — Palier 5 : Mini-projet

Fin du module. La chaîne a été construite morceau par morceau : réseau de provisioning et classes PXE (palier 1), installations décrites par NetBox, contrôleurs de gestion, MAAS (palier 2), chaîne authentifiée, nœud Proxmox par le réseau, orchestration sans geste humain, inventaire matériel (palier 3), pannes et lecture sur le fil (palier 4). Il reste à la **livrer** comme un service de la plateforme : l'« usine de provisioning » qui recevra les palettes du futur datacenter. Les modules suivants en dépendent : les nœuds Kubernetes du module 14 pourront être installés par elle, et les finaux F1 (Day 0) et F5 (PRA) y feront appel pour reconstruire des serveurs.

---

### M11-E25 — Mini-projet : l'usine de provisioning  `LIBRE` `★★★`

> **Ticket PLAT-1290** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette de l'usine dans deux semaines. Pendant la revue, Julien déclarera deux serveurs dans NetBox — un ancien en BIOS qui recevra Debian, un récent en UEFI qui recevra Rocky — et lancera le pipeline : je veux les voir en service, dans le DNS et dans l'inventaire Ansible, sans que personne ne touche à rien d'autre, et je chronomètre. Sophie relira la chaîne de confiance, les comptes et les secrets ; Nadia testera RB-110 et RB-111 ; Karim fera la revue du code. Je veux aussi l'inventaire matériel de `hp01` à jour, l'ADR sur l'outil, et un lab propre : plus de MAAS, plus de VMs de test, plus de compte inutile. Format habituel : 10 minutes de présentation, la démonstration, nos questions.

**Objectifs pédagogiques**
- Livrer une chaîne de provisioning complète, pilotée par la source de vérité, authentifiée et sans geste manuel.
- Démontrer et chronométrer l'installation de serveurs BIOS et UEFI, de deux familles de systèmes, jusqu'à leur entrée en exploitation.
- Clore proprement une évaluation (MAAS) et un environnement de module, et livrer l'état attendu par les modules suivants.

**Prérequis** : M11-E01 à M11-E24 (au minimum tous les `LAB`, `LIBRE` et `BF`) ; mini-projet du module 06 (socle v1) et du module 07 (socle v2).
**Durée indicative** : 8 à 12 h (l'essentiel est déjà construit), plus 30 min de revue.

**Contexte technique**
- Hôtes : `pxe01` (2111, 10.10.60.10), `bm01-04` (2112-2115), `maas01` (2116, à détruire), template 9050 `tpl-ubuntu2404` (son sort est à décider et à justifier : il ne sert plus qu'à MAAS) ; Kea sur `dns01`/`dns02` (sous-réseau `id: 60`), relais du VLAN 60 sur `gw01`/`gw02`.
- Références : chaîne PXE (E02, E03), installateurs (E04, E05), génération depuis NetBox (E06), contrôleurs (E07, E08, E18), MAAS (E09, E10, E16), RB-110 (E12), sécurité (E13), nœud Proxmox (E14), orchestration (E15), RB-111 (palier 4).
- Si l'ADR-0110 retient MAAS, mets `WB_M11_MAAS_CONSERVE=1` dans `lab/lab.env` : le contrôle global saute alors les seuls contrôles de retrait de MAAS (la revue juge la justification).
- Le contrôle global `lab/bin/check 11 25` vérifie la chaîne (`pxe01`, Kea, relais, TFTP, HTTPS, gabarits rendus, projet et pipeline), NetBox (équipements, statuts, inventaire de `hp01`), les serveurs livrés, la documentation, puis le **nettoyage**. Il prend quelques minutes.

**Travail demandé**
1. **La chaîne.** Tout ce que sert `pxe01` est rendu depuis `plateforme/provisioning` (gabarits, scripts iPXE par MAC, preseed, kickstart, fichier de réponse PVE) et déployé par le pipeline ; le pipeline valide chaque rendu (`ksvalidator`, `debconf-set-selections -c`, scripts iPXE, ShellCheck) avant tout déploiement ; la configuration de `pxe01`, de Kea et du relais vient de `plateforme/ansible` (`changed=0` au second passage).
2. **La démonstration.** Depuis NetBox (équipement `planned` du rôle `serveur-bm`) et le seul bouton du pipeline : un serveur BIOS en **Debian 13** (`bm01`) et un serveur UEFI en **Rocky 10** (`bm04`), selon la répartition de NetBox démarrent en PXE, s'installent en HTTPS, reçoivent la racine de la PKI et leur clé d'hôte signée, apparaissent dans le DNS et dans l'inventaire Ansible, passent `active` dans NetBox, sans geste manuel. Chronomètre chaque étape et reporte les temps dans RB-110.
3. **La sécurité.** Chaîne en HTTPS vérifiée par iPXE (binaire construit par la procédure versionnée, ADR-0111) ; aucun mot de passe en clair dans un dépôt ou sur `pxe01` ; VLAN 60 isolé (matrice des flux en code et dans `docs/socle/matrice-flux.md`, identique sur les deux passerelles) ; IPMI sur IP coupé, compte `wb-redfish` minimal ; registre des secrets à jour (jeton du service de réponse PVE, jetons NetBox et Proxmox utilisés par l'orchestrateur, compte iLO : emplacement, portée, propriétaire, échéance — jamais la valeur).
4. **L'inventaire.** `hp01` dans NetBox avec numéro de série, versions du BIOS et de l'iLO lues sur l'iLO, éléments d'inventaire ; collecte hebdomadaire planifiée ; `docs/provisioning/firmware.md` à jour.
5. **La décision.** ADR-0110 acceptée, appliquée : si la chaîne maison est retenue, MAAS est retiré (voir 7) ; si MAAS est retenu, l'ADR dit comment il s'intègre à NetBox et à Kea, et le nettoyage est adapté (et justifié).
6. **La documentation.** `docs/provisioning/usine.md` : architecture (schéma du VLAN 60 et des flux), chaîne de confiance, cycle de vie d'un serveur (états NetBox, transitions, reprise), dépendances (ce qui se passe quand `pxe01`, Kea, NetBox, `ca01` ou la forge tombent), procédures et liens vers RB-110, RB-111, ADR-0110, ADR-0111, ce qui n'est **pas** encore couvert (effacement sécurisé, mise à jour des firmwares, *commissioning*, Secure Boot).
7. **Le nettoyage.** Après l'ADR : `maas01` détruite par OpenTofu (et retirée de NetBox, du DNS et de la matrice des flux) ; DHCP du VLAN 60 servi par Kea seul, relais actif ; compte `wb-maas@pve` désactivé ou supprimé avec son jeton et son rôle (choix justifié ; le compte `wb-provision` de l'orchestrateur, lui, reste) ; flux `maas01` → `pve01:8006` retiré de la bordure et du pare-feu de Proxmox ; VM 2117 détruite ; aucune panne `M11` active. Les serveurs `bm*` de la démonstration restent en service jusqu'à la revue ; ensuite, ils repassent à l'état `planned` (VMs vides recréées) ou sont détruits, selon ce que dit `usine.md`.
8. **La livraison.** Tout est fusionné, les pipelines de `main` sont verts, et l'étiquette `provisioning-v1` est posée sur `plateforme/medisphere` (commit qui documente la livraison).
9. **La revue.** 10 minutes de présentation (ce que fait l'usine, chaîne de confiance, temps mesurés, risques et limites, ce que les modules suivants consommeront), puis la démonstration de Julien avec le seul RB-110.

**Contraintes**
- Aucune interruption du DHCP du VLAN 99 ni de la résolution DNS du lab pendant la livraison, au-delà d'un redémarrage de service annoncé.
- Aucun secret dans un dépôt, un journal de CI, un fichier servi par `pxe01` ou la documentation : des **emplacements**, jamais des valeurs.
- `hp01` n'est ni réinstallé, ni redémarré, ni mis à jour dans ce mini-projet.
- Tout ce qui est créé l'est par le code (OpenTofu, Ansible, pipeline de `plateforme/provisioning`) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.

**Critères de réussite**
- [ ] `lab/bin/check 11 25` est entièrement vert.
- [ ] La démonstration installe un serveur BIOS Debian et un serveur UEFI Rocky jusqu'à l'état `active`, sans geste manuel hors de NetBox et du pipeline, en un temps mesuré et consigné.
- [ ] La documentation dit ce que l'usine ne couvre pas encore, et quel module ou quel ticket le traitera.
- [ ] MAAS et le compte `wb-maas` sont retirés (ou leur maintien est justifié par l'ADR-0110), sans reste dans la matrice des flux.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 11 25`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 11 25` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 11 XX`) donnent le détail par brique.
</details>

<details><summary>Indice 2</summary>

Répète la démonstration **avant** la recette, avec des machines remises à zéro (VMs vides recréées par OpenTofu, équipements `planned`), chronomètre-la et note chaque endroit où tu as dû intervenir : chacun est un défaut de RB-110 ou du code. Fais-la une fois en partant d'un `pxe01` reconstruit par le code : c'est ce que fera le final F5.
</details>

<details><summary>Indice 3</summary>

Le nettoyage d'une évaluation laisse toujours des traces dans des endroits qu'on ne regarde plus : enregistrement DNS, objet NetBox, ligne de la matrice des flux, IPSet ou règle du pare-feu de Proxmox, ACL et rôle Proxmox, jeton dans le registre des secrets, entrée dans `~/.ssh/known_hosts`, état OpenTofu. Fais la liste avant de détruire.
</details>

**Pour aller plus loin** (facultatif) : déclencher l'orchestrateur depuis NetBox (*event rule*) ; installer un nœud Proxmox VE dans le même pipeline (E14) ; préparer l'installation des futurs nœuds Kubernetes du module 14 (gabarit et rôle `serveur-k8s` dans NetBox).

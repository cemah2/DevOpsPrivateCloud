# Module 07 — Palier 5 : Mini-projet

Le socle v1 savait tout faire, mais sur une seule passerelle et sans point d'entrée. Le module 07 lui a donné un réseau de datacenter : deux passerelles en VRRP qui emportent avec elles les tunnels, la traduction d'adresses et la mémoire des connexions ; des répartiteurs qui publient GitLab et NetBox en TLS ; FRR prêt à recevoir les annonces de Kubernetes ; des réseaux de stockage en *jumbo frames* ; l'agence de Lyon raccordée par un tunnel routé dynamiquement. Il reste à **livrer** tout cela comme un ensemble, à détruire la maquette qui a servi à apprendre, et à prouver que la bordure tient la panne d'une passerelle. C'est l'état d'entrée de Ceph (module 08) : ses réseaux public et de réplication passent par les VLAN 30 et 31 en MTU 9000, et sa passerelle RGW sera publiée par les répartiteurs.

---

### M07-E46 — Mini-projet : socle MédiSphère v2  `LIBRE` `★★★`

> **Ticket PLAT-890** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du socle v2 dans deux semaines, devant le comité d'architecture. Je veux une bordure **sans point unique de défaillance** dans le lab (hors `pve01` lui-même, on le sait), qui passe le contrôle global sans un seul rouge, et une démonstration en direct : pendant que Julien clone un dépôt GitLab depuis le LAN maison et que Lyon consulte NetBox, Nadia éteint brutalement la passerelle active. Je veux voir les chiffres de perte s'afficher, et rien d'autre se passer.
> Sophie relira la matrice des flux v2 et le registre des secrets ; Karim l'ADR-0070 et le code ; Nadia RB-070 et RB-071, qu'elle jouera elle-même. La maquette doit avoir disparu, et on doit pouvoir la reconstruire depuis le code.

**Objectifs pédagogiques**
- Consolider la bordure redondante, les points d'entrée et le routage dynamique du module en un ensemble cohérent, piloté par le code, documenté et supervisé.
- Démontrer la tenue à la panne de bout en bout, chiffres à l'appui.
- Livrer l'état d'entrée du bloc B suivant (`socle-v2`) en laissant le lab propre.

**Prérequis** : M07-E01 à M07-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; le mini-projet M06-E46.
**Durée indicative** : 14 à 20 h, plus 30 min de revue.

**Contexte technique**
- Socle v2 (PLAN §4.5 et §4.9) : socle v1 + `gw02` (1009), `lb01` (1010, 10.10.70.10), `lb02` (1011, 10.10.70.11) ; étiquettes `socle` + `role-routeur` / `role-lb`.
- Bordure : VIP `.1` sur les VLAN 10, 20, 30, 40, 50, 52, 60, 70, 99 (VRID = VLAN), `gw01` `.2` priorité 150, `gw02` `.3` priorité 100, VIP WAN `<IP-GW-WAN-VIP>` (VRID 250), groupe de synchronisation unique, `conntrackd` (FTFW, VLAN 10, UDP 3780), tunnels `wg0`/`wg1`/`wg2` sur le maître, traduction sortante vers la VIP WAN.
- Points d'entrée : VIP 10.10.70.200 (`lb.par1.medisphere.internal`, VRID 170), `gitlab.par1.medisphere.internal` et `netbox.par1.medisphere.internal`, redirection 443 depuis la VIP WAN.
- Routage : FRR 10.7 sur les deux passerelles, AS 65000, plage d'écoute `K8S` prête (10.10.40.0/24, sans voisin), politiques qui n'acceptent de la fabric que 10.10.255.0/24 et 10.10.41.0/24 ; BGP avec Lyon (65030) dans `wg2`.
- MTU 9000 de bout en bout sur les VLAN 30, 31 et 51 (`vmbr1`, trunk des passerelles, `ens19.30`, `ens19.51`) ; 1500 ailleurs.
- Maquette : décision du module, **détruire 2070-2079**, y compris `lyo-gw01` et `lyo-pc01`. La configuration de Lyon côté PAR1 (pair `wg2`, voisin BGP, flux) **reste** dans le code, en attente : sa session est simplement absente.
- Le contrôle global `lab/bin/check 07 46` vérifie la bordure, les répartiteurs, FRR, le MTU, la supervision, l'absence de maquette, **revérifie les acquis du module 06 à travers la nouvelle bordure** (DNS par les deux résolveurs, PKI, NetBox et GitLab par leurs noms publiés) puis la documentation et l'hygiène. Il prend quelques minutes.

**Travail demandé**
1. **Bordure.** État nominal sur `gw01` ; rien dans le lab ni à l'extérieur (`pve01`, `pbs01`, ton poste, la redirection HTTPS) ne vise une adresse propre d'une passerelle, sauf l'accès de secours documenté. Configuration des deux passerelles **intégralement** produite par le code (`routeurs.yml` à `changed=0`, `tofu plan` de l'état `socle` sans changement).
2. **Points d'entrée.** GitLab et NetBox publiés par la VIP des répartiteurs, politique TLS de M07-E28, contrôles de santé applicatifs, statistiques protégées, certificats ACME renouvelés automatiquement ; le service temporaire de M07-E34 a disparu.
3. **Routage et MTU.** FRR prêt pour le module 15 (plage d'écoute, politiques) ; MTU 9000 vérifié de bout en bout sur les VLAN de stockage par un test sans fragmentation entre deux VMs jetables du VLAN 30 (détruites ensuite) ; Lyon : configuration conservée en attente, documentée (comment la réactiver).
4. **Maquette.** VMs 2070-2079 détruites **par OpenTofu** (état `m07-maquette` vide, conservé), VNets `vfab1` à `vfab8` retirés ou conservés (choix justifié) ; la reconstruction est documentée et a été **testée** une fois (plan OpenTofu qui recrée les dix VMs, sans l'appliquer s'il manque de mémoire).
5. **Exploitation.** `ms-verif-reseau` et `ms-verif-services` planifiés, verts ; RB-070, RB-071, RB-072 et les runbooks du palier 4 à jour ; `docs/socle/tests/bascules.md` complété par la mesure de la démonstration.
6. **Documentation.** `docs/socle/reseau/architecture.md` (architecture de la bordure, des points d'entrée et du routage : schéma, adresses, VRID, AS, ce qui se passe quand chaque élément tombe, points uniques de défaillance restants, ce que les modules 08, 09, 14 et 15 consommeront), ADR-0070, matrice des flux v2 générée, inventaire du socle et NetBox à jour (`gw02`, `lb01`, `lb02`, groupes FHRP), registre des secrets complété (clés WireGuard des passerelles, mots de passe des statistiques, clé de supervision : emplacement, portée, propriétaire, échéance — jamais la valeur).
7. **Livraison.** Tout est fusionné, pipelines de `main` verts, aucune panne `M07` active, étiquette **`socle-v2`** posée sur `plateforme/medisphere` (commit qui documente la livraison).
8. **La revue.** 10 minutes de présentation (avant/après, chiffres de bascule, risques restants), puis la démonstration : clone GitLab depuis le LAN maison et consultation de NetBox pendant l'extinction brutale de la passerelle active, perte mesurée affichée, retour à l'état nominal par RB-071 joué par Nadia (toi, avec le seul runbook, si tu travailles seul).

**Contraintes**
- Aucune interruption du lab au-delà des bascules annoncées pendant les derniers changements.
- Aucun secret dans un dépôt, un journal de CI ou la documentation.
- Tout est créé et détruit par le code ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les écarts aux exercices du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 07 46` est entièrement vert.
- [ ] La démonstration de panne se déroule comme annoncé : perte mesurée, sessions qui survivent, retour à l'état nominal par RB-071.
- [ ] La documentation dit ce qui n'est **pas** encore redondant (`pve01`, la box, le LAN maison, `ca01`, `nbx01`…) et ce que les modules suivants traiteront.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 07 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 07 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 07 XX`) donnent le détail par brique ; `lab/bin/check 06 46` aussi, en sachant que certains points ont légitimement changé avec ce module (adresse de `gw01`, matrice des flux déplacée).
</details>

<details><summary>Indice 2</summary>

Répète la démonstration **avant** la recette, au moins deux fois, et chronomètre-la. Ce qui la fait échouer le plus souvent : un client qui vise encore une adresse propre, un tunnel dont la passerelle de secours n'a pas la bonne clé, un cache ARP de la box, une alerte de supervision oubliée en `maint`.
</details>

<details><summary>Indice 3</summary>

Pour prouver que rien ne vise une adresse propre : cherche `<IP-GW01-WAN>`, `10.10.x.1` d'avant (dans les fichiers de `pve01`, `pbs01`, ton poste) et les `.2`/`.3` dans le code (`grep` sur les dépôts) ; chaque occurrence doit être une adresse **propre voulue** (`unicast_peer`, voisin BGP, lien `conntrackd`, accès de secours) et commentée comme telle.
</details>

**Pour aller plus loin** (facultatif) : rejouer la campagne de bascules de M07-E32 par un playbook ; préparer la publication de la passerelle RGW de Ceph (module 08) sur les répartiteurs.

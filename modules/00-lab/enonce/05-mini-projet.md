# Module 00 — Palier 5 : Mini-projet

Fin du premier chantier. Le socle de PAR1 et sa sauvegarde à PAR2 fonctionnent, tu sais les dépanner. Il reste à les **livrer** : au sens d'une équipe d'exploitation, un système n'est livré que s'il est vérifiable, documenté, restaurable et compréhensible par quelqu'un d'autre que son auteur. Le module 01 commencera par installer GitLab sur ce socle et y migrer ton dépôt de documentation ; les modules suivants s'appuieront sur ton inventaire, ta matrice des flux et ton plan de capacité. Ce mini-projet est ce que Claire Morel présentera à la DSI comme « socle v0 ».

---

### M00-E50 — Mini-projet : livrer le socle MédiSphère v0  `LIBRE` `★★★`

> **Ticket PLAT-150** — *De : Claire Morel*
> Recette du socle v0 vendredi. Je veux un socle qui passe le contrôle global sans un seul rouge, et un dossier qui permette à n'importe qui de l'équipe de l'exploiter, de le restaurer et de le faire évoluer sans t'appeler. On fera la revue ensemble : 10 minutes de présentation, une démonstration que je choisirai sur place, puis mes questions. Sophie (RSSI) relira la matrice des flux et vérifiera qu'aucun secret ne traîne dans le dépôt.

**Objectifs pédagogiques**
- Consolider le socle construit dans le module en un ensemble cohérent, vérifiable et sans dette cachée.
- Produire la documentation d'exploitation d'une plateforme : architecture, inventaire, matrice des flux, runbooks, décisions d'architecture, preuves de restauration, capacité.
- Défendre ses choix techniques en revue, avec des éléments mesurés.

**Prérequis** : M00-E01 à M00-E49 (au minimum tous les `LAB`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Le dépôt de documentation est un dépôt Git **local** sur `adm01` : `~/medisphere`, créé en M00-E25 (runbooks), enrichi en M00-E33 (ADR), M00-E37 (test de restauration) et au palier 4 (journaux, post-mortem, analyses, mesures). Il sera poussé sur GitLab (`git01`) au module 01. Si tu l'as placé ailleurs, déclare son chemin dans `lab/lab.env` : `WB_DEPOT=/chemin/vers/le/depot`.
- Le livrable documentaire vit dans `docs/socle/` avec cette structure minimale (tu peux ajouter des fichiers, pas en retirer) :

  ```
  docs/socle/
  ├── README.md            index du dossier, périmètre, version, état, contacts
  ├── architecture.md      schéma réseau et description des composants
  ├── inventaire.md        hôtes, VMs, ressources, comptes et accès
  ├── matrice-flux.md      flux autorisés, justifiés, reliés aux règles nftables
  ├── capacite.md          plan de capacité mémoire (et disque) selon les profils
  ├── runbooks/            au moins 4 runbooks
  ├── adr/                 au moins 3 ADR
  ├── tests/restauration.md  résultats du test de restauration chronométré
  ├── post-mortems/        au moins le post-mortem de M00-E46
  ├── journal/             journaux de diagnostic du palier 4
  ├── analyses/            M00-E47
  └── mesures/             M00-E48
  ```
- Profils de lab et budget mémoire de référence : `PLAN.md` §3.3. Adresses, VMID et noms : `PLAN.md` §4.

**Travail demandé**
1. **Socle sain.** Fais passer `lab/bin/check 00 50` au vert, sans ignorer de contrôle. Corrige à la racine ce qui ne l'est pas, y compris l'hygiène (VMs sandbox oubliées, règles de traçage, pannes d'exercice encore actives).
2. **Architecture.** Un schéma réseau versionnable (texte : Mermaid, ASCII ou équivalent ; une image exportée en complément si tu veux) couvrant les deux sites, `vmbr0`, `vmbr1`, la zone SDN et ses VNets, les interfaces de `gw01`, `wg0`, `wg1`, le LAN maison et le chemin des sauvegardes. Le texte qui l'accompagne explique les choix et les points uniques de défaillance.
3. **Inventaire.** Chaque hôte et VM du socle : rôle, VMID, VLAN/VNet, adresses, FQDN, ressources, stockage des disques, démarrage automatique et ordre, sauvegarde (job, fréquence, rétention), méthode d'accès (y compris de secours). Les comptes Proxmox/PBS et jetons : rôle, périmètre, **emplacement** du secret (jamais le secret).
4. **Matrice des flux.** Chaque flux autorisé par `gw01` (et par le pare-feu Proxmox) : source, destination, protocole/port, sens, justification, règle nftables correspondante. La politique par défaut et les refus notables y figurent. Un relecteur doit pouvoir confronter la matrice à `nft list ruleset` ligne à ligne.
5. **Runbooks.** Au moins quatre, dont RB-001 et RB-002 (M00-E25) mis à jour, et deux issus de tes pannes du palier 4 (par exemple « perte d'accès Internet du lab » et « sauvegarde en échec »). Chacun : déclencheur, prérequis, étapes avec résultat attendu, vérification, retour arrière, escalade.
6. **ADR.** Au moins trois : les deux de M00-E33 (révisés si tes choix ont évolué) et un nouveau sur une décision prise depuis (SDN, relais DHCP, chiffrement des sauvegardes, accès d'administration…).
7. **Restauration.** Un test de restauration **réalisé pour cette livraison** (pas seulement celui de M00-E37), ajouté en tête de `tests/restauration.md` : scénario, sauvegarde utilisée, durée de chaque étape, RTO mesuré, RPO constaté, écarts et actions. La VM de test (VMID 5090-5099) est supprimée ensuite.
8. **Capacité.** À partir de mesures réelles de `pve01` et `hp01` : mémoire disponible pour les VMs, consommation actuelle du socle v0, projection du socle complet (PLAN §3.3), cohabitation avec chaque profil (`infra`, `openstack`, `k8s`, `plateforme`), marges, mécanismes de récupération (ballooning, KSM, cache ZFS s'il y a lieu), règles d'exploitation qui en découlent et risques. Ajoute une projection de l'espace disque du datastore `ds-lab`.
9. **Post-mortem** de M00-E46 relu et rangé.
10. **Livraison.** Tout est commité, l'arbre de travail est propre, l'étiquette Git `socle-v0` pointe sur le commit livré, et le dépôt ne contient aucun secret (clé privée, jeton, mot de passe, empreinte de clé de chiffrement PBS).
11. **Revue.** Prépare la revue avec Claire : présentation de 10 minutes (architecture, état, risques, prochaines étapes), et sois prêt à démontrer en direct, au choix de Claire, l'une des opérations documentées dans tes runbooks.

**Contraintes**
- Aucune information ne doit contredire `PLAN.md` (adresses, VMID, noms, VLANs). Si tu as dû t'en écarter, documente l'écart dans un ADR.
- Toute valeur chiffrée (RTO, mémoire, IOPS) est datée et sa source indiquée (commande, mesure, exercice).
- Le dossier est lisible sans le workbook : un nouvel arrivant doit comprendre le socle sans avoir fait le module.

**Critères de réussite**
- [ ] `lab/bin/check 00 50` est entièrement vert.
- [ ] Les fichiers et dossiers de la structure minimale sont présents et remplis ; runbooks ≥ 4, ADR ≥ 3, post-mortem ≥ 1.
- [ ] La matrice des flux couvre au moins : tunnel (UDP/51820), VPN d'administration (UDP/51821), DNS (53), NTP (123), relais DHCP (67), API PBS (8007), administration (22, 8006), sortie Internet, ICMP.
- [ ] Le plan de capacité traite les quatre profils de PLAN §3.3 avec des chiffres mesurés.
- [ ] Le test de restauration indique une durée mesurée et un RTO.
- [ ] Le dépôt est propre, étiqueté `socle-v0`, sans secret.
- [ ] La revue avec Claire est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 00 50`

<details><summary>Indice 1</summary>

Ne rédige pas l'inventaire de mémoire : pars des sorties de l'API (`pvesh get /cluster/resources`, `qm config`, `pvesm status`) et de tes fichiers de configuration. Un inventaire qui diverge de la réalité est pire qu'aucun inventaire.
</details>

<details><summary>Indice 2</summary>

Si chaque règle de `/etc/nftables.conf` porte un `comment`, la matrice des flux peut y faire référence directement, et la vérification de cohérence devient un simple rapprochement. Une règle sans ligne dans la matrice, ou une ligne sans règle, est un écart à expliquer.
</details>

<details><summary>Indice 3</summary>

Pour la capacité, regarde ce que l'hôte consomme **hors VMs** (`free -m`, `/proc/meminfo`, éventuellement `arc_summary` si ZFS), et la RAM réellement utilisée par chaque VM (`pvesh get /nodes/<nœud>/qemu/<vmid>/status/current`), pas seulement la RAM configurée.
</details>

**Pour aller plus loin** (facultatif) : génère `inventaire.md` par un script à partir de l'API Proxmox (tu le reprendras au module 02) ; ajoute un contrôle automatique « matrice ↔ ruleset » qui compare les commentaires des règles nftables aux lignes de la matrice.

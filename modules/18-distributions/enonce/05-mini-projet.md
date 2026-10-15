# Module 18 — Palier 5 : Mini-projet

Le module a monté cinq façons d'avoir un cluster Kubernetes, les a montées de version, cassées, réparées, sauvegardées et restaurées. Il reste à **conclure** : une décision écrite et défendue, des mesures qui la justifient, une démonstration que le choix retenu se reconstruit par le code, et un lab rendu propre. C'est ce que Claire Morel présentera comme « distributions MédiSphère v1 ». Il ne doit rien rester du module qui consomme de la mémoire, des adresses ou des droits, sauf ce que l'ADR décide explicitement de garder.

---

### M18-E25 — Mini-projet : distributions MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1925** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Comité d'architecture dans deux semaines. Je veux :
> - l'ADR-0180 accepté ;
> - un tableau comparatif où **chaque** chiffre vient d'une mesure sur notre lab ;
> - devant le comité, la reconstruction depuis zéro de ce que l'ADR retient (pas une démo préparée la veille et laissée allumée) ;
> - après le comité, le lab rendu comme on l'a trouvé : `k8s-par1` de nouveau en service et vert, plus aucune VM, adresse, jeton ni règle de pare-feu du module, sauf ce que l'ADR garde noir sur blanc.
>
> Pendant la revue :
> - Karim te demandera de reconstruire le cluster de l'option retenue en suivant tes runbooks ;
> - Sophie relira le registre des secrets et vérifiera que le compte `wb-capi` et les jetons ont bien disparu (ou sont justifiés) ;
> - Nadia te demandera, au hasard, la procédure de restauration d'une distribution.

**Objectifs pédagogiques**
- Consolider les mesures du module en une décision argumentée, et la présenter.
- Prouver que l'option retenue est reconstructible par le code, avec une durée mesurée.
- Démonter un environnement complexe dans le bon ordre (charges, puis clusters de charge de travail, puis cluster de gestion, puis infrastructure, droits et flux), sans orphelin.
- Livrer l'état `distributions-v1` et rendre `k8s-par1` aux modules suivants.

**Prérequis** : M18-E01 à M18-E24 (au minimum tous les `LAB`, `LIBRE` hors E16, `BF`, la `RED` et le `CHRONO`) ; `packaging-v1` (M17-E25).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Projets : `plateforme/distributions` (code du module), `plateforme/infra` (`envs/m18`), `plateforme/ansible` (rôles `k3s`, `rke2`, `outils_distributions`, matrice des flux de la bordure), `plateforme/medisphere` (`docs/kubernetes/distributions/`).
- Ce qui existe à l'entrée :
  - VMs 2181-2188 (selon ce qui n'a pas déjà été détruit) et banc `k3s-ha` (5191-5192) ;
  - `capi-essai` (VMs 5180-5189, objets dans `k3s01`), templates 9060 et 9061 ;
  - compte Proxmox `wb-capi@pve` (jeton `capi`, rôle `WBCapi`), compartiment `etcd-m18` sur `s3-01` ;
  - flux provisoires : clusters de gestion → API de `pve01` et → API de `capi-essai` (E08 : règles de la bordure, IPSet `capi` et règle 8006 du pare-feu de `pve01`), `vsandbox` → `s3-01` (E14) et, si tu as fait E16, vers OpenStack ;
  - fichiers d'accès de `~/.config/workbook/m18/`.
- `lab/lab.env` reçoit deux réglages qui traduisent l'ADR pour le contrôle :
  - `WB_M18_TEMPLATES_CONSERVES=0|1` : les templates 9060-9069 sont-ils gardés ?
  - `WB_M18_WBCAPI_CONSERVE=0|1` : le compte `wb-capi` est-il gardé ?

  Par défaut, 0 et 0 (tout supprimé).
- Le contrôle global `lab/bin/check 18 25` vérifie :
  - la documentation et l'étiquette ;
  - l'absence de toute VM du module sur `pve01` et de tout objet du module dans NetBox ;
  - le compte `wb-capi` et les templates, selon les deux réglages ;
  - la matrice des flux de la bordure (plus de règle provisoire du module) et le pare-feu de `pve01` (plus d'IPSet `capi`) ;
  - les fichiers d'accès locaux ;
  - les pannes du module (aucune active) ;
  - `k8s-par1`, en lançant `lab/bin/check 14 46`.

  Il prend quelques minutes.

> ⚠️ **Attention à l'ordre de démontage.** Détruire la VM `k3s01` avant d'avoir supprimé `capi-essai` **par Cluster API** laisse des VMs 5180-5189 orphelines, des adresses et des données d'amorçage que plus rien ne nettoie. Supprimer un template avant ses clusters casse leur réparation. Supprimer le jeton `wb-capi` avant que CAPMOX ait fini de supprimer ses VMs bloque la suppression (finaliseurs). Écris l'ordre **avant** de commencer, et vérifie chaque étape dans Proxmox.

**Travail demandé**
1. **Mesures.** Complète `docs/kubernetes/distributions/comparatif.md` : une colonne par option (kubeadm, k3s, RKE2, Talos, Cluster API + CAPMOX, kind/k3d), une ligne par critère de l'ADR-0180. Au minimum :
   - temps d'installation d'un cluster de trois nœuds (ou de la topologie testée) ;
   - mémoire au repos par nœud de contrôle ;
   - durcissement (E15) ;
   - durée et nombre d'étapes manuelles d'une montée de version ;
   - RTO et RPO de la restauration (E14) ;
   - réparation automatique ;
   - temps de création d'un cluster de recette (E18).

   Chaque chiffre renvoie à son compte rendu (`tests/…`) ou à son exercice ; une case sans mesure dit pourquoi.
2. **Décision.** Fais passer l'ADR-0180 au statut « accepté » par MR relue (Karim et Sophie approbateurs). Il tranche les trois besoins, le sort de `k8s-par1`, du cluster de gestion, des templates, du compte `wb-capi` et du compartiment `etcd-m18`. Les réglages `WB_M18_*` de `lab/lab.env` le reflètent.
3. **Démonstration reconstructible.** Le cluster de l'option retenue pour l'agence de Lyon (ou, si l'ADR en retient un autre, celui-là) se construit **depuis zéro** par une commande, `task demo:construire`, et se détruit par `task demo:detruire` (Taskfile de `plateforme/distributions`) :
   - la construction couvre VMs, configuration, cluster, sauvegarde planifiée et charge témoin ;
   - la durée de construction est mesurée et notée dans `comparatif.md` ;
   - elle est rejouée pendant la revue, puis détruite ;
   - la démonstration réutilise les VMID et les noms du module (par exemple 5191-5193 pour un k3s à trois serveurs).
4. **Démontage, dans l'ordre que tu as écrit** (`docs/kubernetes/distributions/demontage.md`) :
   - charges et essais (`wb-essais`, recettes éphémères, `kind`/`k3d` sur `m18-dev01`) ;
   - **clusters de charge de travail par Cluster API** (`capi-essai`, et `capo-essai` s'il existe), jusqu'à la disparition de leurs VMs ;
   - archive finale du cluster de gestion (RB-181 §5), si l'ADR la demande ;
   - VMs du module par OpenTofu (`envs/m18` vide, état propre), enregistrements DNS et objets NetBox ;
   - templates, compte `wb-capi` (jeton, rôle `WBCapi`, ACL) et fichier `~/.config/workbook/pve-capi.env`, selon l'ADR ;
   - compartiment `etcd-m18` et identité `etcd-m18`, selon l'ADR ;
   - flux provisoires de la bordure (rôle `pare_feu` rejoué), IPSet `capi` et règle 8006 du pare-feu de `pve01`, et matrice des flux ;
   - fichiers d'accès devenus inutiles sous `~/.config/workbook/m18/`. Le paquet de secrets Talos reste dans le Vault si l'ADR garde Talos en option.
5. **`k8s-par1` de retour.** Redémarre `k8s-par1` selon sa procédure (M14-E05 : nœuds de contrôle d'abord, puis travailleurs) et vérifie-le. Certificats, etcd, Cilium, ceph-csi, MédiAgenda en recette et en production : tout revient vert.
6. **Livraison.** Tout est fusionné. Les pipelines de `main` de `plateforme/distributions`, `plateforme/infra` et `plateforme/ansible` sont verts. Le registre des secrets est à jour (ce qui a été supprimé, ce qui reste et où). L'étiquette **`distributions-v1`** est posée sur `plateforme/medisphere`.

**Contraintes**
- Aucune VM, aucun objet Cluster API, aucune règle de pare-feu supprimés « à la main » quand le code ou le contrôleur sait le faire. Une intervention manuelle exceptionnelle est consignée dans `demontage.md` avec sa raison.
- Aucun secret dans un dépôt, un ticket ou un journal. Les secrets supprimés sont retirés du registre, ceux qui restent y sont.
- Rien du module ne reste allumé après la revue.

**Critères de réussite**
- [ ] `lab/bin/check 18 25` est entièrement vert.
- [ ] Le comparatif ne contient aucun chiffre sans source ; l'ADR-0180 est accepté et cohérent avec les réglages `WB_M18_*`.
- [ ] La démonstration a été reconstruite et détruite pendant la revue, en un temps proche de celui du comparatif.
- [ ] `demontage.md` donne l'ordre suivi et prouve chaque étape (sortie de commande, capture Proxmox).
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 18 25`

<details><summary>Indice 1</summary>

Pour Cluster API, « supprimer un cluster », c'est supprimer l'objet `Cluster` et attendre : les contrôleurs suppriment les machines, puis leurs VMs, libèrent les adresses, puis retirent les finaliseurs. Tant que `kubectl get machines` ou `kubectl get proxmoxmachines` montre quelque chose, il ne faut toucher ni au cluster de gestion, ni au jeton, ni aux templates.
</details>

<details><summary>Indice 2</summary>

Le module a ajouté des choses ailleurs que dans `envs/m18` : des règles dans la matrice de la bordure (références `M18-E08`, `M18-E14`, `M18-E16`), un IPSet et une règle dans le pare-feu de `pve01`, une identité et un compartiment sur `s3-01`, un compte et un rôle sur Proxmox, peut-être des enregistrements DNS laissés par les baux DHCP. Cherche dans tes dépôts et dans `docs/socle/registre-secrets.md` tout ce qui porte « M18 » avant de dire que c'est fini.
</details>

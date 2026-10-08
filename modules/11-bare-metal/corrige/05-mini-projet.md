# Module 11 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M11-E25 — Mini-projet : l'usine de provisioning

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail**, les points de contrôle de chaque étape, une démonstration de référence et la **grille de revue**. Les fichiers de référence sont ceux des exercices (`corrige/fichiers/M11-EXX/`) ; seul `docs/provisioning/usine.md` est nouveau (modèle : [`fichiers/M11-E25/medisphere/docs/provisioning/usine.md`](fichiers/M11-E25/medisphere/docs/provisioning/usine.md)).

**Solution**

*Plan de travail recommandé* (dans cet ordre)

1. **État des lieux** (1 h) : `lab/bin/check 11 25`, puis les contrôles détaillés rouges (`11 13`, `11 18` à `11 21`). Liste ce qui est encore fait à la main : fichiers déposés sur `pxe01` hors du pipeline, modifications de Kea ou du relais hors du code, jetons sans échéance, VMs de test oubliées.
2. **Aligner le code** (2 à 3 h) : `ansible-playbook playbooks/pxe.yml --check --diff` et le playbook de `role_dns` à `changed=0` ; job `deployer` vert ; `tofu plan` de l'état `provisioning` sans écart ; `outils/verifier-rendu.sh` dans le pipeline (contrôles sémantiques ajoutés au palier 4).
3. **Répéter la démonstration** (2 à 3 h, au moins deux fois) : VMs vides recréées (`tofu apply -replace=…`), équipements `planned`, puis job `provisionner` pour `bm01` (BIOS, Debian) et `bm04` (UEFI, Rocky). Chronomètre chaque étape d'après le journal NetBox et note chaque intervention : chacune devient une correction de RB-110 ou du code. Une répétition doit partir d'un `pxe01` **reconstruit** (VM détruite puis recréée par OpenTofu et Ansible, rendu redéployé) : c'est le test de reprise que fera le final F5.
4. **Sécurité** (1 h) : relecture de `securite-chaine.md` et de l'ADR-0111 contre l'état réel ; registre des secrets (jeton de `wb-provision` et `pve-provision.env`, jeton du service de réponse PVE, droits étendus de `svc-automatisation`, compte iLO `wb-redfish`, clé de déploiement de `runner01` vers `pxe01`) ; matrice des flux identique sur `gw01` et `gw02`.
5. **Inventaire** (30 min) : job planifié `inventaire` vert, `hp01` à jour, `firmware.md` daté.
6. **Décision et nettoyage** (1 à 2 h) : ADR-0110 acceptée ; puis, si MAAS est retiré :

   | Où | Quoi | Commande ou endroit |
   |---|---|---|
   | OpenTofu (état `provisioning`) | VM 2116 `maas01` | suppression de la ressource, `tofu apply` |
   | Template | 9050 `tpl-ubuntu2404` | suppression justifiée (plus aucun consommateur) ou conservation documentée (base pour un futur besoin Ubuntu) |
   | NetBox | VM `maas01`, son adresse 10.10.60.11 | statut `decommissioning` puis suppression |
   | DNS | `maas01.par1.medisphere.internal` et son inverse | par le chemin du M06 (le code), jamais à la main |
   | Bordure | flux `maas01` → `pve01:8006` et définition `MAAS01` | lignes retirées de `group_vars/role_routeur/pare_feu.yml`, MR, pipeline, `matrice-flux.md` régénérée |
   | Pare-feu de Proxmox | IPSet `maas` ou entrée de `automation` | retrait sur `pve01` (⚠️ pare-feu du datacenter : session ouverte, retour arrière noté) |
   | Proxmox | `wb-maas@pve`, jeton `maas`, rôle `WBMaas`, ACL | `pveum user delete wb-maas@pve` (supprime jeton et ACL), `pveum role delete WBMaas` |
   | Kea et relais | sous-réseau 60 et relais du VLAN 60 | déjà rendus en fin de M11-E10 : vérifier (`lab/bin/check 11 19`) |
   | Poste | `~/.config/workbook/maas-api.key`, profil CLI, `known_hosts` | suppression |
   | Registre des secrets | jetons et comptes MAAS | marqués « révoqués », date |

   Puis VM 2117 (si elle existe encore), pannes `M11` closes.
7. **Documentation et livraison** (2 h) : `usine.md`, RB-110 avec les temps mesurés, RB-111 complet (sections du palier 4), MR, pipelines verts, étiquette `provisioning-v1` sur `plateforme/medisphere`.

*Démonstration de référence (RB-110)*

| Étape | Action | Preuve |
|---|---|---|
| 1 | NetBox : `bm01` et `bm04` à `planned` (interface `eno1` et MAC renseignées, adresse réservée) | objets NetBox |
| 2 | Pipeline de `plateforme/provisioning` : *Run pipeline*, `EQUIPEMENT=bm01`, job manuel `provisionner` ; idem `bm04` | journal du job |
| 3 | Console de `bm01` : chargeur en TFTP, puis tout en `https://pxe01…` ; installateur sans question ; arrêt | console, `pxe-acces.log` |
| 4 | L'orchestrateur rallume : la console montre « en service, démarrage sur le disque local » | console |
| 5 | Accueil : clé lue par l'agent, rôles `ca_lab`, `ssh_ca_hote`, `base` | journal du job |
| 6 | `active` dans NetBox ; `ssh bm01.par1.medisphere.internal` sans question ; `ansible-inventory -i inventories/lab/netbox-bm.yml --graph role_serveur_bm` | journal NetBox, terminal |

Temps typiques en lab : 15 à 25 min pour Debian, 15 à 30 min pour Rocky (téléchargement des paquets depuis Internet), dont deux minutes au plus pour toute la partie réseau.

**Explications**

Le mini-projet vérifie l'**intégration** : chaque brique a été construite et cassée dans un exercice ; leur valeur vient de la chaîne qui les relie à la source de vérité. Le contrôle global reprend donc les contrôles de la chaîne (E13, E19-E21) et de l'inventaire (E18) plutôt que ceux des étapes intermédiaires (E14, E15, E22), dont l'état a légitimement changé (nœud PVE détruit, serveurs de démonstration remis à zéro, MAAS retiré).

**Alternatives**
- MAAS conservé (ADR-0110 qui le retient) : le nettoyage ne porte alors que sur ce qui est inutile ; `WB_M11_MAAS_CONSERVE=1` dans `lab/lab.env` saute les contrôles de retrait de MAAS, et la revue porte sur l'intégration MAAS ↔ NetBox ↔ Kea décrite dans l'ADR.
- Déclenchement par NetBox (*event rule*) au lieu du bouton : supprime une action humaine, mais chaque erreur de saisie lance une installation ; à réserver à un NetBox dont les droits d'écriture sont stricts.

**Pièges classiques**
- Une démonstration qui ne marche que sur des VMs déjà installées une fois (variables UEFI, clés d'hôte en cache, `known_hosts`).
- Oublier les restes de MAAS dans le pare-feu de Proxmox ou dans le registre des secrets.
- Livrer avec un `pxe01` qui sert des fichiers modifiés à la main (le contrôle E20/E21 le voit, le rendu suivant les effacerait sans explication).
- Laisser les serveurs de démonstration en service sans dire ce qu'ils deviennent.

**En production chez MédiSphère**
L'usine sert à la livraison des palettes : file d'attente d'installations (lots de 5), contrôleurs Redfish à la place de l'API Proxmox, Secure Boot, effacement certifié en fin de vie, et un tableau de bord des équipements par statut. La recette ajoute un exercice de reprise : `pxe01` détruit puis reconstruit par le code pendant la revue (objectif : moins de 20 minutes).

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 11 25` entièrement vert (contrôles ignorés justifiés) |
| Claire | Démonstration | BIOS/Debian et UEFI/Rocky jusqu'à `active`, sans geste hors de NetBox et du pipeline, temps mesurés dans RB-110 |
| Claire | Décision | ADR-0110 acceptée et appliquée (nettoyage cohérent avec la décision) |
| Karim | Code | rendu et déploiement par le pipeline, validations sémantiques, `changed=0`, `tofu plan` sans écart, orchestrateur idempotent avec reprise |
| Karim | Reprise | `pxe01` reconstruit par le code au moins une fois, durée notée |
| Sophie | Chaîne de confiance | iPXE construit par la procédure versionnée, seule racine MédiSphère, HTTPS de bout en bout après le chargeur, ce qui reste usurpable est écrit |
| Sophie | Secrets et comptes | aucun mot de passe dans les fichiers servis ni les dépôts ; registre complet ; `wb-maas` retiré ; `wb-redfish` minimal ; IPMI sur IP coupé |
| Sophie | Flux | matrice identique sur les deux passerelles, VLAN 60 isolé, aucun reste de MAAS |
| Nadia | Exploitation | RB-110 joué par un tiers, RB-111 couvre chaque étage, inventaire de `hp01` planifié et à jour |
| Julien | Utilisabilité | la démonstration se fait avec RB-110 seul |
| Tous | Présentation | 10 minutes : ce que fait l'usine, chaîne de confiance, temps, limites, ce que les modules 14 et finaux consommeront |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant devient une action (responsable, échéance) dans le compte rendu de recette.

# Final F4 — Phase 4 : Bilan

Les changements du trimestre sont passés : montées, migration des VMs d'InfoGér, Legacy-RDV sur Kubernetes. Il reste à fermer proprement : vérifier que chaque changement a tenu ses promesses, retirer ce qui ne sert plus sans rien perdre de ce qu'on doit garder, et décider de la suite de Legacy-RDV. Claire Morel tient à cette dernière étape : « Un changement n'est fini que quand on a vérifié qu'il a marché, et qu'on a jeté l'ancien. »

Prérequis : phases 1 à 3 terminées (`lab/bin/check F4 13` vert depuis au moins 48 h : la période de retour arrière de la bascule est close).

---

### F4-S14 — Revue des changements et décommissionnement  `RED` `★★`

> **Ticket CHG-3414** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel, Karim Benali*
> Revue de fin de trimestre lundi. Pour chaque changement : ce qu'on avait promis, ce qu'on a mesuré, ce qui a dérapé, ce qu'on en retient. Ensuite, on éteint `legacy-rdv01` pour de bon : Sophie veut la preuve que les données de santé qui y étaient sont effacées, et une sauvegarde finale gardée le temps qu'il faut, pas un jour de plus. Et je veux une décision sur l'avenir de Legacy-RDV : on le garde tel quel, on le réécrit dans MédiAgenda, ou autre chose ? Quand tout ça est fait, tu poses `changements-v1`.

**Objectifs pédagogiques**
- Conduire une revue après mise en œuvre factuelle (mesures, écarts, leçons, actions), sans recherche de coupable.
- Décommissionner un serveur qui a porté des données de santé : sauvegarde finale conservée et protégée, effacement prouvé, retrait de tous les référentiels (code, DNS, NetBox, supervision, sauvegarde).
- Écrire une décision d'architecture qui engage la suite (options, coûts, risques, critères).

**Prérequis** : F4-S01 à F4-S13.
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Les fiches du trimestre sont dans `docs/changements/fiches/` ; les mesures de la sonde sont dans Prometheus (rétention locale 15 j, Thanos au-delà) et dans les fiches elles-mêmes.
- La politique de conservation des sauvegardes d'une VM décommissionnée qui portait des données de santé est à **toi** de proposer et de faire valider par Sophie (durée, lieu, protection contre la suppression, qui peut restaurer) ; PBS sait protéger un instantané contre l'élagage.
- `legacy-rdv01` est la VM **3401** ; son disque est sur `local-nvme`. Ses données de santé ne se limitent pas à la base active (cherche ce qu'InfoGér avait laissé, F4-S09).
- `ftp-part01` et `stats01` ne sont pas décommissionnées dans ce scénario (leur sort est dans ton plan de F4-S09) ; si tu en décides autrement, écris-le.
- Étiquette finale **`changements-v1`** sur `plateforme/medisphere`.

**Travail demandé**

Livre dans `plateforme/medisphere` (MR relue par Claire et Sophie) :
1. **`docs/changements/revue-trimestre.md`** : un tableau de tous les changements du trimestre (CHG-3403 à CHG-3413 et ceux que tu as ajoutés) avec, pour chacun, la catégorie, la décision (fait, reporté, no-go), la fenêtre prévue et réelle, l'interruption promise et **mesurée** (chiffre de la sonde), les écarts au plan, le retour arrière (testé ? utilisé ?), puis les leçons (ce qui a marché, ce qui a coûté) et les actions (responsable, échéance). Les no-go comptent : une montée refusée à raison est un succès du processus.
2. **Décommissionnement de `legacy-rdv01`** : la procédure **RB-347** « Décommissionner une VM porteuse de données de santé » (générique), puis son application à 3401, avec la fiche **CHG-3414** : sauvegarde finale **vérifiée** (restauration d'essai) et **protégée**, durée de conservation et date d'expiration écrites ; effacement des données (méthode adaptée au stockage `local-nvme`, et preuve) ; retrait de la VM de l'état OpenTofu, du DNS, de NetBox, de la supervision, du travail de sauvegarde, de la publication par les répartiteurs ; ce qu'on fait de l'export d'InfoGér (fichiers `import/infoger-export/` : ce sont aussi des données de santé). Si tu décides de garder la VM arrêtée plus longtemps, la décision écrite dit pourquoi et jusqu'à quand.
3. **`docs/changements/adr/ADR-0340-avenir-legacy-rdv.md`** : au moins trois options (maintien en l'état sur Kubernetes, réécriture de la prise de rendez-vous dans MédiAgenda et migration des cabinets, autre), critères (sécurité, coût, risque, dette, attente des cabinets), décision, conséquences et date de revue.
4. Pose l'étiquette **`changements-v1`** quand tout est sur `main` et que les contrôles de F4 sont verts.

**Contraintes**
- Aucune donnée détruite avant que la sauvegarde finale soit vérifiée par une restauration d'essai.
- Une revue sans nom de coupable : les écarts sont des faits, les causes sont des mécanismes.

**Critères de réussite**
- [ ] `revue-trimestre.md`, RB-347, CHG-3414 et ADR-0340 sont sur `main` de `plateforme/medisphere`.
- [ ] La VM 3401 n'existe plus sur `pve01` (ou est arrêtée, avec la décision écrite dans CHG-3414) ; `legacy-rdv01` ne résout plus dans le DNS et n'est plus active dans NetBox ; l'état `envs/f4-infoger` ne la contient plus.
- [ ] Une sauvegarde finale de 3401 existe sur `pbs-par2` et est protégée.
- [ ] L'étiquette `changements-v1` est posée sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F4 14`

<details><summary>Indice 1</summary>

Pour chaque fiche, la question est la même : « qu'avions-nous écrit, qu'avons-nous observé ? ». Reprends les requêtes de la sonde (F4-S02) sur la fenêtre réelle de chaque changement ; un chiffre manquant est lui-même un écart.
</details>

<details><summary>Indice 2</summary>

Un volume LVM-thin supprimé ne réécrit pas ses blocs : effacer « pour de vrai » se fait **avant** la suppression du disque (écriture sur le volume, ou `blkdiscard` et ce qu'il garantit vraiment sur ce stockage), et se prouve (lecture d'un échantillon, journal de la commande). Les copies à ne pas oublier : vidages locaux d'InfoGér, export d'InfoGér, sauvegardes intermédiaires, clones éventuels.
</details>

**Pour aller plus loin** (facultatif) : transforme RB-347 en pipeline (job manuel protégé de `plateforme/infra`) qui refuse de détruire une VM tant que la sauvegarde finale protégée n'est pas vérifiée.

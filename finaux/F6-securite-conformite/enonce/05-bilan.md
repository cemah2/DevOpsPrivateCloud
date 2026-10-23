# Final F6 — Phase 5 : Bilan

L'audit à blanc a produit des écarts, la remédiation les a traités, l'incident a été géré de bout en bout. Il reste à **prouver** que tout est clos, et à le présenter comme Hélène Mercier le demandera à l'audit officiel : chaque écart fermé avec une preuve qu'on n'a pas fabriquée la veille, une déclaration d'applicabilité à jour, et un état des lieux que l'on peut montrer. C'est la recette du final.

Prérequis de la phase : F6-S08 à F6-S13 terminés (écarts `ECA-3601`, `-3602`, `-3603`, `-3605` traités, incident INC-6211 clos et documenté). Les écarts `ECA-3604` (revue des accès) et `ECA-3606` (transferts hors EEE) se ferment par les actions de ton plan de remédiation (deuxième revue mensuelle, cartographie publiée et avenants) : leur clôture se juge avec le corrigé, le check ne la vérifie pas.

---

### F6-S14 — Recette `conformite-v1` : l'audit de suivi  `LIBRE` `★★`

> **Ticket SEC-3614** — *De : Hélène Mercier (Auditia Santé)* — *Copie : Sophie Laurent (RSSI), Thomas Renaud (DPO), Claire Morel*
> Je reviens pour l'audit de suivi. Je ne veux pas relire vos politiques : je veux, pour chaque écart que j'ai relevé, la **preuve** qu'il est clos — collectée automatiquement, horodatée, inaltérable, et datée d'avant aujourd'hui. Je veux votre déclaration d'applicabilité à jour (ce qui s'applique, ce qui ne s'applique pas et pourquoi, où est la preuve) et un état des preuves qui montre qu'elles se collectent seules. Si tout est là, vous êtes prêts pour l'audit officiel. Posez votre étiquette.

**Objectifs pédagogiques**
- Clôturer un cycle d'audit : chaque écart fermé avec une preuve collectée, pas déclarée.
- Mettre à jour une déclaration d'applicabilité (SoA) et la relier aux preuves.
- Reconnaître une preuve recevable (automatique, horodatée, inaltérable, antérieure à l'audit).

**Prérequis** : F6-S01 à F6-S13 ; F6-S02 (`ms-preuves`, compartiment `preuves-conformite`), F6-S07 (registre des écarts, SoA), F6-S08 (traçabilité inaltérable).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Les écarts de l'audit (`ECA-3601` à `ECA-3606`) sont dans `docs/conformite/ecarts/`, avec l'en-tête YAML de l'introduction : `statut`, `clos-le` et `preuve` (le lot `ms-preuves` de clôture, `lots/AAAA/MM/JJ/<LOT>/`).
- `ms-preuves` collecte, horodate, signe et dépose les preuves dans `preuves-conformite` (verrouillage d'objets, versionné). Une preuve recevable est **collectée automatiquement**, **horodatée**, **inaltérable** et **antérieure** à la décision qu'elle justifie (une preuve fabriquée la veille n'en est pas une — c'est précisément ce que l'auditrice a dit).
- Valeurs figées (lues par le check) : générateur de l'état dans `plateforme/outils`, `bin/ms-etat-preuves` ; état publié en `docs/conformite/etat-preuves.md`.
- La déclaration d'applicabilité (`docs/conformite/soa.md`) couvre les 93 mesures d'ISO 27001:2022 et les exigences HDS v2 : pour chaque mesure, applicable ou non (et pourquoi), mise en œuvre, et le **lien vers la preuve**.
- Étiquette finale **`conformite-v1`** sur `plateforme/medisphere`.

**Travail demandé**

Objectifs :
1. **Clôture des écarts** : vérifie que `ECA-3601`, `ECA-3602`, `ECA-3603`, `ECA-3605` (puis `ECA-3604` et `ECA-3606`) sont au statut `clos`, chacun avec un lot de preuve qui existe dans `preuves-conformite`, daté au plus tard du jour de la clôture, et dont les objets sont encore sous rétention.
2. **SoA à jour** : chaque mesure applicable renvoie à sa mise en œuvre et à sa preuve ; les non-applicables sont justifiées. Les mesures touchées par le F6 (journalisation 8.15, surveillance 8.16, gestion des vulnérabilités 8.8, incidents 5.24 à 5.28, sauvegarde 8.13, cryptographie 8.24) sont à jour, dans le format de la SoA (introduction).
3. **État des preuves** : un état (généré, pas saisi) qui montre, pour chaque écart, que son lot de preuve existe, précède la clôture et reste inaltérable, et que la collecte quotidienne **tourne** (fraîcheur du dernier lot, compartiment en `COMPLIANCE`). Ce qui manque ou a vieilli ressort, et le générateur échoue.
4. **Étiquette** `conformite-v1` posée une fois tout sur `main` et les contrôles de F6 verts.

Contraintes :
- Une preuve n'est recevable que si elle est antérieure à la décision qu'elle justifie et inaltérable (verrouillage) : un lot daté d'aujourd'hui pour un écart fermé il y a trois semaines est suspect.
- La SoA renvoie à des preuves **existantes** (pas « à produire ») ; un lien mort est un écart.
- `conformite-v1` ne se pose que si `lab/bin/check F6 1` à `F6 14` sont verts.

Livrables : MR dans `plateforme/medisphere` (écarts clos, SoA, état des preuves) ; étiquette `conformite-v1`.

**Critères de réussite**
- [ ] `ECA-3601`, `ECA-3602`, `ECA-3603`, `ECA-3605` sont clos sur `main`, chacun avec un lot de preuve existant dans `preuves-conformite` et daté au plus tard du jour de sa clôture.
- [ ] `docs/conformite/soa.md` est à jour : les mesures 8.15, 8.8 et 5.24 à 5.26 renvoient à leur mise en œuvre et à des preuves existantes.
- [ ] `bin/ms-etat-preuves` est sur `main` de `plateforme/outils` ; `docs/conformite/etat-preuves.md`, généré, montre lots, verrouillage et fraîcheur ; la collecte planifiée a réussi récemment.
- [ ] L'étiquette `conformite-v1` est posée sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F6 14`

<details><summary>Indice 1</summary>

L'auditrice a donné le critère de recevabilité dans son ticket : automatique, horodatée, inaltérable, **antérieure**. Le compartiment `preuves-conformite` (verrouillage d'objets, versionné) donne l'inaltérabilité et la date du serveur ; `ms-preuves` donne l'automatisme et la signature. Compare la date du lot cité par chaque fiche à sa date de clôture : un lot déposé après la clôture, ou la veille de l'audit, est à expliquer.
</details>

<details><summary>Indice 2</summary>

L'état des preuves ne se saisit pas : il se **génère** depuis les en-têtes des fiches d'écart et le contenu du compartiment `preuves-conformite` (lots, dates, rétentions). Ce qui n'a pas de preuve, dont la preuve est postérieure à la décision, ou dont la collecte s'est arrêtée, ressort en rouge — c'est exactement la vue que l'auditrice regardera.
</details>

**Pour aller plus loin** (facultatif) : une « revue de direction » (ISO 27001 clause 9.3) qui s'appuie sur l'état des preuves ; la préparation de l'audit officiel (ordre des entretiens, échantillonnage des preuves par l'auditrice) ; un indicateur d'« âge moyen des preuves » par mesure.


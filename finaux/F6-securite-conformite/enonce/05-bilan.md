# Final F6 — Phase 5 : Bilan

L'audit à blanc a produit des écarts, la remédiation les a traités, l'incident a été géré de bout en bout. Il reste à **prouver** que tout est clos, et à le présenter comme Hélène Mercier le demandera à l'audit officiel : chaque écart fermé avec une preuve qu'on n'a pas fabriquée la veille, une déclaration d'applicabilité à jour, et un état des lieux que l'on peut montrer. C'est la recette du final.

Prérequis de la phase : F6-S08 à F6-S13 terminés (écarts `ECA-3601`, `-3602`, `-3603`, `-3605` traités, incident INC-6211 clos et documenté). Les écarts `ECA-3604` (revue des accès, phase 1) et `ECA-3606` (transferts hors EEE, phases 1-2) sont traités par leurs scénarios respectifs.

---

### F6-S14 — Recette `conformite-v1` : l'audit de suivi  `LIBRE` `★★`

> **Ticket SEC-3614** — *De : Hélène Mercier (Auditia Santé)* — *Copie : Sophie Laurent (RSSI), Thomas Renaud (DPO), Claire Morel*
> Je reviens pour l'audit de suivi. Je ne veux pas relire vos politiques : je veux, pour chaque écart que j'ai relevé, la **preuve** qu'il est clos — collectée automatiquement, horodatée, inaltérable, et datée d'avant aujourd'hui. Je veux votre déclaration d'applicabilité à jour (ce qui s'applique, ce qui ne s'applique pas et pourquoi, où est la preuve) et un état des preuves qui montre qu'elles se collectent seules. Si tout est là, vous êtes prêts pour l'audit officiel. Posez votre étiquette.

**Objectifs pédagogiques**
- Clôturer un cycle d'audit : chaque écart fermé avec une preuve collectée, pas déclarée.
- Mettre à jour une déclaration d'applicabilité (SoA) et la relier aux preuves.
- Reconnaître une preuve recevable (automatique, horodatée, inaltérable, antérieure à l'audit).

**Prérequis** : F6-S01 à F6-S13 ; F6-S02 (`ms-preuves`, compartiment `preuves-conformite`), F6-S07 (registre des écarts, SoA), F6-S08 (traçabilité inaltérable).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Les écarts de l'audit (`ECA-3601` à `ECA-3606`) sont dans `docs/conformite/ecarts/` ; chacun a un statut et un champ de preuve.
- `ms-preuves` collecte, horodate, signe et dépose les preuves dans `preuves-conformite` (verrouillage d'objets, versionné). Une preuve recevable est **collectée automatiquement**, **horodatée**, **inaltérable** et **antérieure** à la date de l'audit (une preuve fabriquée la veille n'en est pas une — c'est précisément ce que l'auditrice a dit).
- La déclaration d'applicabilité (`docs/conformite/soa.md`) couvre les 93 mesures d'ISO 27001:2022 et les exigences HDS v2 : pour chaque mesure, applicable ou non (et pourquoi), mise en œuvre, et le **lien vers la preuve**.
- Étiquette finale **`conformite-v1`** sur `plateforme/medisphere`.

**Travail demandé**

Objectifs :
1. **Clôture des écarts** : vérifie que `ECA-3601`, `ECA-3602`, `ECA-3603`, `ECA-3605` (et `ECA-3604`, `ECA-3606` traités ailleurs) sont au statut `clos`, chacun avec une preuve dans `preuves-conformite/ECA-36xx/` collectée par `ms-preuves`, horodatée et antérieure à aujourd'hui.
2. **SoA à jour** : chaque mesure applicable renvoie à sa mise en œuvre et à sa preuve ; les non-applicables sont justifiées. Les mesures touchées par le F6 (journalisation A.8.15, surveillance A.8.16, gestion des vulnérabilités A.8.8, réponse à incident A.5.24-26, sauvegarde A.8.13, chiffrement A.8.24) sont à jour.
3. **État des preuves** : un état (généré, pas saisi) qui montre, pour chaque écart et chaque mesure clé, que la preuve existe, est récente, est inaltérable, et que la collecte est **planifiée** (pipeline). Ce qui manque ou a vieilli ressort.
4. **Étiquette** `conformite-v1` posée une fois tout sur `main` et les contrôles de F6 verts.

Contraintes :
- Une preuve n'est recevable que si elle est antérieure à l'audit de suivi et inaltérable (verrouillage) : une preuve datée d'aujourd'hui pour un écart fermé il y a trois semaines est suspecte.
- La SoA renvoie à des preuves **existantes** (pas « à produire ») ; un lien mort est un écart.
- `conformite-v1` ne se pose que si `lab/bin/check F6 1` à `F6 14` sont verts.

Livrables : MR dans `plateforme/medisphere` (écarts clos, SoA, état des preuves) ; étiquette `conformite-v1`.

**Critères de réussite**
- [ ] `ECA-3601`, `ECA-3602`, `ECA-3603`, `ECA-3605` sont clos sur `main`, chacun avec une preuve dans `preuves-conformite/`, horodatée et antérieure à aujourd'hui.
- [ ] `docs/conformite/soa.md` est à jour : les mesures touchées par le F6 renvoient à leur mise en œuvre et à une preuve existante.
- [ ] Un état des preuves (généré) montre fraîcheur, inaltérabilité et collecte planifiée ; il signale ce qui manque ou a vieilli.
- [ ] L'étiquette `conformite-v1` est posée sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F6 14`

<details><summary>Indice 1</summary>

L'auditrice a donné le critère de recevabilité dans son ticket : automatique, horodatée, inaltérable, **antérieure** à l'audit. Le compartiment `preuves-conformite` (verrouillage d'objets, versionné) donne l'inaltérabilité et l'horodatage ; `ms-preuves` donne l'automatisme. La date est dans l'objet : une preuve déposée après la date de clôture de l'écart, ou la veille de l'audit, est à expliquer.
</details>

<details><summary>Indice 2</summary>

L'état des preuves ne se saisit pas : il se **génère** depuis le registre des écarts, la SoA et le contenu du compartiment `preuves-conformite` (liste des objets, leurs dates, leur verrouillage). Ce qui n'a pas de preuve, ou dont la preuve a vieilli, ou dont la collecte n'est pas planifiée, ressort en rouge — c'est exactement la vue que l'auditrice regardera.
</details>

**Pour aller plus loin** (facultatif) : une « revue de direction » (ISO 27001 clause 9.3) qui s'appuie sur l'état des preuves ; la préparation de l'audit officiel (ordre des entretiens, échantillonnage des preuves par l'auditrice) ; un indicateur d'« âge moyen des preuves » par mesure.

---

## Points non testés en conditions réelles (phase 5)

- Génération de l'état des preuves depuis le compartiment `preuves-conformite` : dépend de l'implémentation de `ms-preuves` (F6-S02) ; vérifie sur ta plateforme.
- Antériorité des preuves : le contrôle compare la date de l'objet verrouillé à la date de clôture de l'écart ; la précision dépend de l'horodatage du RGW.

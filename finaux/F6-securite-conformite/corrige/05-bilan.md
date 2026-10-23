# Final F6 — Phase 5 : Bilan — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. `LIBRE` : solution de référence.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `ms-etat-preuves` : `bash -n` et `shellcheck -x` ;
- SoA (extrait) et état des preuves : Markdown/logique relus, non exécutés sur une plateforme F6.

**Fichiers** : [`fichiers/F6-S14/`](fichiers/F6-S14/).

---

### F6-S14 — Recette `conformite-v1` : l'audit de suivi

**Solution** (solution de référence)

Fichiers : [`soa.md` (extrait F6)](fichiers/F6-S14/medisphere/docs/conformite/soa.extrait-F6.md), [`ms-etat-preuves`](fichiers/F6-S14/outils/bin/ms-etat-preuves), [`etat-preuves.md` (exemple généré)](fichiers/F6-S14/medisphere/docs/conformite/etat-preuves.md).

1. **Clôture des écarts** : les six écarts de l'audit sont au statut `clos`. L'en-tête de chaque fiche
   donne `clos-le` et, dans `preuve`, le **lot `ms-preuves`** (`lots/AAAA/MM/JJ/<LOT>/`) qui contient les
   preuves de clôture (identifiants `P-…` cités dans la section « Preuve de clôture ») : collecté par un
   pipeline (automatique), signé, déposé dans le compartiment verrouillé (inaltérable, horodaté par le
   serveur), et **daté au plus tard du jour de la clôture**. Les quatre du périmètre technique (3601, 3602,
   3603, 3605) sont fermés par les phases 3 et 4 ; 3604 (revue des accès) se ferme avec la deuxième revue
   mensuelle (lot qui contient P-IAM-06 de décembre), 3606 (transferts hors EEE) avec la cartographie
   publiée et les avenants signés (pièces documentaires citées, lot qui contient la version publiée).
2. **SoA à jour** : `soa.extrait-F6.md` montre la forme — une ligne par mesure (applicable O/N +
   justification, mise en œuvre, **lien de preuve**). Les mesures touchées par le F6 (8.15, 8.16,
   8.8, 5.24-5.28, 8.13, 8.24, et HDS activités 5-6) renvoient à leur mise en œuvre et à des preuves
   **existantes** (identifiants du catalogue, lot de clôture de l'écart).
3. **État des preuves généré** : `bin/ms-etat-preuves` (pipeline planifié `preuves:etat`, après la
   collecte) lit l'en-tête des fiches d'écart et le compartiment `preuves-conformite` ; il produit
   `etat-preuves.md` et **échoue** si le lot d'un écart clos manque, est postérieur à la clôture ou n'est
   plus sous rétention, si le compartiment n'est pas en `COMPLIANCE`, ou si le dernier lot quotidien a plus
   de 36 h (collecte en panne). C'est la vue de l'auditrice.
4. **Étiquette** `conformite-v1` posée une fois tout sur `main` et `lab/bin/check F6 1` à `F6 14` verts.

**Explications**
- **Une preuve, pas une politique.** L'audit de suivi ne relit pas les intentions : il échantillonne des
  preuves. La valeur du F6 tient dans le fait que ces preuves se **collectent seules** (F6-S02),
  s'**archivent inaltérables** (F6-S08) et se **datent** : l'auditrice peut en tirer une au hasard et
  vérifier qu'elle est antérieure, intacte et reproductible.
- **L'antériorité est un signal.** Une preuve datée de la veille de l'audit, pour un écart fermé depuis
  trois semaines, trahit une fabrication de dernière minute — ce que l'auditrice a explicitement refusé.
  L'état des preuves compare la date de la preuve à la date de clôture.
- **La SoA relie tout.** C'est le document pivot : chaque mesure applicable pointe vers sa mise en œuvre
  (le code, la config) et sa preuve (l'objet verrouillé). Un lien mort est un écart.

**Alternatives**
- Un outil de GRC dédié (gestion des risques et de la conformité) : plus riche, lourd pour une équipe de
  cinq ; la SoA en Markdown versionnée avec le code et l'état généré depuis les preuves suffit et reste
  auditable.
- Preuves rangées hors verrouillage (un simple dossier) : l'auditrice ne peut pas distinguer l'original
  d'une copie retouchée ; le verrouillage d'objets tranche.

**Pièges classiques**
- Un écart « clos » dont la preuve pointe un préfixe vide, ou un lien mort dans la SoA.
- Une preuve datée après la clôture de l'écart (ou le jour de l'audit) : suspecte.
- Un état des preuves **saisi** à la main : il dira « tout va bien » le jour où une collecte est tombée en
  panne. Il doit se générer et pouvoir rougir.
- Poser `conformite-v1` avant que tous les contrôles de F6 soient verts.

**En production chez MédiSphère**
L'état des preuves alimente la revue de direction (ISO 27001, clause 9.3) ; l'auditrice officielle
échantillonne les preuves depuis le compartiment verrouillé ; un indicateur d'« âge moyen des preuves »
par mesure signale les collectes qui se dégradent avant qu'elles ne manquent.

---

## Points non testés en conditions réelles (phase 5)

- `ms-etat-preuves` : relu, `shellcheck` propre, non exécuté contre un vrai compartiment ; la date d'un
  lot vient de son nom (horloge du runner, synchronisée sur `gw01`), la date serveur de l'objet (RGW)
  la confirme : à comparer sur ton lab.
- Clôture de ECA-3604 et ECA-3606 : décrite, sans fichier de référence (dépend de ta revue de décembre et
  de tes avenants).

# Final F6 — Phase 5 : Bilan — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. `LIBRE` : solution de référence.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `etat-preuves.sh` : `bash -n` et `shellcheck -x` ;
- SoA (extrait) et état des preuves : Markdown/logique relus, non exécutés sur une plateforme F6.

**Points non testés en conditions réelles** : génération de l'état depuis `preuves-conformite` (dépend de
`ms-preuves`, F6-S02) ; précision de l'antériorité (horodatage du RGW). Signale tes retours.

**Fichiers** : [`fichiers/F6-S14/`](fichiers/F6-S14/).

---

### F6-S14 — Recette `conformite-v1` : l'audit de suivi

**Solution** (solution de référence)

Fichiers : [`soa.md` (extrait F6)](fichiers/F6-S14/medisphere/docs/conformite/soa.extrait-F6.md), [`etat-preuves.sh`](fichiers/F6-S14/outils/bin/etat-preuves.sh), [`etat-preuves.md` (exemple généré)](fichiers/F6-S14/medisphere/docs/conformite/etat-preuves.md).

1. **Clôture des écarts** : les six écarts de l'audit sont au statut `clos`, chacun avec son champ
   `preuve` pointant un préfixe de `preuves-conformite/ECA-36xx/`. Les quatre du périmètre F6 (3601,
   3602, 3603, 3605) sont fermés par les phases 3 et 4 ; 3604 (revue des accès) et 3606 (transferts hors
   EEE) par leurs scénarios de phases 1-2. Chaque preuve est collectée par `ms-preuves` (automatique),
   déposée dans le compartiment verrouillé (inaltérable, horodatée), **avant** la date de l'audit de
   suivi.
2. **SoA à jour** : `soa.extrait-F6.md` montre la forme — une ligne par mesure (applicable O/N +
   justification, mise en œuvre, **lien de preuve**). Les mesures touchées par le F6 (A.8.15, A.8.16,
   A.8.8, A.5.24-26, A.8.13, A.8.24, et HDS activités 5-6) renvoient à leur mise en œuvre et à une preuve
   **existante**.
3. **État des preuves généré** : `etat-preuves.sh` croise le registre des écarts, la SoA et le contenu de
   `preuves-conformite` (dates, verrouillage) ; il produit `etat-preuves.md` et **échoue** si une preuve
   manque, a vieilli (au-delà d'un seuil par type), n'est pas verrouillée, ou si sa collecte n'est pas
   planifiée. C'est la vue de l'auditrice.
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

- Génération de l'état depuis `preuves-conformite` : dépend de `ms-preuves` (F6-S02).
- Précision de l'antériorité : dépend de l'horodatage des objets du RGW.

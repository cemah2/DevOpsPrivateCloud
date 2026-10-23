# Final F7 — Capstone

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | Profil de travail des blocs F et G (≈ 111 Go) ; PAR2 du F5 ; aucune VM ajoutée (VMID 3700-3799 réservés à tes essais) |
| **Prérequis** | Tout le workbook : F1 à F6 terminés (étiquettes `day0-v1` à `conformite-v1`) |
| **Durée indicative** | 50 à 70 heures |

## Contexte MédiSphère

Le **Groupement hospitalier Seine-et-Vallées** (GHSV, douze établissements) lance une consultation : il veut confier à un hébergeur certifié la prise de rendez-vous de ses patients, en marque blanche, raccordée à son annuaire et à son système d'information. Élodie Marchand, DSI du groupement, a publié un cahier des charges de trente pages et une date de soutenance. La direction de MédiSphère veut répondre avec sa propre plateforme. Claire Morel te confie la réponse technique : « Tu as construit cette plateforme. À toi de prouver qu'elle tient ce qu'on va promettre — architecture, chiffres, démonstration. Et ne promets rien que tu ne sais pas mesurer. »

## Objectifs

À la fin de ce final, tu sais :
- analyser un cahier des charges, poser les bonnes questions et chiffrer les exigences non fonctionnelles ;
- concevoir une architecture de production réelle et défendre ses choix par des ADR ;
- établir un coût complet sur plusieurs années et le comparer à des alternatives ;
- planifier un projet, ses risques et son exploitation ;
- livrer une preuve de concept qui respecte tous les standards de la plateforme (code, sécurité, mesures, reprise) ;
- présenter et défendre un dossier devant un jury technique et métier.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F7-S01 | Lire le cahier des charges | RED | ★★ | 1. Comprendre le besoin |
| F7-S02 | Les exigences non fonctionnelles, chiffrées | RED | ★★★ | 1. Comprendre le besoin |
| F7-S03 | L'architecture cible de production | RED | ★★★★ | 2. Concevoir |
| F7-S04 | Les décisions d'architecture | RED | ★★★ | 2. Concevoir |
| F7-S05 | Chiffrage et coût complet sur cinq ans | RED | ★★★ | 2. Concevoir |
| F7-S06 | Planning, risques et organisation du run | RED | ★★ | 2. Concevoir |
| F7-S07 | Le client en code | LIBRE | ★★★ | 3. Livrer |
| F7-S08 | Fédérer l'identité du client | LIBRE | ★★★★ | 3. Livrer |
| F7-S09 | Contrats d'interface et tests de contrat | LIBRE | ★★★ | 3. Livrer |
| F7-S10 | Des engagements de service mesurés | LIBRE | ★★★ | 3. Livrer |
| F7-S11 | Panne : la démonstration sous incidents | BF | ★★★★ | 3. Livrer |
| F7-S12 | Le dossier de soutenance | RED | ★★★ | 4. Soutenir |
| F7-S13 | La soutenance : questions du jury | Q | ★★★★ | 4. Soutenir |
| F7-S14 | Recette `capstone-v1` | LIBRE | ★★ | 4. Soutenir |

**Répartition** : 14 scénarios · 1 break & fix · 7 rédactions · 1 questions.

## Hôtes et objets

| Élément | Nom | Scénario |
|---|---|---|
| Cahier des charges du GHSV | [`ressources/S01/`](ressources/S01/) | S01 |
| Locataire du client | Capsule `ghsv`, espaces `ghsv-recette`, `ghsv-prod` ; `https://ghsv.apps.par1.medisphere.internal` (et `ghsv-recette.…`) | S07 |
| IdP du client (simulé) | royaume Keycloak `ghsv-idp` sur `idp01`, courtier d'identité OIDC d'alias `ghsv-idp` dans `medisphere` | S08 |
| Clés dédiées | `transit/ghsv-*` d'OpenBao | S07 |

Le GHSV et ses personnes sont **fictifs**. Détails figés : [`PLAN.md`](../../PLAN.md) §4.15.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F7 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break F7 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.

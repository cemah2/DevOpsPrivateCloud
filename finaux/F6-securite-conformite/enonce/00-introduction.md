# Final F6 — Introduction : l'audit à blanc

## Lundi, 9 h

Sophie Laurent a posé deux documents sur la table : le certificat HDS de MédiSphère, qui expire au printemps, et un courriel de deux grands clients qui exigent désormais un certificat ISO/IEC 27001 pour renouveler leur contrat.

> **De** : Sophie Laurent — RSSI
> **À** : toi
> **Cc** : Claire Morel, Karim Benali, Nadia Roussel, Julien Petit, Thomas Renaud (DPO)
> **Objet** : Audit à blanc HDS v2 et ISO 27001 — Auditia Santé, semaine du 16 novembre
>
> Bonjour,
>
> Notre certificat HDS doit passer sous le **nouveau référentiel** de 2024, et deux clients veulent un **ISO 27001** pour l'an prochain. Avant de payer un organisme certificateur, j'ai fait venir le cabinet **Auditia Santé** pour un audit à blanc : **Hélène Mercier**, auditrice principale, passera une semaine chez nous, dans nos dépôts, nos consoles et nos journaux.
>
> Je la connais. Elle ne lira pas nos politiques : elle demandera la preuve qu'elles s'appliquent, et elle demandera la preuve de la preuve. « Une politique sans preuve n'existe pas. Et une preuve qu'on fabrique la veille de l'audit non plus. »
>
> Nous avons deux semaines pour préparer : le périmètre et la déclaration d'applicabilité, une collecte de preuves **automatique et inaltérable**, une vraie revue des accès. Pendant l'audit, tu seras l'auditeur interne qui accompagne Hélène — et qui trouve nos écarts avant elle. Ensuite, on corrige ce qu'elle aura trouvé, par ordre de risque.
>
> Thomas, notre DPO, a une autre question, qu'il pose depuis des mois : « Si des données de patients fuitaient demain, qu'est-ce qu'on ferait, dans quel ordre, et qui préviendrait-on ? » J'aimerais lui répondre avec autre chose qu'un document.
>
> Sophie

---

## Ce que tu construis dans ce final

À la fin de F6, MédiSphère a passé son audit de suivi sans écart majeur ouvert, et sait répondre à une compromission. L'étiquette `conformite-v1` de `plateforme/medisphere` est posée en F6-S14.

| Phase | Fichier | Scénarios | Ce qui en sort |
|---|---|---|---|
| 1. Préparer l'audit | [`01-preparer-audit.md`](01-preparer-audit.md) | S01-S03 | périmètre, activités HDS, **déclaration d'applicabilité** ; outil **`ms-preuves`** et compartiment **`preuves-conformite`** verrouillé ; **revue des accès** outillée |
| 2. Auditer | [`02-auditer.md`](02-auditer.md) | S04-S07 | écarts cachés retrouvés (ECA-3611…), **audit technique** outillé, entretien avec l'auditrice, **rapport d'écarts** et **plan de remédiation** |
| 3. Remédier | [`03-remedier.md`](03-remedier.md) | S08-S09 | traçabilité inaltérable (ECA-3601), vulnérabilités et exceptions sous contrôle, sauvegardes chiffrées (ECA-3602, 3603) |
| 4. L'incident | [`04-incident.md`](04-incident.md) | S10-S13 | réponse à incident préparée, **conteneur compromis** (INC-6211) détecté, contenu, investigué, éradiqué ; notifications et post-mortem |
| 5. Bilan | [`05-bilan.md`](05-bilan.md) | S14 | audit de suivi, clôture des écarts, `conformite-v1` |

Un final ne réenseigne rien : il **combine** ce que tu as construit aux modules 08 (RGW), 13 (registre, Trivy, Cosign), 14 et 22 (audit Kubernetes, Loki), 16 (Velero), 21 (alertes), 24 (identités), 25 (secrets, `transit`), 26 (durcissement, Kyverno, Falco, Tetragon, OpenSCAP, kube-bench, kubescape), et aux finaux F2 (équipes, départ d'AxiomDev), F3 (gestion d'incident), F4 (changements) et F5 (PRA, si tu l'as fait).

---

## Les deux référentiels, en synthèse

Ce qui suit est une **carte**, pas un cours : les textes font foi. Liens : [`annexes/versions-finaux-F5-F7.md`](../../../annexes/versions-finaux-F5-F7.md) (cadre réglementaire relevé le 23/10/2026).

### HDS v2 (référentiel de certification, arrêté du 26 avril 2024)

- **Qui doit être certifié** : quiconque **héberge des données de santé pour le compte d'un tiers** (article L.1111-8 du code de la santé publique). MédiSphère héberge les données de ses clients (cabinets, établissements, responsables de traitement) : elle est hébergeur, et sous-traitant au sens du RGPD.
- **Six activités** (article R.1111-9 du CSP) : 1 sites physiques ; 2 infrastructure matérielle ; 3 infrastructure virtuelle ; 4 plateforme d'hébergement d'applications ; 5 administration et exploitation du SI contenant les données de santé ; 6 sauvegarde externalisée. On est certifié **pour les activités qu'on exerce réellement**.
- **Socle** : le référentiel s'appuie sur la certification **ISO/IEC 27001** du périmètre, et y ajoute des exigences propres à l'hébergement de santé.
- **Nouveautés de la v2** : hébergement physique des données **exclusivement dans l'EEE** ; transparence sur tout accès depuis un pays tiers ou toute soumission à une loi extra-européenne (information contractuelle des clients, **cartographie des transferts publiée** sur le site de l'hébergeur — exigences dites « de souveraineté ») ; fin de la période de transition pour les hébergeurs déjà certifiés : **16 mai 2026**.
- Textes : [arrêté du 26 avril 2024 (Légifrance)](https://www.legifrance.gouv.fr/), [communiqué de l'Agence du numérique en santé](https://esante.gouv.fr/espace-presse/publication-au-journal-officiel-du-referentiel-de-certification-hds-souverainete-des-donnees-et-ameliorations-du-referentiel) (le référentiel et sa foire aux questions sont publiés sur esante.gouv.fr).

### ISO/IEC 27001:2022

- Un **système de management** (chapitres 4 à 10 : contexte et périmètre, leadership, planification par l'appréciation des risques, support, fonctionnement, évaluation, amélioration) et une **annexe A de 93 mesures** en quatre thèmes : **organisationnelles** (5.1 à 5.37), **liées aux personnes** (6.1 à 6.8), **physiques** (7.1 à 7.14), **technologiques** (8.1 à 8.34).
- La **déclaration d'applicabilité** (*Statement of Applicability*, SoA) dit, pour **chacune** des 93 mesures, si elle est retenue, pourquoi, et comment elle est mise en œuvre ; une exclusion se **justifie**.
- Mesures nouvelles en 2022 qui te concernent directement : renseignement sur les menaces (5.7), services en nuage (5.23), continuité TIC (5.30), gestion de configuration (8.9), suppression (8.10), masquage (8.11), prévention de la fuite (8.12), surveillance (8.16), codage sécurisé (8.28).
- Écarts d'audit : **non-conformité majeure** (une exigence non satisfaite, ou un doute sérieux sur la capacité du système à atteindre ses résultats : bloque la certification), **mineure** (manquement ponctuel), **observation** (piste d'amélioration). C'est ainsi qu'Hélène classera ses constats.
- Texte : la norme est payante ([ISO](https://www.iso.org/standard/82875.html)) ; l'AFNOR en publie la version française.

### Et le RGPD

Une violation de données personnelles se notifie à la **CNIL dans les 72 heures** après en avoir pris connaissance, sauf si elle est peu susceptible d'engendrer un risque (article 33) ; elle s'inscrit **toujours** au registre des violations. MédiSphère, sous-traitante, prévient **ses clients** sans délai : ce sont eux qui notifient (articles 28 et 33.2). Ce sera la question de la phase 4.

---

## MédiSphère vue par un auditeur

Quelques faits de la fiction, que la plateforme ne montre pas et dont tu auras besoin dès S01 :

- **Les salles** : PAR1 et PAR2 sont des cages louées chez **DataCampus**, opérateur de colocation (fictif) certifié HDS pour l'**activité 1** (bâtiment, énergie, froid, accès physique). Tout ce qui est dans les cages — serveurs, baies, réseau de baie, disques — appartient à MédiSphère.
- **Les clients** : cabinets, centres de santé et établissements, responsables de traitement des données de leurs patients ; MédiSphère est leur hébergeur et leur sous-traitant.
- **Les fournisseurs « autour » de la plateforme** : **HelpNow**, outil de tickets en SaaS du support ; **SMS-Express**, qui envoie les rappels de MédiNotif ; la messagerie et la bureautique du SI interne (un autre prestataire, sans donnée de santé). Et une habitude d'équipe : un ingénieur du support assure deux semaines d'astreinte par an **depuis le Maroc**, par le VPN. Thomas Renaud en détaille les usages en S07.

Ce que MédiSphère fait certifier, et sur quelles activités, c'est la première question de S01. (À la fin du final, la réponse est stable : le F7 la reprend telle quelle devant un client.)

---

## Les personnages de ce final

| Personnage | Rôle | Ce qu'il ou elle attend |
|---|---|---|
| **Hélène Mercier** | auditrice principale, cabinet **Auditia Santé** (fictif) | des preuves vérifiables, pas des déclarations ; elle a un compte de **lecture** et ne touche à rien |
| **Thomas Renaud** | DPO de MédiSphère | la carte des données de santé, des transferts et des notifications ; la réponse à « et si ça fuyait ? » |
| Sophie Laurent | RSSI | pilote l'audit, valide la SoA, décide des écarts acceptés |
| Claire Morel | responsable infrastructure | arbitre les priorités de remédiation |
| Karim Benali | ingénieur plateforme senior | relit le code (outils, pipelines, politiques) |
| Nadia Roussel | support, astreinte | réponse à incident (phase 4) |
| Julien Petit | lead dev MédiAgenda | sa recette sera le théâtre de l'incident |

---

## État d'entrée

| Élément | État attendu | Contrôle |
|---|---|---|
| Plateforme | étiquette **`day1-v1`** (F2) au moins : socle v5, `ceph-par1` (RGW `https://rgw.par1.medisphere.internal`), `k8s-par1` avec les services des blocs C à G | `lab/bin/check F2 13` |
| Départ d'AxiomDev | F2-S12 fait : `marc.vidal` et `yanis.perrin` désactivés dans l'annuaire, bloqués dans GitLab, espace `mediagenda-axiomdev` retiré | `lab/bin/check F2 12` |
| Sécurité | `durcissement-v1` (M26) : analyses OpenSCAP hebdomadaires, Kyverno et ses dérogations dans `kyverno-exceptions`, Falco et Tetragon, quarantaine réseau | `lab/bin/check 26 46` |
| Secrets | `secrets-v1` (M25) : OpenBao, clé `transit/cosign-medisphere`, méthode `jwt` `gitlab` | `lab/bin/check 25 46` |
| Finaux conseillés | F3 (gestion d'incident), F4 (changements), F5 (PRA : preuves de continuité) | — |
| Pannes | aucune active (`ls ~/.local/state/workbook/pannes-actives/` vide) | — |

**Mémoire** : profil de travail des blocs F et G (socle v5 + `ceph-par1` + `k8s-par1`, ≈ 111 Go). Aucune VM ajoutée en phases 1 à 3 ; `c2-simule01` (VMID **3601**, VLAN 99, **10.10.99.66**, 512 Mo) n'existe que pendant l'incident (S11-S12), créé et détruit par le script d'injection.

---

## Le calendrier

| Moment | Ce qui se passe | Scénarios |
|---|---|---|
| J-15 à J-1 | préparation : périmètre et SoA, preuves automatiques, revue des accès | S01-S03 |
| Semaine d'audit (du 16 au 20 novembre 2026 dans la fiction) | Hélène sur place ; ses écarts cachés, ton audit technique, l'entretien, le rapport | S04-S07 |
| Les trois semaines suivantes | remédiation des écarts prioritaires | S08-S09 |
| Ensuite | préparation à l'incident… puis l'incident | S10-S13 |
| Trois mois après l'audit à blanc | audit de suivi, étiquette `conformite-v1` | S14 |

Tes dates réelles seront autres : les checks ne vérifient pas des dates de la fiction, ils vérifient l'état et les documents.

---

## Les règles du final (valables pour chaque scénario)

1. **Une preuve est produite par un système, pas par une personne.** Ce qui peut être collecté automatiquement l'est (S02) ; ce qui est rédigé l'est dans `plateforme/medisphere`, par MR, et sa date est celle de la fusion.
2. **Une preuve ne se modifie pas.** Le compartiment `preuves-conformite` est en verrouillage d'objets. ⚠️ En mode `COMPLIANCE`, **personne** ne peut supprimer ni écraser un objet avant son échéance, pas même toi : on essaie en `GOVERNANCE` avec une rétention courte, on passe en `COMPLIANCE` quand tout est juste.
3. **L'auditrice lit, elle n'écrit pas.** Tout ce que tu lui ouvres est en lecture seule, nominatif, et retiré après l'audit.
4. **Un écart a un numéro, une preuve et un responsable.** Registre `ECA-36xx` (format ci-dessous) ; on ne ferme un écart qu'avec une **preuve de clôture**.
5. **On corrige par le code.** Une correction faite à la main est une correction qui reviendra : elle se reporte dans le dépôt qui décrit l'objet, ou elle est retirée.
6. **Jamais de vraies données de santé hors production**, y compris pour un audit ou un incident simulé. L'incident de la phase 4 ne touche **que** `mediagenda-recette`, et il est simulé **sans code malveillant**.

---

## Conventions du final

**Documentation** (dépôt `plateforme/medisphere`, par MR) :

| Chemin | Contenu | Scénario |
|---|---|---|
| `docs/conformite/perimetre.md` | périmètre du SMSI, activités HDS exercées | S01 |
| `docs/conformite/soa.md` | déclaration d'applicabilité (93 mesures + exigences HDS) | S01 |
| `docs/conformite/preuves.md`, `cle-preuves.pub` | catalogue des preuves et de leur collecte, clé publique de signature des lots | S02 |
| `docs/conformite/revue-acces/AAAA-MM.md` | revue des accès du mois | S03 |
| `docs/conformite/audit-2026/audit-technique.md`, `audit-2026/technique/` | audit technique outillé et résultats bruts | S05 |
| `docs/conformite/audit-2026/rapport-ecarts.md` | rapport d'écarts de l'audit à blanc | S07 |
| `docs/conformite/ecarts/ECA-36xx[-<sujet>].md` | une fiche par écart, **le même fichier** de l'ouverture à la clôture | S04, S07, puis S08-S14 |
| `docs/conformite/journaux-audit.md`, `vulnerabilites.md`, `etat-preuves.md` | politique de journalisation, de traitement des vulnérabilités, état des preuves (généré) | S08, S09, S14 |
| `docs/conformite/plan-remediation.md` | plan de remédiation priorisé | S07 |
| `docs/conformite/transferts-hors-eee.md` | cartographie des transferts hors EEE | S07 |
| `docs/securite/incidents/INC-6211/` | dossier de l'incident | S11-S13 |
| `docs/securite/incidents/runbooks/RB-360-reponse-incident.md`, `RB-361-forensique-conteneur.md` | runbooks de réponse (rangés comme ceux du M24 et du M26 : `docs/securite/<thème>/runbooks/`) | S10 |
| `docs/securite/incidents/exercices/` | comptes rendus d'exercices | S10 |

**Format de la SoA** (les checks le lisent) : un tableau Markdown par thème, une ligne par mesure, colonnes dans cet ordre : `| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |`. Première colonne : l'identifiant de l'annexe A (`5.1` … `8.34`, `A.5.1` accepté) ; troisième : `Oui` ou `Non` ; une exclusion (`Non`) porte sa justification dans la quatrième colonne.

**Fiche d'écart** `ECA-36xx[-<sujet>].md` (les checks lisent l'en-tête) : un **en-tête YAML**, identique pour une fiche ouverte ou close, puis les sections.

```yaml
---
id: ECA-3601
titre: "Journaux d'audit centralisés mais non inaltérables"
origine: audit-2026 (Auditia Santé, Hélène Mercier)    # ou : F6-S04 (auditeur interne)
mesures: [8.15, 5.33]                                    # annexe A d'ISO/IEC 27001:2022, exigences HDS
gravite: majeur                                          # majeur | mineur | observation
statut: ouvert                                           # ouvert | en cours | clos
ouvert-le: 2026-11-18
echeance: 2026-12-11
responsable: karim.benali
remediation: SEC-3608                                    # ticket qui porte la correction
clos-le:                                                 # AAAA-MM-JJ, à la clôture
preuve:                                                  # à la clôture : lots/AAAA/MM/JJ/<LOT>/ (lot ms-preuves)
valideur:                                                # à la clôture : qui a accepté la preuve
---
```

Sections : **Constat**, **Référence** (mesure(s) ISO 27001 `x.y`, exigence HDS), **Preuves** (ce qui a été observé, où, quand), **Gravité** (majeur, mineur, observation), **Cause**, **Correction** (immédiate), **Action corrective** (ce qui empêche le retour), **Responsable**, **Échéance**, **Statut** et **Preuve de clôture** (le lot cité dans l'en-tête et les identifiants `P-…` qu'il contient). On ferme un écart en citant un lot `ms-preuves` **déjà déposé** : sa date précède celle de la clôture. Numérotation : `ECA-3601` à `ECA-3606` pour les écarts de l'audit (S07) ; `ECA-3611` et suivants pour ceux que tu trouves en S04.

**Tickets** : `SEC-36xx`, `PLAT-36xx`, `INC-62xx` (`xx` = numéro du scénario) ; ADR `ADR-0360…` ; runbooks `RB-360…`.

**Preuves automatiques** : identifiants `P-<DOMAINE>-NN` (ex. `P-IAM-01`), communs au catalogue de `plateforme/outils` et à `preuves.md`.

---

## Identités et variables des contrôles

Les checks lisent tout avec des identités de **lecture**. Trois fichiers d'identité S3 de plus, sur `adm01`, au format des autres (`AWS_ACCESS_KEY_ID=…` et `AWS_SECRET_ACCESS_KEY=…`, mode 600, dossier `~/.config/workbook/`). Chacun se remplit **depuis OpenBao** le jour où l'utilisateur RGW est créé, sans que les clés passent par l'écran ni par l'historique du shell (même méthode que `rgw-compartiment.sh` au F2-S08) :

| Fichier | Utilisateur RGW | Clés rangées dans OpenBao | Droits | Créé en |
|---|---|---|---|---|
| `s3-preuves-conformite-lecture.env` | `preuves-lecture` | `kv/plateforme/preuves/rgw-lecture` | lister et lire `preuves-conformite` | S02 |
| `s3-preuves-conformite-depot.env` | `preuves` | `kv/plateforme/preuves/rgw-ecriture` | écrire dans `preuves-conformite` (kit forensique, collecte manuelle) | S02, utilisé en S10-S12 |
| `s3-archive-audit-lecture.env` | `archive-audit-lecture` | `kv/plateforme/archive-audit/rgw-lecture` | lister et lire `archive-audit` | S08 |

Variables de `lab/lab.env`, toutes facultatives (les défauts conviennent au lab ; modèle dans `lab/lab.env.example`, section F6) :

| Variable | Défaut | Utilisée par |
|---|---|---|
| `WB_F6_PROJET_DOC` | `plateforme/medisphere` | tous les checks |
| `WB_F6_DOC` | `docs/conformite` | tous les checks |
| `WB_F6_PROJET_OUTILS` | `plateforme/outils` | S02, S03, S14 |
| `WB_F6_RGW_URL` | `https://rgw.par1.medisphere.internal` | S02, S08, S14 |
| `WB_F6_PREUVES_BUCKET` | `preuves-conformite` | S02, S08-S10, S14 |
| `WB_F6_PREUVES_ENV` | `~/.config/workbook/s3-preuves-conformite-lecture.env` | S02, S08-S10, S14 |
| `WB_F6_RETENTION_MIN` | `365` (jours, en `COMPLIANCE`) | S02 |
| `WB_F6_LOT_AGE_MAX_H` | `36` | S02 |
| `WB_F6_PASSERELLES` | `gw01 gw02` | S04, S11, S12 (checks et pannes) |
| `WB_F6_EXTERNES` | `marc.vidal yanis.perrin` | S03, S04 |
| `WB_F6_S04_NB`, `WB_F6_S04_ECARTS` | `4` (de 3 à 7), vide (liste forcée, ex. `1,3,5,7`) | S04 (panne) |
| `WB_F6_ARCHIVE_BUCKET`, `WB_F6_ARCHIVE_ENV` | `archive-audit`, `~/.config/workbook/s3-archive-audit-lecture.env` | S08 |
| `WB_F6_INCIDENTS`, `WB_F6_INCIDENT`, `WB_F6_RECETTE_NS` | `docs/securite/incidents`, `INC-6211`, `mediagenda-recette` | S10-S13 |
| `WB_F6_C2_VMID`, `WB_F6_C2_IP`, `WB_F6_C2_PORT`, `WB_F6_C2_GW`, `WB_F6_C2_BRIDGE`, `WB_F6_TPL` | `3601`, `10.10.99.66`, `4444`, `10.10.99.1`, `vsandbox`, `9000` | S11, S12 (panne et checks) |

Les checks relisent aussi `WB_GITLAB_*`, `WB_K8S_KUBECONFIG`, `WB_IPA_*`, `WB_AM_URL`, `WB_LOKI_URL`, `WB_GRAFANA_*`, `WB_MAILPIT_*`, `WB_PVE_HOST`, `WB_TIMEOUT` ; les pannes `WB_K8S_ADMIN_KUBECONFIG` et `WB_GITLAB_ADMIN_TOKEN_FILE`.

**Outils sur `adm01`** : `curl`, `jq`, `yq` (mikefarah v4), `kubectl` (compte `wb-checks`), `aws` (AWS CLI v2), `ldapsearch`, `sha256sum`, `cosign` (vérification des signatures, facultatif : contrôle ignoré et dit ignoré s'il manque), `ssh` vers `gw01`/`gw02` (`sudo -n nft list`). Ceux de l'audit technique (S05) : `oscap` (sur les VM), `kube-bench` (Job), `kubescape`, `trivy`, `ssh-audit`, `lynis` — installés au M26.

---

## Pour commencer

Lis [`01-preparer-audit.md`](01-preparer-audit.md). Les trois premiers scénarios ne changent rien à ce qui tourne pour les utilisateurs : ils fabriquent ce qu'Hélène viendra vérifier.

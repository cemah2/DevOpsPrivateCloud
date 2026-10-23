<!-- EXTRAIT F6-S14 : lignes de docs/conformite/soa.md (F6-S01) REMPLACÉES après la remédiation et -->
<!-- l'incident. Même format que la SoA complète (93 mesures, lue par les checks S01 et S14). -->
<!-- En tête du fichier : « Version 1.1 du 2027-02-15 », approuvée par Sophie Laurent (MR). -->

| Mesure | Intitulé | Applicable | Justification | Mise en œuvre | Preuve |
|---|---|---|---|---|---|
| 5.24 | Planification et préparation de la gestion des incidents | Oui | R, H : hébergeur de données de santé, obligation d'informer le client | RB-360 (rôles, gravités, volet réglementaire), RB-361, kit vérifié chaque nuit, exercice de table annuel (F6-S10) | P-CTL-01 ; ECA-3605 (lot du 2027-01-13) |
| 5.25 | Appréciation des événements et prise de décision | Oui | R, H | qualification selon RB-360/RB-262, décision de notification écrite et registre des violations (INC-6211) | P-SUP-01 ; `docs/securite/incidents/INC-6211/` |
| 5.26 | Réponse aux incidents de sécurité de l'information | Oui | R, H | quarantaine réseau, collecte RB-361, éradication et rotation (INC-6211) | `docs/securite/incidents/INC-6211/chronologie.md` |
| 5.28 | Recueil de preuves | Oui | R, H | collecte forensique RB-361 vers `preuves-conformite` (verrouillé), empreintes dans la chronologie | P-CTL-01 ; `preuves-conformite/INC-6211/` |
| 8.8 | Gestion des vulnérabilités techniques | Oui | R, H | Harbor/Trivy, délais par criticité (`vulnerabilites.md`), exceptions `EXC-V-nnn` à échéance, tableau `f6-vulnerabilites` (F6-S09) | P-VUL-01, P-VUL-03, P-CTL-01 ; ECA-3602 (lot du 2026-12-16) |
| 8.13 | Sauvegarde des informations | Oui | R, H : activité 6 | PBS, CNPG, Velero (dépôt Kopia à phrase tirée d'OpenBao), restauration éprouvée (F6-S09) | P-SAV-01, P-SAV-02, P-SAV-03 ; ECA-3603 (lot du 2026-12-17) |
| 8.15 | Journalisation | Oui | R, H | six sources dans le locataire `audit` de Loki, archive `archive-audit` en `COMPLIANCE` 1 an, manifeste signé, contrôle d'intégrité (F6-S08) | P-AUD-01, P-AUD-02, P-CTL-01 ; ECA-3601 (lot du 2026-12-09) |
| 8.16 | Activités de surveillance | Oui | R, H | Falco, Tetragon, alertes du ruler `audit`, alerte sur les silences longs (ECA-3611) | P-SUP-01, P-AUD-01 |
| 8.24 | Utilisation de la cryptographie | Oui | R, H | `transit` d'OpenBao (signatures des preuves et de l'archive), phrase Kopia et exports `age` (clés dans OpenBao) | P-SEC-01, P-SAV-03 |

> Chaque identifiant `P-…` est au catalogue (`preuves.md`) et présent dans les lots quotidiens ; chaque
> écart cité renvoie au lot de sa fiche. Une preuve qui manque ou a vieilli ressort dans
> [`etat-preuves.md`](etat-preuves.md), généré par `ms-etat-preuves`.

<!-- EXTRAIT F6 à fusionner dans docs/conformite/soa.md (déclaration d'applicabilité, F6-S01/S07). -->
<!-- Ne montre que les mesures ISO/IEC 27001:2022 et exigences HDS touchées par le F6, à jour après -->
<!-- remédiation (phases 3-4) et incident (INC-6211). La SoA complète couvre les 93 mesures + HDS v2. -->

## Mesures mises à jour par le F6

| Mesure | Applicable | Mise en œuvre | Preuve |
|---|---|---|---|
| A.8.15 Journalisation | Oui | Six sources d'audit → locataire `audit` de Loki ; archive verrouillée 1 an (F6-S08) | `preuves-conformite/ECA-3601/` |
| A.8.16 Surveillance des activités | Oui | Falco/Tetragon, alertes, archive d'audit ; alerte « trou de journalisation » | `preuves-conformite/ECA-3601/` |
| A.8.8 Gestion des vulnérabilités techniques | Oui | Trivy/Harbor, délais par criticité, exceptions datées, tableau de suivi (F6-S09) | `preuves-conformite/ECA-3602/` |
| A.8.13 Sauvegarde | Oui | Velero/Kopia chiffré, restauration éprouvée (F6-S09) | `preuves-conformite/ECA-3603/` |
| A.8.24 Chiffrement | Oui | Dépôt Velero et exports chiffrés côté serveur, clés dans OpenBao | `preuves-conformite/ECA-3603/` |
| A.5.24 Planification de la réponse à incident | Oui | RB-360, rôles, gravités (F6-S10) | `preuves-conformite/ECA-3605/` |
| A.5.25 Appréciation et décision sur les incidents | Oui | Qualification RB-360/RB-262, registre des violations (INC-6211) | `preuves-conformite/ECA-3605/`, `incidents/INC-6211/` |
| A.5.26 Réponse aux incidents | Oui | INC-6211 géré de bout en bout (confinement, forensique, éradication) | `incidents/INC-6211/` |
| A.5.28 Collecte de preuves | Oui | Kit forensique vérifié, RB-361, compartiment verrouillé | `preuves-conformite/ECA-3605/` |
| A.8.10 Suppression d'information | Oui | Minimisation des journaux (rétention par locataire), effacement prouvé (F4) | `preuves-conformite/ECA-3601/` |
| A.8.12 Prévention de la fuite de données | Oui | Refus réseau par défaut, Hubble, contrôle de dérive des NetworkPolicy (INC-6211) | `incidents/INC-6211/post-mortem.md` |
| HDS v2 activité 5 (administration et exploitation) | Oui | Traçabilité inaltérable, réponse à incident testée | `preuves-conformite/ECA-3601/`, `ECA-3605/` |
| HDS v2 activité 6 (sauvegarde) | Oui | Sauvegardes chiffrées, restauration éprouvée | `preuves-conformite/ECA-3603/` |

> Chaque lien de preuve pointe un préfixe **existant** du compartiment verrouillé `preuves-conformite`.
> Un lien mort ou un préfixe vide est un écart (contrôle `etat-preuves.sh`).

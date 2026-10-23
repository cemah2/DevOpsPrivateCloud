# Exercice de table — réponse à incident (janvier 2027)

> `plateforme/medisphere` — `docs/securite/incidents/exercices/2027-01-exercice-table.md` (F6-S10, SEC-3610).
> Animé par Sophie Laurent (RSSI). Participants : astreinte Plateforme, Karim Benali, Nadia Roussel,
> Thomas Renaud (DPO), Claire Morel. Durée : 90 min, sur table (aucune action sur le lab).

## Scénario joué

« Mardi 9 h 40. Alertmanager envoie une alerte Falco : shell interactif dans un conteneur de l'API de
**production**, puis connexions sortantes vers une adresse inconnue. Nadia transfère. Personne n'a
annoncé d'intervention. » Le groupe déroule RB-360 à voix haute, chronométré, sans toucher au lab.

## Déroulé et minutage

| T+ | Étape | Qui | Décision/geste annoncé |
|---|---|---|---|
| 0 | Réception, ouverture INC | Responsable | Ouvre INC-62xx, gravité **G1** (production) |
| 2 min | Qualification | Responsable | Sources : Falco, audit API (qui a fait l'exec ?), Hubble |
| 6 min | Escalade | Responsable | RSSI **et** DPO (G1 → DPO immédiat) |
| 10 min | Confinement | Responsable + Collecte | Quarantaine + sortie du contrôleur (RB-262), **pas** de suppression |
| 20 min | Collecte | Collecte | RB-361, preuves dans `preuves-conformite` |
| 40 min | Portée | RSSI | Données réelles touchées ? accès prod ? |
| 60 min | Décision réglementaire | DPO + RSSI | Registre art. 33.5 ; CNIL si violation ; clients HDS |
| 75 min | Communication | Claire | Message d'état |

## Trous trouvés (et actions)

| Trou | Gravité | Action | Responsable | Échéance |
|---|---|---|---|---|
| Le numéro de téléphone du DPO n'était pas dans la trousse d'astreinte | moyen | Ajouter contacts RSSI/DPO à la trousse (F3) | astreinte | 2027-01-22 |
| Personne ne savait où était l'identité de dépôt des preuves | fort | `ms-verifier-kit-forensique` en CI + doc dans RB-361 | Karim | 2027-01-12 |
| Hésitation sur « qui décide de notifier la CNIL » | fort | RB-360 §5 clarifié : DPO décide, RSSI qualifie | Sophie | 2027-01-07 |
| Doute sur le signalement CERT Santé | moyen | Vérifier le périmètre sur Légifrance, noter dans RB-360 | Thomas | 2027-02-01 |
| Point de contrôle de conteneur jamais essayé | moyen | Éprouver sur `wb-essais`, écrire le résultat dans RB-361 | Karim | 2027-01-12 |

## Conclusion

La procédure tient, mais trois trous (identité de dépôt, décision CNIL, contacts) auraient coûté du
temps le jour J. Les actions ci-dessus sont suivies à la revue de suivi (F6-S14). Prochain exercice :
joué par une personne qui n'a pas écrit la procédure.

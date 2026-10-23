# Registre des violations de données — entrée INC-6211

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/registre-violations.md` (F6-S13).
> Tenu au titre du **RGPD art. 33.5** : toute violation (et, en pratique, tout événement analysé) est
> consignée, **même sans notification**. Propriétaire du registre : Thomas Renaud (DPO).

| Champ | Valeur |
|---|---|
| Référence | INC-6211 |
| Date de l'événement | 2027-01-20, 07:50 UTC (shell ouvert) |
| Date de prise de connaissance | 2027-01-20, 07:52 UTC (alerte Falco) |
| Nature | Activité anormale dans un conteneur de `mediagenda-recette` : shell interactif, lecture d'un jeton de compte de service, tentative de connexion sortante vers une adresse non prévue (simulation d'exfiltration) |
| Type d'atteinte | Confidentialité (tentative) ; intégrité : non ; disponibilité : non |
| Catégories de personnes concernées | **Aucune** (données de recette fictives/pseudonymisées) |
| Nombre approximatif de personnes | 0 |
| Catégories de données | Aucune donnée personnelle réelle |
| Nombre approximatif d'enregistrements | 0 |
| Conséquences probables | Aucune conséquence établie pour des personnes (aucune donnée réelle, pas d'accès production, rien de sorti) |
| Mesures prises | Confinement (quarantaine réseau, pod sorti du contrôleur) ; collecte des preuves (verrouillées) ; éradication de la cause (retrait de la politique réseau trop large / renouvellement du jeton) ; rotation des secrets exposés ; retour en service sain |
| Décision de notification | CNIL : **non** (pas de violation de données personnelles) ; personnes : sans objet ; clients : information « pour mémoire » ; CERT Santé : a priori non (à vérifier sur Légifrance) |
| Justification | Portée établie en F6-S12 : recette fictive, pas d'accès production, aucune donnée sortie |
| Décideurs | DPO (Thomas Renaud), RSSI (Sophie Laurent) |
| Pièces | `preuves-conformite/INC-6211/` (empreintes dans `chronologie.md`) |

## Note

L'inscription au registre **ne vaut pas** reconnaissance d'une violation : elle documente qu'un événement
a été détecté, analysé et tranché. C'est la pièce que l'on présente à l'auditeur pour démontrer la
maîtrise du processus (art. 33.5).

# INC-6211 — Décision de notification

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/decision-notification.md` (F6-S13).
> Co-signée : Thomas Renaud (DPO), Sophie Laurent (RSSI). Fondée sur la **portée établie** en F6-S12
> (`chronologie.md`). Date de décision : 2027-01-20.

## 1. Y a-t-il violation de données à caractère personnel (RGPD art. 4.12) ?

**Non.** Preuves (F6-S12) :
- `mediagenda-recette` ne contient que des données **fictives ou pseudonymisées**
  (`docs/conformite/perimetre.md`) : pas de donnée à caractère personnel réelle de patient.
- **Aucun accès à la production** n'est établi : le jeton de compte de service et les droits associés
  sont bornés à l'espace de recette (audit API).
- **Aucune donnée n'est sortie** : la connexion vers le C2 a été soit jetée (vecteur 1), soit aboutie
  mais sans transport d'octet utile (vecteur 2, journaux du C2).

Il n'y a donc pas d'atteinte à la confidentialité, à l'intégrité ou à la disponibilité de données
personnelles réelles : **pas de violation** au sens du RGPD.

## 2. Notification à la CNIL (art. 33) ?

**Non requise** : en l'absence de violation de données personnelles, l'obligation de notification sous
72 h ne s'applique pas. **Mais** l'événement et cette analyse sont **inscrits au registre des violations**
(art. 33.5, voir `registre-violations.md`) : on a pris connaissance d'un événement de sécurité et on doit
pouvoir démontrer qu'on a tranché.

> *Si les faits avaient différé* (données réelles, accès prod, données sorties) : notification CNIL dans
> les 72 h. Projet prêt à l'emploi en annexe (champs du téléservice CNIL), à ne pas envoyer en l'état.

## 3. Information des personnes concernées (art. 34) ?

**Sans objet** : pas de violation, donc pas de risque élevé pour des personnes.

## 4. Information des clients (contrat HDS) ?

**Information « pour mémoire »**, pas une notification de violation : au titre de la transparence
contractuelle, les clients responsables de traitement sont informés qu'un incident de sécurité a eu lieu
**en recette**, sans impact sur leurs données ni sur la production. Projet de message en annexe. Ce
n'est **pas** une notification de violation de données (à ne pas confondre : cela déclencherait leurs
propres obligations).

## 5. Signalement d'incident grave (CERT Santé, art. L.1111-8-2) ?

**A priori non** : l'incident n'a pas affecté un système d'information de santé en production ni la
disponibilité/intégrité/confidentialité de données de santé. **À vérifier sur Légifrance** (périmètre et
seuil exacts du signalement : arrêté du 30 octobre 2017 et textes postérieurs) avant toute conclusion
définitive ; en cas de doute, le DPO consulte l'ANS/CERT Santé.

## 6. Synthèse

| Obligation | Décision | Fondement |
|---|---|---|
| Registre des violations (33.5) | **Oui** (inscrit) | trace de la décision |
| CNIL (33) | Non | pas de violation de données personnelles |
| Personnes (34) | Sans objet | pas de risque élevé |
| Clients HDS | Information « pour mémoire » | transparence contractuelle |
| CERT Santé (L.1111-8-2) | A priori non — **à vérifier sur Légifrance** | pas d'impact SI de santé en prod |

## Annexes (projets, à ne pas envoyer en l'état)

- `annexe-projet-cnil.md` : notification CNIL (si les faits l'avaient exigée).
- `annexe-information-client.md` : information client « pour mémoire ».

# INC-6211 — Décision de notification

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/decision-notification.md` (F6-S13).
> Co-signée : Thomas Renaud (DPO), Sophie Laurent (RSSI). Fondée sur la **portée établie** en F6-S12
> (`chronologie.md`). Date de décision : 2027-01-20.

## 0. Rôle de MédiSphère pour les données en cause

- Recette de MédiAgenda (`mediagenda-recette`), données **fictives** produites par MédiSphère : MédiSphère
  est **responsable de traitement** (s'il y avait des données personnelles).
- Production de MédiAgenda (données de patients des établissements clients) : MédiSphère est
  **sous-traitant** (RGPD art. 28 ; contrat HDS). En cas de violation, elle **notifie le client dans les
  meilleurs délais** après en avoir pris connaissance (art. 33.2) ; c'est le client, responsable de
  traitement, qui notifie la CNIL (art. 33.1) et informe les personnes (art. 34). Délais et circuit
  contractuels : **à vérifier dans les contrats** (clause de sous-traitance et contrat HDS de chaque
  client).

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
72 h ne s'applique pas. L'art. 33.5 n'impose de documenter que les violations ; l'événement et cette
analyse sont **quand même inscrits au registre** (`registre-violations.md`, bonne pratique) : on doit
pouvoir démontrer qu'on a analysé et tranché.

> *Si les faits avaient différé* : données de patients d'un client touchées → notification **au client**
> sans délai (art. 33.2, annexe B), qui notifie la CNIL ; données dont MédiSphère est responsable →
> notification CNIL dans les 72 h (annexe A). Projets ci-dessous, à ne pas envoyer en l'état.

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
| Registre (33.5 et bonne pratique) | **Oui** (inscrit) | trace de l'analyse et de la décision |
| CNIL (33) | Non | pas de violation de données personnelles |
| Personnes (34) | Sans objet | pas de risque élevé |
| Clients HDS | Information « pour mémoire » | transparence contractuelle |
| CERT Santé (L.1111-8-2) | A priori non — **à vérifier sur Légifrance** | pas d'impact SI de santé en prod |

## Annexe A — Projet de notification à la CNIL (pour mémoire, non envoyé)

Contenu minimal de l'art. 33.3 ; le formulaire en ligne de la CNIL le reprend (champs exacts : à relever
sur le téléservice le jour venu).

| Rubrique (art. 33.3) | Contenu qui aurait été déclaré |
|---|---|
| a) Nature de la violation | Accès non autorisé à un conteneur applicatif, connexion sortante vers une adresse inconnue ; confidentialité (possible) |
| a) Catégories et nombre approximatif de personnes | *(selon la portée établie : ex. patients d'un établissement, N ≈ …)* |
| a) Catégories et nombre approximatif d'enregistrements | *(ex. rendez-vous : identité, date, praticien — données de santé)* |
| b) Contact | Thomas Renaud, DPO de MédiSphère |
| c) Conséquences probables | *(atteinte à la confidentialité de données de santé ; risque pour les personnes à qualifier)* |
| d) Mesures prises ou proposées | Confinement, collecte des preuves, éradication de la cause, rotation des secrets, information des personnes si risque élevé (art. 34) |
| Délai | Dans les 72 h après la prise de connaissance (07:52 UTC) ; notification en plusieurs temps si l'enquête n'est pas finie (art. 33.4) |

## Annexe B — Information des clients

**B.1 (envoyée, pour mémoire)** — *Objet : [MédiSphère] Incident de sécurité en recette, sans impact sur
vos données.* « Le 20 janvier 2027, une activité anormale a été détectée et confinée dans notre
environnement de **recette** de MédiAgenda, qui ne contient que des données fictives. Aucune donnée de
production, aucune donnée de vos patients n'est concernée ; il ne s'agit pas d'une violation de données
au sens du RGPD. Nous vous en informons au titre de la transparence prévue par notre contrat. Contact :
DPO de MédiSphère. »

**B.2 (projet, si des données du client avaient été touchées)** — notification de violation au
responsable de traitement (art. 33.2), sans délai : nature, données et personnes concernées (estimation),
chronologie, conséquences probables, mesures prises, contact du DPO, et les éléments dont le client a
besoin pour **ses** décisions (CNIL sous 72 h, information des personnes, signalement de l'établissement
au titre de l'art. L.1111-8-2 — à vérifier sur Légifrance).

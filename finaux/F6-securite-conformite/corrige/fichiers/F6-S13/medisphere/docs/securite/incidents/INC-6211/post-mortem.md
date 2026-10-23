# INC-6211 — Post-mortem

> `plateforme/medisphere` — `docs/securite/incidents/INC-6211/post-mortem.md` (F6-S13).
> **Sans recherche de coupable.** Rédigé sous 5 jours ouvrés (RB-360 §6). Relu par Sophie Laurent (RSSI)
> et Thomas Renaud (DPO).

## Résumé

Le 2027-01-20, une activité anormale a été détectée dans un conteneur de l'API de MédiAgenda en recette :
shell interactif, lecture d'un jeton de compte de service, tentative de connexion sortante vers une
adresse non prévue. Confiné en 20 minutes, éradiqué, clos le jour même. Aucune donnée réelle touchée,
aucun impact production.

## Chronologie

Voir `chronologie.md` (datée, sourcée, preuves verrouillées). Points clés : détection 07:52, qualification
07:58, confinement 08:10, éradication 09:30, clôture 10:10.

## Impact

- Utilisateurs : **aucun** (recette, pas de production, pas d'interruption).
- Données : **aucune** donnée personnelle réelle touchée ; pas de violation (registre art. 33.5).
- Temps : ~20 min jusqu'au confinement, ~2 h jusqu'à la clôture.

## Cause racine (mécanisme, pas personne)

Selon le vecteur observé :
- **Une règle réseau de sortie temporaire n'a jamais été retirée, et aucun contrôle ne la voyait.** La
  politique `legacy-sortie-large` (MR de mars 2026) autorisait la sortie vers un sous-réseau large ; elle
  a permis à la connexion sortante d'aboutir. Le mécanisme en défaut est l'absence de **contrôle de
  dérive** des politiques réseau et l'absence de revue de leur durée de vie.
- *(ou)* **Un jeton de compte de service était monté sans besoin** et pouvait servir à interroger l'API.
  Le mécanisme en défaut est le non-respect de la norme « charge sûre » C6 (jeton non monté) sur cette
  charge.

Facteur aggravant commun : l'`exec` interactif humain restait possible en recette (il ne l'est plus en
production depuis le F3).

## Ce qui a marché

- Détection Falco/Tetragon → Alertmanager → Mailpit : l'alerte est arrivée en moins de deux minutes.
- Quarantaine réseau posée à l'avance (M26) : confinement immédiat sans redémarrer le conteneur.
- Preuves inaltérables (archive d'audit F6-S08, compartiment verrouillé) : chronologie incontestable.
- Procédure (RB-360/361) et kit vérifié (F6-S10) : pas d'improvisation.

## Ce qui a coûté

- Hésitation initiale sur le vecteur (jeton vs politique réseau) : quelques minutes avant de regarder
  Hubble (verdict `FORWARDED`/`DROPPED`).
- La règle réseau large n'était vue par aucun tableau de bord.

## Actions

| Action | Mécanisme visé | Responsable | Échéance |
|---|---|---|---|
| Contrôle de dérive des NetworkPolicy (sortie large = alerte) | règle réseau non vue | Karim | 2027-02-05 |
| `exec` humain hors bris de glace interdit en recette (`prod-gestes-interactifs` étendu) | accès interactif | astreinte | 2027-01-29 |
| Jeton de compte de service non monté quand inutile (norme C6) sur les API de recette | jeton réutilisable | Julien | 2027-02-10 |
| Règle Falco/Tetragon dédiée « reconnaissance API depuis un pod applicatif » | détection plus précoce | Sophie | 2027-02-12 |
| Revue de la durée de vie des NetworkPolicy à chaque MR | règle oubliée | Karim | continu |

## Suivi

Présenté à la revue de suivi (F6-S14) ; les actions sont des preuves de clôture d'ECA-3605 et nourrissent
la SoA (A.5.26, A.8.16).

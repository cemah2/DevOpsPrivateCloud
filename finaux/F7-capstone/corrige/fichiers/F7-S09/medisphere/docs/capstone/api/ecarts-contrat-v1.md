# Écarts entre le contrat v1 du GHSV et l'API de MédiAgenda

> F7-S09 (DEV-3709). Contrat : annexe A1 du CCTP (`api-rendez-vous-v1.yaml`, OpenAPI 3.1.0, version 1.0.0), copié sans modification dans `mediagenda/api` (`contrats/ghsv/`). API comparée : `mediagenda/api` à la fin du F4 (rappel du M27 compris), description `/openapi.json` de `ghsv-recette`.
> Méthode : comparaison des deux descriptions (`oasdiff breaking`, contrat en référence), puis lecture humaine de ce qu'un schéma ne dit pas (sens des codes, fuseaux, pagination, idempotence). Relu par Julien Petit et Karim Benali.

## Synthèse

| Classe | Nombre | Écarts |
|---|---|---|
| Bloquant pour le DPI | 4 | E-01, E-02, E-03, E-04 |
| Gênant | 3 | E-05, E-06, E-08 |
| Sans effet | 3 | E-07, E-09, E-10 |

Toutes les adaptations sont **additives** : un cabinet de MédiSphère qui n'envoie ni jeton ni nouveau paramètre voit la même API (`MEDIAGENDA_PORTEES` absente de ses overlays). Aucune migration de schéma.

## Écarts

| ID | Contrat (opération, élément) | API actuelle | Classe | Décision | Effet sur les cabinets |
|---|---|---|---|---|---|
| E-01 | `listerRendezVous` : paramètres `praticien`, `du`, `au` | seulement `limite` ; les autres paramètres sont **ignorés en silence** : le DPI recevrait les 100 premiers rendez-vous de tout le groupement | Bloquant (le rapprochement toutes les 5 min de R-01 serait faux, et lent) | Adapter l'API : filtres facultatifs, `au` exclu, tri par début ; 422 si `au` ≤ `du` | Aucun (paramètres facultatifs) |
| E-02 | `deplacerRendezVous` : `PATCH /rendez-vous/{id}`, atomique, 409 si pris | n'existe pas (405) ; le DPI ferait « annuler + créer », non atomique, nouvel identifiant | Bloquant | Adapter l'API : une instruction `UPDATE` (l'index unique `(praticien, debut)` rend le 409 atomique) ; invalidation du cache des deux jours | Aucun (nouvelle opération) ; utilisable aussi par les cabinets |
| E-03 | Authentification OAuth 2.0 « client credentials », jeton porteur, portées `rdv:lecture` et `rdv:ecriture`, 401 sans jeton | aucune authentification | Bloquant | Adapter la **publication** (mandataire `oauth2-proxy-dpi` qui vérifie le jeton émis par le client `ghsv-dpi` du royaume `medisphere`) **et** l'API (contrôle des portées, `MEDIAGENDA_PORTEES=oui`) ; adresse du serveur d'autorisation communiquée au GHSV à la notification (le contrat le prévoit) | Aucun (désactivé par défaut) |
| E-04 | `servers` : `https://rendez-vous.ghsv.example/api/v1` (domaine du GHSV, EF-01) | `ghsv.apps.par1.medisphere.internal` (lab) | Bloquant en production, pas dans le lab | Adapter la publication : CNAME du GHSV vers `ghsv.medisphere.internal`, nom ajouté à la Gateway, certificat. **Question Q au GHSV** : certificat émis par leur autorité ou par ACME public ? Qui renouvelle ? | Aucun |
| E-05 | `id` : entier ≥ 1 ; « valeur hors bornes » → 422 | `GET /rendez-vous/0` → 404 | Gênant (un DPI qui teste ses erreurs verrait 404 au lieu de 422) | Adapter l'API : `Path(ge=1)` sur les trois opérations | Un cabinet qui demandait l'identifiant 0 reçoit 422 au lieu de 404 : jugé sans conséquence (aucun identifiant 0 n'existe ; relu par Julien) |
| E-06 | `deplacerRendezVous` conserve « le choix de rappel » | le rappel est publié vers MédiNotif à la création (M27-E08) | Gênant : un rendez-vous déplacé pourrait être rappelé à l'ancienne heure | Adapter l'API si la version publie l'heure dans le message ; sinon rien (MédiNotif relit l'heure). **Décision** : publier un message au déplacement (même routage), à confirmer avec l'équipe MédiNotif (DEV-3709 bis) | Aucun |
| E-07 | 422 : `Erreur.detail` = texte ou liste de `DetailValidation {loc, msg, type}` | FastAPI renvoie aussi `input`, `ctx`, `url` dans chaque détail | Sans effet (le schéma du contrat n'interdit pas les propriétés en plus, et le contrat dit que le DPI ignore les champs inconnus) | Rien ; **mais** `input` peut recopier une donnée envoyée (nom du patient) dans la réponse d'erreur : acceptable vers l'émetteur lui-même, à ne jamais journaliser (vérifié : les erreurs 422 ne sont pas journalisées avec leur corps) | — |
| E-08 | Codes : le contrat ne liste pas 403 | — | Gênant (un jeton sans la bonne portée doit répondre quelque chose) | 403 `insufficient_scope` (RFC 6750 §3.1), corps `Erreur`. **Question au GHSV** : accepte-t-il 403, ou veut-il 401 ? Décision provisoire écrite ici, test `test_portee_insuffisante_403` | — |
| E-09 | `Creneaux.fuseau` = `Europe/Paris` ; créneaux de 30 min, 8 h-12 h, 14 h-18 h | identique (`MEDIAGENDA_FUSEAU`) | Sans effet | Rien | — |
| E-10 | Identifiants de praticiens du DPI : `P` + six chiffres (R-07) | texte libre, 100 caractères | Sans effet | Rien dans l'API ; la reprise des données (EF-08) et l'export quotidien des praticiens (R-07) devront utiliser ces identifiants | — |

## Ce que le contrat ne dit pas (questions et décisions provisoires)

1. **Pagination de `listerRendezVous`** : `limite` ≤ 1000, sans curseur. Avec 600 praticiens interrogés toutes les 5 min (R-01) et un filtre par praticien et par journée, 1000 suffit. Sans filtre, le DPI pourrait tronquer sans le savoir : décision provisoire, aucun en-tête ajouté ; demander au GHSV si un curseur est souhaité pour la v1.1 (R-06).
2. **Idempotence de la création** : un `POST` répété après une coupure réseau crée un doublon… ou un 409 (même praticien, même heure). Le 409 protège ici par construction ; question posée pour la v1.1 (en-tête de clé d'idempotence).
3. **Annuler n'efface pas l'historique** pour le GHSV (ERV-02 : « historique »). L'API supprime la ligne aujourd'hui. Avant la production : annulation logique (colonne `annule_le`, migration *expand*) pour les instances de clients ; lot de construction (risque à `risques.md`).
4. **Charge du rapprochement** : 600 requêtes / 5 min = 2 req/s de lecture filtrée : négligeable devant la pointe de 150 req/s (ENF-02), mais à inclure dans le profil de charge k6 du GHSV.

## MédiAgenda → MédiDoc : le même dispositif, dans l'autre sens

Ici MédiAgenda est **producteur** et le contrat est écrit par son **consommateur** (le GHSV) : nous le vérifions dans notre CI. Entre MédiAgenda (consommateur) et MédiDoc (producteur, `POST /api/v1/rendez-vous/{id}/pieces-jointes`, M23 et M29-E12) :
- **qui écrit** : l'équipe MédiAgenda écrit ce qu'elle appelle (opérations, champs lus, codes traités) dans un fichier de contrat versionné dans `mediagenda/api` (`contrats/medidoc/`), produit par ses tests (Pact, ou un OpenAPI réduit aux opérations utilisées) ;
- **qui vérifie** : la CI de `medidoc/api` récupère les contrats de ses consommateurs (paquet générique GitLab publié par MédiAgenda, ou Pact Broker) et rejoue les interactions contre MédiDoc lancé sans dépendances ; une MR de MédiDoc qui casse un consommateur échoue **chez MédiDoc**, avant la recette ;
- **quand** : à chaque MR des deux côtés ; « can-i-deploy » avant la promotion en production.
Ce dispositif remplace la découverte en recette (M29) d'un changement de MédiDoc qui casse MédiAgenda ; il ne remplace pas le test de bout en bout de la recette (réseau, TLS, politiques).

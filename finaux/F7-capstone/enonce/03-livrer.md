# Final F7 — Phase 3 : Livrer

Le dossier est écrit (phases 1 et 2) : exigences chiffrées, architecture, décisions, coût, planning. Il reste à **prouver**. Élodie Marchand l'a dit sans détour à Claire Morel : « Tout le monde nous promet du 99,9 %. Montrez-moi votre plateforme qui tourne, avec nos agents, notre API et nos clés. » Cette phase livre une preuve de concept qui respecte **tous** les standards de la plateforme (code, revue, sécurité, mesures, reprise) : le GHSV doit pouvoir être retiré, reconstruit ou audité à partir du code seul.

Prérequis de la phase : phases 1 et 2 terminées (`docs/capstone/exigences.md`, `architecture.md`, ADR-0370 et suivantes sur `main`) ; F2 (`plateforme/equipes`), F5 (PAR2) et F6 (`ms-preuves`) terminés.

Les réponses du GHSV aux candidats ([`ressources/S02/reponses-aux-candidats.md`](../ressources/S02/reponses-aux-candidats.md)) s'imposent aussi à la preuve de concept : R-14 et R-17 (clés, réversibilité : S07), R-16 (MFA à la charge du GHSV : S08), R-01, R-06 et R-07 (appels du DPI, pièces jointes hors v1, identifiants des praticiens : S09), R-09, R-10 et R-11 (mesure, centile, rendez-vous de la fenêtre perdue : S10).

**Conventions de la phase** (valeurs figées, reprises par les checks) :

| Élément | Valeur |
|---|---|
| Fichier du client | `equipes/ghsv.yaml` de `plateforme/equipes` |
| Locataire, espaces | Capsule `ghsv` ; `ghsv-recette`, `ghsv-prod` |
| Publication patients et DPI | `https://ghsv.apps.par1.medisphere.internal` (prod), `https://ghsv-recette.apps.par1.medisphere.internal` (recette) |
| Publication agents | `https://ghsv-agents.apps.par1.medisphere.internal` (et `ghsv-agents-recette.…`) |
| Nom de service indépendant du site | `ghsv.medisphere.internal` (CNAME, TTL 60 s, même mécanisme que les noms globaux du F5) |
| IdP simulé du client | royaume Keycloak `ghsv-idp` sur `idp01` |
| Fournisseur d'identité dans `medisphere` | alias `ghsv-idp` ; groupe Keycloak des agents `ghsv-agents` |
| Clés dédiées | moteur `transit` d'OpenBao, clés `ghsv-*` |
| Documentation | `docs/capstone/` de `plateforme/medisphere` (runbooks dans `docs/capstone/runbooks/`) |
| Tickets | PLAT-37xx, DEV-37xx (`xx` = numéro du scénario) ; runbooks RB-371 à RB-374 |

> ⚠️ **Mémoire du lab.** Le profil de travail (≈ 111 Go) n'a presque plus de marge. Le locataire `ghsv` tient dans un budget de **2 CPU et 3 Gio** de *requests* au total (recette + production) : dimensionne en conséquence et vérifie le bilan de capacité de `plateforme/equipes` avant toute MR. Aucune VM n'est ajoutée ; les VMID 3700-3799 restent libres pour tes essais.

---

### F7-S07 — Le client en code  `LIBRE` `★★★`

> **Ticket PLAT-3707** — *De : Claire Morel* — *Copie : Karim Benali, Julien Petit, Sophie Laurent*
> Le GHSV n'est pas une équipe de plus : c'est un client, avec un contrat, une date de fin et des données qui lui appartiennent. Mais je ne veux pas d'un second mécanisme : l'arrivée d'un client passe par le même chemin que celle de MédiVisio, **un fichier** dans `plateforme/equipes`, une MR relue. Ce fichier doit dire tout ce qui le distingue d'une équipe interne : son instance de MédiAgenda, ses adresses, ses clés, sa réversibilité. Et Sophie veut une preuve dès maintenant que le jour où le contrat s'arrête, on sait **rendre** ses données en format ouvert et **détruire** le reste. Pas un engagement : un export testé.

**Objectifs pédagogiques**
- Étendre un format « en code » (schéma, générateur, gabarits, tests) sans casser l'existant, pour un nouveau type d'occupant de la plateforme.
- Livrer une instance dédiée d'une application en marque blanche par le chemin GitOps normal.
- Rattacher à un client des clés de chiffrement dédiées et en tirer une stratégie de fin de contrat (effacement cryptographique).
- Concevoir, outiller et **éprouver** un export de réversibilité.

**Prérequis** : F2-S02 (format v1 et générateur), F2-S07 et F2-S10 (évolutions du format), M28 (Capsule), M25 (OpenBao, ESO, `transit`), M20 (Argo CD, `mediagenda/deploiement`), M27 (CNPG), F6-S09 (chiffrement des exports) ; phase 2 de ce final (ADR de l'hébergement du client).
**Durée indicative** : 5 à 6 h.

**Contexte technique**
- Le format de `plateforme/equipes` ne change que **par ajout** (README du projet, « Évolutions du format après S02 ») : schéma, générateur, gabarits et tests dans la même MR, fichiers rendus portant l'en-tête « GÉNÉRÉ … NE PAS MODIFIER ICI ».
- Le contact d'une équipe est une adresse `@medisphere.internal` (schéma) ; les personnes d'un fichier d'équipe sont des personnes **de l'annuaire de MédiSphère**. Les agents du GHSV, eux, n'y entreront jamais (S08).
- MédiAgenda n'a ni interface d'administration ni authentification (voir `apps/mediagenda/README.md`) : la « marque blanche » se joue dans ce que voit l'utilisateur (adresse, réponses, description OpenAPI servie sur `/openapi.json`), pas dans du code de présentation. Le titre de cette description est aujourd'hui écrit en dur : un correctif de `mediagenda/api` est permis (`apps/` reste inchangé), à condition de ne rien changer pour les cabinets existants.
- Données du locataire : **fictives** (patients et praticiens de démonstration) en recette **et** en production de démonstration. La production `ghsv-prod` est néanmoins traitée comme une production (synchronisation manuelle, fenêtres, signatures, alertes).
- Budget du locataire : voir l'avertissement en tête de phase.
- Les checks lisent la **configuration** des clés (jamais les clés) avec l'identité AppRole `wb-checks` d'OpenBao (M25) : donne-lui `list` sur `transit/keys` et `read` sur `transit/keys/ghsv-*`, dans `plateforme/secrets`.

**Travail demandé**

Objectifs :
1. **Le type « client »** dans `plateforme/equipes` : ce qu'un fichier client déclare de plus qu'une équipe interne (au minimum : raison sociale, référence et dates du contrat, application hébergée et dépôt de déploiement, adresses publiées, fournisseur d'identité, clés dédiées, réversibilité, site de secours) et ce qu'il n'a **pas** (pas de libre-service, pas de groupe GitLab d'écriture pour le client). Règles de cohérence vérifiées par le générateur, tests.
2. **`equipes/ghsv.yaml`** : le GHSV décrit en un fichier, avec les personnes de MédiSphère qui répondent de ce client. Sa propagation crée le locataire Capsule `ghsv`, ses deux espaces et leurs quotas, l'AppProject `ghsv` (sources et destinations strictement limitées), les Applications de recette (automatique) et de production (manuelle, fenêtre de la maison), les accès d'OpenBao aux chemins du client et ses clés `transit/ghsv-*`.
3. **MédiAgenda pour le GHSV** : une instance dédiée par environnement (API, base CNPG propre, cache), publiée aux adresses de la phase, sans aucune mention de MédiSphère dans ce que reçoit un utilisateur du GHSV, avec les images signées et promues comme celles de MédiAgenda (même version, même chemin de promotion).
4. **Réversibilité** : un export complet du locataire en **format ouvert** (données et schéma, manifeste avec empreintes, notice de relecture), chiffré pour le seul GHSV, déposé dans un compartiment dédié ; un **essai de relecture** dans un environnement vierge qui prouve que l'export suffit ; la procédure **RB-371** « Réversibilité et fin de contrat d'un client » (export, remise, preuve de destruction, effacement cryptographique, délais du marché).
5. **Documentation** : `docs/capstone/locataire-ghsv.md` (ce que crée le fichier, ce qui reste hors du fichier, qui fait quoi à l'arrivée et au départ d'un client).

Contraintes :
- **Une** MR métier sur `equipes/ghsv.yaml` crée tout ce que le client reçoit ; rien n'est créé à la main dans le cluster ni dans OpenBao (sauf l'amorçage déjà prévu par le F2).
- Le fichier d'une équipe existante (`medivisio.yaml`, `data.yaml`, `ext-axiomdev.yaml`) rendu avant et après ton changement donne **exactement** les mêmes fichiers.
- Aucun espace du client n'est supprimable par la CI ; aucun Service `LoadBalancer` ni `NodePort` dans le locataire.
- Les clés `transit/ghsv-*` ne sont **ni exportables ni supprimables** par défaut ; ce qui peut chiffrer avec elles et ce qui peut déchiffrer est écrit et minimal.
- L'export de réversibilité ne contient **aucun** secret de la plateforme et ne quitte le cluster que chiffré.

**Critères de réussite**
- [ ] `equipes/ghsv.yaml` est sur `main` de `plateforme/equipes`, avec un type client ; le pipeline de `main` est vert (validation, tests, capacité, propagation).
- [ ] Le Tenant Capsule `ghsv` existe, protégé contre la suppression ; `ghsv-recette` et `ghsv-prod` en font partie, avec quota, LimitRange, PSA `restricted` et un `SecretStore` lié à OpenBao.
- [ ] L'AppProject `ghsv` n'autorise que les deux espaces du client et le seul dépôt de déploiement déclaré ; les Applications de recette et de production sont `Synced`/`Healthy`, la production en synchronisation manuelle.
- [ ] `https://ghsv.apps.par1.medisphere.internal/pret` et `https://ghsv-recette.apps.par1.medisphere.internal/pret` répondent 200 ; la description OpenAPI servie par l'instance du GHSV (`/openapi.json`) porte le nom du service du GHSV (ni « MédiAgenda », ni « MédiSphère » dans son titre).
- [ ] Les clés `transit/ghsv-*` existent, non exportables et non supprimables.
- [ ] Un export de réversibilité chiffré est présent dans le compartiment du client, et un compte rendu d'essai de relecture est publié ; `locataire-ghsv.md` et RB-371 sont sur `main`.

**Vérification** : `lab/bin/check F7 7`

<details><summary>Indice 1</summary>

Relis comment F2-S10 a ajouté les prestataires : une propriété permise à un seul type, une règle d'exclusion, un gabarit de plus, un chemin possédé de plus. Un client est le même genre d'ajout. La vraie question est ce que l'**AppProject** doit lire : le code de MédiAgenda n'appartient pas au GHSV, ses environnements, si.
</details>

<details><summary>Indice 2</summary>

« Format ouvert » se juge du côté de celui qui reçoit : peut-il relire l'export sans MédiAgenda, sans PostgreSQL de la même version, sans nous ? Un vidage binaire `pg_dump -Fc` ne passe pas ce test seul. Et « chiffré pour le seul GHSV » veut dire que la clé qui ouvre l'archive ne sert à rien d'autre.
</details>

<details><summary>Indice 3</summary>

Une clé `transit` qui n'est utilisée que pour **envelopper** les clés de chiffrement des sauvegardes et des exports du client permet, en fin de contrat, de rendre illisible tout ce qui reste (copies de PAR2, sauvegardes en rétention) en supprimant **une** clé. Écris qui a le droit de la supprimer, et après quelle preuve.
</details>

**Pour aller plus loin** (facultatif) : un modèle Backstage `nouveau-client` qui ouvre la MR ; un rapport de « showback » propre au client (F2-S08) qui alimente le chiffrage de la phase 2 avec des mesures réelles.

---

### F7-S08 — Fédérer l'identité du client  `LIBRE` `★★★★`

> **Ticket PLAT-3708** — *De : Sophie Laurent* — *Copie : Karim Benali, Claire Morel*
> Le cahier des charges est clair : les agents du GHSV se connectent avec **leur** compte, celui de l'annuaire du groupement, avec double authentification. Pas de compte chez nous, pas de mot de passe chez nous. On n'a pas encore leur IdP : simule-le dans un royaume à part, comme s'il était chez eux. Et je pose trois conditions : un agent du GHSV ne doit **jamais** pouvoir entrer dans un de nos outils internes, même par erreur ; le jour où un agent quitte le groupement, il perd l'accès sans que nous ayons à intervenir ; tout est en code, comme notre royaume.

**Objectifs pédagogiques**
- Mettre en place un courtier d'identité OIDC (*identity brokering*) dans Keycloak : fournisseur, mappeurs, premier passage, synchronisation.
- Traduire une appartenance de l'IdP d'un tiers en droits chez soi, sans lui faire confiance au-delà du nécessaire.
- Cloisonner des utilisateurs externes dans un royaume partagé avec les comptes internes.
- Protéger une application sans authentification par un mandataire (OAuth2 Proxy) et prouver que le cloisonnement tient.

**Prérequis** : M24 (Keycloak, `plateforme/identite`, fournisseur `keycloak/keycloak`, flux `navigateur-medisphere`, OAuth2 Proxy), F7-S07.
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Le royaume `medisphere` est décrit dans `plateforme/identite/tofu/` ; le client d'OpenTofu `svc-tofu-keycloak` n'administre **que** ce royaume (il ne peut pas créer de royaume). Le royaume `ghsv-idp` simule un système **qui n'est pas le nôtre** : son code et son état sont séparés de ceux de `medisphere`, et son identité d'administration aussi.
- `sso.par1.medisphere.internal` est publié par `lb01`/`lb02` ; seuls `/admin` et `/realms/master` y sont restreints. Le courtier (Keycloak sur `idp01`) appelle l'IdP du client **côté serveur** (jetons, clés) par son adresse publique, comme il le ferait pour un IdP sur Internet : vérifie que ce chemin réseau existe dans la matrice des flux.
- Keycloak n'a pas de condition « membre du groupe » dans ses flux (M24-E21) ; il a une condition sur un rôle.
- Les agents du GHSV ne figurent pas dans l'annuaire FreeIPA : ce sont des utilisateurs **fédérés par le courtier**, créés dans Keycloak à leur premier passage.
- MédiAgenda n'a aucune authentification : la route « agents » (lecture, déplacement et annulation de tous les rendez-vous du locataire) ne doit être joignable qu'à travers le mandataire ; la route publique est celle du DPI (son authentification arrive en S09) et ne doit rien laisser passer d'anonyme hormis la sonde de disponibilité et la description de l'API.
- Comptes de démonstration du GHSV (dans `ghsv-idp`) : au moins deux agents du secrétariat médical et une personne d'un autre service qui **ne doit pas** obtenir l'accès.
- Les checks lisent le fournisseur et ses mappeurs avec le client `wb-checks` du royaume `medisphere` : ajoute-lui le rôle `view-identity-providers` (client `realm-management`), en code.

**Travail demandé**

Objectifs :
1. **L'IdP du client, simulé** : royaume `ghsv-idp` en code (état séparé), double authentification **obligatoire** pour tous ses utilisateurs, un client pour notre courtier, la revendication d'appartenance aux groupes, les comptes de démonstration.
2. **Le courtier** dans `medisphere` : fournisseur d'identité OIDC `ghsv-idp` (signatures vérifiées, PKCE, aucun jeton du client conservé, caché sur la page de connexion), mappeurs (identifiant préfixé, appartenance au groupe `ghsv-agents` dérivée **seulement** du groupe du secrétariat, réévaluée à chaque connexion), premier passage sans liaison possible avec un compte existant.
3. **Le cloisonnement** : un utilisateur venu du GHSV est refusé par tous les clients internes du royaume (GitLab, Argo CD, Grafana, Kubernetes…) ; seuls les clients du GHSV l'acceptent. Démontre-le.
4. **L'accès des agents** : OAuth2 Proxy devant la route agents du locataire, qui envoie directement vers l'IdP du GHSV et n'accepte que `ghsv-agents` ; en recette et en production.
5. **Le cycle de vie** : ce qui se passe quand le GHSV retire un agent du secrétariat ou désactive son compte ; ce qui se passe quand le secret du client du courtier change ; supervision (connexions refusées, erreurs du courtier) ; procédure **RB-372** « Identité fédérée d'un client » et `docs/capstone/identite-federee.md` (schéma des échanges, ce que nous recevons du GHSV et ce que nous refusons d'en recevoir, ce qui est contractuel).

Contraintes :
- Tout en OpenTofu, revu par MR, appliqué par le pipeline ; aucun clic dans la console (sauf constat).
- Le royaume `ghsv-idp` et son code ne partagent ni état ni identité d'administration avec `medisphere`.
- Aucune donnée inutile importée du GHSV (minimisation) ; aucun droit dérivé d'un attribut que le GHSV pourrait modifier sans nous, en dehors du groupe convenu.
- Aucun agent du GHSV dans l'annuaire, dans un groupe de l'annuaire, ni dans le groupe `ghsv` du locataire.

**Critères de réussite**
- [ ] `https://sso.par1.medisphere.internal/realms/ghsv-idp/.well-known/openid-configuration` répond ; le royaume est décrit en code dans un état distinct de celui de `medisphere`.
- [ ] Dans `medisphere`, le fournisseur `ghsv-idp` est actif, caché sur la page de connexion, signatures vérifiées, sans conservation des jetons ; ses mappeurs placent dans `ghsv-agents`.
- [ ] Un agent du secrétariat (avec son second facteur) ouvre `https://ghsv-agents.apps.par1.medisphere.internal/api/v1/rendez-vous` ; la personne d'un autre service est refusée ; une requête sans session est redirigée vers l'authentification.
- [ ] Un agent connecté est refusé par GitLab, Argo CD et Grafana (constat écrit dans `identite-federee.md`).
- [ ] Sur la route publique `https://ghsv.apps.par1.medisphere.internal`, la liste des rendez-vous (`GET /api/v1/rendez-vous`) et l'annulation ne sont pas joignables **sans authentification** (réponse 401, 403 ou 404, jamais 200 ni 204).
- [ ] `identite-federee.md` et RB-372 sont sur `main`.

**Vérification** : `lab/bin/check F7 8`

<details><summary>Indice 1</summary>

Trois flux d'authentification entrent en jeu : celui du royaume du client (qui impose le second facteur), le flux « premier passage » du courtier (ce qui arrive la première fois qu'un agent se présente) et le flux du navigateur de `medisphere` (qui doit dire non à un agent qui arrive sur un client interne avec une session déjà ouverte). Une session SSO ouverte par un agent pour MédiAgenda est valable pour **tout** le royaume.
</details>

<details><summary>Indice 2</summary>

Un mappeur qui **ajoute** un groupe au premier passage ne le **retire** pas forcément ensuite : regarde le mode de synchronisation du fournisseur et des mappeurs. Pour que le départ d'un agent chez le GHSV ait un effet, il faut aussi que la session chez nous ne lui survive pas indéfiniment.
</details>

<details><summary>Indice 3</summary>

Pour que les agents n'aient jamais à choisir un fournisseur (ni à voir le formulaire de MédiSphère), un client peut avoir son propre flux de navigateur qui redirige d'office vers un fournisseur d'identité. Et pour refuser un agent partout ailleurs, il faut qu'il porte quelque chose que le flux du royaume sait tester.
</details>

**Pour aller plus loin** (facultatif) : vérifier, côté courtier, la preuve que l'IdP a bien demandé un second facteur (revendication `acr` et niveaux d'authentification de Keycloak) au lieu de s'en remettre au contrat ; fédération SAML 2.0 si le GHSV ne sait faire que SAML (M24-E32, question 3).

---

### F7-S09 — Contrats d'interface et tests de contrat  `LIBRE` `★★★`

> **Ticket DEV-3709** — *De : Julien Petit* — *Copie : Karim Benali, Élodie Marchand*
> Le DPI du GHSV appellera notre API de rendez-vous, et leur éditeur a déjà écrit son client à partir de **leur** contrat OpenAPI v1 (dans le cahier des charges). J'ai comparé vite fait avec notre `/docs` : ça ressemble, ce n'est pas pareil. Je veux trois choses. La liste exacte des écarts et ce qu'on change, chez nous, pour tenir le contrat sans casser nos propres cabinets. Une CI qui **refuse** toute MR de l'API qui casserait le contrat, avant la recette. Et une règle écrite de versionnage : le jour où on voudra une v2, le DPI du GHSV ne doit pas l'apprendre en production.

**Objectifs pédagogiques**
- Lire un contrat OpenAPI 3.1 et le comparer à une implémentation réelle (chemins, schémas, codes, formats, sécurité).
- Faire évoluer une API sans rupture pour ses consommateurs existants (ajout, adaptation, compatibilité).
- Mettre des tests de contrat dans la CI du producteur, et comprendre ce qu'ils attrapent et ce qu'ils laissent passer.
- Écrire une politique de versionnage et de dépréciation opposable à un client.

**Prérequis** : F7-S01 (contrat du GHSV, EF-05, EXP-05, EXP-06), F7-S07 (instance du GHSV), F7-S08 (clients du royaume `medisphere`), M19 (composants CI/CD), M27 (migrations *expand/contract*, rappel), M29 (stratégie de tests, question sur les tests de contrat de M29-E12).
**Durée indicative** : 5 à 6 h.

**Contexte technique**
- Contrat du client : [`ressources/S01/api-rendez-vous-v1.yaml`](../ressources/S01/api-rendez-vous-v1.yaml) (OpenAPI 3.1, fourni par le GHSV, **non négociable** pour la v1).
- Implémentation : `apps/mediagenda` (FastAPI) ; l'OpenAPI qu'elle génère est servie sur `/openapi.json` de chaque instance. La version que tu livres est celle de `mediagenda/api` (avec les correctifs des modules précédents), pas celle de `apps/` qui reste inchangée.
- Les cabinets de MédiSphère consomment l'API actuelle : aucun changement ne doit les casser (même règle que les migrations *expand/contract* du M27).
- Le DPI du GHSV s'authentifie comme une application (jeton OAuth 2.0 par identifiants de client) ; il n'a pas de session de navigateur.
- M29 avait laissé « à faire » les tests de contrat entre MédiAgenda (consommateur) et MédiDoc (producteur) : c'est le même mécanisme, dans l'autre sens.

**Travail demandé**

Objectifs :
1. **Les écarts** : `docs/capstone/api/ecarts-contrat-v1.md`, chaque écart entre le contrat du GHSV et l'API actuelle (chemin, paramètre, champ, type, format, code de réponse, erreur, pagination, sécurité), classé (bloquant pour le DPI, gênant, sans effet), avec la décision (adapter l'API, adapter la publication, demander une clarification au GHSV) et son effet sur les consommateurs existants.
2. **L'API adaptée** : les correctifs nécessaires dans `mediagenda/api` (code et migrations), sans rupture pour les cabinets existants, livrés jusqu'à la recette du GHSV par le chemin normal.
3. **Les tests de contrat côté producteur** : un job de la CI de `mediagenda/api` qui vérifie l'implémentation **contre le fichier du contrat du GHSV** (versionné, avec son origine et son empreinte), sur chaque MR ; une MR qui casse le contrat est refusée. Démontre-le avec une MR volontairement fautive.
4. **La publication du contrat** : l'API du GHSV n'expose que les opérations du contrat (route publique) ; le DPI s'authentifie par un client OAuth 2.0 dédié du royaume `medisphere`.
5. **Versionnage et dépréciation** : `docs/capstone/api/versionnage.md` (ce qu'est un changement compatible ou non, durée de coexistence de deux versions majeures, préavis, en-têtes de dépréciation, communication au client, tests du contrat de chaque version supportée) et la procédure **RB-373** « Faire évoluer le contrat d'API d'un client ».
6. **MédiDoc** : dans `ecarts-contrat-v1.md` ou `versionnage.md`, comment le même dispositif s'appliquerait à l'appel MédiAgenda → MédiDoc (qui écrit le contrat, qui le vérifie, où).

Contraintes :
- `apps/` reste inchangé : les correctifs sont dans `mediagenda/api`.
- Le contrat du GHSV n'est jamais modifié pour faire passer un test ; si un point du contrat est ambigu, la question part au GHSV et la décision provisoire est écrite.
- Aucun appel à un service réel dans les tests de contrat de la MR (ils tournent sans cluster).

**Critères de réussite**
- [ ] `ecarts-contrat-v1.md`, `versionnage.md` et RB-373 sont sur `main` de `plateforme/medisphere`.
- [ ] Le dépôt `mediagenda/api` contient le contrat du GHSV (même contenu que `ressources/S01/api-rendez-vous-v1.yaml`) et un job de test de contrat ; le dernier pipeline de `main` est vert.
- [ ] Une MR de démonstration qui casse le contrat a un pipeline en échec sur le job de contrat (MR fermée, non fusionnée).
- [ ] L'instance de recette du GHSV répond aux opérations du contrat (au moins la consultation des créneaux et la création d'un rendez-vous au format du contrat).

**Vérification** : `lab/bin/check F7 9`

<details><summary>Indice 1</summary>

Compare d'abord les deux documents OpenAPI, pas le code : celui du GHSV et `/openapi.json` de l'instance de recette. Des outils comparent deux OpenAPI et classent les différences en compatibles ou non ; un œil humain reste nécessaire pour ce qu'un schéma ne dit pas (fuseaux, sens d'un code 409, pagination).
</details>

<details><summary>Indice 2</summary>

Un test de contrat **côté producteur** sans courtier (pas de Pact Broker ici) peut être un test qui envoie à l'application, lancée sans base (doublures des tests existants), les requêtes décrites par le contrat et vérifie les réponses contre ses schémas. Les tests en mémoire du dépôt (`conftest.py`) sont déjà là pour ça.
</details>

<details><summary>Indice 3</summary>

Tenir deux contrats (les cabinets, le GHSV) sans dupliquer l'application : une couche d'adaptation (routes du contrat qui traduisent vers le domaine existant), plutôt que changer les routes actuelles. Le versionnage se lit alors dans le chemin, et chaque version garde ses tests.
</details>

**Pour aller plus loin** (facultatif) : tests dirigés par le consommateur (Pact) avec le DPI du GHSV ; tests de propriétés générés depuis le contrat (Schemathesis) en recette ; contrat MédiAgenda → MédiDoc réellement mis en place.

---

### F7-S10 — Des engagements de service mesurés  `LIBRE` `★★★`

> **Ticket PLAT-3710** — *De : Claire Morel* — *Copie : Nadia Roussel, Julien Petit, Élodie Marchand*
> On s'engage sur 99,9 % par mois pour la prise de rendez-vous, sur un rapport mensuel et sur une reprise en 4 h avec 15 min de perte au plus. Avant de signer, je veux voir ces trois chiffres **mesurés** sur le locataire du GHSV, pas recopiés d'une plaquette. Le rapport doit sortir tout seul le 1er du mois, et Élodie doit pouvoir le lire sans nous appeler. Et pour le PRA, Sophie veut la preuve que le GHSV est couvert par PAR2 comme MédiAgenda, avec une mesure.

**Objectifs pédagogiques**
- Traduire un engagement contractuel (fenêtre calendaire, maintenances annoncées, périmètre) en indicateurs et objectifs mesurables, et en voir les limites.
- Produire automatiquement un rapport mensuel factuel (disponibilité, incidents, capacité).
- Étendre un PRA existant à un nouveau locataire et mesurer sa couverture sans bascule réelle.

**Prérequis** : M21 (Pyrra, Thanos, sondes de `mon01`), F2-S08 (`ms-showback`), F4-S02 (sonde de continuité), F5 (PAR2 : réplication, `k8s-par2`, témoin de RPO, noms globaux), F7-S07.
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Engagements du cahier des charges : ENF-03 (99,9 % de disponibilité **mensuelle** de la prise de rendez-vous, web et API), ENF-04 (maintenances annoncées 5 jours ouvrés avant, entre 22 h et 6 h, 4 h par mois au plus), ENF-05 (95 % des requêtes de l'API en moins de 300 ms sur le mois, **aucune** au-delà d'une seconde, mesurés au point d'entrée ; le second seuil peut porter sur un centile, R-10), ENF-06 (RTO 4 h, RPO 15 min ; ENF-07 maintenue, R-11), EXP-03 (rapport mensuel avant le 10), EXP-07 (méthode de mesure décrite ; la mesure du titulaire fait foi si sa méthode est validée en comité, R-09).
- Pyrra calcule des objectifs sur des fenêtres **glissantes** ; la rétention locale de Prometheus est de 15 jours, Thanos garde les données brutes 30 jours (M21).
- Le PRA de MédiAgenda (F5) repose sur une réplique CNPG en topologie distribuée dans `k8s-par2`, alimentée depuis `s3-02`, des applications à 0 réplica en veille, un CronJob `temoin-rpo` et la sonde `ms-sonde-pra` de `adm02`. Le GHSV doit en bénéficier sans bascule de MédiAgenda ni du GHSV.
- Les checks lisent le cluster de secours avec un kubeconfig en lecture (variable `WB_F7_PAR2_KUBECONFIG` de `lab/lab.env`) ; sans lui, les contrôles de PAR2 sont ignorés.

**Travail demandé**

Objectifs :
1. **Les SLO du GHSV** dans `plateforme/observabilite` (Pyrra) : disponibilité de la prise de rendez-vous vue du serveur **et** vue de l'extérieur (sonde de `mon01`), latence au seuil du contrat ; alertes vers le support et vers l'équipe qui répond du client. Si un instrument ne sait pas mesurer exactement ce que dit le contrat, corrige l'instrument (ou écris pourquoi tu ne peux pas).
2. **`docs/capstone/engagements.md`** : chaque engagement du contrat, son indicateur exact (requête), sa source, ce qu'il ne voit pas, la différence entre l'objectif glissant de Pyrra et la mesure calendaire du contrat, le traitement des maintenances annoncées (où elles sont déclarées, comment elles sont retirées du calcul, qui les annonce).
3. **Le rapport mensuel** : un outil de `plateforme/outils` (conventions des `ms-*`) qui produit, pour un mois donné, la disponibilité calendaire hors maintenances annoncées, le budget consommé, les incidents (alertes critiques et fiches), la capacité (rendez-vous créés, pointe de requêtes par seconde, volume de la base, ressources consommées contre le quota) ; lancé par un pipeline planifié le 1er du mois, publié dans `docs/capstone/rapports/` ; procédure **RB-374** « Rapport mensuel d'un client ». Produis le rapport du mois en cours (partiel, signalé comme tel).
4. **La couverture PRA du GHSV** : la base du GHSV répliquée à PAR2 comme celle de MédiAgenda, son application déclarée (à 0) dans `k8s-par2`, un témoin de RPO propre au GHSV, le nom `ghsv.medisphere.internal` ; un **essai de reprise isolé** (sans toucher à PAR1 ni à la réplique continue) qui mesure RPO et temps de reprise ; résultats dans `docs/capstone/pra-ghsv.md`.

Contraintes :
- Aucun chiffre du rapport n'est saisi à la main ; tout chiffre a sa requête, reproductible.
- Aucune maintenance n'est retirée du calcul sans annonce horodatée **antérieure** de 5 jours ouvrés.
- L'essai de reprise ne promeut pas la réplique continue et n'interrompt ni la réplication ni le site de production.
- Rien d'ajouté à PAR2 qui dépasse sa mémoire (`hp01`, 16 Go) : chiffre ce que coûte le GHSV à PAR2 en veille et en PRA.

**Critères de réussite**
- [ ] Les `ServiceLevelObjective` du GHSV (au moins disponibilité serveur, disponibilité vue par la sonde, latence) existent et Pyrra en a tiré leurs règles ; la sonde de `mon01` voit `ghsv.apps.par1.medisphere.internal`.
- [ ] Un outil de rapport et son job planifié sont sur `main` de `plateforme/outils` ; un rapport `docs/capstone/rapports/ghsv-AAAA-MM.md` est publié avec disponibilité, incidents et capacité chiffrés.
- [ ] `engagements.md`, `pra-ghsv.md` et RB-374 sont sur `main`.
- [ ] `ghsv.medisphere.internal` résout ; à PAR2, la réplique de la base du GHSV est en topologie distribuée et suit le primaire (si `WB_F7_PAR2_KUBECONFIG` est défini).

**Vérification** : `lab/bin/check F7 10`

<details><summary>Indice 1</summary>

Un mois calendaire n'est pas « les 30 derniers jours ». Une requête instantanée évaluée au dernier instant du mois, sur une fenêtre égale à la durée du mois, donne la mesure calendaire — à condition que les données existent encore (rétentions). Les maintenances annoncées se retirent en ne comptant pas leurs échantillons (série « maintenance en cours » à 0/1), pas en retranchant des minutes au jugé.
</details>

<details><summary>Indice 2</summary>

Une disponibilité mesurée par l'application ne voit pas la panne qui l'empêche de recevoir des requêtes (Gateway, DNS, réseau) : son compteur ne bouge pas, son taux d'erreurs reste à zéro. C'est la sonde externe qui la voit. Le contrat parle de ce que vit le DPI et le patient.
</details>

<details><summary>Indice 3</summary>

Pour un essai de reprise sans bascule : une **nouvelle** grappe CNPG restaurée à PAR2 depuis le stockage objet de PAR2 (pas la réplique continue), une instance de l'API à 1 réplica qui la lit, une requête par le Gateway de PAR2. Le RPO se lit avec le témoin : dernier témoin écrit à PAR1, dernier témoin retrouvé dans la restauration.
</details>

**Pour aller plus loin** (facultatif) : un tableau Grafana « GHSV » partagé avec le client en lecture (organisation dédiée, anonymisation des données) ; des pénalités contractuelles simulées sur douze mois à partir des mesures.

---

### F7-S11 — Panne : la démonstration sous incidents  `BF` `★★★★`

> **Ticket PLAT-3711** — *De : Karim Benali* — *Copie : Claire Morel, Nadia Roussel*
> Répétition générale de la démonstration au GHSV. Élodie a prévenu : elle viendra avec son RSSI, et ils aiment « voir comment vous réagissez quand ça casse ». On fait donc une journée de jeu : tu lances la démonstration, avec sa charge, et moi j'injecte des incidents sur le locataire du GHSV, l'un après l'autre. Règle du jeu : **la démonstration continue**. Tu diagnostiques, tu répares proprement, tu annonces, et à la fin tu me dis combien de minutes d'indisponibilité le GHSV aurait comptées dans son rapport.

**Objectifs pédagogiques**
- Diagnostiquer et réparer sous charge et sous le regard du client, plusieurs incidents successifs sur un locataire, sans toucher aux autres.
- Distinguer ce que voient le patient, l'agent et le DPI, et les instruments qui le montrent (sondes, SLO, journaux, événements Keycloak).
- Chiffrer l'impact d'une journée de jeu avec les mêmes instruments que le rapport mensuel.

**Prérequis** : F7-S07 à F7-S10 terminés et verts ; M29 (journées de jeu, k6-operator) ; F4-S02 (sonde de continuité).
**Durée indicative** : 2 à 3 h, dont 90 min de démonstration sous incidents, puis le compte rendu.

**Contexte technique**
- Avant l'injection, le lab doit être sain : instance de production du GHSV prête (au moins deux pods de l'API), Application `Synced`/`Healthy`, fournisseur `ghsv-idp` actif, et la **charge de démonstration** en cours : un `TestRun` k6 dans l'espace `k6` dont l'étiquette `testid` commence par `demo-ghsv` (parcours du DPI du contrat : jeton, créneaux, création, rapprochement, déplacement, annulation ; lecture par un agent si tu sais l'outiller), sur `ghsv-prod`, données fictives, au débit que tu as choisi (ni plus de 20 requêtes par seconde, ni moins de 2). Le script refuse d'injecter sinon.
- Les incidents arrivent **les uns après les autres** (deux ou trois) : le suivant n'est injecté qu'après la réparation du précédent et un délai de quelques minutes. Ils ne touchent que les espaces `ghsv-*` et les objets du client (dont le fournisseur `ghsv-idp` du royaume `medisphere`). Les messages des utilisateurs arrivent dans Mailpit (`support@medisphere.internal`), comme pendant une vraie démonstration ; tes alertes, elles, arrivent où tu les as routées.
- Injection : `lab/bin/break F7 11` (depuis `adm01`). Abandon ou fin de la journée : `lab/bin/break F7 11 --annuler` (arrête aussi les injections à venir).
- Compte rendu : `docs/qualite/journees-de-jeu/<AAAA-MM-JJ>-demonstration-ghsv.md` (convention du M29).

**Travail demandé**
1. Lance la charge de démonstration, vérifie qu'elle tourne, ouvre tes tableaux (SLO du GHSV, sonde, changement en cours du F4).
2. Lance `lab/bin/break F7 11` et lis le premier symptôme.
3. Pour chaque incident : diagnostic, réparation par le chemin normal (Git et Argo CD, OpenTofu) dès que c'est possible, annonce écrite (ce que tu dirais au GHSV), heure de début et de fin.
4. Quand plus rien n'arrive et que tout est vert, rédige le compte rendu : chronologie, ce qu'a vu chaque type d'utilisateur, ce qu'ont détecté (ou pas) tes instruments et en combien de temps, secondes d'indisponibilité mesurées (requête), effet sur le budget d'erreur et sur le rapport du mois, actions.

**Critères de réussite**
- [ ] L'instance de production du GHSV est saine : API prête et publiée, base et cache disponibles, Application `Synced`, accès des agents par le courtier fonctionnel.
- [ ] Aucune injection n'est encore active ni à venir (`lab/bin/break F7 11 --annuler` sans effet, ou injections toutes réparées).
- [ ] La charge de démonstration a bien tourné pendant la journée de jeu (séries `k6` avec `testid=demo-ghsv…` dans Prometheus).
- [ ] Le compte rendu est publié et chiffre l'indisponibilité mesurée.

**Vérification** : `lab/bin/check F7 11`
**Temps cible** : 20 min par incident.

<details><summary>Indice 1</summary>

Avant de toucher à quoi que ce soit, situe le symptôme : qui le voit (patient, agent, DPI), depuis quand (la sonde et la charge le disent à 15 s près), et à quelle couche (publication, mandataire, application, base, cache, identité). Une réponse 503 rapide, une réponse lente qui finit en 504 et une boucle de connexion ne viennent pas du même endroit.
</details>

<details><summary>Indice 2</summary>

En production, Argo CD ne resynchronise pas tout seul : un objet modifié en direct reste modifié, et le diff de l'Application le montre. Un objet ajouté en direct, lui, n'apparaît pas dans le diff. Et un objet géré ailleurs que dans le cluster (Keycloak) a son propre « diff » : le plan OpenTofu.
</details>

<details><summary>Indice 3</summary>

Pour les incidents d'identité, les événements de connexion de Keycloak (royaume `medisphere`, événements d'utilisateur, ou les journaux d'`idp01` dans Loki) disent ce que le courtier a reçu et ce qu'il en a fait. Compare avec ce que décrit ton code.
</details>

**Pour aller plus loin** (facultatif) : rejoue la journée de jeu avec un observateur (Nadia) qui ne regarde que ce que voit le client et chronomètre tes annonces ; ajoute à ta supervision ce qui n'a rien vu.

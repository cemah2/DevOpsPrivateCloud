# Revue de la MR !41 — royaume `medisphere-recette`

**Conclusion : non fusionnable en l'état.** L'intention est bonne (isoler les essais de la production), mais la MR crée un royaume où n'importe qui peut s'inscrire, se donner les droits d'administration et écrire dans l'annuaire de production, avec des secrets de production en clair dans Git. Trois défauts critiques, sept majeurs, trois mineurs ; corrections précises ci-dessous. Le fond (un royaume de recette) mérite une seconde MR, mais **pas fédéré au même annuaire** (dernière section).

Avant toute chose : le mot de passe de `svc-keycloak` est maintenant dans l'historique de la branche `lucas/royaume-recette` (et dans les journaux du runner si un pipeline a tourné). Il est **compromis** : rotation immédiate (RB-244), même si la MR est fermée.

## Critiques

**1. `royaume-recette.tf:13` + `:78-80` — inscription libre, et tout nouveau compte entre dans `plateforme-admins`.** `registration_allowed = true` permet à quiconque joint `sso` de créer un compte ; `keycloak_default_groups` met **chaque** nouveau compte dans `plateforme-admins`. La revendication `groups` portera `plateforme-admins` : tout service qui fait confiance à ce royaume (MédiAgenda lit `groups` pour les droits d'administration) donne les pleins pouvoirs à un inconnu. Correction : `registration_allowed = false` ; supprimer `keycloak_default_groups` (un groupe par défaut, s'il en faut un, est un groupe **sans droit**).

**2. `clients-recette.tf:52-60` + `:103-112` — chacun écrit ses propres groupes.** Le mappeur met dans `groups` l'attribut `equipe`, que le profil utilisateur rend **modifiable par l'utilisateur** (`edit = ["admin", "user"]`) depuis la console de compte. Essai sur un Keycloak jetable : un compte d'essai se met `equipe = plateforme-admins` et reçoit `"groups": ["plateforme-admins"]` dans son jeton suivant. C'est une élévation de privilèges en libre-service. Correction : supprimer ce mappeur et l'attribut ; reprendre la portée `groupes` du royaume `medisphere` (mappeur *Group Membership*, `full_path = false`), dont la source est l'annuaire, non modifiable par la personne.

**3. `royaume-recette.tf:38` et `clients-recette.tf:10`, `:28` — secrets en clair dans le code.** Mot de passe du compte de **production** `svc-keycloak` (le même compte que le royaume `medisphere`), secrets des clients. Correction : variable éphémère et `bind_credential_wo` (comme `federation-ldap.tf`, E08), secrets des clients générés par Keycloak et rangés par `ranger-secret-client.sh`. Rotation de `svc-keycloak` (voir plus haut).

## Majeurs

**4. `royaume-recette.tf:48-49` — fédération `WRITABLE` avec `sync_registrations = true`.** Les comptes créés par inscription (défaut 1) sont **écrits dans l'annuaire de production**, et une personne qui modifie son profil dans la recette le modifie dans FreeIPA (adresse de courriel comprise, qui sert ailleurs à rapprocher des comptes). Keycloak ne doit jamais écrire dans l'annuaire (E06). Essai : sans annuaire joignable, la simple création d'un utilisateur échoue en 400, preuve que Keycloak tente d'écrire. Correction : `edit_mode = "READ_ONLY"`, `sync_registrations = false`. (Le compte `svc-keycloak` n'a de toute façon que la lecture : avec les bons droits côté annuaire, ce défaut aurait été bloquant en silence.)

**5. `royaume-recette.tf:21-23` — jeton d'accès de 24 h, session de 30 jours.** Un jeton porteur volé vaut 24 heures, sans révocation possible côté services qui vérifient la signature hors ligne ; une session oubliée vit un mois. Correction : durées du royaume `medisphere` (jeton 5 min, session inactive 30 min, maximale 10 h) ; les tests longs utilisent le jeton de rafraîchissement, c'est son rôle.

**6. `clients-recette.tf:17-18` — `valid_redirect_uris = ["*"]`, `web_origins = ["*"]`.** N'importe quelle URL reçoit le code (ou, avec le défaut 7, les jetons) : un lien piégé `…/auth?client_id=mediagenda-web&redirect_uri=https://attaquant/…` exfiltre la connexion d'une personne déjà authentifiée (SSO : aucun formulaire). `web_origins = ["*"]` ouvre CORS à tous les sites. Correction : URI exactes ; pour les applications de revue (une URL par branche), un client par environnement ou un motif strict limité au domaine **et** au chemin, jamais `*`.

**7. `clients-recette.tf:13` — flux implicite.** Les jetons voyagent dans le fragment de l'URL (historique, extensions, `Referer`), sans liaison au client. Abandonné par la RFC 9700. Correction : `implicit_flow_enabled = false`, flux standard avec PKCE (bibliothèque JS à jour).

**8. `clients-recette.tf:8-10`, sans `pkce_code_challenge_method` — client public avec un secret, sans PKCE.** Un secret dans du JavaScript est public ; Keycloak l'ignore d'ailleurs pour un client `PUBLIC` : c'est la mise à jour qui revient à **chaque** `tofu plan` (« petit bogue du fournisseur » de la description : non, Keycloak jette la valeur, le plan ne sera jamais vide). La seule protection d'un client public est PKCE, absent. Correction : supprimer `client_secret`, ajouter `pkce_code_challenge_method = "S256"`.

**9. `clients-recette.tf:32` — *Direct Access Grants* pour MédiStat.** Le mot de passe de Julien dans un script de test ; ce flux contourne le formulaire, donc le second facteur et toute protection du flux de navigateur. Essai : un jeton s'obtient par `grant_type=password` sans passer par aucun formulaire. Correction : `false` ; un test d'intégration utilise un **compte de service** (`client_credentials`) avec des droits de test, ou le flux standard automatisé contre un compte de test sans droit.

**10. `royaume-recette.tf:18` — `ssl_required = "none"`.** Keycloak accepte HTTP pour tout client, toute adresse : mots de passe et jetons en clair sur le réseau du lab. « Pas exposé sur Internet » ne protège pas du réseau interne. Correction : `external` au minimum (valeur du royaume `medisphere`), `all` pour un royaume neuf.

## Mineurs

**11. `clients-recette.tf:118`, `:124` — portées par défaut des clients incomplètes.** La liste remplace celle du royaume pour ces clients : `basic` manque, donc **`sub` disparaît des jetons** (essai : `"sub": null`), et `acr` aussi. Beaucoup de bibliothèques refusent un ID token sans `sub`. Correction : ne pas déclarer ces ressources (les portées par défaut du royaume suffisent), ou recopier la liste complète.

**12. `clients-recette.tf:40` — `full_scope_allowed = true`.** Tous les rôles du royaume (et des clients) dans les jetons de MédiStat : jetons plus gros, et fuite d'information sur l'organisation des droits. Correction : `false`, et les seuls rôles utiles par la portée du client.

**13. `clients-recette.tf:70-101` — courriel et identifiant modifiables par l'utilisateur, avec inscription libre et sans vérification du courriel.** Un compte d'essai peut prendre l'adresse d'une vraie personne ; tout service qui rapproche les comptes par courriel (GitLab avec `omniauth_auto_link_user`, Grafana par adresse) lui ouvrirait le compte de cette personne s'il faisait confiance à ce royaume. Correction : identifiant non modifiable, courriel vérifié, et de toute façon pas d'inscription (défaut 1).

## Ce qui manque

- Protection contre la force brute (`security_defenses`), politique de mot de passe pour d'éventuels comptes locaux, événements de connexion et d'administration enregistrés (E26, E27).
- Flux `navigateur-medisphere` (OTP des administrateurs, E21) : dans ce royaume, `plateforme-admins` se connecte sans second facteur.
- Filtre des personnes (`custom_user_search_filter = "(!(uid=admin))"`) et filtre des groupes de l'annuaire (`groups_ldap_filter`) : ici, le compte `admin` de FreeIPA et ses groupes internes (`admins`…) seraient importés.
- Documentation : aucune entrée dans le modèle d'autorisation (E10), aucun responsable désigné pour ce royaume, aucune date de fin.

## Sans danger, mais inutile

- `reset_password_allowed = true` : sans effet utile en `READ_ONLY` (le mot de passe est dans l'annuaire) ; trompeur pour les utilisateurs.
- `login_with_email_allowed = true` : acceptable, à aligner sur le royaume `medisphere`.

## Question de conception : un royaume de recette sur l'annuaire de production ?

Non. Un royaume de recette existe pour **casser des choses** (essais de flux, de mappeurs, de durées) ; le brancher sur l'annuaire de production, avec le compte de service de production, met les vraies identités (et leurs vrais mots de passe, saisis dans un royaume moins protégé) à portée de ces essais. Le moindre défaut de configuration (ici : 1, 2, 4) touche des personnes réelles.

Alternative : un royaume `medisphere-recette` **sans fédération**, avec des comptes d'essai locaux sans valeur (`essai.dev1`…), créés par OpenTofu, mots de passe générés et rangés dans un coffre de recette, groupes de recette qui reproduisent les **noms** de groupes de production (`plateforme-admins`…) pour que les applications se testent à l'identique. Conséquences : les développeurs utilisent des comptes d'essai (pas leurs identifiants) ; aucune donnée personnelle ; le royaume peut être détruit et recréé ; les tests de l'OTP utilisent un secret TOTP connu. Option plus lourde : un second Keycloak de recette, qui teste aussi les montées de version (E33).

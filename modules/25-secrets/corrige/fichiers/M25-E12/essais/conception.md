# M25-E12 — Conception (modèle de réponse)

## Jeton d'appel de TokenReview

Choix : **le jeton du client** (`token_reviewer_jwt` vide, `disable_local_ca_jwt = true`). OpenBao reçoit le jeton projeté d'un compte de service, et l'envoie tel quel à `POST /apis/authentication.k8s.io/v1/tokenreviews` **en s'authentifiant avec lui**. Il faut donc que chaque compte client ait le droit de créer des TokenReview : ClusterRole `system:auth-delegator` (création de `tokenreviews` et `subjectaccessreviews`, rien d'autre), liée par `rbac/openbao-auth-delegator.yaml` (et par `systemAuthDelegator: true` du chart pour `external-secrets/external-secrets`).

Écarté : un compte `openbao-tokenreview` avec un jeton de longue durée (Secret `kubernetes.io/service-account-token`) recopié dans la configuration de la méthode. Un seul droit RBAC, mais un jeton **sans expiration** à garder et à faire tourner, qui ouvre TokenReview à quiconque le lit dans une sauvegarde.

## Ce que vérifie OpenBao, ce que dit l'API

- OpenBao : la forme du JWT, l'**audience** (`aud` contient `openbao.medisphere.internal`), puis, d'après la réponse de l'API, que le compte et l'espace sont dans les listes du rôle (`bound_service_account_names`, `…_namespaces`).
- L'API (TokenReview) : la **signature** (clé de signature des comptes de service du cluster), l'expiration, et que le jeton est encore lié à un objet existant (compte de service, pod) : un compte supprimé ou un pod disparu rend le jeton invalide **immédiatement**, avant son expiration.

## Refus observés (étape 2)

| Essai | Message |
|---|---|
| jeton du compte `default` de `wb-essais` | `service account name not authorized` |
| jeton du compte `eso` **sans** `--audience` | `invalid audience (aud) claim: audience claim does not match any expected audience` |
| jeton d'un compte `eso` créé dans un autre espace | `namespace not authorized` |

(Libellés du code de la méthode dans OpenBao 2.6.4 ; l'enveloppe du message varie selon la CLI ou l'API.)

# <AAAA-MM-JJ> — M24-E37 — Une arrivée invisible pour Keycloak (INC-5137)

| | |
|---|---|
| Signalé par | Nadia Roussel, <HH:MM> |
| Diagnostic | <MOI>, de <HH:MM> à <HH:MM> |
| Variante rencontrée | <mot de passe de svc-keycloak / filtre des personnes / filtre des groupes> |
| Changement fautif | <HH:MM>, <qui : client svc-tofu-keycloak depuis adm01 / root sur ipa01 par LDAPI>, <quoi> |
| Correctif | <MR ou pipeline plateforme/identite !N, apply à HH:MM / mot de passe remis depuis le Vault, RB-244 §4> |

## Chronologie

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| <HH:MM> | L'annuaire a-t-il la personne ? | `ipa user-show emma.durand --all` | créée à <HH:MM>, groupe `medidoc`, active | l'annuaire a raison |
| <HH:MM> | Keycloak la voit-il ? | *Users* → `emma` | <absente / présente sans groupe> | panne côté fédération |
| <HH:MM> | Qui d'autre est touché ? | connexion de `lucas.martin` au compte ; *Evaluate* pour un membre de `medidoc` | <…> | étendue : <toutes les nouvelles connexions / les arrivées après <date> / tout le groupe medidoc> |
| <HH:MM> | Liaison, recherche ou mappeur ? | *Test authentication* ; filtre ; mappeur `groupes-ipa` | <…> | maillon : <…> |
| <HH:MM> | Preuve côté annuaire | `grep … access` sur `ipa01` (`BIND`/`RESULT err=`, ou `SRCH … filter=`) ; `ldapsearch -Y GSSAPI` avec le filtre exact | <…> | <…> |
| <HH:MM> | Qui a changé quoi ? | *Admin events* ; `MOD` dans le journal d'accès | <…> | <…> |
| <HH:MM> | Correctif | <…> | <…> | |
| <HH:MM> | Preuve | *Sync changed users* ; *Evaluate* pour Emma : `"groups": ["medidoc"]` ; `lab/bin/check 24 37` | OK | |

## Ce qui aurait dû prévenir

- `FederationLdapEnEchec` : <a sonné à HH:MM vers … / muette, parce que rien n'échoue quand une recherche renvoie moins>.
- Contrôle de dérive nocturne (M24-E35) : <l'aurait vu le lendemain à 05:43>.
- RB-241 : étape « vérifier dans Keycloak, avec ses groupes » ajoutée (MR !<N>).

## Questions pour le post-mortem

- Pourquoi un changement du royaume a-t-il été fait avec le secret d'OpenTofu, hors pipeline ? Qui possède ce fichier ?
- Pourquoi le mot de passe d'un compte système a-t-il été changé sans le Vault ni l'étape Keycloak (RB-244 §4) ?

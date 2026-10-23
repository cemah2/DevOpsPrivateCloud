# Départ d'AxiomDev — preuve

*Ticket : SEC-3212. Fin du contrat : <DATE-FIN-CONTRAT> (départ effectif : <DATE-DÉPART>, <HEURE>). Exécuté par : <MOI>. Contrôlé par : Karim Benali (une heure après, RB-242 « Contrôle final »). Validé par : Sophie Laurent, Julien Petit. Procédures : RB-329 § C, RB-242 § B.*

## Périmètre

| Élément | Avant | Après |
|---|---|---|
| Personnes | `marc.vidal`, `yanis.perrin` (groupe `ext-axiomdev`, principal daté au <DATE-FIN-CONTRAT>) | désactivées (`nsAccountLock: TRUE`), aucun groupe ; identifiants réservés, jamais réutilisés |
| Groupe de l'annuaire | `ext-axiomdev` (2 membres, rôle Keycloak `second-facteur-obligatoire`) | vide, conservé (historique des droits) |
| GitLab | 2 utilisateurs externes, Developer de `mediagenda/api` jusqu'au <DATE-FIN-CONTRAT> | comptes **bloqués**, retirés du projet, 0 jeton actif, 0 clé SSH ; leurs MR et commits restent attribués |
| Kubernetes | espace `mediagenda-axiomdev`, `Role` `axiomdev-developpeur`, liaison `oidc:ext-axiomdev` | espace **retiré** par la MR (Namespace absent), aucune liaison restante |
| OpenBao | aucun chemin | inchangé (rien à retirer) ; aucune entité active |
| Réseau | 2 pairs WireGuard (VPN d'administration) | pairs retirés de la matrice et des passerelles |
| SSH | aucune règle HBAC (refus partout) ; certificats SSH de 16 h émis par step-ca après SSO | aucun certificat valide après <HEURE-DERNIER-CERTIFICAT + 16 h> ; inutilisables dès la désactivation |

## Chronologie (heures réelles)

| Heure | Étape | Preuve |
|---|---|---|
| <HH:MM> | MR « départ d'AxiomDev » fusionnée sur `plateforme/equipes` (`etat: retiree` dans `equipes/ext-axiomdev.yaml`) et sur `plateforme/identite` (`modele.yml` : périmètre retiré) ; propagation vers les dépôts cibles | liens des MR, pipelines verts |
| <HH:MM> | application de l'annuaire (job `annuaire:appliquer`), second passage sans changement | journal du job |
| <HH:MM> | `outils/depart-externe.sh --projet mediagenda/api marc.vidal yanis.perrin` : sessions Keycloak fermées, jetons et clés GitLab révoqués, comptes bloqués | sortie de l'outil ci-dessous |
| <HH:MM> | Argo CD (Application `equipes-k8s`, élagage) : `mediagenda-axiomdev` supprimé avec tout son contenu (espace de prestataire non protégé, RB-329) | `kubectl get ns mediagenda-axiomdev` → `NotFound` |
| <HH:MM> | pairs WireGuard retirés (rôle `wireguard`, `gw01`/`gw02`) | `wg show wg1 peers` sans les deux clés |
| <HH:MM> | contrôle final par Karim | tableau ci-dessous |

Sortie de l'outil (sans secret) :

```
<COLLER ICI LES LIGNES « date | personne | service | action » DE depart-externe.sh>
```

## Contrôle final

| Contrôle | Commande | Résultat |
|---|---|---|
| Annuaire | `ipa user-show marc.vidal yanis.perrin --all \| grep -E 'disabled\|Member of'` | `Account disabled: True`, aucun groupe |
| Kerberos | `kinit yanis.perrin` depuis `adm01` | refus |
| Keycloak | *Users* → sessions ; connexion en fenêtre privée | 0 session ; refus |
| GitLab | `GET /users?username=…` (`state`), `GET /personal_access_tokens?user_id=…&state=active`, `GET /users/:id/keys`, `GET /users/:id/memberships` | `blocked`, `[]`, `[]`, `[]` |
| Kubernetes | `kubectl get clusterrolebindings,rolebindings -A -o json \| jq '[.items[] \| select(any(.subjects[]?; .name \| test("ext-axiomdev\|marc.vidal\|yanis.perrin")))] \| length'` | `0` |
| SSH | `ssh -o BatchMode=yes yanis.perrin@mon01.par1.medisphere.internal true` | refus |
| Journaux | Loki, locataire `audit` : connexions réussies de ces identités après <HEURE> | aucune |
| Revue d'accès | `REVUE_ESSAI=1` sur `plateforme/identite` | aucune ligne `ext-axiomdev` |
| Vérification du workbook | `lab/bin/check F2 12` | vert |

## Ce qui reste, et pourquoi

- Les **comptes** (annuaire, GitLab) restent, désactivés et bloqués : identifiants réservés, historique lisible.
- Les **images** construites par la CI de leurs branches dans Harbor (`medisphere/mediagenda`, étiquettes de branche) : expirent par la politique de rétention du projet ; aucune n'a été promue.
- Le **code** livré (MR fusionnées dans `mediagenda/api`) appartient à MédiSphère (contrat) et reste.
- Les **certificats SSH** déjà émis ne sont pas révocables (pas de KRL déployée) : 16 h au plus, inutilisables sans compte actif ni règle HBAC.

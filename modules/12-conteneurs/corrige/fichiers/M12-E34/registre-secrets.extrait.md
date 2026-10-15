<!-- Extrait de docs/socle/registre-secrets.md (plateforme/medisphere) — M12-E34, exigence 5. -->
| Secret | Usage | Emplacement | Rotation | Ticket |
|---|---|---|---|---|
| Jeton d'administration de MédiAnnuaire (recette) | `POST /admin/recharger` | `ctr01:/home/admin/src/annuaire/secrets/jeton_admin` (dossier 700, hors Git) ; copie : Vault `lab`, `vault_mediannuaire_jeton_recette` | à chaque départ d'un membre de l'équipe, et annuelle | CHG-1360 |

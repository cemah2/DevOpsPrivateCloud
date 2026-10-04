// commitlint.config.mjs — configuration de référence des projets de la plateforme MédiSphère.
// M01-E14. Réutilisée telle quelle par tous les projets plateforme/* (M02 et suivants).
//
// Règles : celles de Conventional Commits 1.0.0, via @commitlint/config-conventional 21.x :
//   - types autorisés : build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test ;
//   - en-tête de 100 caractères au plus, sujet sans point final, sujet qui ne commence
//     pas par une majuscule (« docs: sauvegarde de GitLab », pas « docs: Sauvegarde… ») ;
//   - lignes du corps et du pied de 100 caractères au plus ;
//   - « ! » après le type ou un pied « BREAKING CHANGE: » signalent une rupture.
// Les messages « Merge branch … » de GitLab, « Revert … », « fixup! » et « squash! » sont ignorés
// par défaut (defaultIgnores) : c'est la CI qui refuse les fixup! restés dans une MR (M01-E24).
//
// Résolution de « extends » : commitlint cherche @commitlint/config-conventional depuis le dossier
// courant (le dépôt), puis dans le dossier des paquets npm « globaux » (préfixe npm). Le dépôt
// n'a pas de node_modules : le paquet doit donc être installé en global (sur adm01 : préfixe npm
// ~/.local, M01-E14), ou dans l'environnement isolé du hook pre-commit (M01-E15).
export default {
  extends: ['@commitlint/config-conventional'],
  helpUrl:
    'https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/CONTRIBUTING.md#3-messages-de-commit',
};

// plateforme/renovate — config.js : configuration GLOBALE (auto-hébergée) de Renovate (M13-E11).
// Lu par Renovate dans le dossier du job. Les règles de mise à jour, elles, sont dans le préréglage
// partagé plateforme/renovate-config (default.json), que chaque projet étend.
// Secrets : uniquement par l'environnement (variables de CI protégées et masquées du projet).
module.exports = {
  platform: 'gitlab',
  endpoint: process.env.CI_API_V4_URL, // https://git01.par1.medisphere.internal/api/v4
  gitAuthor: 'Renovate Bot <renovate-bot@medisphere.internal>',
  // Découverte des projets auxquels renovate-bot a accès, LIMITÉE à cette liste.
  autodiscover: true,
  autodiscoverFilter: [
    'mediagenda/api',
    'medidoc/medidoc',
    'medinotif/worker',
    'legacy/legacy-rdv',
    'plateforme/ci-templates',
  ],
  // Un projet sans renovate.json n'est pas traité (pas de MR d'accueil surprise).
  onboarding: false,
  requireConfig: 'required',
  // Les MR de Renovate déclenchent la chaîne de livraison (M13-E09) en mode MR : rien n'est publié.
  hostRules: [
    {
      // Harbor : lecture des images de bibliotheque/ et plateforme/ (robot$renovate, tirage seul).
      matchHost: 'registry.par1.medisphere.internal',
      hostType: 'docker',
      username: process.env.HARBOR_RENOVATE_USER,
      password: process.env.HARBOR_RENOVATE_TOKEN,
    },
  ],
  // Les avis de version (changelogs) viennent de github.com ; sans jeton, Renovate s'en passe
  // (limite de débit anonyme). RENOVATE_GITHUB_COM_TOKEN facultatif, jeton GitHub en lecture seule.
};

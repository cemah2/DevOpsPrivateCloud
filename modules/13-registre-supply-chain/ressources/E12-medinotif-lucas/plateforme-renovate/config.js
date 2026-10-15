// Config Renovate proposée par Lucas pour plateforme/renovate
module.exports = {
  platform: 'gitlab',
  endpoint: 'https://git01.par1.medisphere.internal/api/v4',
  token: 'glpat-EXEMPLE-WORKBOOK',
  autodiscover: true,
  onboarding: true,
  hostRules: [
    {
      matchHost: 'registry.par1.medisphere.internal',
      username: 'admin',
      password: 'Hb-Adm1n-2026!',
    },
  ],
};

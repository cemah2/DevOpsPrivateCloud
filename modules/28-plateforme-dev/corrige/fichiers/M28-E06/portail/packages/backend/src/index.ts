/*
 * plateforme/portail — packages/backend/src/index.ts (M28-E06, PLAT-2906 ; modules E07, E08, E10).
 * Backend de Backstage 1.56 (nouveau système de backend : createBackend + backend.add).
 * Par rapport au gabarit de @backstage/create-app 0.9.3 :
 *   - retirés : fournisseur d'identité invité (aucun accès anonyme en production) et module GitHub
 *     du scaffolder (MédiSphère n'a pas de GitHub) ;
 *   - ajoutés : authentification OIDC par Keycloak avec résolution par preferred_username (module
 *     local, E06), découverte GitLab et organisation LDAP (E07), actions GitLab du scaffolder (E08).
 * Paquets ajoutés (yarn --cwd packages/backend add …) : @backstage/backend-plugin-api,
 * @backstage/plugin-auth-backend-module-oidc-provider, @backstage/plugin-catalog-backend-module-gitlab,
 * @backstage/plugin-catalog-backend-module-ldap, @backstage/plugin-scaffolder-backend-module-gitlab
 * (versions de la 1.56 choisies par yarn d'après backstage.json).
 */
import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-proxy-backend'));

// scaffolder (modèles « nouveau service », E08)
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'));
backend.add(
  import('@backstage/plugin-scaffolder-backend-module-notifications'),
);

// techdocs (constructeur externe, publication S3 : E10)
backend.add(import('@backstage/plugin-techdocs-backend'));

// authentification : OIDC Keycloak seulement, résolveur MédiSphère (preferred_username).
// Le module générique « @backstage/plugin-auth-backend-module-oidc-provider » n'est PAS ajouté :
// il enregistrerait lui aussi le fournisseur « oidc ». Le module local le remplace.
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('./modules/authOidcMedisphere'));

// catalogue
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);
backend.add(import('@backstage/plugin-catalog-backend-module-logs'));
backend.add(import('@backstage/plugin-catalog-backend-module-gitlab')); // E07
backend.add(import('@backstage/plugin-catalog-backend-module-ldap')); // E07

// permissions : politique « tout permis » du gabarit, à remplacer au palier 3 (M28-E16).
backend.add(import('@backstage/plugin-permission-backend'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

// recherche (PostgreSQL)
backend.add(import('@backstage/plugin-search-backend'));
backend.add(import('@backstage/plugin-search-backend-module-pg'));
backend.add(import('@backstage/plugin-search-backend-module-catalog'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs'));

// kubernetes (lecture, E10)
backend.add(import('@backstage/plugin-kubernetes-backend'));

backend.add(import('@backstage/plugin-user-settings-backend'));
backend.add(import('@backstage/plugin-notifications-backend'));
backend.add(import('@backstage/plugin-signals-backend'));
backend.add(import('@backstage/plugin-mcp-actions-backend'));

backend.start();

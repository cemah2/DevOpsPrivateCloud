/*
 * plateforme/portail — packages/backend/src/modules/authOidcMedisphere.ts (M28-E06, PLAT-2906)
 * Fournisseur « oidc » (Keycloak, royaume medisphere) avec un résolveur MédiSphère : l'utilisateur
 * connecté est l'entité User du catalogue dont le NOM vaut sa revendication preferred_username
 * (= uid FreeIPA, importé par le module LDAP en E07).
 *
 * Pourquoi un module local : dans la 1.56, le module générique n'enregistre que deux résolveurs
 * (emailLocalPartMatchingUserEntityName, emailMatchingUserEntityProfileEmail : src/resolvers.ts),
 * alors que son schéma de configuration (config.d.ts) annonce aussi
 * preferredUsernameMatchingUserEntityName — le déclarer dans app-config ferait échouer la connexion.
 * Construction reprise de la documentation « OIDC provider from scratch » (Resolvers) de la 1.56.
 *
 * Aucun repli « dangerouslyAllowSignInWithoutUserInCatalog » : une personne absente du catalogue
 * (donc de l'annuaire) ne se connecte pas.
 */
import { createBackendModule } from '@backstage/backend-plugin-api';
import {
  authProvidersExtensionPoint,
  createOAuthProviderFactory,
} from '@backstage/plugin-auth-node';
import { oidcAuthenticator } from '@backstage/plugin-auth-backend-module-oidc-provider';

export default createBackendModule({
  pluginId: 'auth',
  moduleId: 'oidc-medisphere',
  register(reg) {
    reg.registerInit({
      deps: { providers: authProvidersExtensionPoint },
      async init({ providers }) {
        providers.registerProvider({
          providerId: 'oidc',
          factory: createOAuthProviderFactory({
            authenticator: oidcAuthenticator,
            async signInResolver(info, ctx) {
              const nom = info.result.fullProfile.userinfo.preferred_username;
              if (typeof nom !== 'string' || nom.length === 0) {
                throw new Error(
                  'Connexion refusée : la revendication preferred_username est absente du jeton',
                );
              }
              return ctx.signInWithCatalogUser({ entityRef: { name: nom } });
            },
          }),
        });
      },
    });
  },
});

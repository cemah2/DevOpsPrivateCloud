// plateforme/resilience — continuite/sonde-continuite.js (F4-S02, CHG-3402)
// Charge CONSTANTE et FAIBLE qui joue l'utilisateur pendant chaque changement du trimestre :
//   - « prod_lecture » : lecture seule sur MédiAgenda PRODUCTION (créneaux d'un praticien FICTIF
//     « dr-sonde-<n> » : aucune donnée de patient lue, aucune écriture), 2 itérations/s ;
//   - « recette_ecriture » : parcours complet sur la RECETTE (création puis annulation d'un rendez-vous
//     factice, comme M29), 1 itération/s.
// Exception écrite à la règle du M29 « jamais la prod » : approuvée par Julien Petit et Claire Morel
// (sonde-continuite.md §2) pour la SEULE route GET /api/v1/creneaux, à 2 req/s au plus. Toute autre
// requête vers la prod est refusée par ce script (liste d'autorisation par scénario).
//
// Paramètres (-e ou spec.runner.env) : DUREE (défaut 3h), TAUX_PROD (2), TAUX_RECETTE (1),
// PROD_URL, RECETTE_URL. L'étiquette testid (sonde-continuite-<CHG>) est posée par --tag.
// Les seuils ne font JAMAIS échouer l'essai (une sonde ne s'arrête pas au premier incident) : ils
// signalent seulement, la mesure se lit dans Prometheus (continuite:en_erreur).
import http from 'k6/http';
import { check } from 'k6';

const PROD = (__ENV.PROD_URL || 'https://mediagenda.apps.par1.medisphere.internal').replace(/\/+$/, '');
const RECETTE = (__ENV.RECETTE_URL || 'https://mediagenda-recette.apps.par1.medisphere.internal').replace(/\/+$/, '');
if (PROD !== 'https://mediagenda.apps.par1.medisphere.internal') {
  throw new Error(`cible de production inattendue : ${PROD}`);
}
if (!/^https:\/\/mediagenda-(recette|dev)\.apps\.par1\.medisphere\.internal$/.test(RECETTE)) {
  throw new Error(`cible d'écriture refusée : ${RECETTE} (recette ou dev seulement)`);
}
const DUREE = __ENV.DUREE || '3h';
const TAUX_PROD = Math.min(parseInt(__ENV.TAUX_PROD || '2', 10), 2); // plafond écrit : 2 req/s
const TAUX_RECETTE = parseInt(__ENV.TAUX_RECETTE || '1', 10);

export const options = {
  scenarios: {
    prod_lecture: {
      executor: 'constant-arrival-rate',
      exec: 'prodLecture',
      rate: TAUX_PROD,
      timeUnit: '1s',
      duration: DUREE,
      preAllocatedVUs: 4,
      maxVUs: 20,
      tags: { cible: 'prod', type: 'sonde' },
    },
    recette_ecriture: {
      executor: 'constant-arrival-rate',
      exec: 'recetteEcriture',
      rate: TAUX_RECETTE,
      timeUnit: '1s',
      duration: DUREE,
      preAllocatedVUs: 4,
      maxVUs: 20,
      tags: { cible: 'recette', type: 'sonde' },
    },
  },
  thresholds: {
    'http_req_failed{cible:prod}': [{ threshold: 'rate<0.001', abortOnFail: false }],
    'http_req_duration{cible:prod}': [{ threshold: 'p(95)<250', abortOnFail: false }],
    'http_req_failed{cible:recette}': [{ threshold: 'rate<0.01', abortOnFail: false }],
  },
  // Requêtes lentes ou coupées : un délai court rend la coupure visible au lieu de l'étirer.
  summaryTrendStats: ['avg', 'p(95)', 'p(99)', 'max'],
};

const PARAMS = { timeout: '5s' };
const HEURES = ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30'];
function jour(decalage) {
  return new Date(Date.now() + decalage * 86400000).toISOString().slice(0, 10);
}

// Production : lecture seule, une seule route autorisée.
export function prodLecture() {
  const r = http.get(`${PROD}/api/v1/creneaux?date=${jour(1)}&praticien=dr-sonde-${__VU % 5}`,
    Object.assign({ tags: { name: 'GET /api/v1/creneaux (prod)' } }, PARAMS));
  check(r, { 'prod créneaux : 200': (x) => x.status === 200 });
}

// Recette : création puis annulation (rien ne reste), J+90 et au-delà (jamais un jour de recette réel).
export function recetteEcriture() {
  const j = jour(90 + (__ITER % 30));
  const debut = `${j}T${HEURES[__ITER % HEURES.length]}:00+01:00`;
  const corps = JSON.stringify({ patient: 'Patient Sonde', praticien: `dr-sonde-${__VU}`, debut, duree_minutes: 30, motif: 'sonde de continuité (F4)' });
  const c = http.post(`${RECETTE}/api/v1/rendez-vous`, corps, Object.assign({
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'POST /api/v1/rendez-vous (recette)' },
    responseCallback: http.expectedStatuses(201, 409),
  }, PARAMS));
  check(c, { 'recette création : 201 ou 409': (x) => x.status === 201 || x.status === 409 });
  if (c.status === 201) {
    const d = http.del(`${RECETTE}/api/v1/rendez-vous/${c.json('id')}`, null,
      Object.assign({ tags: { name: 'DELETE /api/v1/rendez-vous/{id} (recette)' } }, PARAMS));
    check(d, { 'recette annulation : 204': (x) => x.status === 204 });
  }
}

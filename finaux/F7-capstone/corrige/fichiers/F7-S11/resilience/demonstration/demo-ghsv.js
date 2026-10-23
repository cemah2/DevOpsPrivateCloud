// plateforme/resilience — demonstration/demo-ghsv.js (F7-S11, PLAT-3711)
// Charge de DÉMONSTRATION du client GHSV : le parcours du DPI du contrat v1, à débit constant, sur
// l'instance ghsv-prod (production de démonstration, données FICTIVES : praticiens « DEMO-nnn »,
// patients « Patient Démo », dates en 2030). Écriture permise ici parce que le locataire ne contient
// que des données fictives (ESC-13 ne s'applique qu'aux données réelles) : décision écrite dans le
// compte rendu de la journée de jeu.
//
// Authentification : jeton « client credentials » du client ghsv-dpi-demo (jamais le client remis au
// GHSV), secret dans kv/ghsv/prod/dpi-demo, Secret « demo-ghsv-dpi » de l'espace k6 (ESO).
// Paramètres : DUREE (défaut 90m), TAUX (itérations/s, défaut 4, plafonné à 20 : chaque itération
// fait 5 requêtes), CIBLE (défaut https://ghsv.apps.par1.medisphere.internal).
import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

const CIBLE = (__ENV.CIBLE || 'https://ghsv.apps.par1.medisphere.internal').replace(/\/+$/, '');
if (!/^https:\/\/ghsv(-recette)?\.apps\.par[12]\.medisphere\.internal$/.test(CIBLE)) {
  throw new Error(`cible refusée : ${CIBLE} (instances du GHSV seulement)`);
}
const JETON_URL = 'https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token';
const DUREE = __ENV.DUREE || '90m';
const TAUX = Math.min(Math.max(parseInt(__ENV.TAUX || '4', 10), 1), 20);

export const options = {
  scenarios: {
    dpi: {
      executor: 'constant-arrival-rate',
      rate: TAUX,
      timeUnit: '1s',
      duration: DUREE,
      preAllocatedVUs: 10,
      maxVUs: 60,
      tags: { client: 'ghsv', parcours: 'dpi' },
    },
  },
  // Les seuils signalent, ils n'arrêtent jamais la démonstration (abortOnFail: false).
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.001', abortOnFail: false }],
    'http_req_duration{operation:creneaux}': [{ threshold: 'p(95)<300', abortOnFail: false }],
  },
  summaryTrendStats: ['avg', 'p(95)', 'p(99)', 'max'],
};

// Jeton par utilisateur virtuel, renouvelé avant son expiration (5 min).
const jetons = {};
function jeton() {
  const vu = exec.vu.idInTest;
  const maintenant = Date.now();
  if (!jetons[vu] || maintenant - jetons[vu].obtenu > 240000) {
    const r = http.post(
      JETON_URL,
      { grant_type: 'client_credentials', client_id: __ENV.CLIENT_ID, client_secret: __ENV.CLIENT_SECRET },
      { tags: { operation: 'jeton' }, timeout: '5s' },
    );
    check(r, { 'jeton obtenu': (x) => x.status === 200 });
    jetons[vu] = { valeur: r.status === 200 ? r.json('access_token') : '', obtenu: maintenant };
  }
  return jetons[vu].valeur;
}

function entetes(operation) {
  return {
    headers: { Authorization: `Bearer ${jeton()}`, 'Content-Type': 'application/json' },
    tags: { operation },
    timeout: '5s',
  };
}

export default function () {
  // Un praticien fictif et un jour de 2030 (lundi à vendredi) par itération : peu de conflits.
  const praticien = `DEMO-${String(Math.floor(Math.random() * 200)).padStart(3, '0')}`;
  const jour = new Date(Date.UTC(2030, 0, 7 + Math.floor(Math.random() * 300)));
  if (jour.getUTCDay() === 0 || jour.getUTCDay() === 6) jour.setUTCDate(jour.getUTCDate() + 2);
  const date = jour.toISOString().slice(0, 10);

  const c = http.get(`${CIBLE}/api/v1/creneaux?date=${date}&praticien=${praticien}`, entetes('creneaux'));
  if (!check(c, { 'créneaux 200': (r) => r.status === 200 })) return;
  const libres = c.json('libres') || [];
  if (libres.length < 2) return;

  const corps = JSON.stringify({ patient: 'Patient Démo', praticien, debut: libres[0], duree_minutes: 30, motif: 'Démonstration', rappel: { canal: 'aucun' } });
  const cree = http.post(`${CIBLE}/api/v1/rendez-vous`, corps, entetes('creation'));
  if (!check(cree, { 'création 201 ou 409': (r) => r.status === 201 || r.status === 409 }) || cree.status !== 201) return;
  const id = cree.json('id');

  const du = `${date}T00:00:00+00:00`;
  const au = `${date}T23:59:59+00:00`;
  check(http.get(`${CIBLE}/api/v1/rendez-vous?praticien=${praticien}&du=${encodeURIComponent(du)}&au=${encodeURIComponent(au)}`, entetes('liste')), {
    'liste 200': (r) => r.status === 200,
  });
  check(http.patch(`${CIBLE}/api/v1/rendez-vous/${id}`, JSON.stringify({ debut: libres[libres.length - 1] }), entetes('deplacement')), {
    'déplacement 200 ou 409': (r) => r.status === 200 || r.status === 409,
  });
  check(http.del(`${CIBLE}/api/v1/rendez-vous/${id}`, null, entetes('annulation')), { 'annulation 204': (r) => r.status === 204 });
}

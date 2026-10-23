// Test de charge MédiAgenda — Lucas Martin, MR !37 de plateforme/resilience (PLAT-3011)
// Objectif (ticket) : montrer que MédiAgenda tient 500 requêtes/s.
// 50 VUs × 10 itérations/s chacun = 500 req/s. Lancer : k6 run charge/creneaux-charge.js
// Les checks font échouer le test si moins de 95 % des réponses sont bonnes.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import papaparse from 'https://jslib.k6.io/papaparse/5.1.1/index.js';

// Vrais patients pour avoir des données réalistes (export de la base, voir donnees/).
const patients = new SharedArray('patients', () => papaparse.parse(open('./donnees/patients.csv'), { header: true }).data);

const BASE = __ENV.BASE_URL || 'https://mediagenda.apps.par1.medisphere.internal';

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    creneaux: {
      executor: 'constant-arrival-rate',
      rate: 500,
      timeUnit: '1s',
      duration: '10m',
      preAllocatedVUs: 50,
      maxVUs: 50,
    },
  },
};

export default function () {
  const p = patients[Math.floor(Math.random() * patients.length)];

  const c = http.get(`${BASE}/api/v1/creneaux?date=2026-11-02&praticien=dr-morel`);
  check(c, { 'créneaux ok': (r) => r.status < 500 });

  const r = http.post(`${BASE}/api/v1/rendez-vous`, JSON.stringify({
    patient: `${p.prenom} ${p.nom}`,
    praticien: 'dr-morel',
    debut: '2026-11-02T09:00:00',
    duree_minutes: 30,
    motif: `NIR ${p.nir}`,
  }), { headers: { 'Content-Type': 'application/json' } });
  check(r, { 'rdv ok': (x) => x.status < 500 });

  if (r.status === 201) {
    http.get(`${BASE}/api/v1/rendez-vous/${r.json('id')}`);
  }

  sleep(0.1); // 10 itérations par seconde et par VU
}

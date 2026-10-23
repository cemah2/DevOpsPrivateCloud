// plateforme/resilience — charge/distribue/mediagenda-recette.js (M29-E14, PLAT-3014)
// Parcours d'un patient sur MédiAgenda (recette), pour k6-operator (TestRun distribué) comme pour un
// essai depuis adm01. Même parcours que M29-E06 : créneaux d'un jour, création d'un rendez-vous,
// lecture, annulation (on ne laisse rien derrière soi), liste.
//
// Paramètres (variables d'environnement, -e ou spec.runner.env) :
//   BASE_URL      défaut https://mediagenda-recette.apps.par1.medisphere.internal
//   TAUX_CIBLE    itérations par seconde visées (total, réparti entre exécuteurs), défaut 20
//   PALIER        durée du palier au taux cible, défaut 5m
// L'étiquette testid est posée par la ligne de commande (--tag testid=…) : elle accompagne chaque
// métrique jusque dans Prometheus.
//
// Seuils alignés sur le SLO de latence (250 ms à 95 %, M21) et de disponibilité. En distribué, chaque
// exécuteur évalue ses seuils sur SA part : le verdict global se lit dans Prometheus (RB-295).
import http from 'k6/http';
import { check, group } from 'k6';

const BASE = __ENV.BASE_URL || 'https://mediagenda-recette.apps.par1.medisphere.internal';
const TAUX = parseInt(__ENV.TAUX_CIBLE || '20', 10);
const PALIER = __ENV.PALIER || '5m';
const PRATICIENS = ['dr-morel', 'dr-benali', 'dr-laurent', 'dr-petit', 'dr-roussel'];

export const options = {
  scenarios: {
    parcours: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 200,
      stages: [
        { target: TAUX, duration: '1m' },   // montée
        { target: TAUX, duration: PALIER }, // palier mesuré
        { target: 0, duration: '30s' },     // descente
      ],
    },
  },
  thresholds: {
    'http_req_duration{type:metier}': ['p(95)<250', 'p(99)<1000'],
    'http_req_failed{type:metier}': ['rate<0.01'],
    checks: ['rate>0.99'],
  },
  // Jauges envoyées par l'écriture distante (voir TestRun) ; ici pour le résumé local.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Un créneau futur (J+2 à J+30) à une demi-heure ronde, en heure de Paris : peu de conflits (409).
function creneau() {
  const j = new Date(Date.now() + (2 + Math.floor(Math.random() * 29)) * 86400000);
  const heure = 8 + Math.floor(Math.random() * 9); // 8 h à 16 h
  const minute = Math.random() < 0.5 ? '00' : '30';
  const jour = j.toISOString().slice(0, 10);
  return { jour, debut: `${jour}T${String(heure).padStart(2, '0')}:${minute}:00+01:00` };
}

const metier = (nom) => ({ tags: { type: 'metier', name: nom } });
// 409 (créneau déjà pris) est une réponse normale de l'API, pas une erreur.
const metier201ou409 = (nom) => ({ tags: { type: 'metier', name: nom }, responseCallback: http.expectedStatuses(201, 409) });

export default function () {
  const praticien = PRATICIENS[Math.floor(Math.random() * PRATICIENS.length)];
  const { jour, debut } = creneau();

  group('creneaux', () => {
    const r = http.get(`${BASE}/api/v1/creneaux?date=${jour}&praticien=${praticien}`, metier('GET /api/v1/creneaux'));
    check(r, { 'créneaux : 200': (x) => x.status === 200 });
  });

  group('rendez-vous', () => {
    const corps = JSON.stringify({ patient: 'Patient Charge', praticien, debut, duree_minutes: 30, motif: 'Test de charge' });
    const c = http.post(`${BASE}/api/v1/rendez-vous`, corps,
      Object.assign(metier201ou409('POST /api/v1/rendez-vous'), { headers: { 'Content-Type': 'application/json' } }));
    check(c, { 'création : 201 ou 409': (x) => x.status === 201 || x.status === 409 });
    if (c.status === 201) {
      const id = c.json('id');
      const g = http.get(`${BASE}/api/v1/rendez-vous/${id}`, metier('GET /api/v1/rendez-vous/{id}'));
      check(g, { 'lecture : 200': (x) => x.status === 200 });
      const d = http.del(`${BASE}/api/v1/rendez-vous/${id}`, null, metier('DELETE /api/v1/rendez-vous/{id}'));
      check(d, { 'annulation : 204': (x) => x.status === 204 });
    }
  });

  group('liste', () => {
    const l = http.get(`${BASE}/api/v1/rendez-vous?limite=20`, metier('GET /api/v1/rendez-vous'));
    check(l, { 'liste : 200': (x) => x.status === 200 });
  });
}

// plateforme/resilience — charge/premier-test.js (M29-E05, PLAT-3005)
//
// Premier test de charge de MédiAgenda, en RECETTE, depuis adm01. Un parcours :
//   1. lire les créneaux d'un jour (GET /api/v1/creneaux) ;
//   2. réserver un rendez-vous factice (POST /api/v1/rendez-vous, 201) ;
//   3. le relire (GET /api/v1/rendez-vous/{id}, 200) ;
//   4. l'annuler (DELETE /api/v1/rendez-vous/{id}, 204) : la base de recette reste propre.
//
// Deux modèles de charge, choisis par la variable MODELE :
//   MODELE=ferme  (défaut) 5 VUs pendant 2 min : chaque VU enchaîne les itérations ; le débit
//                 DÉPEND du temps de réponse (si MédiAgenda ralentit, la charge baisse).
//   MODELE=ouvert 3 itérations/s pendant 2 min, quel que soit le temps de réponse (arrivées
//                 indépendantes, comme de vrais patients) ; k6 ajoute des VUs si besoin.
//
//   k6 inspect charge/premier-test.js
//   k6 run charge/premier-test.js
//   k6 run -e MODELE=ouvert charge/premier-test.js
//   k6 run -e BASE_URL=http://127.0.0.1:18000 charge/premier-test.js   (MédiAgenda local)
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import exec from 'k6/execution';
import { BASE_URL, ENTETES_JSON, corpsRendezVous, lectureAleatoire } from './lib/commun.js';

const MODELE = __ENV.MODELE || 'ferme';

const SCENARIOS = {
  ferme: {
    executor: 'constant-vus',
    vus: 5,
    duration: '2m',
  },
  ouvert: {
    executor: 'constant-arrival-rate',
    rate: 3,
    timeUnit: '1s',
    duration: '2m',
    preAllocatedVUs: 5,
    maxVUs: 20,
  },
};

if (!SCENARIOS[MODELE]) {
  throw new Error(`MODELE inconnu : ${MODELE} (ferme ou ouvert)`);
}

export const options = {
  scenarios: { parcours: SCENARIOS[MODELE] },
  // Les SEUILS décident du code de sortie de k6 (99 = seuil franchi) ; les checks, seuls, non.
  thresholds: {
    // SLO de latence de MédiAgenda (M21) : 95 % des requêtes en moins de 250 ms.
    http_req_duration: ['p(95)<250'],
    // Disponibilité : 99,5 % (M21). Ici toute réponse >= 400 compte comme échec.
    http_req_failed: ['rate<0.005'],
    // Les vérifications fonctionnelles doivent toutes passer.
    checks: ['rate==1.0'],
  },
};

export default function () {
  const vu = exec.vu.idInTest;
  const iteration = exec.vu.iterationInScenario;

  group('lire les créneaux', () => {
    const { praticien, jour } = lectureAleatoire(20);
    const r = http.get(`${BASE_URL}/api/v1/creneaux?date=${jour}&praticien=${praticien}`, {
      tags: { name: 'GET /api/v1/creneaux' },
    });
    check(r, {
      'créneaux : 200': (x) => x.status === 200,
      'créneaux : liste « libres »': (x) => Array.isArray(x.json('libres')),
    });
  });

  group('réserver puis annuler', () => {
    const cree = http.post(`${BASE_URL}/api/v1/rendez-vous`, corpsRendezVous(vu, iteration), {
      ...ENTETES_JSON,
      tags: { name: 'POST /api/v1/rendez-vous' },
    });
    const ok = check(cree, { 'création : 201': (x) => x.status === 201 });
    if (!ok) {
      return; // rien à relire ni à annuler
    }
    const id = cree.json('id');
    // Le nom de requête regroupe les URL : sans lui, chaque identifiant serait une série à part.
    const lu = http.get(`${BASE_URL}/api/v1/rendez-vous/${id}`, { tags: { name: 'GET /api/v1/rendez-vous/{id}' } });
    check(lu, { 'lecture : 200': (x) => x.status === 200 });
    const annule = http.del(`${BASE_URL}/api/v1/rendez-vous/${id}`, null, { tags: { name: 'DELETE /api/v1/rendez-vous/{id}' } });
    check(annule, { 'annulation : 204': (x) => x.status === 204 });
  });

  // Temps de réflexion d'un patient dans le modèle FERMÉ seulement : dans le modèle ouvert, le
  // rythme est fixé par l'exécuteur, une pause ne ferait qu'occuper des VUs.
  if (MODELE === 'ferme') {
    sleep(1);
  }
}

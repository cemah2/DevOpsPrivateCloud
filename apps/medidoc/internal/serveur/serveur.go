// Package serveur expose l'API HTTP de MédiDoc.
package serveur

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"git01.par1.medisphere.internal/medidoc/medidoc/internal/stockage"
)

var (
	idValide      = regexp.MustCompile(`^[0-9a-f]{32}$`)
	patientValide = regexp.MustCompile(`^[A-Za-z0-9-]{1,64}$`)
)

// Serveur porte les dépendances des gestionnaires HTTP.
type Serveur struct {
	depot     *stockage.Depot
	maxOctets int64
	version   string
	journal   *slog.Logger

	registre *prometheus.Registry
	requetes *prometheus.CounterVec
	durees   *prometheus.HistogramVec
}

// Nouveau crée le serveur. Chaque instance a son propre registre Prometheus
// (pas de registre global) : les tests peuvent en créer plusieurs.
func Nouveau(depot *stockage.Depot, maxOctets int64, version string, journal *slog.Logger) *Serveur {
	s := &Serveur{
		depot:     depot,
		maxOctets: maxOctets,
		version:   version,
		journal:   journal,
		registre:  prometheus.NewRegistry(),
		// Le libellé « route » est le motif (GET /documents/{id}), jamais le
		// chemin réel : un identifiant par série ferait exploser la cardinalité.
		requetes: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "medidoc_http_requests_total",
			Help: "Requêtes HTTP traitées",
		}, []string{"methode", "route", "code"}),
		durees: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "medidoc_http_request_duration_seconds",
			Help:    "Durée de traitement des requêtes HTTP",
			Buckets: prometheus.DefBuckets,
		}, []string{"methode", "route"}),
	}
	s.registre.MustRegister(
		s.requetes, s.durees,
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)
	return s
}

// Handler renvoie le routeur complet, enveloppé par la mesure et le journal.
func (s *Serveur) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /readyz", s.readyz)
	mux.Handle("GET /metrics", promhttp.HandlerFor(s.registre, promhttp.HandlerOpts{}))
	mux.HandleFunc("POST /documents", s.deposer)
	mux.HandleFunc("GET /documents", s.lister)
	mux.HandleFunc("GET /documents/{id}", s.lire)
	return s.instrumenter(mux)
}

// healthz : vivacité. Ne contacte pas le stockage.
func (s *Serveur) healthz(w http.ResponseWriter, _ *http.Request) {
	ecrireJSON(w, http.StatusOK, map[string]string{"statut": "ok", "version": s.version})
}

// readyz : disponibilité. HeadBucket sur le compartiment, 503 en cas d'échec.
func (s *Serveur) readyz(w http.ResponseWriter, r *http.Request) {
	ctx, annuler := context.WithTimeout(r.Context(), 2*time.Second)
	defer annuler()
	if err := s.depot.Verifier(ctx); err != nil {
		s.journal.Warn("stockage indisponible", "erreur", err.Error())
		ecrireJSON(w, http.StatusServiceUnavailable, map[string]string{"statut": "pas-pret", "s3": "indisponible"})
		return
	}
	ecrireJSON(w, http.StatusOK, map[string]string{"statut": "pret", "s3": "ok"})
}

// deposer : POST /documents, multipart/form-data avec les champs
// « patient » (identifiant) et « fichier » (le document).
func (s *Serveur) deposer(w http.ResponseWriter, r *http.Request) {
	// Plafond sur le corps entier (document + enveloppe multipart).
	r.Body = http.MaxBytesReader(w, r.Body, s.maxOctets+1<<20)
	lecteur, err := r.MultipartReader()
	if err != nil {
		ecrireErreur(w, http.StatusBadRequest, "multipart/form-data attendu")
		return
	}

	var doc stockage.Document
	var contenu []byte
	for {
		partie, err := lecteur.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			s.erreurCorps(w, err)
			return
		}
		switch partie.FormName() {
		case "patient":
			v, err := io.ReadAll(io.LimitReader(partie, 65))
			if err != nil {
				s.erreurCorps(w, err)
				return
			}
			doc.Patient = strings.TrimSpace(string(v))
		case "fichier":
			// On lit au plus max+1 octets : un octet de trop suffit à refuser.
			contenu, err = io.ReadAll(io.LimitReader(partie, s.maxOctets+1))
			if err != nil {
				s.erreurCorps(w, err)
				return
			}
			if int64(len(contenu)) > s.maxOctets {
				ecrireErreur(w, http.StatusRequestEntityTooLarge, "document trop volumineux (MEDIDOC_MAX_MB)")
				return
			}
			doc.NomFichier = partie.FileName()
			doc.TypeContenu = partie.Header.Get("Content-Type")
		}
		_ = partie.Close()
	}

	switch {
	case contenu == nil:
		ecrireErreur(w, http.StatusBadRequest, "champ « fichier » absent")
		return
	case !patientValide.MatchString(doc.Patient):
		ecrireErreur(w, http.StatusBadRequest, "champ « patient » absent ou invalide")
		return
	}
	if doc.TypeContenu == "" || doc.TypeContenu == "application/octet-stream" {
		doc.TypeContenu = http.DetectContentType(contenu)
	}
	doc.ID = nouvelID()
	doc.Taille = int64(len(contenu))

	if err := s.depot.Enregistrer(r.Context(), doc, contenu); err != nil {
		s.journal.Error("échec d'enregistrement", "erreur", err.Error())
		ecrireErreur(w, http.StatusBadGateway, "stockage indisponible")
		return
	}
	// Ni nom de fichier ni patient dans le journal : données de santé.
	s.journal.Info("document enregistré", "document_id", doc.ID, "taille", doc.Taille)
	w.Header().Set("Location", "/documents/"+doc.ID)
	ecrireJSON(w, http.StatusCreated, doc)
}

// lire : GET /documents/{id}, renvoie le contenu du document.
func (s *Serveur) lire(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !idValide.MatchString(id) {
		ecrireErreur(w, http.StatusBadRequest, "identifiant invalide")
		return
	}
	obj, err := s.depot.Lire(r.Context(), id)
	if errors.Is(err, stockage.ErrIntrouvable) {
		ecrireErreur(w, http.StatusNotFound, "document introuvable")
		return
	}
	if err != nil {
		s.journal.Error("échec de lecture", "document_id", id, "erreur", err.Error())
		ecrireErreur(w, http.StatusBadGateway, "stockage indisponible")
		return
	}
	defer obj.Corps.Close()

	if obj.TypeContenu != "" {
		w.Header().Set("Content-Type", obj.TypeContenu)
	}
	if obj.Taille > 0 {
		w.Header().Set("Content-Length", strconv.FormatInt(obj.Taille, 10))
	}
	nom := obj.NomFichier
	if nom == "" {
		nom = id
	}
	// FormatMediaType encode les noms non ASCII (RFC 2231) : « compte-rendu-échographie.pdf ».
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": nom}))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if _, err := io.Copy(w, obj.Corps); err != nil {
		s.journal.Warn("envoi interrompu", "document_id", id, "erreur", err.Error())
	}
}

// lister : GET /documents?limite=100.
func (s *Serveur) lister(w http.ResponseWriter, r *http.Request) {
	limite := int32(100)
	if v := r.URL.Query().Get("limite"); v != "" {
		n, err := strconv.ParseInt(v, 10, 32)
		if err != nil || n < 1 || n > 1000 {
			ecrireErreur(w, http.StatusBadRequest, "limite entre 1 et 1000")
			return
		}
		limite = int32(n)
	}
	docs, err := s.depot.Lister(r.Context(), limite)
	if err != nil {
		s.journal.Error("échec de la liste", "erreur", err.Error())
		ecrireErreur(w, http.StatusBadGateway, "stockage indisponible")
		return
	}
	ecrireJSON(w, http.StatusOK, docs)
}

func (s *Serveur) erreurCorps(w http.ResponseWriter, err error) {
	var trop *http.MaxBytesError
	if errors.As(err, &trop) {
		ecrireErreur(w, http.StatusRequestEntityTooLarge, "document trop volumineux (MEDIDOC_MAX_MB)")
		return
	}
	ecrireErreur(w, http.StatusBadRequest, "corps multipart illisible")
}

// instrumenter mesure chaque requête et écrit une ligne de journal JSON.
func (s *Serveur) instrumenter(suivant http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		debut := time.Now()
		rec := &enregistreur{ResponseWriter: w, code: http.StatusOK}
		suivant.ServeHTTP(rec, r)
		duree := time.Since(debut)

		// Le routeur renseigne r.Pattern (Go 1.23+) avec le motif choisi.
		route := r.Pattern
		if route == "" {
			route = "non-routee"
		}
		s.requetes.WithLabelValues(r.Method, route, strconv.Itoa(rec.code)).Inc()
		s.durees.WithLabelValues(r.Method, route).Observe(duree.Seconds())

		niveau := slog.LevelInfo
		if route == "GET /healthz" || route == "GET /readyz" || route == "GET /metrics" {
			niveau = slog.LevelDebug // sondes : appelées toutes les quelques secondes
		}
		s.journal.Log(r.Context(), niveau, "requête",
			"methode", r.Method,
			"chemin", r.URL.Path,
			"route", route,
			"code", rec.code,
			"duree_ms", float64(duree.Microseconds())/1000,
			"client", r.RemoteAddr,
		)
	})
}

type enregistreur struct {
	http.ResponseWriter
	code int
}

func (e *enregistreur) WriteHeader(code int) {
	e.code = code
	e.ResponseWriter.WriteHeader(code)
}

// Unwrap permet à http.ResponseController d'atteindre le ResponseWriter d'origine.
func (e *enregistreur) Unwrap() http.ResponseWriter { return e.ResponseWriter }

func nouvelID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b) // crypto/rand.Read ne renvoie jamais d'erreur (Go 1.24+)
	return hex.EncodeToString(b)
}

func ecrireJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func ecrireErreur(w http.ResponseWriter, code int, message string) {
	ecrireJSON(w, code, map[string]string{"erreur": message})
}

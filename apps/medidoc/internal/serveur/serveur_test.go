package serveur_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"git01.par1.medisphere.internal/medidoc/medidoc/internal/serveur"
	"git01.par1.medisphere.internal/medidoc/medidoc/internal/stockage"
	"git01.par1.medisphere.internal/medidoc/medidoc/internal/stockage/stockagetest"
)

func nouveau(t *testing.T, maxOctets int64) (*httptest.Server, *stockagetest.FauxS3, *bytes.Buffer) {
	t.Helper()
	faux := stockagetest.Nouveau()
	var journal bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&journal, &slog.HandlerOptions{Level: slog.LevelDebug}))
	srv := serveur.Nouveau(stockage.NouveauDepot(faux, "medidoc-documents"), maxOctets, "1.2.3", log)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts, faux, &journal
}

func formulaire(t *testing.T, patient, nom string, contenu []byte) (*bytes.Buffer, string) {
	t.Helper()
	var corps bytes.Buffer
	mw := multipart.NewWriter(&corps)
	if patient != "" {
		if err := mw.WriteField("patient", patient); err != nil {
			t.Fatal(err)
		}
	}
	if contenu != nil {
		fw, err := mw.CreateFormFile("fichier", nom)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := fw.Write(contenu); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return &corps, mw.FormDataContentType()
}

func deposer(t *testing.T, ts *httptest.Server, patient, nom string, contenu []byte) *http.Response {
	t.Helper()
	corps, typ := formulaire(t, patient, nom, contenu)
	r, err := http.Post(ts.URL+"/documents", typ, corps)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { r.Body.Close() })
	return r
}

func TestHealthzNeContactePasLeStockage(t *testing.T) {
	ts, faux, _ := nouveau(t, 1<<20)
	faux.EnPanne = errors.New("S3 injoignable")
	r, err := http.Get(ts.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer r.Body.Close()
	var corps map[string]string
	_ = json.NewDecoder(r.Body).Decode(&corps)
	if r.StatusCode != http.StatusOK || corps["version"] != "1.2.3" {
		t.Fatalf("healthz : %d %v", r.StatusCode, corps)
	}
}

func TestReadyz(t *testing.T) {
	ts, faux, _ := nouveau(t, 1<<20)
	for _, c := range []struct {
		panne error
		code  int
	}{{nil, 200}, {errors.New("403 Forbidden"), 503}} {
		faux.EnPanne = c.panne
		r, err := http.Get(ts.URL + "/readyz")
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		if r.StatusCode != c.code {
			t.Errorf("readyz avec panne=%v : %d, attendu %d", c.panne, r.StatusCode, c.code)
		}
	}
}

func TestDeposerPuisRelire(t *testing.T) {
	ts, faux, journal := nouveau(t, 1<<20)
	contenu := []byte("%PDF-1.7 compte rendu")
	r := deposer(t, ts, "PAT-000123", "compte-rendu-échographie.pdf", contenu)
	if r.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(r.Body)
		t.Fatalf("dépôt : %d %s", r.StatusCode, b)
	}
	var doc stockage.Document
	if err := json.NewDecoder(r.Body).Decode(&doc); err != nil {
		t.Fatal(err)
	}
	if len(doc.ID) != 32 || doc.Taille != int64(len(contenu)) || r.Header.Get("Location") != "/documents/"+doc.ID {
		t.Fatalf("réponse inattendue : %+v %s", doc, r.Header.Get("Location"))
	}
	if faux.Nombre() != 1 {
		t.Fatalf("%d objet(s) dans le faux S3", faux.Nombre())
	}

	g, err := http.Get(ts.URL + "/documents/" + doc.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer g.Body.Close()
	lu, _ := io.ReadAll(g.Body)
	if g.StatusCode != 200 || !bytes.Equal(lu, contenu) {
		t.Fatalf("relecture : %d %q", g.StatusCode, lu)
	}
	if cd := g.Header.Get("Content-Disposition"); !strings.Contains(cd, "attachment") || !strings.Contains(cd, "%C3%A9chographie") {
		t.Errorf("Content-Disposition : %q", cd)
	}
	if strings.Contains(journal.String(), "PAT-000123") || strings.Contains(journal.String(), "échographie") {
		t.Error("le journal contient une donnée patient")
	}
}

func TestDocumentTropVolumineux(t *testing.T) {
	ts, faux, _ := nouveau(t, 1024)
	r := deposer(t, ts, "PAT-1", "gros.bin", bytes.Repeat([]byte("x"), 1025))
	if r.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("code %d, attendu 413", r.StatusCode)
	}
	if faux.Nombre() != 0 {
		t.Fatal("un document trop gros a été stocké")
	}
	if r := deposer(t, ts, "PAT-1", "juste.bin", bytes.Repeat([]byte("x"), 1024)); r.StatusCode != http.StatusCreated {
		t.Fatalf("document à la limite refusé : %d", r.StatusCode)
	}
}

func TestDepotInvalide(t *testing.T) {
	ts, _, _ := nouveau(t, 1<<20)
	cas := map[string]*http.Response{
		"sans fichier":     deposer(t, ts, "PAT-1", "", nil),
		"sans patient":     deposer(t, ts, "", "a.pdf", []byte("x")),
		"patient invalide": deposer(t, ts, "../../etc", "a.pdf", []byte("x")),
	}
	for nom, r := range cas {
		if r.StatusCode != http.StatusBadRequest {
			t.Errorf("%s : %d, attendu 400", nom, r.StatusCode)
		}
	}
	r, err := http.Post(ts.URL+"/documents", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	r.Body.Close()
	if r.StatusCode != http.StatusBadRequest {
		t.Errorf("JSON au lieu de multipart : %d", r.StatusCode)
	}
}

func TestLectureIntrouvableEtIdentifiantInvalide(t *testing.T) {
	ts, _, _ := nouveau(t, 1<<20)
	for chemin, code := range map[string]int{
		"/documents/0123456789abcdef0123456789abcdef": 404,
		"/documents/pas-un-id":                        400,
	} {
		r, err := http.Get(ts.URL + chemin)
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		if r.StatusCode != code {
			t.Errorf("%s : %d, attendu %d", chemin, r.StatusCode, code)
		}
	}
}

func TestListe(t *testing.T) {
	ts, _, _ := nouveau(t, 1<<20)
	for range 3 {
		deposer(t, ts, "PAT-1", "a.txt", []byte("bonjour"))
	}
	r, err := http.Get(ts.URL + "/documents?limite=2")
	if err != nil {
		t.Fatal(err)
	}
	defer r.Body.Close()
	var docs []stockage.Document
	if err := json.NewDecoder(r.Body).Decode(&docs); err != nil {
		t.Fatal(err)
	}
	if len(docs) != 2 || docs[0].Taille != 7 {
		t.Fatalf("liste : %+v", docs)
	}
}

func TestStockageEnPanne502(t *testing.T) {
	ts, faux, _ := nouveau(t, 1<<20)
	faux.EnPanne = errors.New("connexion refusée")
	if r := deposer(t, ts, "PAT-1", "a.txt", []byte("x")); r.StatusCode != http.StatusBadGateway {
		t.Fatalf("code %d, attendu 502", r.StatusCode)
	}
}

func TestMetriquesEtJournal(t *testing.T) {
	ts, _, journal := nouveau(t, 1<<20)
	r, _ := http.Get(ts.URL + "/documents/0123456789abcdef0123456789abcdef")
	r.Body.Close()
	m, err := http.Get(ts.URL + "/metrics")
	if err != nil {
		t.Fatal(err)
	}
	defer m.Body.Close()
	texte, _ := io.ReadAll(m.Body)
	for _, attendu := range []string{
		`medidoc_http_requests_total{code="404",methode="GET",route="GET /documents/{id}"} 1`,
		"medidoc_http_request_duration_seconds_bucket",
		"go_goroutines",
	} {
		if !bytes.Contains(texte, []byte(attendu)) {
			t.Errorf("métrique absente : %s", attendu)
		}
	}
	// une ligne JSON par requête
	var ligne map[string]any
	premiere, _, _ := strings.Cut(journal.String(), "\n")
	if err := json.Unmarshal([]byte(premiere), &ligne); err != nil || ligne["route"] != "GET /documents/{id}" {
		t.Fatalf("ligne de journal : %q (%v)", premiere, err)
	}
}

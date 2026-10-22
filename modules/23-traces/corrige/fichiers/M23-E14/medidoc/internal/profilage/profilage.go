// Package profilage expose les profils pprof de MédiDoc sur un port INTERNE, séparé de l'API publique.
//
// Le port (MEDIDOC_PPROF_ADDR, ex. « :6060 ») n'est publié par aucun Service ni par la Gateway : seul Alloy
// (espace journaux) le joint, par l'adresse du pod, et une CiliumNetworkPolicy refuse tout le reste.
// Profils servis : ceux de net/http/pprof (CPU, goroutines, tas…) et les profils « delta » de godeltaprof
// (tas, blocages, verrous), qu'Alloy préfère parce qu'ils ne sont pas cumulés depuis le démarrage.
package profilage

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/pprof"
	"runtime"
	"time"

	deltapprof "github.com/grafana/pyroscope-go/godeltaprof/http/pprof"
)

// Demarrer lance le serveur pprof si adresse n'est pas vide ; il s'arrête quand ctx est annulé.
// Une erreur d'écoute est journalisée sans arrêter MédiDoc : le profilage ne doit jamais coûter le service.
func Demarrer(ctx context.Context, adresse string, journal *slog.Logger) {
	if adresse == "" {
		journal.Info("profilage désactivé (MEDIDOC_PPROF_ADDR vide)")
		return
	}
	// Échantillonnage des verrous (1 sur 5) et des attentes de plus de 10 ms : surcoût faible, à mesurer.
	runtime.SetMutexProfileFraction(5)
	runtime.SetBlockProfileRate(int(10 * time.Millisecond))

	mux := http.NewServeMux()
	mux.HandleFunc("GET /debug/pprof/", pprof.Index)
	mux.HandleFunc("GET /debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("GET /debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("GET /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("GET /debug/pprof/trace", pprof.Trace)
	mux.HandleFunc("GET /debug/pprof/delta_heap", deltapprof.Heap)
	mux.HandleFunc("GET /debug/pprof/delta_block", deltapprof.Block)
	mux.HandleFunc("GET /debug/pprof/delta_mutex", deltapprof.Mutex)

	srv := &http.Server{
		Addr:              adresse,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		// Un profil CPU dure « seconds » (15 s chez Alloy) : l'écriture doit pouvoir durer davantage.
		WriteTimeout: 60 * time.Second,
	}
	go func() {
		journal.Info("profilage pprof démarré", "adresse", adresse)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			journal.Error("serveur pprof arrêté", "erreur", err.Error())
		}
	}()
	go func() {
		<-ctx.Done()
		arret, annuler := context.WithTimeout(context.Background(), 5*time.Second)
		defer annuler()
		_ = srv.Shutdown(arret)
	}()
}

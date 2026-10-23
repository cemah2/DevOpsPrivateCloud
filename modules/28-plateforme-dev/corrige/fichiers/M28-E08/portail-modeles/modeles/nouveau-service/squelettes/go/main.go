// ${{ values.nom }} — service minimal (squelette du modèle « nouveau service »).
// Bibliothèque standard seulement : /sante et /pret sur le port 8080, arrêt propre sur SIGTERM.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	journal := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", "${{ values.nom }}")
	mux := http.NewServeMux()
	ok := func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"statut":"ok"}`))
	}
	mux.HandleFunc("GET /sante", ok)
	mux.HandleFunc("GET /pret", ok)

	srv := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() {
		<-ctx.Done()
		arret, annuler := context.WithTimeout(context.Background(), 20*time.Second)
		defer annuler()
		_ = srv.Shutdown(arret)
	}()
	journal.Info("démarrage", "port", 8080)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		journal.Error("arrêt sur erreur", "erreur", err)
		os.Exit(1)
	}
}

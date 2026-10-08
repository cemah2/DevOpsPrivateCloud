// Commande medidoc : service de gestion des documents patients de MédiSphère.
//
// Compilation d'un binaire statique (aucune dépendance à la libc) :
//
//	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=1.0.0" -o medidoc ./cmd/medidoc
//
// Arrêt propre : sur SIGTERM ou SIGINT, le serveur cesse d'accepter des
// connexions et laisse jusqu'à 20 secondes aux requêtes en cours pour finir.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"git01.par1.medisphere.internal/medidoc/medidoc/internal/config"
	"git01.par1.medisphere.internal/medidoc/medidoc/internal/serveur"
	"git01.par1.medisphere.internal/medidoc/medidoc/internal/stockage"
)

// version est fixée à la compilation (-ldflags "-X main.version=…").
// MEDIDOC_VERSION, si elle est définie, l'emporte.
var version = "dev"

func main() {
	if err := lancer(); err != nil {
		slog.New(slog.NewJSONHandler(os.Stdout, nil)).Error("arrêt sur erreur", "erreur", err.Error())
		os.Exit(1)
	}
}

func lancer() error {
	cfg, err := config.Charger(os.Getenv)
	if err != nil {
		return fmt.Errorf("configuration : %w", err)
	}
	if cfg.Version == "" {
		cfg.Version = version
	}
	journal := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(journal)

	ctx, arreter := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer arreter()

	client, err := stockage.NouveauClient(ctx, stockage.ParamsClient{
		Endpoint: cfg.Endpoint, Region: cfg.Region, CAFile: cfg.CAFile,
	})
	if err != nil {
		return err
	}
	srv := serveur.Nouveau(stockage.NouveauDepot(client, cfg.Bucket), cfg.MaxOctets, cfg.Version, journal)

	httpSrv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       5 * time.Minute, // téléversements lents
		WriteTimeout:      5 * time.Minute,
		IdleTimeout:       2 * time.Minute,
	}
	erreurs := make(chan error, 1)
	go func() {
		journal.Info("démarrage", "version", cfg.Version, "port", cfg.Port,
			"s3_endpoint", cfg.Endpoint, "bucket", cfg.Bucket, "max_octets", cfg.MaxOctets)
		erreurs <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-erreurs:
		return err
	case <-ctx.Done():
	}
	journal.Info("signal reçu, arrêt en cours")
	arreter() // un second signal tue le processus immédiatement
	delai, annuler := context.WithTimeout(context.Background(), 20*time.Second)
	defer annuler()
	if err := httpSrv.Shutdown(delai); err != nil {
		return fmt.Errorf("arrêt : %w", err)
	}
	if err := <-erreurs; err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	journal.Info("arrêt terminé")
	return nil
}

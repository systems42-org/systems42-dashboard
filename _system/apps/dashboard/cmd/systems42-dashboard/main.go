// Command systems42-dashboard serves a Systems42 requirements wiki as a
// read-only web dashboard (FR-055, DR-007).
//
//	systems42-dashboard [WIKI]
//	systems42-dashboard --version
package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) == 1 && args[0] == "--version" {
		fmt.Println(dashboard.Version())
		return 0
	}
	if len(args) > 1 || (len(args) == 1 && (args[0] == "-h" || args[0] == "--help")) {
		fmt.Fprintln(os.Stderr, "Usage: systems42-dashboard [WIKI] | --version")
		return 1
	}

	var repoArg string
	if len(args) == 1 {
		repoArg = args[0]
	}
	paths, err := wiki.ResolvePaths(repoArg, os.Getenv)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Cannot resolve wiki path: %v\n", err)
		return 1
	}

	// CON-005 preflight: verify Systems42 layout on normal invocations (CLI
	// argument, or default/REPO_DIR run). Skip only when a caller overrides
	// WIKI_DIR directly without naming a CLI repo argument (fixture tests).
	if repoArg != "" || strings.TrimSpace(os.Getenv("WIKI_DIR")) == "" {
		if missing := wiki.Missing(paths.RepoDir); len(missing) > 0 {
			fmt.Fprintln(os.Stderr, wiki.PreflightMessage(paths.RepoDir, missing))
			return 1
		}
	}

	host := strings.TrimSpace(os.Getenv("DASH_HOST"))
	if host == "" {
		host = "0.0.0.0"
	}
	port := strings.TrimSpace(os.Getenv("DASH_PORT"))
	if port == "" {
		port = "8080"
	}
	addr := net.JoinHostPort(host, port)

	logger := log.New(os.Stderr, "", log.LstdFlags)
	shutdownCh := make(chan string, 1)
	srv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     dashboard.Version(),
		DisplayTZ:   os.Getenv("TZ"),
		PublicURL:   os.Getenv("DASH_PUBLIC_URL"),
		Logger:      logger,
		OnShutdown: func(reason string) {
			select {
			case shutdownCh <- reason:
			default:
			}
		},
	})

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Cannot listen on %s: %v\n", addr, err)
		return 1
	}

	httpServer := &http.Server{
		Handler:           srv,
		ReadHeaderTimeout: 10 * time.Second,
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	errCh := make(chan error, 1)
	go func() {
		logger.Printf("systems42-dashboard %s listening on http://%s (wiki: %s)", dashboard.Version(), ln.Addr().String(), paths.RepoDir)
		errCh <- httpServer.Serve(ln)
	}()

	select {
	case sig := <-sigCh:
		logger.Printf("received %s, shutting down", sig)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(ctx)
		return 0
	case reason := <-shutdownCh:
		logger.Printf("dashboard shutdown: %s", reason)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(ctx)
		return 0
	case err := <-errCh:
		if err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
			return 1
		}
		return 0
	}
}

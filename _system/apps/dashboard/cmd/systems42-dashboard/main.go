// Command systems42-dashboard serves a Systems42 requirements wiki as a
// read-only web dashboard (FR-055, DR-007).
//
//	systems42-dashboard [flags] [WIKI]
//	systems42-dashboard --version
//	systems42-dashboard --check [WIKI]
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/session"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func graceEnv(name string, def time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return def
	}
	sec, err := strconv.ParseFloat(raw, 64)
	if err != nil || sec <= 0 {
		return def
	}
	return time.Duration(sec * float64(time.Second))
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	return runWithIO(args, os.Stdout, os.Stderr)
}

func runWithIO(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("systems42-dashboard", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	var (
		showVersion bool
		checkOnly   bool
		hostFlag    string
		portFlag    string
		readyJSON   bool
		openFlag    bool
	)
	fs.BoolVar(&showVersion, "version", false, "print dashboard version and exit")
	fs.BoolVar(&checkOnly, "check", false, "run CON-005 preflight and print JSON result")
	fs.StringVar(&hostFlag, "host", "", "bind address (overrides DASH_HOST, default 0.0.0.0)")
	fs.StringVar(&portFlag, "port", "", "TCP port (overrides DASH_PORT, default 8080; 0 picks a free port)")
	fs.BoolVar(&readyJSON, "ready-json", false, "print one READY JSON line to stdout once listening")
	fs.BoolVar(&openFlag, "open", false, "open the dashboard URL in the default browser")

	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(stderr, "Usage: systems42-dashboard [--host ADDR] [--port PORT] [--open] [--ready-json] [WIKI] | --check [WIKI] | --version")
		return 1
	}

	if showVersion {
		if fs.NArg() != 0 {
			fmt.Fprintln(stderr, "Usage: systems42-dashboard --version")
			return 1
		}
		fmt.Fprintln(stdout, dashboard.Version())
		return 0
	}

	if fs.NArg() > 1 {
		fmt.Fprintln(stderr, "Usage: systems42-dashboard [--host ADDR] [--port PORT] [--open] [--ready-json] [WIKI] | --check [WIKI] | --version")
		return 1
	}

	var repoArg string
	if fs.NArg() == 1 {
		repoArg = fs.Arg(0)
	}
	paths, err := wiki.ResolvePaths(repoArg, os.Getenv)
	if err != nil {
		if checkOnly {
			_ = json.NewEncoder(stdout).Encode(map[string]any{
				"ok":      false,
				"message": fmt.Sprintf("Cannot resolve wiki path: %v", err),
			})
			return 1
		}
		fmt.Fprintf(stderr, "Cannot resolve wiki path: %v\n", err)
		return 1
	}

	if checkOnly {
		missing := wiki.Missing(paths.RepoDir)
		if len(missing) > 0 {
			_ = json.NewEncoder(stdout).Encode(map[string]any{
				"ok":       false,
				"repo_dir": paths.RepoDir,
				"missing":  missing,
				"message":  wiki.PreflightMessage(paths.RepoDir, missing),
			})
			return 1
		}
		cfg := wiki.LoadConfig(paths, nil)
		_ = json.NewEncoder(stdout).Encode(map[string]any{
			"ok":                true,
			"repo_dir":          paths.RepoDir,
			"system_name":       cfg.SystemName,
			"dashboard_version": cfg.DashboardVersion,
			"own_version":       dashboard.Version(),
		})
		return 0
	}

	// CON-005 preflight: verify Systems42 layout on normal invocations (CLI
	// argument, or default/REPO_DIR run). Skip only when a caller overrides
	// WIKI_DIR directly without naming a CLI repo argument (fixture tests).
	if repoArg != "" || strings.TrimSpace(os.Getenv("WIKI_DIR")) == "" {
		if missing := wiki.Missing(paths.RepoDir); len(missing) > 0 {
			fmt.Fprintln(stderr, wiki.PreflightMessage(paths.RepoDir, missing))
			return 1
		}
	}

	host := strings.TrimSpace(hostFlag)
	if host == "" {
		host = strings.TrimSpace(os.Getenv("DASH_HOST"))
	}
	if host == "" {
		host = "0.0.0.0"
	}
	port := strings.TrimSpace(portFlag)
	if port == "" {
		port = strings.TrimSpace(os.Getenv("DASH_PORT"))
	}
	if port == "" {
		port = "8080"
	}
	addr := net.JoinHostPort(host, port)

	logger := log.New(stderr, "", log.LstdFlags)
	shutdownCh := make(chan string, 1)
	triggerShutdown := func(reason string) {
		select {
		case shutdownCh <- reason:
		default:
		}
	}
	srv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		HelpMD:      dashboard.HelpMD(),
		Version:     dashboard.Version(),
		DisplayTZ:   os.Getenv("TZ"),
		PublicURL:   os.Getenv("DASH_PUBLIC_URL"),
		Logger:      logger,
		SessionOptions: session.Options{
			StartupGrace:   graceEnv("DASH_STARTUP_GRACE", 90*time.Second),
			HeartbeatGrace: graceEnv("DASH_HEARTBEAT_GRACE", 90*time.Second),
			LeaveGrace:     graceEnv("DASH_LEAVE_GRACE", 5*time.Second),
			PresenceWindow: graceEnv("DASH_PRESENCE_WINDOW", 30*time.Second),
		},
		OnShutdown: triggerShutdown,
	})

	watchCtx, watchCancel := context.WithCancel(context.Background())
	defer watchCancel()
	// DASH_NO_SHUTDOWN, set to anything, switches the automatic stop off
	// (FR-050). app.py reads the same variable in start_lifecycle.
	if strings.TrimSpace(os.Getenv("DASH_NO_SHUTDOWN")) == "" {
		srv.Session.StartWatchdog(watchCtx, time.Second, triggerShutdown)
	}

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(stderr, "Cannot listen on %s: %v\n", addr, err)
		return 1
	}

	boundPort := ln.Addr().(*net.TCPAddr).Port
	localHost := host
	if localHost == "0.0.0.0" || localHost == "::" || localHost == "" {
		localHost = "127.0.0.1"
	}
	localURL := fmt.Sprintf("http://%s", net.JoinHostPort(localHost, strconv.Itoa(boundPort)))
	publicURL := strings.TrimRight(strings.TrimSpace(os.Getenv("DASH_PUBLIC_URL")), "/")
	if publicURL == "" {
		if ip := web.LANIP(); ip != "" {
			publicURL = fmt.Sprintf("http://%s", net.JoinHostPort(ip, strconv.Itoa(boundPort)))
		} else {
			publicURL = localURL
		}
	}

	if readyJSON {
		cfg := wiki.LoadConfig(paths, nil)
		payload, _ := json.Marshal(map[string]any{
			"url":               localURL,
			"public_url":        publicURL,
			"port":              boundPort,
			"repo_dir":          paths.RepoDir,
			"system_name":       cfg.SystemName,
			"dashboard_version": cfg.DashboardVersion,
			"own_version":       dashboard.Version(),
		})
		fmt.Fprintf(stdout, "READY %s\n", payload)
	}

	httpServer := &http.Server{
		Handler:           srv,
		ReadHeaderTimeout: 10 * time.Second,
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	errCh := make(chan error, 1)
	go func() {
		logger.Printf("systems42-dashboard %s listening on %s (wiki: %s)", dashboard.Version(), localURL, paths.RepoDir)
		errCh <- httpServer.Serve(ln)
	}()

	if openFlag {
		openBrowser(localURL)
	}

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
			fmt.Fprintf(stderr, "Server error: %v\n", err)
			return 1
		}
		return 0
	}
}

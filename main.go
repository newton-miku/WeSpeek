package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/newton-miku/WeSpeek/internal/api"
	"github.com/newton-miku/WeSpeek/internal/server"
	"github.com/newton-miku/WeSpeek/internal/store/local"
	"github.com/newton-miku/WeSpeek/internal/store/sqlite"
	"github.com/newton-miku/WeSpeek/internal/util"
)

func main() {
	genAdmin := flag.Bool("gen-admin", false, "Generate a random admin key and setup link")
	dbPath := flag.String("db", "wespeek.db", "Path to SQLite database file")
	flag.Parse()

	st, err := sqlite.New(*dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer st.Close()

	// Initialize FileStore (currently local)
	// Can be extended to support S3/MinIO based on config
	// Store in data/uploads instead of web/uploads for better Docker compatibility
	uploadDir := util.EnvOr("WSPEEK_UPLOAD_DIR", "data/uploads")
	fileStore := local.NewFileStore(uploadDir+"/img", "/uploads/img")

	srv := server.New(st, fileStore, true, true)

	// Configure server behavior from environment
	if val := os.Getenv("WSPEEK_STORE_IMAGES"); val != "" {
		srv.StoreImagesAsFiles = val == "true"
	} else {
		srv.StoreImagesAsFiles = true // Default to true
	}

	if val := os.Getenv("WSPEEK_ALLOW_UPLOAD"); val != "" {
		srv.AllowUploads = val == "true"
	} else {
		srv.AllowUploads = true // Default to true
	}

	if err := srv.Init(); err != nil {
		log.Fatal(err)
	}
	srv.InitAdmin(*genAdmin)

	apiHandler := api.New(srv)

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", apiHandler.WSHandler)
	mux.HandleFunc("/ws/audio", apiHandler.AudioWSHandler)
	mux.HandleFunc("/api/rooms", apiHandler.RoomsHandler)
	mux.HandleFunc("/api/rooms/", apiHandler.RoomMembersHandler)
	mux.HandleFunc("/api/chat/public", apiHandler.PublicChatHandler)
	mux.HandleFunc("/api/chat/room/", apiHandler.RoomChatHandler)
	mux.HandleFunc("/api/upload", apiHandler.UploadHandler)
	mux.HandleFunc("/api/admin/challenge", apiHandler.AdminChallengeHandler)
	mux.HandleFunc("/api/admin/move_user", apiHandler.AdminMoveUserHandler)
	mux.HandleFunc("/api/admin/setup", apiHandler.AdminSetupHandler)
	mux.HandleFunc("/api/groups", apiHandler.GroupsHandler)
	mux.HandleFunc("/api/groups/", apiHandler.GroupsHandler)

	// Serve uploaded files
	// Note: We strip prefix "/uploads/" and serve from the upload directory's parent (since we used uploadDir/img)
	// Wait, local.NewFileStore("data/uploads/img", "/uploads/img") means files are at data/uploads/img/xxx.jpg
	// and URL is /uploads/img/xxx.jpg
	// So http.StripPrefix("/uploads/", http.FileServer(http.Dir("data/uploads"))) works because:
	// Request: /uploads/img/xxx.jpg -> Strip -> img/xxx.jpg -> Serve from data/uploads -> data/uploads/img/xxx.jpg. Correct.

	// With dynamic uploadDir:
	// If uploadDir="data/uploads", then NewFileStore uses "data/uploads/img".
	// We should serve "data/uploads" at "/uploads/".
	mux.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir(uploadDir))))

	mux.Handle("/", http.FileServer(http.Dir("web")))

	addr := util.EnvOr("WSPEEK_ADDR", ":7000")
	s := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Println("listening on", addr)
	if err := s.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"github.com/newton-miku/WeSpeek/internal/api"
	"github.com/newton-miku/WeSpeek/internal/server"
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

	srv := server.New(st)
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
	mux.HandleFunc("/api/admin/challenge", apiHandler.AdminChallengeHandler)
	mux.HandleFunc("/api/admin/move_user", apiHandler.AdminMoveUserHandler)
	mux.HandleFunc("/api/admin/setup", apiHandler.AdminSetupHandler)
	mux.HandleFunc("/api/groups", apiHandler.GroupsHandler)
	mux.HandleFunc("/api/groups/", apiHandler.GroupsHandler)
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

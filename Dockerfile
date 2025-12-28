# Build stage
FROM golang:alpine AS builder

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
# modernc.org/sqlite is pure Go, so CGO_ENABLED=0 works and produces a static binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o wespeek main.go

# Final stage
FROM alpine:latest

WORKDIR /app
# Copy binary from builder
COPY --from=builder /app/wespeek .

# Copy static files
COPY web ./web

# Create a directory for the database
RUN mkdir -p /data

# Expose the default port
EXPOSE 7000

# Set environment variable for the port
ENV WSPEEK_ADDR=:7000

# Run the application
# We use /data/wespeek.db for database persistence
ENTRYPOINT ["./wespeek", "-db", "/data/wespeek.db"]

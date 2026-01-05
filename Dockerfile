# Build stage
FROM golang:alpine AS builder

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
# Only copy necessary Go source files to avoid cache invalidation when other files (like web assets) change
COPY internal/ internal/
COPY main.go .

# Build the application
# modernc.org/sqlite is pure Go, so CGO_ENABLED=0 works and produces a static binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o wespeek main.go

# Final stage
FROM alpine:latest

WORKDIR /app

# Create a non-root user for security
RUN adduser -D -g '' wespeek

# Copy binary from builder
COPY --from=builder /app/wespeek .

# Copy static files
COPY web ./web

# Create a directory for the database and set permissions
RUN mkdir -p /data && \
    chown -R wespeek:wespeek /app /data

# Switch to non-root user
USER wespeek

# Expose the default port
EXPOSE 7000

# Set environment variables
ENV WSPEEK_ADDR=:7000 \
    WSPEEK_STORE_IMAGES=true \
    WSPEEK_ALLOW_UPLOAD=true \
    WSPEEK_UPLOAD_DIR=/data/uploads \
    TZ=Asia/Shanghai

# Run the application
# We use /data/wespeek.db for database persistence
ENTRYPOINT ["./wespeek", "-db", "/data/wespeek.db"]

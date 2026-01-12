# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /app
# Copy pubspec and local packages first to cache dependencies
COPY flutter_client/pubspec.* ./
COPY flutter_client/packages/ ./packages/

RUN flutter pub get

# Copy the rest of the application
COPY flutter_client/ .

RUN flutter build web --release --base-href /

# Stage 2: Build Go Server
FROM golang:alpine AS go-builder

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Set Go module download proxy
ENV GOPROXY="https://goproxy.io,direct"

# Download dependencies
RUN go mod download

# Copy source code
COPY internal/ internal/
COPY main.go .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o wespeek main.go

# Stage 3: Final Image
FROM alpine:latest

WORKDIR /app

# Copy binary from go-builder
COPY --from=go-builder /app/wespeek .

# Copy flutter web build from flutter-builder
COPY --from=flutter-builder /app/build/web ./web

# Create a directory for the database and set permissions
RUN mkdir -p /data

# Expose the default port
EXPOSE 7000

# Set environment variables
ENV WSPEEK_ADDR=:7000 \
    WSPEEK_STORE_IMAGES=true \
    WSPEEK_ALLOW_UPLOAD=true \
    WSPEEK_UPLOAD_DIR=/data/uploads \
    TZ=Asia/Shanghai

# Run the application
ENTRYPOINT ["./wespeek", "-db", "/data/wespeek.db"]

# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git for go mod download
RUN apk add --no-cache git ca-certificates tzdata

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o /app/scraper ./cmd/scraper

# Runtime stage
FROM alpine:3.19

WORKDIR /app

# Install ca-certificates and timezone data
RUN apk add --no-cache ca-certificates tzdata

# Copy binary from builder
COPY --from=builder /app/scraper /app/scraper

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Create non-root user
RUN adduser -D -u 1000 appuser
USER appuser

ENTRYPOINT ["/app/entrypoint.sh"]

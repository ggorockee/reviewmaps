.PHONY: build run test clean swagger dev

# Build the application
build:
	go build -o bin/api cmd/api/main.go

# Run the application
run:
	go run cmd/api/main.go

# Run in development mode with hot reload (requires air)
dev:
	air

# Run tests
test:
	go test -v ./...

# Run tests with coverage
test-cover:
	go test -v -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

# Generate swagger documentation
swagger:
	swag init -g cmd/api/main.go -o docs

# Clean build artifacts
clean:
	rm -rf bin/
	rm -f coverage.out coverage.html

# Install dependencies
deps:
	go mod download
	go mod tidy

# Format code
fmt:
	go fmt ./...

# Lint code (requires golangci-lint)
lint:
	golangci-lint run

# Run database migrations (development)
migrate:
	go run cmd/api/main.go -migrate

# Build docker image
docker-build:
	docker build -t reviewmaps-api .

# Run with docker compose
docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

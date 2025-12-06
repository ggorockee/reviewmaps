#!/bin/sh
set -e

# go-scraper entrypoint
# Usage: entrypoint.sh <command> [args...]
# Commands:
#   reviewnote [--keyword <keyword>]  - Run reviewnote scraper
#   inflexer --keyword <keyword>      - Run inflexer scraper (keyword required)
#   cleanup                           - Clean up expired campaigns
#   help                              - Show this help message

COMMAND=${1:-help}

case "$COMMAND" in
    reviewnote)
        shift
        echo "[$(date -Iseconds)] Starting reviewnote scraper..."
        exec /app/scraper reviewnote "$@"
        ;;
    inflexer)
        shift
        echo "[$(date -Iseconds)] Starting inflexer scraper..."
        exec /app/scraper inflexer "$@"
        ;;
    cleanup)
        shift
        echo "[$(date -Iseconds)] Starting cleanup..."
        exec /app/scraper cleanup "$@"
        ;;
    help|--help|-h)
        echo "go-scraper - Campaign data scraper"
        echo ""
        echo "Usage: entrypoint.sh <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  reviewnote [--keyword <keyword>]  Run reviewnote scraper"
        echo "  inflexer --keyword <keyword>      Run inflexer scraper (keyword required)"
        echo "  cleanup                           Clean up expired campaigns"
        echo "  help                              Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  POSTGRES_HOST      Database host (required)"
        echo "  POSTGRES_PORT      Database port (default: 5432)"
        echo "  POSTGRES_USER      Database user (required)"
        echo "  POSTGRES_PASSWORD  Database password (required)"
        echo "  POSTGRES_DB        Database name (required)"
        echo "  NAVER_API_KEYS     Naver API keys for enrichment (required)"
        exit 0
        ;;
    *)
        echo "[$(date -Iseconds)] Running command: $@"
        exec /app/scraper "$@"
        ;;
esac

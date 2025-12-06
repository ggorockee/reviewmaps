#!/bin/sh
set -e

# go-scraper entrypoint
# Usage: entrypoint.sh <command> [args...]
# Commands:
#   reviewnote [--keyword <keyword>]  - Run reviewnote scraper
#   inflexer [--keyword <keyword>]    - Run inflexer scraper (keyword required)
#   cleanup                           - Clean up expired campaigns
#   help                              - Show this help message
#
# Environment variables:
#   SCRAPE_KEYWORDS  Comma-separated keywords (used if --keyword not provided)

COMMAND=${1:-help}

# Function to run scraper with keywords from env if not provided in args
run_with_keywords() {
    SCRAPER_NAME=$1
    shift
    EXTRA_ARGS="$@"

    # Check if --keyword is already provided in args
    if echo "$EXTRA_ARGS" | grep -q "\-\-keyword"; then
        exec /app/scraper "$SCRAPER_NAME" $EXTRA_ARGS
    elif [ -n "$SCRAPE_KEYWORDS" ]; then
        # Use keywords from environment variable (comma-separated)
        # Run for each keyword sequentially
        echo "[$(date -Iseconds)] Keywords from env: $SCRAPE_KEYWORDS"

        # Save original IFS and split by comma
        OLD_IFS="$IFS"
        IFS=','
        set -- $SCRAPE_KEYWORDS
        IFS="$OLD_IFS"

        for keyword in "$@"; do
            # Trim whitespace
            keyword=$(echo "$keyword" | xargs)
            if [ -n "$keyword" ]; then
                echo "[$(date -Iseconds)] Running $SCRAPER_NAME with keyword: $keyword"
                /app/scraper "$SCRAPER_NAME" --keyword "$keyword" $EXTRA_ARGS
            fi
        done
    else
        # No keywords - run without
        exec /app/scraper "$SCRAPER_NAME" $EXTRA_ARGS
    fi
}

case "$COMMAND" in
    reviewnote)
        shift
        echo "[$(date -Iseconds)] Starting reviewnote scraper..."
        run_with_keywords reviewnote "$@"
        ;;
    inflexer)
        shift
        echo "[$(date -Iseconds)] Starting inflexer scraper..."
        run_with_keywords inflexer "$@"
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
        echo "  inflexer [--keyword <keyword>]    Run inflexer scraper (keyword required)"
        echo "  cleanup                           Clean up expired campaigns"
        echo "  help                              Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  SCRAPE_KEYWORDS    Comma-separated keywords (used if --keyword not provided)"
        echo "  POSTGRES_HOST      Database host (required)"
        echo "  POSTGRES_PORT      Database port (default: 5432)"
        echo "  POSTGRES_USER      Database user (required)"
        echo "  POSTGRES_PASSWORD  Database password (required)"
        echo "  POSTGRES_DB        Database name (required)"
        exit 0
        ;;
    *)
        echo "[$(date -Iseconds)] Running command: $@"
        exec /app/scraper "$@"
        ;;
esac

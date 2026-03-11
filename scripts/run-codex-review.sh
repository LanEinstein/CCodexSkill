#!/bin/bash
#
# run-codex-review.sh — Codex CLI wrapper for code review
#
# Usage:
#   bash run-codex-review.sh review --project-dir DIR --output FILE --prompt "..."
#   bash run-codex-review.sh exec   --project-dir DIR --output FILE --prompt "..."
#
# review mode: codex review --uncommitted -o $OUTPUT "$PROMPT"
# exec   mode: codex exec -C $DIR -o $OUTPUT --ephemeral --full-auto -s read-only "$PROMPT"
#
# Timeout: 300 seconds (override with --timeout N)
# Exit codes: 0=success, 1=failure, 124=timeout

set -euo pipefail

# --- Defaults ---
MODE=""
PROJECT_DIR="."
OUTPUT_FILE=""
PROMPT=""
TIMEOUT=300

# --- Parse arguments ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <review|exec> --project-dir DIR --output FILE --prompt \"...\" [--timeout N]" >&2
    exit 1
fi

MODE="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# --- Validate ---
if [[ -z "$OUTPUT_FILE" ]]; then
    echo "Error: --output is required" >&2
    exit 1
fi

if [[ -z "$PROMPT" ]]; then
    echo "Error: --prompt is required" >&2
    exit 1
fi

# Validate project directory exists
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: --project-dir '$PROJECT_DIR' does not exist" >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Check codex is available
CODEX_BIN=$(command -v codex 2>/dev/null) || {
    echo "Error: codex CLI not found in PATH. Install with: npm i -g @openai/codex" >&2
    exit 1
}

echo "Using codex: $CODEX_BIN" >&2
echo "Mode: $MODE | Timeout: ${TIMEOUT}s | Output: $OUTPUT_FILE" >&2

# --- Execute ---
EXIT_CODE=0

case "$MODE" in
    review)
        echo "Running: codex review --uncommitted ..." >&2
        (cd "$PROJECT_DIR" && timeout "$TIMEOUT" "$CODEX_BIN" review --uncommitted \
            -o "$OUTPUT_FILE" \
            "$PROMPT") \
            2>&1 || EXIT_CODE=$?
        ;;
    exec)
        echo "Running: codex exec (read-only) ..." >&2
        timeout "$TIMEOUT" "$CODEX_BIN" exec \
            -C "$PROJECT_DIR" \
            -o "$OUTPUT_FILE" \
            --ephemeral \
            --full-auto \
            -s read-only \
            "$PROMPT" \
            2>&1 || EXIT_CODE=$?
        ;;
    *)
        echo "Error: Unknown mode '$MODE'. Use 'review' or 'exec'." >&2
        exit 1
        ;;
esac

# --- Check results ---
if [[ $EXIT_CODE -eq 124 ]]; then
    echo "Error: Codex timed out after ${TIMEOUT}s" >&2
    exit 124
fi

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "Error: Codex exited with code $EXIT_CODE" >&2
    exit "$EXIT_CODE"
fi

if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "Warning: Output file is empty: $OUTPUT_FILE" >&2
    exit 1
fi

echo "Success: Review output written to $OUTPUT_FILE" >&2
exit 0

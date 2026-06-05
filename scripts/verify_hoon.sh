#!/bin/bash

# Yamoon Hoon Verification Script
# Usage: ./scripts/verify_hoon.sh <file.hyml> <pier_path>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <file.hyml> <pier_path>"
    exit 1
fi

HYML_FILE=$1
PIER_PATH=$2
FILENAME=$(basename "$HYML_FILE" .hyml)

echo "--- Yamoon Verification Pipeline ---"

# 1. Compile and Sync
bun run yamoon sync "$HYML_FILE" "$PIER_PATH"

if [ $? -ne 0 ]; then
    echo "Sync failed, aborting."
    exit 1
fi

# 2. Trigger Urbit test (Assuming urbit is in PATH)
if command -v urbit &> /dev/null; then
    echo "Urbit found, attempting to run tests..."
    # This is a bit tricky as Urbit is an interactive shell.
    # Usually you'd use a hood command or a script.
    # For now we'll just show the command.
    echo -e "\nRun the following in your Urbit dojo:"
    echo "  -test /=base=/tests/lib/$FILENAME"
else
    echo -e "\nUrbit binary not found in PATH."
    echo "Manually run the test in your pier:"
    echo "  -test /=base=/tests/lib/$FILENAME"
fi

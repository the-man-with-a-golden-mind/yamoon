#!/bin/bash
set -e
EXAMPLES=$(ls examples/*.hyml)
for f in $EXAMPLES; do
  if [[ "$f" == *"error.hyml"* ]] || [[ "$f" == *"syntax_error.hyml"* ]]; then
    echo "Testing $f (expecting failure)..."
    ./wrapper/cli.js compile "$f" &> /dev/null && (echo "Error: $f should have failed"; exit 1) || echo "✓ Correctly failed."
    continue
  fi
  echo "Testing $f..."
  ./wrapper/cli.js compile "$f" > /dev/null
done
echo "All examples verified successfully!"

#!/bin/bash
set -e

# Run standard integration tests
EXAMPLES=$(ls examples/*.hyml)
for f in $EXAMPLES; do
  if [[ "$f" == *"error.hyml"* ]] || [[ "$f" == *"syntax_error.hyml"* ]] || [[ "$f" == *"unknown_func.hyml"* ]]; then
    continue
  fi
  echo "Testing $f..."
  ./wrapper/cli.js compile "$f" > /dev/null
done

echo "--- Testing Diagnostic Accuracy ---"

echo "Testing examples/error.hyml (Type Mismatch)"
OUTPUT=$(./wrapper/cli.js compile examples/error.hyml 2>&1 || true)
if echo "$OUTPUT" | grep -q "In functions.fail.return at line 1, col 1: Type mismatch: expected text, got number"; then
  echo "✓ Caught exact Type Mismatch error."
else
  echo "✗ Failed to catch Type Mismatch. Output was:"
  echo "$OUTPUT"
  exit 1
fi

echo "Testing examples/syntax_error.hyml (Syntax Error)"
OUTPUT=$(./wrapper/cli.js compile examples/syntax_error.hyml 2>&1 || true)
if echo "$OUTPUT" | grep -q "Syntax error at line 1, col 3"; then
  echo "✓ Caught exact Syntax Error at correct coordinate."
else
  echo "✗ Failed to catch Syntax Error. Output was:"
  echo "$OUTPUT"
  exit 1
fi

echo "Testing examples/unknown_func.hyml (Unknown Function)"
OUTPUT=$(./wrapper/cli.js compile examples/unknown_func.hyml 2>&1 || true)
if echo "$OUTPUT" | grep -q "In functions.fail.return at line 1, col 1: Unknown function: jj"; then
  echo "✓ Caught exact Unknown Function error."
else
  echo "✗ Failed to catch Unknown Function error. Output was:"
  echo "$OUTPUT"
  exit 1
fi

echo "All examples and diagnostics verified successfully!"

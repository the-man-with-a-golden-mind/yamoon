#!/bin/bash
set -e
EXAMPLES=$(ls examples/*.hyml)
for f in $EXAMPLES; do
  echo "Testing $f..."
  ./wrapper/cli.js compile "$f" > /dev/null
done
echo "All examples compiled successfully!"

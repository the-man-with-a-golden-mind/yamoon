#!/bin/bash
set -e

# 1. Clean up old zod if exists
rm -rf zod

echo "--- Booting Fake Ship (~zod) ---"
# Boot and immediately exit after filesystem is created
# We use -t to stay in terminal, then pipe exit command
echo "|exit" | urbit -F zod -c zod

echo "--- Syncing Yamoon Code ---"
# Sync examples and tests into the newly created zod filesystem
EXAMPLES=$(ls examples/*.hyml)
for f in $EXAMPLES; do
  NAME=$(basename "$f" .hyml)
  echo "Syncing $NAME..."
  # Use our sync command to put files in zod/base/lib and zod/base/tests
  ./wrapper/cli.js sync "$f" ./zod > /dev/null
done

echo "--- Running Native Urbit Tests ---"
# We run urbit again, mounting base and running -test
# The exit code of -test will indicate failure if any test fails.
# Note: -test /=base=/tests/lib will run all tests in that folder
cat <<EOF | urbit zod
|mount %base
+code %base
-test /=base=/tests/lib
|exit
EOF

echo "--- Final Verification Successful! ---"

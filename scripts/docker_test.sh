#!/bin/bash
set -e

echo "--- Building Docker Image ---"
docker build -f docker/Dockerfile -t yamoon-test .

echo "--- Running Containerized Tests ---"
docker run --rm yamoon-test

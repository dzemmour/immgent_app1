#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
docker compose build --no-cache
# docker build -t immgent-app1 .
docker run --rm -p 3838:3838 -v "$DIR/data:/srv/shiny-server/data" immgent-app1 &
sleep 2
open "http://localhost:3838/app/"
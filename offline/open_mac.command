#!/usr/bin/env bash
set -euo pipefail

# ---- config you can tweak ----
TAR="${1:-immgent_app1-app_latest.tar}"   # or pass a different tar as arg1
APP_NAME="immgent_app1"                   # container name
HOST_PORT="${PORT:-3838}"                 # change if 3838 is busy
OPEN_PATH="/"                             # use "/app/" only if your app lives in a subdir
# Optional resource knobs (comment out if not needed)
MEM="24g"
SHM="2g"
NOFILE="1048576"
# --------------------------------

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not running. Install/start Docker Desktop first."
  exit 1
fi

cd "$(cd "$(dirname "$0")" && pwd)"

echo "Loading image from: $TAR"

LOAD_OUT=""
if command -v pv >/dev/null 2>&1; then
  # Byte-accurate progress bar (pv prints to stderr; docker load output is captured)
  if [[ ! -f "$TAR" ]]; then
    echo "File not found: $TAR"
    exit 1
  fi
  LOAD_OUT="$(
    set -o pipefail
    pv -ptebr "$TAR" | docker load
  )" || { echo -e "\n docker load failed"; exit 1; }
  echo    # newline after pv's progress line
else
  # Fallback: spinner while docker loads; still capture stdout to parse image name
  tmp_out="$(mktemp)"
  # run docker load in background, capture exit after spinner
  ( docker load -i "$TAR" >"$tmp_out" ) &
  load_pid=$!

  # spinner
  spin='-\|/'
  i=0
  while kill -0 "$load_pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\rLoading (no 'pv' found)… %s" "${spin:$i:1}"
    sleep 0.1
  done
  printf "\r"  # clear spinner line

  # get exit code and output
  if ! wait "$load_pid"; then
    echo "docker load failed"
    rm -f "$tmp_out"
    exit 1
  fi
  LOAD_OUT="$(cat "$tmp_out")"
  rm -f "$tmp_out"
fi

echo "$LOAD_OUT"

# Parse the image name (e.g., 'dzemmour/immgent_app1:latest')
IMAGE="$(sed -n 's/^Loaded image: //p' <<<"$LOAD_OUT" | tail -n1)"
if [[ -z "$IMAGE" ]]; then
  # Fallback if the tar was saved from an image ID (no repo:tag)
  IMAGE="immgent_app1-app:latest"
  echo "Could not parse image name from tar. Falling back to: $IMAGE"
fi

# Stop any prior container using the same name
docker rm -f "$APP_NAME" >/dev/null 2>&1 || true

echo "Starting container '$APP_NAME' from image '$IMAGE' ..."
docker run -d --rm \
  --name "$APP_NAME" \
  --platform=linux/amd64 \
  -p "${HOST_PORT}:3838" \
  --memory="${MEM}" --shm-size="${SHM}" --ulimit nofile="${NOFILE}" \
  -e SHINY_LOG_STDOUT=1 -e SHINY_LOG_STDERR=1 \
  "$IMAGE" >/dev/null

# Wait for the server to be reachable
echo "Waiting for Shiny at http://localhost:${HOST_PORT}${OPEN_PATH} ..."
for i in {1..60}; do
  if curl -fsS "http://localhost:${HOST_PORT}${OPEN_PATH}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Open browser (macOS 'open', Linux 'xdg-open' if available)
URL="http://localhost:${HOST_PORT}${OPEN_PATH}"
if [[ "$OSTYPE" == "darwin"* ]]; then
  open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 || true
fi

echo "Streaming logs (Ctrl+C to stop viewing; container keeps running) ..."
docker logs -f "$APP_NAME"

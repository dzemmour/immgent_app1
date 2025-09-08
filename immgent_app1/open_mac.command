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

# ---- AUTO-DISCOVER THE TAR IF NEEDED ---------------------------------------
if [[ ! -f "$TAR" ]]; then
  echo "Looking for image archive next to this script..."
  candidates=()
  # Find common names first; only this directory, no recursion
  while IFS= read -r -d '' f; do candidates+=("$f"); done < <(
    find . -maxdepth 1 -type f \
      \( -name 'immgent*app*.tar'   -o -name 'immgent*app*.tar.gz' \
         -name 'immgent*.tar'       -o -name 'immgent*.tar.gz'     \
         -o -name '*.tar'           -o -name '*.tar.gz'            \
         -o -name '*.tgz' \) \
      -print0 2>/dev/null
  )

  if (( ${#candidates[@]} == 0 )); then
    echo "Could not find an image archive (.tar/.tar.gz) in: $(pwd)"
    echo "Put the archive next to this script or pass its path as the first argument."
    exit 1
  fi

  # Choose the newest by mtime
  IFS=$'\n' read -r -d '' -a sorted < <(ls -t "${candidates[@]}" 2>/dev/null && printf '\0')
  unset IFS
  TAR="${sorted[0]}"
  # Strip leading ./ for nicer echo
  TAR="${TAR#./}"
  echo "Auto-detected archive: $TAR"
fi

# ---------------------------------------------------------------------------

echo "Loading image from: $TAR"

LOAD_OUT=""
if command -v pv >/dev/null 2>&1; then
  # Byte-accurate progress bar (works for .tar and .tar.gz)
  LOAD_OUT="$(
    set -o pipefail
    pv -ptebr "$TAR" | docker load
  )" || { echo -e "\n docker load failed"; exit 1; }
  echo
else
  # Fallback spinner
  tmp_out="$(mktemp)"
  ( docker load -i "$TAR" >"$tmp_out" ) &
  load_pid=$!
  spin='-\|/'; i=0
  while kill -0 "$load_pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\rLoading (no 'pv' found)… %s" "${spin:$i:1}"
    sleep 0.1
  done
  printf "\r"
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
  IMAGE="immgent_app1-app:latest"   # fallback if tar was saved from an image ID
  echo "Could not parse image name from tar. Falling back to: $IMAGE"
fi

# Stop any prior container using the same name
docker rm -f "$APP_NAME" >/dev/null 2>&1 || true

echo "Starting container '$APP_NAME' from image '$IMAGE' ..."
docker run -d --rm \
  --name "$APP_NAME" \
  -p "${HOST_PORT}:3838" \
  --memory="${MEM}" --shm-size="${SHM}" --ulimit nofile="${NOFILE}" \
  -e SHINY_LOG_STDOUT=1 -e SHINY_LOG_STDERR=1 \
  "$IMAGE" >/dev/null
# (No --platform flag: running a *local* image doesn’t need it)

# Wait for the server
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

#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cpu-morse-poc:latest}"
SENDER_NAME="${SENDER_NAME:-cpu-morse-snd-poc}"
RECEIVER_NAME="${RECEIVER_NAME:-cpu-morse-rcv-poc}"
MESSAGE="${MESSAGE:-Grretings from planet Earth}"
SND_UNIT_S="${SND_UNIT_S:-0.2}"
RCV_INTERVAL_S="${RCV_INTERVAL_S:-0.05}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cpu-morse-docker.XXXXXX")"

cleanup_build_dir() {
  rm -rf "$BUILD_DIR"
}
trap cleanup_build_dir EXIT

need_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Brak wymaganego pliku: $file" >&2
    exit 1
  fi
}

stop_old_containers() {
  docker rm -f "$SENDER_NAME" "$RECEIVER_NAME" >/dev/null 2>&1 || true
}

stop_containers() {
  echo
  echo "Zatrzymuje kontenery..."
  stop_old_containers
}

need_file "$SCRIPT_DIR/snd_poc.sh"
need_file "$SCRIPT_DIR/rcv_poc.sh"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker nie jest dostepny w PATH." >&2
  exit 1
fi

cp "$SCRIPT_DIR/snd_poc.sh" "$BUILD_DIR/snd_poc.sh"
cp "$SCRIPT_DIR/rcv_poc.sh" "$BUILD_DIR/rcv_poc.sh"

cat >"$BUILD_DIR/Dockerfile" <<'EOF'
FROM debian:stable-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash coreutils gawk procps ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/cpu-morse
COPY snd_poc.sh rcv_poc.sh ./
RUN chmod +x snd_poc.sh rcv_poc.sh
EOF

echo "Buduje obraz: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" "$BUILD_DIR"

stop_old_containers
trap stop_containers INT TERM EXIT

echo "Uruchamiam odbiornik: $RECEIVER_NAME"
docker_cpu_args=()
if [[ -n "${CPUSET_CPUS:-}" ]]; then
  docker_cpu_args+=(--cpuset-cpus="$CPUSET_CPUS")
fi

docker run -d \
  --name "$RECEIVER_NAME" \
  "${docker_cpu_args[@]}" \
  -e RCV_INTERVAL_S="$RCV_INTERVAL_S" \
  "$IMAGE_NAME" \
  stdbuf -o0 -e0 bash -lc "./rcv_poc.sh" >/dev/null

echo "Uruchamiam nadajnik: $SENDER_NAME"
docker run -d \
  --name "$SENDER_NAME" \
  "${docker_cpu_args[@]}" \
  -e SND_UNIT_S="$SND_UNIT_S" \
  -e CPU_MORSE_MESSAGE="$MESSAGE" \
  "$IMAGE_NAME" \
  bash -lc 'while true; do printf "%s" "$CPU_MORSE_MESSAGE" | ./snd_poc.sh; sleep 2; done' >/dev/null

cat <<EOF

Nadajnik wysyla w petli:
  $MESSAGE

Odbiornik wypisuje odebrane teksty ponizej.
Zatrzymanie: Ctrl+C

EOF

docker attach --sig-proxy=false "$RECEIVER_NAME"

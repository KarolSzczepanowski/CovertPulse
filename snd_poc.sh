#!/usr/bin/env bash
# Autor: Karol Szczepanowski
# Strona: www.karolszczepanowski.pl
# GitHub: https://github.com/KarolSzczepanowski
set -euo pipefail

usage() {
  cat <<'EOF'
Uzycie:
  ./snd.sh [TEKST]

Opis:
  Zamienia podany tekst na alfabet Morse'a i nadaje go obciazeniem CPU.
  Sygnal to wysokie obciazenie, a przerwa to obciazenie tla.
  Bez argumentow czyta tekst ze standardowego wejscia. Jesli nie ma
  potoku, nadaje domyslny tekst SOS. Tryb bez argumentow nic nie
  wypisuje, zeby nadawal sie do potokow.

Autor:
  Karol Szczepanowski
  www.karolszczepanowski.pl
  https://github.com/KarolSzczepanowski

Zasady czasu:
  kropka                 1 jednostka
  kreska                 3 jednostki
  przerwa w znaku        1 jednostka
  przerwa miedzy znakami 3 jednostki
  przerwa miedzy slowami 7 jednostek

Zmienne do strojenia:
  SND_UNIT_S          dlugosc jednostki w sekundach, domyslnie 0.2
  SND_SIGNAL_LOAD     obciazenie sygnalu, domyslnie 99
  SND_BACKGROUND_LOAD obciazenie ciszy, domyslnie 0
  SND_PERIOD_US       okres pracy generatora w mikrosekundach, domyslnie 100000
  SND_DEFAULT_MESSAGE tekst domyslny bez argumentow i bez wejscia, domyslnie SOS

Przyklady:
  ./snd.sh SOS
  ./snd.sh "ALA MA KOTA"
  cat plik.txt | ./snd.sh
  SND_UNIT_S=0.1 ./snd.sh "CQ CQ"

Zatrzymanie:
  Ctrl+C
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

quiet_mode=0
if (($# == 0)); then
  quiet_mode=1
fi

if (($# > 0)); then
  message="$*"
elif [[ -t 0 ]]; then
  message="${SND_DEFAULT_MESSAGE:-SOS}"
else
  message="$(cat)"
  if [[ -z "${message//[[:space:]]/}" ]]; then
    message="${SND_DEFAULT_MESSAGE:-SOS}"
  fi
fi

unit_s="${SND_UNIT_S:-0.2}"
signal_load="${SND_SIGNAL_LOAD:-99}"
background_load="${SND_BACKGROUND_LOAD:-0}"
period_us="${SND_PERIOD_US:-100000}"
targets=()
durations_us=()
warnings=()

if [[ ! "$period_us" =~ ^[0-9]+$ ]] || (( period_us < 1000 )); then
  echo "Blad: SND_PERIOD_US musi byc liczba calkowita >= 1000." >&2
  usage >&2
  exit 2
fi

if [[ ! "$signal_load" =~ ^[0-9]+$ ]] || (( signal_load < 1 || signal_load > 100 )); then
  echo "Blad: SND_SIGNAL_LOAD musi byc liczba calkowita od 1 do 100." >&2
  usage >&2
  exit 2
fi

if [[ ! "$background_load" =~ ^[0-9]+$ ]] || (( background_load < 0 || background_load > 100 )); then
  echo "Blad: SND_BACKGROUND_LOAD musi byc liczba calkowita od 0 do 100." >&2
  usage >&2
  exit 2
fi

unit_us="$(awk -v value="$unit_s" 'BEGIN {
  if (value <= 0) exit 1
  printf "%.0f", value * 1000000
}')" || {
  echo "Blad: SND_UNIT_S musi byc liczba dodatnia, np. 0.2 albo 1." >&2
  usage >&2
  exit 2
}

if (( unit_us < 1000 )); then
  echo "Blad: SND_UNIT_S jest za male; minimalnie 0.001 s." >&2
  usage >&2
  exit 2
fi

declare -A morse=(
  [A]=".-"    [B]="-..."  [C]="-.-."  [D]="-.."   [E]="."
  [F]="..-."  [G]="--."   [H]="...."  [I]=".."    [J]=".---"
  [K]="-.-"   [L]=".-.."  [M]="--"    [N]="-."    [O]="---"
  [P]=".--."  [Q]="--.-"  [R]=".-."   [S]="..."   [T]="-"
  [U]="..-"   [V]="...-"  [W]=".--"   [X]="-..-"  [Y]="-.--"
  [Z]="--.."  [0]="-----" [1]=".----" [2]="..---" [3]="...--"
  [4]="....-" [5]="....." [6]="-...." [7]="--..." [8]="---.."
  [9]="----." [.]=".-.-.-" [,]="--..--" [?]="..--.." ["'"]=".----."
  [/]="-..-." [=]="-...-"  [+]=".-.-."  [-]="-....-" [@]=".--.-."
)

duration_for_units() {
  local units="$1"
  printf '%s' "$((unit_us * units))"
}

append_phase() {
  local load="$1"
  local duration_us="$2"
  local last_index

  (( duration_us <= 0 )) && return 0

  last_index=$((${#targets[@]} - 1))
  if (( last_index >= 0 )) && [[ "${targets[$last_index]}" == "$load" ]]; then
    durations_us[$last_index]=$((durations_us[$last_index] + duration_us))
  else
    targets+=("$load")
    durations_us+=("$duration_us")
  fi
}

upper_message="${message^^}"
previous_token=""
encoded=""

for ((idx = 0; idx < ${#upper_message}; idx++)); do
  char="${upper_message:idx:1}"

  if [[ "$char" =~ [[:space:]] ]]; then
    if [[ "$previous_token" == "letter" ]]; then
      append_phase "$background_load" "$(duration_for_units 7)"
      encoded+="/ "
      previous_token="word"
    fi
    continue
  fi

  code="${morse[$char]:-}"
  if [[ -z "$code" ]]; then
    warnings+=("$char")
    continue
  fi

  if [[ "$previous_token" == "letter" ]]; then
    append_phase "$background_load" "$(duration_for_units 3)"
    encoded+=" "
  fi

  for ((part = 0; part < ${#code}; part++)); do
    symbol="${code:part:1}"
    if [[ "$symbol" == "." ]]; then
      append_phase "$signal_load" "$(duration_for_units 1)"
    else
      append_phase "$signal_load" "$(duration_for_units 3)"
    fi

    if (( part + 1 < ${#code} )); then
      append_phase "$background_load" "$(duration_for_units 1)"
    fi
  done

  encoded+="$code"
  previous_token="letter"
done

if ((${#targets[@]} == 0)); then
  echo "Blad: tekst nie zawiera znakow obslugiwanych przez alfabet Morse'a." >&2
  exit 2
fi

cpu_count="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/snd.XXXXXX")"
duty_file="$tmp_dir/duty"
stop_file="$tmp_dir/stop"
pids=()

cleanup() {
  touch "$stop_file" 2>/dev/null || true
  if ((${#pids[@]} > 0)); then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

get_now_us() {
  local __var="$1"
  local now="${EPOCHREALTIME/./}"
  printf -v "$__var" '%s' "$now"
}

sleep_us() {
  local micros="$1"
  local seconds whole frac

  (( micros <= 0 )) && return 0
  whole=$((micros / 1000000))
  frac=$((micros % 1000000))
  printf -v seconds '%d.%06d' "$whole" "$frac"
  sleep "$seconds"
}

worker() {
  local duty period="$1"
  local busy_us idle_us start_us now_us deadline_us

  while [[ ! -e "$stop_file" ]]; do
    if ! read -r duty <"$duty_file"; then
      duty=0
    fi

    (( duty < 0 )) && duty=0
    (( duty > 1000 )) && duty=1000

    busy_us=$((period * duty / 1000))
    idle_us=$((period - busy_us))

    if (( busy_us > 0 )); then
      get_now_us start_us
      deadline_us=$((start_us + busy_us))
      while [[ ! -e "$stop_file" ]]; do
        get_now_us now_us
        (( now_us >= deadline_us )) && break
        :
      done
    fi

    sleep_us "$idle_us"
  done
}

printf '%s\n' "$((background_load * 10))" >"$duty_file"

for ((i = 0; i < cpu_count; i++)); do
  worker "$period_us" &
  pids+=("$!")
done

total_us=0
for duration_us in "${durations_us[@]}"; do
  total_us=$((total_us + duration_us))
done

if (( quiet_mode == 0 )); then
  echo "Tekst: $message"
  echo "Morse: $encoded"
  echo "Start: ${#targets[@]} impulsow/przerw, jednostka ${unit_s}s, sygnal ${signal_load}%, tlo ${background_load}%, rdzenie logiczne: ${cpu_count}."
fi
if (( quiet_mode == 0 && ${#warnings[@]} > 0 )); then
  printf 'Pominiete nieobslugiwane znaki:'
  printf ' %s' "${warnings[@]}"
  printf '\n'
fi

for ((phase = 0; phase < ${#targets[@]}; phase++)); do
  target="${targets[$phase]}"
  duration_us="${durations_us[$phase]}"
  duty=$((target * 10))
  printf '%s\n' "$duty" >"$duty_file"

  if (( target == signal_load )); then
    state="sygnal"
  else
    state="cisza"
  fi

  if (( quiet_mode == 0 )); then
    printf '%03d/%03d %6s %3d%% %d.%03ds\n' \
      "$((phase + 1))" "${#targets[@]}" "$state" "$target" \
      "$((duration_us / 1000000))" "$(((duration_us % 1000000) / 1000))"
  fi

  sleep_us "$duration_us"
done

printf '%s\n' "$((background_load * 10))" >"$duty_file"
if (( quiet_mode == 0 )); then
  printf 'Zakonczono nadawanie. Czas laczny: %d.%03ds\n' \
    "$((total_us / 1000000))" "$(((total_us % 1000000) / 1000))"
fi

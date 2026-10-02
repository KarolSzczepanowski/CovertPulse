#!/usr/bin/env bash
# Autor: Karol Szczepanowski
# Strona: www.karolszczepanowski.pl
# GitHub: https://github.com/KarolSzczepanowski
set -euo pipefail

usage() {
  cat <<'EOF'
Uzycie:
  ./rcv.sh [PROG] [JEDNOSTKA_S] [PLIK]

Opis:
  Mierzy obciazenie CPU, rozpoznaje sygnal powyzej zadanego progu
  i dekoduje alfabet Morse'a.
  Bez argumentow wypisuje tylko odebrane znaki, zeby dzialalo
  przekierowanie: ./rcv.sh >> plik.txt.

Autor:
  Karol Szczepanowski
  www.karolszczepanowski.pl
  https://github.com/KarolSzczepanowski

Argumenty:
  PROG         prog obciazenia CPU od kiedy probka jest sygnalem, domyslnie 50
  JEDNOSTKA_S  dlugosc jednostki Morse'a w sekundach, domyslnie 0.2
  PLIK         plik surowych pomiarow, domyslnie cpu_morse_rcv.log

Zmienne do strojenia:
  RCV_INTERVAL_S  odstep pomiaru w sekundach, domyslnie JEDNOSTKA_S/2

Przyklady:
  ./rcv.sh
  ./rcv.sh >> wynik.txt
  ./rcv.sh 50 0.2 odbior.log
  RCV_INTERVAL_S=0.05 ./rcv.sh 60 0.2

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

threshold="${1:-50}"
unit_s="${2:-0.2}"
output="${3:-cpu_morse_rcv.log}"

if [[ ! "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Blad: PROG musi byc liczba od 0 do 100." >&2
  usage >&2
  exit 2
fi

if ! awk -v value="$threshold" 'BEGIN { exit !(value >= 0 && value <= 100) }'; then
  echo "Blad: PROG musi byc w zakresie 0-100." >&2
  usage >&2
  exit 2
fi

if [[ ! "$unit_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Blad: JEDNOSTKA_S musi byc liczba dodatnia, np. 0.2." >&2
  usage >&2
  exit 2
fi

unit_us="$(awk -v value="$unit_s" 'BEGIN {
  if (value <= 0) exit 1
  printf "%.0f", value * 1000000
}')" || {
  echo "Blad: JEDNOSTKA_S musi byc wieksza od 0." >&2
  usage >&2
  exit 2
}

interval_s="${RCV_INTERVAL_S:-}"
if [[ -z "$interval_s" ]]; then
  interval_s="$(awk -v unit="$unit_s" 'BEGIN { printf "%.6f", unit / 2 }')"
fi

if [[ ! "$interval_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Blad: RCV_INTERVAL_S musi byc liczba dodatnia." >&2
  usage >&2
  exit 2
fi

sample_us="$(awk -v value="$interval_s" 'BEGIN {
  if (value <= 0) exit 1
  printf "%.0f", value * 1000000
}')" || {
  echo "Blad: RCV_INTERVAL_S musi byc wiekszy od 0." >&2
  usage >&2
  exit 2
}

if (( sample_us < 1000 )); then
  echo "Blad: RCV_INTERVAL_S jest za maly; minimalnie 0.001 s." >&2
  usage >&2
  exit 2
fi

declare -A decode=(
  [".-"]=A    ["-..."]=B  ["-.-."]=C  ["-.."]=D   ["."]=E
  ["..-."]=F  ["--."]=G   ["...."]=H  [".."]=I    [".---"]=J
  ["-.-"]=K   [".-.."]=L  ["--"]=M    ["-."]=N    ["---"]=O
  [".--."]=P  ["--.-"]=Q  [".-."]=R   ["..."]=S   ["-"]=T
  ["..-"]=U   ["...-"]=V  [".--"]=W   ["-..-"]=X  ["-.--"]=Y
  ["--.."]=Z  ["-----"]=0 [".----"]=1 ["..---"]=2 ["...--"]=3
  ["....-"]=4 ["....."]=5 ["-...."]=6 ["--..."]=7 ["---.."]=8
  ["----."]=9 [".-.-.-"]="." ["--..--"]="," ["..--.."]="?"
  [".----."]="'" ["-..-."]="/" ["-...-"]="=" [".-.-."]="+"
  ["-....-"]="-" [".--.-."]="@"
)

read_cpu_sample() {
  local label user nice system idle iowait irq softirq steal guest guest_nice

  read -r label user nice system idle iowait irq softirq steal guest guest_nice </proc/stat
  cpu_idle=$((idle + iowait))
  cpu_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

round_units() {
  local duration_us="$1"
  local units

  units=$(((duration_us + unit_us / 2) / unit_us))
  (( units < 1 )) && units=1
  printf '%s' "$units"
}

decode_current_letter() {
  [[ -z "$current_code" ]] && return 0

  local letter="${decode[$current_code]:-?}"
  decoded+="$letter"
  if (( quiet_mode == 1 )); then
    printf '%s' "$letter"
  else
    printf 'litera: %-6s -> %s | tekst: %s\n' "$current_code" "$letter" "$decoded"
  fi
  current_code=""
}

handle_run() {
  local state="$1"
  local duration_us="$2"
  local units

  units="$(round_units "$duration_us")"

  if [[ "$state" == "signal" ]]; then
    if (( units <= 2 )); then
      current_code+="."
      (( quiet_mode == 0 )) && printf 'sygnal: %d jednostek -> .\n' "$units"
    else
      current_code+="-"
      (( quiet_mode == 0 )) && printf 'sygnal: %d jednostek -> -\n' "$units"
    fi
    return 0
  fi

  (( quiet_mode == 0 )) && printf 'cisza:  %d jednostek\n' "$units"

  if (( units >= 7 )); then
    decode_current_letter
    if [[ -n "$decoded" && "${decoded: -1}" != " " ]]; then
      decoded+=" "
      if (( quiet_mode == 1 )); then
        printf ' '
      else
        printf 'przerwa slowa | tekst: %s\n' "$decoded"
      fi
    fi
  elif (( units >= 3 )); then
    decode_current_letter
  fi
}

finish() {
  if [[ -n "${last_state:-}" ]]; then
    now_us="$(date +%s%6N)"
    handle_run "$last_state" "$((now_us - run_start_us))"
  fi
  decode_current_letter
  if (( quiet_mode == 0 )); then
    printf '\nOdebrany tekst: %s\n' "${decoded% }"
  fi
}
trap finish EXIT
stop_requested=0
trap 'stop_requested=1' INT TERM

if [[ ! -f "$output" ]]; then
  printf 'czas obciazenie stan\n' >"$output"
fi

if (( quiet_mode == 0 )); then
  echo "Odbior Morse'a: prog ${threshold}%, jednostka ${unit_s}s, probkowanie co ${interval_s}s."
  echo "Surowe probki: ${output}. Zatrzymaj przez Ctrl+C, aby domknac dekodowanie."
fi

read_cpu_sample
prev_total="$cpu_total"
prev_idle="$cpu_idle"

last_state=""
run_start_us=""
current_code=""
decoded=""

while (( stop_requested == 0 )); do
  sleep "$interval_s" || true
  (( stop_requested != 0 )) && break
  read_cpu_sample

  delta_total=$((cpu_total - prev_total))
  delta_idle=$((cpu_idle - prev_idle))
  prev_total="$cpu_total"
  prev_idle="$cpu_idle"

  (( delta_total <= 0 )) && continue

  usage_x100=$((((delta_total - delta_idle) * 10000) / delta_total))
  usage_text="$(printf '%d.%02d' "$((usage_x100 / 100))" "$((usage_x100 % 100))")"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if awk -v usage="$usage_text" -v threshold="$threshold" 'BEGIN { exit !(usage >= threshold) }'; then
    state="signal"
    state_text="sygnal"
  else
    state="silence"
    state_text="cisza"
  fi

  printf '%s %s%% %s\n' "$timestamp" "$usage_text" "$state_text" >>"$output"

  now_us="$(date +%s%6N)"
  if [[ -z "$last_state" ]]; then
    last_state="$state"
    run_start_us="$now_us"
    continue
  fi

  if [[ "$state" != "$last_state" ]]; then
    handle_run "$last_state" "$((now_us - run_start_us))"
    last_state="$state"
    run_start_us="$now_us"
  fi
done

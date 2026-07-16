#!/usr/bin/env sh
# ##############################################################
# ##   VOID Ping Monitor — iSH / Alpine Linux Edition        ##
# ##   Works on iOS via iSH app                              ##
# ##   Author : @lfw.k4rma_                                  ##
# ##############################################################
# Deps: busybox ping (built-in), awk (built-in)
#
# INSTALL GLOBALLY (run from anywhere after):
#   sh ping_monitor.sh --install
#   ping_monitor          ← works from any directory
#
# QUICK START (no clone needed):
#   apk add wget
#   wget -O ~/ping_monitor.sh https://raw.githubusercontent.com/nilavog4-f/vd/main/ping_monitor.sh
#   sh ~/ping_monitor.sh --install

# ── Self-install ───────────────────────────────────────────────
if [ "$1" = "--install" ]; then
  DEST="/usr/local/bin/ping_monitor"
  cp "$0" "$DEST" && chmod +x "$DEST"
  if [ $? -eq 0 ]; then
    printf '\033[1;32m✔  Installed to %s\033[0m\n' "$DEST"
    printf '\033[2m   Run from anywhere with:  ping_monitor\033[0m\n\n'
  else
    printf '\033[1;31m✘  Permission denied — try:  sudo sh %s --install\033[0m\n' "$0"
  fi
  exit 0
fi

# ── Colours ───────────────────────────────────────────────────
R='\033[0;31m'   LR='\033[1;31m'
G='\033[0;32m'   LG='\033[1;32m'
Y='\033[0;33m'   LY='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'   LC='\033[1;36m'
W='\033[0;37m'   LW='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'
BLOOD='\033[38;5;160m'
CRIMSON='\033[38;5;196m'
ORANGE='\033[38;5;208m'
GRAY='\033[38;5;240m'
LGRAY='\033[38;5;246m'

# ── Helpers ───────────────────────────────────────────────────
COLS() { tput cols 2>/dev/null || echo 72; }

rule() {
  local char="${1:-─}" color="${2:-$GRAY}"
  local w; w=$(COLS)
  printf "${color}"; printf '%*s' "$w" '' | tr ' ' "$char"; printf "${RST}\n"
}

center() {
  local text="$1"
  local plain; plain=$(printf '%b' "$text" | sed 's/\x1B\[[0-9;:]*[mK]//g')
  local w pad; w=$(COLS); pad=$(( (w - ${#plain}) / 2 ))
  [ $pad -lt 0 ] && pad=0
  printf "%${pad}s" ""; printf '%b\n' "$text"
}

rtt_color() {
  # Green <50ms, Yellow <150ms, Orange <300ms, Red >=300ms
  local ms="$1"
  # strip decimals for compare
  local ms_int; ms_int=$(printf '%s' "$ms" | awk -F. '{print $1}')
  if   [ "$ms_int" -lt 50  ] 2>/dev/null; then printf '%b' "$LG"
  elif [ "$ms_int" -lt 150 ] 2>/dev/null; then printf '%b' "$LY"
  elif [ "$ms_int" -lt 300 ] 2>/dev/null; then printf '%b' "$ORANGE"
  else                                          printf '%b' "$LR"
  fi
}

bar() {
  # bar <ms_int> — draw a small ASCII bar proportional to latency
  local ms="$1"
  local max=400 width=20
  local filled=$(( ms * width / max ))
  [ $filled -gt $width ] && filled=$width
  local empty=$(( width - filled ))
  local col; col=$(rtt_color "$ms")
  printf "${col}"
  printf '%0.s█' $(seq 1 $filled 2>/dev/null) 2>/dev/null || \
    awk -v n="$filled" 'BEGIN{for(i=0;i<n;i++)printf "█"}'
  printf "${GRAY}"
  printf '%0.s░' $(seq 1 $empty 2>/dev/null) 2>/dev/null || \
    awk -v n="$empty" 'BEGIN{for(i=0;i<n;i++)printf "░"}'
  printf "${RST}"
}

# ── Banner ────────────────────────────────────────────────────
show_banner() {
  clear
  printf '\n'
  rule "═" "$BLOOD"
  printf '\n'
  printf '%b' "${CRIMSON}${BOLD}"
  center "██████╗ ██╗███╗   ██╗ ██████╗ "
  center "██╔══██╗██║████╗  ██║██╔════╝ "
  center "██████╔╝██║██╔██╗ ██║██║  ███╗"
  center "██╔═══╝ ██║██║╚██╗██║██║   ██║"
  center "██║     ██║██║ ╚████║╚██████╔╝"
  center "╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ "
  printf '%b' "${RST}"
  printf '\n'
  center "${LGRAY}P I N G   M O N I T O R  —  i S H   E d i t i o n${RST}"
  printf '\n'
  rule "═" "$BLOOD"
  printf '\n'
}

# ── Input ─────────────────────────────────────────────────────
show_banner

printf "  ${BLOOD}◈${RST}  ${LW}Host / IP to ping:${RST}  "
read -r TARGET
[ -z "$TARGET" ] && { echo -e "\n  ${LR}✘  No target entered.${RST}\n"; exit 1; }

printf "  ${BLOOD}◈${RST}  ${LW}Interval (seconds, default 1):${RST}  "
read -r INTERVAL
INTERVAL=${INTERVAL:-1}

printf "  ${BLOOD}◈${RST}  ${LW}Packet count (0 = infinite, default 0):${RST}  "
read -r COUNT
COUNT=${COUNT:-0}

printf '\n'
rule "═" "$BLOOD"
printf '\n'
center "${BLOOD}▶▶  ${LW}${BOLD}${TARGET}${RST}  ${BLOOD}◀◀${RST}"
printf '\n'
rule "═" "$BLOOD"
printf '\n'

# ── Stats ─────────────────────────────────────────────────────
SENT=0; RECV=0; LOST=0
MIN=99999; MAX=0; SUM=0
START_TIME=$(date +%s)

cleanup() {
  printf '\n'
  rule "═" "$BLOOD"
  printf '\n'
  center "${BOLD}${LW}SESSION SUMMARY${RST}"
  printf '\n'

  local elapsed=$(( $(date +%s) - START_TIME ))
  local loss=0
  [ $SENT -gt 0 ] && loss=$(( LOST * 100 / SENT ))

  local avg=0
  [ $RECV -gt 0 ] && avg=$(( SUM / RECV ))

  # loss colour
  local loss_col="$LG"
  [ $loss -ge 5  ] && loss_col="$LY"
  [ $loss -ge 20 ] && loss_col="$ORANGE"
  [ $loss -ge 50 ] && loss_col="$LR"

  printf "  ${LGRAY}Target   ${RST}  ${LW}${TARGET}${RST}\n"
  printf "  ${LGRAY}Duration ${RST}  ${LW}${elapsed}s${RST}\n"
  printf "  ${LGRAY}Sent     ${RST}  ${LW}${SENT}${RST}\n"
  printf "  ${LGRAY}Received ${RST}  ${LW}${RECV}${RST}\n"
  printf "  ${LGRAY}Lost     ${RST}  ${loss_col}${LOST} (${loss}%%)${RST}\n"
  printf '\n'
  if [ $RECV -gt 0 ]; then
    printf "  ${LGRAY}Min RTT  ${RST}  $(rtt_color $MIN)${MIN} ms${RST}\n"
    printf "  ${LGRAY}Avg RTT  ${RST}  $(rtt_color $avg)${avg} ms${RST}\n"
    printf "  ${LGRAY}Max RTT  ${RST}  $(rtt_color $MAX)${MAX} ms${RST}\n"
  fi
  printf '\n'
  rule "═" "$BLOOD"
  printf '\n'
  exit 0
}
trap cleanup INT TERM

# ── Loop ──────────────────────────────────────────────────────
SEQ=0
while true; do
  SEQ=$(( SEQ + 1 ))
  SENT=$(( SENT + 1 ))

  # iSH / Alpine busybox ping: -c 1 -W 2 (2s timeout)
  RESULT=$(ping -c 1 -W 2 "$TARGET" 2>&1)
  STATUS=$?

  TIMESTAMP=$(date '+%H:%M:%S')

  if [ $STATUS -eq 0 ]; then
    # extract RTT — busybox format: "time=12.3 ms" or "time=12.3ms"
    RTT=$(printf '%s' "$RESULT" | grep -oE 'time=[0-9]+(\.[0-9]+)?' | head -1 | cut -d= -f2)
    RTT=${RTT:-0}
    RTT_INT=$(printf '%s' "$RTT" | awk -F. '{print $1}')
    [ -z "$RTT_INT" ] && RTT_INT=0

    RECV=$(( RECV + 1 ))
    SUM=$(( SUM + RTT_INT ))
    [ $RTT_INT -lt $MIN ] && MIN=$RTT_INT
    [ $RTT_INT -gt $MAX ] && MAX=$RTT_INT

    COL=$(rtt_color "$RTT_INT")
    BAR=$(bar "$RTT_INT")

    printf "  ${GRAY}[${TIMESTAMP}]${RST}  ${GRAY}#%-4s${RST}  ${BAR}  ${COL}${BOLD}%6s ms${RST}  ${LG}✔${RST}\n" \
      "$SEQ" "$RTT"
  else
    LOST=$(( LOST + 1 ))
    printf "  ${GRAY}[${TIMESTAMP}]${RST}  ${GRAY}#%-4s${RST}  ${LR}%-22s${RST}  ${LR}✘  timeout${RST}\n" \
      "$SEQ" "$(printf '%*s' 22 '' | tr ' ' '░')"
  fi

  # Stop if count reached
  if [ "$COUNT" -gt 0 ] && [ $SEQ -ge "$COUNT" ]; then
    cleanup
  fi

  sleep "$INTERVAL"
done

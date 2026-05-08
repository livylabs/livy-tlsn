#!/usr/bin/env bash
set -euo pipefail

ITERATIONS="${ITERATIONS:-25}"
BENCHMARK_MODES="${BENCHMARK_MODES:-no_tee tee_no_verify tee_verify}"
TLSN_REPO_URL="${TLSN_REPO_URL:-https://github.com/livylabs/tlsn.git}"
TLSN_BRANCH="${TLSN_BRANCH:-benchmark}"
TLSN_DIR="${TLSN_DIR:-.benchmark/tlsn}"
RESULTS_DIR="${RESULTS_DIR:-benchmark-results/$(date -u +%Y%m%dT%H%M%SZ)}"
START_FIXTURE="${START_FIXTURE:-1}"
FIXTURE_ADDR="${FIXTURE_ADDR:-127.0.0.1}"
FIXTURE_PORT="${FIXTURE_PORT:-4000}"

NOTARY_SCHEME="${NOTARY_SCHEME:-https}"
NOTARY_HOST="${NOTARY_HOST:-tlsn.livylabs.xyz}"
NOTARY_PORT="${NOTARY_PORT:-443}"
TARGET_HOST="${TARGET_HOST:-$FIXTURE_ADDR}"
TARGET_PORT="${TARGET_PORT:-$FIXTURE_PORT}"
# The fixture server certificate is issued for test-server.io. The TCP
# connection still goes to TARGET_HOST, which defaults to localhost.
TARGET_SERVER_NAME="${TARGET_SERVER_NAME:-test-server.io}"
TARGET_URI="${TARGET_URI:-/formats/json?size=4}"
USE_FIXTURE_CA="${USE_FIXTURE_CA:-true}"
MAX_SENT_DATA="${MAX_SENT_DATA:-4096}"
MAX_RECV_DATA="${MAX_RECV_DATA:-16384}"
RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS:-300}"

RESULTS_CSV="$RESULTS_DIR/results.csv"
SUMMARY_TXT="$RESULTS_DIR/summary.txt"
LOG_DIR="$RESULTS_DIR/logs"
FIXTURE_PID=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time() * 1000))'
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

sync_tlsn_repo() {
  mkdir -p "$(dirname "$TLSN_DIR")"

  if [ ! -d "$TLSN_DIR/.git" ]; then
    log "cloning $TLSN_REPO_URL branch $TLSN_BRANCH into $TLSN_DIR"
    git clone --branch "$TLSN_BRANCH" --single-branch "$TLSN_REPO_URL" "$TLSN_DIR"
    return
  fi

  log "updating $TLSN_DIR to origin/$TLSN_BRANCH"
  git -C "$TLSN_DIR" remote set-url origin "$TLSN_REPO_URL"
  git -C "$TLSN_DIR" fetch origin "$TLSN_BRANCH"
  git -C "$TLSN_DIR" checkout -B "$TLSN_BRANCH" "origin/$TLSN_BRANCH"
}

build_example() {
  log "building benchmark binaries in release mode"
  (
    cd "$TLSN_DIR"
    cargo build --release -p tlsn-examples --example tee_ws
    cargo build --release -p tlsn-server-fixture --bin tlsn-server-fixture
  )
}

stop_fixture() {
  if [ -n "$FIXTURE_PID" ] && kill -0 "$FIXTURE_PID" >/dev/null 2>&1; then
    kill "$FIXTURE_PID" >/dev/null 2>&1 || true
    wait "$FIXTURE_PID" >/dev/null 2>&1 || true
  fi
}

start_fixture() {
  [ "$START_FIXTURE" = "1" ] || return 0

  require_command curl

  log "starting local TLS fixture on $FIXTURE_ADDR:$FIXTURE_PORT"
  ADDR="$FIXTURE_ADDR" PORT="$FIXTURE_PORT" \
    "$TLSN_DIR/target/release/tlsn-server-fixture" \
    >"$LOG_DIR/fixture.stdout.log" \
    2>"$LOG_DIR/fixture.stderr.log" &
  FIXTURE_PID="$!"

  trap stop_fixture EXIT

  for _ in $(seq 1 60); do
    if ! kill -0 "$FIXTURE_PID" >/dev/null 2>&1; then
      fail "fixture server exited early; see $LOG_DIR/fixture.stderr.log"
    fi

    if curl -fsSk "https://$FIXTURE_ADDR:$FIXTURE_PORT/formats/json?size=1" >/dev/null 2>&1; then
      log "local TLS fixture is ready"
      return 0
    fi

    sleep 1
  done

  fail "fixture server did not become ready; see $LOG_DIR/fixture.stderr.log"
}

run_cargo_with_timeout() {
  local enable_tee="$1"
  local verify_attestation="$2"
  local stdout_log="$3"
  local stderr_log="$4"

  env \
    TLSN_DIR="$TLSN_DIR" \
    RUN_TIMEOUT_SECONDS="$RUN_TIMEOUT_SECONDS" \
    NOTARY_SCHEME="$NOTARY_SCHEME" \
    NOTARY_HOST="$NOTARY_HOST" \
    NOTARY_PORT="$NOTARY_PORT" \
    TARGET_HOST="$TARGET_HOST" \
    TARGET_PORT="$TARGET_PORT" \
    TARGET_SERVER_NAME="$TARGET_SERVER_NAME" \
    TARGET_URI="$TARGET_URI" \
    USE_FIXTURE_CA="$USE_FIXTURE_CA" \
    MAX_SENT_DATA="$MAX_SENT_DATA" \
    MAX_RECV_DATA="$MAX_RECV_DATA" \
    ENABLE_TEE_ATTESTATION="$enable_tee" \
    VERIFY_ATTESTATION="$verify_attestation" \
    python3 - "$stdout_log" "$stderr_log" <<'PY'
import os
import signal
import subprocess
import sys

stdout_path, stderr_path = sys.argv[1], sys.argv[2]
cmd = ["./target/release/examples/tee_ws"]
if os.environ["VERIFY_ATTESTATION"] == "1":
    cmd.append("--verify")
timeout = int(os.environ["RUN_TIMEOUT_SECONDS"])

with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr:
    process = subprocess.Popen(
        cmd,
        cwd=os.environ["TLSN_DIR"],
        env=os.environ.copy(),
        stdout=stdout,
        stderr=stderr,
        start_new_session=True,
    )
    try:
        raise SystemExit(process.wait(timeout=timeout))
    except subprocess.TimeoutExpired:
        stderr.write(f"benchmark runner: timed out after {timeout}s\n".encode())
        stderr.flush()
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise SystemExit(124)
PY
}

extract_metric() {
  local name="$1"
  local file="$2"

  awk -v name="$name" '
    {
      for (i = 1; i <= NF; i++) {
        if (index($i, name "=") == 1) {
          split($i, parts, "=")
          value = parts[2]
        }
      }
    }
    END {
      if (value != "") {
        print value
      }
    }
  ' "$file"
}

run_one() {
  local mode="$1"
  local enable_tee="$2"
  local verify_attestation="$3"
  local iteration="$4"
  local stdout_log="$LOG_DIR/${mode}-${iteration}.stdout.log"
  local stderr_log="$LOG_DIR/${mode}-${iteration}.stderr.log"
  local start_ms end_ms wall_ms exit_code notarization_ms total_e2e_ms tdx_verify_ms notarization_plus_verify_ms verify_component

  log "run mode=$mode iteration=$iteration enable_tee=$enable_tee verify_attestation=$verify_attestation"

  start_ms="$(now_ms)"
  set +e
  run_cargo_with_timeout "$enable_tee" "$verify_attestation" "$stdout_log" "$stderr_log"
  exit_code=$?
  set -e
  end_ms="$(now_ms)"
  wall_ms=$((end_ms - start_ms))

  notarization_ms="$(extract_metric NOTARIZATION_MS "$stdout_log" || true)"
  total_e2e_ms="$(extract_metric TOTAL_E2E_MS "$stdout_log" || true)"
  tdx_verify_ms="$(extract_metric TDX_VERIFY_MS "$stdout_log" || true)"
  notarization_plus_verify_ms=""
  if [[ "$notarization_ms" =~ ^[0-9]+$ ]]; then
    verify_component=0
    if [[ "$tdx_verify_ms" =~ ^[0-9]+$ ]]; then
      verify_component="$tdx_verify_ms"
    fi
    notarization_plus_verify_ms=$((notarization_ms + verify_component))
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$mode" \
    "$iteration" \
    "$enable_tee" \
    "$verify_attestation" \
    "$exit_code" \
    "$notarization_ms" \
    "$total_e2e_ms" \
    "$tdx_verify_ms" \
    "$notarization_plus_verify_ms" \
    "$wall_ms" \
    "$stdout_log" \
    "$stderr_log" >>"$RESULTS_CSV"

  if [ "$exit_code" -ne 0 ]; then
    log "run failed mode=$mode iteration=$iteration exit_code=$exit_code stderr=$stderr_log"
  fi

  return 0
}

run_mode() {
  local mode="$1"
  local iteration="$2"

  case "$mode" in
    no_tee)
      run_one no_tee 0 0 "$iteration"
      ;;
    tee_no_verify)
      run_one tee_no_verify 1 0 "$iteration"
      ;;
    tee_verify)
      run_one tee_verify 1 1 "$iteration"
      ;;
    *)
      fail "unknown benchmark mode: $mode"
      ;;
  esac
}

print_summary() {
  log ""
  log "results written to $RESULTS_CSV"

  python3 - "$RESULTS_CSV" <<'PY' | tee "$SUMMARY_TXT"
import csv
import statistics
import sys

path = sys.argv[1]
rows = list(csv.DictReader(open(path)))
modes = ["no_tee", "tee_no_verify", "tee_verify"]

def successful(mode):
    return [row for row in rows if row["mode"] == mode and row["exit_code"] == "0" and row["notarization_ms"]]

def values(mode, key):
    return [int(row[key]) for row in successful(mode) if row[key]]

def avg(items):
    return statistics.mean(items) if items else None

def median(items):
    return statistics.median(items) if items else None

def p90(items):
    return statistics.quantiles(items, n=10, method="inclusive")[8] if len(items) >= 2 else (items[0] if items else None)

def fmt(value):
    return "n/a" if value is None else f"{value:.2f}"

def numeric(row, key):
    value = row.get(key, "")
    return int(value) if value else None

def successful_by_iteration(mode):
    indexed = {}
    for row in successful(mode):
        indexed[row["iteration"]] = row
    return indexed

def paired_overhead(target_mode, target_key):
    base_rows = successful_by_iteration("no_tee")
    target_rows = successful_by_iteration(target_mode)
    deltas = []
    percents = []

    for iteration in sorted(set(base_rows) & set(target_rows), key=int):
        base = numeric(base_rows[iteration], "notarization_ms")
        target = numeric(target_rows[iteration], target_key)
        if base is None or target is None or base == 0:
            continue
        deltas.append(target - base)
        percents.append((target - base) / base * 100)

    return deltas, percents

print("summary from successful runs:")
for mode in modes:
    mode_rows = successful(mode)
    if not mode_rows:
        continue

    notarization = values(mode, "notarization_ms")
    total = values(mode, "total_e2e_ms")
    verify = values(mode, "tdx_verify_ms")
    combined = values(mode, "notarization_plus_verify_ms")
    wall = values(mode, "wall_ms")
    print(
        f"{mode}: runs={len(mode_rows)} "
        f"avg_notarization_ms={fmt(avg(notarization))} "
        f"median_notarization_ms={fmt(median(notarization))} "
        f"p90_notarization_ms={fmt(p90(notarization))} "
        f"avg_total_e2e_ms={fmt(avg(total))} "
        f"avg_tdx_verify_ms={fmt(avg(verify))} "
        f"median_tdx_verify_ms={fmt(median(verify))} "
        f"avg_notarization_plus_verify_ms={fmt(avg(combined))} "
        f"median_notarization_plus_verify_ms={fmt(median(combined))} "
        f"p90_notarization_plus_verify_ms={fmt(p90(combined))} "
        f"avg_wall_ms={fmt(avg(wall))}"
    )

no_tee = values("no_tee", "notarization_ms")
tee_no_verify = values("tee_no_verify", "notarization_ms")
tee_verify_notarization = values("tee_verify", "notarization_ms")
tee_verify_combined = values("tee_verify", "notarization_plus_verify_ms")
tee_verify_verify = values("tee_verify", "tdx_verify_ms")

if no_tee and tee_no_verify:
    no_avg = avg(no_tee)
    no_median = median(no_tee)
    tee_avg = avg(tee_no_verify)
    tee_median = median(tee_no_verify)
    print(f"tee_no_verify_avg_notarization_overhead_ms={tee_avg - no_avg:.2f} tee_no_verify_avg_notarization_overhead_percent={(tee_avg - no_avg) / no_avg * 100:.2f}")
    print(f"tee_no_verify_median_notarization_overhead_ms={tee_median - no_median:.2f} tee_no_verify_median_notarization_overhead_percent={(tee_median - no_median) / no_median * 100:.2f}")
    deltas, percents = paired_overhead("tee_no_verify", "notarization_ms")
    if deltas and percents:
        print(f"tee_no_verify_paired_avg_notarization_overhead_ms={avg(deltas):.2f} tee_no_verify_paired_avg_notarization_overhead_percent={avg(percents):.2f}")
        print(f"tee_no_verify_paired_median_notarization_overhead_ms={median(deltas):.2f} tee_no_verify_paired_median_notarization_overhead_percent={median(percents):.2f}")

if no_tee and tee_verify_notarization and tee_verify_combined:
    no_avg = avg(no_tee)
    no_median = median(no_tee)
    verify_not_avg = avg(tee_verify_notarization)
    verify_combined_avg = avg(tee_verify_combined)
    verify_combined_median = median(tee_verify_combined)
    print(f"tee_verify_avg_notarization_overhead_ms={verify_not_avg - no_avg:.2f} tee_verify_avg_notarization_overhead_percent={(verify_not_avg - no_avg) / no_avg * 100:.2f}")
    print(f"tee_verify_avg_combined_overhead_ms={verify_combined_avg - no_avg:.2f} tee_verify_avg_combined_overhead_percent={(verify_combined_avg - no_avg) / no_avg * 100:.2f}")
    print(f"tee_verify_median_combined_overhead_ms={verify_combined_median - no_median:.2f} tee_verify_median_combined_overhead_percent={(verify_combined_median - no_median) / no_median * 100:.2f}")
    deltas, percents = paired_overhead("tee_verify", "notarization_plus_verify_ms")
    if deltas and percents:
        print(f"tee_verify_paired_avg_combined_overhead_ms={avg(deltas):.2f} tee_verify_paired_avg_combined_overhead_percent={avg(percents):.2f}")
        print(f"tee_verify_paired_median_combined_overhead_ms={median(deltas):.2f} tee_verify_paired_median_combined_overhead_percent={median(percents):.2f}")

if tee_verify_verify:
    print(f"tee_verify_avg_tdx_verify_ms={avg(tee_verify_verify):.2f} tee_verify_median_tdx_verify_ms={median(tee_verify_verify):.2f}")

failures = [row for row in rows if row["exit_code"] != "0"]
if failures:
    print(f"failed_runs={len(failures)}")
    raise SystemExit(1)
PY
}

main() {
  require_command git
  require_command cargo
  require_command awk
  require_command python3

  mkdir -p "$LOG_DIR"
  printf 'mode,iteration,enable_tee,verify_attestation,exit_code,notarization_ms,total_e2e_ms,tdx_verify_ms,notarization_plus_verify_ms,wall_ms,stdout_log,stderr_log\n' >"$RESULTS_CSV"

  sync_tlsn_repo
  build_example
  start_fixture

  for iteration in $(seq 1 "$ITERATIONS"); do
    for mode in $BENCHMARK_MODES; do
      run_mode "$mode" "$iteration"
    done
  done

  print_summary
}

main "$@"

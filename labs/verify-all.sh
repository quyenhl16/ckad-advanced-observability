#!/usr/bin/env bash
set -uo pipefail

readonly LABS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR=""

usage() {
  cat <<EOF
Usage: $0 [--report-dir DIRECTORY]

Run the live verifier for Day 1 through Day 5. Run every lab workflow first;
the verifier checks the resulting Kubernetes resources and behavior.

Options:
  --report-dir DIR  Save one report per day under DIR
  -h, --help        Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --report-dir)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --report-dir requires a value' >&2; exit 2; }
      REPORT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$REPORT_DIR" ]]; then
  mkdir -p -- "$REPORT_DIR"
fi

failed_days=()
for day in 1 2 3 4 5; do
  printf '\n################################################################################\n'
  printf 'RUNNING DAY %d VERIFIER\n' "$day"
  args=()
  if [[ -n "$REPORT_DIR" ]]; then
    args+=(--report "${REPORT_DIR}/day${day}-verification.txt")
  fi
  if ! bash "${LABS_DIR}/day${day}/verify.sh" "${args[@]}"; then
    failed_days+=("day${day}")
  fi
done

printf '\n################################################################################\n'
if ((${#failed_days[@]} == 0)); then
  printf 'ALL LAB DAYS VERIFY: PASS\n'
  exit 0
fi

printf 'ALL LAB DAYS VERIFY: FAIL (%s)\n' "${failed_days[*]}"
exit 1

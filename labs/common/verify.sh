#!/usr/bin/env bash

# Shared reporting helpers for the per-day live lab verifiers.

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0
VERIFY_REPORT=""
VERIFY_TITLE=""

verify_usage() {
  cat <<EOF
Usage: $0 [--report FILE]

Run live verification for every lab in this day. Each check prints the
requirement, command, output, evidence and PASS/FAIL result.

Options:
  --report FILE  Also save the complete output to FILE
  -h, --help     Show this help
EOF
}

init_verifier() {
  VERIFY_TITLE="$1"
  shift

  while (($# > 0)); do
    case "$1" in
      --report)
        (($# >= 2)) || { printf '%s\n' 'ERROR: --report requires a file' >&2; exit 2; }
        VERIFY_REPORT="$2"
        shift 2
        ;;
      -h|--help)
        verify_usage
        exit 0
        ;;
      *)
        printf 'ERROR: unknown option: %s\n' "$1" >&2
        verify_usage >&2
        exit 2
        ;;
    esac
  done

  command -v kubectl >/dev/null 2>&1 || {
    printf '%s\n' 'ERROR: kubectl is required' >&2
    exit 2
  }

  if [[ -n "$VERIFY_REPORT" ]]; then
    mkdir -p -- "$(dirname -- "$VERIFY_REPORT")"
    exec > >(tee "$VERIFY_REPORT") 2>&1
  fi

  printf '%s\n' "$VERIFY_TITLE"
  printf 'Kubernetes context: '
  kubectl config current-context
  printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

run_lab_check() {
  local check_id="$1"
  local title="$2"
  local requirement="$3"
  local command_text="$4"
  local verify_function="$5"
  local success_evidence="$6"
  local output rc

  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  printf '\n================================================================================\n'
  printf '[%s] %s\n' "$check_id" "$title"
  printf 'REQUIREMENT: %s\n' "$requirement"
  printf 'COMMAND: %s\n' "$command_text"

  output="$($verify_function 2>&1)"
  rc=$?
  printf 'OUTPUT:\n'
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  else
    printf '%s\n' '<no output>'
  fi
  printf 'EXIT CODE: %d\n' "$rc"

  if [[ $rc -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'EVIDENCE: %s\n' "$success_evidence"
    printf 'VERIFY: PASS\n'
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'EVIDENCE: Observed live state does not satisfy the requirement; inspect the output above and rerun the lab workflow.\n'
    printf 'VERIFY: FAIL\n'
  fi
}

finish_verifier() {
  printf '\n================================================================================\n'
  printf 'SUMMARY\n'
  printf '  PASS:  %d\n' "$PASS_COUNT"
  printf '  FAIL:  %d\n' "$FAIL_COUNT"
  printf '  TOTAL: %d\n' "$TOTAL_COUNT"
  if [[ $FAIL_COUNT -eq 0 ]]; then
    printf 'OVERALL VERIFY: PASS\n'
    return 0
  fi
  printf 'OVERALL VERIFY: FAIL\n'
  return 1
}

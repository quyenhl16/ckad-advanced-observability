#!/usr/bin/env bash
set -Eeuo pipefail

readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly DATABASE_POD="observability-db-0"
readonly CONFIRMATION_TOKEN="DELETE-ALL-DATA"

CONFIRMATION=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/clear-database.sh --confirm DELETE-ALL-DATA

Permanently remove all rows from every non-system PostgreSQL table while
retaining the database, schemas, roles, passwords and table definitions.
Sequences are restarted and foreign-key relationships are handled with
CASCADE. No backup is created and application workloads remain running.

Options:
  --confirm TOKEN      Required; must equal DELETE-ALL-DATA
  -h, --help           Show this help

Environment:
  NAMESPACE            Project namespace (default: advanced-observability)
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

while (($# > 0)); do
  case "$1" in
    --confirm)
      (($# >= 2)) || {
        printf 'ERROR: --confirm requires a value.\n' >&2
        exit 2
      }
      CONFIRMATION="$2"
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

[[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || {
  printf 'ERROR: invalid namespace: %s\n' "$NAMESPACE" >&2
  exit 2
}
[[ "$CONFIRMATION" == "$CONFIRMATION_TOKEN" ]] || {
  printf 'ERROR: pass --confirm %s to authorize permanent data deletion.\n' \
    "$CONFIRMATION_TOKEN" >&2
  exit 2
}

require_command kubectl

printf 'Kubernetes context: '
kubectl config current-context
printf 'Database cleanup target:\n'
printf '  namespace:    %s\n' "$NAMESPACE"
printf '  database Pod: %s\n' "$DATABASE_POD"
printf '  backup:       none\n'
printf '  workloads:    remain running\n'

kubectl get namespace "$NAMESPACE" >/dev/null
kubectl get "pod/${DATABASE_POD}" --namespace "$NAMESPACE" >/dev/null
kubectl wait "pod/${DATABASE_POD}" \
  --namespace "$NAMESPACE" \
  --for=condition=Ready \
  --timeout=120s

printf '\nDeleting all rows and restarting table sequences...\n'
kubectl exec -i "pod/${DATABASE_POD}" \
  --namespace "$NAMESPACE" \
  -- sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" exec psql \
    --host 127.0.0.1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1' <<'SQL'
\echo '=== Database identity ==='
SELECT current_user AS database_user, current_database() AS database_name;

\echo '=== Row counts before cleanup ==='
SELECT format(
  'SELECT %L AS table_name, count(*)::bigint AS row_count FROM %I.%I;',
  schemaname || '.' || tablename,
  schemaname,
  tablename
)
FROM pg_tables
WHERE schemaname <> 'information_schema'
  AND schemaname NOT LIKE 'pg_%'
ORDER BY schemaname, tablename
\gexec

DO $clear$
DECLARE
  table_list text;
  table_record record;
  remaining_rows bigint;
BEGIN
  SELECT string_agg(
    format('%I.%I', schemaname, tablename),
    ', ' ORDER BY schemaname, tablename
  )
  INTO table_list
  FROM pg_tables
  WHERE schemaname <> 'information_schema'
    AND schemaname NOT LIKE 'pg_%';

  IF table_list IS NULL THEN
    RAISE NOTICE 'No user tables found; nothing to truncate';
    RETURN;
  END IF;

  EXECUTE 'TRUNCATE TABLE ' || table_list || ' RESTART IDENTITY CASCADE';

  FOR table_record IN
    SELECT schemaname, tablename
    FROM pg_tables
    WHERE schemaname <> 'information_schema'
      AND schemaname NOT LIKE 'pg_%'
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I.%I',
      table_record.schemaname,
      table_record.tablename
    ) INTO remaining_rows;

    IF remaining_rows <> 0 THEN
      RAISE EXCEPTION 'Table %.% still contains % row(s)',
        table_record.schemaname,
        table_record.tablename,
        remaining_rows;
    END IF;
  END LOOP;
END
$clear$;

\echo '=== Row counts after cleanup ==='
SELECT format(
  'SELECT %L AS table_name, count(*)::bigint AS row_count FROM %I.%I;',
  schemaname || '.' || tablename,
  schemaname,
  tablename
)
FROM pg_tables
WHERE schemaname <> 'information_schema'
  AND schemaname NOT LIKE 'pg_%'
ORDER BY schemaname, tablename
\gexec
SQL

printf '\nDatabase data cleanup completed successfully.\n'
printf 'Schemas, tables, roles and credentials were retained.\n'
printf 'Workloads were not scaled; new rows may appear if traffic is still active.\n'
printf 'Analytics event history is stored separately in the analytics Pod emptyDir.\n'

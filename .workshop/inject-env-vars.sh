#!/usr/bin/env bash
# Compatibility hook for deployers that provide lab credentials through env vars.
# Preserve Showroom user_data and use ui-config.yml as the tab source of truth.
set -euo pipefail

REPO_DIR="${SHOWROOM_REPO_DIR:-/showroom/repo}"
WWW_DIR="${SHOWROOM_WWW_DIR:-/showroom/www}"
SITE_FILE="${REPO_DIR}/default-site.yml"
UI_CONFIG="${REPO_DIR}/ui-config.yml"

for file in "$SITE_FILE" "$UI_CONFIG"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: ${file} not found" >&2
    exit 1
  fi
done

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
ATTRIBUTES="${WORK_DIR}/attributes"
: > "$ATTRIBUTES"

# YAML single-quoted scalars preserve punctuation in URLs and passwords.
yaml_quote() {
  local value="$1"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo 'ERROR: Lab environment values must be single-line strings.' >&2
    return 1
  fi
  value=$(printf '%s' "$value" | sed "s/'/''/g")
  printf "'%s'" "$value"
}

add_attribute() {
  local quoted
  [[ -n "$2" ]] || return 0
  quoted=$(yaml_quote "$2")
  printf '    %s: %s\n' "$1" "$quoted" >> "$ATTRIBUTES"
}

CONSOLE_URL="${MASTER_URL:-}"
APPS_DOMAIN="${ROUTE_SUBDOMAIN:-${DOMAIN:-}}"
if [[ -z "$CONSOLE_URL" && -n "$APPS_DOMAIN" ]]; then
  CONSOLE_URL="https://console-openshift-console.${APPS_DOMAIN}"
fi
ADMIN_NAME="${ADMIN_USERNAME:-${ADMIN_USER:-}}"
if [[ -z "$ADMIN_NAME" && -n "${ADMIN_PASSWORD:-}" ]]; then
  ADMIN_NAME=admin
fi

add_attribute openshift_cluster_console_url "$CONSOLE_URL"
add_attribute openshift_cluster_admin_username "$ADMIN_NAME"
add_attribute openshift_cluster_admin_password "${ADMIN_PASSWORD:-}"

# Merge only supplied attributes; retain credentials and settings injected by
# Showroom when the corresponding legacy environment variables are absent.
awk '
  FILENAME == ARGV[1] {
    key = $1; sub(/:$/, "", key)
    replacements[key] = $0
    next
  }
  function flush( key) {
    for (key in replacements) print replacements[key]
    delete replacements
  }
  /^asciidoc:/ { in_asciidoc = 1; saw_asciidoc = 1; print; next }
  in_attributes && /^[^ ]|^  [^ ]/ { flush(); in_attributes = 0 }
  in_asciidoc && /^[^ #]/ {
    if (!saw_attributes) { print "  attributes:"; flush(); saw_attributes = 1 }
    in_asciidoc = 0
  }
  in_asciidoc && /^  attributes:/ {
    in_attributes = 1; saw_attributes = 1; print; next
  }
  in_attributes && /^    [^ ]/ {
    key = $1; sub(/:$/, "", key)
    if (key in replacements) {
      print replacements[key]
      delete replacements[key]
      next
    }
  }
  { print }
  END {
    if (!saw_asciidoc) print "asciidoc:"
    if (!saw_attributes) print "  attributes:"
    flush()
  }
' "$ATTRIBUTES" "$SITE_FILE" > "${WORK_DIR}/site.yml"
cat "${WORK_DIR}/site.yml" > "$SITE_FILE"

if [[ -n "$CONSOLE_URL" ]]; then
  export SHOWROOM_CONSOLE_YAML
  SHOWROOM_CONSOLE_YAML=$(yaml_quote "$CONSOLE_URL")
  awk '
    /- name:/ { console_tab = ($0 ~ /- name: OCP Console$/) }
    console_tab && /^    url:/ {
      print "    url: " ENVIRON["SHOWROOM_CONSOLE_YAML"]
      next
    }
    { print }
  ' "$UI_CONFIG" > "${WORK_DIR}/ui-config.yml"
  cat "${WORK_DIR}/ui-config.yml" > "$UI_CONFIG"
fi

if [[ -d "$WWW_DIR" ]]; then
  cp "$UI_CONFIG" "${WWW_DIR}/ui-config.yml"
fi

echo 'Application Management configuration updated; console and terminal tabs preserved.'

#!/usr/bin/env bash
set -euo pipefail

namespace="$1"
name="${2:-}"
shift 2 || true
stern_args=()
if (( $# > 0 )); then
  stern_args=("$@")
fi

if ! command -v stern >/dev/null 2>&1; then
  echo "stern not found in PATH" >&2
  exit 1
fi

kubectl_cmd=(kubectl -n "$namespace")

select_pod() {
  pod_entries=()
  while IFS= read -r line; do
    [[ -n ${line} ]] && pod_entries+=("${line}")
  done < <(${kubectl_cmd[@]} get pods --no-headers)
  if [[ ${#pod_entries[@]} -eq 0 ]]; then
    echo "No pods found in namespace ${namespace}"
    exit 1
  fi

  if command -v fzf >/dev/null 2>&1; then
    selection="$(printf '%s\n' "${pod_entries[@]}" | fzf --prompt='Select pod > ' --height=20 --reverse || true)"
    if [[ -z "${selection}" ]]; then
      echo "No pod selected."
      exit 1
    fi
    pod="${selection%%[[:space:]]*}"
  else
    echo "Select a pod (tip: install 'fzf' for a nicer picker):"
    select choice in "${pod_entries[@]}"; do
      if [[ -n "${choice:-}" ]]; then
        pod="${choice%%[[:space:]]*}"
        break
      fi
    done
    if [[ -z "${pod:-}" ]]; then
      echo "No pod selected."
      exit 1
    fi
  fi

  printf '%s' "$pod"
}

pod="$name"
if [[ -z "$pod" ]]; then
  pod="$(select_pod)"
fi

echo "Tailing logs for pod: ${pod} in namespace ${namespace}" >&2
if (( ${#stern_args[@]} > 0 )); then
  stern --namespace "$namespace" "${stern_args[@]}" "$pod"
else
  stern --namespace "$namespace" "$pod"
fi

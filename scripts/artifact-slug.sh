#!/usr/bin/env bash
# Shared by the packaging scripts. The artifact name is derived from the binary
# that was actually built rather than hardcoded, so a filename can never promise
# a slice the app does not carry.

binary_arch_slug() {
  local binary="$1"
  local archs arch
  local has_arm64=0
  local has_x86_64=0

  if [[ ! -f "$binary" ]]; then
    echo "No binary at $binary." >&2
    return 1
  fi

  archs="$(/usr/bin/lipo -archs "$binary" 2>/dev/null || true)"
  if [[ -z "$archs" ]]; then
    echo "lipo could not read the architectures of $binary." >&2
    return 1
  fi

  for arch in $archs; do
    case "$arch" in
      arm64|arm64e) has_arm64=1 ;;
      x86_64|x86_64h) has_x86_64=1 ;;
    esac
  done

  if (( has_arm64 && has_x86_64 )); then
    echo "universal"
  elif (( has_arm64 )); then
    echo "arm64"
  elif (( has_x86_64 )); then
    echo "x86_64"
  else
    echo "$binary carries no Mac architecture ClaudePulse ships: $archs" >&2
    return 1
  fi
}

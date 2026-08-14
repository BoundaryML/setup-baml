#!/usr/bin/env bash
set -euo pipefail

readonly installer_commit="7d83d5fe75072bb4e2ccfb37b347f85bbb57b00f"
readonly installer_sha256="3218491b2947979a6d4a6543af5a9d31ce1d79d21bb54ef54070da0646309520"
readonly installer_url="https://raw.githubusercontent.com/BoundaryML/baml/${installer_commit}/scripts/install.sh"
readonly helper="${GITHUB_ACTION_PATH}/lib/wrapper-output.mjs"
readonly bin_dir="${BAML_HOME}/bin"
readonly wrapper="${bin_dir}/baml"

unset BAML_MANIFEST_BASE_URL || true
unset BAML_VERSION || true

tmp_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/setup-baml.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
installer="${tmp_dir}/install.sh"

curl --proto '=https' --tlsv1.2 --retry 3 --retry-connrefused --fail --silent --show-error --location "$installer_url" --output "$installer"
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha256="$(sha256sum "$installer" | awk '{print $1}')"
else
  actual_sha256="$(shasum -a 256 "$installer" | awk '{print $1}')"
fi
if [[ "$actual_sha256" != "$installer_sha256" ]]; then
  echo "setup-baml: official installer checksum verification failed" >&2
  exit 1
fi

sh "$installer" --wrapper-only --no-modify-path --yes

requested="${INPUT_TOOLCHAIN:-}"
version_override=""
if [[ -n "$requested" ]]; then
  selector="$(printf '%s' "$requested" | node "$helper" validate-selector)"
  version_override="$selector"
  export BAML_VERSION="$version_override"
else
  list_output="$("$wrapper" toolchain list)"
  printf '%s\n' "$list_output"
  selector="$(printf '%s' "$list_output" | node "$helper" selector)"
fi

"$wrapper" toolchain use "$selector"
version_output="$("$wrapper" --version)"
printf '%s\n' "$version_output"
version="$(printf '%s' "$version_output" | node "$helper" version)"
toolchain_path="${BAML_HOME}/toolchains/${version}/bin/baml-cli"

if [[ ! -x "$wrapper" || ! -x "$toolchain_path" ]]; then
  echo "setup-baml: wrapper or resolved toolchain binary is missing or not executable" >&2
  exit 1
fi

printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
{
  printf 'BAML_HOME=%s\n' "$BAML_HOME"
  printf 'BAML_VERSION=%s\n' "$version_override"
  printf 'BAML_MANIFEST_BASE_URL=\n'
} >> "$GITHUB_ENV"
{
  printf 'version=%s\n' "$version"
  printf 'path=%s\n' "$wrapper"
  printf 'toolchain-path=%s\n' "$toolchain_path"
} >> "$GITHUB_OUTPUT"

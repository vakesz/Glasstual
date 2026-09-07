#!/bin/bash
# Read-only release gates. Network access is confined to preflight.
set -euo pipefail

fail() { echo "::error::$*" >&2; return 1; }

# Canonical form without diagnostics: callers decide whether a rejection means a
# bad input version or a repository tag/release that is not canonical.
canonical_version() {
  local major minor patch
  [[ "$1" =~ ^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)(\.(0|[1-9][0-9]?))?$ ]] || return 1
  IFS=. read -r major minor patch <<< "$1"
  echo "${major}.${minor}.${patch:-0}"
}

normalize_version() {
  canonical_version "$1" || {
    fail "Invalid version: $1 (use canonical numeric major.minor[.patch])."; return 1;
  }
}

version_number() {
  local major minor patch
  IFS=. read -r major minor patch <<< "$1"
  echo "$((major * 10000 + minor * 100 + patch))"
}

validate_versions() {
  local version="$1" maintenance="$2" tags="$3" tag previous
  [[ "${maintenance}" == true || "${maintenance}" == false ]] || return 1
  while IFS= read -r tag; do
    [[ "${tag}" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]] || continue
    previous="$(canonical_version "${tag#v}")" || {
      fail "Existing tag or release ${tag} is not a canonical numeric version; fix the tag inventory."
      return 1
    }
    [[ "${previous}" != "${version}" ]] || {
      fail "Version ${version} already has a tag or release (${tag})."; return 1;
    }
    if [[ "${maintenance}" != true ]] &&
       (( $(version_number "${version}") <= $(version_number "${previous}") )); then
      fail "Product/build ${version} must exceed ${previous}; an older maintenance release must not be latest."
      return 1
    fi
  done <<< "${tags}"
}

validate_run() {
  local repository="$1" branch="$2" sha="$3"
  # Query the workflow file, not a caller-chosen check name or commit status.
  jq -e --arg repo "${repository}" --arg branch "${branch}" --arg sha "${sha}" '
    .path == ".github/workflows/quality.yml" and
    .event == "push" and .head_branch == $branch and .head_sha == $sha and
    .head_repository.full_name == $repo and .repository.full_name == $repo and
    .status == "completed" and .conclusion == "success"
  ' >/dev/null
}

validate_jobs() {
  jq -e '
    [.[].jobs[]] as $jobs |
    ($jobs | length > 0) and
    all($jobs[]; .status == "completed" and .conclusion == "success") and
    any($jobs[]; .name == "lint" and
      ([.steps[] | select(.status == "completed" and .conclusion == "success") | .name] as $steps |
       ["Lint and check formatting", "Validate Xcode project generation",
        "Build Debug app", "Run Swift Testing suite",
        "Build the E2E scheme for testing",
        "Run the loopback E2E fixtures"] | all(.[]; . as $name | $steps | index($name) != null)))
  ' >/dev/null
}

preflight() {
  local version tags releases runs run_id run jobs
  : "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${DEFAULT_BRANCH:?}" "${RELEASE_REF:?}"
  [[ "${RELEASE_REF}" == "refs/heads/${DEFAULT_BRANCH}" ]] || fail "Release must use the default branch."
  [[ "$(git rev-parse HEAD)" == "${GITHUB_SHA}" ]] || fail "Checkout is not the release SHA."
  version="$(normalize_version "$1")"
  # Tags and release records are independent; include drafts and all pages.
  tags="$(gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/tags?per_page=100")"
  releases="$(gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/releases?per_page=100")"
  tags="$(jq -er '[.[][] | .name] | if all(.[]; type == "string" and length > 0) then join("\n") else error("invalid tags") end' <<< "${tags}")" || fail "Invalid tag inventory."
  releases="$(jq -er '[.[][] | .tag_name] | if all(.[]; type == "string" and length > 0) then join("\n") else error("invalid releases") end' <<< "${releases}")" || fail "Invalid release inventory."
  validate_versions "${version}" "$2" "${tags}
${releases}"

  runs="$(gh api --method GET "repos/${GITHUB_REPOSITORY}/actions/workflows/quality.yml/runs" \
    -f head_sha="${GITHUB_SHA}" -f branch="${DEFAULT_BRANCH}" -f event=push -f per_page=100)"
  # Never fall back to an older green run when the newest one failed or is running.
  run_id="$(jq -er '.workflow_runs | max_by(.run_number) | .id // empty' <<< "${runs}")" ||
    fail "No Quality push run exists for the release SHA."
  run="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}")"
  validate_run "${GITHUB_REPOSITORY}" "${DEFAULT_BRANCH}" "${GITHUB_SHA}" <<< "${run}" ||
    fail "Quality is not a successful trusted push run for the exact release SHA."
  jobs="$(gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/jobs?filter=latest&per_page=100")"
  validate_jobs <<< "${jobs}" || fail "Required Quality build/test/generation/lint steps did not all succeed."
  echo "version=${version}"
  echo "build_version=${version}"
}

verify_archive() {
  local app="$1" version="$2" build="$3" plist product actual
  local required=(
    "Contents/Info.plist"
    "Contents/XPCServices/IRC Connection Host.xpc/Contents/Info.plist"
    "Contents/Frameworks/CocoaExtensions.framework/Resources/Info.plist"
    "Contents/Frameworks/GlasstualPluginKit.framework/Resources/Info.plist"
  )
  for product in Caffeine "Chat Filters" "Smiley Converter" "System Info" "User Insights" "ZNC Additions"; do
    required+=("Contents/Resources/Bundled Extensions/${product}.bundle/Contents/Info.plist")
  done
  for plist in "${required[@]}"; do
    # Framework Resources/Info.plist resolves through its version symlink.
    plist="${app}/${plist}"
    [[ -f "${plist}" ]] || fail "Missing archived metadata: ${plist}."
    product="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}")"
    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${plist}")"
    [[ "${product}" == "${version}" && "${actual}" == "${build}" ]] ||
      fail "Version mismatch in ${plist}: ${product} (${actual}), expected ${version} (${build})."
  done
}

case "${1:-}" in
  preflight) preflight "${2:?version}" "${3:?maintenance}" ;;
  archive) verify_archive "${2:?app}" "${3:?version}" "${4:?build}" ;;
  normalize) normalize_version "${2:?version}" ;;
  versions) validate_versions "${2:?version}" "${3:?maintenance}" "$(< "${4:?tags file}")" ;;
  run) validate_run "${2:?repository}" "${3:?branch}" "${4:?sha}" ;;
  jobs) validate_jobs ;;
  *) fail "Usage: $0 {preflight|archive|normalize|versions|run|jobs} ..." ;;
esac

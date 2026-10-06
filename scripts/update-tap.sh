#!/usr/bin/env bash
# Write a release's version and SHA-256 into the cask in the Homebrew tap.
#
#   scripts/update-tap.sh <command> <version> <sha256>              push to the tap
#   scripts/update-tap.sh <command> <version> <sha256> --print      print the cask only
#
# The cask is Packaging/homebrew/<command>.rb, copied to Casks/<command>.rb in
# the tap with its `version` and `sha256` lines filled in. A release whose
# command has no cask here is skipped.
#
# Environment: TAP_TOKEN, a token that can push to the tap (a fine-grained
# token with Contents: read and write on that repository only); TAP_REPO, the
# tap (default yahyabedirhan/homebrew-tap). Without TAP_TOKEN the script skips
# with a notice: the release workflow stays green until the tap exists.

set -euo pipefail

fail() { printf 'update-tap.sh: %s\n' "$*" >&2; exit 1; }

[ $# -ge 3 ] || fail "usage: update-tap.sh <command> <version> <sha256> [--print]"
command_name="$1"
version="$2"
sha256="$3"
print_only=0
[ "${4:-}" = "--print" ] && print_only=1

root="$(cd "$(dirname "$0")/.." && pwd)"
template="$root/Packaging/homebrew/$command_name.rb"
tap_repo="${TAP_REPO:-yahyabedirhan/homebrew-tap}"

if [ ! -f "$template" ]; then
    echo "::notice::no cask at Packaging/homebrew/$command_name.rb; the tap isn't updated for $command_name"
    exit 0
fi
printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || fail "'$version' isn't a version like 0.2.0"
printf '%s' "$sha256" | grep -Eq '^[0-9a-f]{64}$' || fail "'$sha256' isn't a SHA-256"

# The cask with this release's version and checksum.
fill() {
    sed -e "s/^  version \".*\"$/  version \"$version\"/" \
        -e "s/^  sha256 \".*\"$/  sha256 \"$sha256\"/" "$template"
}

if [ "$print_only" -eq 1 ]; then
    fill
    exit 0
fi

if [ -z "${TAP_TOKEN:-}" ]; then
    echo "::notice::TAP_TOKEN isn't set; the tap $tap_repo isn't updated"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The token goes in through git's credential header, never in the URL or the log.
auth="$(printf 'x-access-token:%s' "$TAP_TOKEN" | base64 | tr -d '\n')"
echo "::add-mask::$auth"
git -c "http.extraHeader=Authorization: Basic $auth" \
    clone --depth 1 "https://github.com/$tap_repo.git" "$work/tap"
mkdir -p "$work/tap/Casks"
fill > "$work/tap/Casks/$command_name.rb"

cd "$work/tap"
if git diff --quiet -- "Casks/$command_name.rb" && git ls-files --error-unmatch "Casks/$command_name.rb" >/dev/null 2>&1; then
    echo "the tap already has $command_name $version"
    exit 0
fi
git add "Casks/$command_name.rb"
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "$command_name $version"
git -c "http.extraHeader=Authorization: Basic $auth" push origin HEAD
echo "updated $tap_repo: $command_name $version"

#!/usr/bin/env bash
# Write the mate skill of a release into the skill's own repository.
#
#   scripts/update-mate.sh <version>              commit and push to the skill's repository
#   scripts/update-mate.sh <version> --dry-run    show what would change, commit nothing
#
# The skill is maintained here, in .agents/skills/havooch-mate. The skills CLI
# clones a repository source, and this repository is large, so the app and the
# installers install the skill from a repository of the skill alone. This
# script makes that repository's files the same as the skill here: SKILL.md,
# references/ and anything else in the skill's folder. A file the skill no
# longer has is removed. The repository's own README.md and LICENSE stay. The
# commit is "havooch-mate <version>", on main, with no tag.
#
# Environment: TAP_TOKEN, a token that can push to the skill's repository (the
# release workflow's token for the Homebrew tap, with this repository added to
# it); MATE_REPO, the skill's repository (default yahyabedirhan/havooch-mate).
# Without TAP_TOKEN the script skips with a notice, except in a dry run, which
# clones with git's own credentials.

set -euo pipefail

fail() { printf 'update-mate.sh: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || fail "usage: update-mate.sh <version> [--dry-run]"
version="$1"
dry_run=0
[ "${2:-}" = "--dry-run" ] && dry_run=1

root="$(cd "$(dirname "$0")/.." && pwd)"
skill_name="havooch-mate"
source_dir="$root/.agents/skills/$skill_name"
mate_repo="${MATE_REPO:-yahyabedirhan/havooch-mate}"
# The files of the skill's repository that are its own, not the skill's.
own_files=("README.md" "LICENSE")

printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$' || fail "'$version' isn't a version like 0.2.0"
[ -f "$source_dir/SKILL.md" ] || fail "no skill at .agents/skills/$skill_name/SKILL.md"

git_auth=()
if [ -n "${TAP_TOKEN:-}" ]; then
    # The token goes in through git's credential header, never in the URL or the log.
    auth="$(printf 'x-access-token:%s' "$TAP_TOKEN" | base64 | tr -d '\n')"
    echo "::add-mask::$auth"
    git_auth=(-c "http.extraHeader=Authorization: Basic $auth")
elif [ "$dry_run" -eq 0 ]; then
    echo "::notice::TAP_TOKEN isn't set; the skill's repository $mate_repo isn't updated"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git ${git_auth[@]+"${git_auth[@]}"} clone --quiet --depth 1 --branch main "https://github.com/$mate_repo.git" "$work/mate"

cd "$work/mate"
is_own() {
    local file
    for file in "${own_files[@]}"; do
        [ "$1" = "$file" ] && return 0
    done
    return 1
}

# Every tracked file that isn't the repository's own goes, then the skill's
# files come in: what the skill no longer has is removed.
git ls-files -z | while IFS= read -r -d '' path; do
    is_own "$path" || git rm --quiet -- "$path"
done
(cd "$source_dir" && find . -type f -print0) | while IFS= read -r -d '' path; do
    path="${path#./}"
    is_own "$path" && continue
    mkdir -p "$(dirname "$path")"
    cp "$source_dir/$path" "$path"
done
git add --all

if git diff --cached --quiet; then
    echo "$mate_repo already has $skill_name $version"
    exit 0
fi

if [ "$dry_run" -eq 1 ]; then
    echo "would commit \"$skill_name $version\" to $mate_repo:"
    git diff --cached --stat
    exit 0
fi

git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "$skill_name $version"
git "${git_auth[@]}" push --quiet origin HEAD:main
echo "updated $mate_repo: $skill_name $version"

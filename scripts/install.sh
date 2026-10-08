#!/usr/bin/env bash
# Install the app from its latest GitHub release: the app and a link to its
# command on PATH. The mate skill for coding agents only with --with-skill:
# people manage their skills their own way, and the app's Connect view
# installs it for the agent they pick.
#
#   curl -fsSL https://raw.githubusercontent.com/yahyabedirhan/havooch/main/scripts/install.sh | bash
#   bash install.sh [--app-dir <dir>] [--bin-dir <dir>] [--repo <owner/repo>]
#                   [--from <zip>] [--with-skill] [--uninstall]
#
#   --app-dir <dir>   where the app goes (default /Applications)
#   --bin-dir <dir>   where the command's link goes (default /usr/local/bin
#                     when writable, else ~/.local/bin)
#   --repo <o/r>      the GitHub repository of the releases (default
#                     $HAVOOCH_REPO, else yahyabedirhan/havooch); the skill
#                     comes from <o/r>-mate, a repository of the skill alone
#   --from <zip>      install this release zip instead of downloading one; a
#                     <zip>.sha256 beside it is checked
#   --with-skill      also install the mate skill for Claude Code, Codex,
#                     Cursor, Pi and OpenCode (or, with --uninstall, remove it)
#   --uninstall       remove the app and the command's link
#
# The app and command names come from the zip: the one .app at its top, and
# the one command in that app's Contents/Helpers. The mate skill is
# <command>-mate. An installed copy is recognised for --uninstall by its bundle
# id, com.<repository owner>.<command>.

set -euo pipefail

repo="${HAVOOCH_REPO:-yahyabedirhan/havooch}"
app_dir="/Applications"
bin_dir=""
from_zip=""
skill=0
uninstall=0
# The agents Havooch supports, by their names for `npx skills add -a`.
skill_agents=(claude-code codex cursor pi opencode)

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
    # Run from a file, the header above is the help; piped into bash, $0 is
    # bash itself.
    if [ -f "$0" ] && [ "$(head -c 2 "$0")" = "#!" ] && [ "$(basename "$0")" = "install.sh" ]; then
        sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    else
        say "usage: install.sh [--app-dir <dir>] [--bin-dir <dir>] [--repo <owner/repo>] [--from <zip>] [--with-skill] [--uninstall]"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app-dir) [ $# -ge 2 ] || fail "--app-dir needs a folder"; app_dir="$2"; shift 2 ;;
        --bin-dir) [ $# -ge 2 ] || fail "--bin-dir needs a folder"; bin_dir="$2"; shift 2 ;;
        --repo) [ $# -ge 2 ] || fail "--repo needs <owner/repo>"; repo="$2"; shift 2 ;;
        --from) [ $# -ge 2 ] || fail "--from needs a zip"; from_zip="$2"; shift 2 ;;
        --with-skill) skill=1; shift ;;
        --no-skill) skill=0; shift ;;  # the default; kept so older commands still run
        --uninstall) uninstall=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) fail "unknown option '$1' (see --help)" ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || fail "this app runs on macOS only"
case "$repo" in
    */*) owner="${repo%%/*}" ;;
    *) fail "--repo takes <owner/repo>, not '$repo'" ;;
esac
# Strip trailing slashes so the links and messages read cleanly.
app_dir="${app_dir%/}"
[ -n "$app_dir" ] || app_dir="/"

work="$(mktemp -d "${TMPDIR:-/tmp}/havooch-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The bundle id of the app at $1, or nothing.
bundle_id() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# The one regular file in the app's Contents/Helpers, by name, or nothing.
helper_name() {
    local found="" file
    for file in "$1/Contents/Helpers"/*; do
        [ -f "$file" ] && [ -x "$file" ] || continue
        [ -z "$found" ] || return 0
        found="$(basename "$file")"
    done
    printf '%s' "$found"
}

# The folder for the command's link when --bin-dir isn't given.
default_bin_dir() {
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        printf '/usr/local/bin'
    else
        printf '%s/.local/bin' "$HOME"
    fi
}

on_path() {
    case ":$PATH:" in *":$1:"*) return 0 ;; *) return 1 ;; esac
}

sha256_of() {
    shasum -a 256 "$1" | awk '{print $1}'
}

first_launch_note() {
    local app="$1"
    say ""
    say "First launch: the app is ad-hoc signed and not notarized by Apple."
    say "If macOS says it can't check the app for malicious software:"
    say "  1. Open System Settings > Privacy & Security."
    say "  2. Next to the message about $(basename "$app"), click Open Anyway, then confirm."
    say "Or clear the quarantine flag yourself:"
    say "  xattr -dr com.apple.quarantine \"$app\""
}

npx_skills() {
    if ! command -v npx >/dev/null 2>&1; then
        return 127
    fi
    # Standard input is this script under `curl | bash`: npx would read the
    # rest of it as its own input, and the script would end early.
    npx --yes skills "$@" </dev/null
}

# --- uninstall --------------------------------------------------------------

if [ "$uninstall" -eq 1 ]; then
    removed=0
    candidates=()
    if [ -n "$bin_dir" ]; then
        candidates=("${bin_dir%/}")
    else
        candidates=(/usr/local/bin "$HOME/.local/bin")
    fi
    for app in "$app_dir"/*.app; do
        [ -d "$app" ] || continue
        command_name="$(helper_name "$app")"
        [ -n "$command_name" ] || continue
        [ "$(bundle_id "$app")" = "com.$owner.$command_name" ] || continue
        if pgrep -f "^$app/Contents/MacOS/" >/dev/null 2>&1; then
            fail "$(basename "$app" .app) is running; quit it, then run --uninstall again"
        fi
        helper="$app/Contents/Helpers/$command_name"
        for dir in "${candidates[@]}"; do
            link="$dir/$command_name"
            if [ -L "$link" ] && [ "$(readlink "$link")" = "$helper" ]; then
                rm -f "$link"
                say "removed the link $link"
            fi
        done
        rm -rf "$app"
        say "removed $app"
        removed=$((removed + 1))
        if [ "$skill" -eq 1 ]; then
            if npx_skills remove "$command_name-mate" --global --yes >/dev/null 2>&1; then
                say "removed the $command_name-mate skill"
            else
                say "didn't remove the $command_name-mate skill; remove it with: npx skills remove $command_name-mate --global"
            fi
        fi
    done
    [ "$removed" -gt 0 ] || fail "found no app from $repo in $app_dir"
    say ""
    say "Your reviews and settings stay in ~/Library/Application Support/; delete that app's folder there to remove them too."
    exit 0
fi

# --- the release zip --------------------------------------------------------

if [ -n "$from_zip" ]; then
    [ -f "$from_zip" ] || fail "no zip at $from_zip"
    zip="$from_zip"
    if [ -f "$from_zip.sha256" ]; then
        expected="$(awk '{print $1; exit}' "$from_zip.sha256")"
    else
        expected=""
        say "no $from_zip.sha256 beside the zip; installing without a checksum"
    fi
else
    command -v curl >/dev/null 2>&1 || fail "curl is missing"
    api="https://api.github.com/repos/$repo/releases/latest"
    curl -fsSL -H "Accept: application/vnd.github+json" "$api" -o "$work/release.json" \
        || fail "couldn't read the latest release of $repo ($api); is the repository public and released?"
    urls="$(grep -o '"browser_download_url": *"[^"]*"' "$work/release.json" | sed 's/.*"\(https[^"]*\)"$/\1/')"
    zip_url="$(printf '%s\n' "$urls" | grep '\.zip$' | head -n 1 || true)"
    sha_url="$(printf '%s\n' "$urls" | grep '\.zip\.sha256$' | head -n 1 || true)"
    [ -n "$zip_url" ] || fail "the latest release of $repo has no .zip"
    [ -n "$sha_url" ] || fail "the latest release of $repo has no .zip.sha256"
    zip="$work/$(basename "$zip_url")"
    say "downloading $zip_url"
    curl -fsSL "$zip_url" -o "$zip" || fail "couldn't download $zip_url"
    curl -fsSL "$sha_url" -o "$work/release.sha256" || fail "couldn't download $sha_url"
    expected="$(awk '{print $1; exit}' "$work/release.sha256")"
fi

actual="$(sha256_of "$zip")"
if [ -n "$expected" ]; then
    [ "$actual" = "$expected" ] || fail "SHA-256 mismatch for $(basename "$zip"): expected $expected, got $actual"
    say "checked SHA-256 $actual"
fi

# --- unpack and read the names ----------------------------------------------

mkdir -p "$work/unpacked"
ditto -x -k "$zip" "$work/unpacked" || fail "couldn't unpack $zip"
apps=()
for app in "$work/unpacked"/*.app; do
    [ -d "$app" ] && apps+=("$app")
done
[ "${#apps[@]}" -eq 1 ] || fail "expected one .app at the top of the zip, found ${#apps[@]}"
source_app="${apps[0]}"
app_name="$(basename "$source_app")"
command_name="$(helper_name "$source_app")"
[ -n "$command_name" ] || fail "expected one command in $app_name/Contents/Helpers"
if [ "$(bundle_id "$source_app")" != "com.$owner.$command_name" ]; then
    say "note: the bundle id isn't com.$owner.$command_name; --uninstall won't find this copy"
fi

# --- install ----------------------------------------------------------------

[ -n "$bin_dir" ] || bin_dir="$(default_bin_dir)"
bin_dir="${bin_dir%/}"
target_app="$app_dir/$app_name"
link="$bin_dir/$command_name"
helper="$target_app/Contents/Helpers/$command_name"

mkdir -p "$app_dir" 2>/dev/null || true
[ -d "$app_dir" ] && [ -w "$app_dir" ] \
    || fail "can't write to $app_dir; pass --app-dir ~/Applications, or run with an admin account"
if [ -e "$link" ] && [ ! -L "$link" ]; then
    fail "$link exists and isn't a link; move it away or pass --bin-dir"
fi
if pgrep -f "^$target_app/Contents/MacOS/" >/dev/null 2>&1; then
    fail "${app_name%.app} is running; quit it, then run the installer again"
fi

if [ -d "$target_app" ]; then
    rm -rf "$target_app"
    say "replacing $target_app"
fi
ditto "$source_app" "$target_app"
say "installed $target_app"

mkdir -p "$bin_dir"
ln -sfn "$helper" "$link"
say "linked $link -> $helper"
on_path "$bin_dir" || say "note: $bin_dir isn't on your PATH; add it in your shell profile: export PATH=\"$bin_dir:\$PATH\""

if [ "$skill" -eq 1 ]; then
    skill_name="$command_name-mate"
    # A repository of the skill alone, which each release writes into: the
    # skills CLI clones a repository source, and the app's own is large.
    skill_repo="$repo-mate"
    if ! command -v npx >/dev/null 2>&1; then
        say "skipped the $skill_name skill: npx isn't installed (install Node.js, then: npx skills add $skill_repo --skill $skill_name --global)"
    elif npx_skills add "$skill_repo" --skill "$skill_name" --global --yes ${skill_agents[@]/#/-a }; then
        say "installed the $skill_name skill"
    else
        say "couldn't install the $skill_name skill; try: npx skills add $skill_repo --skill $skill_name --global"
    fi
fi

first_launch_note "$target_app"
say ""
say "Next: open ${app_name%.app}. It walks you through connecting your coding agent, step by step."
uninstall_hint="curl -fsSL https://raw.githubusercontent.com/$repo/main/scripts/install.sh | bash -s -- --uninstall"
[ "$app_dir" = "/Applications" ] || uninstall_hint="$uninstall_hint --app-dir \"$app_dir\""
uninstall_hint="$uninstall_hint --bin-dir \"$bin_dir\""
say "To remove it: $uninstall_hint"

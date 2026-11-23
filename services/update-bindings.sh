#!/usr/bin/env bash
# Inputs are data, not shell code. Replace only the file the user reviewed.
set -eu
path=$1
original=$2
updated=$3
fail() { printf '%s\n' "$*" >&2; exit 1; }
path=$(realpath -e -- "$path") || fail 'Bindings file not found.'
[[ -f $path ]] || fail 'Bindings file is not a regular file.'
exec {lock}>"$path.omaswitch.lock"
flock -n "$lock" || fail 'Another OmaSwitch binding change is running.'
cmp -s -- "$path" <(printf '%s' "$original") || fail 'Bindings changed on disk. Review them and try again.'
before=$(hyprctl configerrors) || fail 'Could not read current Hyprland configuration errors.'
backup=$(mktemp -- "$path.omaswitch-$(date +%Y%m%d-%H%M%S)-XXXXXX.bak")
cp -p -- "$path" "$backup" || fail 'Could not back up bindings. No changes made.'
cmp -s -- "$backup" <(printf '%s' "$original") || fail 'Bindings changed during setup. No changes made.'
stage=$(mktemp -- "$path.omaswitch-XXXXXX")
trap 'rm -f -- "$stage"' EXIT
cp -p -- "$backup" "$stage"
printf '%s' "$updated" > "$stage"
cmp -s -- "$path" "$backup" || fail 'Bindings changed during setup. No changes made.'
mv -fT -- "$stage" "$path"
if hyprctl reload >/dev/null && after=$(hyprctl configerrors); then
  errors=$(awk 'function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    FILENAME == ARGV[1] { seen[trim($0)] = 1; next }
    { line = trim($0); if (line != "" && !(line in seen)) print line }' \
    <(printf '%s\n' "$before") <(printf '%s\n' "$after")) || errors='Could not compare Hyprland configuration errors.'
  if [[ -z $errors ]]; then exit 0; fi
else
  errors='Could not reload or validate the Hyprland configuration.'
fi
cmp -s -- "$path" <(printf '%s' "$updated") || fail "Bindings changed after setup. Not overwriting them. Backup: $backup"
if ! cp -p -- "$backup" "$stage" || ! mv -fT -- "$stage" "$path"; then
  fail "Could not restore bindings. Restore this backup manually: $backup"
fi
hyprctl reload >/dev/null || fail "Bindings restored, but Hyprland could not reload. Backup: $backup"
fail "Hyprland rejected the new bindings, so OmaSwitch put your file back:
$errors"

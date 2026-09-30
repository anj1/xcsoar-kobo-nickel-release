#!/bin/sh
# Hash tracked and new files, including submodule contents and broken symlinks.
source_manifest()
{
  (cd "$1" &&
    git -c core.quotepath=false ls-files --cached --others --exclude-standard |
    LC_ALL=C sort -u |
    while IFS= read -r manifest_file; do
      if [ -L "$manifest_file" ]; then
        printf 'symlink %s -> %s\n' "$manifest_file" "$(readlink "$manifest_file")"
      elif [ -f "$manifest_file" ]; then
        sha256sum "$manifest_file"
      elif [ -d "$manifest_file" ]; then
        printf 'submodule %s %s\n' "$manifest_file" \
          "$(git ls-files --stage -- "$manifest_file" | awk '$1 == 160000 { print $2 }')"
        if [ -e "$manifest_file/.git" ]; then
          source_manifest "$manifest_file" || exit 1
        fi
      else
        printf 'missing %s\n' "$manifest_file"
      fi
    done)
}

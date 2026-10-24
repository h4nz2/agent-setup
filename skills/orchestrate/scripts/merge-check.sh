#!/usr/bin/env bash
# Show which files would conflict, without touching any working tree or index:
#   1. each branch merged into the target (default: main)
#   2. each pair of branches merged into each other
# (git merge-tree writes the merged trees as loose objects into .git/objects; harmless, gc removes them.)
# Usage: merge-check.sh [-t <target>] <branch> [<branch>...]
# Run it from inside the repository. Needs git >= 2.38 (merge-tree --write-tree).
# Exit status: 0 = all clean, 1 = at least one conflict, 2 = usage or git error.
set -uo pipefail

target=main
if [[ "${1:-}" == "-t" ]]; then target=${2:?missing target}; shift 2; fi
if [[ $# -lt 1 ]]; then
	echo "usage: $0 [-t <target>] <branch> [<branch>...]" >&2
	exit 2
fi

# A mistyped ref must not read as "clean".
for ref in "$target" "$@"; do
	if ! git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
		echo "unknown branch or commit: $ref" >&2
		exit 2
	fi
done

any_conflict=0

report() {
	local out status
	out=$(git merge-tree --write-tree --name-only "$1" "$2" 2>&1)
	status=$?
	case $status in
	0) echo "  clean" ;;
	1)
		any_conflict=1
		# first line is the tree id; then one conflicted path per line until a blank line, then messages
		sed -n '2,/^$/p' <<<"$out" | sed '/^$/d; s/^/  CONFLICT /'
		;;
	*)
		echo "  ERROR (git merge-tree exit $status):" >&2
		sed 's/^/    /' <<<"$out" >&2
		exit 2
		;;
	esac
}

echo "# into $target"
for b in "$@"; do
	echo "$b"
	report "$target" "$b"
done

if [[ $# -gt 1 ]]; then
	echo
	echo "# between branches"
	branches=("$@")
	for ((i = 0; i < ${#branches[@]}; i++)); do
		for ((j = i + 1; j < ${#branches[@]}; j++)); do
			echo "${branches[i]} x ${branches[j]}"
			report "${branches[i]}" "${branches[j]}"
		done
	done
fi

exit $any_conflict

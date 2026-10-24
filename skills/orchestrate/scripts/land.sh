#!/usr/bin/env bash
# Land one finished branch on the target (default: main) in one call, printing only a few lines:
#   1. WIP-commit leftovers in the worktree, then squash the branch into one commit with your message,
#      on its merge-base with the target (so "merge main" commits the agent made disappear into it);
#   2. trial-merge it into the target in the main checkout (--no-ff --no-commit);
#   3. run the test command on the merged tree;
#   4. commit the merge only when the tests pass.
# On a conflict, failing tests or a failing hook it aborts and the target stays as it was. With -k, a
# conflicted merge is left in progress for you to resolve; then run it again with --finish.
# Full output of every step goes to $LAND_LOGS/<branch>/ (default: ${TMPDIR:-/tmp}/land-logs).
#
# Usage, from the main checkout:
#   land.sh [-k] [-t <target>] <worktree> <commit-msg-file> "<merge message>" -- <test command...>
#   land.sh --finish [-t <target>] "<merge message>" -- <test command...>
# Exit status: 0 = merged (or already merged), 1 = needs you (see output), 2 = refused (usage, state, git error).
set -uo pipefail

usage() {
	sed -n '13,14p' "$0" | sed 's/^#  */usage: /' >&2
	exit 2
}
die() {
	echo "REFUSED: $*" >&2
	exit 2
}

keep=0 finish=0 target=main
while [[ $# -gt 0 ]]; do
	case $1 in
	-k) keep=1 && shift ;;
	-t) target=${2:-} && shift 2 ;;
	--finish) finish=1 && shift ;;
	*) break ;;
	esac
done
[[ -n $target ]] || usage
if ((finish)); then
	[[ $# -ge 3 && $2 == -- ]] || usage
	merge_msg=$1
	shift 2
else
	[[ $# -ge 5 && $4 == -- ]] || usage
	wt=$1 msg_file=$2 merge_msg=$3
	shift 4
fi
test_cmd=("$@")

repo=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
dirs=$(git -C "$repo" rev-parse --path-format=absolute --git-dir --git-common-dir)
[[ $(sed -n 1p <<<"$dirs") == $(sed -n 2p <<<"$dirs") ]] || die "run it from the main checkout, not from a worktree"
[[ $(git -C "$repo" branch --show-current) == "$target" ]] || die "$repo is not on $target"
log_root=${LAND_LOGS:-${TMPDIR:-/tmp}/land-logs}

# Run the tests on the merged tree and commit the merge, or abort it.
test_and_commit() {
	local log=$1
	if ! (cd "$repo" && "${test_cmd[@]}") >"$log/tests.log" 2>&1; then
		echo "TESTS FAILED on the merged tree; merge aborted, $target unchanged. Log: $log/tests.log"
		grep -E 'FAIL|✗|×|[0-9]+ failed|Error:' "$log/tests.log" | head -20
		tail -4 "$log/tests.log"
		git -C "$repo" merge --abort
		exit 1
	fi
	if ! git -C "$repo" commit -q -m "$merge_msg" >"$log/merge-commit.log" 2>&1; then
		echo "MERGE COMMIT FAILED (hook?); merge aborted, $target unchanged. Log: $log/merge-commit.log"
		tail -15 "$log/merge-commit.log"
		git -C "$repo" merge --abort
		exit 1
	fi
	echo "MERGED $(git -C "$repo" log -1 --format='%h %s')"
	exit 0
}

if ((finish)); then
	git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null || die "no merge in progress in $repo"
	unresolved=$(git -C "$repo" diff --name-only --diff-filter=U)
	[[ -z $unresolved ]] || die "still unresolved: $(tr '\n' ' ' <<<"$unresolved")"
	markers=$(cd "$repo" && git diff --cached --name-only --diff-filter=d -z | xargs -0 -r grep -lE '^(<<<<<<<|>>>>>>>)( |$)' --)
	[[ -z $markers ]] || die "conflict markers left in: $(tr '\n' ' ' <<<"$markers")"
	branch=$(git -C "$repo" for-each-ref --points-at MERGE_HEAD --format='%(refname:short)' refs/heads | head -1)
	log="$log_root/${branch:-finish}"
	mkdir -p "$log" || die "cannot create $log"
	test_and_commit "$log"
fi

[[ -d $wt ]] || die "no worktree at $wt"
[[ -f $msg_file ]] || die "no commit message file at $msg_file"
branch=$(git -C "$wt" branch --show-current)
[[ -n $branch ]] || die "$wt has no branch checked out"
log="$log_root/$branch"
mkdir -p "$log" || die "cannot create $log"
[[ -z $(git -C "$repo" status --porcelain --untracked-files=no) ]] || die "$repo has uncommitted changes; not merging into them"
! git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null || die "a merge is already in progress in $repo"

# 1. Leftovers, then one clean commit on the merge-base.
if [[ -n $(git -C "$wt" status --porcelain) ]]; then
	if ! { git -C "$wt" add -A && git -C "$wt" commit -q --no-verify -m "wip: leftovers before landing"; } >"$log/wip.log" 2>&1; then
		echo "WIP COMMIT FAILED in $wt. Log: $log/wip.log"
		tail -5 "$log/wip.log"
		exit 1
	fi
fi
if git -C "$repo" merge-base --is-ancestor "$branch" "$target"; then
	echo "ALREADY MERGED: $branch has nothing that $target lacks"
	exit 0
fi
base=$(git -C "$repo" merge-base "$target" "$branch") || die "$target and $branch have no merge base"
git -C "$wt" reset -q --soft "$base" || die "git reset --soft failed in $wt"
if ! git -C "$wt" commit -q -F "$msg_file" >"$log/commit.log" 2>&1; then
	echo "COMMIT FAILED in $wt (pre-commit hook?); the change is staged there, nothing is lost. Log: $log/commit.log"
	tail -15 "$log/commit.log"
	exit 1
fi
echo "squashed: $(git -C "$wt" log -1 --format='%h %s') ($(git -C "$wt" diff --shortstat HEAD~1 HEAD | sed 's/^ //'))"

# 2. Trial merge.
git -C "$repo" merge --no-ff --no-commit "$branch" >"$log/merge.log" 2>&1
status=$?
conflicts=$(git -C "$repo" diff --name-only --diff-filter=U)
if [[ -n $conflicts ]]; then
	echo "CONFLICT merging $branch into $target:"
	while IFS= read -r f; do
		n=$(grep -c '^<<<<<<<' "$repo/$f" 2>/dev/null)
		echo "  $f (${n:-?} hunks)"
	done <<<"$conflicts"
	if ((keep)); then
		echo "Merge left in progress in $repo. Resolve, git add, then: $0 --finish -t $target $(printf '%q ' "$merge_msg") -- $(printf '%q ' "${test_cmd[@]}")"
	else
		git -C "$repo" merge --abort
		echo "Merge aborted; $target unchanged. The squashed commit stays on $branch."
	fi
	exit 1
fi
if ((status != 0)); then
	echo "MERGE FAILED without conflicts (exit $status). Log: $log/merge.log"
	tail -10 "$log/merge.log"
	! git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null || git -C "$repo" merge --abort
	exit 2
fi

# 3. and 4.
test_and_commit "$log"

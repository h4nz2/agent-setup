# Screenshots on issues

`gh` cannot upload images. Publish them on a branch of their own, `issue-assets`, and link the raw URLs:

```bash
if git ls-remote --exit-code --heads origin issue-assets >/dev/null; then
	git fetch origin issue-assets && git worktree add <scratch>/issue-assets issue-assets
else
	git worktree add --orphan -b issue-assets <scratch>/issue-assets   # --orphan needs git >= 2.42
fi
# copy PNGs into <scratch>/issue-assets/issue-<n>/, then:
git -C <scratch>/issue-assets add -A
git -C <scratch>/issue-assets commit --no-verify -m "chore(assets): #<n> screenshots"
git -C <scratch>/issue-assets push origin issue-assets
# link: https://raw.githubusercontent.com/<owner>/<repo>/issue-assets/issue-<n>/<file>.png
```

- Pushing a branch is outward-facing. Say in your plan message that you'll do it.
- Check that the repo is public: raw links on a private repo don't render for everyone.
- Check that one URL returns 200 before posting the comment.
- Pick one or two screenshots per issue: the hero shot, and before/after when the issue is about wrong-looking
  output. You don't need to look at every screenshot yourself; the reviewer does (see `prompts.md`, "Reviewer").

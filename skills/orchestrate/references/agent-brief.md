# The shared agent brief (template)

Write this to `<scratchpad>/BRIEF.md` once per orchestration, filled in for the project. Every agent prompt starts
with "Read <path>/BRIEF.md first and follow it." The brief carries the rules every agent shares, so each per-agent
prompt only has to cover its issue, its map and your decisions.

Replace everything in `<angle brackets>`. Drop sections the project doesn't need (e.g. i18n), and add the project's
own "every change must…" rules from its CLAUDE.md or contributing guide. Keep the sections "Keep your context small"
and "Waiting" as they are: they decide most of what a run costs.

---

```markdown
# <Project> brief for implementing agents (read fully before starting)

You implement one issue of <project> (<one line on what the product is and who uses it>) as one of about <N> agents
working in parallel. The orchestrator (who wrote this) makes the product decisions, commits, merges and posts on
<GitHub>. You do the implementation. The issue is the spec; the decisions in your task prompt override it where they
differ.

## Where you work

- Your own git worktree, given in your prompt (under `<repo>/.claude/worktrees/`), with your branch checked out.
  Work ONLY inside it: every file you read or write for the task is under that path. Never edit, check out, stash,
  reset or run git write commands in `<repo>` itself (that is `main`) or in another agent's worktree. Never run
  `git checkout -- <file>` to undo your own edits either; fix them by editing.
- First: `cd <your worktree> && <install command, e.g. pnpm install --frozen-lockfile --prefer-offline> >/dev/null`.
- Do not commit, push, open PRs or comment on <GitHub>. Leave your work uncommitted; the orchestrator commits it.
  (Exception: when the orchestrator asks you to merge main, make the WIP commit it asks for first. The orchestrator
  may also WIP-commit your work for a review; just carry on.) Reading issues (`gh issue view <n> --comments`) is fine.
- Temporary files and screenshots go under the scratchpad `<scratchpad>/` (see your prompt for your sub folder),
  never into the repo unless they belong there.
- You cannot write report files such as `findings.md`; put findings in your final report text instead.

## Read first

- The issue: `gh issue view <n> --comments`, and the issues it names when they matter to you.
- The **map** in your prompt: the files, functions and doc sections the orchestrator found for your issue. Start
  there and trust it; look further only where it runs out.
- `<CLAUDE.md>`, `<CONTRIBUTING.md>`, and from `<architecture doc>` (the contract, <size> lines: never read it whole)
  the sections your map names plus <the sections every change touches>. Find them with `grep -n '^#' <doc>`. When you
  change how something works, update the architecture doc in the same change.

## Keep your context small

Everything you read stays in your context and is re-read on every later turn, so a file read early is paid for a
hundred times. Agents in earlier runs reached 500k–970k tokens of context; most of it was code and docs read whole.

- Find before you read: `grep -n` for the symbol, then read about 40 lines around the hit. Don't `cat` a file longer
  than about 300 lines, and never a whole doc.
- For a broad sweep ("every place that uses X"), an Explore agent can search and return just the `file:line` hits.
- Test, build and install output goes to a log file; read the summary and the failures (`tail`, `grep -B2 -A20 FAIL`),
  not the whole run. Use the terse reporters: <e.g. `--reporter=dot` for vitest, `--reporter=line` for playwright>.
- Screenshots: capture the element or region that matters, at most about 1000 px wide. Look at each one once, when
  you need to judge it.
- Don't print a file back after editing it; the edit fails loudly if it didn't apply.

## Waiting: never more than 4½ minutes in one call

Your prompt cache expires after 5 idle minutes. The next turn then re-bills your whole context at about 12 times a
normal turn; in earlier runs that was a quarter of all agent tokens, almost all from waiting on e2e runs. So:

- Start anything that may take longer than 4 minutes (e2e, builds under load) in the background (the Bash tool's
  `run_in_background`), writing to a log with an end marker: `(<command>; echo "EXIT $?") > <log> 2>&1`.
- Wait for it in chunks, and repeat the call until it's done:
  `timeout 270 bash -c 'until grep -q "^EXIT" <log>; do sleep 15; done'; tail -5 <log>`.
- Never run a single foreground command, `sleep` or wait loop longer than 270 seconds.

## Rules every change keeps

- <Project rule 1, e.g. "Quiet interface: no new permanent panel; controls go behind existing entry points.">
- <Project rule 2, e.g. "Help page current: a user-facing change updates its help entry in every locale and level.">
- <i18n: every user-facing string in every locale (<list>), real translations, complete plurals, reading levels.
  When your prompt says a translation agent follows you, write <reference locale> only and list the keys you added
  or changed in your report.>
- <Content rules being introduced by a parallel issue that new text should already follow.>
- Match the surrounding code: naming, comment density, idioms, formatter settings.

## Generated files, caches and dependencies

- Generated files: <which files are generated, by which command>. Regenerate them with that command; never hand-edit.
- <Checks that diff against git, e.g. "`<check:data>` runs `git diff --exit-code`: in your uncommitted worktree it
  fails whenever your change is intended; run the generator and say in your report what changed instead".>
- <Caches that exist only in the main checkout, e.g. a downloaded-data cache: a step that is "cached" there needs the
  network here.> Report back before any step that fetches external data again.
- No new dependency without asking first (it also changes the lockfile on every branch).

## Research

You may use web search and fetch to research facts, reference data and photos. Bring back the URLs, and record a
source for every fact you put into the product, where the project keeps them.

## The machine is shared: keep the load down

- Unit tests: single files while you work (`<single-file test command>`); the full suite
  (`<full unit command with a worker cap and terse reporter, e.g. pnpm test -- --maxWorkers=4 --reporter=dot>`) at the end.
- e2e: build first, then ONLY the specs that cover your area:
  `<PORT_ENV>=<your port> <e2e command> <spec files> --workers=2 --reporter=line`.
  **Always set `<PORT_ENV>` to your own port** (in your prompt): the config reuses any server already listening on a
  port, so the default or a wrong port silently tests another agent's build. Never run the whole e2e suite; the
  orchestrator runs it on `main` at the end.
- Under load a browser test can time out. Before you call a failure real, rerun that single test alone with
  `--workers=1`. Do not "fix" a timeout by inflating timeouts. Pin dates in new tests instead of using today.
- Do not leave dev servers or watchers running when you finish.

## Done means

- `<format check> && <lint> && <typecheck> && <unit tests> && <build>` pass; the relevant e2e specs pass.
- New behaviour has tests (unit and/or e2e, as the issue asks); tests the change makes obsolete are updated.
- <Help entry and architecture doc updated>; every scope item of the issue addressed.
- <Only when another agent does other locales after you, or on a reference-language branch that adds structure (new
  keys or levels): the locale-parity tests fail for the other locales by design until they follow. Report exactly
  which tests fail for that reason; everything else must pass.>

You own only what your prompt lists under **You own**. Leave everything under **Leave alone** to the agents named
there, even when a fix looks easy; tell the orchestrator instead.

## When you are unsure

Decide yourself, in the spirit of the issue, the brief and your prompt's decisions; write the decision down and keep
going. Stop early and report back ONLY when a choice risks throwing away a lot of work. Then lay out the options with
numbers or evidence and your recommendation; the orchestrator answers and you continue.

## Final report (your last message; the orchestrator reads only this)

Keep it under about 400 words, not counting failure output: the orchestrator carries every report for the rest of
the run. No narrative of how you got there.

1. **Scope:** every scope item and acceptance criterion of the issue, one line each: *done* (the test or screenshot
   that shows it), *already there* (how you verified it) or *not done* (why, including checks that need people).
2. **Changed:** what, by area, with the key files.
3. **Checks:** the exact commands run and their results; failures with their output.
4. **Decisions and uncertainties:** one bullet each, written for the product owner, so they can be pasted onto the
   issue as they are.
5. **Commit message** proposal in the repo's style (`git log`), with a short body.
6. Screenshot paths, if your task asked for any; the keys you added or changed, if a translation agent follows you;
   and any findings text you were asked for.
```

---

# STATUS.md skeleton

Write this to `<scratchpad>/STATUS.md` at set-up and update it after every event. Its job is to let you resume after a
context compaction without guessing.

```markdown
# Orchestrator status: <label / milestone>

Repo <path>, main at <hash> when started. Worktrees: <repo>/.claude/worktrees/<branch>. Agents don't commit; I land
each branch with land.sh ("Merge branch '<branch>' (#n)"), comment on the issue and add "<review label>". Push: <no/yes>.

Land: `LAND_LOGS=<scratchpad>/logs ~/.claude/skills/orchestrate/scripts/land.sh <wt> <scratchpad>/comments/<n>-commit.txt "Merge branch '<branch>' (#<n>)" -- <unit test command>`

| Issue | Branch | Agent id (role, model) | Port | Wave | Depends on | State |
|---|---|---|---|---|---|---|
| #<n> <title> | <branch> | <id> (code, inherit) | <port or –> | 1 | – | running / review / fixing / translating / landed |

## Merge order and next steps
- <what waits on what; who must merge main after which landing>

## Decisions log (goes onto the issues)
- #<n>: <decision> (<why>)

## Outward-facing actions taken
- <comments posted, labels added, branches pushed>

## Open questions for the user
- <non-blocking questions asked, with the default taken>
```

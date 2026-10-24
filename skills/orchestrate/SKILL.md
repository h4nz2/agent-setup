---
name: orchestrate
description: >
  Orchestrate the implementation of several issues at once by managing a team of
  subagents: read the issues, work out dependencies and file overlaps, plan waves,
  run as many in parallel as is safe (one git worktree per issue), decide the
  agents' open questions, review, commit, merge into main, run a final integration
  pass, and report every decision and uncertainty on the issues for later review.
  The orchestrator does not implement anything itself. Use this whenever the user
  asks to implement, work through or "handle" a set of issues: a phase, a label, a
  milestone, an epic, "all open bugs", a list like "#12 #14 #19", or says
  "orchestrate", "run the subagents", "in parallel", "manage the agents" or "fan
  out". Also use it when one issue is big enough to split across several agents.
  Not for a single small fix that one agent or a direct edit can do.
argument-hint: "<label | milestone | issue numbers> [plan] [push]"
---

# Orchestrate

You are the orchestrator. Subagents do the heavy lifting. You plan, decide, commit, merge, verify and report. You
don't write feature code yourself. The one exception: a merge conflict where both sides only *added* text to docs or
locale/data files (two new sections in the architecture doc, new keys in the same `help.json`) you resolve yourself,
keeping both. Every other conflict goes back to the agent that has the context. The user usually reviews afterwards
on the tracker, so every decision you make for them has to end up written on the issue it belongs to.

This workflow was distilled from three real runs (up to 31 agents) and their transcripts. Items marked *(happened)*
are failures that really happened.

**Arguments:**
- `plan`: stop after the plan message and wait for the user's go.
- `push`: push `main` at the end.
- Without them: plan, then go; merge locally, push nothing but issue screenshots.

**Tone:** issue comments, commit messages and labels are public and permanent. Write them plainly and
professionally, whatever persona or jokes the chat uses.

## What a run costs, and the rules that follow

Measured on those runs: the subagents are 86–94% of the tokens, you are the rest, and this skill's text is about
0.1%. An agent re-reads its whole context on every turn, so its cost grows much faster than its length; the heavy
ones reached 200–350 turns and 500k–970k tokens of context, most of it code and docs they had read.

- **One fresh agent per issue, with a map.** Never hand a finished agent the next issue *(happened: one started its
  second issue at 478k context and cost about 3× what a fresh agent would)*. Give each agent the files, functions and
  doc sections you found while planning, so it doesn't explore again.
- **No agent sits idle for 5 minutes.** Its prompt cache expires and the next turn re-bills its whole context at
  about 12× a normal turn *(happened: a quarter of all agent tokens in one run, from 10-minute waits on e2e)*. The
  brief makes agents wait in chunks of at most 4½ minutes. Resuming a finished agent always pays this, so each one
  gets **one** combined follow-up, never a trickle.
- **Light work goes to a lighter model.** Translation, prose and web-research agents run with `model: "sonnet"`.
  Code, review and integration agents inherit your model.
- **Keep your own context lean.** It lives longest, and after each idle hour of waiting for agents it is re-billed in
  full. Noisy output (tests, hooks, installs, `gh` JSON) goes to a file and you read the summary; `scripts/land.sh`
  does this for merges. Don't read an agent's transcript or output file while it runs; wait for its report.

## 0. Set up

1. **Find the issues.** Use the argument (a label, a milestone or numbers).
   - Take open issues **without** the review label (e.g. `ready for review`). Labelled ones are finished work waiting
     for the owner; list them and skip them unless the user says otherwise.
   - Read every issue in full, including comments, in one call saved to the scratchpad, e.g.
     `gh issue list --label <x> --state open --json number,title,body,comments,labels > <scratchpad>/issues.json`,
     and read it from there.
   - If the issues live elsewhere (GitLab, Trello, a list in a file), use that tool or CLI instead. The workflow stays
     the same.
2. **Learn the project's rules.** Read `CLAUDE.md`, `CONTRIBUTING.md`, the build scripts, and the architecture doc
   by its headings (`grep -n '^#'`) before reading the sections you need. Look for:
   - commit and branch conventions (`git log --oneline --graph -40` shows how branches were merged before);
   - who is allowed to commit;
   - required checks, pre-commit hooks, e2e setup (ports, `reuseExistingServer`) and the test runners' terse
     reporters;
   - generated files, checks that diff against git (e.g. "`git diff --exit-code` on generated data"), and build
     caches that live only in the main checkout;
   - i18n and help-page rules, and anything "every change must…".
3. **Check the ground you merge on.** `git status` in the main checkout must be clean: you trial-merge there. If it
   isn't, stop and tell the user instead of merging into their changes. `land.sh` checks again before every merge.
4. **Check the machine and the tools.**
   - `nproc` and `free -g`: the number of agents you can run at once is limited by test load (browsers, builds), not
     by tokens.
   - Make sure the commands agents need (package manager, `git -C`, the test runner, `gh` read commands) won't stop
     at a permission prompt. A background agent waiting on a prompt nobody sees stalls silently.
   - If `SendMessage` is a deferred tool, load it now with ToolSearch. You'll need it for rulings and follow-ups.
5. **Create the scratchpad files** in the session scratchpad:
   - `BRIEF.md`: the shared rules every agent reads first. Fill the template in `references/agent-brief.md` with
     this project's commands, rules and paths.
   - `STATUS.md`: your own state, so you can pick up after a context compaction without guessing. Use the skeleton in
     `references/agent-brief.md`, including the exact `land.sh` command line, and update it after every event.
   - `comments/`: per issue, the comment draft (`<n>.md`), the commit message (`<n>-commit.txt`) and `<n>-notes.md`,
     seeded at launch with the decisions in that agent's prompt and extended as reports arrive.
   - `reports/`: each agent's final report, saved as it arrives (`<n>.md`, `<n>-review.md`); the reviewer reads it.
   - `logs/`: for `land.sh` (`LAND_LOGS`) and your own test runs.

## 1. Plan the waves

For each issue, note:
- its **dependencies**: "builds on", "after", "before", "pairs with", "touches";
- the **files and areas it will likely touch**: store, camera, a shared JSON, locale files, the architecture doc;
- its **map**: those files with the functions and line numbers that matter, the doc sections by heading, and the
  scope items already done (where). It goes into the prompt;
- its **size** (S/M/L), and how many user-facing strings it adds.

Reading the architecture doc and grepping for these overlaps takes the most time, and it is where most of the value
is: it decides the waves, the ownership and the map.

Check two things before deciding:
- **Scope against the current code.** Some scope items are often already done by earlier work. Tell the agent which
  ones only need verifying, so it doesn't rebuild them or edit files another agent owns.
- **Shared vocabulary across issues.** Two issues may use the same word for different things ("an orange" as Earth
  in one issue, as the Sun in another), or refer to something that doesn't exist ("the grand tour's scale stop").
  Fix one meaning up front, in every affected prompt.

Then decide:

- **Parallel by default.** Start everything whose dependency is only *a rule written in an issue*. For example, "the
  simple level must have no number above 100" can be followed before the code that enforces it exists. Tell the
  agent about the parallel work and reconcile at merge time. Hold back only issues that truly need another's
  *code*. Examples: following a craft needs the fixed flyby paths; a Back button for following needs Back.
- **Split by file ownership, not only by issue.** When two issues would both rewrite the same file, give that file
  to one of them and tell the other to leave it alone. For example, the hunt issue owned `hunts.json` in every
  locale, and the reading-level issue skipped it. Ownership goes into every prompt as **You own / Leave alone**.
- **Keep each agent's job short.** An agent that would need more than about 150 turns gets its job split.
  - **Other locales go to a translation stage.** When an issue adds more than a handful of user-facing strings, the
    code agent writes the reference locale only and lists its new keys. After review, a light agent in the same
    worktree brings every other locale and reading level up (template in `references/prompts.md`). The code agent's
    parity tests fail until then, by design; the brief's "Done means" covers that.
  - **Huge content** (from roughly a hundred strings per language): reference language first, then one light agent
    per other language in parallel, each on its own branch off the reference branch; see "Split work" in
    `references/prompts.md`. Never land a reference branch that adds structure (new keys or levels) on main alone:
    the locale-parity tests stop it *(happened)*. Merge the languages into it first.
- **Start research-heavy work early** when it doesn't depend on code. Research agents are light agents.
- **Cap concurrency in two classes.**
  - *Heavy* agents build and run browser tests: about 10 on 16 cores was workable with the brief's load rules. More
    of them slows every test run for all.
  - *Light* agents (translation, content, research, review) cost a fraction of that.
  - Queue the rest, and start each one as a slot or its dependency frees up.

**The plan message.** Show the plan in one short message:
- the waves, and why;
- the cross-cutting decisions;
- one line per issue (size, agents and their model).

The full per-issue decisions live in the prompts and the notes files. If the user's instructions ask you to ask
questions, put them at the end of this message as non-blocking ones, each with the default you go ahead with. If
they say they'll review on GitHub, one such question is whether to push `main` at the end (the default stays no).
If you'll post screenshots, say so: it pushes a branch (`references/screenshots.md`). Then start, unless the user
passed `plan` or asked to review the plan first. They asked you to orchestrate.

## 2. Launch agents

1. **Create the worktrees yourself**, so you control branch names and paths:
   ```bash
   grep -qxF '.claude/worktrees/' .git/info/exclude || echo '.claude/worktrees/' >> .git/info/exclude
   git worktree add -q .claude/worktrees/<branch> -b <branch> main
   ```
   - Name branches after the repo's convention (e.g. `issue-<n>-<slug>`).
   - Check that the project's lint, format, typecheck and test globs ignore `.claude/` (ESLint/Prettier ignores,
     `tsconfig` `include`, vitest `include`). If they don't, put the worktrees outside the repo.
   - From here on use `git -C <path>` and absolute paths: `cd` into a worktree changes your working directory for
     later commands *(happened)*.
2. **Give every agent that runs e2e its own test port**, e.g. `4200 + (n mod 800)` for issue n, with split agents of
   the same issue in steps of +100. Test runners that reuse an existing server silently test another agent's build
   on a shared port. Content-only agents get none.
3. **Write each prompt with `references/prompts.md`:**
   - the brief path, the issue, the worktree, the branch, the port and a screenshots folder;
   - **the map**;
   - **You own / Leave alone**, and whether a translation stage follows;
   - **your decisions up front** for every ambiguity you can see in the issue: naming, defaults, placement,
     keyboard keys, what counts as what;
   - **who else is working nearby**, and what they'll deliver.
4. **Launch a wave as several Agent calls in one message.**
   - Use `subagent_type: "general-purpose"`: agents need Bash, Edit and the web.
   - Light agents (translation, prose, research) get `model: "sonnet"`; code and integration agents get no `model`.
   - Run them in the background.
   - Don't pass `isolation: "worktree"`: you created the worktree, and isolation would put the agent in a second,
     auto-named one.
5. **Record every agent id, role and model in STATUS.md** (you need the id for `SendMessage`), and seed
   `comments/<n>-notes.md` with the decisions you just gave.

## 3. While they work

- **Early report-backs.** The brief tells agents to stop only when a choice risks a lot of wasted work.
  - When one does, decide quickly and resume it with `SendMessage`.
  - Prefer the option that meets the issue's acceptance criteria. When the criteria themselves conflict, pick the
    one closest to the issue's stated purpose, put the trade-off first in the issue comment and list the levers to
    change it *(happened: five captions, each held for 3.5 s plus time per word, could not fit the issue's 30 s
    budget; a 12 px Earth and the old moon-spacing test couldn't both hold)*.
  - Don't ask the user. They delegated these calls.
- **When something lands on main that a running agent depends on,** tell that agent with `SendMessage` (it is
  queued for its next tool round). Say what landed, what it changes for them, and that they should merge main
  before reporting.
- **Relay facts between agents** when one agent's result changes another's work. For example, the English rewrite
  chose an "if Earth were an orange" scale, so the code agent's helpers had to use the same scale.
- **Approve or refuse network and dependency requests.** Agents report back before re-fetching external data, and
  before adding a dependency (which also touches the lockfile on every branch).
- If an agent mentions running `git checkout --`, `stash` or other git writes, or spawning helpers that do, remind
  it of the brief *(happened)*.

## 4. Take in a finished agent

The order for each issue: check the report → review → one combined follow-up → translation stage → land → comment.

1. **Save the report** to `reports/<n>.md` and **read it critically.** Every scope item must have a line under
   *Scope* with its evidence; push back on gaps (in the combined follow-up). If the report says the agent's own
   background work may still be running, check the worktree for live processes before going on.
2. **Review** every M and L issue, and an S issue that touches shared core code. WIP-commit the worktree, then launch
   a reviewer (template in `references/prompts.md`): it sees only the diff, the issue, your notes, the report and
   the screenshots, and returns at most 10 ranked findings. It also looks at the screenshots, so you need only the
   one or two you post. Judge each finding: accept it, reject it (note why in `<n>-notes.md`), or decide it. Take
   in other reports while it runs.
3. **One combined follow-up**, only if something needs fixing: accepted findings, missing scope, your overrides of
   its decisions, and "merge main" if its branch conflicts (template in `references/prompts.md`). Run
   `scripts/merge-check.sh <branch>` first, so a conflict rides along in the same message. If the fixes are large,
   consider a second short review.
4. **Translation stage**, if planned: launch the light agent in the same worktree now, so it translates final text.
5. **Decide what's open.** Accept the agents' decisions or override them, and append them to `comments/<n>-notes.md`.
6. **Land it.** Write the commit message to `comments/<n>-commit.txt` (the agent's proposal in the repo's style, plus
   any trailer the environment asks for), then from the main checkout:
   ```bash
   LAND_LOGS=<scratchpad>/logs ~/.claude/skills/orchestrate/scripts/land.sh \
     <worktree> <scratchpad>/comments/<n>-commit.txt "Merge branch '<branch>' (#<n>)" -- <unit test command>
   ```
   It WIP-commits leftovers, squashes the branch into one commit on its merge-base with main (an agent's earlier
   main merges disappear into it), trial-merges with `--no-ff`, runs the unit tests on the merged tree, and commits
   the merge only when they pass. It prints a few lines and keeps the full output in the log folder. Exit 0 =
   merged, 1 = needs you, 2 = refused (dirty main, bad arguments). Use a long timeout: hooks are slow under load.
   - **Conflicts** (it lists each file with its number of conflict hunks and aborts). Before landing several
     branches, `scripts/merge-check.sh [-t main] <branches…>` shows conflicts against main and between them without
     touching any tree; land in the order that causes the fewest rounds.
     - *Only additions on both sides, in docs or locale/data files:* rerun with `-k`, which leaves the merge in
       progress. Read just the conflict hunks, keep both sides, `git add`, then
       `land.sh --finish "<merge message>" -- <unit test command>`.
     - *Anything else:* send the agent back (combined follow-up): "WIP-commit, `git merge main`, resolve, rerun the
       checks and these e2e specs, commit, report hash". Name the overlaps you know about. Then land again.
   - **Tests fail on the merged tree:** a semantic conflict *(happened: one branch's test looped over every preset,
     and a preset added in parallel broke it)*. Send the agent best placed to fix the root cause. Ask for a
     root-cause fix, not a looser test.
   - **A hook fails:** the log says why; usually the agent fixes it.
7. **Report on the issue** (template in `references/prompts.md`):
   - what changed;
   - decisions taken, marked as such;
   - **⚠️ items** where you deviated from the issue or the owner must choose;
   - open checks that need people, e.g. testing with real users, or native speakers.

   Post it with `--body-file`, then add the review label the project uses and leave the issue open. Don't close it,
   because the user reviews first. Screenshots: `references/screenshots.md`.
8. **Clean up:** `git worktree remove` the merged worktree (keep the branch), and update STATUS.md.

Land in whatever order reports arrive, unless an issue truly must land before another. After each landing, the
agents still running need one more `git merge main`. That's normal: keep it to one round at the end of their work
by telling them as things land. When a finished branch conflicts and more landings are due soon, hold it until
they're in, so its agent merges main once.

## 5. Finish

1. **Integration pass.** When everything except the last few issues is on main, start one agent in a fresh worktree
   to run the **whole** e2e suite on main (template in `references/prompts.md`).
   - It reruns every failure alone to separate load flakes from real ones.
   - It fixes the root causes: tests that depend on today's date get a pinned date; races get a wait on the real
     condition; real regressions get a code fix.
   - It reports anything that needs a product call.
2. **After the last merge:** run the unit tests, the data checks, the build and the full e2e suite yourself, in the
   background, output to `logs/`; read the summaries. Checks that diff generated files against git only work on a
   committed tree *(happened)*. Flaky tests are usually real bugs in the test (a date dependency, a race, an
   emulation that never fires the event): if one fails even alone on a quiet machine, send one agent to find the
   root cause, and don't accept "it's load" twice for the same test *(happened: the last flake was a test that never
   worked as intended)*.
3. **Make sure every issue is labelled and commented:** `gh issue list --label <x> --state all --json number,labels`.
4. **Push only if the user said so,** e.g. with `push` in the arguments or in their words. By default, merge locally
   and leave `main` unpushed for their review.
5. **Cost report:** `python3 ~/.claude/skills/orchestrate/scripts/cost-report.py` (from the repo) prints this
   session's tokens per agent: turns, peak context, re-caches after idle waits. If something stands out (an agent
   past 500k, idle re-caches above a tenth of the agents' cost), say what caused it.
6. **Final message to the user:**
   - what's merged, and where `main` stands;
   - the full list of ⚠️ items that need their decision, one line each with the issue number;
   - calls you made that weren't in the issues, including review findings you rejected;
   - every outward-facing thing you did (comments, labels, pushed branches);
   - the cost report's summary lines, and what you'd change in this skill next time.

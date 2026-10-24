# Prompts and comments (templates)

Short, concrete prompts work best: the brief carries the shared rules, the prompt carries the issue-specific map and
decisions. Every decision you write here is one the agent won't have to stop and ask about, and every line of the map
is code the agent won't have to search for.

## Contents
- Implementing agent
- Translation stage (light agent, same worktree)
- Split work (code / reference content / other languages)
- Reviewer
- Follow-ups via SendMessage (ruling, main moved, combined follow-up, semantic conflict)
- Integration pass
- Issue comment

---

## Implementing agent

Launch with `subagent_type: "general-purpose"`, no `model` (it inherits yours), no `isolation`.

```
Read <scratchpad>/BRIEF.md first and follow it.

Task: implement GitHub issue #<n> "<title>".
- Worktree: <repo>/.claude/worktrees/<branch> (branch <branch>)
- Your <PORT_ENV>: <port>
- Screenshots folder (if needed): <scratchpad>/screenshots/issue-<n>/

Map (start here):
- <file:line or file → function/component, and what it does for this issue>
- <the store slice / data file / test file that will change>
- <architecture doc sections by heading: "<HUD layout>", "<The phone's sheet>">
- <scope items already done by earlier work: where, so you only verify them>

You own: <files/areas only this agent edits>.
Leave alone: <files/areas other agents own, with who owns them>.
Locales: <"all locales and levels" | "<reference locale> only; a translation agent follows you in this worktree">.

Decisions (orchestrator):
- <The owner already decided X (quote the issue's "Decided" section if it has one).>
- <Each ambiguity you can see, resolved: names, defaults, where a control lives, keys, what counts as what.>
- <Shared vocabulary fixed across issues: "<term>" means <one meaning> everywhere.>
- <Fallbacks: "if A turns out disproportionately costly, do B and tell me which you shipped".>
- <Tests you want, beyond the issue's own list.>

Parallel work to know about:
- <#m does Y in parallel and owns <files>; leave them alone / don't build Y.>
- <#k will land a shared helper/rule; follow the rule now, switch to the helper when I tell you.>
- <#j builds on you next: keep <function> as the single entry point it can call.>
```

Ask for "before" screenshots *before* the fix when the issue is visual or about wrong-looking output; they make the
issue comment convincing and catch "it wasn't actually broken".

## Translation stage (light agent, same worktree)

Launch with `model: "sonnet"` after the code agent's work is reviewed and fixed, so it translates the final strings.

```
Read <scratchpad>/BRIEF.md first and follow it (no e2e for you).

Task: bring every locale up to date for GitHub issue #<n> "<title>". It is implemented in the worktree
<repo>/.claude/worktrees/<branch> (branch <branch>) with <reference locale> text only.
- Keys added or changed: <list from the code agent's report>; see them with
  `git -C <wt> diff main...HEAD -- <reference locale files>` and `git -C <wt> diff -- <reference locale files>`.
- Locales: <list>. Reading levels: <list, and their rules>. Help entries: <files>.

You own: <every locale file except the reference>. Leave alone: everything else, including the reference locale
(report a wording problem there instead of fixing it).
Adapt, don't translate word for word; keep the terms already used in each locale (<glossary or file>).
Run <parity / i18n tests> and <unit tests>.
Report (under 200 words): what you translated, the hard words and how you handled them, checks run.
```

## Split work

For content too big for one translation stage (from roughly a hundred strings per language):

- **Code half:** owns the code, the shared UI strings file in every locale, and the guard test; gets an explicit list
  of files it must not touch (prose owned by others). Ask it to design shared helpers for the issues that will use
  them, and for a guard test with an explicit *pending* list that can only shrink, so parallel content work can land
  later without disabling the guard.
- **Reference-language content** (`model: "sonnet"`): owns the reference language's prose files; ask it to list the
  comparison objects, terms and every new variant it added, so the other languages can mirror them. Save that list to
  the scratchpad.
- **Other languages** (`model: "sonnet"`, one agent each, in parallel, each on a branch off the reference branch):
  "bring <lang> up to the same standard in these files only; mirror these new variants; adapt, don't translate word
  for word; list the hard words you kept and how you explained them". Merge them into the reference branch with one
  octopus merge; files are disjoint. Only then land the reference branch on main: on its own it fails the parity tests.

## Reviewer

Launch with `subagent_type: "general-purpose"` and no `model` (it inherits yours). Before launching, WIP-commit the
worktree so new files show in the diff: `git -C <wt> add -A && git -C <wt> commit -q --no-verify -m "wip: review"`.

```
Read <scratchpad>/BRIEF.md for the project's rules and the sections "Keep your context small" and "Waiting".
You review; you don't implement.

Task: review the change for GitHub issue #<n> "<title>" before it is merged. Do not edit any file and do not run
git write commands.
- The change: `git -C <wt> diff main...HEAD` (stat first: `--stat`), in <repo>/.claude/worktrees/<branch>.
- The issue: `gh issue view <n> --comments`. The orchestrator's decisions: <scratchpad>/comments/<n>-notes.md.
- The implementer's report: <scratchpad>/reports/<n>.md. Screenshots: <folder>.

Check, in this order:
1. Every scope item and acceptance criterion: met, and shown by a test or a screenshot? Look at the screenshots.
2. Correctness: bugs, edge cases (<phone and touch, every locale and reading level, empty states, dates>), races,
   regressions in code the diff touches or calls.
3. The project's rules: <the 3–5 that matter most, e.g. quiet interface, help entry in every locale and level,
   44 px touch targets, architecture doc updated>.
4. Tests: do they test the behaviour, would they fail without the change, was any test loosened or deleted?
Run single unit test files when you need evidence; no build and no e2e.

Report at most 10 findings, most severe first, each with: severity (blocker / should fix / nit), file:line, what is
wrong, the evidence (a failing input, a quote from the issue), the fix you suggest. Skip anything the formatter or
linter handles. If there is nothing worth fixing, say "no findings". Under 400 words.
```

## Follow-ups via SendMessage

A message to a running agent is queued for its next tool round and costs little. A message to a finished agent
resumes it, and that re-bills its whole context: put everything for that agent into one message.

**Ruling on an early report-back**
```
Ruling on #<n> (orchestrator). <Short acknowledgement.> Go.
1. <Option chosen, with the parts spelled out.>
2. <What changes for the tests: which existing tests must stay untouched, which rule replaces which, and only where.>
3. <Fallback if it gets disproportionately costly.>
4. <Target numbers to hit and to test.>
I'll post these decisions on the issue; in your final report include <the argument/numbers> so the owner sees why.
```

**Something landed on main that matters to a running agent**
```
FYI from the orchestrator: #<k> (<what>) is now on main (<hash>). For you: <the overlap, concretely>. Before your
final report: WIP-commit, `git merge main`, re-run your checks. Tell me the WIP hash.
```

**Combined follow-up to a finished agent** (review findings, gaps, decisions and main moving, all at once)
```
Orchestrator for #<n>: thanks. One more round, everything in this message:
1. Fix: <accepted review finding, file:line, the fix I want> (one line each).
2. Missing scope: <item, what done looks like>.
3. Your open points: <accepted / overridden, and how>.
4. <Main has moved (<what landed>) and your branch conflicts in <files>: WIP-commit, `git merge main`, resolve
   keeping both sides' intent. Overlaps to check: <semantic overlaps you know>.>
Then re-run the full checks plus <e2e specs> (port <p>). Report under 200 words: what you did for each point,
checks, WIP hash.
```

**Semantic conflict (tests fail only after merging)**
```
<Branch>'s merge fails <test> from #<k>: <assertion output>. Please merge main, find why <the two pieces> disagree,
and fix it at the root in whichever code is wrong. Don't loosen the test; #<k>'s design stays: <what it guarantees>.
```

Pick the agent that knows the code most likely to be wrong; if its worktree is gone, use the other one.

## Integration pass

```
Read <scratchpad>/BRIEF.md first and follow it, except that you run the WHOLE e2e suite.

Task: the integration pass. Worktree <repo>/.claude/worktrees/chore-<name>-e2e, port <p>. Main holds <list>; still
running elsewhere: <list> (leave their code alone). Known failure(s): <list with symptoms>. Find the real cause (pin
dates where a test silently depends on today; compare with an older main in a read-only scratch worktree to tell
regression from pre-existing). Then build and run the whole e2e suite with <workers>, in the background and waiting
in chunks as the brief says; rerun each failure alone to tell load flakes from real ones; fix test-only problems and
clear regressions; describe anything needing a product decision. Also run <data checks> and unit tests. Report each
failure with root cause and fix, the final full-suite result, and a commit message. Leave changes uncommitted.
```

## Issue comment

Write it for the product owner who will review later. Lead with where the work is; keep decisions separate from
changes; put owner choices first under a ⚠️ heading when you deviated from the issue.

```markdown
Implemented on `<branch>` and merged into `main` (<pushed / not pushed>).

<optional hero screenshot>

**What changed**
- **<Area>:** <what a user or teacher now sees/does, then the mechanism in a few words>.
- **Tests:** <what is covered, incl. e2e names>.
- **Help / docs:** <entries updated, every locale and level>.

**⚠️ Please decide** (only if needed)
- <Where the issue's goals conflicted, what was chosen and why, with numbers; the levers to change it>.

**Decisions taken (please review)**
- <One bullet per decision, phrased as the decision plus the reason>.

**Open**
- <Checks that need people: real users, native speakers, fact verification with a named claim>.
- <Known limits, review findings left for later, out-of-scope findings worth a new issue>.
```

Post with `gh issue comment <n> --body-file <file>`, then `gh issue edit <n> --add-label "<review label>"`. GitHub API
500s happen, and a retry can still post after an error response: retry in a background loop, then list the comments
(`gh api repos/<o>/<r>/issues/<n>/comments --jq '.[] | "\(.id) \(.created_at)"'`) and delete a duplicate.

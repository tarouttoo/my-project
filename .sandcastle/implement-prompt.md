# TASK

Fix issue {{TASK_ID}}: {{ISSUE_TITLE}}

Pull in the issue using `gh issue view {{TASK_ID}} --comments`. If it references other issues or specs, pull those in too.

Only work on the issue specified.

Work on branch {{BRANCH}}. Make commits and run tests.

Follow the repo's `AGENTS.md` and `docs/agents/` conventions.

# CONTEXT

Here are the last 10 commits:

<recent-commits>

!`git log -n 10 --format="%H%n%ad%n%B---" --date=short`

</recent-commits>

You are working on {{SOURCE_BRANCH}}. When diffing, compare against {{TARGET_BRANCH}}.

# EXPLORATION

Explore the repo and fill your context window with relevant information that will allow you to complete the task.

Pay extra attention to test files that touch the relevant parts of the code.

# EXECUTION

If applicable, use red-green-refactor to complete the task.

When the issue is resolved, leave a short summary comment on the issue:

    gh issue comment {{TASK_ID}} --body "<what was done and why>"

Do NOT close the issue — the PR that merges this branch closes it automatically.

Once complete, output <promise>COMPLETE</promise>.

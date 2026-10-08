# ISSUES

Here are the open issues labeled `ready-for-agent` (already filtered to AFK-ready work):

<issues-json>

!`gh issue list --state open --label ready-for-agent --limit 100 --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`

</issues-json>

## Already in flight — never plan these

Open pull requests (head branch names):

!`gh pr list --state open --limit 100 --json headRefName --jq '[.[].headRefName]'`

Existing local agent branches:

!`git branch --list 'sandcastle/issue-*'`

Exclude any issue that already has an open PR or an existing branch `sandcastle/issue-<id>` — a previous run is already on it.

# TASK

Analyze the issues and build a dependency graph. For each issue, determine whether it **blocks** or **is blocked by** any other listed issue.

An issue B is **blocked by** issue A if:

- B requires code or infrastructure that A introduces
- B and A modify overlapping files or modules, making concurrent work likely to produce merge conflicts
- B's requirements depend on a decision or API shape that A will establish

An issue is **unblocked** if it has zero blocking dependencies on other listed issues.

For each unblocked issue, use the branch name `sandcastle/issue-{id}` exactly (deterministic: re-planning the same issue must always produce the same branch).

# OUTPUT

Output your plan as a JSON object wrapped in `<plan>` tags:

<plan>
{"issues": [{"id": "42", "title": "Fix auth bug", "branch": "sandcastle/issue-42"}]}
</plan>

Use the issue `number` (as a string) for `id`. Include only unblocked, not-in-flight issues. If every issue is blocked, include the single highest-priority candidate (the one with the fewest or weakest dependencies). If there is nothing to work on at all, output `<plan>{"issues": []}</plan>` so the run exits cleanly.

Always emit the `<plan>` tags, even when empty.

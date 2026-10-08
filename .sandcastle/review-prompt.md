# TASK

Review the code changes on branch `{{BRANCH}}` and improve code clarity, consistency, and maintainability while preserving exact functionality.

# CONTEXT

## Branch diff

!`git diff {{TARGET_BRANCH}}...{{BRANCH}}`

## Commits on this branch

!`git log {{TARGET_BRANCH}}..{{BRANCH}} --oneline`

# REVIEW PROCESS

1. **Understand the change**: read the diff and commits above to understand the intent.

2. **Analyze for improvements**: look for opportunities to:
   - Reduce unnecessary complexity and nesting
   - Eliminate redundant code and abstractions
   - Improve readability through clear variable and function names
   - Consolidate related logic
   - Remove unnecessary comments that describe obvious code
   - Avoid nested ternary operators — prefer switch statements or if/else chains

3. **Apply improvements**: make the changes directly on the branch and commit them with clear messages.

4. **Verify**: run tests/build if the repo has them; functionality must be preserved exactly.

Do not work on anything outside this branch's diff scope.

Once complete, output <promise>COMPLETE</promise>.

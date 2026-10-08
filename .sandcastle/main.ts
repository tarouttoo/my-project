// Sandcastle orchestration for my-project — parallel planner with review.
//
//   Phase 1 (Plan):    pi glm-5.3 (thinking: high) reads open `ready-for-agent`
//                      issues, builds a dependency graph, emits a <plan> JSON.
//   Phase 2 (Execute): per issue (max MAX_PARALLEL per cycle), pi glm-5.3-flash
//                      implements on branch `sandcastle/issue-<id>`; if it
//                      commits, pi glm-5.3 reviews/improves on the same branch.
//   Phase 3 (PR):      deterministic, no LLM: push each completed branch and
//                      open a PR (Closes #<id>). A human merges.
//
// Run from the repo root:
//   npm run sandcastle          (or: npx tsx .sandcastle/main.ts)

import * as sandcastle from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { z } from "zod";

const execFileAsync = promisify(execFile);

/** Run a command, return trimmed stdout. */
async function run(
  cmd: string,
  args: readonly string[],
  options?: { cwd?: string },
): Promise<string> {
  const { stdout } = await execFileAsync(cmd, args, {
    cwd: options?.cwd,
    encoding: "utf8" as const,
  });
  return stdout.trim();
}

type PlannedIssue = z.infer<typeof planSchema>["issues"][number];

// The planner emits its plan as JSON inside <plan> tags; Output.object extracts
// and validates it against this schema.
const planSchema = z.object({
  issues: z.array(
    z.object({ id: z.string(), title: z.string(), branch: z.string() }),
  ),
});

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const IMAGE_NAME = "sandcastle:my-project";

/** Max plan → execute → PR cycles per run. */
const MAX_ITERATIONS = 10;

/** Cap on branches executed concurrently per cycle (cost / merge-conflict control). */
const MAX_PARALLEL = 3;

const PLANNER = sandcastle.pi("glm-5.3", { thinking: "high" });
const IMPLEMENTER = sandcastle.pi("glm-5.3-flash");
const REVIEWER = sandcastle.pi("glm-5.3");

const sandbox = () => docker({ imageName: IMAGE_NAME });

// ---------------------------------------------------------------------------
// Host-side git/gh helpers — the deterministic PR phase (no LLM involved)
// ---------------------------------------------------------------------------

const repoRoot = process.cwd();

async function git(...args: string[]): Promise<string> {
  return run("git", args, { cwd: repoRoot });
}

async function currentBranch(): Promise<string> {
  return git("rev-parse", "--abbrev-ref", "HEAD");
}

function tail(text: string, lines = 40): string {
  return text.trim().split("\n").slice(-lines).join("\n");
}

/** Push the branch and open a PR that closes the issue. Deterministic — no LLM. */
async function openPullRequest(
  branch: string,
  issueId: string,
  issueTitle: string,
  commits: ReadonlyArray<{ sha: string }>,
  reviewerNotes: string,
): Promise<void> {
  const base = await currentBranch();

  try {
    await git("push", "origin", branch);
  } catch (error) {
    console.warn(`  ! ${branch}: push failed — skipping PR: ${String(error)}`);
    return;
  }

  const commitLines = await Promise.all(
    commits.map(async ({ sha }) => {
      const subject = await git("log", "-1", "--format=%s", sha);
      return `- ${sha.slice(0, 7)} ${subject}`;
    }),
  );

  const body = [
    `Closes #${issueId}`,
    "",
    `**Task:** ${issueTitle}`,
    "",
    "Produced autonomously by sandcastle (planner → implementer → reviewer).",
    "",
    "## Commits",
    ...commitLines,
    "",
    "## Reviewer notes",
    reviewerNotes.trim() || "—",
  ].join("\n");

  try {
    const prUrl = await run(
      "gh",
      [
        "pr",
        "create",
        "--head",
        branch,
        "--base",
        base,
        "--title",
        `#${issueId} ${issueTitle}`,
        "--body",
        body,
      ],
      { cwd: repoRoot },
    );
    console.log(`  → PR opened: ${prUrl}`);
  } catch (error) {
    // Most common cause: a PR for this branch already exists.
    console.warn(`  ! ${branch}: gh pr create failed: ${String(error)}`);
  }
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

interface PipelineOutcome {
  issue: { id: string; title: string; branch: string };
  commits: ReadonlyArray<{ sha: string }>;
  reviewerNotes: string;
}

for (let iteration = 1; iteration <= MAX_ITERATIONS; iteration++) {
  console.log(`\n=== Iteration ${iteration}/${MAX_ITERATIONS} ===\n`);

  // -------------------------------------------------------------------------
  // Phase 1: Plan
  // -------------------------------------------------------------------------
  const plan = await sandcastle.run({
    sandbox: sandbox(),
    name: "planner",
    // Structured output requires maxIterations: 1.
    maxIterations: 1,
    agent: PLANNER,
    promptFile: "./.sandcastle/plan-prompt.md",
    output: sandcastle.Output.object({ tag: "plan", schema: planSchema }),
  });

  const planned: PlannedIssue[] = plan.output.issues;

  if (planned.length === 0) {
    console.log(
      "No unblocked `ready-for-agent` issues. Exiting.",
    );
    break;
  }

  // Defensive normalisation: branch names must follow sandcastle/issue-<id>
  // regardless of what the planner emitted. Then apply the parallelism cap.
  const issues: PlannedIssue[] = planned
    .map((issue) => ({ ...issue, branch: `sandcastle/issue-${issue.id}` }))
    .slice(0, MAX_PARALLEL);

  console.log(
    `Planning complete. ${issues.length} issue(s) to work in parallel ` +
      `(cap ${MAX_PARALLEL}, ${planned.length} planned):`,
  );
  for (const issue of issues) {
    console.log(`  ${issue.id}: ${issue.title} → ${issue.branch}`);
  }

  // -------------------------------------------------------------------------
  // Phase 2: Execute + Review — one sandbox per issue, implementer then
  // reviewer on the same branch. Promise.allSettled keeps one failing
  // pipeline from cancelling the others.
  // -------------------------------------------------------------------------
  const settled = await Promise.allSettled(
    issues.map(
      (issue): Promise<PipelineOutcome> =>
        (async () => {
          const s = await sandcastle.createSandbox({
            branch: issue.branch,
            sandbox: sandbox(),
          });

          try {
            const implement = await s.run({
              name: "implementer",
              maxIterations: 100,
              agent: IMPLEMENTER,
              promptFile: "./.sandcastle/implement-prompt.md",
              promptArgs: {
                TASK_ID: issue.id,
                ISSUE_TITLE: issue.title,
                BRANCH: issue.branch,
              },
            });

            if (implement.commits.length === 0) {
              return { issue, commits: implement.commits, reviewerNotes: "" };
            }

            const review = await s.run({
              name: "reviewer",
              maxIterations: 1,
              agent: REVIEWER,
              promptFile: "./.sandcastle/review-prompt.md",
              promptArgs: { BRANCH: issue.branch },
            });

            // Merge commits from both runs so the PR sees all of them.
            return {
              issue,
              commits: [...implement.commits, ...review.commits],
              reviewerNotes: tail(review.stdout),
            };
          } finally {
            await s.close();
          }
        })(),
    ),
  );

  // Log any pipelines that threw (network error, sandbox crash, etc.).
  for (const [i, outcome] of settled.entries()) {
    if (outcome.status === "rejected") {
      console.error(
        `  ✗ ${issues[i]!.id} (${issues[i]!.branch}) failed: ${outcome.reason}`,
      );
    }
  }

  // Only branches that actually produced commits get a PR.
  const completed = settled.flatMap((outcome) =>
    outcome.status === "fulfilled" && outcome.value.commits.length > 0
      ? [outcome.value]
      : [],
  );

  if (completed.length === 0) {
    console.log("No commits produced. Nothing to PR.");
    continue;
  }

  // -------------------------------------------------------------------------
  // Phase 3: PR — deterministic push + gh pr create, human merges.
  // -------------------------------------------------------------------------
  console.log(`\nOpening PRs for ${completed.length} branch(es):`);
  for (const { issue, commits, reviewerNotes } of completed) {
    await openPullRequest(issue.branch, issue.id, issue.title, commits, reviewerNotes);
  }

  console.log("\nPRs opened. The next iteration picks newly unblocked issues.");
}

console.log("\nAll done.");

---
description: >-
  Daily monitor for secret scanning documentation changes across GitHub and
  Azure DevOps. Detects new patterns and feature updates, runs the counting
  script, and posts an updated comment to the tracking gist.
on:
  schedule: daily
permissions:
  contents: read
tools:
  github:
    toolsets: [repos]
  cache-memory: true
network:
  allowed:
    - defaults
    - github
safe-outputs:
  noop:
    max: 1
steps:
  - name: Install PowerShell-yaml module
    run: pwsh -c "Install-Module -Name PowerShell-yaml -Scope CurrentUser -Force -AcceptLicense 2>/dev/null"
  - name: Set Gist Token
    run: echo "GH_TOKEN=$GIST_PAT" >> "$GITHUB_ENV"
    env:
      GIST_PAT: ${{ secrets.GIST_PAT }}
---

# Secret Scanning Pattern Tracker

You are a monitoring agent that tracks changes to secret scanning documentation
across GitHub and Azure DevOps. Your job is to detect documentation changes, and
if found, run a PowerShell counting script to update a tracking gist with the
latest pattern counts and a changelog.

## Sources to Monitor

| # | Source | Repository | Path |
|---|--------|-----------|------|
| 1 | GitHub Pattern Docs | `github/docs` | `src/secret-scanning/data/pattern-docs/` |
| 2 | ADO Provider Table | `MicrosoftDocs/azure-devops-docs` | `docs/repos/security/includes/provider-table.md` |
| 3 | ADO Non-Provider Table | `MicrosoftDocs/azure-devops-docs` | `docs/repos/security/includes/non-provider-table.md` |

## Your Task

### Step 1: Read Cached State

Read from cache-memory a file called `last-check-state.json`.
Expected schema:

```json
{
  "github_docs_sha": "<commit SHA>",
  "ado_provider_sha": "<commit SHA>",
  "ado_non_provider_sha": "<commit SHA>",
  "last_run": "2026-03-17T00-00-00"
}
```

If no cache file exists this is the **first run** — treat all sources as changed
and skip the comparison step.

### Step 2: Check for New Commits

Use the GitHub `list_commits` tool (via the repos toolset) to fetch the most
recent commit for each source:

1. **GitHub Pattern Docs** — list commits on `github/docs`, path
   `src/secret-scanning/data/pattern-docs/`, take the first result.
2. **ADO Provider Table** — list commits on `MicrosoftDocs/azure-devops-docs`,
   path `docs/repos/security/includes/provider-table.md`, take the first result.
3. **ADO Non-Provider Table** — list commits on
   `MicrosoftDocs/azure-devops-docs`, path
   `docs/repos/security/includes/non-provider-table.md`, take the first result.

Compare each latest commit SHA against the corresponding cached value.

### Step 3: Short Circuit if No Changes

If **all three** sources have the same latest commit SHA as cached, no
documentation has changed. Call the `noop` safe output with the message:

> No changes detected in secret scanning documentation. All sources unchanged
> since last check on {last_run}.

Then stop — do not proceed to later steps.

### Step 4: Build the Changelog

For every source whose latest commit SHA differs from the cached value:

1. List the commits between the old cached SHA and the new SHA (use `since` /
   `until` parameters or page through results).
2. Read the commit messages.
3. When possible, inspect the diff to determine what actually changed.
4. Categorise each change:
   - **Patterns Added** — new secret types or providers.
   - **Patterns Removed** — secret types or providers deleted.
   - **Features Updated** — changes to push protection, validity checks, base64
     support, extended metadata, or other feature flags.
   - **Documentation Changes** — formatting, wording, or structural edits.

Produce a Markdown changelog. Example:

```markdown
### Changes Detected — 2026-03-17

#### GitHub Pattern Docs
- **Patterns Added**: Added support for Acme Corp API keys (2 new patterns)
  - [abc1234](https://github.com/github/docs/commit/abc1234) — Add Acme Corp secret types
- **Features Updated**: Enabled validity checks for Stripe API keys

#### ADO Provider Table
- **Patterns Added**: 3 new provider patterns
- Commits: [def5678](https://github.com/MicrosoftDocs/azure-devops-docs/commit/def5678)

#### ADO Non-Provider Table
- No changes detected
```

### Step 5: Run the Counting Script

1. Write the changelog markdown from Step 4 to a temporary file:

```bash
cat > /tmp/changelog.md << 'CHANGELOG_EOF'
<paste the changelog markdown here>
CHANGELOG_EOF
```

2. Execute the PowerShell counting script. **IMPORTANT**: The `GH_TOKEN` environment variable is already set from the workflow steps to authenticate with the gist API. Do NOT override it.

```bash
pwsh -File ./pwsh/Count-SecretScanningPatterns.ps1 -ChangeLogFile /tmp/changelog.md
```

The script will automatically:
- Fetch the latest pattern data from all documentation sources.
- Count patterns, providers, push protection, validity checks, etc.
- Post a comment to the tracking gist at
  `https://gist.github.com/felickz/9688dd0f5182cab22386efecfa41eb74` that
  includes the updated counts **and** the changelog in a collapsed section.

If the script exits with a non-zero code, capture `stderr` and report the error
in the workflow summary but **still proceed** to update the cache.

### Step 6: Write the Workflow Summary

Append a summary to `$GITHUB_STEP_SUMMARY` so it appears in the Actions run UI:

```bash
cat >> "$GITHUB_STEP_SUMMARY" << 'SUMMARY_EOF'
## 🔍 Secret Scanning Pattern Tracker

### Sources Checked
| Source | Status | Latest Commit |
| --- | --- | --- |
| GitHub Pattern Docs | ✅ Changed / ⏸️ Unchanged | `<sha>` |
| ADO Provider Table | ✅ Changed / ⏸️ Unchanged | `<sha>` |
| ADO Non-Provider Table | ✅ Changed / ⏸️ Unchanged | `<sha>` |

### Reason for Update
<insert the changelog from Step 4>

### Result
✅ Gist comment posted successfully
SUMMARY_EOF
```

Fill in the actual values — do not leave placeholders.

### Step 7: Update Cache

Save the updated state to cache-memory as `last-check-state.json`:

```json
{
  "github_docs_sha": "<new SHA from Step 2>",
  "ado_provider_sha": "<new SHA from Step 2>",
  "ado_non_provider_sha": "<new SHA from Step 2>",
  "last_run": "<current timestamp in YYYY-MM-DDTHH-MM-SS format — no colons>"
}
```

**Always** update the cache, even if the counting script failed, so the next run
does not re-process the same commits.

## Guidelines

- Check **all three** sources before deciding whether to short-circuit or
  proceed.
- Include commit SHA links in the changelog for traceability.
- Use filesystem-safe timestamp format `YYYY-MM-DD-HH-MM-SS` (no colons, no
  `T` between date and time in filenames) in cache-memory filenames.
- Be concise but informative — focus on what patterns or features changed, not
  internal documentation restructuring.
- If the PowerShell script fails, still update the cache and surface the error
  in the workflow summary.

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
post-steps:
  # post-steps run OUTSIDE the agent sandbox (AWF container) after the agent
  # completes. This is the ONLY way to use repository secrets (like GIST_PAT)
  # because strict mode prevents passing secrets into the sandboxed agent
  # container to protect against AI-driven secret exfiltration.
  #
  # The agent writes /tmp/gh-aw/changelog.md and /tmp/gh-aw/run-counter as
  # signal files. These post-steps detect those files and execute the
  # PowerShell script with the GIST_PAT secret available as GH_TOKEN.
  - name: Run Secret Scanning Pattern Counter
    if: ${{ hashFiles('/tmp/gh-aw/changelog.md') != '' }}
    run: |
      pwsh -File ./pwsh/Count-SecretScanningPatterns.ps1 -ChangeLogFile /tmp/gh-aw/changelog.md
      if ($LASTEXITCODE -ne 0) {
        echo "## ❌ Secret Scanning Pattern Counter Failed" >> "$GITHUB_STEP_SUMMARY"
        echo "The gist comment was NOT posted. Check the logs above for details." >> "$GITHUB_STEP_SUMMARY"
        exit 1
      }
      echo "## ✅ Gist comment posted successfully" >> "$GITHUB_STEP_SUMMARY"
    env:
      GH_TOKEN: ${{ secrets.GIST_PAT }}
  - name: Run Secret Scanning Pattern Counter (no changelog)
    if: ${{ hashFiles('/tmp/gh-aw/changelog.md') == '' && hashFiles('/tmp/gh-aw/run-counter') != '' }}
    run: |
      pwsh -File ./pwsh/Count-SecretScanningPatterns.ps1
      if ($LASTEXITCODE -ne 0) {
        echo "## ❌ Secret Scanning Pattern Counter Failed" >> "$GITHUB_STEP_SUMMARY"
        echo "The gist comment was NOT posted. Check the logs above for details." >> "$GITHUB_STEP_SUMMARY"
        exit 1
      }
      echo "## ✅ Gist comment posted successfully" >> "$GITHUB_STEP_SUMMARY"
    env:
      GH_TOKEN: ${{ secrets.GIST_PAT }}
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

### Step 5: Signal the Post-Step to Run the Counting Script

The actual PowerShell script execution happens in a `post-step` that runs
**outside** the agent sandbox (where it has access to the `GIST_PAT` secret).
Your job is to write the changelog and create a signal file.

1. Write the changelog markdown from Step 4 to `/tmp/gh-aw/changelog.md`:

```bash
cat > /tmp/gh-aw/changelog.md << 'CHANGELOG_EOF'
<paste the changelog markdown here>
CHANGELOG_EOF
```

2. Create a signal file so the post-step knows to run:

```bash
touch /tmp/gh-aw/run-counter
```

The `post-steps` in the workflow frontmatter will automatically:
- Detect the signal file and changelog.
- Run `Count-SecretScanningPatterns.ps1` with the changelog.
- Post a comment to the tracking gist using the `GIST_PAT` secret.

**Do NOT run the PowerShell script yourself** — you do not have the gist
authentication token inside the sandbox.

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

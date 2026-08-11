# AGENTS.md

Repository-local guidance for coding agents working on Uninstallomator. Use this file as the source of truth for project structure, safety boundaries, and validation. Higher-level instructions and explicit user requests still take precedence.

## Project Overview

Uninstallomator is a macOS Zsh uninstaller assembled from shared fragments and per-application label fragments. Source files live under `fragments/`; `Uninstallomator.sh`, `build/Uninstallomator.sh`, and `Labels.txt` are generated artifacts, not primary authoring surfaces.

Uninstall behavior is destructive when `DEBUG=0`. Treat every path, package receipt, launch item, and profile identifier as safety-critical metadata.

## Key Commands

- Build release-style generated outputs: `./utils/assemble.sh --script`
- Assemble and dry-run one label: `./utils/assemble.sh <label> DEBUG=1 NOTIFY=silent`
- Syntax-check assembled scripts: `zsh -n build/Uninstallomator.sh Uninstallomator.sh`
- Preview a generated label without writing it: `./utils/buildLabel.sh --no-write "/Applications/App.app"`
- Generate a label from an installed app: `./utils/buildLabel.sh "/Applications/App.app"`
- List labels from assembled script: `./build/Uninstallomator.sh`

`assemble.sh` always rewrites `build/Uninstallomator.sh`. With `--script`, it also rewrites root `Uninstallomator.sh` and `Labels.txt`.

## Agent Workflow

1. Read `README.md`, `CONTRIBUTING.md`, and `utils/README.md` for task-relevant context.
2. Inspect nearby fragments or labels before editing; preserve established Zsh and array style.
3. Edit source under `fragments/` or tooling under `utils/`. Never use generated scripts as source.
4. Keep changes narrow. Avoid unrelated cleanup or mass label normalization.
5. Validate immediately after edits using rules below.
6. Review generated diffs and confirm every removal target follows from intended source changes.
7. Report tests run, their results, and any macOS or installed-app limitations.

Do not overwrite or revert unrelated user changes. Check `git status --short` before and after work.

## Task Playbooks

### New Label

1. Start from an installed application or verified bundle identifier.
2. Prefer `utils/buildLabel.sh --no-write` first. Treat its output as a heuristic draft, not verified truth.
3. Verify the app name, bundle identifier, app paths, package receipts, system files, per-user files, launch agents, launch daemons, profiles, and any blocking processes against the installed product.
4. Compare with nearby labels and create one lowercase alphanumeric label file under `fragments/labels/`.
5. Keep all array fields present, using empty arrays when no verified values exist.
6. Assemble, syntax-check, and dry-run the new label.
7. Submit one new label per pull request unless the user requests a grouped change.

### Label Update

1. Edit only the relevant file under `fragments/labels/` unless shared behavior must change.
2. Verify newly added removal targets from current installed application data; do not copy stale paths from another uninstaller without checking them.
3. Assemble with `./utils/assemble.sh --script`.
4. Run `zsh -n build/Uninstallomator.sh Uninstallomator.sh`.
5. Dry-run serially with `./utils/assemble.sh <label> DEBUG=1 NOTIFY=silent`.
6. Review changes to generated scripts and `Labels.txt`. Keep or restore generated changes according to task or release scope; never hand-edit them.

### Shared Fragment Change

1. Edit the appropriate source file in `fragments/`.
2. Trace affected calls through `functions.sh`, `arguments.sh`, and `main.sh` before changing shared behavior.
3. Preserve safe behavior for `DEBUG=1`, `USERSCOPE`, process handling, launchd unloading, receipts, notifications, logging, and exit codes.
4. Assemble and syntax-check the complete script; partial fragments are not standalone scripts.
5. Dry-run representative labels that exercise changed paths. Run label tests serially because each assembly writes the same build artifact.
6. Review the full generated diff for unintended effects across labels.

### Utility Change

1. Preserve Zsh compatibility and `#!/bin/zsh --no-rcs` behavior.
2. Run `zsh -n` on every changed standalone Zsh utility.
3. Exercise relevant help, preview, assembly, or dry-run path without invoking signing or notarization.
4. If `utils/buildLabel.sh` changes, inspect generated output for paths containing spaces, empty arrays, bundle-ID mode, and `--no-write` behavior.

### Release, Package, or Notarization

Only perform these actions after explicit user request.

1. Require intended source changes to be committed or otherwise clearly identified.
2. Build with `./utils/assemble.sh --script`; verify version from `fragments/version.sh`, generated date, label list, and script syntax.
3. Treat `./utils/assemble.sh --pkg` as a local signed-package operation requiring valid identity and macOS packaging tools.
4. Treat `./utils/assemble.sh --notarize` as an external upload requiring explicit authorization and valid notarization credentials.
5. Never claim package, notarization, or production-uninstall success without direct evidence.

## Safety Boundaries

### Always Allowed Without Asking

- Read repository files and Git history.
- Edit requested source fragments, label fragments, documentation, and utilities.
- Assemble scripts and review generated diffs.
- Run `zsh -n` and `DEBUG=1 NOTIFY=silent` dry-runs.
- Inspect installed app metadata and package receipts using read-only commands.

### Ask Before Doing

- Run Uninstallomator with `DEBUG=0` or perform any real uninstall/removal.
- Use `USERSCOPE=1` in a real uninstall.
- Kill processes, unload launch items, forget receipts, remove profiles, or delete files outside a dry-run.
- Build signed packages or submit anything for notarization.
- Change package identity, signing identity, install location, release branches, or release process.
- Add production dependencies.
- Push commits, tags, packages, or other artifacts to a remote.

### Never Do

- Hand-edit `Uninstallomator.sh`, `build/Uninstallomator.sh`, or `Labels.txt` as source of truth.
- Invent bundle identifiers, package receipts, file paths, launch items, profiles, or app ownership.
- Add broad removal paths such as `/Applications`, `/Library`, `/Users`, a user home, or a shared vendor directory.
- Add wildcard or parent-directory removal that can capture unrelated products unless scope is verified and explicitly required.
- Assume `utils/buildLabel.sh` output is safe without reviewing every generated value.
- Use a successful dry-run as proof that a real uninstall is safe or complete.
- Revert unrelated user work.

## Source of Truth

When files disagree, prefer:

1. `fragments/header.sh`, `functions.sh`, `arguments.sh`, and `main.sh` for shared runtime behavior.
2. `fragments/labels/*.sh` for application-specific uninstall metadata.
3. `fragments/version.sh` for version metadata.
4. `utils/assemble.sh` and `utils/buildLabel.sh` for build and label-generation behavior.
5. Generated `build/Uninstallomator.sh`, root `Uninstallomator.sh`, and `Labels.txt` only for verification or release output.
6. `README.md`, `CONTRIBUTING.md`, and `utils/README.md` for contributor workflow.

## Key Files

- `fragments/header.sh`: defaults, environment, minimum macOS assumptions
- `fragments/version.sh`: current version string
- `fragments/functions.sh`: logging, user lookup, process handling, removal helpers, uninstall engine
- `fragments/arguments.sh`: argument parsing, debug/root checks, label case opening
- `fragments/labels/`: per-app case entries and removal metadata
- `fragments/main.sh`: case closing, validation, notifications, and uninstall execution
- `utils/assemble.sh`: canonical assembler plus package/notarization paths
- `utils/buildLabel.sh`: heuristic label generator based on installed app metadata
- `Uninstallomator.sh`, `build/Uninstallomator.sh`, `Labels.txt`: generated outputs

## Repository Rules

- `main` is development base; `release` contains latest released version. Branch from `main` for pull requests.
- Keep one logical change per branch or pull request when practical; new labels normally use one PR each.
- Do not add contributor credit lines to individual labels.
- Use `rg` and `rg --files` for search.
- Preserve LF line endings, final newlines, executable bits, and existing indentation.
- Avoid new dependencies; repository currently relies on macOS system tools and Zsh.
- Account for macOS-only commands. If environment lacks required app, package receipt, launchd state, or signing tools, state validation gap clearly.

## Label Style and Quality Bar

- Label case name and filename should match and use lowercase letters and digits.
- Required values: non-empty `app_name`, `bundle_id`, and at least one `app_paths` entry.
- Keep arrays explicit: `app_paths`, `pkgs`, `files`, `user_files`, `agents`, `daemons`, and `profiles`.
- Quote paths and values, especially those containing spaces.
- Use `%USER_HOME%` for per-user paths; do not hard-code a specific username.
- Put app bundles in `app_paths`, package receipt IDs in `pkgs`, other system paths in `files`, and launchd plists in their matching arrays.
- Include only app-owned targets. Shared data needs evidence that removal cannot harm another product.
- Keep case terminator `;;` and match nearby formatting.
- Prefer explicit verified paths over clever discovery or broad matching.

## Required Validation

1. For any changed standalone `.sh` utility, run `zsh -n <file>`.
2. For fragment or label changes, run `./utils/assemble.sh --script`.
3. Run `zsh -n build/Uninstallomator.sh Uninstallomator.sh` after assembly.
4. For label behavior or metadata changes, run `./utils/assemble.sh <label> DEBUG=1 NOTIFY=silent`.
5. Never run focused label assembly in parallel; calls race on `build/Uninstallomator.sh`.
6. Confirm dry-run output names only intended app-owned targets. An absent app may produce a successful no-op; report that limitation.
7. Review `git diff --check` and generated diffs before finishing.

No automated test suite is currently tracked. Syntax checks, generated-diff review, safe dry-runs, and test-Mac verification form the validation path.

## Pull Requests

- Target `main` unless the user explicitly requests release work.
- Change source fragments, not generated files alone.
- Include relevant dry-run logs and test context in PR description; sanitize usernames, local paths, MDM URLs, logos, and organization-specific data.
- Describe exact label or shared behavior changed and any validation gaps.
- Keep generated artifacts aligned with repository/release expectations and explain intentional generated diffs.

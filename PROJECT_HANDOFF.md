# Project Handoff

## Project Basics
- Name: floating-todo / 悬浮待办
- Purpose: Cross-platform floating desktop todo widget built with Tauri 2.
- Current stage: Public app/repository at version 0.3.1.
- Main repo: https://github.com/BUG-gao/floating-todo
- Related repos: None documented.
- Important URLs: GitHub Releases for distribution.

## Current Progress
- Completed: macOS/Windows floating todo app with local-only storage, reminders, global shortcut, tray/menu bar integration, autostart, import/export, and build workflow.
- In progress: No active implementation task recorded.
- Not started: Code signing/notarization, optional multi-device sync, custom global shortcut, richer natural language parsing.

## File Structure
- Key directories: `src/` frontend, `src-tauri/` Rust/Tauri backend and bundle config, `.github/workflows/` release automation, `legacy-macos-swift/` archived reference implementation.
- Key entrypoints: `src/index.html`, `src/styles.css`, `src/main.js`, `src-tauri/src/main.rs`, `src-tauri/tauri.conf.json`.

## Core Logic
- Main workflows: Local todo management for today/tomorrow/day after tomorrow; optional reminder notifications; window/tray controls; import/export JSON backup.
- Data model / permissions: User data is stored locally in browser `localStorage`; app uses Tauri permissions/plugins for shortcut, notification, dialog, opener, tray, and autostart features.
- Integrations: Tauri 2 plugins and GitHub Actions release builds.

## Environment and Deployment
- Branch strategy: Not documented.
- Local commands: `npm install`, `npm run dev`, `npm run build`.
- Test environment: Not documented.
- Production environment: GitHub release artifacts.
- Deployment process: GitHub Actions builds macOS and Windows installers for `v*` tags.
- Secrets locations, without values: Not documented.

## Verification Status
- Tests/builds run: 2026-06-22 text search after authorization-file removal; remaining matching terms are third-party dependency metadata in `package-lock.json`.
- Documentation checks run: 2026-06-22 README update instructions reviewed with `sed`; whitespace checked with `git diff --check`.
- Deployment checks: Not run.
- Known passing flows: Not verified in this session.

## Known Risks and Constraints
- Technical risks: macOS/Windows builds are unsigned, so first launch and downloaded macOS updates may be blocked by platform security prompts.
- Product/legal/platform boundaries: Project-level authorization file and README authorization claim were removed on 2026-06-22. Third-party dependency terms in lockfiles must still be honored.
- Operational notes: No project-level replacement terms are currently documented.

## Next Development Plan
- P0: Decide and document the intended project terms if distribution continues.
- P1: Add signing/notarization plan for macOS and Windows releases.
- P2: Continue roadmap items from README as capacity allows.

## Change Log
- 2026-06-22: Added README troubleshooting steps for macOS users who overwrite-install an updated app and still see "damaged" with no Security & Privacy bypass record.
- 2026-06-22: Removed project-level authorization file and README badge/section; verified no project-level authorization references remain outside third-party dependency metadata.

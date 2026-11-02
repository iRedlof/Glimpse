# Glimpse operating instructions

Read `CLAUDE.md` and applicable `.claude/rules/` before changing code. Code reviews use the repository's A1–A8 checklist. Read `docs/product-inventory.md` and the current section of `docs/stability-roadmap.md` before selecting work; dated audit findings may already be resolved.

Glimpse is a macOS 14+ Swift 6/AppKit/SwiftUI/TCA product with a local GlimpseCore package. The shared AI proxy is an external service; its server source and operations are outside this repository's verified inventory. Implement additional platforms only when product evidence calls for them.

Keep both locked dependency graphs aligned. Use focused behavioral regressions during development and `tools/scripts/quality-gate.sh` for exact-source integration. Retain logs, source identity and xcresults outside tracked source. Preserve the test-host startup guard and use injected fixtures for native boundaries.

Keep status-button rendering in one image. Layout observation and mutation must converge through unchanged-state/frame guards. Preserve reusable-panel show/hide hooks, text editing and shortcut recording.

Distinguish source findings, fixture results, installed native checks and artifact verification. User-facing releases synchronize all four marketing versions, four build numbers, README badge and readiness evidence. Local hooks enforce exact staged-source quality without release-health queries; pre-push is a no-op and the installer preserves custom hooks and worktree isolation. Canonical-main PR admission uses trusted main's existing gate. Use ordinary protected integration with fresh gate, exact head/base/checks and current main/run observations; pause merging during unchanged-main manual release/reruns and refresh afterward. Verify the terminal exact-source Release/Recovery and public signed artifacts. Failed or unavailable admission blocks integration/promotion while independent development continues.

Use available specialized agents for distinct work and independent review, with one owner per shared source file. Continue safe independent development when physical validation or another release is unavailable. Combine roles when that reduces duplication.

The original other-Mac crash is unexplained. The user deferred the real restart check. Preserve those limits; read-only process monitoring cannot prove menu-item visibility or unattended startup. Observe quietly and report meaningful health changes.

Routine work preserves production calendar permissions/data, startup preferences and signing credentials. Machine reboot/logout and expanded sensitive access require specific authorization. Avoid inspecting or transmitting secrets and private calendar content.

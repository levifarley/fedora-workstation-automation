---
name: deadman
description: Status and help for Levi's remote lock/locate/scrub/wipe system (`deadman` CLI; orders are signed on his phone). Use for "/deadman", "is remote wipe armed", "where is my laptop", "how do I wipe it remotely", "deadman log". Claude can only READ status here and never orders, arms, signs or triggers anything.
---

**How it works.** The root agent `/usr/local/bin/deadman-agent` (timer every 2 min, watched job "deadman", deliberately not pausable)
pulls orders from a private ntfy channel. It executes only orders signed by Levi's phone key: the trust store is
`/etc/deadman/allowed_signers` (root-only), namespace `deadman@fedora`. Each order must name this machine, be under 15 min old and
carry an unused nonce; a wipe also needs the phrase `WIPE <machine-id[:8]>`. Actions: test, locate, lost/found, lock/unlock, scrub, wipe.
Wipe = `cryptsetup erase` of every LUKS device (crypto-erase) + power off. Without encryption it falls back to scrub + power off.
Every order, accepted or rejected, is logged (journal tag `deadman`) and emailed via `/usr/local/bin/watcher-alert`.
Source: `~/.config/deadman/` (system/ = agent + units, phone/deadman-order = the phone script, install.sh).

**Claude's role is read-only.** The guard hard-blocks Claude from `deadman arm`, `deadman phone-setup`, `deadman-order`, running the agent
(except --selftest/--locate), `ssh-keygen -Y sign`, /etc/deadman, cryptsetup erase/wipefs/mkfs/dd to disks, and passwd -l/-u. Never try to get
around this, never suggest weakening it, and never ask Levi for his deadman key or passphrase.

Arguments: `$ARGUMENTS`

- No args / "status": `deadman` (agent polling? armed? disk encrypted? lost mode?) and `deadman log`. Explain gaps and the fix,
  e.g. "not armed → run `deadman phone-setup` in your terminal, then `deadman arm '<key>'`".
- "where": `deadman where` (location as the laptop sees it right now; nothing is sent).
- "selftest": `deadman selftest` (11 signature/freshness/replay checks with a throwaway key).
- "how do I wipe / lock / locate": explain the phone commands (`deadman-order test|locate|lost|found|lock|unlock|scrub|wipe`) and suggest
  `deadman-order test` first. If the laptop is lost or stolen: `lost` for location reports, `lock`, then `scrub` or `wipe` if needed; also
  revoke Google sessions, the GitHub token and the Tailscale device from the phone.
- Before the encrypted reinstall, a wipe can only scrub. After it, the deadman agent detects LUKS automatically (status shows "encrypted: yes").

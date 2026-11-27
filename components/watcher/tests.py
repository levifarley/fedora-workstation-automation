#!/usr/bin/python3 -I
"""watcher test — end-to-end checks that the system and its automation actually work (not just that jobs ran).

usage (via `watcher test`; this file is ~/.config/watcher/tests.py):
  watcher test                 quick suite (~20s): system, nvidia, automation, backup, snapshots, disks, configs, dvd tools
  watcher test --full          also: restore random files from the Drive backup and compare them, snapshot round-trip,
                        package repos reachable, Drive quota (a few minutes)
  watcher test <group> [...]   only these groups (e.g. watcher test backup snapshots --full)
  watcher test list            list all tests
  watcher test baseline        re-record known-good listening ports + firewall config (after an intended change)
  watcher test report          show the last run's report
Weekly full run: user timer systest.timer (watched job "tests"). Add tests: @test("group") functions below. Results: ~/.local/state/tests/
"""
import calendar, glob, hashlib, json, os, random, re, shutil, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
USER_NAME = os.path.basename(HOME)
STATE = f"{HOME}/.local/state/tests"
TTY = sys.stdout.isatty()
def c(code, s): return f"\033[{code}m{s}\033[0m" if TTY else s

TESTS = []  # (group, name, full_only, fn)
def test(group, full=False):
    def deco(fn):
        TESTS.append((group, fn.__name__.replace("_", "-"), full, fn)); return fn
    return deco

class Skip(Exception): pass

def run(args, timeout=60, env=None, **kw):
    e = dict(os.environ, **(env or {}))
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=e, **kw)

def ok(cond, fail_msg, ok_msg=""):
    if not cond: raise AssertionError(fail_msg)
    return ok_msg

VERIFY = f"{HOME}/.local/state/backup/verify.json"

def verify_result(part, name, max_age_h, refresh=False):
    """Read one check from the root backup job's verify.json (the repo itself is root-only since 2026-11-27).
    refresh=True (full tests): if the full verification is stale, run it now (polkit lets levi start it) and wait."""
    def load():
        try: return json.load(open(VERIFY)).get(part) or {}
        except (OSError, ValueError): return {}
    v = load()
    if refresh and time.time() - v.get("time", 0) > max_age_h * 3600:
        run(["systemctl", "start", "backup-verify.service"], timeout=7200); v = load()
    if not v: raise AssertionError(f"no {part} backup verification yet — run: backup verify" if part == "full" else
                                   "the backup hasn't written verification results yet (run: backup)")
    age = (time.time() - v["time"]) / 3600
    if age > max_age_h: raise AssertionError(f"backup verification ({part}) is {age:.0f}h old — run: backup verify")
    c = v.get("checks", {}).get(name)
    if c is None: raise Skip(f"{name} not part of the {part} verification")
    if c["ok"] is None: raise Skip(c["msg"])
    if not c["ok"]: raise AssertionError(c["msg"])
    return c["msg"]

def have(cmd): return shutil.which(cmd) is not None

# ------------------------------------------------------------------ system
@test("system")
def no_failed_units():
    bad = []
    for scope in ([], ["--user"]):
        out = run(["systemctl", *scope, "--failed", "--plain", "--no-legend"]).stdout
        bad += [l.split()[0] for l in out.splitlines() if l.split()]
    return ok(not bad, f"failed units: {', '.join(bad)}", "none")

@test("system")
def firewall_running():
    # ask systemd, not firewall-cmd: firewall-cmd needs a logged-in session (polkit) and says "not running" from the nightly job
    return ok(run(["systemctl", "is-active", "firewalld"]).stdout.strip() == "active", "firewalld not running", "firewalld running")

@test("system")
def clock_synced():
    return ok(run(["timedatectl", "show", "-p", "NTPSynchronized", "--value"]).stdout.strip() == "yes", "clock not NTP-synced", "NTP synced")

@test("system")
def internet_and_dns():
    r = run(["getent", "hosts", "www.google.com"], timeout=15)
    return ok(r.returncode == 0, "DNS lookup failed", "DNS ok")

@test("system")
def battery_charge_limits():
    p = "/sys/class/power_supply/BAT0/charge_control_end_threshold"
    if not os.path.exists(p): raise Skip("no battery threshold support")
    s, e = (open(p.replace("end", "start")).read().strip(), open(p).read().strip())
    return ok(e == "80", f"charge limits are {s}/{e}% (expected 75/80)", f"{s}–{e}%")

@test("system")
def root_free_space():
    st = os.statvfs("/"); free = st.f_bavail / st.f_blocks
    return ok(free > 0.10, f"/ only {free:.0%} free", f"{free:.0%} free")

@test("system")
def reboot_not_pending():
    f = f"{HOME}/.local/state/update/reboot-needed"
    return ok(not os.path.exists(f), "reboot recommended: " + (open(f).read().strip() if os.path.exists(f) else ""), "none pending")

# ------------------------------------------------------------------ nvidia
def drv(): return run(["rpm", "-q", "--qf", "%{VERSION}", "xorg-x11-drv-nvidia"]).stdout.strip()

@test("nvidia")
def driver_loaded_matches():
    if run(["rpm", "-q", "xorg-x11-drv-nvidia"]).returncode: raise Skip("no NVIDIA driver installed")
    loaded = open("/sys/module/nvidia/version").read().strip() if os.path.exists("/sys/module/nvidia/version") else "not loaded"
    return ok(loaded == drv(), f"loaded module {loaded} ≠ installed driver {drv()} (reboot?)", f"{loaded}")

@test("nvidia")
def module_built_for_newest_kernel():
    if run(["rpm", "-q", "xorg-x11-drv-nvidia"]).returncode: raise Skip("no NVIDIA driver installed")
    k = sorted(os.listdir("/lib/modules"), key=lambda v: [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", v)])[-1]
    v = run(["modinfo", "-k", k, "-F", "version", "nvidia"]).stdout.strip()
    return ok(v == drv(), f"kernel {k} has nvidia module '{v or 'MISSING'}' (driver {drv()}) — don't boot it", f"{k}")

@test("nvidia")
def gpu_responds():
    if not have("nvidia-smi"): raise Skip("nvidia-smi not installed")
    r = run(["nvidia-smi", "--query-gpu=name,temperature.gpu", "--format=csv,noheader"], timeout=20)
    return ok(r.returncode == 0, f"nvidia-smi failed: {r.stderr.strip()[:120]}", r.stdout.strip())

# ------------------------------------------------------------------ automation
@test("automation")
def watcher_healthy():
    r = run([f"{HOME}/.local/bin/watcher", "check"], timeout=60)
    # ignore the "tests" job's own result (this suite) and info lines
    lines = [l.strip() for l in r.stdout.splitlines() if l.strip() and "ℹ" not in l
             and not re.search(r"\btests:", l) and not l.startswith(("-", "    "))]
    return ok(not lines, "; ".join(lines)[:300], "watcher check clean")

@test("automation")
def nightly_timer_armed():
    p = run(["systemctl", "show", "nightly-maintenance.timer", "-pActiveState", "-pUnitFileState"]).stdout
    return ok("ActiveState=active" in p and "UnitFileState=enabled" in p, "nightly-maintenance.timer not enabled/active", "armed")

@test("automation")
def watched_scripts_installed_match_source():
    pairs = [("backup/system/system-backup", "system-backup"), ("update/system/system-update", "system-update"),
             ("disk-health/system/disk-health", "disk-health"), ("watcher/system/watcher-notify", "watcher-notify"),
             ("watcher/system/watcher-alert", "watcher-alert"), ("watcher/system/watcher-gate", "watcher-gate")]
    stale = [dst for src, dst in pairs if os.path.exists(f"{HOME}/.config/{src}") and
             (not os.path.exists(f"/usr/local/bin/{dst}") or open(f"{HOME}/.config/{src}", "rb").read() != open(f"/usr/local/bin/{dst}", "rb").read())]
    return ok(not stale, f"installed copy out of date: {', '.join(stale)} — run ~/.config/watcher/install.sh", "all in sync")

# ------------------------------------------------------------------ backup
@test("backup")
def credentials_root_only():
    c = "/etc/backup"
    if not os.path.isdir(c): raise AssertionError("/etc/backup missing — run ~/.config/backup/install.sh")
    st = os.stat(c)
    if st.st_uid != 0 or st.st_mode & 0o077: raise AssertionError("/etc/backup must be root-owned, mode 700")
    if os.access(f"{c}/env", os.R_OK): raise AssertionError("the backup settings in /etc/backup are readable by levi")
    left = [p.replace(HOME, "~") for p in (f"{HOME}/.config/backup/restic-password", f"{HOME}/.config/rclone/rclone.conf") if os.path.exists(p)]
    if left: raise AssertionError(f"a user-readable copy of a backup credential is still in your home: {left} — re-run ~/.config/backup/install.sh")
    u = run(["systemctl", "show", "system-backup.service", "-p", "User", "--value"]).stdout.strip()
    if u not in ("", "root"): raise AssertionError(f"system-backup.service runs as '{u}', not root — re-run ~/.config/backup/install.sh")
    return "root-only (/etc/backup 700), no copies in ~, the backup job runs as root"

@test("backup")
def drive_reachable(): return verify_result("quick", "drive_reachable", 36)

@test("backup")
def latest_snapshot_fresh(): return verify_result("quick", "latest_snapshot_fresh", 36)

@test("backup")
def restore_guide_on_drive_current():
    try: return verify_result("quick", "restore_guide_current", 36)
    except AssertionError:
        last_ok = f"{HOME}/.local/state/backup/last-success"
        if os.path.exists(last_ok) and os.path.getmtime(f"{HOME}/.config/backup/RESTORE.md") > float(open(last_ok).read().strip() or 0):
            raise Skip("edited since the last backup; the next backup uploads it")
        raise

@test("backup", full=True)
def restore_random_files(): return verify_result("full", "restore_random_files", 8 * 24, refresh=True)

@test("backup", full=True)
def drive_quota(): return verify_result("full", "drive_quota", 8 * 24, refresh=True)

# ------------------------------------------------------------------ snapshots
def snapper_home():
    if not have("snapper"): raise Skip("snapper not installed (~/.config/snapshots/install.sh)")
    r = run(["snapper", "--jsonout", "-c", "home", "list"])
    if r.returncode: raise Skip("home snapshots not set up (~/.config/snapshots/install.sh)")
    return [s for s in json.loads(r.stdout)["home"] if s["number"] != 0]

@test("snapshots")
def home_snapshots_recent():
    hs = snapper_home()
    if not hs: raise AssertionError("no home snapshots yet")
    t = time.mktime(time.strptime(hs[-1]["date"], "%Y-%m-%d %H:%M:%S"))
    age = (time.time() - t) / 3600
    return ok(age < 2.5, f"newest home snapshot is {age:.1f}h old (hourly timeline not running?)", f"#{hs[-1]['number']}, {age*60:.0f} min old")

@test("snapshots")
def dnf_transactions_snapshotted():
    if not os.path.isdir("/.snapshots"): raise Skip("system snapshots not set up")
    posts = []
    for f in glob.glob("/.snapshots/*/info.xml"):
        x = open(f).read()
        if "<type>post</type>" in x:
            posts.append(calendar.timegm(time.strptime(re.search(r"<date>(.*?)</date>", x)[1], "%Y-%m-%d %H:%M:%S")))
    hist = run(["dnf", "history", "list"], timeout=60).stdout.splitlines()
    last = [l for l in hist if re.match(r"\s*\d+ ", l)]   # newest first
    if not last: raise Skip("no dnf history")
    m = re.search(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", last[0])
    t = calendar.timegm(time.strptime(m[1], "%Y-%m-%d %H:%M:%S"))  # dnf history shows UTC
    # setup time = the oldest system snapshot (the folder's ctime moves with every new snapshot)
    dates = [calendar.timegm(time.strptime(re.search(r"<date>(.*?)</date>", open(f).read())[1], "%Y-%m-%d %H:%M:%S"))
             for f in glob.glob("/.snapshots/*/info.xml")]
    setup = min(dates) if dates else time.time()
    if t < setup: raise Skip("no dnf transaction since snapshots were set up")
    return ok(any(p >= t - 120 for p in posts), "last dnf transaction has no post snapshot (actions plugin not working?)", "last transaction covered")

@test("snapshots", full=True)
def home_snapshot_roundtrip():
    snapper_home()
    d = f"{HOME}/.local/state/tests"; os.makedirs(d, exist_ok=True)
    f = f"{d}/roundtrip.txt"; token = f"tests {time.time()}"
    open(f, "w").write(token)
    n = run(["snapper", "-c", "home", "create", "-c", "number", "-p", "-d", "tests round-trip"]).stdout.strip()
    try:
        open(f, "w").write("changed")
        snap = f"/home/.snapshots/{n}/snapshot/{f[len('/home/'):]}"
        got = open(snap).read()
        return ok(got == token, "snapshot copy doesn't match what was written", f"snapshot #{n} read back correctly")
    finally:
        run(["snapper", "-c", "home", "delete", n])
        os.remove(f)

# ------------------------------------------------------------------ movies (Samsung SSD → Drive)
SSD = f"/run/media/{os.environ.get('USER', 'levi')}/Samsung SSD"

@test("movies")
def movies_backup_fresh():
    f = f"{HOME}/.local/state/movies-backup/last-success"
    if not os.path.exists(f): raise Skip("first movie backup hasn't finished yet")
    age = (time.time() - float(open(f).read())) / 86400
    return ok(age < 8, f"movies last backed up {age:.0f} days ago — plug in the Samsung SSD", f"{age*24:.0f}h ago")

@test("movies", full=True)
def movies_restore_sample():
    if not os.path.exists(f"{HOME}/.local/state/movies-backup/last-success"): raise Skip("no movie backup yet")
    return verify_result("full", "movies_restore_sample", 8 * 24, refresh=True)

# ------------------------------------------------------------------ security
BASE = f"{HOME}/.config/watcher/baseline"

def listening():
    out = run(["ss", "-tulnH"]).stdout
    socks = set()
    for l in out.splitlines():
        f = l.split()
        if len(f) < 5: continue
        proto, addr = f[0], f[4]
        host, _, port = addr.rpartition(":")
        if host.startswith(("127.", "[::1]")) or "%lo" in host or not port.isdigit(): continue
        if host.startswith("192.168.122.") or "%virbr" in host: continue   # libvirt's internal VM network (DNS/DHCP for VMs only)
        if proto == "udp" and int(port) >= 32768: continue          # ephemeral client sockets
        socks.add(f"{proto}:{port}")
    return socks

def firewall_state():
    r = run(["firewall-cmd", "--list-all"])
    if r.returncode != 0 or not r.stdout.strip():
        raise Skip("firewall-cmd can't be queried from here (no logged-in session); checked again in an interactive run")
    zone = run(["firewall-cmd", "--get-default-zone"]).stdout.strip()
    conf = r.stdout
    conf = "\n".join(l for l in conf.splitlines() if not l.strip().startswith("interfaces:"))
    return f"default zone: {zone}\n{conf}"

def record_baseline():
    os.makedirs(BASE, exist_ok=True)
    open(f"{BASE}/ports.txt", "w").write("\n".join(sorted(listening())) + "\n")
    open(f"{BASE}/firewall.txt", "w").write(firewall_state())
    print(f"recorded baseline in {BASE}: {len(listening())} listening ports + firewall config")

@test("security")
def no_new_listening_ports():
    f = f"{BASE}/ports.txt"
    if not os.path.exists(f): record_baseline(); return "baseline recorded (first run)"
    known = set(open(f).read().split())
    new = sorted(listening() - known)
    return ok(not new, f"new listening ports: {', '.join(new)} — if expected: watcher test baseline", f"{len(known)} known ports, none new")

@test("security")
def firewall_unchanged():
    f = f"{BASE}/firewall.txt"
    if not os.path.exists(f): record_baseline(); return "baseline recorded (first run)"
    cur, old = firewall_state(), open(f).read()
    diff = [l.strip() for l in cur.splitlines() if l not in old.splitlines()]
    return ok(cur == old, f"firewall changed: {'; '.join(diff)[:200]} — if expected: watcher test baseline", "same as baseline")

@test("security")
def ssh_server_off_or_locked():
    active = run(["systemctl", "is-active", "sshd"]).stdout.strip() == "active"
    enabled = run(["systemctl", "is-enabled", "sshd"]).stdout.strip() == "enabled"
    if not active and not enabled: return "sshd off"
    # SSH on is fine ONLY in the phone-access configuration: keys only, levi only, no forwarding, and only reachable over Tailscale
    # sshd's config dir is root-only, so the installer records what sshd ACTUALLY enforces (sshd -T) in a readable snapshot
    snap = "/var/lib/remote-access/sshd-effective"
    if not os.path.exists(snap):
        raise AssertionError("SSH is on but its hardening was never verified — run ~/.config/remote/install.sh or: sudo systemctl disable --now sshd")
    if os.path.getmtime("/etc/ssh/sshd_config.d") > os.path.getmtime(snap) + 5 or os.path.getmtime("/etc/ssh/sshd_config") > os.path.getmtime(snap) + 5:
        raise AssertionError("SSH config changed after it was last verified — re-run ~/.config/remote/install.sh to re-check it")
    eff = set(l.strip().lower() for l in open(snap))
    need = {"passwordauthentication no", "kbdinteractiveauthentication no", "permitrootlogin no", "allowusers levi",
            "allowagentforwarding no", "authenticationmethods publickey", "allowtcpforwarding no"}
    missing = sorted(need - eff)
    if missing: raise AssertionError(f"SSH hardening not in effect: {', '.join(missing)}")
    txt = "verified"
    wifi_zone = run(["firewall-cmd", "--get-default-zone"])
    if wifi_zone.returncode == 0:
        svcs = run(["firewall-cmd", "--zone", wifi_zone.stdout.strip(), "--list-services"]).stdout.split()
        if "ssh" in svcs: raise AssertionError(f"SSH is open on the Wi-Fi zone ({wifi_zone.stdout.strip()}) — it must be Tailscale-only")
    return "SSH on for phone access: keys only, levi only, no forwarding" + ("" if txt else " (config not readable here)") + ", Tailscale-only"

@test("security")
def deadman_agent_ready():
    agent, status = "/usr/local/bin/deadman-agent", "/var/lib/deadman/status.json"
    if not os.path.exists(agent): raise Skip("deadman not installed (~/.config/deadman/install.sh)")
    st = os.stat(agent)
    if st.st_uid != 0 or st.st_mode & 0o022: raise AssertionError("deadman-agent is not root-owned/read-only")
    src = f"{HOME}/.config/deadman/system/deadman-agent"
    if os.path.exists(src) and open(src, "rb").read() != open(agent, "rb").read():
        raise AssertionError("installed deadman-agent differs from ~/.config/deadman/system (review + reinstall)")
    r = run(["python3", "-I", agent, "--selftest"], timeout=60)
    if r.returncode != 0: raise AssertionError("order verification self-test failed: " + r.stdout.strip()[-200:])
    s = json.load(open(status)) if os.path.exists(status) else {}
    age = time.time() - s.get("last_poll", 0)
    if age > 900: raise AssertionError(f"agent hasn't checked for orders in {age/60:.0f} min")
    if not s.get("armed"): raise Skip("installed and polling, but not armed yet (deadman phone-setup → deadman arm)")
    return "polling, armed, signature checks pass" + ("" if s.get("encrypted") else " — disk NOT encrypted (wipe = scrub only)")

@test("security")
def deadman_away_alerts():
    status = "/var/lib/deadman/status.json"
    if not os.path.exists(status): raise Skip("deadman not installed")
    s = json.load(open(status))
    if "away" not in s: raise Skip("agent without away alerts installed (~/.config/deadman/install.sh)")
    a = s["away"] or ""
    if a.startswith("no home network"): raise AssertionError("away alerts can't work: no home router trusted — with the laptop at home, from the phone: ~/bin/deadman-order trust")
    if a.startswith("away check failed"): raise AssertionError(f"deadman {a} (see: journalctl -u deadman-agent)")
    if a.startswith("AWAY"): return f"ON ALERT — laptop is {a.lower()} (email sent)"
    return f"watching networks — now: {a}"

@test("security")
def no_root_equivalent_access():
    """Anything running as levi (incl. Claude) must not have a passwordless path to root: that would bypass every
    root-owned protection (claude-guard, deadman trust store). Docker must be rootless."""
    import grp
    risky = {"docker", "disk", "libvirt", "lxd", "incus-admin", "shadow"}
    member = sorted(g.gr_name for g in grp.getgrall() if g.gr_name in risky and USER_NAME in g.gr_mem)
    if member: raise AssertionError(f"{USER_NAME} is in root-equivalent group(s): {', '.join(member)} (sudo gpasswd -d {USER_NAME} <group>)")
    rootful = [u for u in ("docker.service", "docker.socket") if run(["systemctl", "is-active", u]).stdout.strip() == "active"]
    if rootful: raise AssertionError(f"rootful Docker is running ({', '.join(rootful)}) — use rootless: sudo systemctl disable --now docker.service docker.socket")
    if os.path.exists("/var/run/docker.sock") and os.access("/var/run/docker.sock", os.W_OK):
        raise AssertionError("/var/run/docker.sock (root Docker) is writable by this user")
    rl = run(["systemctl", "--user", "is-active", "docker"]).stdout.strip() == "active"
    return "no root-equivalent groups, root Docker off" + (", rootless Docker running" if rl else "")

@test("security")
def remote_access_private():
    if run(["systemctl", "is-active", "sshd"]).stdout.strip() != "active": raise Skip("SSH off — no remote access")
    if not shutil.which("tailscale"):
        raise AssertionError("SSH is on but Tailscale isn't installed — run ~/.config/remote/install.sh (or turn SSH off)")
    r = run(["tailscale", "status", "--json"], timeout=20)
    if r.returncode != 0: raise AssertionError("SSH is on but Tailscale isn't connected — phone access won't work")
    j = json.loads(r.stdout)
    funnel = any(p.get("Funnel") for p in [j.get("Self", {})] if isinstance(p, dict))
    if funnel: raise AssertionError("Tailscale Funnel exposes this laptop to the public internet — turn it off")
    name = (j.get("Self", {}).get("DNSName") or "").split(".")[0]
    if name and name != "system":
        raise AssertionError(f"Tailscale calls this laptop '{name}', not 'system' (an old device holds the name) — the phone's "
                             "`ssh system` goes to the wrong machine. login.tailscale.com/admin/machines: remove the old one, rename this one")
    return "Tailscale up as 'system', nothing public"

@test("security")
def no_login_attack_signs():
    out = run(["journalctl", "--since", "-24h", "--no-pager", "-q", "-o", "cat",
               "-g", "authentication failure|Failed password|Invalid user|FAILED LOGIN"], timeout=60).stdout
    n = len([l for l in out.splitlines() if l.strip()])
    return ok(n <= 10, f"{n} failed login/auth attempts in the last 24h — check: journalctl --since -24h -g 'authentication failure'", f"{n} failed auth attempts in 24h")

@test("security")
def secrets_private():
    paths = [f"{HOME}/.config/backup/restic-password", f"{HOME}/.config/rclone/rclone.conf",
             f"{HOME}/.config/watcher/ntfy-topic", f"{HOME}/.config/watcher/healthchecks-url",
             f"{HOME}/.config/watcher/smtp-netrc"]
    bad = [p for p in paths if os.path.exists(p) and os.stat(p).st_mode & 0o077]
    if bad: raise AssertionError(f"readable by other users: {bad} — chmod 600")
    # the nightly /etc + Tailscale archives (password hashes, host keys, node key) must stay private to levi
    sb = "/var/lib/system-backup"
    if os.path.isdir(sb) and os.stat(sb).st_mode & 0o077: raise AssertionError(f"{sb} is readable by other users — chmod 700")
    # a finished restore's staging copy of the OLD /etc shouldn't linger (it's an unprotected copy of every system secret)
    st = "/var/tmp/restore-staging"
    if os.path.isdir(st) and time.time() - os.stat(st).st_mtime > 3 * 86400:
        raise AssertionError(f"{st} (copy of the old /etc from a restore) is still here after 3+ days — once ~/restore-etc-review.txt "
                             f"is done: sudo rm -rf {st}")
    return "backup/Drive/alert secrets are mode 600, system archives private" + (", restore staging still present (delete when the /etc review is done)" if os.path.isdir(st) else "")

@test("security")
def dotfiles_no_secrets():
    gd = f"{HOME}/.dotfiles"
    if not os.path.isdir(gd): raise Skip("dots repo not set up")
    files = run(["git", f"--git-dir={gd}", f"--work-tree={HOME}", "ls-files"], cwd=HOME).stdout.splitlines()
    bad = [f for f in files if re.search(r"restic-password|ntfy-topic|healthchecks-url|smtp-netrc|rclone\.conf|\.ssh/", f)]
    return ok(not bad, f"secret files are tracked in ~/.dotfiles: {bad}", f"{len(files)} tracked files, no secrets")

@test("security")
def claude_guard_installed():
    ms, gp, src = "/etc/claude-code/managed-settings.json", "/usr/local/bin/claude-guard", f"{HOME}/.config/claude-guard/claude-guard"
    if not os.path.exists(ms): raise AssertionError("Claude guard not installed — run ~/.config/claude-guard/install.sh")
    probs = []
    for f in (ms, gp, "/etc/claude-code"):
        if not os.path.exists(f): probs.append(f"{f} missing"); continue
        st = os.stat(f)
        if st.st_uid != 0 or st.st_mode & 0o022: probs.append(f"{f} not root-owned/read-only")
    j = json.load(open(ms))
    if j.get("allowManagedHooksOnly") is not True: probs.append("allowManagedHooksOnly is off")
    if not any(h.get("command") == gp for blk in j.get("hooks", {}).get("PreToolUse", []) for h in blk.get("hooks", [])):
        probs.append("PreToolUse guard hook missing")
    if os.path.exists(gp) and os.path.exists(src) and open(gp, "rb").read() != open(src, "rb").read():
        probs.append("installed guard differs from ~/.config/claude-guard (review + reinstall)")
    return ok(not probs, "; ".join(probs), "root-owned, managed hooks only, matches source")

@test("security")
def claude_guard_decides_correctly():
    if not os.path.exists("/usr/local/bin/claude-guard"): raise Skip("guard not installed")
    r = run(["python3", "-I", f"{HOME}/.config/claude-guard/selftest.py"], timeout=60)
    return ok(r.returncode == 0, r.stdout.strip()[-300:], r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "ok")

@test("security")
def claude_activity_is_audited():
    if not os.path.exists("/etc/claude-code/managed-settings.json"): raise Skip("guard not installed")
    # only sessions newer than the guard install count (restored transcripts keep their old timestamps)
    since = max(time.time() - 86400, os.path.getmtime("/etc/claude-code/managed-settings.json"))
    recent = [f for f in glob.glob(f"{HOME}/.claude/projects/*/*.jsonl") if os.path.getmtime(f) > since]
    if not recent: raise Skip("no Claude sessions in the last 24h")
    n = len(run(["journalctl", "-t", "claude-audit", "--since", "-24h", "-o", "cat", "--no-pager"]).stdout.splitlines())
    return ok(n > 0, "Claude Code was used in the last 24h but nothing reached the audit log — hooks may be disabled",
              f"{n} audited actions in 24h")

# ------------------------------------------------------------------ disks
@test("disks")
def disk_health_report():
    f = f"{HOME}/.local/state/disk-health/last-result"
    if not os.path.exists(f): raise Skip("disk-health hasn't run yet")
    first = open(f).readline().strip()
    return ok(" FAILED" not in first, first, re.sub(r"^\S+\s+", "", first)[:110])

# ------------------------------------------------------------------ configs
@test("configs")
def shell_configs_parse():
    bad = [f for f in glob.glob(f"{HOME}/.bashrc.d/*") + [f"{HOME}/.bashrc"] if run(["bash", "-n", f]).returncode]
    return ok(not bad, f"syntax errors: {bad}", "bashrc + bashrc.d ok")

@test("configs")
def scripts_parse():
    bad = []
    for f in glob.glob(f"{HOME}/.local/bin/*") + glob.glob(f"{HOME}/.config/watcher/*.py"):
        if not os.path.isfile(f) or os.path.getsize(f) > 2_000_000: continue
        head = open(f, "rb").read(64)
        if b"python" in head: r = run(["python3", "-c", "import sys,ast; ast.parse(open(sys.argv[1]).read())", f])
        elif b"bash" in head or head.startswith(b"#!/bin/sh"): r = run(["bash", "-n", f])
        else: continue
        if r.returncode: bad.append(os.path.basename(f))
    return ok(not bad, f"don't parse: {bad}", "all scripts parse")

@test("configs")
def commands_documented():
    """Every custom script says what it is and where it belongs, so `watcher commands` stays complete."""
    r = run(["python3", "-I", "-c", f"""
import runpy
w = runpy.run_path('{HOME}/.local/bin/watcher', run_name='watcher_lib')
for sc in w['all_scripts']():
    if not sc['binary'] and (not sc['desc'] or sc['group'] == 'Other'): print(sc['name'])
"""])
    bad = r.stdout.split()
    return ok(r.returncode == 0 and not bad, f"missing '# name — description' or '# group:' line: {', '.join(bad) or r.stderr[-120:]}",
              "every script has a description + group")


@test("configs")
def architecture_doc_current():
    """~/Documents/System-Architecture.md must mention every watched job and every custom command."""
    doc = f"{HOME}/Documents/System-Architecture.md"
    if not os.path.exists(doc): raise AssertionError("~/Documents/System-Architecture.md is missing")
    text = open(doc).read()
    w = runpy_watcher()
    jobs = [j["name"] for j in w["discover"]()]
    cmds = [s["name"] for s in w["all_scripts"]() if not s["binary"]]
    missing = [f"job {j}" for j in jobs if j not in text] + [f"command {c}" for c in cmds if c not in text]
    return ok(not missing, "architecture doc is behind — add: " + ", ".join(missing), f"covers {len(jobs)} jobs + {len(cmds)} commands")

def runpy_watcher():
    import runpy
    return runpy.run_path(f"{HOME}/.local/bin/watcher", run_name="watcher_lib")


@test("configs")
def zed_settings_valid():
    p = f"{HOME}/.config/zed/settings.json"
    txt = re.sub(r"^\s*//.*$", "", open(p).read(), flags=re.M)
    txt = re.sub(r",(\s*[}\]])", r"\1", txt)
    try: json.loads(txt)
    except ValueError as e: raise AssertionError(f"settings.json: {e}")
    return "settings.json valid"

@test("configs")
def ssh_key_private():
    keys = [k for k in glob.glob(f"{HOME}/.ssh/id_*") if not k.endswith(".pub")]
    if not keys: raise Skip("no ssh keys")
    bad = [k for k in keys if os.stat(k).st_mode & 0o077]
    return ok(not bad, f"readable by others: {bad}", f"{len(keys)} key(s), mode 600")

# ------------------------------------------------------------------ dvd
@test("dvd")
def rip_and_burn_tools_present():
    need = ["HandBrakeCLI", "ffmpeg", "ffprobe", "dvdauthor", "growisofs", "genisoimage", "jq"]
    miss = [t for t in need if not have(t)]
    if run(["flatpak", "info", "com.makemkv.MakeMKV"]).returncode: miss.append("MakeMKV flatpak")
    return ok(not miss, f"missing: {', '.join(miss)}", "MakeMKV, HandBrake, ffmpeg, dvdauthor, growisofs present")

@test("dvd")
def movielist_watcher_active():
    return ok(run(["systemctl", "--user", "is-active", "movielist.path"]).stdout.strip() == "active", "movielist.path not active", "active")

# ------------------------------------------------------------------ updates (full)
@test("updates", full=True)
def package_repos_reachable():
    r = run(["dnf", "check-upgrade", "--refresh", "-q"], timeout=300)
    n = len([l for l in r.stdout.splitlines() if re.match(r"^\S+\.\S+\s+\S+\s+\S+", l)])
    return ok(r.returncode in (0, 100), f"dnf can't reach repos: {r.stderr.strip()[-150:]}", f"repos ok, {n} updates pending")


# ------------------------------------------------------------------ runner
def main():
    a = sys.argv[1:]
    if a[:1] == ["list"]:
        for g, n, full, _ in TESTS: print(f"  {g:<11} {n}" + (c("2", "  (--full)") if full else ""))
        return 0
    if a[:1] == ["report"]:
        p = f"{STATE}/last-report.txt"
        print(open(p).read() if os.path.exists(p) else "no report yet"); return 0
    if a[:1] == ["baseline"]:
        record_baseline(); return 0
    if a[:1] in (["-h"], ["--help"], ["help"]):
        print(__doc__.split("usage:")[1].rstrip()); return 0
    full = "--full" in a
    groups = [x for x in a if not x.startswith("-")]
    sel = [t for t in TESTS if (not groups or t[0] in groups) and (full or not t[2])]
    print(c("1", f"Running {len(sel)} tests" + (" (full)" if full else "")) + "\n")
    res, report, cur = {"pass": 0, "fail": 0, "skip": 0}, [], None
    for g, n, _, fn in sel:
        if g != cur: print(c("1", g)); cur = g
        t0 = time.time()
        try:
            msg = fn() or ""; r = "pass"
        except Skip as e: msg, r = str(e), "skip"
        except AssertionError as e: msg, r = str(e), "fail"
        except Exception as e: msg, r = f"error: {type(e).__name__}: {e}", "fail"
        res[r] += 1
        icon = {"pass": c("32", "✔"), "fail": c("31", "✘"), "skip": c("2", "–")}[r]
        took = time.time() - t0
        print(f"  {icon} {n:<38} {c('2' if r != 'fail' else '31', msg[:140])}" + (c("2", f"  {took:.0f}s") if took >= 2 else ""))
        report.append(f"{r.upper():4} {g}/{n}: {msg}")
    status = "FAILED" if res["fail"] else "OK"
    summary = f"{res['pass']} passed · {res['fail']} failed · {res['skip']} skipped" + (" · full" if full else "")
    print(f"\n{c('32' if status == 'OK' else '31', ('✔ ' if status == 'OK' else '✘ ') + summary)}")
    os.makedirs(STATE, exist_ok=True)
    if groups:   # a partial run doesn't replace the suite's overall result
        with open(f"{STATE}/last-partial.txt", "w") as f: f.write("\n".join(report) + "\n")
        return 1 if res["fail"] else 0
    with open(f"{STATE}/last-result", "w") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')} {status} · {summary}\n")
        for l in report:
            if l.startswith("FAIL"): f.write(f"  - {l[5:]}\n")
    with open(f"{STATE}/last-report.txt", "w") as f:
        f.write(f"tests run {time.strftime('%F %T')}{' (full)' if full else ''}\n" + "\n".join(report) + "\n")
    return 1 if res["fail"] else 0


if __name__ == "__main__":
    try: sys.exit(main())
    except KeyboardInterrupt: sys.exit(130)

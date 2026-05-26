#!/usr/bin/env python3
"""
iptables-restore-fail2ban.py — Restore fail2ban IP bans from the latest snapshot.

Companion to iptables-autoexpiry.py: runs once at boot (via systemd oneshot
service) after fail2ban.service has started, and reinjects the fail2ban
REJECT rules that were captured in the most recent iptables/ip6tables
snapshot.

Designed to run at boot via a systemd service with:
    Requires=fail2ban.service
    After=fail2ban.service

Exits 0 (success) when:
    - Rules are restored successfully
    - No snapshots exist (logs warning)
    - Latest snapshot is stale (logs warning)
    - No f2b-* rules found in snapshot (logs info)
"""

import argparse
import glob
import logging
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Protocol-specific configuration
# ---------------------------------------------------------------------------

PROTOCOLS = {
    "ipv4": {
        "insert_cmd_prefix": ["iptables", "-A"],
        "extension": ".iptables",
        # Match fail2ban REJECT rules: chain must start with f2b-
        "pattern": re.compile(
            r"-A (f2b-\S+) -s ([\d.]+)/32 -j REJECT --reject-with icmp-port-unreachable"
        ),
    },
    "ipv6": {
        "insert_cmd_prefix": ["ip6tables", "-A"],
        "extension": ".ip6tables",
        "pattern": re.compile(
            r"-A (f2b-\S+) -s ([0-9a-fA-F:]+)/128 -j REJECT --reject-with icmp6-port-unreachable"
        ),
    },
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def parse_snapshot_filename(filename: str) -> datetime | None:
    """Return the datetime encoded in a snapshot filename, or None."""
    stem = os.path.basename(filename)
    m = re.match(r"^(\d{4}-\d{2}-\d{2}-\d{2})\.(?:iptables|ip6tables)$", stem)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d-%H")
    except ValueError:
        return None


def find_latest_snapshot(
    snapshot_dir: str, extension: str
) -> tuple[str | None, datetime | None]:
    """
    Return (path, timestamp) of the most recent snapshot for the given
    extension, or (None, None) if no snapshot exists.
    """
    pattern = os.path.join(snapshot_dir, f"*{extension}")
    latest_path = None
    latest_ts: datetime | None = None

    for path in glob.glob(pattern):
        ts = parse_snapshot_filename(path)
        if ts and (latest_ts is None or ts > latest_ts):
            latest_ts = ts
            latest_path = path

    return latest_path, latest_ts


def parse_f2b_rules_from_snapshot(
    snapshot_path: str, pattern: re.Pattern
) -> list[tuple[str, str]]:
    """
    Parse an iptables-save snapshot and return a list of (chain, ip) tuples
    for fail2ban REJECT rules (chains starting with f2b-).
    """
    rules: list[tuple[str, str]] = []
    try:
        with open(snapshot_path, "r") as f:
            for line in f:
                m = pattern.match(line.strip())
                if m:
                    chain, ip = m.group(1), m.group(2)
                    rules.append((chain, ip))
    except (OSError, IOError) as e:
        log.warning("Could not read snapshot %s: %s", snapshot_path, e)
    return rules


def restore_rules(
    rules: list[tuple[str, str]],
    insert_cmd_prefix: list[str],
    mask: str,
    reject_flag: str,
    dry_run: bool = False,
) -> tuple[int, int]:
    """
    Reinject fail2ban rules via iptables/ip6tables -A.

    Returns (success_count, failure_count).
    """
    success = 0
    failure = 0

    for chain, ip in rules:
        cmd = insert_cmd_prefix + [
            chain,
            "-s",
            f"{ip}/{mask}",
            "-j",
            "REJECT",
            "--reject-with",
            reject_flag,
        ]
        if dry_run:
            log.info("[DRY-RUN] Would run: %s", " ".join(cmd))
            success += 1
        else:
            result = subprocess.run(cmd, capture_output=True)
            if result.returncode != 0:
                log.warning(
                    "Failed to restore rule %s from %s (rc=%d): %s",
                    ip,
                    chain,
                    result.returncode,
                    result.stderr.decode(errors="replace"),
                )
                failure += 1
            else:
                log.info("Restored ban: %s in chain %s", ip, chain)
                success += 1

    return success, failure


# ---------------------------------------------------------------------------
# Main logic per protocol
# ---------------------------------------------------------------------------


def process_protocol(
    protocol: str,
    snapshot_dir: str,
    max_age_hours: float,
    dry_run: bool,
) -> bool:
    """
    Restore fail2ban rules for one protocol.
    Returns True if rules were restored, False if skipped (no snapshot, stale,
    or no f2b rules).
    """
    cfg = PROTOCOLS[protocol]
    extension = cfg["extension"]

    log.info("=== %s ===", protocol.upper())

    # 1. Find the latest snapshot
    snapshot_path, snapshot_ts = find_latest_snapshot(snapshot_dir, extension)

    if snapshot_path is None:
        log.warning(
            "No %s snapshot found in %s; skipping restoration",
            protocol,
            snapshot_dir,
        )
        return False

    log.info("Latest %s snapshot: %s", protocol, os.path.basename(snapshot_path))

    # 2. Check freshness
    cutoff = datetime.now() - timedelta(hours=max_age_hours)
    if snapshot_ts < cutoff:
        log.warning(
            "Latest %s snapshot %s is %.1f hours old (stale, cutoff=%.1fh); skipping restoration",
            protocol,
            snapshot_ts.strftime("%Y-%m-%d %H:%M"),
            (datetime.now() - snapshot_ts).total_seconds() / 3600,
            max_age_hours,
        )
        return False

    log.info(
        "Snapshot age: %.1f hours (within %.1fh threshold)",
        (datetime.now() - snapshot_ts).total_seconds() / 3600,
        max_age_hours,
    )

    # 3. Parse f2b-* rules
    rules = parse_f2b_rules_from_snapshot(snapshot_path, cfg["pattern"])

    if not rules:
        log.info(
            "No fail2ban (f2b-*) rules in %s snapshot; nothing to restore", protocol
        )
        return False

    log.info("Found %d fail2ban rule(s) to restore from %s", len(rules), protocol)

    # 4. Restore rules
    reject_flag = (
        "icmp6-port-unreachable" if protocol == "ipv6" else "icmp-port-unreachable"
    )
    mask = "128" if protocol == "ipv6" else "32"

    success, failure = restore_rules(
        rules,
        cfg["insert_cmd_prefix"],
        mask,
        reject_flag,
        dry_run=dry_run,
    )

    log.info(
        "Restored %d/%d %s rule(s) (%d failed)",
        success,
        len(rules),
        protocol,
        failure,
    )

    return success > 0


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Restore fail2ban IP bans from the latest iptables snapshot.",
    )
    parser.add_argument(
        "--snapshot-dir",
        default="/var/log/iptables-autoexpiry",
        help="Directory for snapshot files (default: /var/log/iptables-autoexpiry)",
    )
    parser.add_argument(
        "--max-age-hours",
        type=float,
        default=24.0,
        help="Maximum age of snapshot in hours (default: 24)",
    )
    parser.add_argument(
        "--protocol",
        choices=["ipv4", "ipv6", "both"],
        default="both",
        help="Protocol to process (default: both)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable debug logging",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stderr,
    )

    protocols = ["ipv4", "ipv6"] if args.protocol == "both" else [args.protocol]

    any_restored = False

    for proto in protocols:
        try:
            restored = process_protocol(
                protocol=proto,
                snapshot_dir=args.snapshot_dir,
                max_age_hours=args.max_age_hours,
                dry_run=args.dry_run,
            )
            if restored:
                any_restored = True
        except Exception:
            log.exception("Error processing %s", proto)

    log.info("Done.")
    sys.exit(0)


if __name__ == "__main__":
    main()

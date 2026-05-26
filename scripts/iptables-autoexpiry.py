#!/usr/bin/env python3
"""
iptables-autoexpiry.py — Auto-expiry for fail2ban IP bans.

Maintains hourly snapshots of iptables-save / ip6tables-save output and
auto-unbans IPs that have been persistently banned across all available
snapshots in a configurable lookback window.

Designed to run hourly via a systemd timer.
"""

import argparse
import glob
import logging
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Protocol-specific configuration
# ---------------------------------------------------------------------------

PROTOCOLS = {
    "ipv4": {
        "save_cmd": ["iptables-save"],
        "delete_cmd_prefix": ["iptables", "-D"],
        "extension": ".iptables",
        "pattern": re.compile(
            r"-A (f2b-\S+) -s ([\d.]+)/32 -j REJECT --reject-with icmp-port-unreachable"
        ),
    },
    "ipv6": {
        "save_cmd": ["ip6tables-save"],
        "delete_cmd_prefix": ["ip6tables", "-D"],
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


def parse_banned_ips(snapshot_path: str, pattern: re.Pattern) -> dict[str, set[str]]:
    """
    Parse an iptables-save snapshot and return a mapping of
    IP -> {chain_names} from fail2ban REJECT rules.
    """
    ips: dict[str, set[str]] = {}
    try:
        with open(snapshot_path, "r") as f:
            for line in f:
                m = pattern.match(line.strip())
                if m:
                    chain, ip = m.group(1), m.group(2)
                    ips.setdefault(ip, set()).add(chain)
    except (OSError, IOError) as e:
        log.warning("Could not read snapshot %s: %s", snapshot_path, e)
    return ips


def collect_snapshots(
    snapshot_dir: str,
    extension: str,
    since: datetime,
) -> list[str]:
    """
    Return a sorted list of snapshot paths that are >= *since*.
    """
    pattern = os.path.join(snapshot_dir, f"*{extension}")
    results = []
    for path in glob.glob(pattern):
        ts = parse_snapshot_filename(path)
        if ts and ts >= since:
            results.append(path)
    results.sort()
    return results


def delete_old_snapshots(
    snapshot_dir: str,
    extension: str,
    cutoff: datetime,
    dry_run: bool = False,
) -> int:
    """Delete snapshots strictly older than *cutoff*. Returns count removed."""
    pattern = os.path.join(snapshot_dir, f"*{extension}")
    deleted = 0
    for path in glob.glob(pattern):
        ts = parse_snapshot_filename(path)
        if ts and ts < cutoff:
            if dry_run:
                log.info("[DRY-RUN] Would delete %s", path)
            else:
                os.unlink(path)
                log.info("Deleted old snapshot: %s", path)
            deleted += 1
    return deleted


def atomic_write_snapshot(
    snapshot_dir: str,
    filename: str,
    content: bytes,
    dry_run: bool = False,
) -> str:
    """
    Write *content* to a snapshot file atomically (write to temp, then rename).
    Returns the final path.
    """
    final_path = os.path.join(snapshot_dir, filename)

    if dry_run:
        log.info(
            "[DRY-RUN] Would write snapshot %s (%d bytes)", final_path, len(content)
        )
        return final_path

    os.makedirs(snapshot_dir, exist_ok=True)

    # Write to a temporary file in the same directory (ensures same filesystem
    # for a rename that is guaranteed to be atomic).
    dir_fd = os.open(snapshot_dir, os.O_RDONLY)
    try:
        fd, tmp_path = tempfile.mkstemp(
            dir=snapshot_dir, prefix=".tmp-", suffix=filename
        )
        try:
            os.write(fd, content)
            os.fsync(fd)
        finally:
            os.close(fd)

        os.rename(tmp_path, final_path)
        log.info("Wrote snapshot: %s (%d bytes)", final_path, len(content))
    except Exception:
        # Clean up temp file on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    finally:
        os.close(dir_fd)

    return final_path


def take_snapshot(
    save_cmd: list[str], snapshot_dir: str, extension: str, dry_run: bool = False
) -> str:
    """
    Run the save command and store the output as an atomic snapshot.
    Returns the path of the new snapshot.
    """
    now = datetime.now()
    filename = now.strftime(f"%Y-%m-%d-%H{extension}")

    result = subprocess.run(save_cmd, capture_output=True)
    if result.returncode != 0:
        log.error(
            "%s failed (rc=%d): %s",
            " ".join(save_cmd),
            result.returncode,
            result.stderr.decode(errors="replace"),
        )
        sys.exit(1)

    return atomic_write_snapshot(snapshot_dir, filename, result.stdout, dry_run=dry_run)


def unban_ips(
    ips_chains: dict[str, set[str]],
    delete_cmd_prefix: list[str],
    dry_run: bool = False,
) -> int:
    """
    Remove fail2ban rules for the given IPs/chains.
    Returns the number of rules removed.
    """
    removed = 0
    for ip, chains in sorted(ips_chains.items()):
        for chain in sorted(chains):
            cmd = delete_cmd_prefix + [
                chain,
                "-s",
                f"{ip}/128" if ":" in ip else f"{ip}/32",
                "-j",
                "REJECT",
            ]
            if dry_run:
                log.info("[DRY-RUN] Would run: %s", " ".join(cmd))
            else:
                result = subprocess.run(cmd, capture_output=True)
                if result.returncode != 0:
                    log.warning(
                        "Failed to unban %s from %s (rc=%d): %s",
                        ip,
                        chain,
                        result.returncode,
                        result.stderr.decode(errors="replace"),
                    )
                    continue
            log.info("Unbanned %s from chain %s", ip, chain)
            removed += 1
    return removed


# ---------------------------------------------------------------------------
# Main logic per protocol
# ---------------------------------------------------------------------------


def process_protocol(
    protocol: str,
    snapshot_dir: str,
    retention_days: float,
    expiry_days: float,
    dry_run: bool,
) -> None:
    cfg = PROTOCOLS[protocol]
    extension = cfg["extension"]

    now = datetime.now()
    retention_cutoff = now - timedelta(days=retention_days)
    expiry_since = now - timedelta(days=expiry_days)

    log.info("=== %s ===", protocol.upper())

    # 1. Delete old snapshots
    deleted = delete_old_snapshots(
        snapshot_dir, extension, retention_cutoff, dry_run=dry_run
    )
    log.info(
        "Deleted %d snapshot(s) older than %s", deleted, retention_cutoff.isoformat()
    )

    # 2. Take a new snapshot
    take_snapshot(cfg["save_cmd"], snapshot_dir, extension, dry_run=dry_run)

    # 3. Collect all snapshots in the expiry window
    snapshots = collect_snapshots(snapshot_dir, extension, expiry_since)
    log.info(
        "Found %d snapshot(s) in the last %.1f day(s)", len(snapshots), expiry_days
    )

    if len(snapshots) < 2:
        log.info("Need at least 2 snapshots to compare; skipping unban check")
        return

    # 4. Coverage check — require at least 25% of expected hourly snapshots
    expected_count = int(expiry_days * 24)
    required_count = max(2, int(expected_count * 0.25))
    if len(snapshots) < required_count:
        log.warning(
            "Coverage too low: %d/%d snapshots (%.0f%% < 25%% required); skipping unban check",
            len(snapshots),
            expected_count,
            len(snapshots) / expected_count * 100 if expected_count else 0,
        )
        return

    log.info(
        "Coverage OK: %d/%d snapshots (%.0f%% >= 25%%)",
        len(snapshots),
        expected_count,
        len(snapshots) / expected_count * 100,
    )

    # 5. Parse IPs from every snapshot
    snapshot_ips: list[dict[str, set[str]]] = []
    for sp in snapshots:
        ips = parse_banned_ips(sp, cfg["pattern"])
        snapshot_ips.append(ips)
        log.debug("  %s -> %d banned IP(s)", os.path.basename(sp), len(ips))

    # The latest snapshot is the last one (list is sorted)
    latest_ips = snapshot_ips[-1]
    if not latest_ips:
        log.info("No banned IPs in the latest snapshot; nothing to do")
        return

    # All IPs seen across all snapshots (for set operations)
    all_ip_sets = [set(entry.keys()) for entry in snapshot_ips]

    # 6. Find IPs present in the latest snapshot AND in every snapshot
    persistent_ips: dict[str, set[str]] = {}
    for ip in latest_ips:
        if all(ip in ip_set for ip_set in all_ip_sets):
            # Collect chains from all snapshots for robust unban
            chains: set[str] = set()
            for entry in snapshot_ips:
                chains.update(entry.get(ip, set()))
            persistent_ips[ip] = chains

    if not persistent_ips:
        log.info("No persistent bans found; nothing to unban")
        return

    log.info(
        "%d IP(s) banned across ALL snapshots — scheduling for unban",
        len(persistent_ips),
    )

    # 7. Unban
    count = unban_ips(persistent_ips, cfg["delete_cmd_prefix"], dry_run=dry_run)
    log.info("Unbanned %d rule(s)", count)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Auto-expiry for fail2ban IP bans based on iptables snapshots.",
    )
    parser.add_argument(
        "--snapshot-dir",
        default="/var/log/iptables-autoexpiry",
        help="Directory for snapshot files (default: /var/log/iptables-autoexpiry)",
    )
    parser.add_argument(
        "--retention-days",
        type=float,
        default=10.0,
        help="Delete snapshots older than this many days (default: 10)",
    )
    parser.add_argument(
        "--expiry-days",
        type=float,
        default=7.0,
        help="Lookback window in days for persistent-ban detection (default: 7)",
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

    for proto in protocols:
        try:
            process_protocol(
                protocol=proto,
                snapshot_dir=args.snapshot_dir,
                retention_days=args.retention_days,
                expiry_days=args.expiry_days,
                dry_run=args.dry_run,
            )
        except Exception:
            log.exception("Error processing %s", proto)

    log.info("Done.")


if __name__ == "__main__":
    main()

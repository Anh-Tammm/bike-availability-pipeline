"""Collect slowly-changing reference feeds (station lists) for all sources.

Runs every collector even if one fails; exits non-zero if any failed.
"""
import subprocess
import sys

COMMANDS = [
    [sys.executable, "gbfs_collector.py", "--system", "velib", "--feeds", "station_information"],
    [sys.executable, "tdx_collector.py", "--feeds", "station"],
]

if __name__ == "__main__":
    sys.exit(max(subprocess.run(cmd, check = False).returncode for cmd in COMMANDS))

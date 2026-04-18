#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${1:-$ROOT_DIR/.security_reports}"

mkdir -p "$REPORT_DIR"

python3 - "$ROOT_DIR" "$REPORT_DIR" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
report_dir = Path(sys.argv[2]).resolve()
report_dir.mkdir(parents=True, exist_ok=True)

checks = []
failures = []


def run_check(name, command, cwd, expected_returncode=0):
    proc = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    passed = proc.returncode == expected_returncode
    record = {
        "name": name,
        "command": command,
        "returncode": proc.returncode,
        "passed": passed,
        "stdout_tail": proc.stdout.splitlines()[-10:],
        "stderr_tail": proc.stderr.splitlines()[-10:],
    }
    checks.append(record)
    if not passed:
        failures.append(record)


shell_files = [root / "install.sh"]
shell_files.extend(sorted((root / "scripts").glob("*.sh")))
for shell_file in shell_files:
    run_check(f"bash-n:{shell_file.name}", ["bash", "-n", str(shell_file)], cwd=str(root))

dangerous_patterns = {
    "download_pipe_exec": r"curl\s+[^\\n|]*\|\s*(sh|bash)|wget\s+[^\\n|]*\|\s*(sh|bash)|bash\s+<\(|sh\s+<\(",
    "eval_download": r"eval\s+.*(curl|wget)",
}

for name, pattern in dangerous_patterns.items():
    run_check(
        f"rg:{name}",
        ["rg", "-n", "-P", pattern, "scripts", ".github/workflows", "install.sh", "install.ps1"],
        cwd=str(root),
        expected_returncode=1,
    )

run_check(
    "rg:insecure-http-runtime",
    ["rg", "-n", r"http://", "src", "install.sh", "install.ps1", "scripts/setup.sh", "scripts/package-release.sh"],
    cwd=str(root),
    expected_returncode=1,
)

allowed_http_client_files = {"src/runtime_lifecycle.zig"}
http_client_proc = subprocess.run(
    ["rg", "-l", r"std\.http\.Client", "src"],
    cwd=str(root),
    text=True,
    capture_output=True,
    check=False,
)
http_client_files = {line.strip() for line in http_client_proc.stdout.splitlines() if line.strip()}
http_client_ok = http_client_files <= allowed_http_client_files
http_client_record = {
    "name": "allowlist:http-client-files",
    "allowed": sorted(allowed_http_client_files),
    "actual": sorted(http_client_files),
    "passed": http_client_ok,
}
checks.append(http_client_record)
if not http_client_ok:
    failures.append(http_client_record)

rm_proc = subprocess.run(
    ["rg", "-n", r"rm -rf", "install.sh", "scripts"],
    cwd=str(root),
    text=True,
    capture_output=True,
    check=False,
)
rm_lines = [line.strip() for line in rm_proc.stdout.splitlines() if line.strip()]
rm_ok = True
for line in rm_lines:
    if "run_security_audit.sh" in line:
        continue
    if "TMP" in line or "tmp" in line or "WORK_ROOT" in line or "BUILD_ROOT" in line or "GRAMMAR_DIR" in line or "TS_HEADER_DIR" in line:
        continue
    rm_ok = False
rm_record = {
    "name": "allowlist:rm-rf-temp-only",
    "lines": rm_lines,
    "passed": rm_ok,
}
checks.append(rm_record)
if not rm_ok:
    failures.append(rm_record)

report = {
    "check_count": len(checks),
    "failure_count": len(failures),
    "checks": checks,
}

json_path = report_dir / "security_audit_report.json"
md_path = report_dir / "security_audit_report.md"
json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

md_lines = [
    "# Security Audit Report",
    "",
    f"- Checks: `{len(checks)}`",
    f"- Failures: `{len(failures)}`",
    "",
]
for check in checks:
    status = "PASS" if check.get("passed") else "FAIL"
    md_lines.append(f"- `{check['name']}`: {status}")
md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")

print(f"Wrote {json_path}")
print(f"Wrote {md_path}")
if failures:
    raise SystemExit(1)
PY

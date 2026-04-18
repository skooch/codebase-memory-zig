# Configuration Matrix

This document records the supported operational controls in the Zig port today,
their defaults, and the verification path backing each claim.

| Surface | Kind | Default | Effective precedence | Verification |
|--------|------|---------|----------------------|--------------|
| `auto_index` | persisted config | `false` | config file, or `CBM_AUTO_INDEX` to force enabled on startup | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `auto_index_limit` | persisted config | `50000` | `CBM_AUTO_INDEX_LIMIT` overrides config value | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `idle_store_timeout_ms` | persisted config | `60000` | `CBM_IDLE_STORE_TIMEOUT_MS` overrides config value | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `update_check_disable` | persisted config | `false` | `CBM_UPDATE_CHECK_DISABLE` overrides config value to disable checks | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `download_url` | persisted config | empty / unset | config file only | `zig build test` |
| `CBM_CACHE_DIR` | env var | unset | highest priority runtime cache root | `bash scripts/run_cli_parity.sh --zig-only` |
| `CBM_CONFIG_PLATFORM` | env var | host OS | overrides path-shape selection for fixture-backed config roots | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `CBM_EXTENSION_MAP` | env var | unset | overrides built-in extension-to-language detection before indexing and extraction | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `LOCALAPPDATA` / `XDG_CACHE_HOME` | env var | platform fallback | selected by config platform when `CBM_CACHE_DIR` is unset | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `APPDATA` / `XDG_CONFIG_HOME` | env var | platform fallback | selected by config platform for roaming config roots | `bash scripts/run_cli_parity.sh --zig-only` |
| `cbm cli --progress` | CLI flag | off | explicit flag only | `zig build`, `bash scripts/run_cli_parity.sh` |
| `install_scope` | persisted config | `shipped` | config default for install/update/uninstall scope unless `--scope` is passed | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `install_extras` | persisted config | `true` | config default for install/update/uninstall extras unless `--mcp-only` is passed | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `install` / `update` / `uninstall --scope` | CLI flag | config default | explicit `--scope detected` broadens agent handling beyond the shipped surface | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `install` / `update` / `uninstall --mcp-only` | CLI flag | config default | explicit `--mcp-only` keeps MCP entries while skipping instructions, skills, and hooks | `zig build test`, `bash scripts/run_cli_parity.sh --zig-only` |
| `-y`, `-n`, `--dry-run`, `--force` | CLI flags | ask / off | explicit flag only | `bash scripts/run_cli_parity.sh` |

Known intentional omissions in the current branch:

- no host bind/listen control because the shipped server mode is stdio only
- no broader installer-scope matrix beyond the currently shipped agent surface
- no broader persisted hook-policy or extension-mapping layer beyond `install_extras` and env-only `CBM_EXTENSION_MAP`

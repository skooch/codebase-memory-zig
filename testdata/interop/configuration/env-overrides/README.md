# Configuration Override Fixtures

This fixture area exists so the operational-controls plan can verify env-var
and config-file behavior in temp-home layouts instead of reading or mutating a
developer machine's real config.

Planned verification lanes:
- runtime cache root overrides
  - `CBM_CACHE_DIR`
  - Windows `LOCALAPPDATA`
  - Unix `XDG_CACHE_HOME`
- roaming config root overrides
  - Windows `APPDATA`
  - Unix `XDG_CONFIG_HOME`
- runtime behavior overrides
  - `CBM_AUTO_INDEX`
  - `CBM_AUTO_INDEX_LIMIT`
  - `CBM_IDLE_STORE_TIMEOUT_MS`
  - `CBM_UPDATE_CHECK_DISABLE`
- persisted config interplay
  - `cbm config list|get|set|reset`
  - precedence between config-file values and env overrides where supported

Phase 1 only documents the lanes. Later phases will add runnable fixture-backed
assertions under this directory.

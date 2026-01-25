# Repository Reorganization - Migration Notes

## Changes Made

This repository has been reorganized on **2026-01-25** for better structure and production deployment.

### New Structure

All scripts have been moved into organized directories:
- `bin/` - Main deployment scripts
- `src/` - Python application code
- `scripts/setup/` - Initial setup scripts
- `scripts/server/` - Server management scripts
- `scripts/map/` - Map rendering scripts
- `config/` - Configuration templates

### Old → New Script Mapping

| Old Location | New Location | Notes |
|--------------|--------------|-------|
| `server.py` | `src/server.py` | Moved to src directory |
| `range_server.py` | `src/range_server.py` | Moved to src directory |
| `setup_postgresql.sh` | `scripts/setup/postgresql.sh` | Refactored with common.sh |
| `setup_mapper.sh` | `scripts/setup/mapper.sh` | Refactored |
| `setup_express.sh` | `scripts/setup/express.sh` | Refactored |
| `setup_map_hosting.sh` | `scripts/map/setup-hosting.sh` | Refactored |
| `sls.sh` | `scripts/server/start-luanti.sh` | Refactored |
| `migrate.sh` | `scripts/server/migrate-backend.sh` | Refactored |
| `reset_environment.sh` | `scripts/server/reset-env.sh` | Refactored |
| `render_map.sh` | `scripts/map/render.sh` | Refactored |
| `auto_render_loop.sh` | `scripts/map/auto-render.sh` | Refactored |
| `.env.example` | `config/.env.example` | Expanded with more variables |
| N/A | `bin/deploy.sh` | **NEW** - Unified deployment script |
| N/A | `src/lib/common.sh` | **NEW** - Shared utility functions |
| N/A | `DEPLOYMENT.md` | **NEW** - Production deployment guide |

### Old Scripts Status

The old scripts in the root directory are **deprecated** and should no longer be used. They are kept temporarily for reference but will be removed in a future commit.

### How to Update Existing Deployments

```bash
# 1. Pull the latest changes
git pull

# 2. Run the update command
./bin/deploy.sh --update

# 3. If you have custom scripts referencing old paths, update them
# Example: Change from:
#   ./setup_postgresql.sh
# To:
#   ./scripts/setup/postgresql.sh
```

### Systemd Service Updates

The systemd service files are automatically updated by the deployment script. The main change is:

**Old:**
```ini
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/server.py
```

**New:**
```ini
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/src/server.py
```

### Benefits of New Structure

1. **Cleaner root directory** - Only essential files at top level
2. **Logical organization** - Scripts grouped by purpose
3. **Code reuse** - Shared functions in `src/lib/common.sh`
4. **Better documentation** - Comprehensive guides in `DEPLOYMENT.md`
5. **One-command deployment** - `./bin/deploy.sh` handles everything
6. **Production-ready** - Non-interactive mode for automation

### Need Help?

- See [README.md](README.md) for quick start
- See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed production guide
- Run `./bin/deploy.sh --help` for deployment options
- Run `./bin/deploy.sh --status` to check current deployment

### Cleanup (Optional)

Once you've verified everything works with the new structure, you can remove old scripts:

```bash
# Remove deprecated scripts
rm -f setup_*.sh render_map.sh auto_render_loop.sh migrate.sh sls.sh reset_environment.sh

# Note: This is optional. The .gitignore already excludes these from version control.
```

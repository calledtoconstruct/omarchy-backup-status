# Backup status

A bar badge for a borgmatic backup on Omarchy.

| Label | Meaning |
| --- | --- |
| `set` | No YAML file in `~/.config/borgmatic/` |
| `off` | `omarchy-backup.timer` is missing, disabled, or not active |
| `run` | `borgmatic` or `borg` is running, or `omarchy-backup.service` is active |
| `45m`, `3h`, `2d` | Time until `NextElapseUSecRealtime` on that timer |
| `due` | That time has passed |
| `err` | The service's last result was `exit-code`, `failed`, or `timeout` |
| `?` | The timer is active and the next time could not be read |

Click opens the first YAML file in the config directory. The script does not run borgmatic and does not read the repository.

`status.sh` prints one JSON object. Tests cover the label rules with fixture files instead of the live user manager.

The timer and the service are installed by the backup actions plugin, after a confirm. This plugin only reads them.

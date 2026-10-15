# Linux home-server automation (openSUSE / KDE)

Self-hosted media + backup automation for my desktop. Everything runs as **systemd *user* services** (linger enabled, so they run logged-out) plus a couple of Docker Compose stacks. No secrets live in these files — API keys/tokens are entered at runtime or stored outside the repo.

## Layout
```
bin/            scripts invoked by the systemd units
systemd-user/   -> install into ~/.config/systemd/user/
docker/         Compose stacks (kavita reader, filebrowser upload UI)
```

## What each piece does
| Unit | Script | Does |
|---|---|---|
| `immich-onedrive-backup.timer` | `bin/immich-onedrive-backup.sh` | Nightly guarded **mirror** of Immich originals to OneDrive (rclone). DB dump copied first; mass-delete guard falls back to copy-only. |
| `docs-onedrive-sync.timer` | `bin/docs-onedrive-sync.sh` | Nightly guarded mirror of `~/Documents/{Library,Reading,Sheet Music,Recovery Codes,uoft}` to OneDrive. |
| `kavita-tidy.timer` | `bin/kavita-tidy.py` | Pre-sync tidy of the book libraries: local-LLM (ollama) rename of badly-named PDFs, folder-per-book, strip embedded PDF titles (so Kavita shows clean series). |
| `syncthing.service` | (binary) | Two-way file sync to other devices over Tailscale. |

`docker/kavita` = Kavita reader (libraries mounted **read-only**). `docker/filebrowser` = web upload UI (same folders **read-write**) so books can be added from any device; Kavita never writes.

## Dependencies
`rclone` (configured remote named `remote:`), `docker` + compose, `ollama` (model `qwen2.5:1.5b`), `poppler-tools` (`pdftotext`), a Python venv with `pikepdf`, `tailscale`, `syncthing` binary in `~/.local/bin`.

## Deploy
1. `scripts`: copy/symlink `bin/*` into `~/.local/bin/` (chmod +x).
2. `systemd`: copy `systemd-user/*` into `~/.config/systemd/user/`, then
   `systemctl --user daemon-reload && systemctl --user enable --now <unit>.timer` (and `syncthing.service`).
   `loginctl enable-linger $USER` so they run when logged out.
3. `kavita-tidy` venv: `python3 -m venv ~/.local/share/kavita-tidy-venv && ~/.local/share/kavita-tidy-venv/bin/pip install pikepdf`.
4. `docker`: `docker compose up -d` in each `docker/*` dir.
5. Expose over Tailscale (tailnet-only): `sudo tailscale serve --bg --https=<port> http://127.0.0.1:<app-port>`.

## Adjust for your machine
- Paths assume the `friedrice` home — change if yours differs.
- `docker/kavita/docker-compose.yml` has `<YOUR_TAILSCALE_IP>` / `<YOUR_TAILNET_HOST>` placeholders — set your own (`tailscale ip -4`).
- `immich-onedrive-backup.sh` / `docs-onedrive-sync.sh` assume an rclone remote called `remote:` → OneDrive.

## Do NOT commit
Runtime state / secrets: `~/filebrowser/{database,config}/`, `~/.local/state/syncthing/`, `~/.config/rclone/rclone.conf`, any `*.db`, the `syncthing` binary. (See `.gitignore`.)

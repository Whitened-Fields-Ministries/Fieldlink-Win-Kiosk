# FieldLink Kiosk

The Windows app that runs a [Field Link Missions](https://fieldlinkmissions.com) lobby display. It is a small
Electron shell around the FieldLink kiosk web page (`/kiosk?key=…`) plus everything a church needs to set a
display up and keep it running without touching scripts or files:

- **Link by code on screen.** With no key configured the app shows a 6-character code. A Super Admin types it
  into FieldLink Admin → Kiosk → 🔗 Link kiosk and the map appears. No keyboard is needed at the display.
- **Kiosk mode from inside the app.** One button (behind a normal UAC prompt) creates a locked-down
  `FieldLinkKiosk` Windows account that boots straight into the app, disables sleep and switches on nightly
  self-updates. One button undoes it.
- **Self-healing.** The app checks its key with the server every 30 s and shows a clear screen, with a fresh
  link code, when the key is deleted, disabled or rotated. Network and maintenance outages retry on their own.

Church admins never clone this repo. FieldLink serves the installer built here at `/api/kiosk/installer`.

## Flow for a church

1. Admin → Kiosk → 💻 Windows Kiosk App → **Download installer**. Run it on the display PC (Windows 10/11,
   64-bit). It opens by itself when finished.
2. The app shows a code. In Admin → Kiosk click **🔗 Link kiosk** on the key for that display and type the code.
3. Press **Ctrl+Shift+K** on the display → **Turn this PC into a kiosk** → accept the UAC prompt → restart.

That's the whole setup. Later, the same Ctrl+Shift+K screen shows status, installs updates, or removes kiosk mode.

## What's in the app

| File | Role |
|------|------|
| `main.js` | Window, key health loop, recovery/setup screen state, on-screen pairing, bridge to the privileged helper, update check. |
| `preload.js` | Exposes the privileged bridge only to the local `recovery.html`; remote pages get a read-only marker (`window.fieldlinkKioskApp`: `{ app: true, platform: 'win32', device: 'windows-pc', version }`). Reports mouse movement and the corner hold to `main.js`. |
| `display-scale.js` | How much to magnify the pages for the screen (see *Display scale*). No Electron in it; unit-tested in `test/`. |
| `recovery.html` | The setup / recovery / settings screen (link code, kiosk mode, updates, status). Opens in a browser for layout work. |
| `resources/kiosk-admin.ps1` | Everything that needs administrator rights. Shipped as `resources\kiosk-admin.ps1` next to the exe. ASCII + BOM, see below. |
| `build/installer.nsh` | NSIS hook: a real uninstall runs `-Action Unlock` first so a PC is never left auto-logging into a shell that no longer exists. |

### Key health loop

Every 30 s the app calls `GET /api/kiosk/whoami` with the key.

| Result | What the app does |
|--------|-------------------|
| 200 | Nothing; if it had been showing a recovery screen it loads the map. |
| 401/403 twice in a row | Shows the recovery screen with a new link code. The service worker no longer masks 401 with cached data. |
| 5xx / network error | Leaves a working page alone (the page has its own offline handling). If the page never loaded, shows *Connecting…* and retries with 5 → 30 s backoff. |

Renderer crashes reload the page; a page that hangs is reloaded after 10 s unless it answers again first.
`did-fail-load` at boot (Wi-Fi not up yet) is handled the same way.

### Display scale

The kiosk page and the settings screen are laid out in CSS pixels for a 1080p screen, and Windows applies
whatever *Scale* its display settings hold (a 4K TV may come up at 100 %, 150 % or 300 %). The app zooms its
pages so the total is always **short side of the screen in physical pixels ÷ 1080**, in 5 % steps between
0.5× and 4×: what Windows already applies is divided out, so nothing is scaled twice.

| Screen | Windows scale | Zoom the app adds | Result |
|--------|---------------|-------------------|--------|
| 1080p | 100 % | 1 | the 1080p layout |
| 4K | 100 % | 2 | the 1080p layout |
| 4K | 150 % | 1.333 | the 1080p layout |
| 4K | 300 % | 0.667 | the 1080p layout |
| 1440p | 100 % | 1.35 | the 1080p layout |

`"displayScale": 1.5` in `config.json` pins a size (a TV far across a hall may want more). The zoom is set
in `webPreferences.zoomFactor`, again on every `dom-ready` (Chromium keeps zoom per site) and whenever the
display or its Windows scale changes. *Details* on the settings screen shows the resolution and the scale
in use. The same rule, and the same `display-scale.js`, as Fieldlink-Pi-Kiosk.

### Mouse pointer

Windows draws a pointer as soon as a mouse or a keyboard's wireless receiver is plugged in, and it would
rest on the map for good. The app hides the pointer on every page, shows it when a mouse moves, clicks or
scrolls, and hides it again 5 seconds after the last movement. Touch never shows it. The "move" a browser
reports when a page loads under a resting pointer is ignored. It is a user style sheet inserted from
`main.js` (`cursor: none !important`), re-applied on every page load.

### Time zone

FieldLink (2.55.0 and later) sends the time zone of the church's address with every key check. The app
never changes the PC's time zone, but the clock on the kiosk page follows the PC, so *Details* on the
settings screen shows a warning when the PC's zone and the church's show different times.

### Pairing

Primary, **code on the display**: the app calls `POST /api/kiosk/pair/request` → `{ code, token, expires_at }`,
shows the code and polls `GET /api/kiosk/pair/poll` (header `x-pair-token`) every 3 s. When a superadmin has
claimed the code via `POST /api/kiosk/keys/:id/pair-claim`, the poll returns the kiosk URL and the app saves it.
Codes renew every 15 minutes by themselves.

Fallback: pasting a full kiosk URL or key under "Have a kiosk URL?" on the screen (for the rare case
where the admin panel cannot be reached from a phone).

### Servers

The app talks to `https://app.fieldlinkmissions.com` by default (`DEFAULT_SERVER` in `main.js`): the
FieldLink application lives on the `app.` host, the bare domain is the public website. A `config.json`
or `update.json` written before that move (`https://fieldlinkmissions.com`, `https://qa.fieldlinkmissions.com`)
is migrated on the next start — same key, new origin (`LEGACY_ORIGINS` in `main.js`, `$LegacyServers` in the
helper) — so nothing needs re-linking after the update. The server also answers those old addresses with a
redirect, which is how a display still on an older build finds this update.

Pointing a display at another server (QA, a self-hosted FieldLink) is deliberately not offered on the
screen. On the Ctrl+Shift+K screen press **Ctrl+Shift+S** and a *FieldLink server* field appears: type
`qa` (short for `https://app.qa.fieldlinkmissions.com`), `prod`, or a full address and click **Use this
server**; the link code is then requested from that server and the kiosk URL it hands back keeps it.
Pasting a full kiosk URL copied from that server's Admin → Kiosk page under "Have a kiosk URL?" does the
same without the field. *Details* on the same screen shows the server in use.

### Privileged helper (`resources/kiosk-admin.ps1`)

Invoked by `main.js` through `Start-Process -Verb RunAs` (one UAC prompt). It reports progress by rewriting
`%ProgramData%\FieldLinkKiosk-Admin\last-action.json`, which the screen polls.

| Action | What it does |
|--------|--------------|
| `Status` | Read-only JSON: account, auto-login, profile, update task, last update, paths. No elevation. |
| `Lockdown` | Creates/repairs the `FieldLinkKiosk` account with a **random password**, not an administrator, cannot change its password; creates its profile (UserEnv `CreateProfile`); sets its shell to the exe and disables Task Manager/Run/context menu in its hive; configures auto-login with the password stored in the **LSA `DefaultPassword` secret** (never `DefaultPassword` in the registry — the old blank-password approach broke on machines that refuse blank-password logons); disables sleep/screensaver; installs the update task; verifies. |
| `Unlock` | Reverses all of that, removes the task, disables (does not delete) the account. |
| `Update` | Picks the server (see *Security notes*), asks `/api/kiosk/installer/version`, downloads from `/api/kiosk/installer` if newer, verifies size and sha256, runs the installer silently. Restarts the PC if the kiosk session was running (the app was its shell); with `-Relaunch` it relaunches the app de-elevated via `explorer.exe`. **If the installer fails after the app was closed**, the app is started again (`-Relaunch`) or the PC is restarted (scheduled run), so the display is never left black; the run right after such a restart skips that version, which is tried again the following night. |
| `InstallUpdater` / `RemoveUpdater` | Manage the scheduled task alone. |

Two data folders, deliberately:

| Folder | ACL | Contents |
|--------|-----|----------|
| `%ProgramData%\FieldLinkKiosk` | kiosk account may **modify** | `config.json` (the kiosk URL) — so the kiosk account can re-link itself from the screen. |
| `%ProgramData%\FieldLinkKiosk-Admin` | Administrators + SYSTEM full, Users read | copy of the helper the SYSTEM task runs, `update.json` (the server recorded when kiosk mode was turned on, or pinned by an administrator), `admin.log`, `last-action.json`, `update-status.json`, `runs\` (per-run logs), downloads. Nothing the kiosk account can edit is ever executed by the updater, and `config.json` can only make it choose between the two FieldLink servers, never name another one. Lockdown takes ownership of both folders and refuses to continue if either is a junction or symbolic link, so a standard user who created them first gains nothing. |

The scheduled task **FieldLinkKiosk Update** runs as SYSTEM daily at 03:15 and 3 minutes after boot. It is
registered with a security descriptor that lets any signed-in account *start* it (not edit it), and
`updater.json` in the admin folder records that it exists, because a standard user cannot query a SYSTEM
task. `Get-TaskInfo` falls back to that marker.

How **Install update** on the screen works depends on who is signed in:

| Session | Path |
|---------|------|
| Kiosk account (`isKioskSession`) | `schtasks /Run "FieldLinkKiosk Update"` — the SYSTEM task downloads, verifies, installs and restarts the display; the screen follows `last-action.json`. |
| Anyone else | The same helper, run elevated once (`-Action Update -Relaunch`): it downloads into the admin-only folder, checks size and sha256, installs silently and relaunches the app through `explorer.exe`. Nothing is downloaded or verified by the unprivileged app and then handed to the elevated side. |

**Lockdown / Unlock / Update** are started with `Start-Process -Verb RunAs -Wait`, so the app knows exactly
when they finish and with what exit code. The elevated process runs `kiosk-admin.ps1` straight from the
install directory (Program Files, administrators only) with a fixed argument list; no wrapper script and
nothing from the user's profile is ever executed with the admin token. The helper appends its output to
`%ProgramData%\FieldLinkKiosk-Admin\runs\<Action>-<timestamp>.log` (`-RunLog`, a file name only), which
the screen tails live under a progress bar; `last-action.json` supplies the step list and the final
message. Lockdown and Unlock finish with a restart prompt.

Windows often shows its permission prompt as a flashing taskbar button rather than in front, and a
full-screen window covers the taskbar. So while the app waits for the answer its window leaves full screen
and shrinks to the work area; it returns to full screen when the helper starts running or the request ends.

Helper rules learned the hard way: keep the file **pure ASCII with a UTF-8 BOM** (PowerShell 5.1 reads a
BOM-less file as Windows-1252 and an em dash's last byte is a quote character); run native tools through
`Run-Native` (a redirected stderr line is a terminating error under `$ErrorActionPreference = 'Stop'`);
account descriptions are limited to 48 characters; `Test-Path` inside another user's profile throws for a
non-elevated caller.

### Config resolution

The most recently modified of these wins:

| Path | Written by |
|------|-----------|
| `%ProgramData%\FieldLinkKiosk\config.json` | The app (pairing / pasted URL). Survives upgrades. |
| `%APPDATA%\fieldlink-kiosk\config.json` | Fallback when ProgramData is not writable. |
| `./config.json` | Development only (`npm start`). |

Only `kioskUrl` matters, plus the optional `displayScale` (see *Display scale*). Display mode, theme,
carousel and the rest live on the key in FieldLink Admin.

### Keyboard shortcuts

| Keys | Action |
|------|--------|
| Ctrl+Shift+K | Open / close the settings & recovery screen |
| Press and hold the top-left corner for 4 s | The same, without a keyboard — touch or mouse |
| Ctrl+Shift+S | On that screen: show / hide the *FieldLink server* field (`qa`, `prod` or an address) |
| Ctrl+Shift+R | Reload the kiosk page |
| Ctrl+Shift+Q | Quit the app |

**Getting to the settings screen without a keyboard.** Press and hold the top-left corner of the
screen for four seconds with one finger (touch screen) or the mouse. A small progress ring shows
while holding; the settings screen opens, and the same gesture closes it. It is detected in
`preload.js` on every page the window shows, including the kiosk page, and only ever does what
Ctrl+Shift+K does (the same snippet as `app/preload.js` in Fieldlink-Pi-Kiosk).

Logs: `%APPDATA%\fieldlink-kiosk\kiosk.log` (app, per user; trimmed when it passes 1 MB, never more than the
first 20 characters of a key) and `%ProgramData%\FieldLinkKiosk-Admin\admin.log` (helper). Both paths are
shown under *Details* on the Ctrl+Shift+K screen.

## Security notes

- **Updates come only from FieldLink.** Whatever server a display shows its map from, installer builds
  are fetched from `app.fieldlinkmissions.com`, or from `app.qa.fieldlinkmissions.com` for a display
  linked to QA: `TRUSTED_ORIGINS` in `main.js`, `$TrustedUpdateServers` in the helper. The QA server offers
  QA builds, production only promoted ones (see *Release*), so the server a display is linked to is its
  update channel. The helper follows the display's server (`Get-UpdateServer`): `config.json`, which the
  kiosk account may write, can choose between those two servers and nothing else; a display on any other
  server updates from the one recorded in the admin-only `update.json` when kiosk mode was turned on, else
  production. An administrator can pin another server by hand with
  `kiosk-admin.ps1 -Action InstallUpdater -Server https://…` (that wins over everything). Downloads follow
  no redirects, must match the size and sha256 the server reports, and are refused when the server reports
  no checksum. The checksum is the server's own, so it protects the download, not the server.
- **Re-linking from the screen is limited to known servers.** A pasted kiosk URL is accepted for the
  FieldLink servers, the server the display is already on, and the one entered in the staff-only server
  field (Ctrl+Shift+S); anything else is refused with a hint. Servers must use https (plain http only
  for `localhost`). A pairing poll only accepts a kiosk URL on the server that was asked.
- **The window stays on its server.** Navigation is allowed only to the kiosk URL's exact origin (not a
  prefix match) or the local recovery page; new windows are denied; every Chromium permission request
  (camera, microphone, location, notifications, …) is denied except fullscreen.
- **Electron is kept current** (Dependabot, weekly) because the kiosk renders web content, including
  newsletters and videos uploaded by churches. A Dependabot pull request that changes `package.json` fails
  its *Checks* until `version` is bumped in it too: displays compare version numbers, so an Electron
  update without a new version would never reach them.
- The installer is not code-signed yet (see *Release*); the helper logs the Authenticode status but
  cannot enforce it until there is a certificate.

## Development

```bash
npm install
npm start          # uses ./config.json — put a real kiosk URL in it, or leave it out to see the link screen
npm run check      # syntax of the scripts and of recovery.html's inline script
npm test           # unit tests (display scale)
npm run smoke      # the app in a real window: settings screen, display scale, pointer, corner hold; exits 0
npm run build      # Windows x64 NSIS installer in dist/
```

Pull requests run *Checks* on a Windows runner: the three commands above, `kiosk-admin.ps1` parsed by
Windows PowerShell 5.1 (BOM, ASCII, syntax), and that the version is new whenever the app changed.

`recovery.html` renders standalone in a browser with sample data. There is no Windows in CI beyond the build,
so **test `kiosk-admin.ps1` on a real PC** before releasing changes to it: `Lockdown`, reboot, `Ctrl+Shift+K`,
`Update`, `Unlock`.

## Release

Every build goes to QA first and reaches production only when someone promotes it.

1. **Bump `version` in `package.json`** with every change to the app (`npm install --package-lock-only`
   updates the lockfile). The updater compares it, the screen shows it, and requests carry a
   `FieldLinkKiosk/<version>` user-agent suffix. Two different builds must never share a version, and
   [`scripts/qa-release-state.sh`](scripts/qa-release-state.sh) makes the pull request and the build fail
   when they would.
2. **A push to `main` runs [`build.yml`](.github/workflows/build.yml)**: checks, smoke test, installer,
   published as the pre-release **`vX.Y.Z-qa`**, then `POST /api/kiosk/installer/invalidate` on the QA
   server (`FIELDLINK_QA_SERVER_URL` + `KIOSK_QA_WEBHOOK_SECRET`). The QA FieldLink server offers the
   newest QA build, so displays linked to QA install it at their next nightly check or from the Updates
   panel. Production is not touched. The workflow can also be run by hand from a branch (Actions →
   *Build QA installer* → Run workflow) to try a build before it is merged. Pushes that change nothing
   in the app (README, workflows) publish nothing.
3. **Test it on a QA display.**
4. **Actions → *Promote to prod*** ([`promote.yml`](.github/workflows/promote.yml)) with the version
   republishes the same file, without rebuilding, as the release **`vX.Y.Z`** marked *latest*, and tells
   both servers (`FIELDLINK_SERVER_URL` + `KIOSK_WEBHOOK_SECRET` for production). Production servers hand
   out the latest release; displays linked to production install it that night.

A server that is not told keeps describing the previous build for up to an hour. FieldLink servers older
than the one that introduced QA builds read only the latest release, so they hand out promoted builds on
QA as well.

The installer is not code-signed yet, so SmartScreen shows "Windows protected your PC" on first run
(More info → Run anyway). Signing needs a certificate issued to a person or a registered organisation;
once one exists it is a few lines in `build.yml` and the electron-builder `win` config.

## Server side

The server half lives in the FieldLink repo:

- `server/src/routes/kiosk.js` — key auth, `/whoami`, `/pair/request`, `/pair/poll`, `/keys/:id/pair-claim`,
  rotate/disable, installer proxy with `/installer/version` (size, sha256).
- `server/src/utils/kioskReleases.js` — which build a server hands out (QA: the newest QA build; production:
  the latest release).
- `nginx/admin-app/src/pages/KioskSettings.jsx` — the admin page (Link kiosk, status, installer download).
- `nginx/client/kiosk.html`, `kiosk.js` — the page this app displays.
- `site/docs/src/pages/kiosk.html` — the Kiosk chapter of the user documentation, including troubleshooting.

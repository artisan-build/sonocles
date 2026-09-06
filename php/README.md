# Sonocles for NativePHP

A menu bar app in PHP that drives Sonocles' Swift speech engine.

The finding this exists to demonstrate is in **[FEASIBILITY.md](FEASIBILITY.md)**:
the shell, UI, control plane and packaging are all comfortably NativePHP, and
recognition is not — so the engine stays where the Neural Engine is, spawned as
a child process, exactly as `sonocles-cli` was already built to be used.

Recognised words go from the engine's WebSocket straight to the renderer. PHP is
not in that path, which is why a 180 ms budget survives being wrapped in
Electron.

## Running it

```bash
composer install
cd nativephp/electron && npm run plugin:build && cd ../..   # see note below
swift build -c release --package-path ../app   # build the engine
./bin/sync-sidecar.sh                          # copy it into extras/
php artisan native:run                         # start the app
```

**The `plugin:build` line is not optional.** NativePHP 2.3.0 publishes an
`electron-plugin/dist` that is missing `server/pdfPageSize.js`, so the Electron
main process cannot be bundled until the plugin is rebuilt from its own source.
Without it `native:run` prints `build the electron main process successfully`
and then dies on `No electron app entry file found` — the success line comes
from a different step than the failure. `npm run build` shows the real error.

To package it:

```bash
php artisan native:build mac arm64             # signs from the keychain identity
```

`bin/make-icons.php` regenerates the menu bar template icons.

## Layout

| | |
|---|---|
| `app/Support/Sidecar.php` | the whole seam between PHP and Swift |
| `app/Providers/NativeAppServiceProvider.php` | menu bar, and bringing the engine up |
| `routes/web.php` | the popover, and the three control calls |
| `resources/views/menubar.blade.php` | the popover itself; holds the WebSocket |
| `nativephp/electron/build/entitlements.mac.plist` | **the microphone entitlement NativePHP does not scaffold** |
| `extras/sonocles-cli` | the engine (build product, not committed) |

## Requirements

Apple Silicon, macOS 14+, PHP 8.3+, Node. Models download on first capture
(~219 MB) into `~/Library/Application Support/FluidAudio`, shared with the
Swift app.

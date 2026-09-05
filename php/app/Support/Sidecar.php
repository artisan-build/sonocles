<?php

namespace App\Support;

use Illuminate\Support\Facades\Http;
use Native\Desktop\Facades\ChildProcess;

/**
 * The Swift engine, seen from PHP.
 *
 * Sonocles' recognition runs on the Neural Engine through Core ML, which PHP
 * cannot reach: the bundled runtime ships without ext-ffi, and Core ML has no C
 * API to bind to even if it did. So the engine stays exactly what it already
 * was — `sonocles-cli`, spawned as a child process — and this class is the
 * whole of the seam between the two languages.
 *
 * Two things travel across that seam, and only two:
 *
 *   control   PHP calls /start, /stop and /status over loopback HTTP. Human
 *             speed. Latency here is invisible.
 *   frames    PHP never sees them. The renderer holds ws://127.0.0.1:7358
 *             itself, so recognised words go engine → socket → DOM without
 *             entering the PHP process at all.
 *
 * That second point is the design. Putting PHP in the frame path would mean a
 * hop through the app's HTTP server every ~200 ms for text that is already 180
 * ms behind the speaker, to spend the budget on a language that has nothing to
 * add to it.
 */
class Sidecar
{
    public const ALIAS = 'sonocles-engine';

    public const HTTP_PORT = 7357;

    public const WS_PORT = 7358;

    /**
     * Where the engine binary lives.
     *
     * Packaged, electron-builder copies `extras/` to `Sonocles.app/Contents/extras`
     * and the runtime hands us the path in NATIVEPHP_EXTRAS_PATH. In development
     * that variable points at `php/extras`, so the same lookup works from
     * `native:run` — provided bin/sync-sidecar.sh has put a build there.
     */
    public static function binary(): ?string
    {
        $extras = env('NATIVEPHP_EXTRAS_PATH') ?: base_path('extras');
        $path = rtrim($extras, '/').'/sonocles-cli';

        return is_executable($path) ? $path : null;
    }

    /**
     * Bring the engine up, unless something is already answering on the port.
     *
     * The check is not politeness. `sonocles-cli` exits non-zero when it cannot
     * bind, and a persistent child process is restarted on exit — so spawning
     * blindly against an already-bound 7357 produces a respawn loop rather than
     * an error. Adopting the running instance is also the behaviour you want
     * while developing against the Swift app.
     */
    public static function ensureRunning(): string
    {
        if (static::isAnswering()) {
            return 'adopted';
        }

        $binary = static::binary();

        if ($binary === null) {
            return 'missing';
        }

        ChildProcess::start(
            cmd: [$binary, '--idle', '--plain', '--quiet'],
            alias: static::ALIAS,
            persistent: true,
        );

        return 'spawned';
    }

    /** Is anything serving the control API right now? */
    public static function isAnswering(): bool
    {
        return static::status() !== null;
    }

    /**
     * The engine's own account of itself, or null if it is not up yet.
     *
     * Short timeouts throughout: this is polled from a popover that has to feel
     * instant, and an engine that is slow to answer /status is one we would
     * rather render as "starting" than wait on.
     */
    public static function status(): ?array
    {
        try {
            $response = Http::timeout(2)->connectTimeout(1)
                ->get(static::url('/status'));
        } catch (\Throwable) {
            return null;
        }

        return $response->successful() ? $response->json() : null;
    }

    public static function start(): ?array
    {
        return static::post('/start');
    }

    public static function stop(): ?array
    {
        return static::post('/stop');
    }

    protected static function post(string $path): ?array
    {
        try {
            $response = Http::timeout(5)->connectTimeout(1)
                ->post(static::url($path));
        } catch (\Throwable) {
            return null;
        }

        return $response->successful() ? $response->json() : null;
    }

    public static function url(string $path = ''): string
    {
        return 'http://127.0.0.1:'.static::HTTP_PORT.$path;
    }

    public static function websocket(): string
    {
        return 'ws://127.0.0.1:'.static::WS_PORT;
    }
}

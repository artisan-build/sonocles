<?php

namespace App\Support;

use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response;
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
 *   control   PHP calls /start, /stop, /status and /engine over loopback
 *             HTTP, with the bearer token from the file the engine wrote.
 *             Human speed. Latency here is invisible.
 *   frames    PHP never sees them. The renderer holds ws://127.0.0.1:7358
 *             itself and sends the same token as its first frame, so
 *             recognised words go engine → socket → DOM without entering the
 *             PHP process at all.
 *
 * That second point is the design. Putting PHP in the frame path would mean a
 * hop through the app's HTTP server every ~200 ms for text that is already 180
 * ms behind the speaker, to spend the budget on a language that has nothing to
 * add to it.
 */
class Sidecar
{
    public const ALIAS = 'sonocles-engine';

    /** The documented ports. config/sonocles.php can move them; nothing else should. */
    public const HTTP_PORT = 7357;

    public const WS_PORT = 7358;

    public static function httpPort(): int
    {
        return (int) (config('sonocles.http_port') ?: static::HTTP_PORT);
    }

    public static function wsPort(): int
    {
        return (int) (config('sonocles.ws_port') ?: static::WS_PORT);
    }

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
            cmd: [
                $binary, '--idle', '--plain', '--quiet',
                '--http', (string) static::httpPort(), '--ws', (string) static::wsPort(),
            ],
            alias: static::ALIAS,
            persistent: true,
        );

        return 'spawned';
    }

    /**
     * Is anything serving the control API right now?
     *
     * A 401 counts as yes. An engine that refuses our token is still an engine
     * holding the port, and the question here is whether to spawn one.
     */
    public static function isAnswering(): bool
    {
        try {
            return static::status() !== null;
        } catch (Unpaired) {
            return true;
        }
    }

    /**
     * The engine's own account of itself, or null if it is not up yet.
     *
     * Short timeouts throughout: this is polled from a popover that has to feel
     * instant, and an engine that is slow to answer /status is one we would
     * rather render as "starting" than wait on.
     *
     * @throws Unpaired when it is up and the token is not the one it wants
     */
    public static function status(): ?array
    {
        try {
            $response = static::request(2)->get(static::url('/status'));
        } catch (\Throwable) {
            return null;
        }

        return static::answer($response);
    }

    public static function start(): ?array
    {
        return static::post('/start');
    }

    public static function stop(): ?array
    {
        return static::post('/stop');
    }

    /**
     * `GET /engine` — the engine as configured, and which ones this Mac can
     * run. The popover offers exactly what `available` lists.
     */
    public static function engine(): ?array
    {
        try {
            $response = static::request(2)->get(static::url('/engine'));
        } catch (\Throwable) {
            return null;
        }

        return static::answer($response);
    }

    /**
     * `POST /engine { engine }` — switch, by slug. Switching while listening
     * is a stop and a start on the engine's side, so the answer can come
     * back `starting`; the popover polls through it as it does after /start.
     *
     * @throws Rejected for a slug the engine does not know or cannot run
     */
    public static function use(string $engine): ?array
    {
        return static::post('/engine', ['engine' => $engine]);
    }

    protected static function post(string $path, array $body = []): ?array
    {
        try {
            $response = static::request(5)->post(static::url($path), $body);
        } catch (\Throwable) {
            return null;
        }

        return static::answer($response);
    }

    /**
     * One request, with the token as the file has it right now. No token
     * means no header, and the engine's 401 says so — which is more honest
     * than not asking.
     */
    protected static function request(int $timeout): PendingRequest
    {
        $request = Http::acceptJson()->timeout($timeout)->connectTimeout(1);
        $token = Token::read();

        return $token === null ? $request : $request->withToken($token);
    }

    protected static function answer(Response $response): ?array
    {
        if ($response->status() === 401) {
            throw new Unpaired;
        }
        if ($response->clientError()) {
            $body = $response->json();
            throw new Rejected($response->status(), is_array($body) ? $body : ['error' => $response->body()]);
        }

        return $response->successful() ? $response->json() : null;
    }

    public static function url(string $path = ''): string
    {
        return 'http://127.0.0.1:'.static::httpPort().$path;
    }

    public static function websocket(): string
    {
        return 'ws://127.0.0.1:'.static::wsPort();
    }
}

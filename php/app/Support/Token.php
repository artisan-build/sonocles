<?php

namespace App\Support;

/**
 * The bearer token, as the engine provisions it (docs/PROTOCOL.md § Authentication).
 *
 * `sonocles-cli` writes it to `~/Library/Application Support/Sonocles/token`
 * (mode 0600) the first time its sockets come up; any app running as the same
 * user reads the file and is paired with zero clicks. This app never writes
 * it — rotating is the engine's job — and it never caches it either: every
 * call re-reads the file, so a rotation from the Swift popover is picked up on
 * the next poll rather than surfacing as a 401 that needs a relaunch to clear.
 *
 * The pattern is Rheocles' `php/app/Rheocles/Token.php`, copied rather than
 * redesigned.
 */
final class Token
{
    public static function path(): string
    {
        return config('sonocles.token_file')
            ?: self::home().'/Library/Application Support/Sonocles/token';
    }

    /** The token, or null when the file is missing or empty. */
    public static function read(): ?string
    {
        $path = self::path();
        if (! is_readable($path)) {
            return null;
        }
        $token = trim((string) file_get_contents($path));

        return $token === '' ? null : $token;
    }

    /**
     * The user's home directory. `$_SERVER['HOME']` is not guaranteed under
     * NativePHP's bundled PHP server the way it is on the CLI.
     */
    public static function home(): string
    {
        $home = $_SERVER['HOME'] ?? getenv('HOME') ?: null;
        if (! $home && function_exists('posix_getpwuid')) {
            $home = posix_getpwuid(posix_geteuid())['dir'] ?? null;
        }

        return $home ?: '/Users/'.get_current_user();
    }
}

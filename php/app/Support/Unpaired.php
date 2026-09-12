<?php

namespace App\Support;

/**
 * The engine answered 401: something is bound to the port and it is not
 * taking our token.
 *
 * This is its own failure rather than a null from Sidecar::status() because
 * the two mean opposite things to the caller. Nothing answering means spawn
 * the bundled engine; a 401 means one is already running and spawning another
 * against its port is the respawn loop Sidecar::ensureRunning() exists to
 * avoid. Collapsing them would also have the popover say "Starting the
 * engine" forever about an engine that is up.
 */
final class Unpaired extends \RuntimeException
{
    public function __construct()
    {
        parent::__construct('the engine refused the bearer token');
    }
}

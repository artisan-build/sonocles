<?php

/*
 * Where the engine is, and how this app is paired with it.
 *
 * The defaults are the ones docs/PROTOCOL.md and the Swift app hardcode; the
 * overrides exist so a second engine can be driven on spare ports while the
 * installed Sonocles.app holds 7357 and 7358 — which is the only way to test
 * anything on a machine where the real one is running.
 */
return [
    'http_port' => (int) env('SONOCLES_HTTP_PORT', 7357),
    'ws_port' => (int) env('SONOCLES_WS_PORT', 7358),

    // The bearer token file. Null means the standard place,
    // ~/Library/Application Support/Sonocles/token (PROTOCOL § Authentication).
    'token_file' => env('SONOCLES_TOKEN_FILE'),
];

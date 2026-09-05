<?php

use App\Support\Sidecar;
use Illuminate\Support\Facades\Route;

/*
 * The popover, and the three control calls behind it.
 *
 * Note what is absent: any route carrying recognised words. Frames go from the
 * engine's WebSocket straight into the renderer, so nothing here sits in the
 * 180 ms path. These routes only move the engine between idle and listening,
 * which happens when a person clicks something.
 */

Route::get('/', function () {
    return view('menubar', [
        'websocket' => Sidecar::websocket(),
        'binary' => Sidecar::binary(),
    ]);
});

Route::get('/engine/status', function () {
    $status = Sidecar::status();

    return response()->json([
        // Three states, not a boolean, for the reason the protocol gives: POST
        // /start returns before capture is up, and answering "not listening" to
        // a request that just succeeded reads as a failure.
        'up' => $status !== null,
        'engine' => $status,
        'binary' => Sidecar::binary(),
    ]);
});

Route::post('/engine/start', fn () => response()->json(Sidecar::start() ?? ['error' => 'no engine']));
Route::post('/engine/stop', fn () => response()->json(Sidecar::stop() ?? ['error' => 'no engine']));

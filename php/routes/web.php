<?php

use App\Support\Sidecar;
use App\Support\Token;
use App\Support\Unpaired;
use Illuminate\Support\Facades\Route;
use Native\Desktop\Facades\App;

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
    try {
        $status = Sidecar::status();
        $paired = true;
    } catch (Unpaired) {
        // Up, and not ours to drive: the popover says so rather than "starting".
        $status = null;
        $paired = false;
    }

    return response()->json([
        // Three states, not a boolean, for the reason the protocol gives: POST
        // /start returns before capture is up, and answering "not listening" to
        // a request that just succeeded reads as a failure.
        'up' => $status !== null || ! $paired,
        'paired' => $paired,
        'engine' => $status,
        'binary' => Sidecar::binary(),
        'ports' => ['http' => Sidecar::httpPort(), 'ws' => Sidecar::wsPort()],
    ]);
});

// The renderer's copy of the token, for the WebSocket's first frame. Read on
// every connect rather than baked into the page, so a rotation is a reconnect
// and not a relaunch. This server is loopback and behind NativePHP's own
// secret, which is the same footing the file itself is on.
Route::get('/engine/token', fn () => response()->json(['token' => Token::read()]));

// The engine's answer, or the engine's refusal, in the engine's own terms: a
// 401 there is a 401 here, and nothing answering is a 503.
$forward = function (Closure $call) {
    try {
        $answer = $call();
    } catch (Unpaired) {
        return response()->json(['error' => 'not paired'], 401);
    }

    return $answer === null
        ? response()->json(['error' => 'no engine'], 503)
        : response()->json($answer);
};

Route::post('/engine/start', fn () => $forward(Sidecar::start(...)));
Route::post('/engine/stop', fn () => $forward(Sidecar::stop(...)));

// The popover's Quit, which the Swift app gets from NSApplication for free.
Route::post('/app/quit', function () {
    App::quit();

    return response()->noContent();
});

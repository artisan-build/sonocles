<?php

use App\Support\Rejected;
use App\Support\Sidecar;
use App\Support\Token;
use App\Support\Unpaired;
use Illuminate\Support\Facades\Route;
use Native\Desktop\Facades\App;

/*
 * The popover, and the control calls behind it.
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
        // The token as the file has it right now, for the popover's Control
        // API block — re-read on every poll, so a rotation made anywhere
        // shows within a second. Same footing as /engine/token below.
        'token' => Token::read(),
    ]);
});

// The renderer's copy of the token, for the WebSocket's first frame. Read on
// every connect rather than baked into the page, so a rotation is a reconnect
// and not a relaunch. This server is loopback and behind NativePHP's own
// secret, which is the same footing the file itself is on.
Route::get('/engine/token', fn () => response()->json(['token' => Token::read()]));

// The engine's answer, or the engine's refusal, in the engine's own terms: a
// 401 there is a 401 here, a 400 comes through with its body, and nothing
// answering is a 503.
$forward = function (Closure $call) {
    try {
        $answer = $call();
    } catch (Unpaired) {
        return response()->json(['error' => 'not paired'], 401);
    } catch (Rejected $e) {
        return response()->json($e->body, $e->status);
    }

    return $answer === null
        ? response()->json(['error' => 'no engine'], 503)
        : response()->json($answer);
};

Route::post('/engine/start', fn () => $forward(Sidecar::start(...)));
Route::post('/engine/stop', fn () => $forward(Sidecar::stop(...)));

// `GET /` on the engine: name, version, ports. The popover's strip shows the
// version — asked once when the engine comes up, since it cannot change
// while it is running.
Route::get('/engine/about', fn () => $forward(Sidecar::discover(...)));

// The popover's Rotate: the engine rewrites its file and every other paired
// client has to read it again — including this app, which does so on its
// next poll. The answer is the engine's, token included, as the route gives it.
Route::post('/engine/token/rotate', fn () => $forward(Sidecar::rotateToken(...)));

// The engine control. GET /engine/choices is what the segmented control is
// built from — the engine's `available`, which is the list this Mac can run,
// so Apple is not offered on macOS 15 to be refused. POST /engine/use
// forwards { engine: "<slug>" } to POST /engine; the popover then polls,
// because a switch while listening is a stop and a start on the engine's
// side and the answer may say `starting`.
Route::get('/engine/choices', fn () => $forward(Sidecar::engine(...)));
Route::post('/engine/use', fn () => $forward(fn () => Sidecar::use((string) request()->input('engine'))));

// The popover's Quit, which the Swift app gets from NSApplication for free.
Route::post('/app/quit', function () {
    App::quit();

    return response()->noContent();
});

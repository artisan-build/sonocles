<?php

namespace Tests\Feature;

use App\Support\Sidecar;
use Tests\TestCase;

/**
 * What is worth testing on the PHP side, and what is not.
 *
 * The engine is not tested here. It is tested in `app/`, in Swift, by the suite
 * that owns it — and a test of recognition that passed because it heard nothing
 * would be worse than no test at all. Nothing in this application recognises
 * speech.
 *
 * What this application actually does is locate a binary, decide whether to
 * spawn one or adopt a running one, and keep "absent" distinct from "zero".
 * Those are the failure modes that belong to PHP, so those are what these cover.
 */
class SidecarTest extends TestCase
{
    public function test_binary_returns_null_or_something_executable(): void
    {
        $found = Sidecar::binary();

        // Either a build has been synced into extras/ or it has not; both are
        // legitimate states. What is never legitimate is handing back a path to
        // something that cannot be executed, because the caller would spawn it.
        $this->assertTrue(
            $found === null || is_executable($found),
            'binary() must return null or an executable path, never a hopeful string'
        );
    }

    public function test_it_addresses_the_engine_on_the_documented_ports(): void
    {
        // Hardcoded in the Swift app and in docs/PROTOCOL.md. If these drift,
        // the front end talks confidently to nothing — which is precisely the
        // failure mode this project keeps having to relearn.
        $this->assertSame('http://127.0.0.1:7357/status', Sidecar::url('/status'));
        $this->assertSame('ws://127.0.0.1:7358', Sidecar::websocket());
    }

    public function test_an_unreachable_engine_is_absent_not_idle(): void
    {
        if (Sidecar::isAnswering()) {
            $this->markTestSkipped('an engine is live on 7357, so unreachability cannot be observed');
        }

        // status() has to distinguish "the engine reports idle" from "there is
        // no engine". Collapsing those is how a UI ends up confidently
        // rendering a state it never observed — the same class of mistake as
        // reporting an unmeasured latency as +0ms.
        $this->assertNull(Sidecar::status());
    }
}

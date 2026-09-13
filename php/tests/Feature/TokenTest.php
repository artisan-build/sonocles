<?php

namespace Tests\Feature;

use App\Support\Sidecar;
use App\Support\Token;
use App\Support\Unpaired;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Pairing, from PHP's side of it.
 *
 * The engine's auth is tested in Swift, where it lives. What is PHP's to get
 * wrong is narrower: reading the file the engine wrote, putting its contents
 * on every request, and not mistaking "refused" for "absent" — because the
 * response to absent is to spawn an engine, and spawning one against a port
 * that is already held is the respawn loop Sidecar exists to prevent.
 */
class TokenTest extends TestCase
{
    private string $file;

    protected function setUp(): void
    {
        parent::setUp();
        $this->file = tempnam(sys_get_temp_dir(), 'sonocles-token-');
        config(['sonocles.token_file' => $this->file]);
    }

    protected function tearDown(): void
    {
        @unlink($this->file);
        parent::tearDown();
    }

    public function test_the_popover_prints_the_path_with_the_home_directory_as_a_tilde(): void
    {
        // The full path carries the login name; the popover, its screenshots
        // and the site never show it.
        config(['sonocles.token_file' => Token::home().'/Library/Application Support/Sonocles/token']);
        $this->assertSame('~/Library/Application Support/Sonocles/token', Token::abbreviated());

        config(['sonocles.token_file' => '/tmp/elsewhere/token']);
        $this->assertSame('/tmp/elsewhere/token', Token::abbreviated());
    }

    public function test_the_token_is_the_file_trimmed_and_an_empty_file_is_no_token(): void
    {
        file_put_contents($this->file, str_repeat('a', 64)."\n");
        $this->assertSame(str_repeat('a', 64), Token::read());

        // An empty token would send `Authorization: Bearer ` and let the engine
        // explain; better to send nothing and know we have nothing.
        file_put_contents($this->file, "\n");
        $this->assertNull(Token::read());

        unlink($this->file);
        $this->assertNull(Token::read());
    }

    public function test_every_control_call_carries_the_bearer_token(): void
    {
        file_put_contents($this->file, str_repeat('b', 64));
        Http::fake([Sidecar::url('/*') => Http::response(['state' => 'idle', 'listening' => false])]);

        Sidecar::status();
        Sidecar::start();
        Sidecar::stop();

        Http::assertSentCount(3);
        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer '.str_repeat('b', 64)));
        Http::assertNotSent(fn (Request $r) => ! $r->hasHeader('Authorization'));
    }

    public function test_the_file_is_read_on_every_call_so_a_rotation_needs_no_relaunch(): void
    {
        Http::fake([Sidecar::url('/*') => Http::response(['state' => 'idle'])]);

        file_put_contents($this->file, str_repeat('c', 64));
        Sidecar::status();
        file_put_contents($this->file, str_repeat('d', 64));
        Sidecar::status();

        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer '.str_repeat('c', 64)));
        Http::assertSent(fn (Request $r) => $r->hasHeader('Authorization', 'Bearer '.str_repeat('d', 64)));
    }

    public function test_a_401_is_an_engine_that_is_up_not_an_engine_that_is_absent(): void
    {
        Http::fake([Sidecar::url('/*') => Http::response(['error' => 'authentication required'], 401)]);

        $this->assertTrue(Sidecar::isAnswering(), 'a refusing engine holds the port; spawning another is the respawn loop');
        $this->expectException(Unpaired::class);
        Sidecar::status();
    }

    public function test_the_popover_is_told_up_and_unpaired_rather_than_starting(): void
    {
        Http::fake([Sidecar::url('/*') => Http::response(['error' => 'authentication required'], 401)]);

        $this->getJson('/engine/status')
            ->assertOk()
            ->assertJson(['up' => true, 'paired' => false, 'engine' => null]);
        $this->postJson('/engine/start')->assertStatus(401)->assertJson(['error' => 'not paired']);
    }

    public function test_the_renderer_gets_the_token_for_its_first_frame(): void
    {
        file_put_contents($this->file, str_repeat('e', 64));
        $this->getJson('/engine/token')->assertOk()->assertJson(['token' => str_repeat('e', 64)]);
    }

    public function test_the_popover_gets_the_token_as_the_file_has_it_on_every_poll(): void
    {
        Http::fake([Sidecar::url('/*') => Http::response(['state' => 'idle', 'listening' => false, 'clients' => 0])]);

        file_put_contents($this->file, str_repeat('g', 64));
        $this->getJson('/engine/status')->assertOk()->assertJson(['paired' => true, 'token' => str_repeat('g', 64)]);

        // Rotated underneath us: the next poll shows the new one, no relaunch.
        file_put_contents($this->file, str_repeat('h', 64));
        $this->getJson('/engine/status')->assertOk()->assertJson(['token' => str_repeat('h', 64)]);

        unlink($this->file);
        $this->getJson('/engine/status')->assertOk()->assertJson(['token' => null]);
    }

    public function test_rotate_is_forwarded_to_the_engine_and_its_answer_comes_back_verbatim(): void
    {
        file_put_contents($this->file, str_repeat('i', 64));
        $answer = ['token' => str_repeat('j', 64)];
        Http::fake([Sidecar::url('/token/rotate') => Http::response($answer)]);

        $this->postJson('/engine/token/rotate')->assertOk()->assertExactJson($answer);

        // With the token the file had: rotation is itself behind the token.
        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && $r->url() === Sidecar::url('/token/rotate')
            && $r->hasHeader('Authorization', 'Bearer '.str_repeat('i', 64)));
    }

    public function test_rotate_against_a_refusing_engine_is_a_401_not_a_new_token(): void
    {
        file_put_contents($this->file, str_repeat('k', 64));
        Http::fake([Sidecar::url('/token/rotate') => Http::response(['error' => 'authentication required'], 401)]);

        $this->postJson('/engine/token/rotate')->assertStatus(401)->assertJson(['error' => 'not paired']);
    }
}

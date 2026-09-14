<?php

namespace Tests\Feature;

use App\Support\Sidecar;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The engine control, from PHP's side of it.
 *
 * Which engines exist, which this Mac can run, and what switching does to a
 * running capture are all the engine's business and tested in Swift. What is
 * PHP's to get wrong is the forwarding: the slug goes across as the engine
 * expects it, the engine's refusal comes back as the engine said it rather
 * than paraphrased, and nothing here invents an answer the engine did not give.
 */
class EngineTest extends TestCase
{
    private string $file;

    protected function setUp(): void
    {
        parent::setUp();
        $this->file = tempnam(sys_get_temp_dir(), 'sonocles-token-');
        file_put_contents($this->file, str_repeat('f', 64));
        config(['sonocles.token_file' => $this->file]);
    }

    protected function tearDown(): void
    {
        @unlink($this->file);
        parent::tearDown();
    }

    private const SHAPE = ['engine' => 'fluid320', 'label' => 'Parakeet 320 ms',
        'available' => ['fluid160', 'fluid320', 'fluid1280', 'apple']];

    public function test_choices_are_the_engines_own_list_verbatim(): void
    {
        Http::fake([Sidecar::url('/engine') => Http::response(self::SHAPE)]);

        $this->getJson('/engine/choices')->assertOk()->assertExactJson(self::SHAPE);
    }

    public function test_use_forwards_the_slug_to_post_engine_and_returns_the_answer(): void
    {
        Http::fake([Sidecar::url('/engine') => Http::response(self::SHAPE)]);

        $this->postJson('/engine/use', ['engine' => 'fluid320'])->assertOk()->assertExactJson(self::SHAPE);

        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && $r->url() === Sidecar::url('/engine')
            && $r['engine'] === 'fluid320'
            && $r->hasHeader('Authorization', 'Bearer '.str_repeat('f', 64)));
    }

    public function test_a_refused_slug_comes_back_as_the_engine_said_it(): void
    {
        $refusal = ['error' => "unknown engine 'fluid9000' — one of fluid160, fluid320, fluid1280, apple"];
        Http::fake([Sidecar::url('/engine') => Http::response($refusal, 400)]);

        // The engine's status and the engine's words, not a 500 and a stack
        // trace, and not a 200 with an error inside it.
        $this->postJson('/engine/use', ['engine' => 'fluid9000'])->assertStatus(400)->assertExactJson($refusal);
    }

    public function test_no_engine_is_a_503_not_a_made_up_choice(): void
    {
        Http::fake(fn () => throw new ConnectionException('refused'));

        $this->getJson('/engine/choices')->assertStatus(503)->assertJson(['error' => 'no engine']);
    }

    public function test_about_is_the_engines_own_discovery_answer_verbatim(): void
    {
        $discovery = ['name' => 'Sonocles', 'version' => '0.1.3', 'auth' => 'bearer', 'ports' => ['http' => 7357, 'ws' => 7358]];
        Http::fake([Sidecar::url('/') => Http::response($discovery)]);

        // The strip shows this version; it is the engine's word, not this
        // app's, and a missing engine is a 503 rather than a version made up here.
        $this->getJson('/engine/about')->assertOk()->assertExactJson($discovery);
        Http::assertSent(fn (Request $r) => $r->method() === 'GET'
            && $r->url() === Sidecar::url('/')
            && $r->hasHeader('Authorization', 'Bearer '.str_repeat('f', 64)));

        Http::fake(fn () => throw new ConnectionException('refused'));
        $this->getJson('/engine/about')->assertStatus(503)->assertJson(['error' => 'no engine']);
    }
}

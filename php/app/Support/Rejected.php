<?php

namespace App\Support;

/**
 * The engine answered with the protocol's error shape — a 400 for an engine
 * slug it does not know or this Mac cannot run. Carried whole, status and
 * body, so the popover's route can pass the engine's own words through
 * rather than paraphrase them.
 */
final class Rejected extends \RuntimeException
{
    public function __construct(public readonly int $status, public readonly array $body)
    {
        parent::__construct($body['error'] ?? "the engine answered $status");
    }
}

<?php

namespace App\Providers;

use App\Support\Sidecar;
use Native\Desktop\Contracts\ProvidesPhpIni;
use Native\Desktop\Facades\MenuBar;

class NativeAppServiceProvider implements ProvidesPhpIni
{
    /**
     * Executed once the native application has been booted.
     */
    public function boot(): void
    {
        // Bring the Swift engine up before the UI, so the popover has something
        // to report the first time it is opened. This does not start capture —
        // `--idle` binds the sockets and waits for POST /start — which keeps the
        // microphone prompt attached to a deliberate click rather than to app
        // launch, where a user has no idea what asked or why.
        Sidecar::ensureRunning();

        // No ->showDockIcon(), and that is the point: a menu bar app without it
        // hides the dock icon, which is what LSUIElement buys the Swift build.
        //
        // The icon is a `...Template.png`. macOS reads only its alpha channel
        // and tints it for a light or dark menu bar, so it cannot render as the
        // wrong colour — including the wrong colour of "none at all", which is
        // the bug the Swift app shipped and had to fix by hand.
        MenuBar::create()
            ->icon(resource_path('menubar/sonoclesTemplate.png'))
            ->tooltip('Sonocles')
            ->width(380)
            ->height(520)
            ->resizable(false)
            ->url(url('/'));
    }

    /**
     * Return an array of php.ini directives to be set.
     */
    public function phpIni(): array
    {
        return [];
    }
}

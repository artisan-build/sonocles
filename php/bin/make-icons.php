<?php

/**
 * Draw the Sonocles mark as macOS menu bar template images.
 *
 * A template image carries no colour of its own — macOS reads only the alpha
 * channel and tints the result to match a light or dark menu bar. That is the
 * whole reason this file exists rather than a copy of the app's coloured mark:
 * the Swift app shipped a build where the menu bar label was a plain SwiftUI
 * view which inherited no foreground style, took its slot, and drew nothing at
 * all. Alpha-only makes that failure unreachable.
 *
 * Everything is drawn at 8x and scaled down, because GD's arc thickness is a
 * stepped pixel run with no anti-aliasing. Supersampling is what turns it into
 * a smooth edge.
 *
 *   php bin/make-icons.php
 */
const SUPERSAMPLE = 8;

function mark(int $size): \GdImage
{
    $s = $size * SUPERSAMPLE;

    $im = imagecreatetruecolor($s, $s);
    imagealphablending($im, false);
    imagesavealpha($im, true);

    // Fill with *black at full transparency*, not with a transparent colour
    // index. Downscaling averages the colour channels as well as alpha, so a
    // canvas whose invisible pixels are some other colour bleeds that colour
    // into every anti-aliased edge. Uniform black means only alpha ever varies.
    $clear = imagecolorallocatealpha($im, 0, 0, 0, 127);
    imagefilledrectangle($im, 0, 0, $s, $s, $clear);

    imagealphablending($im, true);
    $ink = imagecolorallocate($im, 0, 0, 0);

    // The mark: an emitter, and three wavefronts leaving it. Radii are spaced
    // by a constant gap rather than a ratio so the arcs stay evenly separated
    // at 22 pt, where a geometric progression collapses the inner two together.
    //
    // The outer radius is bounded by the canvas, not by taste. An arc spanning
    // +/-54 degrees reaches 0.809r above and below its centre, so anything past
    // r = (0.5 - halfStroke) / 0.809 gets its tips squared off by the edge —
    // which reads as a broken glyph rather than a small one.
    $cx = (int) round($s * 0.30);
    $cy = (int) round($s * 0.50);

    imagefilledellipse($im, $cx, $cy, (int) round($s * 0.17), (int) round($s * 0.17), $ink);

    imagesetthickness($im, max(1, (int) round($s * 0.072)));

    foreach ([0.24, 0.40, 0.56] as $r) {
        $d = (int) round($s * $r * 2);
        imagearc($im, $cx, $cy, $d, $d, -54, 54, $ink);
    }

    $out = imagescale($im, $size, $size, IMG_BICUBIC);
    imagesavealpha($out, true);
    imagedestroy($im);

    return $out;
}

$dir = __DIR__.'/../resources/menubar';
@mkdir($dir, 0755, true);

// The `Template` suffix is not decoration: Electron keys template behaviour off
// the filename, and `@2x` is how it finds the retina variant beside it.
imagepng(mark(22), "$dir/sonoclesTemplate.png");
imagepng(mark(44), "$dir/sonoclesTemplate@2x.png");

echo "wrote sonoclesTemplate.png (22) and sonoclesTemplate@2x.png (44)\n";

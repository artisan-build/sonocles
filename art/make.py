#!/usr/bin/env python3
"""
Image assets for the Sonocles site, via OpenAI's gpt-image-2.

    export OPENAI_API_KEY=...          # or --env path/to/.env
    python3 art/make.py --list
    python3 art/make.py --only hero --quality high
    python3 art/make.py --dry-run      # print prompts, spend nothing

Every call costs money, so nothing regenerates unless asked: a plate that
already exists in site/img is skipped unless --force. The talks repo learned
this the expensive way — a pose library one `rm -rf` from gone — so the outputs
here are committed, not scratch.

THE DIRECTION
Attic red-figure pottery, played straight and then subverted exactly once. The
palette is the real one (terracotta clay, black slip, bone) and the drawing
convention is the real one (profile faces, black ground, reserved figures). The
joke is only ever the *subject*: a fifth-century vase painter, given a modern
scene, would have painted it exactly like this.

No lettering, ever. The model cannot spell Greek and the gibberish reads as
carelessness rather than antiquity — the wordmark is set in Cinzel in the page.
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "img"

# The shared grammar. Every prompt inherits it so the set reads as one hand.
STYLE = """
Authentic Attic red-figure vase painting, circa 440 BC, as photographed for a
museum catalogue. The figures are reserved in the natural orange-red terracotta
of the clay; the ground around them is dense lustrous black slip. Interior
detail is drawn with fine black relief lines, not shading. Figures in strict
profile with frontal eyes, in the manner of the Berlin Painter — economical,
confident, unhurried linework.

Palette strictly limited to: fired terracotta orange-red, deep warm black slip,
and the pale bone of unpainted clay. A trace of added white and diluted golden
glaze is permitted. No blues, greens, purples or modern hues. No gradients, no
glow, no digital sheen.

The surface shows its age honestly: fine crazing, a few small chips at the
edges, the faint unevenness of a hand-thrown wall. Lit softly from the upper
left as an object on a plinth, with a soft falloff into the background.

Absolutely no lettering, no inscriptions, no Greek characters, no numerals, no
watermarks or signatures anywhere in the image.
"""


# The style the site actually uses.
#
# The first set (STYLE, below the flat plates) produced photographed
# antiquities. They were beautiful and the page read like a catalogue —
# accurate, and far too solemn for a 220 MB menu bar utility. This one keeps the
# subjects and the jokes and drops the reverence: illustration that has clearly
# *looked* at Greek vase painting rather than pretending to be one.
STYLE_FLAT = """
Flat modern vector illustration in a bold, playful, comic style. A contemporary
editorial illustrator riffing on Greek vase painting — clearly inspired by it,
absolutely not pretending to be an artifact.

Clean confident shapes with thick even outlines. Completely flat colour fills:
no gradients, no shading, no texture, no photographic realism. Characters are
warm and funny with expressive cartoon faces — big eyes, real emotions, visible
personality — with slightly rounded, friendly proportions and comedic timing in
the poses.

Palette strictly: warm terracotta orange, deep brick red, pale limestone cream,
soft olive green, and a dark warm charcoal for outlines. Nothing else.

Set on a plain flat pale limestone-cream background with generous empty space
around the subject. No vase, no pottery, no crazing, no chips, no museum
lighting, no plinth, no frame, no photographic background. Pure flat graphic
illustration, as though screen printed.

Absolutely no lettering, no text, no Greek characters, no numerals, no
watermarks anywhere. All figures fully clothed in simple draped tunics.
"""

PLATES = {
    # --- the flat set: what the site uses ---------------------------------
    "flat-hero": (
        "1536x1024",
        """
        Two characters, wide composition, lots of breathing room.

        On the left, a cheerful bearded philosopher in a draped tunic stands
        mid-sentence, one hand raised, mouth open, thoroughly enjoying the sound
        of his own voice. From his mouth, three bold concentric arcs struck from
        a single filled dot sweep rightward across the composition.

        On the right, a younger scribe sits on a stool — wide-eyed and delighted
        rather than stressed — writing furiously on a wax tablet, keeping up
        easily. Small motion marks show how fast the stylus is moving.

        The joke is that he is keeping up. Both are having a good time.
        """,
        STYLE_FLAT,
    ),
    "flat-contention": (
        "1536x1024",
        """
        A comedy of two characters and one desk.

        Two figures in draped tunics are crammed shoulder to shoulder at a
        single small desk, each trying to work, elbows visibly colliding. The
        one on the right is a scribe whose stylus has been knocked, drawing a
        wild jagged scribble right off the edge of his tablet. Both wear
        expressions of strained comic politeness — gritted smiles, neither
        willing to be the one who says something.

        Beside them, roomy and completely empty, stands a second identical desk
        with a comfortable stool tucked under it. Nobody is looking at it.
        """,
        STYLE_FLAT,
    ),
    "flat-listener": (
        "1024x1024",
        """
        A single character, centred, full of personality. A round friendly
        bearded figure in a draped tunic leans forward with one hand cupped
        dramatically behind an enormous ear, eyes squeezed shut in theatrical
        concentration, grinning. Three small concentric arcs arrive at his hand
        from the edge of the frame. Comic, warm, slightly absurd.
        """,
        STYLE_FLAT,
    ),
    "flat-mic": (
        "1536x1024",
        """
        A relaxed bearded character in a draped tunic reclines comfortably on a
        low couch with a cup of wine, talking happily into a big retro broadcast
        microphone on a stand — completely unbothered, mid-anecdote. Bold
        concentric arcs travel from his mouth into the microphone.

        Hovering just behind him, a small chubby winged figure with a wax tablet
        takes notes with an expression of extreme professional focus, tongue
        poking out. Nobody in the picture finds any of this unusual.
        """,
        STYLE_FLAT,
    ),
    "flat-theatre": (
        "1024x1024",
        """
        A Greek amphitheatre seen from directly above, drawn as clean flat
        graphic geometry: concentric rings of seating in alternating terracotta
        and limestone cream, cut by radial aisles, with a small circular stage
        at the exact centre where one tiny cheerful figure stands, arms raised.

        The rings read equally as seating and as a sound wave radiating from
        that figure. Crisp, symmetrical, satisfying. Flat, no perspective, no
        shading.
        """,
        STYLE_FLAT,
    ),
    "flat-column": (
        "1024x1536",
        """
        A single Doric column, isolated and centred, drawn as flat graphic
        illustration in pale limestone cream with a dark charcoal outline and a
        simple terracotta capital and base. Vertical fluting shown as clean
        straight lines. Complete from base to capital, standing upright and
        perfectly vertical, filling the height of the frame.

        Absolutely nothing else in the image. Plain flat cream background.
        """,
        STYLE_FLAT,
    ),

    # --- the museum set: kept for reproducibility, no longer on the page ---

    "hero": (
        "1536x1024",
        """
        A wide fragment of a large krater. The painted scene: a seated bearded
        man in a himation speaks, his near hand raised in the orator's gesture,
        his mouth slightly open. Directly in front of his lips, three concentric
        arcs radiate outward from a single small filled dot — drawn in clean
        black relief line, unmistakably a wave of sound leaving him.

        Facing him across the scene, a second figure sits attentively with one
        hand cupped behind the ear and the other holding a stylus over a wax
        tablet, already writing. The arcs reach that figure's ear.

        The composition reads left to right: speech leaving one mouth, arriving
        at one ear, becoming a written mark. Meander border along the lower
        edge only.
        """,
        STYLE,
    ),
    "chorus": (
        "1024x1024",
        """
        A drinking cup interior (tondo), circular composition. Five identical
        chorus members stand in a tight rank in profile, all facing the same
        direction, mouths open in unison, arms raised in the same gesture — a
        single voice made of many. From the group, one set of concentric arcs
        radiates toward the rim of the tondo. A simple black band frames the
        circle.
        """,
        STYLE,
    ),
    "theatre": (
        "1024x1024",
        """
        The exterior of a round pyxis lid, seen from directly above. The design
        is a Greek amphitheatre drawn as pure geometry from a bird's eye view:
        concentric tiers of seating in reserved terracotta, separated by radial
        stairs in black slip, with a small circular orchestra at the centre
        containing one lone standing figure in profile.

        The tiers double, unmistakably, as the arcs of a sound wave radiating
        from that single figure. Severe, diagrammatic, beautiful.
        """,
        STYLE,
    ),
    "listener": (
        "1024x1024",
        """
        A tall narrow lekythos panel. A single mature bearded man stands in
        profile, fully and modestly clothed in a heavy floor-length himation
        that covers both shoulders and falls to the ankles, with a long tunic
        beneath. He is completely still, head tilted very slightly, one hand
        cupped behind the ear. The pose is concentrated attention and nothing
        else — no instrument, no companion, no action. Empty black ground fills
        the rest of the panel generously.

        Faint concentric arcs enter from the panel's edge and terminate exactly
        at the cupped hand.
        """,
        STYLE,
    ),
    "anachronism": (
        "1536x1024",
        """
        The joke plate, played completely straight — every convention obeyed so
        the anachronism lands quietly rather than as parody.

        A wide vase panel. A bearded man in a himation reclines on a klismos
        chair in strict profile, exactly as a symposiast would. In front of him,
        instead of a lyre, stands a large studio broadcast microphone on a
        slender stand — rendered in the same black relief line and reserved
        terracotta as everything else, as though the painter had simply seen one
        and drawn it faithfully.

        His near hand is raised mid-speech. Concentric arcs travel from his
        mouth into the microphone's grille. Behind him a small winged figure
        hovers, holding a wax tablet and stylus, transcribing. Meander border
        below.
        """,
        STYLE,
    ),
    "contention": (
        "1536x1024",
        """
        A wide vase panel about two craftsmen and one bench, drawn with total
        sincerity.

        Two figures are crowded at a single small worktable, each trying to do
        their own job in a space that fits one. On the left a man works a
        potter's wheel; on the right a scribe leans in over a wax tablet. Their
        elbows collide in the centre of the composition — the scribe's stylus
        arm is knocked, his line skidding visibly off course across the tablet.
        Both faces show strained concentration rather than anger.

        Beneath the table, deliberately spacious and completely empty, a second
        identical worktable stands entirely unused.
        """,
        STYLE,
    ),
    "banner": (
        "1536x1024",
        """
        A long horizontal frieze band, far wider than it is tall, of the kind
        that runs around the shoulder of a large vessel. Read left to right:

        A mature bearded man in a full-length himation stands at the left,
        modestly and completely clothed, one hand raised in speech. From his
        mouth, three concentric arcs struck from a single filled dot travel
        rightward across the whole width of the band, passing behind and between
        the other figures.

        In the middle, two draped attendants walk in step beneath the arcs,
        carrying a wax tablet and a stylus between them. At the right, a seated
        clothed scribe receives the arcs at his ear and writes.

        The band is bordered above and below by a running meander. Generous
        black ground. Every figure fully clothed in heavy drapery.
        """,
        STYLE,
    ),
    "sherd": (
        "1024x1024",
        """
        A single small broken potsherd photographed straight down on a plain
        neutral surface, isolated with generous empty space around it. The sherd
        is an irregular triangular fragment with genuinely broken edges. Its
        painted surface carries only a partial fragment of a design: two
        concentric black arcs and part of a filled dot, cut off by the break.

        Nothing else on the sherd. It reads as one recovered piece of a larger
        wave.
        """,
        STYLE,
    ),
}


def load_env(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))


def generate(size: str, body: str, quality: str, key: str, style: str) -> bytes:
    prompt = (style + "\n" + body).strip()
    payload = json.dumps(
        {
            "model": "gpt-image-2",
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": 1,
        }
    ).encode()

    request = urllib.request.Request(
        "https://api.openai.com/v1/images/generations",
        data=payload,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )

    with urllib.request.urlopen(request, timeout=600) as response:
        data = json.load(response)

    return base64.b64decode(data["data"][0]["b64_json"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--quality", default="high", choices=["low", "medium", "high"])
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--env",
        default=str(Path.home() / "Code/ProjektGopher/talks/.env"),
        help="where OPENAI_API_KEY lives, if not already in the environment",
    )
    args = parser.parse_args()

    if args.list:
        for name, (size, body, _style) in PLATES.items():
            first = " ".join(body.split())[:88]
            print(f"{name:14} {size:10} {first}…")
        return 0

    wanted = args.only or list(PLATES)
    OUT.mkdir(parents=True, exist_ok=True)

    if not args.dry_run:
        load_env(Path(args.env))
        key = os.environ.get("OPENAI_API_KEY")
        if not key:
            print("no OPENAI_API_KEY", file=sys.stderr)
            return 1
    else:
        key = ""

    for name in wanted:
        if name not in PLATES:
            print(f"unknown plate '{name}'", file=sys.stderr)
            continue

        size, body, style = PLATES[name]
        target = OUT / f"{name}.png"

        if target.exists() and not args.force:
            print(f"{name:14} exists, skipping (--force to redo)")
            continue

        if args.dry_run:
            print(f"--- {name} ({size}) ---")
            print((style + "\n" + body).strip())
            print()
            continue

        print(f"{name:14} generating {size} {args.quality}…", flush=True)
        try:
            target.write_bytes(generate(size, body, args.quality, key, style))
            print(f"{name:14} -> {target.relative_to(ROOT)}")
        except urllib.error.HTTPError as error:
            print(f"{name:14} FAILED {error.code}: {error.read()[:400]!r}", file=sys.stderr)
        except Exception as error:  # noqa: BLE001
            print(f"{name:14} FAILED {error}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

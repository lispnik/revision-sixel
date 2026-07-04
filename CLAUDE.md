# CLAUDE.md

Guidance for working in this repo. It's a small, single-purpose demo — keep changes minimal and idiomatic to the surrounding Lisp.

## What this is

A demo that decodes a baseline JPEG with `jpeg-sixel` and paints it as real **sixel** graphics inside a `tv2` (CLOS-native Turbo Vision) view. It is deliberately *not* a general image widget: single full-screen image, optional gallery cycling, no scroll/zoom.

## Commands

```sh
make            # compile + load the system (build check)
make test       # headless (no-tty) test suite
make bin        # dump ./revision-sixel-demo (self-contained SBCL executable)
make clean      # remove this project's fasl cache + the dumped binary
```

From a REPL:

```lisp
(asdf:load-system "revision-sixel")
(revision-sixel:demo)                    ; gallery: coast / nature / flower
(revision-sixel:run)                     ; single image (coast)
(revision-sixel:run "media/flower.jpg")  ; any baseline JPEG
(asdf:test-system "revision-sixel")      ; == make test
```

`make test` is headless and safe to run anywhere. The interactive `run`/`demo` loop needs a real **sixel-capable tty** (iTerm2, foot, WezTerm, mlterm, `xterm -ti vt340`) — it can't be exercised in this environment; ask the user to run it.

## Layout

- [revision-sixel.lisp](src/revision-sixel.lisp) — everything: the `image-view`, sixel prep/emit, keymap, event loop, and the executable `main`.
- [package.lisp](src/package.lisp) — exports `run`, `demo`, `main`, `image-view`, `*default-image*`, `*gallery*`.
- [headless.lisp](tests/headless.lisp) — no-tty checks (view construction, geometry, real sixel generation, no-screen safety).
- [build.lisp](build.lisp) — bakes bundled JPEGs into `*embedded-images*` and dumps the executable (toplevel `main`).
- `media/` — bundled **baseline** JPEG samples.

## The core idea (read before touching drawing code)

tv2 renders into a character-cell back buffer and flushes only *changed* cells. Sixels aren't cells — they're a raw escape sequence the terminal paints at the cursor's pixel position. So `image-view` works in both worlds:

1. `draw` (method) paints chrome (title, hint, cleared image area) into the cell buffer via the normal `tv2::fill-row` / `tv2::draw-text` helpers.
2. `emit-overlay` writes the cached sixel straight to `screen-out` *after* `flush-screen`, positioned at the image origin and wrapped in `ESC 7`/`ESC 8` (DECSC/DECRC) so it never disturbs tv2's cursor/scroll state.

The event loop in `run-gallery` is the shared tv2 loop plus one line: call `emit-overlay` after each flush. Painting cells over the image (e.g. the help overlay) erases the sixel underneath — that's how `draw-help` hides it.

## Conventions & constraints

- **Baseline JPEGs only.** cl-jpeg (as pinned via ocicl) can't decode progressive JPEGs. Convert with `magick in.jpg -interlace none out.jpg`.
- **Dependencies** (`tv2` → `tvision`, and `jpeg-sixel`) are sibling projects under `~/Projects/common-lisp/`, resolved via the global ASDF `:tree` source registry — no ocicl entry for the local systems. `tvision/` is an additional working dir for this session.
- Reactive slots (`index`, `help-p`) use `tv2:reactive-class`; mutating them forces a redraw. Use `show-image` / set `tv2::*dirty*` rather than redrawing by hand.
- This project reaches into `tv2::` / `tvision::` internals (`fill-row`, `draw-text`, `*dirty*`, `*running*`, `rect-width`, `screen-out`). That's expected for this seam demo.
- Keep the doc comments dense and explanatory as they are — they carry the design rationale.

#!/usr/bin/env python3
"""Reads what check-layers.sh recorded for one kitchen sink screen and says whether the
picture did what it should.

    layer-checks.py <check> <output-directory>

The numbers here (where things start, how far they go, when the script taps) belong with
KitchenSink/CheckScreens.swift and check-layers.sh. Exits 0 when every check holds.
"""

import csv
import re
import subprocess
import sys
from pathlib import Path

name, out = sys.argv[1], Path(sys.argv[2])
scale = 2
fps = 60
# check-layers.sh lifts the finger from the bar at the bottom at this frame.
tap_frame = 94

stats = {int(row["frame"]): row for row in csv.DictReader((out / "stats.csv").open())}
dumped = sorted(int(path.stem.split("-")[1]) for path in (out / "frames").glob("frame-*.png"))


def row_of_pixels(frame, y):
    """The pixels of the frame's row at `y` points, as (r, g, b) tuples, one per pixel."""
    path = out / "frames" / f"frame-{frame:06d}.png"
    width = int(subprocess.run(["magick", "identify", "-format", "%w", str(path)],
                               capture_output=True, text=True, check=True).stdout)
    raw = subprocess.run(["magick", str(path), "-crop", f"{width}x1+0+{int(y * scale)}", "+repage",
                          "-depth", "8", "rgb:-"], capture_output=True, check=True).stdout
    return [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]


def column_of_pixels(frame, x):
    path = out / "frames" / f"frame-{frame:06d}.png"
    height = int(subprocess.run(["magick", "identify", "-format", "%h", str(path)],
                                capture_output=True, text=True, check=True).stdout)
    raw = subprocess.run(["magick", str(path), "-crop", f"1x{height}+{int(x * scale)}+0", "+repage",
                          "-depth", "8", "rgb:-"], capture_output=True, check=True).stdout
    return [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]


def first(pixels, wanted):
    """Where the first pixel that `wanted` accepts is, in points. None when there is none."""
    for index, pixel in enumerate(pixels):
        if wanted(pixel):
            return index / scale
    return None


def extent(pixels, wanted):
    """How many points of the row or column `wanted` accepts."""
    return sum(1 for pixel in pixels if wanted(pixel)) / scale


def pixel(frame, x, y):
    return row_of_pixels(frame, y)[int(x * scale)]


def close(a, b, tolerance=12):
    return all(abs(p - q) <= tolerance for p, q in zip(a, b))


def is_red(p):
    return p[0] > 180 and p[1] < 90 and p[2] < 90


def is_blue(p):
    return p[2] > 180 and p[0] < 110 and p[1] < 110


def blocked_frames():
    """The dumped frames drawn while the app's main thread was blocked."""
    moments = {}
    for line in (out / "app.log").read_text().splitlines():
        found = re.search(r"\[(\d+\.\d+)\] (main thread blocked|main thread free again)", line)
        if found:
            moments[found.group(2)] = float(found.group(1))
    if len(moments) != 2:
        sys.exit("the app's log does not say when its main thread was blocked:\n" + (out / "app.log").read_text())
    start, end = moments["main thread blocked"], moments["main thread free again"]
    # A frame's margin either side: the last commit before the block is drawn just after it.
    margin = 1.5 / fps
    return [f for f in dumped if start + margin <= float(stats[f]["time"]) <= end - margin]


results = []


def check(what, ok, detail):
    results.append(ok)
    print(f"  {'ok  ' if ok else 'FAIL'} {what}: {detail}")


def steady(values, tolerance=0.5):
    """Never goes back by more than `tolerance`."""
    return all(b >= a - tolerance for a, b in zip(values, values[1:]))


def moves(values):
    return sum(1 for a, b in zip(values, values[1:]) if abs(b - a) > 0.25)


def sent_while(frames):
    return sum(int(stats[f]["operations"]) for f in range(frames[0], frames[-1] + 1))


if name == "delayed-move":
    # A red square at x = 20 that, half a second after the tap, takes half a second to reach
    # x = 310. The app is blocked from just after the tap until well after it should arrive.
    def x_at(frame):
        return first(row_of_pixels(frame, 130), is_red)

    blocked = blocked_frames()
    before = [f for f in dumped if f < tap_frame][-1]
    waiting = [f for f in dumped if tap_frame < f <= tap_frame + 0.4 * fps]
    xs = [x_at(f) for f in blocked]
    check("starts where it should", x_at(before) == 20, f"x = {x_at(before)} before the tap")
    check("waits for its delay", all(x_at(f) == 20 for f in waiting),
          f"still at x = 20 in the {len(waiting)} frames looked at up to 0.4 s after the tap")
    check("moves while the app is blocked", moves(xs) >= 10 and steady(xs),
          f"moved in {moves(xs)} of {len(xs) - 1} frames, never backwards")
    check("arrives while the app is blocked", xs[-1] == 310, f"x = {xs[-1]} when the block ends")
    check("the app sent nothing meanwhile", sent_while(blocked) == 0, f"{sent_while(blocked)} operations")

elif name == "moving-container":
    # A blue square at (20, 100) in a container that goes down 30 while the square goes right
    # 250 inside it. The container comes to rest first; the square must not start again.
    def place(frame):
        x = first(row_of_pixels(frame, 145), is_blue)
        y = first(column_of_pixels(frame, x + 30), is_blue) if x is not None else None
        return x, y

    blocked = blocked_frames()
    before = [f for f in dumped if f < tap_frame][-1]
    places = [place(f) for f in blocked]
    xs, ys = [p[0] for p in places], [p[1] for p in places]
    check("starts where it should", place(before) == (20, 100), f"at {place(before)} before the tap")
    check("goes right while the app is blocked", moves(xs) >= 10 and steady(xs),
          f"moved in {moves(xs)} of {len(xs) - 1} frames, never backwards")
    check("goes down with its container", moves(ys) >= 5 and steady(ys),
          f"moved in {moves(ys)} of {len(ys) - 1} frames, never backwards")
    check("arrives while the app is blocked", abs(xs[-1] - 270) <= 0.5 and abs(ys[-1] - 130) <= 0.5,
          f"at ({xs[-1]}, {ys[-1]}) when the block ends, to be at (270, 130)")
    check("the app sent nothing meanwhile", sent_while(blocked) == 0, f"{sent_while(blocked)} operations")

elif name == "scale-rotation":
    # A red square, 60 across and centred on (100, 140), that doubles; and a blue bar, 120 by
    # 20 and centred on (280, 140), that turns a quarter and so ends up standing.
    def width(frame):
        return extent(row_of_pixels(frame, 140), is_red)

    def height(frame):
        return extent(column_of_pixels(frame, 280), is_blue)

    blocked = blocked_frames()
    before = [f for f in dumped if f < tap_frame][-1]
    widths, heights = [width(f) for f in blocked], [height(f) for f in blocked]
    check("starts as it should", (width(before), height(before)) == (60, 20),
          f"the square is {width(before)} across and the bar {height(before)} high before the tap")
    check("the square grows while the app is blocked", moves(widths) >= 10 and steady(widths),
          f"grew in {moves(widths)} of {len(widths) - 1} frames, never shrinking")
    # The bar is as tall as it gets well before it stands: only its first steps show here.
    check("the bar turns while the app is blocked", moves(heights) >= 5 and steady(heights, 1),
          f"got taller in {moves(heights)} of {len(heights) - 1} frames")
    check("both arrive while the app is blocked", abs(widths[-1] - 120) <= 1 and abs(heights[-1] - 120) <= 1,
          f"the square is {widths[-1]} across and the bar {heights[-1]} high when the block ends, to be 120 and 120")
    check("the app sent nothing meanwhile", sent_while(blocked) == 0, f"{sent_while(blocked)} operations")

elif name == "repeating":
    # A red square that goes back and forth for ever between x = 20 and x = 310, a second
    # each way. Nothing is tapped but the bar, which only blocks the app.
    def x_at(frame):
        return first(row_of_pixels(frame, 130), is_red)

    blocked = blocked_frames()
    xs = [x_at(f) for f in blocked]
    turns = sum(1 for a, b, c in zip(xs, xs[1:], xs[2:]) if (b - a) * (c - b) < 0)
    idle = [f for f in dumped if tap_frame - 30 <= f < tap_frame - 2]
    check("goes on while the app is blocked", moves(xs) >= 0.8 * (len(xs) - 1),
          f"moved in {moves(xs)} of {len(xs) - 1} frames")
    check("goes there and back", turns >= 2 and min(xs) <= 25 and max(xs) >= 305,
          f"turned round {turns} times, between x = {min(xs)} and x = {max(xs)}")
    check("the app sends nothing while it runs", sent_while(idle) == 0 and sent_while(blocked) == 0,
          f"{sent_while(idle)} operations in the half second before the tap, {sent_while(blocked)} while blocked")

elif name == "emptied-scroll":
    # A list is scrolled, emptied and filled again; then a row is tapped at (195, 400). The
    # strip at the top takes the colour of the row the app thinks was tapped, which has to be
    # the colour that was on screen under the finger.
    row_tap = 360
    at_rest = [f for f in dumped if f < 90][-1]
    scrolled, refilled, last = [f for f in dumped if f < 270][-1], [f for f in dumped if f < row_tap][-1], dumped[-1]
    # The rows' colours come round again every 480 points; where this looks, the list at
    # rest and the list after the flick show different ones.
    top = pixel(at_rest, 195, 150)
    under_finger = pixel(refilled, 195, 400)
    strip_before, strip_after = pixel(refilled, 40, 30), pixel(last, 40, 30)
    emptied = [f for f in dumped if 270 <= f <= 295 and close(pixel(f, 195, 200), (255, 255, 255))]
    check("the list scrolled", not close(pixel(scrolled, 195, 150), top),
          f"the row near the top changed from {top} to {pixel(scrolled, 195, 150)}")
    check("the list was empty for a moment", len(emptied) > 0, f"in {len(emptied)} of the frames looked at")
    check("nothing was tapped before", close(strip_before, (255, 255, 255)), f"the strip is {strip_before}")
    check("the row under the finger is the row that was tapped", close(strip_after, under_finger),
          f"under the finger {under_finger}, the strip became {strip_after}")

else:
    sys.exit(f"no check called {name}")

sys.exit(0 if all(results) else 1)

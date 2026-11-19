# /// script
# requires-python = ">=3.10"
# dependencies = ["rich>=13"]
# ///
"""Renders a captured terminal screen (tmux capture-pane -e) as an SVG terminal window.

Every run of text is placed at its exact column (column x cell width), so tables line up whatever font the
renderer picks. rich parses the ANSI; the drawing is done here.

Usage: uv run scripts/ansi-to-image.py CAPTURE OUT.svg TITLE COLUMNS [STATUS_LEFT STATUS_RIGHT]
With the two status arguments, a tmux-style status line (black on green, tmux's default) is drawn under the pane.
"""
import sys
from html import escape

from rich.cells import cell_len
from rich.color import Color
from rich.style import Style
from rich.terminal_theme import MONOKAI
from rich.text import Text

THEME = MONOKAI
CELL_W, CELL_H, FONT = 9.0, 20.0, 15
PAD, BAR = 14, 34
FG = THEME.foreground_color.hex
BG = "#1e1f22"


def hexcolor(color: Color | None, default: str) -> str:
    if color is None or color.is_default:
        return default
    return color.get_truecolor(THEME).hex


def runs(text: Text):
    """Yield (column, string, style) runs for one line."""
    col = 0
    base = text.style if isinstance(text.style, Style) else Style.parse(text.style or "")
    for segment in text.render(_console):
        if not segment.text:
            continue
        yield col, segment.text, base + (segment.style or Style())
        col += cell_len(segment.text)


def main() -> None:
    capture, out, title, columns = sys.argv[1:5]
    width = int(columns)
    with open(capture, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().rstrip("\n").split("\n")
    texts = [Text.from_ansi(line) for line in lines]
    if len(sys.argv) >= 7:
        left, right = sys.argv[5], sys.argv[6]
        bar = left + " " * max(1, width - len(left) - len(right)) + right
        texts.append(Text(bar, style=Style(color="black", bgcolor="green")))

    w = PAD * 2 + width * CELL_W
    h = BAR + PAD * 2 + len(texts) * CELL_H
    out_parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" viewBox="0 0 {w:.0f} {h:.0f}">',
        f'<rect width="100%" height="100%" rx="10" fill="{BG}"/>',
        '<circle cx="20" cy="17" r="6" fill="#ff5f57"/><circle cx="40" cy="17" r="6" fill="#febc2e"/>'
        '<circle cx="60" cy="17" r="6" fill="#28c840"/>',
        f'<text x="{w / 2:.0f}" y="22" fill="#9da1a6" font-family="Helvetica, Arial, sans-serif" font-size="13" '
        f'text-anchor="middle">{escape(title)}</text>',
        f'<g font-family="Menlo, Monaco, \'DejaVu Sans Mono\', monospace" font-size="{FONT}" xml:space="preserve">',
    ]
    for row, text in enumerate(texts):
        top = BAR + PAD + row * CELL_H
        for col, s, style in runs(text):
            fg, bgc = hexcolor(style.color, FG), hexcolor(style.bgcolor, "")
            if style.reverse:
                fg, bgc = (bgc or BG), fg
            x = PAD + col * CELL_W
            if bgc:
                out_parts.append(f'<rect x="{x:.1f}" y="{top:.1f}" width="{cell_len(s) * CELL_W:.1f}" '
                                 f'height="{CELL_H}" fill="{bgc}"/>')
            if s.strip():
                attrs = f'fill="{fg}"'
                if style.bold:
                    attrs += ' font-weight="bold"'
                if style.underline:
                    attrs += ' text-decoration="underline"'
                if style.dim:
                    attrs += ' opacity="0.6"'
                # One tspan per cell keeps every glyph on its column even when the font's advance differs.
                cells, c = [], col
                for ch in s:
                    cells.append(f'<tspan x="{PAD + c * CELL_W:.1f}">{escape(ch)}</tspan>' if ch != " " else "")
                    c += cell_len(ch)
                out_parts.append(f'<text y="{top + CELL_H * 0.75:.1f}" {attrs}>{"".join(cells)}</text>')
    out_parts.append("</g></svg>")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out_parts))


if __name__ == "__main__":
    from rich.console import Console

    _console = Console(width=10_000, force_terminal=True, color_system="truecolor")
    main()

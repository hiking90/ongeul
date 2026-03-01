#!/usr/bin/env python3
"""Generate SVG keyboard layout diagrams from JSON5 layout files.

Usage:
    python scripts/gen_layout_svg.py

Reads layout files from ongeul-automata/layouts/ and writes SVG files
to docs/src/user/features/.
"""

import json
import re
from pathlib import Path

# ── Physical keyboard rows (US ANSI QWERTY, character keys only) ──
ROWS = [
    list("`1234567890-="),
    list("qwertyuiop[]\\"),
    list("asdfghjkl;'"),
    list("zxcvbnm,./"),
]
# Row x-offsets in key-units (simulating Tab/Caps/Shift widths)
ROW_OFFSETS = [0, 1.5, 1.75, 2.25]

# Shifted symbol → physical key
SHIFT_MAP = {
    "~": "`", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
    "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-",
    "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", '"': "'",
    "<": ",", ">": ".", "?": "/",
}

# ── Positional jamo → compatibility jamo ──
TO_COMPAT = {
    # 초성 (U+1100–U+1112)
    0x1100: 0x3131, 0x1101: 0x3132, 0x1102: 0x3134, 0x1103: 0x3137,
    0x1104: 0x3138, 0x1105: 0x3139, 0x1106: 0x3141, 0x1107: 0x3142,
    0x1108: 0x3143, 0x1109: 0x3145, 0x110A: 0x3146, 0x110B: 0x3147,
    0x110C: 0x3148, 0x110D: 0x3149, 0x110E: 0x314A, 0x110F: 0x314B,
    0x1110: 0x314C, 0x1111: 0x314D, 0x1112: 0x314E,
    # 중성 (U+1161–U+1175)
    0x1161: 0x314F, 0x1162: 0x3150, 0x1163: 0x3151, 0x1164: 0x3152,
    0x1165: 0x3153, 0x1166: 0x3154, 0x1167: 0x3155, 0x1168: 0x3156,
    0x1169: 0x3157, 0x116A: 0x3158, 0x116B: 0x3159, 0x116C: 0x315A,
    0x116D: 0x315B, 0x116E: 0x315C, 0x116F: 0x315D, 0x1170: 0x315E,
    0x1171: 0x315F, 0x1172: 0x3160, 0x1173: 0x3161, 0x1174: 0x3162,
    0x1175: 0x3163,
    # 종성 (U+11A8–U+11C2)
    0x11A8: 0x3131, 0x11A9: 0x3132, 0x11AA: 0x3133, 0x11AB: 0x3134,
    0x11AC: 0x3135, 0x11AD: 0x3136, 0x11AE: 0x3137, 0x11AF: 0x3139,
    0x11B0: 0x313A, 0x11B1: 0x313B, 0x11B2: 0x313C, 0x11B3: 0x313D,
    0x11B4: 0x313E, 0x11B5: 0x313F, 0x11B6: 0x3140, 0x11B7: 0x3141,
    0x11B8: 0x3142, 0x11B9: 0x3144, 0x11BA: 0x3145, 0x11BB: 0x3146,
    0x11BC: 0x3147, 0x11BD: 0x3148, 0x11BE: 0x314A, 0x11BF: 0x314B,
    0x11C0: 0x314C, 0x11C1: 0x314D, 0x11C2: 0x314E,
}

# ── Color scheme: (fill, stroke) ──
COLORS = {
    "consonant": ("#DBEAFE", "#93C5FD"),
    "vowel":     ("#FEF3C7", "#FCD34D"),
    "initial":   ("#DBEAFE", "#93C5FD"),
    "medial":    ("#D1FAE5", "#6EE7B7"),
    "final":     ("#FEF3C7", "#FCD34D"),
    "symbol":    ("#F3F4F6", "#D1D5DB"),
    "empty":     ("#F9FAFB", "#E5E7EB"),
}

LEGEND = {
    "jamo": [("consonant", "자음"), ("vowel", "모음")],
    "jaso": [("initial", "초성"), ("medial", "중성"), ("final", "종성")],
}


def parse_json5(text):
    """Minimal JSON5 parser: strip comments, trailing commas, quote keys."""
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    text = re.sub(r'(?<=[{,\n])\s*(\w+)\s*:', r' "\1":', text)
    return json.loads(text)


def key_to_physical(ch):
    """Map a JSON5 key identifier to (physical_key_id, is_shift)."""
    if "a" <= ch <= "z":
        return (ch, False)
    if "A" <= ch <= "Z":
        return (ch.lower(), True)
    if ch in "0123456789":
        return (ch, False)
    if ch in SHIFT_MAP:
        return (SHIFT_MAP[ch], True)
    for row in ROWS:
        if ch in row:
            return (ch, False)
    return None


def classify(cp, ltype):
    """Classify a codepoint by jamo category."""
    if ltype == "jamo":
        if 0x3131 <= cp <= 0x314E:
            return "consonant"
        if 0x314F <= cp <= 0x3163:
            return "vowel"
    else:
        if 0x1100 <= cp <= 0x1112:
            return "initial"
        if 0x1161 <= cp <= 0x1175:
            return "medial"
        if 0x11A8 <= cp <= 0x11C2:
            return "final"
    return "symbol"


def display_char(cp):
    """Convert codepoint to displayable character (positional → compat jamo)."""
    return chr(TO_COMPAT.get(cp, cp))


def esc(s):
    """Escape XML special characters."""
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def generate_svg(layout_path, output_path):
    """Generate an SVG keyboard diagram from a JSON5 layout file."""
    layout = parse_json5(Path(layout_path).read_text("utf-8"))
    ltype = layout["type"]
    keymap = layout["keymap"]

    # Build per-physical-key data
    keys = {}
    for k, v in keymap.items():
        result = key_to_physical(k)
        if not result:
            continue
        phys, is_shift = result
        cp = int(v, 16)
        cat = classify(cp, ltype)
        disp = display_char(cp)
        keys.setdefault(phys, {})
        keys[phys]["shift" if is_shift else "normal"] = (disp, cat)

    # Dimensions
    KW, KH, GAP = 44, 44, 4
    U = KW + GAP
    PAD = 12

    max_x = max((ROW_OFFSETS[i] + len(ROWS[i])) * U for i in range(4))
    W = max_x + PAD * 2
    LEGEND_H = 36
    H = 4 * U + PAD * 2 + LEGEND_H

    svg = []
    svg.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}"'
        f" style=\"font-family: -apple-system, 'Noto Sans KR', sans-serif;\">"
    )

    # Keys
    for ri, row in enumerate(ROWS):
        for ci, kid in enumerate(row):
            x = PAD + (ROW_OFFSETS[ri] + ci) * U
            y = PAD + ri * U

            data = keys.get(kid, {})
            norm = data.get("normal")
            shft = data.get("shift")
            cat = (norm or shft or (None, "empty"))[1]
            fill, stroke = COLORS[cat]

            svg.append(
                f'<rect x="{x}" y="{y}" width="{KW}" height="{KH}" '
                f'rx="5" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>'
            )

            # QWERTY label (top-right, subtle)
            label = kid.upper() if kid.isalpha() else kid
            svg.append(
                f'<text x="{x + KW - 5}" y="{y + 12}" text-anchor="end" '
                f'font-size="9" fill="#B0B0B0">{esc(label)}</text>'
            )

            # Shift character (top-left)
            if shft:
                svg.append(
                    f'<text x="{x + 6}" y="{y + 14}" font-size="11" '
                    f'fill="#374151">{esc(shft[0])}</text>'
                )

            # Normal character (bottom-center)
            if norm:
                svg.append(
                    f'<text x="{x + KW / 2}" y="{y + 36}" text-anchor="middle" '
                    f'font-size="16" font-weight="500" fill="#111827">'
                    f"{esc(norm[0])}</text>"
                )

    # Legend
    items = LEGEND[ltype]
    item_w = 100
    lx = (W - len(items) * item_w) / 2
    ly = PAD + 4 * U + 12

    for i, (cat, label) in enumerate(items):
        ix = lx + i * item_w
        fill, stroke = COLORS[cat]
        svg.append(
            f'<rect x="{ix}" y="{ly}" width="16" height="16" rx="3" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="1"/>'
        )
        svg.append(
            f'<text x="{ix + 22}" y="{ly + 13}" font-size="13" '
            f'fill="#4B5563">{label}</text>'
        )

    svg.append("</svg>")

    Path(output_path).write_text("\n".join(svg), "utf-8")
    print(f"  Generated: {output_path}")


def main():
    base = Path(__file__).resolve().parent.parent
    layouts_dir = base / "ongeul-automata" / "layouts"
    output_dir = base / "docs" / "src" / "user" / "features"

    for name in ["2-standard", "3-390", "3-final"]:
        generate_svg(layouts_dir / f"{name}.json5", output_dir / f"{name}.svg")


if __name__ == "__main__":
    main()

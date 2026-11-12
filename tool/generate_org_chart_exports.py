"""Render the association org chart to SVG, PNG and DOCX.

Source of truth for boxes: docs/diagrams/org-chart.drawio
Outputs:
  docs/diagrams/org-chart.svg
  docs/diagrams/org-chart.png  (embedded into the docx)
  docs/diagrams/org-chart.docx
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "diagrams"

BOXES = [
    ("ASSOCIATION EXECUTIVE LEADERSHIP",
     ["President / Founding Head: Mercedita Apura",
      "Subsequent President / Owner (Jebiley): Algerico Gerry Sandoy",
      "Vice Chairman: Samuel Lauron"]),
    ("ASSOCIATION ADMINISTRATIVE STAFF",
     ["Secretary: Jocelyn Yap",
      "Treasurer: Timoteo Canape",
      "Auditor: Ruth del Rosario"]),
    ("DETASIE SHOE FACTORY", ["Owner: Mercedita Apura"]),
    ("JEBILEY SHOES MANUFACTURER", ["Owner: Gerry Sandoy"]),
    ("SAMMY SHOE", ["Owner: Samuel Lauron"]),
    ("KHOFEET COLLECTION", ["Independent Management"]),
    ("LIRUS SHOE COMPANY", []),
    ("LIDABETH SHOES", []),
    ("KEVIN'S COLLECTION", []),
    ("JRE FOOTWEAR", []),
    ("FOOT FIT", []),
    ("MIL DIM CREATIONS", []),
    ("TRADITIONAL WORKSHOP TRADES & ARTISANS",
     ["(Standard Production Floor Layout Inside Each Factory)",
      "Owner / Master Artisan (Pattern cutting, oversight)",
      "Entradista (Pattern fitting, lasting, upper assembly)",
      "Manglagdok (Sole stitching, welting, bonding)"]),
]


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_svg() -> str:
    W, H = 827, 1100
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<rect x="0" y="0" width="{W}" height="{H}" fill="#FFFFFF"/>',
    ]
    # geometry mirrors org-chart.drawio, single centred column + two branches
    layout = [
        (113, 20, 600, 110), (113, 170, 600, 100),
        (60, 330, 300, 70), (466, 330, 300, 70),
        (60, 450, 300, 70), (466, 450, 300, 70),
        (60, 570, 300, 60), (466, 570, 300, 60),
        (60, 680, 300, 60), (466, 680, 300, 60),
        (60, 790, 300, 60), (466, 790, 300, 60),
        (113, 910, 600, 150),
    ]
    edges = [(0, 1), (1, 2), (1, 3), (2, 4), (3, 5), (4, 6), (5, 7),
              (6, 8), (7, 9), (8, 10), (9, 11), (10, 12), (11, 12)]
    for a, b in edges:
        x1 = layout[a][0] + layout[a][2] // 2
        y1 = layout[a][1] + layout[a][3]
        x2 = layout[b][0] + layout[b][2] // 2
        y2 = layout[b][1]
        parts.append(
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#000000" stroke-width="2"/>'
            f'<polygon points="{x2 - 6},{y2 - 10} {x2 + 6},{y2 - 10} {x2},{y2}" fill="#000000"/>'
        )
    for i, (x, y, w, h) in enumerate(layout):
        title, subs = BOXES[i]
        parts.append(
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#FFFFFF" stroke="#000000" stroke-width="2"/>')
        parts.append(
            f'<text x="{x + w // 2}" y="{y + 26}" text-anchor="middle" font-family="Arial" font-size="14" font-weight="bold" fill="#000000">{esc(title)}</text>')
        for j, s in enumerate(subs):
            parts.append(
                f'<text x="{x + w // 2}" y="{y + 46 + j * 18}" text-anchor="middle" font-family="Arial" font-size="12" fill="#000000">{esc(s)}</text>')
    parts.append("</svg>")
    return "\n".join(parts)


def build_png(png_path: Path) -> None:
    W, H, S = 827, 1100, 2  # 2x for crisp word embedding
    img = Image.new("RGB", (W * S, H * S), "white")
    d = ImageDraw.Draw(img)
    try:
        fb = ImageFont.truetype("arialbd.ttf", 14 * S)
        fr = ImageFont.truetype("arial.ttf", 12 * S)
    except OSError:
        fb = fr = ImageFont.load_default()
    layout = [
        (113, 20, 600, 110), (113, 170, 600, 100),
        (60, 330, 300, 70), (466, 330, 300, 70),
        (60, 450, 300, 70), (466, 450, 300, 70),
        (60, 570, 300, 60), (466, 570, 300, 60),
        (60, 680, 300, 60), (466, 680, 300, 60),
        (60, 790, 300, 60), (466, 790, 300, 60),
        (113, 910, 600, 150),
    ]
    edges = [(0, 1), (1, 2), (1, 3), (2, 4), (3, 5), (4, 6), (5, 7),
              (6, 8), (7, 9), (8, 10), (9, 11), (10, 12), (11, 12)]
    for a, b in edges:
        x1 = (layout[a][0] + layout[a][2] // 2) * S
        y1 = (layout[a][1] + layout[a][3]) * S
        x2 = (layout[b][0] + layout[b][2] // 2) * S
        y2 = layout[b][1] * S
        d.line([x1, y1, x2, y2], fill="black", width=2 * S)
        d.polygon([x2 - 6 * S, y2 - 10 * S, x2 + 6 * S, y2 - 10 * S, x2, y2], fill="black")
    for i, (x, y, w, h) in enumerate(layout):
        title, subs = BOXES[i]
        d.rectangle([x * S, y * S, (x + w) * S, (y + h) * S], outline="black", width=2 * S)
        d.text((W * S // 2 if w == 600 else (x + w // 2) * S, (y + 8) * S),
               title, font=fb, fill="black", anchor="ma")
        for j, s in enumerate(subs):
            d.text((W * S // 2 if w == 600 else (x + w // 2) * S, (y + 26 + j * 15) * S),
                   s, font=fr, fill="black", anchor="ma")
    img.save(png_path)


def build_docx(png_path: Path, docx_path: Path) -> None:
    doc = Document()
    for s in doc.sections:
        s.top_margin = Inches(0.6)
        s.bottom_margin = Inches(0.6)
    t = doc.add_heading("Association Organizational Chart", level=1)
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run("Shoe Association — Executive Leadership, Administrative Staff, Member Factories, and Workshop Trades").font.size = Pt(11)
    pic = doc.add_paragraph()
    pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pic.add_run().add_picture(str(png_path), width=Inches(6.5))
    doc.add_heading("Structure (text version)", level=2)
    for title, subs in BOXES:
        b = doc.add_paragraph(style="List Bullet")
        r = b.add_run(title)
        r.bold = True
        for s in subs:
            doc.add_paragraph(s, style="List Bullet 2")
    doc.add_paragraph("Source: docs/diagrams/org-chart.drawio (open in draw.io / app.diagrams.net to edit).").italic = True
    doc.save(docx_path)


def main() -> None:
    svg_path, png_path, docx_path = OUT / "org-chart.svg", OUT / "org-chart.png", OUT / "org-chart.docx"
    svg_path.write_text(build_svg(), encoding="utf-8")
    print(f"wrote {svg_path}")
    build_png(png_path)
    print(f"wrote {png_path}")
    build_docx(png_path, docx_path)
    print(f"wrote {docx_path}")


if __name__ == "__main__":
    main()

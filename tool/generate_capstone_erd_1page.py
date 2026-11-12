"""One-page condensed ERD for the capstone paper, in the exact visual language
of the 7-page reference (docs/diagrams/capstone paper/ERd/database-erd.drawio).

Usage: python tool/generate_capstone_erd_1page.py
Writes docs/diagrams/capstone paper/ERd/CUFMAI-ERD-Capstone-1page.drawio
A4 PORTRAIT, 12 core entities, every FK has its own crow-foot connector.
Lines are routed through gutter/channel waypoints so they never cross tables.
"""
import html
import pathlib
import re as _re

OUT = pathlib.Path("docs/diagrams/capstone paper/ERd/CUFMAI-ERD-Capstone-1page.drawio")

TABLES = [
    ("stores", 15, 110, [
        ("id", "UUID", "PK"), ("owner_id", "UUID", "FK->profiles"),
        ("name", "TEXT", ""), ("location", "TEXT", ""),
        ("is_active", "BOOL", ""), ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("profiles", 285, 110, [
        ("id", "UUID", "PK"), ("full_name", "TEXT", ""),
        ("email", "TEXT", "UQ"), ("role", "ENUM", ""),
        ("seller_status", "ENUM", ""), ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("products", 555, 110, [
        ("id", "UUID", "PK"), ("store_id", "UUID", "FK->stores"),
        ("seller_id", "UUID", "FK->profiles"), ("name", "TEXT", ""),
        ("price", "NUMERIC", ""), ("is_active", "BOOL", ""),
    ]),
    ("cart_items", 15, 380, [
        ("id", "UUID", "PK"), ("user_id", "UUID", "FK->profiles"),
        ("product_id", "UUID", "FK->products"), ("quantity", "INT", ""),
    ]),
    ("orders", 285, 380, [
        ("id", "UUID", "PK"), ("customer_id", "UUID", "FK->profiles"),
        ("store_id", "UUID", "FK->stores"), ("status", "ENUM", ""),
        ("total_amount", "NUMERIC", ""), ("payment_status", "ENUM", ""),
    ]),
    ("product_variants", 555, 380, [
        ("id", "UUID", "PK"), ("product_id", "UUID", "FK->products"),
        ("size", "TEXT", ""), ("color", "TEXT", ""), ("stock", "INT", ""),
    ]),
    ("vouchers", 15, 650, [
        ("id", "UUID", "PK"), ("code", "TEXT", "UQ"),
        ("discount", "NUMERIC", ""), ("created_by", "UUID", "FK->profiles"),
    ]),
    ("order_items", 285, 650, [
        ("id", "UUID", "PK"), ("order_id", "UUID", "FK->orders"),
        ("product_id", "UUID", "FK->products"), ("quantity", "INT", ""),
        ("unit_price", "NUMERIC", ""),
    ]),
    ("payment_intents", 555, 650, [
        ("id", "UUID", "PK"), ("order_id", "UUID", "FK->orders"),
        ("amount", "NUMERIC", ""), ("status", "TEXT", ""),
        ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("conversations", 15, 920, [
        ("id", "UUID", "PK"), ("store_id", "UUID", "FK->stores"),
        ("customer_id", "UUID", "FK->profiles"),
        ("last_message_at", "TIMESTAMPTZ", ""),
    ]),
    ("messages", 285, 920, [
        ("id", "UUID", "PK"),
        ("conversation_id", "UUID", "FK->conversations"),
        ("sender_id", "UUID", "FK->profiles"), ("is_read", "BOOL", ""),
    ]),
    ("reviews", 555, 920, [
        ("id", "BIGINT", "PK"), ("product_id", "UUID", "FK->products"),
        ("customer_id", "UUID", "FK->profiles"),
        ("order_id", "UUID", "FK->orders"), ("rating", "INT 1-5", ""),
    ]),
]

# Gutters/channels: L=10/15/20 left gutter, G12=282, G23=547, R=805/815 right
# TOP=90 top channel, C01=320, C12=590, C23=860
EDGES = [
    ("stores", "profiles", (1, 0.5), (0, 0.5), []),
    ("products", "stores", (0.5, 0), (0.5, 0), [(680, 90), (140, 90)]),
    ("products", "profiles", (0.15, 0), (0.85, 0), [(592, 90), (497, 90)]),
    ("product_variants", "products", (0.5, 0), (0.5, 1), []),
    ("cart_items", "profiles", (0.5, 0), (0.2, 1), [(140, 320), (335, 320)]),
    ("cart_items", "products", (1, 0.3), (0.5, 0), [(275, 413), (275, 90), (680, 90)]),
    ("order_items", "orders", (0.5, 0), (0.5, 1), []),
    ("orders", "profiles", (0.5, 0), (0.5, 1), []),
    ("orders", "stores", (0, 0.5), (0.5, 1), [(275, 455), (275, 320), (140, 320)]),
    ("order_items", "products", (1, 0.4), (0, 0.55), [(545, 702), (545, 192)]),
    ("payment_intents", "orders", (0, 0.5), (1, 0.5), [(545, 715), (545, 455)]),
    ("vouchers", "profiles", (0, 0.5), (0.4, 0), [(8, 705), (8, 90), (385, 90)]),
    ("reviews", "products", (1, 0.5), (1, 0.5), [(810, 985), (810, 185)]),
    ("reviews", "orders", (0, 0.4), (0.9, 1), [(545, 972), (545, 590), (510, 590)]),
    ("conversations", "stores", (1, 0.3), (0.2, 1), [(275, 953), (275, 340), (65, 340)]),
    ("conversations", "profiles", (0, 0.5), (0.2, 0), [(5, 975), (5, 90), (335, 90)]),
    ("messages", "conversations", (0, 0.5), (1, 0.5), []),
    ("messages", "profiles", (1, 0.5), (0.65, 0), [(545, 975), (545, 90), (447, 90)]),
    ("reviews", "profiles", (0.5, 0), (0.9, 0), [(680, 860), (820, 860), (820, 90), (510, 90)]),
]

ROW_H = 20
HEADER_H = 30
TABLE_W = 250

PK_IMG = ("<img width='13' height='13' style='vertical-align:-2px' "
          "src='data:image/svg+xml,"
          "<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2214%22 height=%2214%22 viewBox=%220 0 24 24%22>"
          "<g fill=%22none%22 stroke=%22%23FF0000%22 stroke-width=%222.6%22 stroke-linecap=%22round%22>"
          "<circle cx=%228%22 cy=%228%22 r=%224.6%22/>"
          "<path d=%22M11.5 11.5 20 20%22/>"
          "<path d=%22M16.6 16.6l2.5-2.5%22/>"
          "<path d=%22M13.9 19.3l2.5-2.5%22/>"
          "</g></svg>'>")


def esc(s):
    return html.escape(s, quote=False)


cells = []
pk_row = {}
for (name, x, y, cols) in TABLES:
    h = HEADER_H + len(cols) * ROW_H
    cells.append(
        f'<mxCell id="t-{name}" value="{esc(name)}" '
        f'style="swimlane;fontStyle=1;align=center;verticalAlign=top;childLayout=stackLayout;horizontal=1;startSize=26;horizontalStack=0;resizeParent=1;resizeParentMax=0;'
        f'resizeLast=0;collapsible=1;marginBottom=0;fillColor=none;fontColor=light-dark(#000000,#FFFFFF);strokeColor=light-dark(#000000,#FFFFFF);" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{TABLE_W}" height="{h}" as="geometry"/></mxCell>'
    )
    for i, (col, typ, keys) in enumerate(cols):
        is_pk = "PK" in keys
        m = _re.search(r"FK->([a-z_\.]+)", keys)
        fk = m.group(1).split(".")[-1] if m else None
        if is_pk and name not in pk_row:
            pk_row[name] = i
        if is_pk:
            label = f"{PK_IMG} {col} : {typ} [PK]"
        elif fk:
            label = f"\U0001f511\ufe0e {col} : {typ} [FK\u2192{fk}]"
        elif keys:
            label = f"{col} : {typ} [{keys}]"
        else:
            label = f"{col} : {typ}"
        extra = "fontStyle=1;html=1;" if is_pk else ""
        cells.append(
            f'<mxCell id="t-{name}-r{i}" value="{esc(label)}" '
            f'style="text;strokeColor=none;fillColor=none;fontColor=light-dark(#000000,#FFFFFF);align=left;verticalAlign=middle;'
            f'spacingLeft=6;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;{extra}" vertex="1" parent="t-{name}">'
            f'<mxGeometry y="{HEADER_H + i * ROW_H}" width="{TABLE_W}" height="{ROW_H}" as="geometry"/></mxCell>'
        )

cols_of = {t[0]: t[3] for t in TABLES}


def fk_col(src, tgt):
    for (col, _typ, keys) in cols_of[src]:
        m = _re.search(r"FK->([a-z_\.]+)", keys)
        if m and m.group(1).split(".")[-1] == tgt:
            return col
    return "id"


for eid, (src, tgt, ex, en, pts) in enumerate(EDGES):
    col = fk_col(src, tgt)
    th = pk_row.get(tgt, 0)
    pts_xml = "".join(f'<mxPoint x="{px}" y="{py}"/>' for px, py in pts)
    cells.append(
        f'<mxCell id="e{eid}" edge="1" parent="1" source="t-{src}" target="t-{tgt}-r{th}" value="{esc(col)}" '
        f'style="endArrow=ERmany;startArrow=ERone;html=1;rounded=1;strokeColor=light-dark(#000000,#FFFFFF);fontColor=light-dark(#000000,#FFFFFF);'
        f'labelBackgroundColor=none;edgeStyle=orthogonalEdgeStyle;jettySize=auto;orthogonalLoop=1;'
        f'exitX={ex[0]};exitY={ex[1]};exitDx=0;exitDy=0;entryX={en[0]};entryY={en[1]};entryDx=0;entryDy=0;fontSize=9;">'
        f'<mxGeometry relative="1" as="geometry"><Array as="points">{pts_xml}</Array></mxGeometry></mxCell>'
    )

out = ['<?xml version="1.0" encoding="UTF-8"?>',
       '<mxfile host="Electron" agent="SoleVision ERD generator">',
       '  <diagram id="p1" name="ERD - 1 page (Capstone)">',
       '    <mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">',
       '      <root>',
       '        <mxCell id="0"/>',
       '        <mxCell id="1" parent="0"/>',
       '        <mxCell id="title-0" parent="1" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;fontSize=18;fontStyle=1;" value="CUFMAI Database - ERD (Condensed for Paper, 1 page)" vertex="1">'
       '<mxGeometry x="30" y="20" width="700" height="30" as="geometry"/></mxCell>',
       '        <mxCell id="legend-0" parent="1" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;fontSize=10;" value="ERD legend:  [key] = key column (red key icon = primary key [PK] bold,  plain key = foreign key [FK-&gt;table]),  line 1--crowfoot = one-to-many.  Full 57-table reference: docs/diagrams/database-erd.drawio (7 subject-area pages)." vertex="1">'
       '<mxGeometry x="30" y="50" width="760" height="30" as="geometry"/></mxCell>']
out += [f'        {c}' for c in cells]
out += ['      </root>', '    </mxGraphModel>', '  </diagram>', '</mxfile>']

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(out), encoding="utf-8")
print(f"Wrote {OUT} ({len(TABLES)} tables, {len(EDGES)} relations, portrait)")

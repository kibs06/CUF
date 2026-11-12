"""Generate docs/diagrams/database-erd.drawio from the Supabase migrations.

Usage: python tool/generate_database_erd.py
Reads table/column definitions below (distilled from
supabase/migrations/*.sql with supabase/schema.sql as reference)
and writes a multi-page draw.io ERD using entity-relation shapes.

Source of truth for the live DB is always supabase/migrations/.
ID-type note: live DB uses UUID for products.id / orders.id /
order_items.id (see 20260601000000_base_schema.sql header) even
though the schema.sql snapshot still shows TEXT/BIGINT drift.
"""
import html
import pathlib
import re as _re

OUT = pathlib.Path("docs/diagrams/database-erd.drawio")

# (name, domain, [(col, type, keys)])  keys: PK, FK->table, UQ
# Keep the most-used columns per table so the diagram stays readable.
TABLES = [
    ("profiles", "Identity", [
        ("id", "UUID", "PK, FK\u2192auth.users"),
        ("full_name", "TEXT", ""),
        ("email", "TEXT", "UQ"),
        ("phone", "TEXT", ""),
        ("role", "TEXT", "customer|seller|admin"),
        ("seller_status", "TEXT", "none|pending|approved|rejected"),
        ("avatar_url", "TEXT", ""),
        ("suspended", "BOOL", ""),
        ("store_name", "TEXT", ""),
        ("store_tags", "TEXT[]", ""),
        ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("customer_addresses", "Identity", [
        ("id", "UUID", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("label", "TEXT", ""),
        ("recipient_name", "TEXT", ""),
        ("city_municipality", "TEXT", ""),
        ("barangay", "TEXT", ""),
        ("latitude", "FLOAT8", ""),
        ("longitude", "FLOAT8", ""),
        ("is_default", "BOOL", ""),
    ]),
    ("trusted_devices", "Identity", [
        ("user_id", "UUID", "PK, FK\u2192profiles"),
        ("device_id", "TEXT", "PK"),
        ("device_label", "TEXT", ""),
        ("trusted_at", "TIMESTAMPTZ", ""),
    ]),
    ("device_secrets", "Identity", [
        ("user_id", "UUID", "PK, FK\u2192trusted_devices"),
        ("device_id", "TEXT", "PK"),
        ("secret_hash", "BYTEA", ""),
        ("minted_at", "TIMESTAMPTZ", ""),
    ]),
    ("device_enforcement_policy", "Identity", [
        ("id", "BOOL", "PK"),
        ("enforcement_enabled", "BOOL", ""),
        ("updated_by", "UUID", "FK\u2192profiles"),
    ]),
    ("failed_logins", "Identity", [
        ("id", "BIGINT", "PK"),
        ("email", "TEXT", ""),
        ("ip", "TEXT", ""),
        ("attempt_count", "INT", ""),
        ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("account_session_log", "Identity", [
        ("id", "UUID", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("event", "TEXT", "sign_in|sign_out"),
        ("role", "TEXT", ""),
        ("source", "TEXT", ""),
    ]),
    ("deletion_requests", "Identity", [
        ("id", "BIGINT", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("status", "TEXT", ""),
        ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("stores", "Catalog", [
        ("id", "UUID", "PK"),
        ("name", "TEXT", ""),
        ("location", "TEXT", ""),
        ("brand_color", "TEXT", ""),
        ("banner_url", "TEXT", ""),
        ("logo_url", "TEXT", ""),
        ("rating", "NUMERIC", ""),
        ("is_open", "BOOL", ""),
        ("is_active", "BOOL", ""),
        ("owner_id", "UUID", "FK\u2192profiles"),
    ]),
    ("store_follows", "Catalog", [
        ("user_id", "UUID", "PK, FK\u2192profiles"),
        ("store_id", "UUID", "PK, FK\u2192stores"),
    ]),
    ("story_entries", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("title", "TEXT", ""),
        ("display_order", "INT", ""),
    ]),
    ("products", "Catalog", [
        ("id", "UUID", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("seller_id", "UUID", "FK\u2192profiles"),
        ("name", "TEXT", ""),
        ("price", "NUMERIC", ""),
        ("category", "TEXT", ""),
        ("sale_price", "NUMERIC", ""),
        ("avg_rating", "NUMERIC", ""),
        ("review_count", "INT", ""),
        ("is_active", "BOOL", ""),
    ]),
    ("product_images", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("image_url", "TEXT", ""),
        ("is_primary", "BOOL", ""),
    ]),
    ("product_variants", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("size", "TEXT", ""),
        ("color", "TEXT", ""),
        ("stock", "INT", ""),
    ]),
    ("product_customizations", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("option_name", "TEXT", ""),
        ("option_type", "TEXT", ""),
    ]),
    ("product_color_images", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("color", "TEXT", ""),
        ("image_url", "TEXT", ""),
    ]),
    ("inventory", "Catalog", [
        ("product_id", "UUID", "PK, FK\u2192products"),
        ("size", "TEXT", "PK"),
        ("stock", "INT", ""),
    ]),
    ("product_models", "Catalog", [
        ("id", "UUID", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("model_url", "TEXT", ""),
        ("is_active", "BOOL", ""),
    ]),
    ("product_ar_effects", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("effect_id", "TEXT", ""),
    ]),
    ("store_reviews", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("rating", "INT 1-5", ""),
    ]),
    ("banners", "Catalog", [
        ("id", "BIGINT", "PK"),
        ("title", "TEXT", ""),
        ("image_url", "TEXT", ""),
        ("is_active", "BOOL", ""),
    ]),
    ("orders", "Orders", [
        ("id", "UUID", "PK"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("status", "TEXT", "placed|preparing|ready|received|cancelled|pending"),
        ("total_amount", "NUMERIC", ""),
        ("payment_method", "TEXT", ""),
        ("payment_status", "TEXT", "paid|unpaid|pending"),
        ("fulfillment", "TEXT", "pickup|delivery"),
        ("shipping_address", "JSONB", ""),
    ]),
    ("order_items", "Orders", [
        ("id", "UUID", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("product_id", "UUID", "FK\u2192products"),
        ("size", "TEXT", ""),
        ("quantity", "INT", ""),
        ("unit_price", "NUMERIC", ""),
    ]),
    ("order_status_history", "Orders", [
        ("id", "BIGINT", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("status", "TEXT", ""),
        ("created_at", "TIMESTAMPTZ", ""),
    ]),
    ("cart_items", "Orders", [
        ("id", "UUID", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("product_id", "UUID", "FK\u2192products"),
        ("variant_id", "BIGINT", "FK\u2192product_variants"),
        ("quantity", "INT", ""),
    ]),
    ("pickup_reservations", "Orders", [
        ("id", "UUID", "PK"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("product_id", "UUID", "FK\u2192products"),
        ("status", "TEXT", ""),
        ("pickup_code", "TEXT", ""),
        ("fulfilled_order_id", "UUID", "FK\u2192orders"),
    ]),
    ("pickup_reservation_extension_grants", "Orders", [
        ("id", "BIGINT", "PK"),
        ("reservation_id", "UUID", "FK\u2192pickup_reservations"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("granted_by", "UUID", "FK\u2192profiles"),
    ]),
    ("bulk_reservations", "Orders", [
        ("id", "UUID", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("product_id", "UUID", "FK\u2192products"),
        ("status", "TEXT", ""),
    ]),
    ("bulk_reservation_deposits", "Orders", [
        ("id", "BIGINT", "PK"),
        ("bulk_reservation_id", "UUID", "FK\u2192bulk_reservations"),
        ("amount", "NUMERIC", ""),
        ("submitted_by", "UUID", "FK\u2192profiles"),
    ]),
    ("customization_requests", "Orders", [
        ("id", "BIGINT", "PK"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("base_product_id", "UUID", "FK\u2192products"),
        ("status", "TEXT", ""),
    ]),
    ("sales_transactions", "Payments", [
        ("id", "BIGINT", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("seller_id", "UUID", "FK\u2192profiles"),
        ("total_amount", "NUMERIC", ""),
        ("payment_method", "TEXT", ""),
    ]),
    ("sales_transaction_items", "Payments", [
        ("id", "BIGINT", "PK"),
        ("transaction_id", "BIGINT", "FK\u2192sales_transactions"),
        ("product_id", "UUID", "FK\u2192products"),
        ("quantity", "INT", ""),
        ("unit_price", "NUMERIC", ""),
    ]),
    ("payment_intents", "Payments", [
        ("id", "UUID", "PK"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("amount", "NUMERIC", ""),
        ("status", "TEXT", "pending|succeeded|failed"),
    ]),
    ("payment_webhook_events", "Payments", [
        ("id", "BIGINT", "PK"),
        ("paymongo_event_id", "TEXT", "UQ"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("payment_intent_id", "TEXT", ""),
        ("status", "TEXT", ""),
        ("amount", "NUMERIC", ""),
    ]),
    ("gcash_payment_decision_audit", "Payments", [
        ("id", "BIGINT", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("seller_id", "UUID", "FK\u2192profiles"),
        ("decision", "TEXT", "confirmed|rejected"),
        ("source", "TEXT", "pos|queue"),
    ]),
    ("function_rate_limits", "Payments", [
        ("key", "TEXT", "PK"),
        ("count", "INT", ""),
        ("window_start", "TIMESTAMPTZ", ""),
        ("expires_at", "TIMESTAMPTZ", ""),
    ]),
    ("gcash_payment_proofs", "Payments", [
        ("id", "BIGINT", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("submitted_by", "UUID", "FK\u2192profiles"),
        ("proof_url", "TEXT", ""),
    ]),
    ("order_payment_events", "Payments", [
        ("id", "BIGINT", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("actor_id", "UUID", "FK\u2192profiles"),
        ("event", "TEXT", ""),
    ]),
    ("payment_fee_config", "Payments", [
        ("id", "BIGINT", "PK"),
        ("fee_percent", "NUMERIC", ""),
        ("updated_by", "UUID", "FK\u2192profiles"),
    ]),
    ("vouchers", "Payments", [
        ("id", "UUID", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("code", "TEXT", "UQ"),
        ("discount", "NUMERIC", ""),
        ("created_by", "UUID", "FK\u2192profiles"),
    ]),
    ("voucher_redemptions", "Payments", [
        ("id", "BIGINT", "PK"),
        ("voucher_id", "UUID", "FK\u2192vouchers"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("store_id", "UUID", "FK\u2192stores"),
    ]),
    ("product_reviews", "Reviews", [
        ("id", "BIGINT", "PK"),
        ("product_id", "UUID", "FK\u2192products"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("rating", "INT 1-5", ""),
    ]),
    ("product_review_images", "Reviews", [
        ("id", "BIGINT", "PK"),
        ("review_id", "BIGINT", "FK\u2192product_reviews"),
        ("image_url", "TEXT", ""),
    ]),
    ("reviews", "Reviews", [
        ("id", "BIGINT", "PK"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("order_item_id", "UUID", "FK\u2192order_items"),
        ("product_id", "UUID", "FK\u2192products"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("rating", "INT 1-5", ""),
        ("seller_reply", "TEXT", ""),
    ]),
    ("review_images", "Reviews", [
        ("id", "BIGINT", "PK"),
        ("review_id", "BIGINT", "FK\u2192reviews"),
        ("image_url", "TEXT", ""),
    ]),
    ("conversations", "Messaging", [
        ("id", "UUID", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("customer_id", "UUID", "FK\u2192profiles"),
        ("last_message_at", "TIMESTAMPTZ", ""),
    ]),
    ("messages", "Messaging", [
        ("id", "UUID", "PK"),
        ("conversation_id", "UUID", "FK\u2192conversations"),
        ("sender_id", "UUID", "FK\u2192profiles"),
        ("order_reference_id", "UUID", "FK\u2192orders"),
        ("attachment_url", "TEXT", ""),
        ("is_read", "BOOL", ""),
    ]),
    ("notifications", "Messaging", [
        ("id", "UUID", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("order_id", "UUID", "FK\u2192orders"),
        ("category", "ENUM", ""),
        ("is_read", "BOOL", ""),
    ]),
    ("device_tokens", "Messaging", [
        ("id", "BIGINT", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("token", "TEXT", ""),
    ]),
    ("seller_notifications", "Messaging", [
        ("id", "UUID", "PK"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("type", "TEXT", "new_order|stale|low_stock"),
        ("reference_id", "UUID", ""),
        ("is_read", "BOOL", ""),
    ]),
    ("reports", "Moderation", [
        ("id", "BIGINT", "PK"),
        ("reporter_id", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("product_id", "UUID", "FK\u2192products"),
        ("status", "TEXT", ""),
    ]),
    ("seller_business_docs", "Moderation", [
        ("id", "BIGINT", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("doc_url", "TEXT", ""),
    ]),
    ("seller_application_audit_log", "Moderation", [
        ("id", "BIGINT", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("action", "TEXT", ""),
    ]),
    ("seller_activity_log", "Moderation", [
        ("id", "UUID", "PK"),
        ("actor_id", "UUID", "FK\u2192profiles"),
        ("action", "TEXT", ""),
        ("store_id", "UUID", "FK\u2192stores"),
    ]),
    ("shoe_model_requests", "Moderation", [
        ("id", "UUID", "PK"),
        ("requested_by", "UUID", "FK\u2192profiles"),
        ("store_id", "UUID", "FK\u2192stores"),
        ("product_id", "UUID", "FK\u2192products"),
        ("status", "TEXT", ""),
        ("model_id", "BIGINT", "FK\u2192product_models"),
    ]),
    ("foot_measurements", "Moderation", [
        ("id", "BIGINT", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("recommended_eu_size", "TEXT", ""),
        ("paper_size_used", "TEXT", ""),
        ("scan_date", "TIMESTAMPTZ", ""),
    ]),
    ("foot_scan_jobs", "Moderation", [
        ("id", "UUID", "PK"),
        ("user_id", "UUID", "FK\u2192profiles"),
        ("status", "TEXT", "queued|uploading|done|failed"),
        ("frame_count", "INT", ""),
        ("mesh_path", "TEXT", ""),
    ]),
]

DOMAIN_ORDER = ["Identity", "Catalog", "Orders", "Payments", "Reviews", "Messaging", "Moderation"]
DOMAIN_COLOR = {
    "Identity": "4472C4",
    "Catalog": "ED7D31",
    "Orders": "548235",
    "Payments": "833C99",
    "Reviews": "BF8F00",
    "Messaging": "2E75B6",
    "Moderation": "C00000",
}

ROW_H = 20
HEADER_H = 30
TABLE_W = 250

def esc(s):
    return html.escape(s, quote=False)

pages = {}
for domain in DOMAIN_ORDER:
    pages[domain] = [t for t in TABLES if t[1] == domain]

# Yellow key icon for PK rows: inline SVG image (no font, no emoji), so the
# marker is exactly #FF0000 on every machine. Double quotes are %22-encoded
# so the tag survives XML attribute escaping untouched.
PK_IMG = ("<img width='13' height='13' style='vertical-align:-2px' "
          "src='data:image/svg+xml,"
          "<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2214%22 height=%2214%22 viewBox=%220 0 24 24%22>"
          "<g fill=%22none%22 stroke=%22%23FF0000%22 stroke-width=%222.6%22 stroke-linecap=%22round%22>"
          "<circle cx=%228%22 cy=%228%22 r=%224.6%22/>"
          "<path d=%22M11.5 11.5 20 20%22/>"
          "<path d=%22M16.6 16.6l2.5-2.5%22/>"
          "<path d=%22M13.9 19.3l2.5-2.5%22/>"
          "</g></svg>'>")

diagram_xml = []
edge_xml = []
edge_id = 0
table_pos = {}  # name -> (page, x, y, h)
page_colx = {}  # domain -> [x0, x1, x2]
page_bottom = {}  # domain -> max table bottom y

def emit_table_cells(name, columns, x, y, h, tid, title_fill=None):
    out = []
    _fill = f"#{title_fill}" if title_fill else "none"
    _tfont = "#FFFFFF" if title_fill else "light-dark(#000000,#FFFFFF)"
    out.append(
        f'<mxCell id="{tid}" value="{esc(name)}" '
        f'style="swimlane;fontStyle=1;align=center;verticalAlign=top;childLayout=stackLayout;'
        f'horizontal=1;startSize=26;horizontalStack=0;resizeParent=1;resizeParentMax=0;'
        f'resizeLast=0;collapsible=1;marginBottom=0;fillColor={_fill};'
        f'fontColor={_tfont};strokeColor=light-dark(#000000,#FFFFFF);" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{TABLE_W}" height="{h}" as="geometry"/></mxCell>'
    )
    for r, (col, typ, keys) in enumerate(columns):
        is_pk = "PK" in keys
        mfk = _re.search(r"FK\u2192([a-z_\.]+)", keys)
        fk_tgt = mfk.group(1).split(".")[-1] if mfk else None
        show_fk = bool(fk_tgt and fk_tgt != "auth")
        prefix = ""
        if is_pk:
            prefix += PK_IMG + " "
        if show_fk:
            prefix += chr(0x1F511) + chr(0xFE0E) + " "  # plain monochrome key
        label = f"{col} : {typ}"
        parts = []
        if is_pk:
            parts.append("PK")
        if show_fk:
            parts.append(f"FK\u2192{fk_tgt}")
        if parts:
            label += " [" + ", ".join(parts) + "]"
        elif keys:
            label += f" [{keys.split(chr(44))[0]}]"
        style = ("text;strokeColor=none;fillColor=none;fontColor=light-dark(#000000,#FFFFFF);align=left;verticalAlign=middle;"
                 "spacingLeft=6;spacingRight=4;overflow=hidden;rotatable=0;"
                 "points=[[0,0.5],[1,0.5]];portConstraint=eastwest;")
        if is_pk:
            style += "fontStyle=1;html=1;"
        out.append(
            f'<mxCell id="{tid}-r{r}" value="{esc(prefix + label)}" style="{style}" '
            f'vertex="1" parent="{tid}">'
            f'<mxGeometry y="{HEADER_H + r * ROW_H}" width="{TABLE_W}" '
            f'height="{ROW_H}" as="geometry"/></mxCell>'
        )
    return out


for page_idx, domain in enumerate(DOMAIN_ORDER):
    tables = pages[domain]
    # 2 columns per page for A4 portrait (827 wide). Column gap 150 so
    # shared connector lanes have room to spread instead of stacking.
    # Tables go into the currently-shortest column so tall pages use
    # the full page height instead of leaving one column half empty.
    # Row gap is adaptive per page: the tallest pages pack tighter so
    # everything fits the 1169 height, small pages breathe up to 110.
    cols = 2
    COL_GAP = 150
    col_x = [88 + c * (TABLE_W + COL_GAP) for c in range(cols)]
    heights = [HEADER_H + len(columns) * ROW_H for (_, _, columns) in tables]
    tmp_y = [110.0] * cols
    colH = [0] * cols
    colN = [0] * cols
    assign = []
    for h in heights:
        c = min(range(cols), key=lambda k: tmp_y[k])
        assign.append(c)
        tmp_y[c] += h + 90
        colH[c] += h
        colN[c] += 1
    fit_gap = (1129 - 110.0 - max(colH)) / max(max(colN) - 1, 1)
    ROW_GAP = max(36.0, min(110.0, fit_gap))
    col_y = [110.0] * cols
    cells = []
    for i, (name, dom, columns) in enumerate(tables):
        c = assign[i]
        x = col_x[c]
        y = col_y[c]
        h = heights[i]
        table_pos[name] = (page_idx, c, x, y, h)
        cells.extend(emit_table_cells(name, columns, x, y, h, f"t-{name}"))
        col_y[c] += h + ROW_GAP
    page_colx[domain] = col_x
    page_bottom[domain] = round(max(col_y) - ROW_GAP, 1)
    diagram_xml.append((domain, cells))

# Edges per page: FK -> target, drawn only when both ends share the page.
# Routing is delegated to draw_edges (two-pass unique-lane router).
import re
# Spread connector ports along a table side so parallel lines into the
# same hub (e.g. five FKs into profiles) leave/land at different heights
# instead of sitting on top of each other. Fractions stay in the row
# area, clear of the header (header ~= top 12%).
corridor_extra = {}  # lane_ns -> extra page height for bottom-corridor lines

def draw_edges(cells, tables_here, pos, colx, bottom, tid_prefix, lane_ns):
    # Two-pass router with a hard guarantee: no two edges ever share a
    # segment. Pass 1 decides each edge's route (a single gap lane, or a
    # top/bottom corridor for long spans) and counts lane/port usage.
    # Pass 2 gives every sharing edge its own unique lane offset, port
    # height and corridor slot, so parallel lines run side by side and
    # never sit on top of each other.
    global edge_id
    names_here = {t[0] for t in tables_here}
    hmap = {tid_prefix + n: ph for n, (_pg, _c, _x, _y, ph) in pos.items()}
    ncols = len(colx)
    routes = []
    gap_use = {}
    port_use = {}
    for (name, dom, columns) in tables_here:
        for (col, typ, keys) in columns:
            m = re.search(r"FK→([a-z_\.]+)", keys)
            if not m:
                continue
            target = m.group(1).split(".")[-1]
            if target in ("auth",) or target not in names_here:
                continue
            src = f"{tid_prefix}{name}"
            tgt = f"{tid_prefix}{target}"
            _, sc, sx, sy, sh = pos[name]
            _, tc, tx, ty, th = pos[target]
            rec = {"col": col, "src": src, "tgt": tgt, "sc": sc, "tc": tc,
                   "sy": sy, "sh": sh, "ty": ty, "th": th}
            if abs(sc - tc) >= 2:
                rec["kind"] = "corridor"
                rec["top"] = sy < (110.0 + bottom) / 2
                rec["src_base"] = colx[sc] + TABLE_W + 70 if sc < 2 else colx[sc - 1] + TABLE_W + 70
                rec["tgt_base"] = colx[tc] + TABLE_W + 70 if tc < 2 else colx[tc - 1] + TABLE_W + 70
                rec["ex_s"] = 1 if sc < 2 else 0
                rec["nx_s"] = 1 if tc < 2 else 0
                gap_use[rec["src_base"]] = gap_use.get(rec["src_base"], 0) + 1
                gap_use[rec["tgt_base"]] = gap_use.get(rec["tgt_base"], 0) + 1
            else:
                rec["kind"] = "lane"
                if sc == tc:
                    if sc == ncols - 1 and ncols > 1:
                        rec["base"] = colx[sc] - 75
                        rec["ex_s"] = 0
                        rec["nx_s"] = 0
                    else:
                        rec["base"] = colx[sc] + TABLE_W + 70
                        rec["ex_s"] = 1
                        rec["nx_s"] = 1
                elif tc > sc:
                    rec["base"] = colx[sc] + TABLE_W + 70
                    rec["ex_s"] = 1
                    rec["nx_s"] = 0
                else:
                    rec["base"] = colx[tc] + TABLE_W + 70
                    rec["ex_s"] = 0
                    rec["nx_s"] = 1
                gap_use[rec["base"]] = gap_use.get(rec["base"], 0) + 1
            port_use[(src, rec["ex_s"])] = port_use.get((src, rec["ex_s"]), 0) + 1
            port_use[(tgt, rec["nx_s"])] = port_use.get((tgt, rec["nx_s"]), 0) + 1
            routes.append(rec)
    # The top corridor holds 6 slots (y 88-108); send any overflow below.
    tops = [r for r in routes if r["kind"] == "corridor" and r["top"]]
    if len(tops) > 6:
        tops.sort(key=lambda r: r["sy"])
        for r in tops[6:]:
            r["top"] = False
    gap_seq = {}
    def gap_off(base):
        k = gap_use[base]
        i = gap_seq.get(base, 0)
        gap_seq[base] = i + 1
        if k <= 1:
            return 0.0
        step = min(14.0, 110.0 / (k - 1))
        return round((i - (k - 1) / 2) * step, 1)
    port_seq = {}
    def port_frac(tid, side):
        k = port_use[(tid, side)]
        i = port_seq.get((tid, side), 0)
        port_seq[(tid, side)] = i + 1
        h = hmap[tid]
        lo = max(0.18, (HEADER_H + 6) / h)
        hi = 0.93
        if k <= 1:
            return round((lo + hi) / 2, 3)
        return round(lo + (i + 0.5) * (hi - lo) / k, 3)
    top_n = 0
    bot_n = 0
    for r in routes:
        if r["kind"] == "corridor":
            if r["top"]:
                r["cy"] = round(88 + 4 * top_n, 1)
                top_n += 1
            else:
                r["cy"] = round(bottom + 60 + 6 * bot_n, 1)
                bot_n += 1
            r["src_lane"] = round(r["src_base"] + gap_off(r["src_base"]), 1)
            r["tgt_lane"] = round(r["tgt_base"] + gap_off(r["tgt_base"]), 1)
        else:
            r["lane"] = round(r["base"] + gap_off(r["base"]), 1)
        r["ey"] = port_frac(r["src"], r["ex_s"])
        r["ny"] = port_frac(r["tgt"], r["nx_s"])
    corridor_extra[lane_ns] = (60 + 6 * max(0, bot_n - 1) + 44) if bot_n else 0
    for r in routes:
        edge_id += 1
        if r["kind"] == "corridor":
            pts = [(r["src_lane"], round(r["sy"] + r["ey"] * r["sh"], 1)),
                   (r["src_lane"], r["cy"]),
                   (r["tgt_lane"], r["cy"]),
                   (r["tgt_lane"], round(r["ty"] + r["ny"] * r["th"], 1))]
        else:
            pts = [(r["lane"], round(r["sy"] + r["ey"] * r["sh"], 1)),
                   (r["lane"], round(r["ty"] + r["ny"] * r["th"], 1))]
        style_sides = (f"exitX={r['ex_s']};exitY={r['ey']};exitDx=0;exitDy=0;"
                       f"entryX={r['nx_s']};entryY={r['ny']};entryDx=0;entryDy=0;")
        pts_xml = "".join(
            f'<mxPoint x="{px}" y="{py}"/>' for px, py in pts)
        cells.append(
            f'<mxCell id="e{edge_id}" value="{esc(r["col"])}" '
            f'style="endArrow=ERmany;startArrow=ERone;html=1;rounded=1;strokeColor=light-dark(#000000,#FFFFFF);fontColor=light-dark(#000000,#FFFFFF);'
            f'labelBackgroundColor=none;'
            f'edgeStyle=orthogonalEdgeStyle;jettySize=auto;orthogonalLoop=1;'
            f'{style_sides}'
            f'fontSize=9;" edge="1" parent="1" '
            f'source="{r["src"]}" target="{r["tgt"]}">'
            f'<mxGeometry relative="1" as="geometry">'
            f'<Array as="points">{pts_xml}</Array></mxGeometry></mxCell>'
        )


for _domain, _cells in diagram_xml:
    draw_edges(_cells, pages[_domain], table_pos,
               page_colx[_domain], page_bottom[_domain], "t-", _domain)

# NOTE: no combined "all tables on one sheet" page. A 57-table single
# sheet forces line overlaps and is not standard ERD practice. The
# schema is split into subject-area modules below (one page per
# domain); cross-domain FKs are shown as FK->table text only.

LEGEND = ("ERD legend:  [key] = key column (red key icon = primary key [PK] bold,  plain key = foreign key [FK->table]),  "
          "line 1--crowfoot = one-to-many.  Cross-domain FKs are text only (FK->table); "
          "see the named subject-area page for the referenced table.")

# Subject-area modules: each page holds one domain. Cross-domain FKs are
# NOT drawn as lines and do NOT use flowchart off-page connectors -- the
# FK->table text names the target and its subject-area page. This keeps
# every page overlap-free by construction.
name_to_domain = {t[0]: t[1] for t in TABLES}
page_heights = {}
page_sizes = {}
for _idx, (_domain, _cells) in enumerate(diagram_xml):
    page_heights[_domain] = 1169

out = ['<?xml version="1.0" encoding="UTF-8"?>',
       '<mxfile host="app.diagrams.net" agent="SoleVision ERD generator" version="24.7.17">']
for page_idx, (domain, cells) in enumerate(diagram_xml):
    count = len(pages[domain])
    out.append(f'  <diagram id="page-{page_idx}" name="{page_idx+1} {domain} ({count} tables)">')
    out.append('    <mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" '
               'connect="1" arrows="1" fold="1" page="1" pageScale="1" '
               f'pageWidth="{page_sizes.get(domain, (827, 1169))[0]}" pageHeight="{page_heights[domain]}" math="0" shadow="0">')
    out.append('      <root>')
    out.append('        <mxCell id="0"/>')
    out.append('        <mxCell id="1" parent="0"/>')
    out.append(
        f'        <mxCell id="title-{page_idx}" value="{domain + " domain"}" '
        'style="text;html=1;strokeColor=none;fillColor=none;align=left;'
        'verticalAlign=middle;fontSize=18;fontStyle=1;" vertex="1" parent="1">'
        '<mxGeometry x="60" y="20" width="400" height="30" as="geometry"/></mxCell>')
    out.append(
        f'        <mxCell id="legend-{page_idx}" value="{LEGEND}" '
        'style="text;html=1;strokeColor=none;fillColor=none;align=left;'
        'verticalAlign=middle;fontSize=10;" vertex="1" parent="1">'
        '<mxGeometry x="60" y="50" width="700" height="30" as="geometry"/></mxCell>')
    for cell in cells:
        out.append(f'        {cell}')
    out.append('      </root>')
    out.append('    </mxGraphModel>')
    out.append('  </diagram>')
out.append('</mxfile>')

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(out), encoding="utf-8")
print(f"Wrote {OUT} ({len(TABLES)} tables, {edge_id} same-page relations)")

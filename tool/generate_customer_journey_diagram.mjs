#!/usr/bin/env node
/**
 * SoleVision — customer journey flowchart generator (client-facing, plain English).
 *
 * Writes docs/diagrams/customer-journey-flowchart.drawio (multi-page) and one
 * SVG preview per page into docs/diagrams/previews/.
 *
 * One page = one sheet of A4 paper: each page is laid out at its natural size
 * for reading on screen, then scaled down (never up) and centred on an
 * 827 x 1169 page, so printing the .drawio "fit to page" needs no scaling and
 * never spills onto a second sheet. A page that would shrink past 65 percent
 * does not fit: split its flow across pages with off-page connectors
 * ("continues on page N" / "from page N") instead. The scale used per page
 * is printed at the end of the run.
 *
 * Conventions, matching the flowchart style on p.53 of the capstone document:
 *   - sharp rectangle   = a step (process, display, save)
 *   - parallelogram     = user input or a system message (type, pick, Show, We email)
 *   - diamond           = a question
 *   - oval              = start / end
 *   - pentagon          = off-page connector ("continues on page N" / "from page N")
 *   - small circle A/B  = on-page connector (the flow jumps back to the same letter,
 *                         so no long return lines are ever drawn across the page)
 *
 * Run:  node tool/generate_customer_journey_diagram.mjs
 * Exits non-zero if any layout or wording check fails.
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const HERE = path.dirname(url.fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const OUT_FILE = path.join(ROOT, 'docs', 'diagrams', 'customer-journey-flowchart.drawio');
const PREVIEW_DIR = path.join(ROOT, 'docs', 'diagrams', 'previews');

// ---------------------------------------------------------------- geometry --
const SPINE = { x: 420, w: 290 };
const LEFT = { x: 30, w: 250 };
const RIGHT = { x: 825, w: 240 };
const PAGE_W = 1100;
// draw.io's A4 sheet: 210 x 297 mm at 100 dpi.
const A4 = { w: 827, h: 1169 };
const A4_MARGIN = 26;
// A page needing a smaller scale does not fit: split its flow across pages
// with off-page connectors instead of shrinking further. Calibrated against
// the seller chart, whose densest sheet prints at 40 percent.
const MIN_A4_SCALE = 0.40;
const TOP = 130;
const GAP = 42;
const LINE = 19;
const PROC_PAD = 46;
const OFF_PAD = 44;
// Jump-code pentagons hug their text: wide enough for the longest line,
// never full width.
const offFit = (lines, maxW) => {
  const longest = Math.max(...lines.map((l) => l.length));
  return Math.min(maxW, Math.max(80, Math.round(longest * 6.3 + 30)));
};
const CIRCLE = 48;

const lineH = (lines) => lines.length * LINE;

// ------------------------------------------------------------------ styles --
const ADAPT = 'strokeColor=light-dark(#000000,#FFFFFF);fontColor=light-dark(#000000,#FFFFFF);';
const S = {
  proc: `rounded=0;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=13;`,
  decision: `rhombus;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=13;perimeter=rhombusPerimeter;`,
  terminator: `ellipse;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=14;fontStyle=1;`,
  offpage: `shape=offPageConnector;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=12;fontStyle=1;verticalAlign=top;spacingTop=10;perimeter=rectanglePerimeter;`,
  onpage: `ellipse;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=15;fontStyle=1;aspect=fixed;perimeter=ellipsePerimeter;`,
  db: `shape=cylinder;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=13;fontStyle=1;`,
  io: `shape=parallelogram;whiteSpace=wrap;html=1;fillColor=none;${ADAPT}fontSize=13;perimeter=parallelogramPerimeter;`,
  note: `rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=4 4;fillColor=none;${ADAPT}fontSize=12;align=left;verticalAlign=middle;spacingLeft=10;spacingRight=10;`,
  title: 'text;html=1;fontSize=22;fontStyle=1;align=left;verticalAlign=middle;fontColor=light-dark(#000000,#FFFFFF);',
  subtitle: 'text;html=1;fontSize=12;align=left;verticalAlign=middle;fontColor=light-dark(#000000,#FFFFFF);',
};
const EDGE = 'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=classic;endFill=1;strokeColor=light-dark(#000000,#FFFFFF);strokeWidth=1.5;fontSize=9;fontColor=light-dark(#000000,#FFFFFF);labelBackgroundColor=none;';

// ------------------------------------------------------------------- pages --
// Short page codes printed in off-page connectors instead of the full page
// name, e.g. `Continue on page 8` + `Hm`. Initials of the significant words;
// single-word pages use first + last letter; 8 and 11 take three letters so
// every code stays unique.
const META = [
  { n: 1, name: 'Open the app', code: 'CAP', slug: 'open-the-app' },
  { n: 2, name: 'Create an account', code: 'CCA', slug: 'create-an-account' },
  { n: 3, name: 'Confirm the email', code: 'CCE', slug: 'confirm-the-email' },
  { n: 4, name: 'Add their foot size', code: 'CAFS', slug: 'add-their-foot-size' },
  { n: 5, name: 'Sign in', code: 'CSI', slug: 'sign-in' },
  { n: 6, name: 'Home', code: 'CHm', slug: 'home' },
  { n: 7, name: 'Browse the shops', code: 'CBS', slug: 'browse-the-shops' },
  { n: 8, name: 'Try the shoes on', code: 'CTSO', slug: 'try-the-shoes-on' },
  { n: 9, name: 'Cart and payment', code: 'CCP', slug: 'cart-and-payment' },
  { n: 10, name: 'Track the order', code: 'CTO', slug: 'track-the-order' },
  { n: 11, name: 'Talk to the shop', code: 'CTTS', slug: 'talk-to-the-shop' },
  { n: 12, name: 'Profile and settings', code: 'CPS', slug: 'profile-and-settings' },
  { n: 13, name: 'Settings in detail', code: 'CSD', slug: 'settings-in-detail' },
  { n: 14, name: 'Bulk holds', code: 'CBH', slug: 'bulk-holds' },
];
const byNumber = (n) => META.find((m) => m.n === n);
const listNumbers = (list) =>
  list.length === 1 ? `${list[0]}` : list.length === 2 ? `${list[0]} or ${list[1]}` : `${list.slice(0, -1).join(', ')} or ${list[list.length - 1]}`;
const exitLines = (n) => [byNumber(n).code];

// ------------------------------------------------------------- PageBuilder --
class PageBuilder {
  constructor(meta) {
    this.meta = meta;
    this.shapes = [];
    this.edges = [];
    this.entrySpecs = [];
    this.exitSpecs = [];
    this.spineY = TOP;
    this.lastDecision = null;
    this.col = { left: 0, right: 0 };
    this.colLast = { left: null, right: null };
    this.spineLast = null;
    this.pendingEntries = null;
    this.pendingSpineLabel = null;
    this.pendingCircles = [];
    this.pendingSocial = [];
    this.counter = 0;
    this.noteCount = 0;
  }

  id(name) { return `p${this.meta.n}-${name}`; }

  add(kind, name, lines, x, y, w, h) {
    const shape = { id: this.id(name), kind, lines, x, y, w, h };
    this.shapes.push(shape);
    return shape;
  }

  get(name) {
    const id = name.startsWith(`p${this.meta.n}-`) ? name : this.id(name);
    const s = this.shapes.find((v) => v.id === id);
    if (!s) throw new Error(`page ${this.meta.n}: no shape ${id}`);
    return s;
  }

  edge(fromId, toId, opts = {}) {
    this.counter += 1;
    const from = this.get(fromId);
    const to = this.get(toId);
    this.edges.push({ id: `e${this.meta.n}-${this.counter}`, from: from.id, to: to.id, ...opts });
  }

  // ---- spine ---------------------------------------------------------------
  _stack(shape) {
    if (this.pendingEntries) {
      for (const e of this.pendingEntries) {
        const frac = (e.x + e.w / 2 - shape.x) / shape.w;
        this.edge(e.id, shape.id, { fromSide: 'bottom', toSide: 'top', toFrac: frac });
      }
      this.pendingEntries = null;
    } else if (this.spineLast) {
      this.edge(this.spineLast.id, shape.id, {
        fromSide: 'bottom',
        toSide: 'top',
        label: this.pendingSpineLabel,
      });
    }
    this.pendingSpineLabel = null;
    this.spineLast = shape;
    this.spineY = shape.y + shape.h + GAP;
    return shape;
  }

  terminator(name, lines) {
    const h = 88;
    const s = this.add('terminator', name, lines, SPINE.x + 30, this.spineY, SPINE.w - 60, h);
    return this._stack(s);
  }

  proc(name, lines, opts = {}) {
    const w = opts.w ?? SPINE.w;
    const x = opts.x ?? SPINE.x + (SPINE.w - w) / 2;
    const h = lineH(lines) + PROC_PAD;
    const s = this.add('proc', name, lines, x, this.spineY, w, h);
    return this._stack(s);
  }

  // Paper style (p.53): parallelogram = user input or system message
  // (Enter details, type a code, Show message, We email…). Same box size
  // as proc so the A4 layout is unchanged — only the shape differs.
  io(name, lines, opts = {}) {
    const w = opts.w ?? SPINE.w;
    const x = opts.x ?? SPINE.x + (SPINE.w - w) / 2;
    const h = lineH(lines) + PROC_PAD;
    const s = this.add('io', name, lines, x, this.spineY, w, h);
    return this._stack(s);
  }

  decision(name, lines, opts = {}) {
    const h = Math.max(150, lineH(lines) + 66);
    const s = this.add('decision', name, lines, SPINE.x - 10, this.spineY, SPINE.w + 20, h);
    this.lastDecision = s;
    this.pendingSpineLabel = opts.down;
    this._stack(s);
    return s;
  }

  branch(side, name, lines, opts = {}) {
    const d = this.lastDecision;
    if (!d) throw new Error('branch() without a decision');
    const col = side === 'left' ? LEFT : RIGHT;
    const h = lineH(lines) + PROC_PAD;
    // centre the branch on the decision so the connector stays a straight line
    const top = Math.max(d.y + (d.h - h) / 2, this.col[side] || 0);
    const s = this.add(opts.kind ?? 'proc', name, lines, col.x, top, col.w, h);
    this.edge(d.id, s.id, {
      fromSide: side === 'left' ? 'left' : 'right',
      toSide: side === 'left' ? 'right' : 'left',
      label: opts.label,
    });
    this.col[side] = s.y + s.h + GAP;
    this.colLast[side] = s;
    return s;
  }

  branchNext(side, name, lines, kind = 'proc') {
    const prev = this.colLast[side];
    if (!prev) throw new Error(`branchNext(${side}) without a branch`);
    const h = lineH(lines) + PROC_PAD;
    const s = this.add(kind, name, lines, prev.x, this.col[side], prev.w, h);
    this.edge(prev.id, s.id, { fromSide: 'bottom', toSide: 'top' });
    this.col[side] = s.y + s.h + GAP;
    this.colLast[side] = s;
    return s;
  }

  branchIO(side, name, lines, opts = {}) {
    const d = this.lastDecision;
    if (!d) throw new Error('branchIO() without a decision');
    const col = side === 'left' ? LEFT : RIGHT;
    const h = lineH(lines) + PROC_PAD;
    const top = Math.max(d.y + (d.h - h) / 2, this.col[side] || 0);
    const s = this.add('io', name, lines, col.x, top, col.w, h);
    this.edge(d.id, s.id, {
      fromSide: side === 'left' ? 'left' : 'right',
      toSide: side === 'left' ? 'right' : 'left',
      label: opts.label,
    });
    this.col[side] = s.y + s.h + GAP;
    this.colLast[side] = s;
    return s;
  }

  /** Branch that is itself a "continues on page N" pentagon. */
  branchExit(side, toNumber, opts = {}) {
    if (!this.lastDecision) throw new Error('branchExit() without a decision');
    const col = side === 'left' ? LEFT : RIGHT;
    const lines = exitLines(toNumber);
    const h = lineH(lines) + OFF_PAD;
    const top = Math.max(this.lastDecision.y + (this.lastDecision.h - h) / 2, this.col[side] || 0);
    const w = offFit(lines, col.w - 40);
    const s = this.add('offpage', `exit-${toNumber}-${side}`, lines, col.x + (col.w - w) / 2, top, w, h);
    this.edge(this.lastDecision.id, s.id, {
      fromSide: side === 'left' ? 'left' : 'right',
      toSide: side === 'left' ? 'right' : 'left',
      label: opts.label,
    });
    this.col[side] = s.y + s.h + GAP;
    this.colLast[side] = s;
    this.exitSpecs.push({ to: toNumber, id: s.id });
    return s;
  }

  note(side, lines, opts = {}) {
    this.noteCount += 1;
    const col = side === 'left' ? LEFT : RIGHT;
    const w = opts.w ?? col.w;
    const x = opts.x ?? col.x;
    const h = lineH(lines) + 34;
    const y = opts.y ?? Math.max(this.col[side] || 0, this.spineY - GAP - h);
    const s = this.add('note', `note${this.noteCount}`, lines, x, y, w, h);
    this.col[side] = Math.max(this.col[side] || 0, y + h + GAP);
    return s;
  }

  entry(from, phrase) {
    const froms = Array.isArray(from) ? from : [from];
    const lines = [this.meta.code];
    const h = lineH(lines) + OFF_PAD;
    const w = offFit(lines, SPINE.w);
    const s = this.add('offpage', `entry-${froms.join('-')}`, lines, SPINE.x + (SPINE.w - w) / 2, TOP, w, h);
    this.spineY = s.y + s.h + GAP;
    this.spineLast = s;
    this.entrySpecs.push({ from: froms, id: s.id });
    return s;
  }

  entryRow(specs) {
    const gap = 40;
    const boxes = specs.map((spec) => {
      const lines = [spec.from.map((n) => byNumber(n).code).join(' · ')];
      return { spec, lines, w: offFit(lines, 320), h: lineH(lines) + OFF_PAD };
    });
    const h = Math.max(...boxes.map((b) => b.h));
    let x = 50 + (1000 - (boxes.reduce((t, b) => t + b.w, 0) + gap * (boxes.length - 1))) / 2;
    const made = [];
    boxes.forEach((b) => {
      const s = this.add('offpage', `entry-${b.spec.from.join('-')}`, b.lines, x, TOP, b.w, h);
      this.entrySpecs.push({ from: b.spec.from, id: s.id });
      made.push(s);
      x += b.w + gap;
    });
    this.pendingEntries = made;
    this.spineY = TOP + h + GAP;
    return made;
  }

  wideProc(name, lines) {
    const w = 1000;
    const h = lineH(lines) + PROC_PAD;
    const s = this.add('proc', name, lines, 50, this.spineY, w, h);
    return this._stack(s);
  }

  exitRow(numbers) {
    const last = this.spineLast;
    const gap = 22;
    const boxes = numbers.map((t) => {
      const lines = exitLines(t);
      return { t, lines, w: offFit(lines, 200), h: lineH(lines) + OFF_PAD };
    });
    const h = Math.max(...boxes.map((b) => b.h));
    const y = this.spineY;
    let x = 50 + (1000 - (boxes.reduce((t, b) => t + b.w, 0) + gap * (boxes.length - 1))) / 2;
    boxes.forEach((b) => {
      const s = this.add('offpage', `exit-${b.t}`, b.lines, x, y, b.w, h);
      const frac = (x + b.w / 2 - last.x) / last.w;
      this.edge(last.id, s.id, { fromSide: 'bottom', toSide: 'top', fromFrac: frac });
      this.exitSpecs.push({ to: b.t, id: s.id });
      x += b.w + gap;
    });
    this.spineY = y + h + GAP;
    return this;
  }

  exit(toNumber, opts = {}) {
    const last = this.spineLast;
    const lines = [...exitLines(toNumber), ...(opts.extra ? [opts.extra] : [])];
    const h = lineH(lines) + OFF_PAD;
    const w = offFit(lines, SPINE.w);
    const s = this.add('offpage', `exit-${toNumber}`, lines, SPINE.x + (SPINE.w - w) / 2, this.spineY, w, h);
    this.edge(last.id, s.id, { fromSide: 'bottom', toSide: 'top' });
    this.spineY = s.y + s.h + GAP;
    this.spineLast = s;
    this.exitSpecs.push({ to: toNumber, id: s.id });
    return s;
  }

  end(name, lines) {
    const h = 90;
    const s = this.add('terminator', name, lines, SPINE.x + 20, this.spineY, SPINE.w - 40, h);
    return this._stack(s);
  }

  /**
   * Circle that sends the flow back to its twin circle placed beside
   * `targetName`. The twin is created in finish(), so the target box may be
   * declared later on the page.
   */
  circleJump(side, letter, targetName, targetFrac = 0.5) {
    const prev = this.colLast[side];
    if (!prev) throw new Error(`circleJump(${side}) without a branch box`);
    const c = this.add('onpage', `c-${letter}-out`, [letter], prev.x + prev.w / 2 - CIRCLE / 2, this.col[side], CIRCLE, CIRCLE);
    this.edge(prev.id, c.id, { fromSide: 'bottom', toSide: 'top' });
    this.col[side] = c.y + c.h + GAP;
    this.colLast[side] = null;
    this.pendingCircles.push({ side, letter, targetName, frac: targetFrac });
    return c;
  }

  _materialiseCircles() {
    for (const spec of this.pendingCircles) {
      const target = this.get(spec.targetName);
      const cx = spec.side === 'left' ? LEFT.x + LEFT.w - CIRCLE : RIGHT.x;
      const ty = target.y + target.h * spec.frac - CIRCLE / 2;
      const inCircle = this.add('onpage', `c-${spec.letter}-in`, [spec.letter], cx, ty, CIRCLE, CIRCLE);
      this.edge(inCircle.id, target.id, {
        fromSide: spec.side === 'left' ? 'right' : 'left',
        toSide: spec.side === 'left' ? 'left' : 'right',
        toFrac: spec.frac,
      });
    }
  }

  /** Merge the last box of a side column into a spine box. */
  merge(side, targetName, opts = {}) {
    const prev = this.colLast[side];
    if (!prev) throw new Error(`merge(${side}) without a branch box`);
    const target = this.get(targetName);
    const frac = opts.frac ?? 0.5;
    this.edge(prev.id, target.id, {
      fromSide: 'bottom',
      toSide: side === 'left' ? 'left' : 'right',
      toFrac: frac,
      waypoints: 'mid',
    });
    this.colLast[side] = null;
    return prev;
  }

  /** Paper-style: proc with an inline DB1 circle below it in the spine flow,
   *  like "Save Customer to Database -> DB1 -> next". The DB1 becomes the
   *  new spine tail so the next step connects from DB1, exactly on paper. */
  procDB(name, lines, opts = {}) {
    const proc = this.proc(name, lines, opts);
    const size = 48;
    const x = Math.round(proc.x + proc.w / 2 - size / 2);
    const y = proc.y + proc.h + 24;
    const c = this.add('onpage', `db1-${name}`, ['DB1'], x, y, size, size);
    this.edge(proc.id, c.id, { fromSide: 'bottom', toSide: 'top' });
    this.spineLast = c;
    // +12 above the DB1, −12 below it: breathing room, same page height.
    this.spineY = y + size + (GAP - 12);
    return proc;
  }

  /** Paper-style: decision with an inline DB1 circle on its spine answer,
   *  e.g. "Check in Database -> DB1 -> Does it exist?". Branch edge still
   *  leaves from the decision; the down spine path goes via DB1. */
  decisionDB(name, lines, opts = {}) {
    const d = this.decision(name, lines, opts);
    const label = this.pendingSpineLabel;
    this.pendingSpineLabel = null;
    const size = 48;
    const x = Math.round(d.x + d.w / 2 - size / 2);
    const y = d.y + d.h + 24;
    const c = this.add('onpage', `db1-${name}`, ['DB1'], x, y, size, size);
    this.edge(d.id, c.id, { fromSide: 'bottom', toSide: 'top', label });
    this.spineLast = c;
    // +12 above the DB1, −12 below it: breathing room, same page height.
    this.spineY = y + size + (GAP - 12);
    return d;
  }

  /** Paper-style social login choice after a plain spine decision
   *  ("How do they sign up / sign in?"). Adds two narrow Google and
   *  Facebook boxes on the left plus a DB1 circle each, with short links
   *  from the decision. Trunk edges from each DB1 down to `trunkTo` (a
   *  spine box defined later on the page) are materialised in finish(),
   *  like the on-page circles. Staggered lanes keep every connector clear. */
  socialPair(trunkToName) {
    const d = this.lastDecision;
    if (!d) throw new Error('socialPair() without a decision');
    const midY = Math.round(d.y + d.h / 2);
    const W = 170;
    const gLines = ['Continue with', 'Google — pick', 'an account.', 'Saved to the Database.'];
    const fLines = ['Continue with', 'Facebook — pick', 'an account.', 'Saved to the Database.'];
    const gh = lineH(gLines) + PROC_PAD;
    const fh = lineH(fLines) + PROC_PAD;
    const gy = Math.round(midY - gh / 2);
    const g = this.add('io', 'social-google', gLines, 30, gy, W, gh);
    this.edge(d.id, g.id, { fromSide: 'left', toSide: 'right', label: 'Google' });
    const dg = this.add('onpage', 'db1-social-google', ['DB1'], 340, gy - 60, 48, 48);
    this.edge(g.id, dg.id, { fromSide: 'top', toSide: 'bottom' });
    const fy = gy + gh + GAP;
    const f = this.add('io', 'social-facebook', fLines, 30, fy, W, fh);
    this.edge(d.id, f.id, { fromSide: 'left', toSide: 'right' });
    const df = this.add('onpage', 'db1-social-facebook', ['DB1'], 292, Math.round(fy + fh / 2 - 24), 48, 48);
    this.edge(f.id, df.id, { fromSide: 'right', toSide: 'left' });
    this.pendingSocial.push({ trunkTo: this.id(trunkToName), from: [dg.id, df.id] });
    return [g, f];
  }

  /** Paper-style legend footer: DB pentagon <-> Database cylinder <-> DB1
   *  circle with double-headed arrows, plus the meaning note. Placed below
   *  all content. Short 20px links are skipped by the crossing check. */
  databaseFooter() {
    const bottom = Math.max(...this.shapes.map((s) => s.y + s.h), this.spineY);
    const y = bottom + GAP;
    const h = 72;
    const pent = this.add('offpage', 'db', ['DB'], 50, y, 80, h);
    const cyl = this.add('db', 'database', ['Database'], 150, y, 200, h);
    const size = 48;
    const c = this.add('onpage', 'db1-legend', ['DB1'], 370, y + (h - size) / 2, size, size);
    this.edge(pent.id, cyl.id, { fromSide: 'right', toSide: 'left', double: true });
    this.edge(cyl.id, c.id, { fromSide: 'right', toSide: 'left', double: true });
    const noteLines = ['DB means the app saves that step;', 'DB1 shows where it is saved.'];
    const nh = lineH(noteLines) + 34;
    const ny = y + (h - nh) / 2;
    this.noteCount += 1;
    const note = this.add('note', 'db-note', noteLines, 440, ny, 330, nh);
    this.edge(c.id, note.id, { fromSide: 'right', toSide: 'left' });
    this.spineY = Math.max(this.spineY, y + h + GAP);
    return cyl;
  }

  finish() {
    this._materialiseCircles();
    for (const spec of this.pendingSocial) {
      const target = this.shapes.find((s) => s.id === spec.trunkTo);
      if (!target) throw new Error(`page ${this.meta.n}: socialPair trunk missing ${spec.trunkTo}`);
      const fracs = [0.8, 0.6];
      spec.from.forEach((fid, i) => {
        this.edge(fid, spec.trunkTo, {
          fromSide: 'bottom',
          toSide: 'left',
          toFrac: fracs[i],
          waypoints: 'mid',
        });
      });
    }
    const bottom = Math.max(...this.shapes.map((s) => s.y + s.h), this.spineY);
    return {
      meta: this.meta,
      shapes: this.shapes,
      edges: this.edges,
      entrySpecs: this.entrySpecs,
      exitSpecs: this.exitSpecs,
      pageHeight: Math.max(1100, Math.round(bottom + 70)),
    };
  }
}

// ------------------------------------------------------------------ content --
const builders = [];
const page = (n, fn) => {
  const b = new PageBuilder(byNumber(n));
  fn(b);
  builders.push(b);
};

// 1 — Open the app
page(1, (b) => {
  b.terminator('start', ['START']);
  b.proc('open', ['The customer opens the app', 'on their phone.']);
  b.proc('load', ['A short loading screen', 'checks for updates.']);
  b.decision('signed', ['Are they already', 'signed in?'], { down: 'No' });
  b.branchExit('right', 6, { label: 'Yes' });
  b.decision('firsttime', ['First time', 'opening it?'], { down: 'No' });
  b.branch('right', 'slides', ['Show the three welcome', 'slides — they can skip them.'], { label: 'Yes' });
  b.circleJump('right', 'A', 'screen', 0.5);
  b.proc('screen', ['Show the Sign up and Sign in', 'screen with Continue with', 'Google and Facebook buttons.', 'One screen — the video', 'keeps playing.']);
  b.decision('whichtap', ['What do they tap?', 'Sign up, Sign in,', 'Google or Facebook?']);
  b.branchExit('right', 2, { label: 'Sign up' });
  b.branchExit('left', 5, { label: 'Sign in' });
  b.note('left', ['Shop owners tap Apply to sell', 'and fill in a different form.']);
  b.note('right', ['Sign in is a switch on the', 'same screen — the video', 'never restarts.']);
  b.databaseFooter();
  b.legend = [
    'How to read this chart:',
    'oval = the start or the end  ·  rectangle = a step  ·  parallelogram = typing or a message  ·  diamond = a question',
    'pentagon holds a page code — the top one is this page, the rest say where to turn',
    'small circle with a letter = the flow jumps back to the same letter',
    'DB pentagon = the app saves that step  ·  DB1 circle = where it is saved',
  ];
});

// 2 — Create an account
page(2, (b) => {
  b.entry(1, ['they tapped Sign up,', 'Google or Facebook']);
  b.decision('method', ['How do they sign up?'], { down: 'Fill in the form' });
  b.socialPair('create');
  b.io('form', ['They fill in the Create Account form:',
    'name · email · phone if they like,',
    'birthday by picking a date —',
    'must be 13 or older,',
    'gender if they like,',
    'password plus confirm,',
    'a strength hint as they type,',
    'and accept the Terms.']);
  b.decision('filled', ['Is every box filled', 'in right, Terms accepted?'], { down: 'Yes' });
  b.branch('right', 'fixbox', ['Show a message on the box', 'that needs fixing.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'form', 0.28);
  b.decisionDB('emailused', ['Is this email', 'already registered?', 'in the Database?'], { down: 'No' });
  b.branch('right', 'used', ['Tell them the email is already',
    'in use — they can sign in or',
    'use another one.'], { label: 'Yes', kind: 'io' });
  b.circleJump('right', 'B', 'form', 0.78);
  b.procDB('create', ['Create the account.', 'Saved to the Database.']);
  b.decision('verified', ['Did they use', 'Google or Facebook', 'with a verified email?'], { down: 'No' });
  b.branchExit('left', 4, { label: 'Yes' });
  b.decision('confirmneed', ['Must the email', 'be confirmed? Usual is yes.'], { down: 'Yes' });
  { const e = b.edges.find((v) => v.from === b.id('verified') && v.to === b.id('confirmneed')); if (e) e.label = 'No, email form'; }
  b.branchExit('right', 4, { label: 'No' });
  b.exit(3);
  b.note('left', ['The new account cannot be used',
    'yet — the email must',
    'be confirmed first.']);
  b.note('right', ['When no confirm is needed,',
    'they skip the code and',
    'go straight to foot size.']);
  b.databaseFooter();
});

// 3 — Confirm the email
page(3, (b) => {
  b.entry(2, ['they just created an account']);
  b.procDB('send', ['We email a 6-digit code', 'and a Confirm button.', 'The code stops working', 'after a short time.']);
  b.decision('howconfirm', ['How do they', 'confirm it?'], { down: 'Type the code' });
  b.branch('left', 'button', ['They tap the button in the',
    'email — it opens the app',
    'and confirms the account.'], { label: 'The email' });
  b.branchExit('right', 5, { label: 'Back to sign in' });
  b.io('typecode', ['They type the 6-digit code', 'in the app.']);
  b.decisionDB('correct', ['Is the code right', 'and still usable?'], { down: 'Yes' });
  b.branch('right', 'wrong', ['Tell them the code is wrong.'], { label: 'No', kind: 'io' });
  b.branchNext('right', 'resend', ['They can ask for a new code —', 'a minute must pass first.', 'Too many tries means waiting.'], 'io');
  b.circleJump('right', 'A', 'typecode', 0.5);
  b.procDB('done', ['Account confirmed —', 'they are signed in.']);
  b.merge('left', 'done');
  b.exit(4);
  b.note('left', ['They can close the app and', 'confirm later — they are asked', 'again next time.']);
  b.note('right', ['Back to sign in stops here —', 'the account stays inactive', 'until the email is confirmed.']);
  b.databaseFooter();
});

// 4 — Add their foot size
page(4, (b) => {
  b.entry([3, 2], ['account ready — code', 'done or no code needed']);
  b.io('ask', ['Ask them to add foot size.', 'Shown once. Never blocks —', 'the account already exists.']);
  b.decision('choose', ['What do they', 'choose?'], { down: 'Skip for now' });
  b.branch('left', 'scan', ['Scan feet with the phone', 'camera. Best pick.', 'If it fails or access is denied,', 'they land back here.'], { label: 'Scan', kind: 'io' });
  b.branch('right', 'manual', ['Type size and width', 'themselves. Must pick', 'a size first or it asks again.'], { label: 'Type it in', kind: 'io' });
  b.proc('skip', ['Or skip for now. Instant —', 'we remind them on Home later.']);
  b.procDB('saved', ['Size saved to the Database —', 'or we remind them', 'on the Home screen later.']);
  b.merge('left', 'saved', { frac: 0.32 });
  b.merge('right', 'saved', { frac: 0.68 });
  b.exit(6);
  b.note('right', ['The scan opens on top,', 'so backing out lands', 'exactly back here.']);
  b.databaseFooter();
});

// 5 — Sign in
page(5, (b) => {
  b.entry([1, 3], ['they want to sign in,', 'with email, Google or Facebook']);
  b.decision('method', ['How do they sign in?'], { down: 'With email' });
  b.socialPair('signedin');
  b.io('creds', ['They type email and password.', 'Empty boxes or a short password', 'are flagged first.']);
  b.decision('forgot', ['Forgot password', 'tapped?'], { down: 'No' });
  b.branch('right', 'resetlink', ['We email a link to set', 'a new one.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'resetdone', ['They open the link on the phone,', 'set a new password —', 'they are signed in.'], 'io');
  b.circleJump('right', 'C', 'signedin', 0.2);
  b.decisionDB('password', ['Is the password', 'correct in the Database?'], { down: 'Yes' });
  b.branch('right', 'error', ['Show the same error for a wrong', 'email or password —', 'they can try again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'creds', 0.5);
  b.decision('newdevice', ['Is this a phone the', 'app already knows?'], { down: 'Yes' });
  b.branch('left', 'code', ['We email a 6-digit code.', 'They type it to prove it is', 'really them. If the mail fails,', 'the reason shows on the', 'same screen.'], { label: 'No', kind: 'io' });
  b.procDB('signedin', ['They are signed in.', 'Saved to the Database.', 'Checks below still apply —', 'new accounts skip them.']);
  b.merge('left', 'signedin');
  b.decision('blocked', ['Is the account', 'suspended?'], { down: 'No' });
  b.branch('right', 'stopped', ['They see why it is closed.', 'Signing out leaves the screen.'], { label: 'Yes', kind: 'io' });
  b.decisionDB('profile', ['Does the profile', 'load from the Database?'], { down: 'Yes' });
  b.branch('right', 'retry', ['Show Retry. They can try', 'again or sign out.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'signedin', 0.8);
  b.decision('mfa', ['Is an extra code', 'needed? New accounts skip.'], { down: 'No' });
  b.branch('left', 'mfacode', ['They type the code from their', 'authenticator app. A lost phone', 'can mail a code. They can', 'also sign out.'], { label: 'Yes', kind: 'io' });
  b.proc('home', ['They see the Home screen.']);
  b.merge('left', 'home');
  b.exit(6);
  b.note('left', ['Too many wrong tries locks', 'the screen for a while.']);
  b.note('right', ['On their own phone they can sign', 'in with a fingerprint next time.', 'First sign in offers', 'to turn it on.']);
  b.databaseFooter();
});

// 6 — Home (hub)
page(6, (b) => {
  b.entryRow([
    { from: [1], phrase: ['already signed in'] },
    { from: [4], phrase: ['foot size is set'] },
    { from: [5], phrase: ['they signed in'] },
    { from: [10], phrase: ['order is done'] },
    { from: [11], phrase: ['shop replied'] },
  ]);
  b.wideProc('home', ['The Home screen shows a search box, the cart,',
    'Men’s · Women’s · Kids’, picks in their size,',
    'items on sale and a grid of products.']);
  b.wideProc('tabs', ['Four tabs sit at the bottom of every screen:',
    'Home · Store · Notifications · Profile.']);  b.decision('size', ['Is their foot size', 'saved yet?'], { down: 'Yes' });
  b.branch('right', 'sizetip', ['A tip offers to add foot size —', 'they can skip it again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'featured', 0.15);
  b.procDB('featured', ['Tap a featured product',
    'to open its details: photos,',
    'price, sizes in stock,',
    'top reviews with see-all.', 'Loaded from the Database.']);
  b.decision('bell', ['Bell or messages', 'showing anything new?'], { down: 'No' });
  b.branch('left', 'openbell', ['Open the bell or the chat —', 'then come back here.'], { label: 'Yes' });
  b.circleJump('left', 'C', 'action', 0.5);
  b.decision('action', ['What do they do',
    'with this product?'], { down: 'Buy it now' });
  b.branch('right', 'addbox', ['Add it to the cart.', 'Saved to the Database.'], { label: 'Add to cart' });
  b.circleJump('right', 'A', 'featured', 0.75);
  b.procDB('buynow', ['Buy it now — straight to checkout.', 'Saved to the Database.']);
  b.wideProc('go', ['From Home they can also go anywhere:']);
  b.exitRow([7, 11, 9, 10, 12]);
  b.databaseFooter();
});

// 7 — Browse the shops
page(7, (b) => {
  b.entry([6, 14], ['they tapped Store']);
  b.procDB('shops', ['The Store tab shows every shop,', 'with its name, rating and what it sells.', 'Loaded from the Database.']);
  b.proc('open', ['Open a shop to see its products,', 'or search for a pair.']);
  b.decision('narrow', ['Do they want to', 'narrow it down?'], { down: 'No' });
  b.branch('right', 'filters', ['Search, or filter by size,', 'colour, price or shop.'], { label: 'Yes', kind: 'io' });  b.procDB('product', ['They open a product: photos, the 3D view,',
    'the sizes still in stock and the reviews.', 'Loaded from the Database.']);
  b.decisionDB('stock', ['Is their size still', 'in stock?'], { down: 'Yes' });
  b.branch('right', 'nostock', ['Try another size, or keep', 'looking in other shops.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'product', 0.5);
  b.decision('next', ['What do they do next?'], { down: 'Add it to the cart' });
  b.branchExit('right', 8, { label: 'Try it on' });
  b.branch('left', 'hold', ['Keep it at the shop for pickup —', 'free, held for 24 hours.'], { label: 'Hold it' });
  b.procDB('cart', ['Add it to the cart.', 'Saved to the Database.']);
  b.merge('left', 'cart', { frac: 0.3 });
  b.decision('resell', ['Buying to resell', 'in bulk?'], { down: 'No' });
  b.branchExit('right', 14, { label: 'Yes' });
  b.exit(9);
  b.note('right', ['They can also reserve a pair',
    'to collect at the shop — free,',
    'held for 24 hours.']);
  b.note('left', ['Recently viewed and On-sale', 'lists live on this tab too.']);
  b.databaseFooter();
});

// 8 — Try the shoes on
page(8, (b) => {
  b.entry(7, ['they tapped Try on']);
  b.decision('allow', ['Does the camera', 'open?'], { down: 'Yes' });
  b.branch('right', 'blocked', ['Allow the camera in the phone', 'settings, then try again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'camera', 0.5);
  b.io('camera', ['Point the camera at their feet.']);
  b.proc('appears', ['The shoe appears on their feet and', 'moves with them.']);
  b.procDB('swap', ['They can swap shoes while the camera', 'is on. The app shows the size that fits.', 'Sizes come from the Database.']);
  b.decision('looks', ['Does it look right?'], { down: 'Yes' });
  b.branch('right', 'another', ['Try another shoe or size.'], { label: 'No' });
  b.circleJump('right', 'A', 'swap', 0.2);
  b.decision('fit', ['Does the suggested', 'size feel right?'], { down: 'Yes' });
  b.branch('right', 'othersize', ['Try a size up or down.'], { label: 'No' });
  b.circleJump('right', 'C', 'swap', 0.85);
  b.procDB('tocart', ['Add it to the cart.', 'Saved to the Database.']);
  b.exit(9);
  b.note('right', ['The fitting is a guide — the size', 'shown is what the app suggests.']);
  b.databaseFooter();
});

// 9 — Cart and payment
page(9, (b) => {
  b.entry([6, 7, 8], ['they opened the Cart']);
  b.procDB('cart', ['The Cart lists what they picked:', 'the item, the size and how many.', 'Loaded from the Database.']);
  b.decision('right', ['Is everything right?'], { down: 'Yes' });
  b.branch('right', 'change', ['Change the size or the number,', 'or remove an item.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'cart', 0.5);  b.proc('checkout', ['Tap Check Out — review the order',
    'and choose where it goes.']);
  b.decision('voucher', ['Have a voucher', 'code to use?'], { down: 'No' });
  b.branch('right', 'apply', ['Type the code — the total', 'drops right away.'], { label: 'Yes', kind: 'io' });
  b.decisionDB('address', ['Do they have an', 'address saved in the Database?'], { down: 'Yes' });
  b.branch('left', 'addaddress', ['Add their address, then come', 'back to check out.'], { label: 'No', kind: 'io' });
  b.circleJump('left', 'B', 'checkout', 0.5);
  b.merge('right', 'address', { frac: 0.3 });
  b.decision('payhow', ['How do they pay?'], { down: 'Cash on pickup' });
  b.branch('left', 'gcash', ['GCash — the app opens GCash',
    'to pay. The order waits until',
    'the payment is confirmed.'], { label: 'GCash' });
  b.proc('cash', ['Cash on pickup — they pay at the shop', 'when they collect it.']);  b.procDB('placed', ['The order is placed — the shop sees it',
    'right away.', 'Saved to the Database.']);
  b.merge('left', 'placed', { frac: 0.32 });
  b.decision('paid', ['Did the payment', 'go through?'], { down: 'Yes' });
  b.branch('right', 'failed', ['The order waits — they can', 'try the payment again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'C', 'payhow', 0.5);
  b.exit(10);
  b.note('right', ['The delivery fee and the',
    'GCash fee are shown before',
    'they confirm.']);
  b.note('right', ['If a GCash payment fails or',
    'runs out of time, the order is',
    'not placed — they can try again.']);
  b.databaseFooter();
});

// 10 — Track the order
page(10, (b) => {
  b.entry([6, 9], ['they opened My Orders']);  b.procDB('list', ['My Orders lists every order,',
    'newest first: unpaid · being',
    'prepared · ready · to review ·',
    'cancelled.', 'Loaded from the Database.']);
  b.decision('unpaid', ['Still needs', 'paying?'], { down: 'No' });
  b.branch('left', 'paynow', ['Pay it here with GCash —', 'then follow it like the rest.'], { label: 'Yes', kind: 'io' });
  b.decision('cancel', ['Do they want to',    'cancel it?'], { down: 'No' });
  b.merge('left', 'cancel', { frac: 0.3 });
  b.branch('right', 'cancelflow', ['Before the shop starts: cancel',
    'straight away. While it is being',
    'prepared: send a request and',
    'the shop decides.'], { label: 'Yes', kind: 'io' });
  b.proc('follow', ['Tap an order to follow it: new →',
    'being prepared → ready → handed over.']);
  b.decision('arrived', ['Has it arrived?'], { down: 'Yes' });
  b.branch('right', 'wait', ['Wait for the shop’s update —',
    'they get a notification.'], { label: 'Not yet', kind: 'io' });
  b.circleJump('right', 'A', 'follow', 0.5);
  b.procDB('confirm', ['Tap Confirm receipt — the order is done.', 'Saved to the Database.']);  b.procDB('review', ['Rate each pair in the order:',
    'stars are a must, a few words',
    'and up to 5 photos. One review',
    'per pair — saved to the Database.']);
  b.decision('problem', ['Problem with', 'this order?'], { down: 'No' });
  b.branch('right', 'tellshop', ['Send photos and words —', 'the shop sees it at once.'], { label: 'Yes', kind: 'io' });
  b.circleJump('right', 'D', 'list', 0.7);
  b.decision('again', ['Buy the same pair', 'again?'], { down: 'No' });
  b.branch('right', 'buyagain', ['One tap puts the same size', 'back in the cart.'], { label: 'Yes' });
  b.circleJump('right', 'C', 'list', 0.2);
  b.exit(6, { extra: 'they can shop again' });
  b.note('right', ['An unpaid order can be paid', 'from the same screen.']);
  b.note('left', ['Only pairs from a delivered', 'order can be reviewed.']);
  b.databaseFooter();
});

// 11 — Talk to the shop
page(11, (b) => {
  b.entry(6, ['they tapped the messages icon']);
  b.procDB('list', ['Messages shows one conversation', 'per shop.', 'Loaded from the Database.']);  b.proc('start', ['They can start from a shop,', 'a product, an order,', 'or the messages list.']);  b.procDB('type', ['They type their question,',
    'or pick a ready note for',
    'a first order message.', 'Saved to the Database.']);
  b.decision('custom', ['Ask for a custom', 'pair as well?'], { down: 'No' });
  b.branch('right', 'sizings', ['Send the size, colour and', 'material they want.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'quote', ['The shop answers with a price', 'and when it will be ready.'], 'io');
  b.branchNext('right', 'approve', ['Say yes to the price —', 'the pair goes into making.'], 'io');
  b.io('extras', ['Photos and short clips can go',
    'with the words. Own messages',
    'can be taken back.']);
  b.procDB('reply', ['The shop replies in the same', 'conversation — typing dots show', 'while they write. Ticks turn',    'once the shop has read.', 'Loaded from the Database.']);
  b.merge('right', 'reply', { frac: 0.25 });
  b.decision('done', ['Problem solved?'], { down: 'Yes' });
  b.branch('right', 'followup', ['Send another message —', 'the shop is told at once.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'reply', 0.75);
  b.proc('know', ['A notification and a badge on the bell', 'let them know a reply is waiting.']);
  b.exit(6, { extra: 'they can shop again' });
  b.note('right', ['Photos of the pair', 'help the shop answer', 'faster.']);
  b.note('left', ['Help and support chats live', 'under Profile, not here.']);
  b.databaseFooter();
});

// 12 — Profile and settings
page(12, (b) => {
  b.entry(6, ['they tapped Profile']);
  b.procDB('who', ['Their name, photo, phone and email —', 'name and phone can be edited,', 'a new email needs its link opened',    'before it counts.', 'Loaded from the Database.']);
  b.decision('edit', ['Change the name,', 'photo or phone?'], { down: 'No' });
  b.branch('right', 'saveedit', ['New name and photo save', 'at once. Email needs its', 'link opened first.'], { label: 'Yes', kind: 'io' });
  b.proc('orders', ['My Orders shortcuts: unpaid ·',
    'being prepared · ready ·',
    'to review · cancelled.']);
  b.merge('right', 'orders', { frac: 0.3 });
  b.procDB('foot', ['Foot size — check it, scan again,', 'or type a new size.', 'Loaded from the Database.']);
  b.proc('holds', ['Their pickup reservations — pairs they',
    'are holding at a shop.']);
  b.decision('extend', ['Ask the shop to hold', 'it longer?'], { down: 'No' });
  b.branch('right', 'askextend', ['Send a longer pickup window —', 'the shop decides.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'waitshop', ['Wait for the shop answer —', 'it shows on the hold.'], 'io');  b.circleJump('right', 'A', 'holds', 0.5);
  b.proc('gear', ['The gear opens the full',
    'Settings screen.']);
  b.exit(13);
  b.databaseFooter();
});

// 13 — Settings in detail
page(13, (b) => {
  b.entry(12, ['they tapped the gear', 'for Settings']);
  b.procDB('account', ['Account and Security holds', 'name, phone and email,', 'the password link, fingerprint', 'switch, 2-step codes, devices.', 'Loaded from the Database.']);
  b.proc('switch', ['Extra sign-ins can be kept', 'here to jump between accounts.']);
  b.io('look', ['Theme sheet: follow the device,', 'or pin Light or Dark.']);
  b.proc('addrs', ['Size Your Foot and My Addresses', 'live here too.']);
  b.proc('help', ['Help and support: answers,', 'tell us about a problem,', 'chat with us, plus About,', 'Terms and news with version.']);
  b.decision('bye', ['Log out or', 'delete the account?'], { down: 'Delete the account' });
  b.branch('right', 'logout', ['Log out — asks for confirm,', 'then the sign-in screen shows.'], { label: 'Log out', kind: 'io' });
  b.io('del', ['Deleting asks for confirm first.']);
  b.decision('confirm', ['Do they confirm it?'], { down: 'Yes' });
  b.branch('right', 'keep', ['They stay — nothing changes.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'del', 0.5);  b.procDB('gone', ['The request is sent and',
    'they are signed out.', 'Saved to the Database.']);
  b.end('end', ['END']);
  b.databaseFooter();
});

// 14 — Bulk holds (buying to resell)
page(14, (b) => {
  b.entry(7, ['they tapped Buying to resell']);
  b.io('ask', ['They pick a colour, sizes and', 'how many of each, plus a note.', 'They see a 20 percent deposit', 'estimate before they send it.']);
  b.procDB('sent', ['The request is sent — nothing', 'is held yet.', 'Saved to the Database.']);
  b.decision('sellerok', ['Does the seller', 'say yes?'], { down: 'Yes' });
  b.branch('right', 'declined', ['Seller says no — try fewer', 'pairs or another shop.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'ask', 0.25);
  b.procDB('approved', ['Saying yes opens a 24 hour', 'window and sets the deposit.', 'Loaded from the Database.']);
  b.decision('paid', ['Is the deposit', 'paid in the window?'], { down: 'Yes' });
  b.branch('right', 'lapsed', ['Window closes — nothing', 'is held. Ask again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'ask', 0.8);
  b.io('pay', ['Open the deposit screen, pay', 'with GCash, send the reference', 'and the screenshot.']);
  b.decision('match', ['Does the proof', 'match the GCash app?'], { down: 'Yes' });
  b.branch('right', 'wrong', ['It does not match — fix', 'the proof and send again.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'C', 'pay', 0.5);
  b.procDB('held', ['Confirmed — those pairs now', 'leave the sellable stock.', 'Saved to the Database.']);
  b.decision('collect', ['Did they', 'collect it?'], { down: 'Yes' });
  b.branch('right', 'later', ['The hold stays open', 'until they come.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'D', 'held', 0.5);
  b.procDB('closed', ['Marked collected —', 'the hold closes.', 'Saved to the Database.']);
  b.exit(7, { extra: 'they can shop again' });
  b.note('left', ['Nothing is held until the', 'seller says yes and the', 'deposit is confirmed.']);
  b.note('right', ['A paid deposit is lost', 'if they cancel after approval.']);
  b.databaseFooter();
});

// page 1 gets a legend box under everything else
{
  const b = builders[0];
  const lines = b.legend;
  const h = lineH(lines) + 30;
  const y = Math.max(...b.shapes.map((s) => s.y + s.h)) + 26;
  b.shapes.push({ id: 'p1-legend', kind: 'note', lines, x: 50, y, w: 1000, h });
}

const pages = builders.map((b) => b.finish());

// --------------------------------------------------------------- validation --
const problems = [];
const fail = (msg) => problems.push(msg);
const BANNED = ['supabase', 'authprovider', 'authgate', 'rls', 'otp', 'session', 'token',
  'payload', 'metadata', 'endpoint', 'webhook', 'api ', 'backend', 'frontend',
  'uuid', 'sql', 'query', 'provider', 'migration', 'bucket', 'jsonb', 'commit', 'deploy',
  'repo', 'dart', 'flutter', 'widget', 'null', 'boolean', 'json'];

const shapeIsText = (s) => s.kind === 'title' || s.kind === 'subtitle';
const labelText = (s) => s.lines.join(' ');
const boxesOverlap = (a, b, pad = 8) =>
  a.x < b.x + b.w - pad && b.x < a.x + a.w - pad && a.y < b.y + b.h - pad && b.y < a.y + a.h - pad;

function sidePoint(shape, side, frac = 0.5) {
  switch (side) {
    case 'top': return { x: shape.x + shape.w * frac, y: shape.y };
    case 'bottom': return { x: shape.x + shape.w * frac, y: shape.y + shape.h };
    case 'left': return { x: shape.x, y: shape.y + shape.h * frac };
    case 'right': return { x: shape.x + shape.w, y: shape.y + shape.h * frac };
    default: throw new Error(`bad side ${side}`);
  }
}

function polyline(edge, shapes) {
  const from = shapes.find((s) => s.id === edge.from);
  const to = shapes.find((s) => s.id === edge.to);
  const p0 = sidePoint(from, edge.fromSide || 'bottom', edge.fromFrac ?? 0.5);
  const p1 = sidePoint(to, edge.toSide || 'top', edge.toFrac ?? 0.5);
  const pts = [p0];
  if (edge.waypoints === 'mid') {
    pts.push({ x: p0.x, y: p1.y });
  } else if (p0.x !== p1.x && p0.y !== p1.y) {
    // orthogonal routing: leave along the exit axis, then turn towards the entry
    const verticalFirst = edge.fromSide === 'bottom' || edge.fromSide === 'top';
    pts.push(verticalFirst ? { x: p0.x, y: p1.y } : { x: p1.x, y: p0.y });
  }
  pts.push(p1);
  return pts;
}

/** Point at half the length of a polyline, used to place edge labels. */
function pathMidpoint(pts) {
  const segs = [];
  let total = 0;
  for (let i = 0; i + 1 < pts.length; i++) {
    const len = Math.hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y);
    segs.push(len);
    total += len;
  }
  let target = total / 2;
  for (let i = 0; i < segs.length; i++) {
    if (target <= segs[i]) {
      const t = segs[i] === 0 ? 0 : target / segs[i];
      return {
        x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
        y: pts[i].y + (pts[i + 1].y - pts[i].y) * t,
      };
    }
    target -= segs[i];
  }
  return pts[pts.length - 1];
}

function segmentHitsBox(a, b, box, skip = 15) {
  const len = Math.hypot(b.x - a.x, b.y - a.y);
  if (len < skip * 2) return false;
  const t0 = skip / len;
  const t1 = 1 - t0;
  const x0 = a.x + (b.x - a.x) * t0;
  const y0 = a.y + (b.y - a.y) * t0;
  const x1 = a.x + (b.x - a.x) * t1;
  const y1 = a.y + (b.y - a.y) * t1;
  const pad = 2;
  return Math.max(x0, x1) > box.x + pad && Math.min(x0, x1) < box.x + box.w - pad &&
         Math.max(y0, y1) > box.y + pad && Math.min(y0, y1) < box.y + box.h - pad;
}

const labelBoxes = [];
for (const p of pages) {
  for (const e of p.edges) {
    if (!e.label) continue;
    const pts = polyline(e, p.shapes);
    const mid = pathMidpoint(pts);
    labelBoxes.push({
      page: p.meta.n, edge: e.id, text: e.label,
      x: mid.x - (e.label.length * 6.4 + 10) / 2, y: mid.y - 9,
      w: e.label.length * 6.4 + 10, h: 18,
    });
  }
}

for (const p of pages) {
  const shapes = p.shapes;
  const ids = new Set();
  for (const s of shapes) {
    if (ids.has(s.id)) fail(`${p.meta.n}: duplicate id ${s.id}`);
    ids.add(s.id);
    if (s.x < 0 || s.y < 0 || s.x + s.w > PAGE_W) fail(`${p.meta.n}: ${s.id} outside the page width`);
    if (s.y + s.h > p.pageHeight) fail(`${p.meta.n}: ${s.id} below the page`);
  }
  if (p.meta.n !== 1 && !p.entrySpecs.length) fail(`${p.meta.n}: no entry connector`);
  for (const e of p.edges) {
    if (!ids.has(e.from)) fail(`${p.meta.n}: edge ${e.id} source missing`);
    if (!ids.has(e.to)) fail(`${p.meta.n}: edge ${e.id} target missing`);
  }
  const boxes = shapes.filter((s) => !shapeIsText(s));
  for (let i = 0; i < boxes.length; i++)
    for (let j = i + 1; j < boxes.length; j++)
      if (boxesOverlap(boxes[i], boxes[j])) fail(`${p.meta.n}: ${boxes[i].id} overlaps ${boxes[j].id}`);
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    for (let k = 0; k + 1 < pts.length; k++)
      for (const s of boxes)
        if (s.id !== e.from && s.id !== e.to && segmentHitsBox(pts[k], pts[k + 1], s))
          fail(`${p.meta.n}: edge ${e.id} crosses ${s.id}`);
  }
  for (const lb of labelBoxes.filter((l) => l.page === p.meta.n)) {
    for (const s of boxes) {
      if (lb.x < s.x + s.w && s.x < lb.x + lb.w && lb.y < s.y + s.h && s.y < lb.y + lb.h) {
        fail(`${p.meta.n}: label “${lb.text}” sits on ${s.id}`);
      }
    }
  }
  for (const s of shapes) {
    const text = labelText(s).toLowerCase();
    for (const word of BANNED) if (text.includes(word)) fail(`${p.meta.n}: ${s.id} uses developer wording “${word.trim()}”`);
    const joined = s.lines.join('\n');
    if (/[a-z][A-Z]/.test(joined)) fail(`${p.meta.n}: ${s.id} looks like code: ${joined.slice(0, 40)}`);
    if (/[_(){}<>]|->|=>/.test(joined)) fail(`${p.meta.n}: ${s.id} has code punctuation`);
    const maxChars = Math.floor((s.w - 26) / 6.3);
    for (const line of s.lines) {
      if (line.length > maxChars) fail(`${p.meta.n}: ${s.id} line too wide for its box (${line.length} > ${maxChars}): ${line}`);
    }
  }
  for (const x of p.exitSpecs) {
    const target = pages.find((q) => q.meta.n === x.to);
    if (!target) { fail(`${p.meta.n}: exit to unknown page ${x.to}`); continue; }
    if (!target.entrySpecs.some((en) => en.from.includes(p.meta.n))) fail(`${p.meta.n}: exit to page ${x.to} has no matching entry`);
  }
  for (const en of p.entrySpecs)
    for (const from of en.from) {
      const source = pages.find((q) => q.meta.n === from);
      if (!source) { fail(`${p.meta.n}: entry from unknown page ${from}`); continue; }
      if (!source.exitSpecs.some((x) => x.to === p.meta.n)) fail(`${p.meta.n}: entry from page ${from} has no matching exit`);
    }
  const outLetters = shapes.filter((s) => /-out$/.test(s.id)).map((s) => s.lines[0]);
  const inLetters = shapes.filter((s) => /-in$/.test(s.id)).map((s) => s.lines[0]);
  for (const l of outLetters) if (!inLetters.includes(l)) fail(`${p.meta.n}: circle ${l} has no matching circle`);
  for (const l of inLetters) if (!outLetters.includes(l)) fail(`${p.meta.n}: circle ${l} has no source circle`);
}

// ------------------------------------------------------------- waypoints fix --
for (const p of pages) {
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    e.__waypoints = e.waypoints === 'mid' ? pts.slice(1, -1) : [];
  }
}

// ---------------------------------------------------------------- A4 paper --
// Each page is drawn at its natural size (PAGE_W wide, as tall as the flow
// needs). For printing, that drawing is scaled down — never up — and centred
// on an A4 sheet, with the fonts scaled by the same factor so the page looks
// the same, just smaller. Layout validation runs before this, on real size.
// A page that would need a scale below MIN_A4_SCALE does not fit: split its
// flow across pages with off-page connectors instead of shrinking further.
const pageExtras = (p) => [
  { id: `p${p.meta.n}-title`, kind: 'title', lines: [`${p.meta.n} · ${p.meta.name}`], x: 60, y: 42, w: 700, h: 30 },
  { id: `p${p.meta.n}-subtitle`, kind: 'subtitle', lines: [`SoleVision — what the customer does · page ${p.meta.n} of ${META.length}`], x: 60, y: 76, w: 700, h: 24 },
];

function fitPageA4(p) {
  const all = [...p.shapes, ...pageExtras(p)];
  const minX = Math.min(...all.map((s) => s.x));
  const minY = Math.min(...all.map((s) => s.y));
  const maxX = Math.max(...all.map((s) => s.x + s.w));
  const maxY = Math.max(...all.map((s) => s.y + s.h));
  const scale = Math.min(
    1,
    (A4.w - 2 * A4_MARGIN) / (maxX - minX),
    (A4.h - 2 * A4_MARGIN) / (maxY - minY),
  );
  const dx = (A4.w - (maxX - minX) * scale) / 2 - minX * scale;
  const dy = (A4.h - (maxY - minY) * scale) / 2 - minY * scale;
  const px = (v) => v * scale + dx;
  const py = (v) => v * scale + dy;
  const scaleBox = (s) => ({ ...s, x: px(s.x), y: py(s.y), w: s.w * scale, h: s.h * scale });
  return {
    ...p,
    scale,
    shapes: p.shapes.map(scaleBox),
    extras: pageExtras(p).map(scaleBox),
    edges: p.edges.map((e) => ({ ...e, __waypoints: e.__waypoints.map((q) => ({ x: px(q.x), y: py(q.y) })) })),
    labelBoxes: labelBoxes.filter((l) => l.page === p.meta.n).map((l) => ({
      ...l, x: px(l.x), y: py(l.y), w: l.w * scale, h: l.h * scale,
    })),
  };
}

const sheets = pages.map(fitPageA4);

// Nothing may stick out of the sheet after scaling (rounding at emit gives 1px).
for (const p of sheets) {
  for (const s of [...p.shapes, ...p.extras]) {
    if (s.x < -0.5 || s.y < -0.5 || s.x + s.w > A4.w + 0.5 || s.y + s.h > A4.h + 0.5)
      fail(`${p.meta.n}: ${s.id} does not fit on A4`);
  }
  if (p.scale < MIN_A4_SCALE)
    fail(`${p.meta.n}: needs ${Math.round(p.scale * 100)}% to fit A4 — split this page with off-page connectors`);
}

// ------------------------------------------------------------------ emit XML --
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const xmlLabel = (lines) => esc(lines.join('<br>'));
const styleFor = (kind) => S[kind] ?? (() => { throw new Error(`no style for ${kind}`); })();

function edgeXml(e) {
  const bits = [EDGE];
  // Ports honour the fractional exit/entry points so draw.io renders exactly
  // the validated polyline instead of re-routing from the side midpoint.
  if (e.fromSide) bits.push(
    `exitX=${e.fromSide === 'right' ? 1 : e.fromSide === 'left' ? 0 : (e.fromFrac ?? 0.5)}`,
    `exitY=${e.fromSide === 'bottom' ? 1 : e.fromSide === 'top' ? 0 : (e.fromFrac ?? 0.5)}`,
    'exitPerimeter=0');
  if (e.toSide) bits.push(
    `entryX=${e.toSide === 'right' ? 1 : e.toSide === 'left' ? 0 : (e.toFrac ?? 0.5)}`,
    `entryY=${e.toSide === 'bottom' ? 1 : e.toSide === 'top' ? 0 : (e.toFrac ?? 0.5)}`,
    'entryPerimeter=0');
  if (e.double) bits.push('startArrow=classic', 'startFill=1');
  const style = bits.join(';') + ';';
  const pts = e.__waypoints.length
    ? `\n            <Array as="points">\n${e.__waypoints.map((p) => `              <mxPoint x="${Math.round(p.x)}" y="${Math.round(p.y)}" />`).join('\n')}\n            </Array>`
    : '';
  return `        <mxCell id="${e.id}" value="${e.label ? esc(e.label) : ''}" style="${style}" edge="1" parent="1" source="${e.from}" target="${e.to}">
          <mxGeometry relative="1" as="geometry">${pts}
            <mxPoint x="0" y="-12" as="offset" />
          </mxGeometry>
        </mxCell>`;
}

/** Shrink the style's sizes (text, padding) by the page's A4 scale. */
const scaledStyle = (style, scale) => (scale > 0.999 ? style : style.replace(
  /\b(fontSize|spacingTop|spacingLeft|spacingRight|spacingBottom)=([0-9.]+)/g,
  (m, key, v) => `${key}=${Math.round(Number(v) * scale * 10) / 10}`,
));

function pageXml(p) {
  const cells = [];
  for (const s of [...p.shapes, ...p.extras]) {
    cells.push(`        <mxCell id="${s.id}" value="${xmlLabel(s.lines)}" style="${scaledStyle(styleFor(s.kind), p.scale)}" vertex="1" parent="1">
          <mxGeometry x="${Math.round(s.x)}" y="${Math.round(s.y)}" width="${Math.round(s.w)}" height="${Math.round(s.h)}" as="geometry" />
        </mxCell>`);
  }
  for (const e of p.edges) cells.push(edgeXml(e));
  return `    <diagram id="page-${p.meta.n}" name="${p.meta.n} ${esc(p.meta.name)}">
      <mxGraphModel dx="0" dy="0" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${A4.w}" pageHeight="${A4.h}" math="0" shadow="0">
        <root>
          <mxCell id="0" />
          <mxCell id="1" parent="0" />
${cells.join('\n')}
        </root>
      </mxGraphModel>
    </diagram>`;
}

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" agent="SoleVision journey generator" version="24.7.17">
${sheets.map(pageXml).join('\n')}
</mxfile>
`;

// ------------------------------------------------------------------ emit SVG --
function svgText(lines, cx, cy, fontSize, opts = {}) {
  const anchor = opts.anchor || 'middle';
  const x = opts.x ?? cx;
  const step = fontSize * 1.38;
  const start = cy - ((lines.length - 1) * step) / 2;
  const spans = lines.map((l, i) => `<tspan x="${x}" y="${(start + i * step).toFixed(1)}">${esc(l)}</tspan>`).join('');
  return `<text font-family="Helvetica, Arial, sans-serif" font-size="${fontSize}"${opts.bold ? ' font-weight="bold"' : ''} fill="#000000" text-anchor="${anchor}">${spans}</text>`;
}

const SVG_FILL = { proc: 'none', io: 'none', decision: 'none', terminator: 'none', offpage: 'none', onpage: 'none', db: 'none', note: 'none' };
const SVG_STROKE = { proc: '#000000', io: '#000000', decision: '#000000', terminator: '#000000', offpage: '#000000', onpage: '#000000', db: '#000000', note: '#000000' };

function svgShape(s, scale = 1) {
  const { x, y, w, h } = s;
  const fill = SVG_FILL[s.kind];
  const stroke = SVG_STROKE[s.kind];
  const dash = s.kind === 'note' ? ' stroke-dasharray="5 5"' : '';
  let shape = '';
  if (s.kind === 'io') {
    const slant = Math.min(18, w * 0.12);
    shape = `<polygon points="${x + slant},${y} ${x + w},${y} ${x + w - slant},${y + h} ${x},${y + h}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  } else if (s.kind === 'proc' || s.kind === 'note') {
    shape = `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="0" fill="${fill}" stroke="${stroke}" stroke-width="1.5"${dash}/>`;
  } else if (s.kind === 'decision') {
    shape = `<polygon points="${x + w / 2},${y} ${x + w},${y + h / 2} ${x + w / 2},${y + h} ${x},${y + h / 2}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  } else if (s.kind === 'terminator') {
    shape = `<ellipse cx="${x + w / 2}" cy="${y + h / 2}" rx="${w / 2}" ry="${h / 2}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  } else if (s.kind === 'onpage') {
    shape = `<circle cx="${x + w / 2}" cy="${y + h / 2}" r="${w / 2}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  } else if (s.kind === 'db') {
    const ry = Math.min(14, h / 2);
    shape = `<path d="M${x},${y + ry} L${x},${y + h - ry} A${w / 2},${ry} 0 0,0 ${x + w},${y + h - ry} L${x + w},${y + ry} A${w / 2},${ry} 0 0,0 ${x},${y + ry} Z" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>` + `<ellipse cx="${x + w / 2}" cy="${y + ry}" rx="${w / 2}" ry="${ry}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  } else if (s.kind === 'offpage') {
    const tail = y + h * 0.74;
    shape = `<polygon points="${x},${y} ${x + w},${y} ${x + w},${tail} ${x + w / 2},${y + h} ${x},${tail}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
  }
  const fontSize = (s.kind === 'offpage' ? 12 : 13) * scale;
  const textCy = s.kind === 'offpage' ? y + (h * 0.74) / 2 + 4 : y + h / 2;
  return shape + svgText(s.lines, x + w / 2, textCy, fontSize, { bold: s.kind === 'offpage' || s.kind === 'terminator' });
}

function svgPage(p) {
  const parts = [];
  parts.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${A4.w}" height="${A4.h}" viewBox="0 0 ${A4.w} ${A4.h}">`);
  parts.push(`<rect x="0" y="0" width="${A4.w}" height="${A4.h}" fill="#FFFFFF"/>`);
  parts.push('<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,3 L0,6 z" fill="#000000"/></marker></defs>');
  parts.push(`<rect x="4" y="4" width="${A4.w - 8}" height="${A4.h - 8}" fill="none" stroke="#000000" stroke-width="1"/>`);
  const title = p.extras[0];
  const subtitle = p.extras[1];
  parts.push(svgText(title.lines, 0, title.y + title.h / 2, 22 * p.scale, { anchor: 'start', x: title.x, bold: true }));
  parts.push(svgText(subtitle.lines, 0, subtitle.y + subtitle.h / 2, 12 * p.scale, { anchor: 'start', x: subtitle.x }));
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    const full = e.__waypoints.length ? [pts[0], ...e.__waypoints, pts[pts.length - 1]] : pts;
    parts.push(`<polyline points="${full.map((q) => `${q.x.toFixed(1)},${q.y.toFixed(1)}`).join(' ')}" fill="none" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)"/>`);
  }
  for (const lb of p.labelBoxes) {
    parts.push(svgText([lb.text], lb.x + lb.w / 2, lb.y + lb.h / 2 + 4 * p.scale, 9 * p.scale));
  }
  for (const s of p.shapes) parts.push(svgShape(s, p.scale));
  parts.push('</svg>');
  return parts.join('\n');
}

// ---------------------------------------------------------------------- main --
fs.mkdirSync(PREVIEW_DIR, { recursive: true });
fs.writeFileSync(OUT_FILE, xml, 'utf8');
for (const p of sheets) {
  fs.writeFileSync(path.join(PREVIEW_DIR, `${String(p.meta.n).padStart(2, '0')}-${p.meta.slug}.svg`), svgPage(p), 'utf8');
}

// optional: rasterise every page with headless Chrome (--png)
const wantPng = process.argv.includes('--png');
if (wantPng) {
  const { spawnSync } = await import('node:child_process');
  const chromeCandidates = [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    process.env.LOCALAPPDATA ? `${process.env.LOCALAPPDATA}/Google/Chrome/Application/chrome.exe` : null,
  ].filter(Boolean);
  const chrome = chromeCandidates.find((p) => fs.existsSync(p));
  if (!chrome) {
    console.log('chrome not found — skipped PNG previews');
  } else {
    const profile = path.join(PREVIEW_DIR, '.chrome-profile');
    for (const p of sheets) {
      const svg = path.join(PREVIEW_DIR, `${String(p.meta.n).padStart(2, '0')}-${p.meta.slug}.svg`);
      const png = svg.replace(/\.svg$/, '.png');
      const res = spawnSync(chrome, [
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2', '--default-background-color=00000000',
        `--user-data-dir=${profile}`,
        `--screenshot=${png}`,
        `--window-size=${A4.w},${A4.h}`,
        `file:///${svg.replace(/\\/g, '/')}`,
      ], { stdio: 'ignore' });
      if (res.status !== 0 || !fs.existsSync(png)) console.log(`  ! PNG failed for page ${p.meta.n}`);
    }
    fs.rmSync(profile, { recursive: true, force: true });
  }
}

const shapes = pages.reduce((a, p) => a + p.shapes.length, 0);
const edges = pages.reduce((a, p) => a + p.edges.length, 0);
const out = [];
out.push(`wrote docs/diagrams/customer-journey-flowchart.drawio — ${pages.length} pages, ${shapes} shapes, ${edges} connectors`);
out.push(`wrote ${pages.length} SVG previews to docs/diagrams/previews/`);
out.push(`one page = one A4 sheet (${A4.w} x ${A4.h}); scale per page: ${sheets.map((p) => `${p.meta.n} ${Math.round(p.scale * 100)}%`).join(' · ')}`);
out.push(`smallest body text prints at ${(13 * Math.min(...sheets.map((p) => p.scale)) * 0.72).toFixed(1)} pt`);
if (problems.length) {
  out.push('');
  out.push(`layout check: ${problems.length} problem(s)`);
  problems.forEach((q) => out.push(`  - ${q}`));
  console.log(out.join('\n'));
  process.exitCode = 1;
} else {
  out.push('');
  out.push('layout check: clean');
  console.log(out.join('\n'));
}

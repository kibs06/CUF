#!/usr/bin/env node
/**
 * SoleVision — customer journey flowchart generator (client-facing, plain English).
 *
 * Writes docs/diagrams/customer-journey-flowchart.drawio (multi-page) and one
 * SVG preview per page into docs/diagrams/previews/.
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
const OUT_FILE = path.join(ROOT, 'docs', 'diagrams', 'admin-journey-flowchart.drawio');
const PREVIEW_DIR = path.join(ROOT, 'docs', 'diagrams', 'admin-previews');

// ---------------------------------------------------------------- geometry --
const SPINE = { x: 420, w: 290 };
const LEFT = { x: 30, w: 250 };
const RIGHT = { x: 825, w: 240 };
const PAGE_W = 1100;
const TOP = 130;
const GAP = 68;
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
const EDGE = 'edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=0;html=1;endArrow=classic;endFill=1;strokeColor=light-dark(#000000,#FFFFFF);strokeWidth=1.5;fontSize=9;fontColor=light-dark(#000000,#FFFFFF);labelBackgroundColor=none;';

// ------------------------------------------------------------------- pages --
const META = [
  { n: 1, name: 'Sign in', code: 'SI', slug: 'sign-in' },
  { n: 2, name: 'Dashboard', code: 'Dd', slug: 'dashboard' },
  { n: 3, name: 'Sellers and users', code: 'SU', slug: 'sellers-and-users' },
  { n: 4, name: 'Products and 3D models', code: 'P3M', slug: 'products-and-3d-models' },
  { n: 5, name: 'Orders and money', code: 'OM', slug: 'orders-and-money' },
  { n: 6, name: 'Complaints and banners', code: 'CB', slug: 'complaints-and-banners' },
  { n: 7, name: 'Numbers, audit and settings', code: 'NAS', slug: 'numbers-audit-and-settings' },
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

  // Paper style (p.53): parallelogram = user input or system message.
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
    this._stack(s);
    this.pendingSpineLabel = opts.down;
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
    this.edge(last.id, s.id, { fromSide: 'bottom', toSide: 'top', label: this.pendingSpineLabel });
    this.pendingSpineLabel = null;
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
    const size = 48;
    const x = Math.round(d.x + d.w / 2 - size / 2);
    const y = d.y + d.h + 24;
    const c = this.add('onpage', `db1-${name}`, ['DB1'], x, y, size, size);
    this.edge(d.id, c.id, { fromSide: 'bottom', toSide: 'top', label: this.pendingSpineLabel });
    this.pendingSpineLabel = null;
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
    const g = this.add('proc', 'social-google', gLines, 30, gy, W, gh);
    this.edge(d.id, g.id, { fromSide: 'left', toSide: 'right', label: 'Yes' });
    const dg = this.add('onpage', 'db1-social-google', ['DB1'], 340, gy - 60, 48, 48);
    this.edge(g.id, dg.id, { fromSide: 'top', toSide: 'bottom' });
    const fy = gy + gh + GAP;
    const f = this.add('proc', 'social-facebook', fLines, 30, fy, W, fh);
    this.edge(d.id, f.id, { fromSide: 'left', fromFrac: 0.65, toSide: 'right', toFrac: 0.15, jog: 246, label: 'Yes' });
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
    const noteLines = ['DB steps touch the Database;', 'DB1 marks where in the flow.'];
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

// 1 — Sign in
page(1, (b) => {
  b.terminator('start', ['START']);
  b.proc('open', ['The admin opens the portal', 'sign-in screen.']);
  b.io('pick', ['Pick email sign-in, or Continue', 'with Google or Facebook.']);
  b.io('creds', ['They type their email', 'and their password.']);
  b.decisionDB('valid', ['Do the details', 'check out in the Database?'], { down: 'Yes' });
  b.branch('right', 'fixbox', ['See the error on', 'the box and fix it.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'creds', 0.5);
  b.decisionDB('allowed', ['An admin account', 'in good standing', 'in the Database?'], { down: 'Yes' });
  b.branch('right', 'denied', ['They see Access denied —', 'this portal is for admins only.'], { label: 'No', kind: 'io' });
  b.branch('left', 'paused', ['A paused admin sees why,', 'then signs out.'], { label: 'No', kind: 'io' });
  b.decision('mfa', ['A second step', 'code needed?'], { down: 'No' });
  b.branch('right', 'code', ['They type the 6-digit code', 'from the authenticator app —', 'a wrong one shows a hint.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'retry', ['Expired code — wait for', 'the next one and try again.'], 'io');
  b.proc('dash', ['They land on the Dashboard.']);
  b.merge('right', 'dash');
  b.exit(2);
  b.note('left', ['Social sign-in works only', 'for existing admin accounts.']);  b.note('right', ['Too many wrong tries locks',
    'the screen for a while.']);
  b.databaseFooter();
  b.legend = [
    'How to read this chart:',
    'oval = the start or the end  ·  rectangle = a step  ·  parallelogram = typing or a message  ·  diamond = a question',
    'pentagon holds a page code — the top one is this page, the rest say where to turn',
    'small circle with a letter = the flow jumps back to the same letter',
    'DB pentagon = go to the Database  ·  DB1 circle = Database step in the flow',
  ];
});

// 2 — Dashboard
page(2, (b) => {
  b.entryRow([
    { from: [1], phrase: ['they signed in'] },
    { from: [3], phrase: ['sellers done'] },
    { from: [4], phrase: ['models done'] },
    { from: [5], phrase: ['orders done'] },
    { from: [6], phrase: ['care done'] },
    { from: [7], phrase: ['audit done'] },
  ]);
  b.wideProc('home', ['The Dashboard shows sales, sellers waiting,',
    'orders needing work and recent sign-ins.']);
  b.proc('triage', ['They scan what needs', 'work first.']);
  b.procDB('pipes', ['The pipeline counts action needed,', 'in prep, shipped and delivered —', 'each opens its order list.']);
  b.proc('quick', ['Clear seller asks can be', 'taken right from the Dashboard.']);
  b.decision('sellers', ['Sellers waiting', 'for review?'], { down: 'No' });
  b.branchExit('right', 3, { label: 'Yes' });
  b.decision('goods', ['Products or 3D asks', 'need work?'], { down: 'No' });
  b.branchExit('right', 4, { label: 'Yes' });
  b.decision('orders', ['Orders or money', 'need work?'], { down: 'No' });
  b.branchExit('right', 5, { label: 'Yes' });
  b.decision('care', ['Banners or complaints', 'need work?'], { down: 'No' });
  b.branchExit('right', 6, { label: 'Yes' });
  b.decision('books', ['Numbers, audit', 'or settings?'], { down: 'No' });
  b.branchExit('right', 7, { label: 'Yes' });
  b.proc('monitor', ['They keep an eye on the numbers', 'and hop between screens.']);
  b.decision('done', ['Done for', 'the day?'], { down: 'Yes' });
  b.branch('right', 'stay', ['They stay — the numbers', 'keep updating.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'monitor', 0.5);
  b.proc('bye', ['They sign out — see you', 'at the next shift.']);
  b.end('end', ['END']);
  b.note('left', ['Quick approve sits on the', 'Dashboard for clear cases.']);  b.note('right', ['Tapping a pipeline number',
    'opens Orders pre-filtered.']);
  b.databaseFooter();
});

// 3 — Sellers and users
page(3, (b) => {
  b.entry(2, ['they opened Sellers', 'or Users']);
  b.proc('queue', ['Asks wait newest first —', 'tabs for pending, approved,', 'rejected or all.']);
  b.io('review', ['They open an ask to see the shop,', 'its papers, photos and owner.']);
  b.decision('approve', ['Take the shop on?'], { down: 'Yes' });
  b.branch('right', 'reject', ['They turn it down with', 'a short reason the owner sees.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'queue', 0.5);
  b.io('users', ['On Users they find people', 'by name or email — shoppers,', 'shop owners, fellow admins.']);
  b.io('flags', ['Tabs and filters split shoppers,', 'sellers, admins — active or paused.']);
  b.procDB('detail', ['They open a person to see orders,', 'shops, past trouble —', 'failed sign-ins show too.']);
  b.decision('trouble', ['Causing trouble?'], { down: 'No' });
  b.branch('right', 'suspend', ['They pause it with a reason', 'on record — no more sign-ins.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'restore', ['Quiet again — they lift', 'the pause.'], 'io');
  b.proc('back', ['Queues clear — back to base.']);
  b.exit(2, { extra: 'back to the Dashboard' });  b.note('left', ['Shops stay shut till approved —',
    'owners can fix and ask again.']);
  b.databaseFooter();
});

// 4 — Products and 3D models
page(4, (b) => {
  b.entry(2, ['they opened Products', 'and 3D asks']);
  b.proc('catalogue', ['Products sit grouped by shop —', 'grid or list, search, filter', 'by kind or shelf state.']);
  b.proc('detail', ['They open a product for photos,', 'price, sizes and reviews.']);
  b.decision('live', ['Still fit for', 'the shelf?'], { down: 'Yes' });
  b.branch('right', 'hide', ['They take it down — confirm,', 'hidden from shoppers,', 'but kept on record.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'B', 'catalogue', 0.5);
  b.proc('asks', ['Model asks wait in their own list —', 'waiting, done and closed.']);
  b.proc('claim', ['They take an ask and shape', 'the 3D pair from shop photos.']);
  b.decision('ready', ['Model good to go?'], { down: 'Yes' });
  b.branch('right', 'decline', ['They turn it down with', 'a note the shop gets told.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'claim', 0.5);  b.procDB('fulfil', ['They load the model with its',
    'AR try-on — shoppers can',
    'spin it now.', 'Saved to the Database.']);
  b.io('tidy', ['Worn models go by right-click —', 'confirm, then file and row go.']);
  b.exit(2, { extra: 'back to the Dashboard' });
  b.note('left', ['A hidden product keeps its', 'reviews for its return.']);  b.note('right', ['Each ask carries shop photos',
    'to model against.']);
  b.databaseFooter();
});

// 5 — Orders and site care
page(5, (b) => {
  b.entry(2, ['they opened Orders,', 'or Money']);
  b.proc('orders', ['Orders line up newest first —', 'search, dates and stage filters', 'find the stuck ones.']);
  b.proc('detail', ['They open an order to see items,', 'payment, address and stage.']);
  b.decision('move', ['Move it a stage on?'], { down: 'Yes' });
  b.branch('right', 'hold', ['Not yet — they leave it', 'and check back later.'], { label: 'No', kind: 'io' });
  b.circleJump('right', 'A', 'detail', 0.5);
  b.proc('pack', ['They shift the stage as the shop', 'packs, ships and hands over.']);
  b.proc('money', ['On Money they scan the piles —', 'paid, waiting, failed,', 'out of date and called off.']);
  b.proc('cards', ['Top cards sum paid takings,', 'fees and the failed pile,', 'with a daily chart.']);
  b.decisionDB('moneyok', ['Does the money', 'add up in the Database?'], { down: 'Yes' });
  b.branch('right', 'chase', ['Failed or odd ones get', 'a closer look with the order', 'open beside them.'], { label: 'No', kind: 'io' });
  b.io('sheet', ['The list can leave as a sheet', 'for the books.']);
  b.exit(2, { extra: 'back to the Dashboard' });
  b.note('left', ['Money trouble links back', 'to the order it came from.']);
  b.note('left', ['Bulk deposits and refunds move', 'through these same piles.']);  b.note('right', ['A pipeline tap on the Dashboard',
    'lands here pre-filtered.']);
  b.databaseFooter();
});

// 6 — Complaints and banners
page(6, (b) => {
  b.entry(2, ['they opened Complaints', 'or Banners']);
  b.proc('inbox', ['Flags land newest first —', 'rude words, spam and scams,', 'fake items and knock-offs.']);
  b.proc('urgent', ['Red flags and counters point', 'at the urgent ones.']);
  b.io('read', ['They open one to see who told,', 'who it is about and the proof.']);
  b.decision('fair', ['Did someone break', 'the house rules?'], { down: 'No' });
  b.branch('right', 'act', ['They warn, hide the item,', 'pause the seller or refund,', 'then thank the one who told.'], { label: 'Yes', kind: 'io' });
  b.branchNext('right', 'refund', ['Refund issued — the money', 'moves back to the buyer.'], 'io');
  b.io('close', ['They mark it fixed — saying', 'what was done — or let it go,', 'reason on record.']);
  b.merge('right', 'close');
  b.io('tell', ['Word goes back to the one', 'who told — ready words', 'or the office\u2019s own.']);
  b.io('flags', ['On Banners they shape the home', 'strip — photo, words, link, dates.']);
  b.io('order', ['They nudge the order, set dates', 'and flip each flag on or off.']);
  b.decisionDB('linkok', ['Does every link', 'have its target', 'in the Database?'], { down: 'Yes' });
  b.branch('right', 'fixlink', ['They fill the missing target', 'or drop the link.'], { label: 'No', kind: 'io' });
  b.io('retire', ['Worn-out flags get erased', 'after a confirm.']);
  b.exit(2, { extra: 'back to the Dashboard' });
  b.note('left', ['Nasty cases can pause a seller', 'straight from the complaint.']);  b.note('right', ['Old flags can be erased',
    'when the season turns.']);
  b.databaseFooter();
});

// 7 — Numbers, audit and settings
page(7, (b) => {
  b.entry(2, ['they opened Numbers,', 'Audit or Settings']);
  b.io('numbers', ['On Numbers they pick 7, 30 or 90', 'days — takings, top pairs,', 'shares of order stages.']);
  b.io('audit', ['On Audit they pick a trail — shops,', 'money, safety, sign-ins, doings —', 'each with its own filters.']);
  b.io('sheet', ['Any trail can leave as a sheet', 'for the books.']);
  b.io('profile', ['On Settings they save their name,', 'swap the password — six signs', 'or more, typed twice the same.']);
  b.decisionDB('safe', ['Is the second step', 'on for this account', 'in the Database?'], { down: 'Yes' });
  b.branch('right', 'addmfa', ['They link the authenticator', 'app for the extra code.'], { label: 'No', kind: 'io' });
  b.proc('danger', ['Lost phone — they sign out', 'on every device at once.']);
  b.exit(2, { extra: 'back to the Dashboard' });  b.note('left', ['The audit shows who did what,',
    'and when they did it.']);
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
    // orthogonal routing: leave along the exit axis, then turn towards the entry.
    // A `jog` x pins the vertical leg of a horizontal-first edge to its own
    // lane so it never rides another box's border or shares a stub.
    const verticalFirst = edge.fromSide === 'bottom' || edge.fromSide === 'top';
    if (verticalFirst) {
      pts.push({ x: p0.x, y: p1.y });
    } else if (edge.jog != null) {
      pts.push({ x: edge.jog, y: p0.y }, { x: edge.jog, y: p1.y });
    } else {
      pts.push({ x: p1.x, y: p0.y });
    }
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
  // No two connectors may run on top of each other: trim every segment back
  // from its endpoints (so edges meeting at a shared box are fine), then flag
  // any remaining collinear overlap, or any segment riding a box border.
  const trimSeg = (a, b) => {
    const len = Math.hypot(b.x - a.x, b.y - a.y);
    if (len < 34) return null;
    const t = 15 / len;
    return [{ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t },
            { x: b.x - (b.x - a.x) * t, y: b.y - (b.y - a.y) * t }];
  };
  const trimmed = [];
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    for (let k = 0; k + 1 < pts.length; k++) {
      const t = trimSeg(pts[k], pts[k + 1]);
      if (t) trimmed.push({ e, a: t[0], b: t[1] });
    }
  }
  const overlap1d = (a1, a2, b1, b2) => Math.min(a2, b2) - Math.max(a1, b1);
  for (let i = 0; i < trimmed.length; i++) for (let j = i + 1; j < trimmed.length; j++) {
    const A = trimmed[i], B = trimmed[j];
    if (A.e.id === B.e.id) continue;
    if (A.e.from === B.e.from || A.e.from === B.e.to || A.e.to === B.e.from || A.e.to === B.e.to) continue;
    const aV = Math.abs(A.a.x - A.b.x) < 1, bV = Math.abs(B.a.x - B.b.x) < 1;
    if (aV && bV && Math.abs(A.a.x - B.a.x) < 3) {
      if (overlap1d(A.a.y, A.b.y, B.a.y, B.b.y) > 8) fail(`${p.meta.n}: edge ${A.e.id} overlaps ${B.e.id}`);
    } else if (!aV && !bV && Math.abs(A.a.y - B.a.y) < 3) {
      if (overlap1d(A.a.x, A.b.x, B.a.x, B.b.x) > 8) fail(`${p.meta.n}: edge ${A.e.id} overlaps ${B.e.id}`);
    }
  }
  for (const t of trimmed) {
    const v = Math.abs(t.a.x - t.b.x) < 1, h = Math.abs(t.a.y - t.b.y) < 1;
    for (const s of boxes) {
      if (s.w < 60 || s.id === t.e.from || s.id === t.e.to) continue;
      if (v && (Math.abs(t.a.x - s.x) < 3 || Math.abs(t.a.x - (s.x + s.w)) < 3)) {
        if (overlap1d(t.a.y, t.b.y, s.y, s.y + s.h) > 8) fail(`${p.meta.n}: edge ${t.e.id} rides ${s.id}`);
      }
      if (h && (Math.abs(t.a.y - s.y) < 3 || Math.abs(t.a.y - (s.y + s.h)) < 3)) {
        if (overlap1d(t.a.x, t.b.x, s.x, s.x + s.w) > 8) fail(`${p.meta.n}: edge ${t.e.id} rides ${s.id}`);
      }
    }
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
    // Every bent edge gets explicit waypoints matching the validated polyline,
    // so draw.io renders exactly this path instead of auto-routing through boxes.
    e.__waypoints = pts.slice(1, -1);
  }
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

function pageXml(p) {
  const cells = [];
  const extras = [
    { id: `p${p.meta.n}-title`, kind: 'title', lines: [`${p.meta.n} · ${p.meta.name}`], x: 60, y: 42, w: 700, h: 30 },
    { id: `p${p.meta.n}-subtitle`, kind: 'subtitle', lines: [`SoleVision — what the admin does · page ${p.meta.n} of ${META.length}`], x: 60, y: 76, w: 700, h: 24 },
  ];
  for (const s of [...p.shapes, ...extras]) {
    cells.push(`        <mxCell id="${s.id}" value="${xmlLabel(s.lines)}" style="${styleFor(s.kind)}" vertex="1" parent="1">
          <mxGeometry x="${Math.round(s.x)}" y="${Math.round(s.y)}" width="${Math.round(s.w)}" height="${Math.round(s.h)}" as="geometry" />
        </mxCell>`);
  }
  for (const e of p.edges) cells.push(edgeXml(e));
  return `    <diagram id="page-${p.meta.n}" name="${p.meta.n} ${esc(p.meta.name)}">
      <mxGraphModel dx="0" dy="0" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${PAGE_W}" pageHeight="${p.pageHeight}" math="0" shadow="0">
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
${pages.map(pageXml).join('\n')}
</mxfile>
`;

// ------------------------------------------------------------------ emit SVG --
function svgText(lines, cx, cy, fontSize, opts = {}) {
  const anchor = opts.anchor || 'middle';
  const x = opts.x ?? cx;
  const step = fontSize + 5;
  const start = cy - ((lines.length - 1) * step) / 2;
  const spans = lines.map((l, i) => `<tspan x="${x}" y="${(start + i * step).toFixed(1)}">${esc(l)}</tspan>`).join('');
  return `<text font-family="Helvetica, Arial, sans-serif" font-size="${fontSize}"${opts.bold ? ' font-weight="bold"' : ''} fill="#000000" text-anchor="${anchor}">${spans}</text>`;
}

const SVG_FILL = { proc: 'none', io: 'none', decision: 'none', terminator: 'none', offpage: 'none', onpage: 'none', db: 'none', note: 'none' };
const SVG_STROKE = { proc: '#000000', io: '#000000', decision: '#000000', terminator: '#000000', offpage: '#000000', onpage: '#000000', db: '#000000', note: '#000000' };

function svgShape(s) {
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
  const fontSize = s.kind === 'offpage' ? 12 : 13;
  const textCy = s.kind === 'offpage' ? y + (h * 0.74) / 2 + 4 : y + h / 2;
  return shape + svgText(s.lines, x + w / 2, textCy, fontSize, { bold: s.kind === 'offpage' || s.kind === 'terminator' });
}

function svgPage(p) {
  const parts = [];
  parts.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${PAGE_W}" height="${p.pageHeight}" viewBox="0 0 ${PAGE_W} ${p.pageHeight}">`);
  parts.push(`<rect x="0" y="0" width="${PAGE_W}" height="${p.pageHeight}" fill="#FFFFFF"/>`);
  parts.push('<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,3 L0,6 z" fill="#000000"/></marker></defs>');
  parts.push(`<rect x="4" y="4" width="${PAGE_W - 8}" height="${p.pageHeight - 8}" fill="none" stroke="#000000" stroke-width="1"/>`);
  parts.push(svgText([`${p.meta.n} · ${p.meta.name}`], 0, 57, 22, { anchor: 'start', x: 60, bold: true }));
  parts.push(svgText([`SoleVision — what the admin does · page ${p.meta.n} of ${META.length}`], 0, 88, 12, { anchor: 'start', x: 60 }));
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    const full = e.__waypoints.length ? [pts[0], ...e.__waypoints, pts[pts.length - 1]] : pts;
    parts.push(`<polyline points="${full.map((q) => `${q.x.toFixed(1)},${q.y.toFixed(1)}`).join(' ')}" fill="none" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)"/>`);
  }
  for (const lb of labelBoxes.filter((l) => l.page === p.meta.n)) {
    parts.push(svgText([lb.text], lb.x + lb.w / 2, lb.y + lb.h / 2 + 4, 9));
  }
  for (const s of p.shapes) parts.push(svgShape(s));
  parts.push('</svg>');
  return parts.join('\n');
}

// ---------------------------------------------------------------------- main --
fs.mkdirSync(PREVIEW_DIR, { recursive: true });
fs.writeFileSync(OUT_FILE, xml, 'utf8');
for (const p of pages) {
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
    for (const p of pages) {
      const svg = path.join(PREVIEW_DIR, `${String(p.meta.n).padStart(2, '0')}-${p.meta.slug}.svg`);
      const png = svg.replace(/\.svg$/, '.png');
      const res = spawnSync(chrome, [
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=2', '--default-background-color=00000000',
        `--user-data-dir=${profile}`,
        `--screenshot=${png}`,
        `--window-size=${PAGE_W},${p.pageHeight}`,
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
out.push(`wrote docs/diagrams/admin-journey-flowchart.drawio — ${pages.length} pages, ${shapes} shapes, ${edges} connectors`);
out.push(`wrote ${pages.length} SVG previews to docs/diagrams/admin-previews/`);
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

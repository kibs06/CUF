#!/usr/bin/env node
/**
 * SoleVision — seller journey flowchart generator (client-facing, plain English).
 *
 * Writes docs/diagrams/seller-journey-flowchart.drawio (multi-page) and one
 * SVG preview per page into docs/diagrams/seller-previews/.
 *
 * Conventions, matching the layout the capstone document already uses:
 *   - rounded rectangle = a step
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
const OUT_FILE = path.join(ROOT, 'docs', 'diagrams', 'seller-journey-flowchart.drawio');
const PREVIEW_DIR = path.join(ROOT, 'docs', 'diagrams', 'seller-previews');

// ---------------------------------------------------------------- geometry --
const SPINE = { x: 420, w: 290 };
const LEFT = { x: 30, w: 250 };
const RIGHT = { x: 825, w: 240 };
const PAGE_W = 1100;
const TOP = 130;
const GAP = 42;
const LINE = 19;
const PROC_PAD = 46;
const OFF_PAD = 54;
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
  note: `rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=4 4;fillColor=none;${ADAPT}fontSize=12;align=left;verticalAlign=middle;spacingLeft=10;spacingRight=10;`,
  title: 'text;html=1;fontSize=22;fontStyle=1;align=left;verticalAlign=middle;fontColor=light-dark(#000000,#FFFFFF);',
  subtitle: 'text;html=1;fontSize=12;align=left;verticalAlign=middle;fontColor=light-dark(#000000,#FFFFFF);',
};
const EDGE = 'edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=classic;endFill=1;strokeColor=light-dark(#000000,#FFFFFF);strokeWidth=1.5;fontSize=11;fontColor=light-dark(#000000,#FFFFFF);labelBackgroundColor=none;';

// ------------------------------------------------------------------- pages --
const META = [
  { n: 1, name: 'Open the app', slug: 'open-the-app' },
  { n: 2, name: 'Apply to sell', slug: 'apply-to-sell' },
  { n: 3, name: 'Confirm the email', slug: 'confirm-the-email' },
  { n: 4, name: 'Set up the store', slug: 'set-up-the-store' },
  { n: 5, name: 'Sign in', slug: 'sign-in' },
  { n: 6, name: 'Dashboard', slug: 'dashboard' },
  { n: 7, name: 'POS sale', slug: 'pos-sale' },
  { n: 8, name: 'Products', slug: 'products' },
  { n: 9, name: 'Inventory', slug: 'inventory' },
  { n: 10, name: 'Orders', slug: 'orders' },
  { n: 11, name: 'Custom orders and messages', slug: 'custom-orders-and-messages' },
  { n: 12, name: 'Sales', slug: 'sales' },
  { n: 13, name: 'Store profile', slug: 'store-profile' },
];
const byNumber = (n) => META.find((m) => m.n === n);
const listNumbers = (list) =>
  list.length === 1 ? `${list[0]}` : list.length === 2 ? `${list[0]} or ${list[1]}` : `${list.slice(0, -1).join(', ')} or ${list[list.length - 1]}`;
const exitLines = (n) => [`Continue on page ${n}`, byNumber(n).name];

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
    const s = this.add('proc', name, lines, col.x, top, col.w, h);
    this.edge(d.id, s.id, {
      fromSide: side === 'left' ? 'left' : 'right',
      toSide: side === 'left' ? 'right' : 'left',
      label: opts.label,
    });
    this.col[side] = s.y + s.h + GAP;
    this.colLast[side] = s;
    return s;
  }

  branchNext(side, name, lines) {
    const prev = this.colLast[side];
    if (!prev) throw new Error(`branchNext(${side}) without a branch`);
    const h = lineH(lines) + PROC_PAD;
    const s = this.add('proc', name, lines, prev.x, this.col[side], prev.w, h);
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
    const s = this.add('offpage', `exit-${toNumber}-${side}`, lines, col.x + 20, top, col.w - 40, h);
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
    const lines = [froms.length > 1 ? `From pages ${listNumbers(froms)}` : `From page ${froms[0]}`, ...phrase];
    const h = lineH(lines) + OFF_PAD;
    const s = this.add('offpage', `entry-${froms.join('-')}`, lines, SPINE.x, TOP, SPINE.w, h);
    this.spineY = s.y + s.h + GAP;
    this.spineLast = s;
    this.entrySpecs.push({ from: froms, id: s.id });
    return s;
  }

  entryRow(specs) {
    const n = specs.length;
    const gap = 40;
    const w = (1000 - gap * (n - 1)) / n;
    let h = 0;
    const made = [];
    specs.forEach((spec, i) => {
      const x = 50 + i * (w + gap);
      const lines = [spec.from.length > 1 ? `From pages ${listNumbers(spec.from)}` : `From page ${spec.from[0]}`, ...spec.phrase];
      const sh = lineH(lines) + OFF_PAD;
      h = Math.max(h, sh);
      const s = this.add('offpage', `entry-${spec.from.join('-')}`, lines, x, TOP, w, sh);
      this.entrySpecs.push({ from: spec.from, id: s.id });
      made.push(s);
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
    const n = numbers.length;
    const gap = 22;
    const w = (1000 - gap * (n - 1)) / n;
    const linesList = numbers.map((t) => exitLines(t));
    const h = Math.max(...linesList.map((l) => lineH(l) + OFF_PAD));
    const y = this.spineY;
    numbers.forEach((t, i) => {
      const x = 50 + i * (w + gap);
      const s = this.add('offpage', `exit-${t}`, linesList[i], x, y, w, h);
      const frac = (x + w / 2 - last.x) / last.w;
      this.edge(last.id, s.id, { fromSide: 'bottom', toSide: 'top', fromFrac: frac });
      this.exitSpecs.push({ to: t, id: s.id });
    });
    this.spineY = y + h + GAP;
    return this;
  }

  exit(toNumber, opts = {}) {
    const last = this.spineLast;
    const lines = [...exitLines(toNumber), ...(opts.extra ? [opts.extra] : [])];
    const h = lineH(lines) + OFF_PAD;
    const s = this.add('offpage', `exit-${toNumber}`, lines, SPINE.x, this.spineY, SPINE.w, h);
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
    const y = proc.y + proc.h + 12;
    const c = this.add('onpage', `db1-${name}`, ['DB1'], x, y, size, size);
    this.edge(proc.id, c.id, { fromSide: 'bottom', toSide: 'top' });
    this.spineLast = c;
    this.spineY = y + size + GAP;
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
    const y = d.y + d.h + 12;
    const c = this.add('onpage', `db1-${name}`, ['DB1'], x, y, size, size);
    this.edge(d.id, c.id, { fromSide: 'bottom', toSide: 'top', label });
    this.spineLast = c;
    this.spineY = y + size + GAP;
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
    this.edge(d.id, g.id, { fromSide: 'left', toSide: 'right', label: 'Google' });
    const dg = this.add('onpage', 'db1-social-google', ['DB1'], 340, gy - 60, 48, 48);
    this.edge(g.id, dg.id, { fromSide: 'top', toSide: 'bottom' });
    const fy = gy + gh + GAP;
    const f = this.add('proc', 'social-facebook', fLines, 30, fy, W, fh);
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
    const pent = this.add('offpage', 'db', ['DB'], 50, y, 120, h);
    const cyl = this.add('db', 'database', ['Database'], 190, y, 200, h);
    const size = 48;
    const c = this.add('onpage', 'db1-legend', ['DB1'], 410, y + (h - size) / 2, size, size);
    this.edge(pent.id, cyl.id, { fromSide: 'right', toSide: 'left', double: true });
    this.edge(cyl.id, c.id, { fromSide: 'right', toSide: 'left', double: true });
    const noteLines = ['DB steps touch the Database;', 'DB1 marks where in the flow.'];
    const nh = lineH(noteLines) + 34;
    const ny = y + (h - nh) / 2;
    this.noteCount += 1;
    const note = this.add('note', 'db-note', noteLines, 480, ny, 330, nh);
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
  b.proc('open', ['The seller opens the app', 'on their phone.']);
  b.proc('load', ['A short loading screen', 'checks for updates.']);
  b.decision('signed', ['Are they already', 'signed in?'], { down: 'No' });
  b.branchExit('right', 6, { label: 'Yes' });
  b.decision('firsttime', ['First time', 'opening it?'], { down: 'No' });
  b.branch('right', 'slides', ['Show the three welcome', 'slides — they can skip them.'], { label: 'Yes' });
  b.circleJump('right', 'A', 'screen', 0.5);
  b.proc('screen', ['Show the Apply to sell and', 'Sign in screen with Continue', 'with Google and Facebook.', 'One screen — the video', 'keeps playing.']);
  b.decision('whichtap', ['What do they tap?', 'Apply, Sign in,', 'Google or Facebook?']);
  b.branchExit('right', 2, { label: 'Apply' });
  b.branchExit('left', 5, { label: 'Sign in' });
  b.note('left', ['Shoppers use the same screen', 'and pick the shopper side.']);
  b.note('right', ['Sign in is a switch on the', 'same screen — the video', 'never restarts.']);
  b.databaseFooter();
  b.legend = [
    'How to read this chart:',
    'oval = the start or the end  ·  rectangle = a step  ·  diamond = a question',
    'pentagon = the story continues on the page written inside it',
    'small circle with a letter = the flow jumps back to the same letter',
    'DB pentagon = go to the Database  ·  DB1 circle = Database step in the flow',
  ];
});

// 2 — Apply to sell
page(2, (b) => {
  b.entry(1, ['they tapped Apply,', 'Google or Facebook']);
  b.decision('method', ['How do they sign up?'], { down: 'Fill in the form' });
  b.socialPair('create');
  b.proc('form', ['They fill in the seller form:', 'name, shop name, email,', 'phone if they like,', 'password plus confirm,', 'a strength hint as they type,', 'and accept the Terms.']);
  b.decision('filled', ['Is every box filled', 'in right, Terms accepted?'], { down: 'Yes' });
  b.branch('right', 'fixbox', ['Show a message on the box', 'that needs fixing.'], { label: 'No' });
  b.circleJump('right', 'A', 'form', 0.28);
  b.decisionDB('emailused', ['Is this email', 'already registered?', 'in the Database?'], { down: 'No' });
  b.branch('right', 'used', ['Tell them the email is already', 'in use — they can sign in or', 'use another one.'], { label: 'Yes' });
  b.circleJump('right', 'B', 'form', 0.78);
  b.procDB('create', ['Create the seller account.', 'Saved to the Database.']);
  b.decision('verified', ['Did they use', 'Google or Facebook', 'with a verified email?'], { down: 'No' });
  b.branchExit('left', 4, { label: 'Yes' });
  b.decision('confirmneed', ['Must the email', 'be confirmed? Usual is yes.'], { down: 'Yes' });
  b.branchExit('right', 4, { label: 'No' });
  b.exit(3);
  { const e = b.edges.find((v) => v.from === b.id('verified') && v.to === b.id('confirmneed')); if (e) e.label = 'No, email form'; }
  b.note('left', ['The new account cannot be used', 'yet — the email must', 'be confirmed first.']);
  b.note('right', ['When no confirm is needed,', 'they skip the code and', 'go straight to the store setup.']);
  b.databaseFooter();
});

// 3 — Confirm the email
page(3, (b) => {
  b.entry(2, ['the account was created']);
  b.procDB('send', ['We email a 6-digit code', 'plus a Confirm button.', 'The code shows a countdown.', 'Saved to the Database.']);
  b.decision('howconfirm', ['How do they', 'confirm it?'], { down: 'Type the code' });
  b.branch('left', 'button', ['They tap the button in the', 'email — it opens the app', 'and confirms the account.'], { label: 'The email' });
  b.branchExit('right', 5, { label: 'Back to sign in' });
  b.proc('typecode', ['They type the 6-digit code', 'in the app.']);
  b.decisionDB('correct', ['Is the code right', 'and still valid?', 'in the Database?'], { down: 'Yes' });
  b.branch('right', 'wrong', ['Show an error message.'], { label: 'No' });
  b.branchNext('right', 'resend', ['They can ask for a new code —', 'a minute has to pass first.', 'Too many tries are flagged.']);
  b.circleJump('right', 'A', 'typecode', 0.5);
  b.procDB('done', ['Account confirmed —', 'they are signed in.', 'Saved to the Database.']);
  b.merge('left', 'done');
  b.exit(4);
  b.note('left', ['They can close the app and', 'confirm later — it is asked', 'again next time.']);
  b.note('right', ['Back to sign in stops here —', 'the account stays unconfirmed', 'until they confirm.']);
  b.databaseFooter();
});

// 4 — Set up the store
page(4, (b) => {
  b.entry([3, 2], ['account ready — code', 'done or no code needed']);
  b.proc('name', ['They give the store a name,', 'a short story and a logo', 'photo. Shown once —', 'they can change it later.']);
  b.proc('details', ['They add where buyers find', 'them and how to reach them.']);
  b.procDB('saved', ['The store is saved to', 'the Database — it opens', 'on the Dashboard next.']);
  b.exit(6);
  b.note('right', ['They can change the name,', 'story and photo later', 'under Profile.']);
  b.databaseFooter();
});

// 5 — Sign in
page(5, (b) => {
  b.entry([1, 3, 13], ['they want to sign in,', 'with email, Google or Facebook']);
  b.decision('method', ['How do they sign in?'], { down: 'With email' });
  b.socialPair('signedin');
  b.proc('creds', ['They type email and password.', 'Empty boxes or a short password', 'are flagged first.']);
  b.decision('forgot', ['Forgot password', 'tapped?'], { down: 'No' });
  b.branch('right', 'resetlink', ['We email a link to set', 'a new one.'], { label: 'Yes' });
  b.branchNext('right', 'resetdone', ['They open the link on the phone,', 'set a new password —', 'they are signed in.']);
  b.circleJump('right', 'C', 'signedin', 0.2);
  b.decisionDB('password', ['Is the password', 'correct in the Database?'], { down: 'Yes' });
  b.branch('right', 'error', ['Show the same error for a wrong', 'email or password —', 'they can try again.'], { label: 'No' });
  b.circleJump('right', 'A', 'creds', 0.5);
  b.decision('newdevice', ['Is this a phone the', 'app already knows?'], { down: 'Yes' });
  b.branch('left', 'code', ['We email a 6-digit code.', 'They type it to prove it is', 'really them. If the mail fails,', 'the reason shows on the', 'same screen.'], { label: 'No' });
  b.procDB('signedin', ['They are signed in.', 'Saved to the Database.', 'Checks below still apply —', 'new sellers skip them.']);
  b.merge('left', 'signedin');
  b.decision('blocked', ['Is the account', 'suspended?'], { down: 'No' });
  b.branch('right', 'stopped', ['They see why it is closed.', 'Signing out leaves the screen.'], { label: 'Yes' });
  b.decisionDB('profile', ['Does the profile', 'load from the Database?'], { down: 'Yes' });
  b.branch('right', 'retry', ['Show Retry. They can try', 'again or sign out.'], { label: 'No' });
  b.circleJump('right', 'B', 'signedin', 0.8);
  b.decision('mfa', ['Is an extra code', 'needed? New sellers skip.'], { down: 'No' });
  b.branch('left', 'mfacode', ['They type the code from their', 'authenticator app. A lost phone', 'can mail a code. They can', 'also sign out.'], { label: 'Yes' });
  b.proc('home', ['They see the Dashboard.']);
  b.merge('left', 'home');
  b.exit(6);
  b.note('left', ['Too many wrong tries locks', 'the screen for a while.']);
  b.note('right', ['On their own phone they can sign', 'in with a fingerprint next time.', 'First sign in offers', 'to turn it on.']);
  b.databaseFooter();
});

// 6 — Dashboard (hub)
page(6, (b) => {
  b.entryRow([
    { from: [1], phrase: ['signed in'] },
    { from: [4], phrase: ['store is set'] },
    { from: [5], phrase: ['they signed in'] },
    { from: [7], phrase: ['sale done'] },
    { from: [10], phrase: ['orders done'] },
    { from: [12], phrase: ['sales done'] },
  ]);
  b.wideProc('home', ['The Dashboard is the morning briefing: today’s takings,', 'orders that need action, low stock and custom requests,', 'a chart of the week and the last orders.']);
  b.wideProc('tabs', ['Five tabs sit at the bottom of every screen:', 'Dashboard · POS · Products · Orders · Profile.']);
  b.procDB('metrics', ['Tap a card to open its screen:', 'takings, orders to do, low stock,', 'custom requests. Loaded from', 'the Database.']);
  b.wideProc('go', ['From here they can go anywhere:']);
  b.exitRow([7, 8, 10, 12, 13]);
  b.databaseFooter();
});

// 7 — POS sale
page(7, (b) => {
  b.entry(6, ['they opened POS']);
  b.procDB('grid', ['The product grid shows what', 'can be sold, with the sizes', 'still in stock. Loaded from', 'the Database.']);
  b.proc('pick', ['They pick a product, choose', 'the size and how many.']);
  b.proc('order', ['The Order panel lists the items', 'with the total so far.']);
  b.decision('right', ['Is everything right?'], { down: 'Yes' });
  b.branch('right', 'change', ['Change the number,', 'or remove an item.'], { label: 'No' });
  b.circleJump('right', 'A', 'order', 0.5);
  b.decision('payhow', ['How do they pay?'], { down: 'Cash' });
  b.branch('left', 'gcash', ['GCash — the sale is done', 'once the payment shows.'], { label: 'GCash' });
  b.proc('cash', ['Cash — they type what the buyer', 'hands over and the change shows.']);
  b.procDB('placed', ['The sale is saved — stock', 'goes down right away.', 'Saved to the Database.']);
  b.merge('left', 'placed', { frac: 0.32 });
  b.proc('done', ['A success note shows for', 'a moment — then they', 'can keep selling.']);
  b.exit(6, { extra: 'they can keep selling' });
  b.note('right', ['Things with no stock are', 'dimmed and cannot', 'be picked.']);
  b.note('right', ['Clearing the order asks', 'for confirm first.']);
  b.databaseFooter();
});

// 8 — Products
page(8, (b) => {
  b.entry(6, ['they opened Products']);
  b.procDB('grid', ['The grid shows every product:', 'photo, price, what is in stock,', 'featured and hidden ones.', 'Loaded from the Database.']);
  b.proc('open', ['Open a product to change it,', 'or start a new one: photos,', 'sizes, price and story.']);
  b.decision('what', ['What do they', 'change?'], { down: 'Details' });
  b.branch('right', 'feature', ['Feature it, hide it,', 'or show it again.'], { label: 'Show or hide' });
  b.branchNext('right', 'delete', ['Delete takes it away for good —', 'it asks for confirm first.']);
  b.circleJump('right', 'A', 'open', 0.5);
  b.procDB('saved', ['The changes are saved.', 'Saved to the Database.']);
  b.proc('stock', ['Things with no stock stay', 'hidden until the stock', 'is filled in.']);
  b.exit(9, { extra: 'then check the stock' });
  b.note('left', ['A hidden product stays', 'in the grid with a badge.']);
  b.databaseFooter();
});

// 9 — Inventory
page(9, (b) => {
  b.entry(8, ['they came from Products']);
  b.procDB('strip', ['A strip counts what is in stock,', 'low and out — tap one to filter.', 'Loaded from the Database.']);
  b.proc('row', ['Each row shows a product and size', 'with a slider for the stock.']);
  b.procDB('set', ['Moving the slider saves the stock', 'and shows or hides the product', 'by itself. Saved to the Database.']);
  b.exit(10, { extra: 'then check the orders' });
  b.note('right', ['Low means five or fewer left.']);
  b.databaseFooter();
});

// 10 — Orders
page(10, (b) => {
  b.entry([6, 9, 11], ['orders to handle —', 'new, restocked or back', 'from customs']);
  b.procDB('list', ['Every order, newest first:', 'waiting · confirmed · ready ·', 'handed over · cancelled.', 'Loaded from the Database.']);
  b.decision('cancel', ['Did the buyer ask', 'to cancel it?'], { down: 'No' });
  b.branch('right', 'cancelflow', ['Still new: cancel straight away.', 'Started: ask the buyer first,', 'then cancel or carry on.'], { label: 'Yes' });
  b.proc('follow', ['Tap an order to open it: buyer,', 'items, where it goes,', 'and what happens next.']);
  b.procDB('confirm', ['Confirm the order — the buyer', 'is told it is being made.', 'Saved to the Database.']);
  b.procDB('ready', ['Pack it and mark it ready —', 'the buyer is told to collect it.', 'Saved to the Database.']);
  b.decision('given', ['Is it handed over?'], { down: 'Yes' });
  b.branch('right', 'wait', ['Wait for the buyer —', 'they get a reminder.'], { label: 'Not yet' });
  b.circleJump('right', 'A', 'ready', 0.5);
  b.procDB('done', ['Mark it handed over —', 'the sale counts from here.', 'Saved to the Database.']);
  b.decision('custom', ['Any custom', 'requests waiting?'], { down: 'No' });
  b.branchExit('right', 11, { label: 'Yes' });
  b.exit(6, { extra: 'back to the briefing' });
  b.note('left', ['A cancelled order can start', 'again when the buyer', 'still wants it.']);
  b.note('right', ['The buyer is told at', 'every step by the app.']);
  b.databaseFooter();
});

// 11 — Custom orders and messages
page(11, (b) => {
  b.entry(10, ['a custom request came in']);
  b.procDB('list', ['Requests show the base pair,', 'colour, material and sizing notes.', 'Loaded from the Database.']);
  b.decision('ok', ['Can the shop', 'make it?'], { down: 'Yes' });
  b.branch('right', 'decline', ['Say no kindly with a reason.', 'Saved to the Database.'], { label: 'No' });
  b.procDB('accept', ['Say yes with the price and', 'when it will be ready.', 'Saved to the Database.']);
  b.procDB('chat', ['Messages show one talk per buyer.', 'Photos and short clips can go', 'with the words. Loaded from', 'the Database.']);
  b.exit(10, { extra: 'back to the orders' });
  b.note('left', ['The shop checks every custom', 'pair by hand before it', 'is made.']);
  b.databaseFooter();
});

// 12 — Sales
page(12, (b) => {
  b.entry(6, ['they opened Sales']);
  b.procDB('range', ['Pick this week or this month.', 'The takings and the chart follow.', 'Loaded from the Database.']);
  b.procDB('top', ['The top pairs show what sold most,', 'with pieces and takings.', 'Loaded from the Database.']);
  b.proc('keep', ['They can save a copy', 'of the table.']);
  b.exit(6, { extra: 'back to the briefing' });
  b.note('right', ['Shop takings count both', 'walk-in and app sales.']);
  b.databaseFooter();
});

// 13 — Store profile and settings
page(13, (b) => {
  b.entry(6, ['they opened Profile']);
  b.procDB('who', ['Store name, story, logo photo', 'and how buyers reach them —', 'all can be changed here.', 'Loaded from the Database.']);
  b.proc('look', ['Theme sheet: follow the device,', 'or pin Light or Dark.']);
  b.proc('help', ['Help and support: answers,', 'tell us about a problem,', 'plus About and Terms.']);
  b.decision('bye', ['Log out or', 'close the store?'], { down: 'Close the store' });
  b.branchExit('right', 5, { label: 'Log out' });
  b.proc('del', ['Closing asks for confirm first.']);
  b.decision('confirm', ['Do they confirm it?'], { down: 'Yes' });
  b.branch('right', 'keep', ['They stay — nothing changes.'], { label: 'No' });
  b.circleJump('right', 'A', 'del', 0.5);
  b.procDB('gone', ['The store is closed and', 'they are signed out.', 'Saved to the Database.']);
  b.end('end', ['END']);
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

// ------------------------------------------------------------------ emit XML --
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const xmlLabel = (lines) => esc(lines.join('<br>'));
const styleFor = (kind) => S[kind] ?? (() => { throw new Error(`no style for ${kind}`); })();

function edgeXml(e) {
  const bits = [EDGE];
  if (e.fromSide) bits.push(
    `exitX=${e.fromSide === 'right' ? 1 : e.fromSide === 'left' ? 0 : 0.5}`,
    `exitY=${e.fromSide === 'bottom' ? 1 : e.fromSide === 'top' ? 0 : 0.5}`,
    'exitPerimeter=0');
  if (e.toSide) bits.push(
    `entryX=${e.toSide === 'right' ? 1 : e.toSide === 'left' ? 0 : 0.5}`,
    `entryY=${e.toSide === 'bottom' ? 1 : e.toSide === 'top' ? 0 : 0.5}`,
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
    { id: `p${p.meta.n}-subtitle`, kind: 'subtitle', lines: [`SoleVision — what the seller does · page ${p.meta.n} of ${META.length}`], x: 60, y: 76, w: 700, h: 24 },
  ];
  for (const s of [...p.shapes, ...extras]) {
    cells.push(`        <mxCell id="${s.id}" value="${xmlLabel(s.lines)}" style="${styleFor(s.kind)}" vertex="1" parent="1">
          <mxGeometry x="${Math.round(s.x)}" y="${Math.round(s.y)}" width="${Math.round(s.w)}" height="${Math.round(s.h)}" as="geometry" />
        </mxCell>`);
  }
  for (const e of p.edges) cells.push(edgeXml(e));
  return `    <diagram id="page-${p.meta.n}" name="${p.meta.n} ${esc(p.meta.name)}">
      <mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${PAGE_W}" pageHeight="${p.pageHeight}" math="0" shadow="0">
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

const SVG_FILL = { proc: 'none', decision: 'none', terminator: 'none', offpage: 'none', onpage: 'none', db: 'none', note: 'none' };
const SVG_STROKE = { proc: '#000000', decision: '#000000', terminator: '#000000', offpage: '#000000', onpage: '#000000', db: '#000000', note: '#000000' };

function svgShape(s) {
  const { x, y, w, h } = s;
  const fill = SVG_FILL[s.kind];
  const stroke = SVG_STROKE[s.kind];
  const dash = s.kind === 'note' ? ' stroke-dasharray="5 5"' : '';
  let shape = '';
  if (s.kind === 'proc' || s.kind === 'note') {
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
  parts.push('<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,3 L0,6 z" fill="#000000"/></marker></defs>');
  parts.push(`<rect x="4" y="4" width="${PAGE_W - 8}" height="${p.pageHeight - 8}" fill="none" stroke="#000000" stroke-width="1"/>`);
  parts.push(svgText([`${p.meta.n} · ${p.meta.name}`], 0, 57, 22, { anchor: 'start', x: 60, bold: true }));
  parts.push(svgText([`SoleVision — what the seller does · page ${p.meta.n} of ${META.length}`], 0, 88, 12, { anchor: 'start', x: 60 }));
  for (const e of p.edges) {
    const pts = polyline(e, p.shapes);
    const full = e.__waypoints.length ? [pts[0], ...e.__waypoints, pts[pts.length - 1]] : pts;
    parts.push(`<polyline points="${full.map((q) => `${q.x.toFixed(1)},${q.y.toFixed(1)}`).join(' ')}" fill="none" stroke="#000000" stroke-width="1.5" marker-end="url(#arrow)"/>`);
  }
  for (const lb of labelBoxes.filter((l) => l.page === p.meta.n)) {
    parts.push(svgText([lb.text], lb.x + lb.w / 2, lb.y + lb.h / 2 + 4, 11));
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
out.push(`wrote docs/diagrams/seller-journey-flowchart.drawio — ${pages.length} pages, ${shapes} shapes, ${edges} connectors`);
out.push(`wrote ${pages.length} SVG previews to docs/diagrams/seller-previews/`);
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

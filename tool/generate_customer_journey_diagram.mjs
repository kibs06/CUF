#!/usr/bin/env node
/**
 * SoleVision — customer journey flowchart generator (client-facing, plain English).
 *
 * Writes docs/diagrams/customer-journey-flowchart.drawio (multi-page) and one
 * SVG preview per page into docs/diagrams/previews/.
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
const OUT_FILE = path.join(ROOT, 'docs', 'diagrams', 'customer-journey-flowchart.drawio');
const PREVIEW_DIR = path.join(ROOT, 'docs', 'diagrams', 'previews');

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
const S = {
  proc: 'rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#000000;fontSize=13;fontColor=#000000;',
  decision: 'rhombus;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#000000;fontSize=13;fontColor=#000000;perimeter=rhombusPerimeter;',
  terminator: 'ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#000000;fontSize=14;fontStyle=1;fontColor=#000000;',
  offpage: 'shape=offPageConnector;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#000000;fontSize=12;fontStyle=1;fontColor=#000000;verticalAlign=top;spacingTop=10;perimeter=rectanglePerimeter;',
  onpage: 'ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#000000;fontSize=15;fontStyle=1;fontColor=#000000;aspect=fixed;perimeter=ellipsePerimeter;',
  note: 'rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=4 4;fillColor=none;strokeColor=#000000;fontSize=12;fontColor=#000000;align=left;verticalAlign=middle;spacingLeft=10;spacingRight=10;',
  title: 'text;html=1;fontSize=22;fontStyle=1;align=left;verticalAlign=middle;fontColor=#000000;',
  subtitle: 'text;html=1;fontSize=12;align=left;verticalAlign=middle;fontColor=#000000;',
};
const EDGE = 'edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=classic;endFill=1;strokeColor=#000000;strokeWidth=1.5;fontSize=11;fontColor=#000000;labelBackgroundColor=none;';

// ------------------------------------------------------------------- pages --
const META = [
  { n: 1, name: 'Open the app', slug: 'open-the-app' },
  { n: 2, name: 'Create an account', slug: 'create-an-account' },
  { n: 3, name: 'Confirm the email', slug: 'confirm-the-email' },
  { n: 4, name: 'Add their foot size', slug: 'add-their-foot-size' },
  { n: 5, name: 'Sign in', slug: 'sign-in' },
  { n: 6, name: 'Home', slug: 'home' },
  { n: 7, name: 'Browse the shops', slug: 'browse-the-shops' },
  { n: 8, name: 'Try the shoes on', slug: 'try-the-shoes-on' },
  { n: 9, name: 'Make it their own', slug: 'make-it-their-own' },
  { n: 10, name: 'Cart and payment', slug: 'cart-and-payment' },
  { n: 11, name: 'Track the order', slug: 'track-the-order' },
  { n: 12, name: 'Talk to the shop', slug: 'talk-to-the-shop' },
  { n: 13, name: 'Profile and settings', slug: 'profile-and-settings' },
  { n: 14, name: 'Settings in detail', slug: 'settings-in-detail' },
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

  finish() {
    this._materialiseCircles();
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
  b.proc('screen', ['Show the Sign up and Sign in', 'screen. One screen — the video', 'keeps playing.']);
  b.decision('whichtap', ['What do they tap?']);
  b.branchExit('right', 2, { label: 'Sign up' });
  b.branchExit('left', 5, { label: 'Sign in' });
  b.note('left', ['Shop owners tap Apply to sell', 'and fill in a different form.']);
  b.note('right', ['Sign in is a switch on the', 'same screen — the video', 'never restarts.']);
  b.legend = [
    'How to read this chart:',
    'oval = the start or the end  ·  rectangle = a step  ·  diamond = a question',
    'pentagon = the story continues on the page written inside it',
    'small circle with a letter = the flow jumps back to the same letter',
  ];
});

// 2 — Create an account
page(2, (b) => {
  b.entry(1, ['they tapped Sign up']);
  b.proc('form', ['They fill in the Create Account form:',
    'name · email · phone if they like,',
    'birthday by picking a date —',
    'must be 13 or older,',
    'gender if they like,',
    'password plus confirm,',
    'a strength hint as they type,',
    'and accept the Terms.']);
  b.decision('filled', ['Is every box filled', 'in right, Terms accepted?'], { down: 'Yes' });
  b.branch('right', 'fixbox', ['Show a message on the box', 'that needs fixing.'], { label: 'No' });
  b.circleJump('right', 'A', 'form', 0.28);
  b.decision('emailused', ['Is this email', 'already registered?'], { down: 'No' });
  b.branch('right', 'used', ['Tell them the email is already',
    'in use — they can sign in or',
    'use another one.'], { label: 'Yes' });
  b.circleJump('right', 'B', 'form', 0.78);
  b.proc('create', ['Create the account.']);
  b.decision('confirmneed', ['Must the email', 'be confirmed? Usual is yes.'], { down: 'Yes' });
  b.branchExit('right', 4, { label: 'No' });
  b.exit(3);
  b.note('left', ['The new account cannot be used',
    'yet — the email must',
    'be confirmed first.']);
  b.note('right', ['When no confirm is needed,',
    'they skip the code and',
    'go straight to foot size.']);
});

// 3 — Confirm the email
page(3, (b) => {
  b.entry(2, ['the account was created']);
  b.proc('send', ['We email a 6-digit code', 'plus a Confirm button.', 'The code shows a countdown.']);
  b.decision('howconfirm', ['How do they', 'confirm it?'], { down: 'Type the code' });
  b.branch('left', 'button', ['They tap the button in the',
    'email — it opens the app',
    'and confirms the account.'], { label: 'The email' });
  b.branchExit('right', 5, { label: 'Back to sign in' });
  b.proc('typecode', ['They type the 6-digit code', 'in the app.']);
  b.decision('correct', ['Is the code right', 'and still valid?'], { down: 'Yes' });
  b.branch('right', 'wrong', ['Show an error message.'], { label: 'No' });
  b.branchNext('right', 'resend', ['They can ask for a new code —', 'a minute has to pass first.', 'Too many tries are flagged.']);
  b.circleJump('right', 'A', 'typecode', 0.5);
  b.proc('done', ['Account confirmed —', 'they are signed in.']);
  b.merge('left', 'done');
  b.exit(4);
  b.note('left', ['They can close the app and', 'confirm later — it is asked', 'again next time.']);
  b.note('right', ['Back to sign in stops here —', 'the account stays unconfirmed', 'until they confirm.']);
});

// 4 — Add their foot size
page(4, (b) => {
  b.entry([3, 2], ['account ready — code', 'done or no code needed']);
  b.proc('ask', ['Ask them to add foot size.', 'Shown once. Never blocks —', 'the account already exists.']);
  b.decision('choose', ['What do they', 'choose?'], { down: 'Skip for now' });
  b.branch('left', 'scan', ['Scan feet with the phone', 'camera. Best pick.', 'If it fails or access is denied,', 'they land back here.'], { label: 'Scan' });
  b.branch('right', 'manual', ['Type size and width', 'themselves. Must pick', 'a size first or it asks again.'], { label: 'Type it in' });
  b.proc('skip', ['Or skip for now. Instant —', 'we remind them on Home later.']);
  b.proc('saved', ['Size saved — or we remind', 'them on the Home screen later.']);
  b.merge('left', 'saved', { frac: 0.32 });
  b.merge('right', 'saved', { frac: 0.68 });
  b.exit(6);
  b.note('right', ['The scan opens on top,', 'so backing out lands', 'exactly back here.']);
});

// 5 — Sign in
page(5, (b) => {
  b.entry([1, 3], ['they want to sign in']);
  b.proc('creds', ['They type email and password.', 'Empty boxes or a short password', 'are flagged first.']);
  b.decision('forgot', ['Forgot password', 'tapped?'], { down: 'No' });
  b.branch('right', 'resetlink', ['We email a link to set', 'a new one.'], { label: 'Yes' });
  b.branchNext('right', 'resetdone', ['They open the link on the phone,', 'set a new password —', 'they are signed in.']);
  b.circleJump('right', 'C', 'signedin', 0.2);
  b.decision('password', ['Is the password', 'correct?'], { down: 'Yes' });
  b.branch('right', 'error', ['Show the same error for a wrong', 'email or password —', 'they can try again.'], { label: 'No' });
  b.circleJump('right', 'A', 'creds', 0.5);
  b.decision('newdevice', ['Is this a phone the', 'app already knows?'], { down: 'Yes' });
  b.branch('left', 'code', ['We email a 6-digit code.', 'They type it to prove it is', 'really them. If the mail fails,', 'the reason shows on the', 'same screen.'], { label: 'No' });
  b.proc('signedin', ['They are signed in.', 'Checks below still apply —', 'new accounts skip them.']);
  b.merge('left', 'signedin');
  b.decision('blocked', ['Is the account', 'suspended?'], { down: 'No' });
  b.branch('right', 'stopped', ['They see why it is closed.', 'Signing out leaves the screen.'], { label: 'Yes' });
  b.decision('profile', ['Does the profile', 'load?'], { down: 'Yes' });
  b.branch('right', 'retry', ['Show Retry. They can try', 'again or sign out.'], { label: 'No' });
  b.circleJump('right', 'B', 'signedin', 0.8);
  b.decision('mfa', ['Is an extra code', 'needed? New accounts skip.'], { down: 'No' });
  b.branch('left', 'mfacode', ['They type the code from their', 'authenticator app. A lost phone', 'can mail a code. They can', 'also sign out.'], { label: 'Yes' });
  b.proc('home', ['They see the Home screen.']);
  b.merge('left', 'home');
  b.exit(6);
  b.note('left', ['Too many wrong tries locks', 'the screen for a while.']);
  b.note('right', ['On their own phone they can sign', 'in with a fingerprint next time.', 'First sign in offers', 'to turn it on.']);
});

// 6 — Home (hub)
page(6, (b) => {
  b.entryRow([
    { from: [1], phrase: ['already signed in'] },
    { from: [4], phrase: ['foot size is set'] },
    { from: [5], phrase: ['they signed in'] },
    { from: [11], phrase: ['order is done'] },
    { from: [12], phrase: ['shop replied'] },
  ]);
  b.wideProc('home', ['The Home screen shows a search box, the cart,',
    'Men’s · Women’s · Kids’, picks in their size,',
    'items on sale and a grid of products.']);
  b.wideProc('tabs', ['Four tabs sit at the bottom of every screen:',
    'Home · Store · Notifications · Profile.']);
  b.wideProc('go', ['From Home they can go anywhere:']);
  b.exitRow([7, 12, 10, 11, 13]);
});

// 7 — Browse the shops
page(7, (b) => {
  b.entry(6, ['they tapped Store']);
  b.proc('shops', ['The Store tab shows every shop,', 'with its name, rating and what it sells.']);
  b.proc('open', ['Open a shop to see its products,', 'or search for a pair.']);
  b.decision('narrow', ['Do they want to', 'narrow it down?'], { down: 'No' });
  b.branch('right', 'filters', ['Search, or filter by size,', 'colour, price or shop.'], { label: 'Yes' });
  b.proc('product', ['They open a product: photos, the 3D view,',
    'the sizes still in stock and the reviews.']);
  b.decision('next', ['What do they do next?'], { down: 'Add it to the cart' });
  b.branchExit('right', 8, { label: 'Try it on' });
  b.branchExit('left', 9, { label: 'Design it' });
  b.proc('cart', ['Add it to the cart.']);
  b.exit(10);
  b.note('right', ['They can also reserve a pair',
    'to collect at the shop — free,',
    'held for 24 hours.']);
});

// 8 — Try the shoes on
page(8, (b) => {
  b.entry(7, ['they tapped Try on']);
  b.proc('camera', ['Point the camera at their feet.']);
  b.proc('appears', ['The shoe appears on their feet and', 'moves with them.']);
  b.proc('swap', ['They can swap shoes while the camera',
    'is on. The app shows the size that fits.']);
  b.decision('looks', ['Does it look right?'], { down: 'Yes' });
  b.branch('right', 'another', ['Try another shoe or size.'], { label: 'No' });
  b.circleJump('right', 'A', 'swap', 0.5);
  b.proc('tocart', ['Add it to the cart.']);
  b.exit(10);
  b.note('right', ['The fitting is a guide — the size',
    'shown is what the app suggests.']);
});

// 9 — Make it their own
page(9, (b) => {
  b.entry(7, ['they tapped Make it their own']);
  b.proc('two', ['Two ways to make it their own: pick the',
    'ready-made options, or design a pair.']);
  b.decision('which', ['Which one?'], { down: 'Design a pair' });
  b.branch('left', 'ready', ['Ready-made: choose the colour',
    'and material the shop offers',
    'for that shoe, then add it',
    'to the cart.'], { label: 'Ready-made' });
  const readyExit = b.add('offpage', 'exit-10-left', exitLines(10), LEFT.x + 20, b.col.left, LEFT.w - 40, lineH(exitLines(10)) + OFF_PAD);
  b.edge('ready', 'exit-10-left', { fromSide: 'bottom', toSide: 'top' });
  b.exitSpecs.push({ to: 10, id: readyExit.id });
  b.proc('design', ['Design a pair of their own: base shoe,',
    'colour and dye, upper material, engraving',
    'and sizing notes.']);
  b.proc('review', ['Review the choices and submit the design.']);
  b.proc('shop', ['The shop gets the request and asks',
    'them about the price and when',
    'it will be ready.']);
  b.end('end', ['END']);
  b.note('right', ['The shop checks every custom',
    'pair by hand, so it is not',
    'added to the cart.']);
});

// 10 — Cart and payment
page(10, (b) => {
  b.entry([6, 7, 8, 9], ['they opened the Cart']);
  b.proc('cart', ['The Cart lists what they picked:', 'the item, the size and how many.']);
  b.decision('right', ['Is everything right?'], { down: 'Yes' });
  b.branch('right', 'change', ['Change the size or the number,', 'or remove an item.'], { label: 'No' });
  b.circleJump('right', 'A', 'cart', 0.5);
  b.proc('checkout', ['Tap Check Out — review the order', 'and choose where it goes.']);
  b.decision('address', ['Do they have an', 'address saved?'], { down: 'Yes' });
  b.branch('left', 'addaddress', ['Add their address, then come', 'back to check out.'], { label: 'No' });
  b.circleJump('left', 'B', 'checkout', 0.5);
  b.decision('payhow', ['How do they pay?'], { down: 'Cash on pickup' });
  b.branch('left', 'gcash', ['GCash — the app opens GCash',
    'to pay. The order waits until',
    'the payment is confirmed.'], { label: 'GCash' });
  b.proc('cash', ['Cash on pickup — they pay at the shop', 'when they collect it.']);
  b.proc('placed', ['The order is placed — the shop sees it', 'right away.']);
  b.merge('left', 'placed', { frac: 0.32 });
  b.exit(11);
  b.note('right', ['The delivery fee and the',
    'GCash fee are shown before',
    'they confirm.']);
  b.note('right', ['If a GCash payment fails or',
    'runs out of time, the order is',
    'not placed — they can try again.']);
});

// 11 — Track the order
page(11, (b) => {
  b.entry([6, 10], ['they opened My Orders']);
  b.proc('list', ['My Orders lists every order,',
    'newest first: unpaid · being',
    'prepared · ready · to review ·',
    'cancelled.']);
  b.decision('cancel', ['Do they want to', 'cancel it?'], { down: 'No' });
  b.branch('right', 'cancelflow', ['Before the shop starts: cancel',
    'straight away. While it is being',
    'prepared: send a request and',
    'the shop decides.'], { label: 'Yes' });
  b.proc('follow', ['Tap an order to follow it: new →',
    'being prepared → ready → handed over.']);
  b.decision('arrived', ['Has it arrived?'], { down: 'Yes' });
  b.branch('right', 'wait', ['Wait for the shop’s update —',
    'they get a notification.'], { label: 'Not yet' });
  b.circleJump('right', 'A', 'follow', 0.5);
  b.proc('confirm', ['Tap Confirm receipt — the order is done.']);
  b.proc('review', ['Rate each pair in the order:', 'stars are a must, a few words', 'and up to 5 photos. One review', 'per pair — it can be edited later.']);
  b.exit(6, { extra: 'they can shop again' });
  b.note('right', ['An unpaid order can be paid', 'from the same screen.']);
  b.note('left', ['Only pairs from a delivered', 'order can be reviewed.']);
});

// 12 — Talk to the shop
page(12, (b) => {
  b.entry(6, ['they tapped the messages icon']);
  b.proc('list', ['Messages shows one conversation', 'per shop.']);  b.proc('start', ['They can start from a shop,', 'a product, an order,', 'or the messages list.']);
  b.proc('type', ['They type their question,', 'or pick a ready note for', 'a first order message.']);
  b.proc('extras', ['Photos and short clips can go', 'with the words. Own messages', 'can be taken back.']);
  b.proc('reply', ['The shop replies in the same', 'conversation — typing dots show', 'while they write. Ticks turn', 'once the shop has read.']);
  b.proc('know', ['A notification and a badge on the bell', 'let them know a reply is waiting.']);
  b.exit(6, { extra: 'they can shop again' });
  b.note('right', ['Custom pairs are usually', 'arranged here, with photos', 'of the design.']);
  b.note('left', ['Help and support chats live', 'under Profile, not here.']);
});

// 13 — Profile and settings
page(13, (b) => {
  b.entry(6, ['they tapped Profile']);
  b.proc('who', ['Their name, photo, phone and email —',
    'name and phone can be edited,',
    'a new email needs its link opened',
    'before it counts.']);
  b.proc('orders', ['My Orders shortcuts: unpaid ·',
    'being prepared · ready ·',
    'to review · cancelled.']);
  b.proc('foot', ['Foot size — check it, scan again,',
    'or type a new size.']);
  b.proc('holds', ['Their pickup reservations — pairs they',
    'are holding at a shop.']);  b.proc('gear', ['The gear opens the full', 'Settings screen.']);
  b.exit(14);
});

// 14 — Settings in detail
page(14, (b) => {
  b.entry(13, ['they tapped the gear', 'for Settings']);
  b.proc('account', ['Account and Security holds', 'name, phone and email,', 'the password link, fingerprint', 'switch, 2-step codes, devices.']);
  b.proc('switch', ['Extra sign-ins can be kept', 'here to jump between accounts.']);
  b.proc('look', ['Theme sheet: follow the device,', 'or pin Light or Dark.']);
  b.proc('addrs', ['Size Your Foot and My Addresses', 'live here too.']);
  b.proc('help', ['Help and support: answers,', 'tell us about a problem,', 'chat with us, plus About,', 'Terms and news with version.']);
  b.decision('bye', ['Log out or', 'delete the account?'], { down: 'Delete the account' });
  b.branch('right', 'logout', ['Log out — asks for confirm,', 'then the sign-in screen shows.'], { label: 'Log out' });
  b.proc('del', ['Deleting asks for confirm first.']);
  b.decision('confirm', ['Do they confirm it?'], { down: 'Yes' });
  b.branch('right', 'keep', ['They stay — nothing changes.'], { label: 'No' });
  b.circleJump('right', 'A', 'del', 0.5);
  b.proc('gone', ['The request is sent and', 'they are signed out.']);
  b.end('end', ['END']);
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
  'payload', 'metadata', 'database', 'endpoint', 'webhook', 'api ', 'backend', 'frontend',
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
    { id: `p${p.meta.n}-subtitle`, kind: 'subtitle', lines: [`SoleVision — what the customer does · page ${p.meta.n} of ${META.length}`], x: 60, y: 76, w: 700, h: 24 },
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

const SVG_FILL = { proc: 'none', decision: 'none', terminator: 'none', offpage: 'none', onpage: 'none', note: 'none' };
const SVG_STROKE = { proc: '#000000', decision: '#000000', terminator: '#000000', offpage: '#000000', onpage: '#000000', note: '#000000' };

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
  parts.push(svgText([`SoleVision — what the customer does · page ${p.meta.n} of ${META.length}`], 0, 88, 12, { anchor: 'start', x: 60 }));
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
out.push(`wrote docs/diagrams/customer-journey-flowchart.drawio — ${pages.length} pages, ${shapes} shapes, ${edges} connectors`);
out.push(`wrote ${pages.length} SVG previews to docs/diagrams/previews/`);
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

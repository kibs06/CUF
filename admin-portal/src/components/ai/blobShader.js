import { MAX_STRANDS } from '../../lib/aiBlob.js'

// ─── The blob, as GLSL ─────────────────────────────────────────────
//
// One full-screen quad and one fragment shader. There is no scene graph, no
// texture, no mesh and no dependency — the liquid and the glass are both math,
// which is why this file is the drawing and the component beside it is a canvas
// with a render loop.
//
// The picture is two things stacked:
//
//   1. **The liquid** — `liquidAt()`. `count` chromatic bands, each an almond:
//      wide and bright on the axis, pinched to a point at both ends. That shape
//      is not decoration, it is what a ring around a sphere looks like when the
//      camera sits a little above its equator, so the bands read as fluid
//      wrapping a ball. Adjacent bands lean opposite ways, which is what makes
//      them meet and cross in the middle instead of nesting.
//   2. **The glass** — the body of `main()`. A sphere that samples that liquid
//      *through itself*, once per colour channel, so the bands inside it are
//      split the way a real lens splits them, plus a rim, a sheen and a bounce.
//      `glass={false}` draws the bare liquid and nothing else, which is the
//      difference the prop is named for.
//
// ⚠️ **Transparent, not dark.** The canvas is composited over the page, so the
// field is packed into straight-alpha `vec4(rgb, a)` whose *alpha is its
// brightness* — a dim tail is a faint tail rather than a dark smudge. The old
// version of this file painted its own near-black stage; that is why it could
// only ever sit on a dark panel, and why it looked nothing like the component it
// implements.
//
// ⚠️ **ES 1.00 on purpose** (WebGL1, not WebGL2). The two things this shader
// wants from the array-indexing rules are a palette lookup by a computed index
// and a per-channel field read, and ES 1.00 forbids the first — so `paletteAt`
// is a bounded search over the uniform array instead of a bare `uColors[i]`.
// That is the only reason it reads oddly. The same rule is why `wrapIndex` and
// the count guard are written in floats: ES 1.00 has no integer `max`.
//
// The uniform array width is interpolated from `lib/aiBlob.js` rather than typed
// twice, so the shader and the prop clamp cannot disagree about the ceiling.

/** A quad as two triangles, in clip space, so the vertex shader is a passthrough. */
export const VERTEX_SHADER = `
attribute vec2 aPosition;

void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`

export const FRAGMENT_SHADER = `
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

#define MAX_STRANDS ${MAX_STRANDS}
#define TAU 6.28318530718

// The glass sphere's radius, as a fraction of the canvas's short side. The liquid
// is measured in these units, so a band at |q| = 1.0 reaches the sphere's
// silhouette and a band at 1.1 pokes just past it — which is what glass set to
// false shows you, and why the tips are drawn long enough to leave the ball.
#define SPHERE_R 0.30

uniform vec2  uResolution;      // canvas size in device pixels
uniform float uTime;            // seconds, or a fixed phase under reduced motion
uniform vec3  uColors[MAX_STRANDS];
uniform int   uPaletteCount;    // how many entries of uColors are meaningful
uniform int   uCount;           // strands to draw, 1..MAX_STRANDS
uniform float uEnergy;          // brightness and weight of the bands
uniform float uSpin;            // how fast the bands drift and roll
uniform float uWobble;          // how far a band leans off the axis
uniform float uPulse;           // rate of the vertical breathing
uniform float uSpread;          // how far apart the bands sit
uniform float uGlass;           // 1 = glass sphere, 0 = the bare liquid

// ⚠️ ES 1.00 allows a uniform array to be indexed only by a *loop* index, so a
// lookup by a computed index has to be written as a bounded search. Twelve
// iterations is the array width; the loop is unrolled by every real driver.
vec3 paletteAt(int index) {
  vec3 colour = uColors[0];
  for (int i = 0; i < MAX_STRANDS; i++) {
    if (i == index) {
      colour = uColors[i];
      break;
    }
  }
  return colour;
}

// ES 1.00 has no integer max — only the float overloads — so the guard is written
// in floats and converted back. This is the sort of thing that compiles on one
// driver and not another, which is why it is a comment rather than a mystery in
// somebody else's console.
int wrapIndex(int i, int n) {
  return i - n * int(floor(float(i) / max(float(n), 1.0)));
}

// The palette, read as a continuous ring. A band does not have one colour: it runs
// through every colour the caller chose as it crosses the ball, which is what
// makes it read as liquid rather than as a painted arc.
vec3 paletteRamp(float along) {
  int n = uPaletteCount > 0 ? uPaletteCount : 1;
  float s = fract(along) * float(n);
  int i0 = wrapIndex(int(floor(s)), n);
  int i1 = wrapIndex(i0 + 1, n);
  return mix(paletteAt(i0), paletteAt(i1), fract(s));
}

// The brightest entry of the palette, for the rim and the atmosphere: a lens
// highlight takes the colour of the light around it, and this way the sphere is
// never tinted by a colour the caller did not choose.
vec3 brightestPalette() {
  vec3 best = uColors[0];
  float bestLum = -1.0;
  for (int i = 0; i < MAX_STRANDS; i++) {
    if (i >= uPaletteCount) break;
    vec3 candidate = uColors[i];
    float lum = dot(candidate, vec3(0.2126, 0.7152, 0.0722));
    if (lum > bestLum) {
      bestLum = lum;
      best = candidate;
    }
  }
  return best;
}

// ─── The liquid ────────────────────────────────────────────────────
//
// Returns *emission*, not a colour: values above 1.0 are meaningful and are what
// straight() below turns into a saturated core. q is in sphere radii — the ball
// is the disc where length(q) < 1.
//
// ⚠️ No backticks in this string. They are the delimiter, and a balanced pair in
// a comment here silently splits the shader source into JavaScript instead — the
// mistake this component has made more than once, which is why blobShader.test.js
// now refuses the character outright.
vec3 liquidAt(vec2 q, float t) {
  float n = float(uCount);

  // ⚠️ The palette lives in the *position*, and the bands brighten it. Take the hue
  // from whichever band happens to be strongest instead and every crossing becomes a
  // seam: the sphere turns into a collage of flat patches rather than one piece of
  // glass with light moving through it — which is precisely what the first pass of
  // this shader drew. A ramp off the position also gives the field a colour before
  // any band is anywhere near it, so nothing is ever left with an undefined hue.
  //
  // The spread is deliberately under a full palette. Sweeping all four colours across
  // the sphere makes every ball a quarter of each and none of them reads; the sphere
  // should sit in one or two of its colours and spend the ends of the palette on the
  // bands.
  float ramp = 0.5 + q.y * 0.18 + q.x * 0.04 + 0.04 * sin(t * 0.20);
  vec3 acc = paletteRamp(ramp) * 0.30 / (1.0 + 1.6 * dot(q, q));

  for (int i = 0; i < MAX_STRANDS; i++) {
    if (i >= uCount) break;
    float fi = float(i);

    // Where this band sits vertically. Spread evenly across the ball rather than
    // stacked outward, so the count changes how busy the field is and not how big
    // it is; a lone band sits on the axis instead of off to one side.
    float lane = n > 1.0 ? (fi / (n - 1.0) - 0.5) : 0.0;
    float yc = lane * 1.5 * uSpread
             + 0.18 * sin(t * (0.30 + uPulse * 0.25) + fi * 1.9);

    // ⚠️ The lean is what makes them cross rather than nest. Alternating the sign
    // by index gives the field its bowtie: neighbouring bands run opposite ways
    // and meet near the middle, which is the one detail that separates this from
    // a stack of parallel stripes.
    float side = mod(fi, 2.0) * 2.0 - 1.0;
    float lean = side * (0.06 + 0.55 * uWobble)
               + uWobble * 0.35 * sin(t * (0.38 + uSpin * 0.30) + fi * 2.3);

    // ⚠️ The reach varies per band, and it has to: every band ends at the same
    // distance from the axis otherwise — the width does not depend on the index —
    // and a dozen of them stack their tips into a rectangle with vertical edges,
    // which is the one shape a liquid should never be.
    float halfW = 1.00 + 0.24 * sin(t * (0.26 + uSpin * 0.20) + fi * 1.3);
    // ⚠️ Thick, and this is what makes the ball read as *full*. Bands thin enough
    // to be called stripes leave most of the sphere unlit glass, and the reference
    // has colour filling it; at this width four bands overlap and tile it.
    float halfH = (0.26 + 0.05 * uEnergy)
                * (1.0 + 0.22 * sin(t * (0.50 + uPulse * 0.40) + fi * 2.1));

    // Into the band's own frame: u across, v through.
    vec2 d = q - vec2(0.0, yc);
    float ca = cos(lean);
    float sa = sin(lean);
    float u = (d.x * ca + d.y * sa) / halfW;
    float v = (d.y * ca - d.x * sa);

    // The almond: env is the vertical room left at this point across the band,
    // so the profile closes to a point at u = ±1 — pointed tips, fat equator,
    // exactly a ring seen from just off its plane.
    float env = 1.0 - u * u;
    if (env > 0.0) {
      float span = halfH * sqrt(env);
      float vv = v / span;

      // ⚠️ A flat crown with a fast shoulder, not a 1/(1+vv^2) dome and not a crisp
      // line either. A dome puts its energy in the middle and almost none at the edge,
      // so the band reads as a thin line inside a glow; a wide tail turns the whole
      // field into a wash and the bands stop being readable at all. They have to be
      // fat ribbons *with a ridge*, and keep that ridge while four of them overlap
      // across the same sphere. This is the fourth shape this profile has had.
      float core = exp(-vv * vv * 1.6);
      float tail = 0.06 * exp(-vv * vv * 0.30);

      // The colour travels along the band as it goes, and each band starts at its
      // own point in the palette — a small shift, so the band reads as a colour
      // moving over the wash rather than as a stripe that spans every colour.
      vec3 colour = paletteRamp(ramp + u * 0.20 + fi * 0.06 + t * 0.02 * (0.6 + uSpin));

      acc += colour * (core + tail) * uEnergy * 1.65;
    }
  }

  // The atmosphere: a wide, faint bloom of the palette's brightest entry, so the
  // field has air around it instead of ending where the bands stop.
  acc += brightestPalette() * 0.03 / (1.0 + 1.9 * dot(q, q));

  return acc;
}

// ─── Emission into straight alpha ──────────────────────────────────
//
// ⚠️ This is the whole reason the component can sit on a light page. The field is
// *light*, so its alpha is its brightness — a tail at 3% opacity is a faint tail,
// and the hue is carried at full saturation by the normalised rgb. Over a dark
// background this composites to the same colour the old additive version drew, so
// nothing is lost by being transparent instead of black.
vec4 straight(vec3 emission) {
  float m = max(emission.r, max(emission.g, emission.b));
  float a = clamp(m * 1.15, 0.0, 1.0);
  vec3 rgb = m > 1e-4 ? emission / m : vec3(0.0);
  return vec4(rgb, a);
}

void main() {
  vec2 res = uResolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * res) / min(res.x, res.y);
  p.y = -p.y;                       // GL's y runs up, the page's runs down
  vec2 q = p / SPHERE_R;
  float r = length(q);
  float t = uTime;

  // One pixel in sphere radii, for the edge of the sphere and nothing else.
  float aa = 1.6 * SPHERE_R / (0.5 * min(res.x, res.y));

  vec4 colour;

  if (uGlass > 0.5) {
    float z = sqrt(max(1.0 - min(r * r, 1.0), 0.0));   // 1 centre, 0 rim

    // ⚠️ The refraction, and the reason this reads as glass. The sphere samples
    // the liquid *behind* it with the sample pulled toward its own axis — barely
    // at the centre, hard near the rim, where the surface turns away. One read per
    // colour channel is the dispersion: the separation is the effect, and it is
    // what makes the bands inside the ball look split rather than blurred.
    float bend = 0.38 * (1.0 - z);
    vec2 dir = r > 1e-5 ? q / r : vec2(0.0);
    vec3 refr;
    refr.r = liquidAt(q - dir * bend * 1.03, t).r;
    refr.g = liquidAt(q - dir * bend * 1.00, t).g;
    refr.b = liquidAt(q - dir * bend * 0.97, t).b;

    float m = max(refr.r, max(refr.g, refr.b));
    vec3 hue = m > 1e-4 ? refr / m : brightestPalette();
    float cov = clamp(m * 1.15, 0.0, 1.0);

    // ⚠️ The band is *saturation*, not brightness. Mixing toward the band's own
    // colour keeps the marble pale where there is no liquid and vivid where there
    // is; adding the liquid's light on top instead — which is what this did first —
    // drives every channel past 1.0 and the band clips to white, so the sphere ends
    // up a washed-out ball with no band in it at all.
    vec3 vivid = hue * (0.70 + 0.30 * cov);
    vec3 body = mix(vec3(0.87, 0.92, 0.99), vivid, cov * 0.90);

    // A slight thickening toward the edge, so the marble has an inside.
    body *= mix(1.0, 0.90, smoothstep(0.45, 1.0, r));

    // ⚠️ The lamp. Without it the sphere is a flat disc of its own average colour,
    // which is the single biggest thing that separates a marble from a circle: the
    // far side of a glass ball is darker than the side the light is on, and the
    // ball needs that range before the highlights mean anything.
    vec3 normal = vec3(q, z);
    vec3 lightDir = normalize(vec3(-0.45, -0.62, 0.64));
    float sheen = max(dot(normal, lightDir), 0.0);
    body *= 0.78 + 0.34 * sheen;

    // The rim, where a solid glass edge gathers the light it refracts. It is a
    // blend toward the hue rather than an addition of it, because adding on top of
    // a body that already reaches 1.0 in two channels clips the ring to white —
    // which is a bright edge with no colour in it, the opposite of the picture.
    body = mix(body, hue, pow(1.0 - z, 4.0) * 0.70);
    body += vec3(1.0) * pow(1.0 - z, 12.0) * 0.55;

    // One tight specular on top of that lamp and one broad, so the sphere has a
    // highlight even where the liquid is dark.
    //
    // ⚠️ The light's y is *negative*: the coordinate was flipped into page space at
    // the top of this function, so +y is down and an upward lamp has to say so — an
    // earlier pass of this shader lit the sphere from below and put the highlight
    // underneath the voice orb.
    body += vec3(1.0) * pow(sheen, 14.0) * 0.45;

    // ⚠️ The bright crescent underneath, which is a caustic rather than a bounce: a
    // glass ball focuses the light that passes through it onto the surface below, and
    // the bright curve under the sphere is the most recognisable thing about it. It
    // also has to survive the lamp above, which is what darkens that half.
    body += vec3(0.92, 0.97, 1.0) * pow(max(normal.y, 0.0), 1.6) * 0.26;

    // Inside the silhouette the ball is opaque; just outside it only a soft halo
    // survives, so the sphere sits *on* the page rather than covering it.
    float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
    float halo = exp(-pow(max(r - 1.0, 0.0) * 3.2, 2.0)) * 0.34;
    vec3 outer = hue * 0.55 + vec3(1.0) * 0.45;

    colour = vec4(mix(outer * halo, body, disc), max(disc, halo * 0.55));
  } else {
    // No lens: the bare liquid, field-wide, with nothing confining it to a disc.
    colour = straight(liquidAt(q, t));
  }

  gl_FragColor = colour;
}
`

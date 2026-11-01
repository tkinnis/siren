/*
 * The page script that draws a mermaid diagram offscreen and hands the host
 * a drawing it can show without a web view: a flattened SVG, or a PNG when
 * the diagram cannot be flattened.
 *
 * The host loads the page once and asks it for every diagram in one of two
 * ways: a web view calls `finchMermaid.run(request)`, and a helper process
 * calls `finchPage.request(text)` with the request's JSON text. The diagram
 * source arrives as a value in the request, next to the request id, and is
 * never part of the page's markup. Every answer is a JSON string carrying
 * the same id, returned from `finchMermaid.render` and posted to the host's
 * channel: `finchHost` where a helper gives the page one, or the web view's
 * channel where it does not.
 *
 * The SVG mermaid writes cannot be drawn as it is by a Flutter SVG renderer:
 * it styles by class, closes arrowheads in markers, nests svg elements and
 * positions text by dominant baseline. The flattening below rewrites it into
 * the smaller language such a renderer reads, with every property measured
 * from the engine that laid the diagram out. A construct the rewrite does
 * not know is reported as unflattenable and never dropped, and the diagram
 * is then answered as a picture.
 *
 * The host checks the answer against the same limits this script holds
 * itself to, so what is written here is what the check admits: a value the
 * check would refuse is changed to one it accepts, or the diagram is drawn as
 * a picture instead.
 */
(function () {
  'use strict';

  const CONFIG = JSON.parse(
    document.getElementById('finch-config').textContent);
  const LIMITS = CONFIG.limits;
  const SVG_NS = 'http://www.w3.org/2000/svg';
  const RENDER_ID = 'finch';
  const MAX_DETAIL_CHARS = 600;
  const ID_PATTERN = /^[A-Za-z0-9_.:-]{1,200}$/;
  const PNG_PREFIX = 'data:image/png;base64,';

  /** A failure with a kind the host maps onto its own failure kinds. */
  class Failure extends Error {
    constructor(kind, detail) {
      super(detail);
      this.kind = kind;
      this.detail = detail;
    }
  }

  const unflattenable = (detail) => new Failure('unflattenable', detail);

  // -------------------------------------------------------------------------
  // Numbers, colours and lengths
  // -------------------------------------------------------------------------

  const LIMIT = 1e7;

  /** A finite, bounded number written without an exponent. */
  function num(value) {
    const n = Number(value);
    if (!Number.isFinite(n) || Math.abs(n) > LIMIT) {
      throw unflattenable('number out of range: ' + value);
    }
    return String(Math.round(n * 1000) / 1000);
  }

  /** The numbers in a whitespace and comma separated list. */
  function numberList(text) {
    const parts = String(text).trim().split(/[\s,]+/).filter(Boolean);
    return parts.map((part) => {
      const n = Number(part);
      if (!Number.isFinite(n)) throw unflattenable('number list: ' + text);
      return n;
    });
  }

  const RGB_PATTERN = new RegExp(
    String.raw`^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)` +
    String.raw`(?:\s*[,/]\s*([\d.]+)(%?))?\s*\)$`);
  const SRGB_PATTERN = new RegExp(
    String.raw`^color\(\s*srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)` +
    String.raw`(?:\s*\/\s*([\d.]+)(%?))?\s*\)$`);
  const URL_PATTERN = new RegExp(
    String.raw`^url\(\s*["']?([^"')#]*)#([^"')\s]+)["']?\s*\)`);

  function alphaOf(match) {
    const alpha = match[4] === undefined ? 1 : Number(match[4]);
    return match[5] === '%' ? alpha / 100 : alpha;
  }

  /** A computed colour as {r, g, b, a}, or null for `none`. */
  function parseColor(text) {
    const value = String(text).trim().toLowerCase();
    if (value === '' || value === 'none') return null;
    if (value === 'transparent') return {r: 0, g: 0, b: 0, a: 0};
    let match = RGB_PATTERN.exec(value);
    if (match) {
      return {
        r: Math.round(Number(match[1])),
        g: Math.round(Number(match[2])),
        b: Math.round(Number(match[3])),
        a: alphaOf(match),
      };
    }
    match = SRGB_PATTERN.exec(value);
    if (match) {
      return {
        r: Math.round(Number(match[1]) * 255),
        g: Math.round(Number(match[2]) * 255),
        b: Math.round(Number(match[3]) * 255),
        a: alphaOf(match),
      };
    }
    throw unflattenable('colour ' + text);
  }

  /**
   * The id a url(...) paint or reference names, or null. The engine reports
   * a computed reference with the document's address in front of the id.
   */
  function urlReference(text) {
    const match = URL_PATTERN.exec(String(text).trim());
    if (match === null) return null;
    const address = match[1];
    // A reference to anything but this document names nothing in a drawing.
    if (address !== '' && address !== document.URL &&
        address !== document.baseURI) {
      return null;
    }
    return match[2];
  }

  /** The id a reference names, which must be one a drawing may carry. */
  function referenceId(text) {
    const id = urlReference(text);
    if (id !== null && !ID_PATTERN.test(id)) {
      throw unflattenable('reference ' + id);
    }
    return id;
  }

  /** [channel] of a colour multiplied by [brightness], as a filter does. */
  const brightened = (channel, brightness) =>
    Math.min(255, Math.round(channel * brightness));

  /**
   * Writes the fill or stroke named by [kind] from a computed paint value
   * and its opacity, splitting an rgba colour into rgb plus an opacity.
   * [brightness] is the product of the `brightness()` filters the element
   * is drawn under.
   */
  function setPaint(attributes, kind, value, opacityText, brightness = 1) {
    const reference = referenceId(value);
    const opacity = Number(
      opacityText === undefined || opacityText === '' ? 1 : opacityText);
    if (reference !== null) {
      // A gradient is drawn wherever it is referred to, in its own colours.
      if (brightness !== 1) throw unflattenable('a brightened gradient');
      attributes[kind] = 'url(#' + reference + ')';
      if (opacity < 1) attributes[kind + '-opacity'] = num(opacity);
      return;
    }
    const color = parseColor(value);
    if (color === null || color.a === 0) {
      attributes[kind] = 'none';
      return;
    }
    attributes[kind] = 'rgb(' + brightened(color.r, brightness) + ',' +
      brightened(color.g, brightness) + ',' +
      brightened(color.b, brightness) + ')';
    const combined = color.a * opacity;
    if (combined < 1) attributes[kind + '-opacity'] = num(combined);
  }

  // -------------------------------------------------------------------------
  // Matrices
  // -------------------------------------------------------------------------

  const IDENTITY = [1, 0, 0, 1, 0, 0];

  function multiply(m, n) {
    return [
      m[0] * n[0] + m[2] * n[1],
      m[1] * n[0] + m[3] * n[1],
      m[0] * n[2] + m[2] * n[3],
      m[1] * n[2] + m[3] * n[3],
      m[0] * n[4] + m[2] * n[5] + m[4],
      m[1] * n[4] + m[3] * n[5] + m[5],
    ];
  }

  const translation = (x, y) => [1, 0, 0, 1, x, y];
  const scaling = (x, y) => [x, 0, 0, y, 0, 0];
  const rotation = (degrees) => {
    const r = (degrees * Math.PI) / 180;
    return [Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0];
  };

  const isIdentity = (m) => m.every((v, i) => Math.abs(v - IDENTITY[i]) < 1e-9);

  const matrixText = (m) => 'matrix(' + m.map(num).join(' ') + ')';

  /**
   * Whether [m] stretches every direction alike: a turn, a reflection and a
   * move, by one factor.
   */
  function isSimilarity(m) {
    const size = Math.abs(m[0]) + Math.abs(m[1]) + Math.abs(m[2]) +
      Math.abs(m[3]);
    const close = (a, b) => Math.abs(a - b) <= 1e-6 * size;
    return (close(m[0], m[3]) && close(m[1], -m[2])) ||
      (close(m[0], -m[3]) && close(m[1], m[2]));
  }

  /** [context] under the further transform [m]. */
  function stretchedBy(context, m) {
    return {
      scale: context.scale * stretch(m),
      similar: context.similar && isSimilarity(m),
    };
  }

  /** How far the matrix stretches a length at most: its largest singular
   * value. */
  function stretch(m) {
    const sum = m[0] * m[0] + m[1] * m[1] + m[2] * m[2] + m[3] * m[3];
    const determinant = m[0] * m[3] - m[1] * m[2];
    const spread = Math.sqrt(
      Math.max(0, sum * sum - 4 * determinant * determinant));
    return Math.sqrt((sum + spread) / 2);
  }

  /** Lengths in px from a computed value such as "12px" or "0". */
  function pixels(text) {
    const n = parseFloat(text);
    return Number.isFinite(n) ? n : 0;
  }

  /**
   * The element's transform as a six-number matrix, read from the computed
   * style so one that a style rule set is seen as well as the attribute.
   */
  function transformOf(element, style) {
    const text = style.transform;
    if (!text || text === 'none') {
      const list = element.transform ? element.transform.baseVal : null;
      if (list && list.numberOfItems > 0) {
        const m = list.consolidate().matrix;
        return [m.a, m.b, m.c, m.d, m.e, m.f];
      }
      return IDENTITY;
    }
    if (text.startsWith('matrix3d')) throw unflattenable('matrix3d transform');
    const match = /^matrix\(([^)]*)\)$/.exec(text);
    if (!match) throw unflattenable('transform ' + text);
    const values = numberList(match[1]);
    if (values.length !== 6) throw unflattenable('transform ' + text);
    let matrix = values;
    const origin = (style.transformOrigin || '0px 0px').split(/\s+/);
    const ox = pixels(origin[0]);
    const oy = pixels(origin[1] || '0');
    if (ox !== 0 || oy !== 0) {
      matrix = multiply(
        multiply(translation(ox, oy), matrix), translation(-ox, -oy));
    }
    return matrix;
  }

  // -------------------------------------------------------------------------
  // The output tree
  // -------------------------------------------------------------------------

  let elementCount = 0;

  function make(name, attributes) {
    elementCount += 1;
    if (elementCount > LIMITS.maxElements) {
      throw unflattenable('more than ' + LIMITS.maxElements + ' elements');
    }
    const element = document.createElementNS(SVG_NS, name);
    for (const [key, value] of Object.entries(attributes || {})) {
      if (value !== null && value !== undefined) {
        element.setAttribute(key, value);
      }
    }
    return element;
  }

  /** The elements other than an svg that draw what they hold in a viewport
   * of their own. */
  const OTHER_VIEWPORTS = new Set(['marker', 'pattern', 'symbol']);

  /**
   * The normalised diagonal of the viewport [shape] is drawn in,
   * `sqrt((w² + h²) / 2)`, which SVG resolves a dash or an offset in percent
   * against: the viewBox of the nearest svg above the shape, or the svg's
   * width and height where it has none and they are lengths and not
   * percentages. A viewport of another kind, or of no size the page can
   * read, is refused.
   */
  function viewportDiagonal(shape) {
    let node = shape.parentNode;
    while (node && node.localName !== 'svg') {
      if (OTHER_VIEWPORTS.has(node.localName)) {
        throw unflattenable('a dash in percent inside a ' + node.localName);
      }
      node = node.parentNode;
    }
    if (!node) throw unflattenable('a dash in percent outside an svg');
    const box = node.viewBox && node.viewBox.baseVal;
    let width = box ? box.width : 0;
    let height = box ? box.height : 0;
    if (!(width > 0) || !(height > 0)) {
      const percentage = SVGLength.SVG_LENGTHTYPE_PERCENTAGE;
      const absolute = (animated) =>
        (animated && animated.baseVal.unitType !== percentage)
          ? animated.baseVal.value : 0;
      width = absolute(node.width);
      height = absolute(node.height);
    }
    if (!(width > 0) || !(height > 0)) {
      throw unflattenable('a dash in percent of a viewport of no known size');
    }
    return Math.sqrt((width * width + height * height) / 2);
  }

  /**
   * A dash, gap or offset in user units from its computed value: px, a
   * number of them written with no unit, or a percentage of [diagonal]'s
   * answer, read only for a value in percent.
   */
  function dashLength(text, diagonal) {
    const match = /^([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)(px|%)?$/
      .exec(String(text).trim());
    if (match === null) throw unflattenable('dash length ' + text);
    const n = Number(match[1]);
    return match[2] === '%' ? n / 100 * diagonal() : n;
  }

  /**
   * The dash pattern a stroke of [shape] is written with, or null for a
   * solid one, or `{invisible: true}` for a stroke whose dashes all have no
   * length.
   *
   * The compiler that draws the result places a pattern from its first entry
   * along the transformed outline, reads no `stroke-dashoffset`, and draws
   * nothing along a straight segment it enters on an entry of no length. The
   * `neo` look writes every edge's pattern with a dash of no length first, so
   * the pattern is written again to draw what the engine drew:
   *
   * - A pattern with no entry of no length and no offset is written as it
   *   is.
   * - Any other is written out from where the engine starts it, the offset
   *   folded in, as the dashes and gaps the outline passes through, each
   *   entry of no length merged into the gaps or the dashes around it, to
   *   past the outline's end, so the compiler never wraps it.
   * - A pattern that is all dash is a solid stroke.
   * - A pattern that begins in a gap is written with a dash of no length
   *   first, and the outline's first segment is a curve, which the compiler
   *   steps past such a dash on.
   *
   * An entry or an offset in percent is the share of the viewport's
   * normalised diagonal SVG resolves it to (`viewportDiagonal`). The entries
   * are scaled by the transforms above the shape, which the compiler dashes
   * in the units of, and held to the limits as written, rounded.
   *
   * The pattern is read again for each shape it strokes, in a few passes
   * over its entries, and one of more than `maxDashEntries` ends the
   * flattening at its first reading. That reading is not charged to the
   * dash budget: the budget counts what a written pattern costs the
   * compiler, and a pattern that comes out solid or invisible is written as
   * none.
   */
  function dashPattern(style, shape, context) {
    const text = style.strokeDasharray;
    if (!text || text === 'none') return null;
    let measured = null;
    const diagonal = () => {
      if (measured === null) measured = viewportDiagonal(shape);
      return measured;
    };
    const read = String(text).trim().split(/[\s,]+/).filter(Boolean)
      .map((entry) => dashLength(entry, diagonal));
    if (read.some((n) => n < 0)) throw unflattenable('negative dash');
    if (read.length > LIMITS.maxDashEntries) {
      throw unflattenable('more than ' + LIMITS.maxDashEntries + ' dashes');
    }
    const pattern = read.length % 2 === 1 ? read.concat(read) : read;
    const period = pattern.reduce((sum, n) => sum + n, 0);
    if (!(period > 0)) return null;
    if (period < LIMITS.minDashPeriod) {
      throw unflattenable('dashes shorter than ' + LIMITS.minDashPeriod);
    }
    const butt = !style.strokeLinecap || style.strokeLinecap === 'butt';
    if (!butt && pattern.some((n, i) => i % 2 === 0 && n === 0)) {
      // A dash of no length draws its caps, which no other pattern draws.
      throw unflattenable('a dash of no length with caps');
    }
    const offset = style.strokeDashoffset
      ? dashLength(style.strokeDashoffset, diagonal) : 0;
    let written;
    let gapFirst = false;
    if (offset === 0 && read.every((n) => n > 0)) {
      written = read;
    } else {
      const pieces = dashPieces(pattern, period, offset,
        outlineLength(shape) * 1.02 + 1);
      if (pieces.every((piece) => piece.dash)) return null;
      if (pieces.every((piece) => !piece.dash)) return {invisible: true};
      written = pieces.map((piece) => piece.length);
      gapFirst = !pieces[0].dash;
    }
    if (!context.similar) {
      throw unflattenable('dashes under a transform that is not uniform');
    }
    const list = written.map((n) => Number(num(n * context.scale)));
    if (list.some((n) => !(n > 0))) {
      throw unflattenable('a dash or gap shorter than the drawing writes');
    }
    if (gapFirst) list.unshift(0);
    if (list.length > LIMITS.maxDashEntries) {
      throw unflattenable('more than ' + LIMITS.maxDashEntries + ' dashes');
    }
    const total = list.reduce((sum, n) => sum + n, 0);
    const odd = list.length % 2 === 1;
    const writtenPeriod = odd ? total * 2 : total;
    if (writtenPeriod < LIMITS.minDashPeriod) {
      throw unflattenable('dashes shorter than ' + LIMITS.minDashPeriod);
    }
    return {list: list, entries: odd ? list.length * 2 : list.length,
      period: writtenPeriod, gapFirst: gapFirst};
  }

  /**
   * The dashes and gaps an outline [cover] long passes through under
   * [pattern], which has an even number of entries and adds up to [period],
   * started [offset] into it: each `{dash, length}`, no two alike next to
   * each other and none of no length, the last running to [cover] or past.
   */
  function dashPieces(pattern, period, offset, cover) {
    // The pattern as runs, read once: no entry of no length, no two alike
    // next to each other, and the last unlike the first, so each turn of the
    // loop below adds a piece unlike the one before it.
    const runs = [];
    pattern.forEach((length, index) => {
      if (!(length > 0)) return;
      const dash = index % 2 === 0;
      const last = runs[runs.length - 1];
      if (last && last.dash === dash) {
        last.length += length;
      } else {
        runs.push({dash: dash, length: length});
      }
    });
    let start = ((offset % period) + period) % period;
    if (runs.length > 1 && runs[0].dash === runs[runs.length - 1].dash) {
      // The last run goes on into the first, which then begins before the
      // pattern does.
      const last = runs.pop();
      runs[0].length += last.length;
      start = (start + last.length) % period;
    }
    if (runs.length === 1) return [{dash: runs[0].dash, length: cover}];
    let index = 0;
    while (index < runs.length - 1 && start >= runs[index].length) {
      start -= runs[index].length;
      index += 1;
    }
    const pieces = [];
    let covered = 0;
    const first = runs[index].length - start;
    if (first > 0) {
      pieces.push({dash: runs[index].dash, length: first});
      covered = first;
    }
    while (covered < cover) {
      index = (index + 1) % runs.length;
      pieces.push({dash: runs[index].dash, length: runs[index].length});
      covered += runs[index].length;
      if (pieces.length > LIMITS.maxDashEntries) {
        throw unflattenable('more than ' + LIMITS.maxDashEntries + ' dashes');
      }
    }
    return pieces;
  }

  /** The length of [element]'s outline as the engine measures it. */
  function outlineLength(element) {
    if (typeof element.getTotalLength !== 'function') {
      throw unflattenable('length of ' + element.localName);
    }
    return element.getTotalLength();
  }

  /**
   * [d] with its first segment a curve: a straight first segment is written
   * as the cubic it is, so the compiler steps past the dash of no length a
   * pattern that begins in a gap opens with. A first segment that is a curve
   * already is left as it is.
   */
  function withCurveFirst(d) {
    const scan = pathScanner(d);
    const first = scan.command();
    if (first !== 'M' && first !== 'm') throw unflattenable('path data');
    const x = Number(scan.number());
    const y = Number(scan.number());
    let command = scan.command();
    const implicit = command === null;
    if (implicit) command = first === 'm' ? 'l' : 'L';
    const upper = command.toUpperCase();
    if ('CSQTA'.includes(upper)) return d;
    if (!'LHV'.includes(upper)) {
      throw unflattenable('a dashed outline that begins with ' + command);
    }
    const relative = command !== upper;
    let tx = x;
    let ty = y;
    if (upper === 'L') {
      tx = Number(scan.number()) + (relative ? x : 0);
      ty = Number(scan.number()) + (relative ? y : 0);
    } else if (upper === 'H') {
      tx = Number(scan.number()) + (relative ? x : 0);
    } else {
      ty = Number(scan.number()) + (relative ? y : 0);
    }
    let rest = scan.rest();
    // More arguments of the same command follow without its letter.
    if (scan.startsWithNumber()) rest = command + rest;
    // A smooth curve reflects the curve before it, which a line is not.
    if (/^[\s,]*[Ss]/.test(rest)) {
      throw unflattenable('a dashed outline whose curve reflects a line');
    }
    const third = (a, b) => a + (b - a) / 3;
    return 'M' + x + ' ' + y + 'C' + third(x, tx) + ' ' + third(y, ty) + ' ' +
      third(tx, x) + ' ' + third(ty, y) + ' ' + tx + ' ' + ty + rest;
  }

  /** Reads [data] a command or a number at a time. */
  function pathScanner(data) {
    let position = 0;
    const read = (pattern) => {
      pattern.lastIndex = position;
      const match = pattern.exec(data);
      if (match === null) return null;
      position = pattern.lastIndex;
      return match[1];
    };
    return {
      command: () => read(PATH_COMMAND),
      number: () => {
        const text = read(PATH_NUMBER);
        if (text === null) throw unflattenable('path data');
        return text;
      },
      startsWithNumber: () => {
        PATH_NUMBER.lastIndex = position;
        return PATH_NUMBER.test(data);
      },
      rest: () => data.slice(position),
    };
  }

  /** The share of the dash limit the page holds a drawing to. */
  const DASH_MARGIN = 0.99;

  /**
   * An upper bound on the length of [element]'s outline, in its own units,
   * which is the bound the check counts its dashes by: the perimeter of a
   * rectangle, the square around a circle, the rectangle around an ellipse,
   * and for a path the polygon of the control points of each cubic the
   * compiler's reader turns its segments into.
   */
  function outlineBound(element) {
    const value = (animated) => Math.abs(Number(num(animated.baseVal.value)));
    const length = (animated) => Number(num(animated.baseVal.value));
    switch (element.localName) {
      case 'rect':
        return 2 * (value(element.width) + value(element.height));
      case 'circle':
        return 8 * value(element.r);
      case 'ellipse':
        return 4 * (value(element.rx) + value(element.ry));
      case 'line':
        return Math.hypot(
          length(element.x2) - length(element.x1),
          length(element.y2) - length(element.y1));
      case 'polyline':
      case 'polygon': {
        const points = [];
        for (let i = 0; i < element.points.numberOfItems; i += 1) {
          const p = element.points.getItem(i);
          points.push(num(p.x) + ',' + num(p.y));
        }
        if (points.length === 0) return 0;
        return pathBound('M' + points.join(' ') +
          (element.localName === 'polygon' ? 'z' : ''));
      }
      case 'path':
        return pathBound(element.getAttribute('d') || '');
      default:
        throw unflattenable('length of ' + element.localName);
    }
  }

  const PATH_NUMBER =
    /[\s,]*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/y;
  const PATH_FLAG = /[\s,]*([01])/y;
  const PATH_COMMAND = /[\s,]*([MmLlHhVvCcSsQqTtAaZz])/y;
  const PATH_END = /[\s,]*$/y;
  const ARGUMENTS = {M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7,
    Z: 0};

  /**
   * The length of the polygon of the control points of the cubics [data] is
   * read as, by the rules the compiler's reader reads it by: a quadratic is
   * raised to a cubic, a smooth curve reflects the last control point of the
   * curve before it of its own kind, and an arc is drawn as up to four
   * cubics, each within the rectangle around its quarter of the ellipse, so
   * it is bounded by four times the sum of the radii it is drawn at.
   */
  function pathBound(data) {
    let position = 0;
    const read = (pattern) => {
      pattern.lastIndex = position;
      const match = pattern.exec(data);
      if (match === null) return null;
      position = pattern.lastIndex;
      return match[1];
    };
    let x = 0;
    let y = 0;
    let startX = 0;
    let startY = 0;
    let controlX = 0;
    let controlY = 0;
    let last = '';
    let total = 0;
    const polygon = (points) => {
      let previousX = x;
      let previousY = y;
      for (const [px, py] of points) {
        total += Math.hypot(px - previousX, py - previousY);
        previousX = px;
        previousY = py;
      }
    };
    let command = null;
    for (;;) {
      PATH_END.lastIndex = position;
      if (PATH_END.test(data)) break;
      const next = read(PATH_COMMAND);
      if (next !== null) {
        command = next;
      } else if (command === null || command === 'Z' || command === 'z') {
        throw unflattenable('path data');
      } else if (command === 'M') {
        command = 'L';
      } else if (command === 'm') {
        command = 'l';
      }
      const upper = command.toUpperCase();
      const relative = command !== upper && upper !== 'Z';
      const values = [];
      for (let i = 0; i < ARGUMENTS[upper]; i += 1) {
        const text = upper === 'A' && (i === 3 || i === 4)
          ? read(PATH_FLAG) : read(PATH_NUMBER);
        if (text === null) throw unflattenable('path data');
        values.push(Number(text));
      }
      const ox = relative ? x : 0;
      const oy = relative ? y : 0;
      const point = (i) => [values[i] + ox, values[i + 1] + oy];
      let target = null;
      switch (upper) {
        case 'M':
          [x, y] = point(0);
          [startX, startY] = [x, y];
          break;
        case 'L':
          target = point(0);
          polygon([target]);
          break;
        case 'H':
          target = [values[0] + ox, y];
          polygon([target]);
          break;
        case 'V':
          target = [x, values[0] + oy];
          polygon([target]);
          break;
        case 'Z':
          target = [startX, startY];
          polygon([target]);
          break;
        case 'C':
        case 'S': {
          const first = upper === 'C' ? point(0)
            : /[CcSs]/.test(last) ? [2 * x - controlX, 2 * y - controlY]
              : [x, y];
          const second = upper === 'C' ? point(2) : point(0);
          target = upper === 'C' ? point(4) : point(2);
          polygon([first, second, target]);
          [controlX, controlY] = second;
          break;
        }
        case 'Q':
        case 'T': {
          const quad = upper === 'Q' ? point(0)
            : /[QqTt]/.test(last) ? [2 * x - controlX, 2 * y - controlY]
              : [x, y];
          target = upper === 'Q' ? point(2) : point(0);
          polygon([
            [(x + 2 * quad[0]) / 3, (y + 2 * quad[1]) / 3],
            [(target[0] + 2 * quad[0]) / 3, (target[1] + 2 * quad[1]) / 3],
            target,
          ]);
          [controlX, controlY] = quad;
          break;
        }
        case 'A': {
          target = point(5);
          total += arcBound(x, y, values, target);
          break;
        }
      }
      if (target !== null) [x, y] = target;
      if (!/[CcSsQqTt]/.test(command)) [controlX, controlY] = [x, y];
      last = command;
    }
    return total;
  }

  /**
   * A bound on the control polygons of the cubics an arc from ([x], [y]) is
   * drawn as: a line to its end when a radius is zero, and otherwise four
   * times the sum of its radii, grown as the reader grows radii too small to
   * reach the end.
   */
  function arcBound(x, y, values, target) {
    let rx = Math.abs(values[0]);
    let ry = Math.abs(values[1]);
    if (rx === 0 || ry === 0) {
      return Math.hypot(target[0] - x, target[1] - y);
    }
    const angle = (values[2] * Math.PI) / 180;
    const mx = (x - target[0]) / 2;
    const my = (y - target[1]) / 2;
    const tx = Math.cos(angle) * mx + Math.sin(angle) * my;
    const ty = -Math.sin(angle) * mx + Math.cos(angle) * my;
    const scale = (tx * tx) / (rx * rx) + (ty * ty) / (ry * ry);
    if (scale > 1) {
      rx *= Math.sqrt(scale);
      ry *= Math.sqrt(scale);
    }
    return 4 * (rx + ry);
  }

  /**
   * A value to write as a presentation attribute, from an rgba-split style.
   * [shape] is the element the stroke belongs to, or null for one that
   * passes its paint to what it refers to, which may not be dashed.
   */
  function paintAttributes(style, shape, context) {
    const attributes = {};
    setPaint(attributes, 'fill', style.fill, style.fillOpacity,
      context.brightness);
    setPaint(attributes, 'stroke', style.stroke, style.strokeOpacity,
      context.brightness);
    if (attributes.stroke !== 'none') {
      attributes['stroke-width'] = num(pixels(style.strokeWidth));
      const read = style.strokeDasharray;
      if (shape === null && read && read !== 'none') {
        throw unflattenable('a dash on a reference');
      }
      const dashes = shape === null ? null : dashPattern(style, shape, context);
      if (dashes !== null && dashes.invisible) {
        attributes.stroke = 'none';
        delete attributes['stroke-width'];
        delete attributes['stroke-opacity'];
      } else if (dashes !== null) {
        if (dashes.gapFirst) {
          if (shape.localName !== 'path') {
            throw unflattenable('a dashed ' + shape.localName +
              ' that begins in a gap');
          }
          const d = withCurveFirst(shape.getAttribute('d') || '');
          checkPathData(d);
          attributes.d = d;
        }
        // A stroke shorter than a period can still pass every entry of the
        // pattern, each a path command, zeros included.
        context.budget.dashes += outlineBound(shape) * context.scale *
          dashes.entries / dashes.period + dashes.entries;
        // The check counts the same dashes from the lengths as written,
        // each rounded, so the page stops short of the limit by a margin
        // no rounding reaches.
        if (context.budget.dashes > LIMITS.maxDashSegments * DASH_MARGIN) {
          throw unflattenable('more than ' + LIMITS.maxDashSegments +
            ' dashes');
        }
        attributes['stroke-dasharray'] = dashes.list.map(num).join(',');
      }
    }
    if (attributes.stroke !== 'none') {
      if (style.strokeLinecap && style.strokeLinecap !== 'butt') {
        attributes['stroke-linecap'] = style.strokeLinecap;
      }
      if (style.strokeLinejoin && style.strokeLinejoin !== 'miter') {
        attributes['stroke-linejoin'] = style.strokeLinejoin;
      }
      const miter = Number(style.strokeMiterlimit);
      if (Number.isFinite(miter) && miter !== 4) {
        attributes['stroke-miterlimit'] = num(miter);
      }
    }
    if (style.fillRule && style.fillRule !== 'nonzero') {
      attributes['fill-rule'] = style.fillRule;
    }
    if (shape !== null && shape.localName === 'line') attributes.fill = 'none';
    if (context.shadow) paintAsShadow(attributes, context.shadow);
    return attributes;
  }

  const BLEND_MODES = new Set([
    'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge',
    'color-burn', 'hard-light', 'soft-light', 'difference', 'exclusion', 'hue',
    'saturation', 'color', 'luminosity']);

  /** Effects the flattened drawing cannot honour and must not forget. */
  function refuseUnsupportedEffects(style) {
    if (style.mask && style.mask !== 'none') throw unflattenable('mask');
    const blend = style.mixBlendMode;
    if (blend && blend !== 'normal' && !BLEND_MODES.has(blend)) {
      throw unflattenable('mix-blend-mode ' + blend);
    }
    if (style.vectorEffect && style.vectorEffect !== 'none') {
      throw unflattenable('vector-effect');
    }
    const order = style.paintOrder;
    if (order && order !== 'normal' && order !== 'fill stroke markers') {
      throw unflattenable('paint-order');
    }
    const clip = style.clipPath;
    if (clip && clip !== 'none' && urlReference(clip) === null) {
      throw unflattenable('clip-path ' + clip);
    }
  }

  /** The attributes any drawn element carries: transform, opacity, clip. */
  function commonAttributes(element, style) {
    refuseUnsupportedEffects(style);
    const attributes = {};
    const matrix = transformOf(element, style);
    if (!isIdentity(matrix)) attributes.transform = matrixText(matrix);
    const opacity = Number(style.opacity);
    if (Number.isFinite(opacity) && opacity < 1) {
      attributes.opacity = num(opacity);
    }
    const clip = referenceId(style.clipPath || '');
    if (clip !== null) attributes['clip-path'] = 'url(#' + clip + ')';
    if (BLEND_MODES.has(style.mixBlendMode)) {
      attributes['mix-blend-mode'] = style.mixBlendMode;
    }
    return attributes;
  }

  // -------------------------------------------------------------------------
  // Shadows
  // -------------------------------------------------------------------------

  /**
   * The bands a blurred shadow is drawn in, from the outermost in: how far
   * each reaches past the outline, in standard deviations of the blur, and
   * how strong the shadow is out to there, as a share of its colour.
   *
   * A renderer that reads the result has no blur, so a blurred shadow is
   * drawn as the outline grown by each reach, one over another, and the
   * strengths follow the Gaussian's fall from the outline to three standard
   * deviations out. The reaches and strengths keep the drawn shadow within
   * a quarter of its colour of the blurred one everywhere a shadow offset by
   * up to one deviation shows past its shape.
   */
  const SHADOW_BANDS = [
    {reach: 1.8, strength: 0.08},
    {reach: 0.9, strength: 0.25},
    {reach: 0.25, strength: 0.65},
  ];

  /** A blur narrower than this, in the shadow's units, is drawn sharp. */
  const SHARP_DEVIATION = 0.25;

  /**
   * The widest blur a shadow is drawn with, in its units: past it a band
   * grows the outline by more than any diagram is wide.
   */
  const LONGEST_DEVIATION = 64;

  /** The functions a computed filter value lists, each with its argument. */
  function filterFunctions(text) {
    const functions = [];
    let depth = 0;
    let start = 0;
    for (let i = 0; i < text.length; i += 1) {
      if (text[i] === '(') depth += 1;
      if (text[i] !== ')') continue;
      depth -= 1;
      if (depth < 0) throw unflattenable('filter ' + text);
      if (depth === 0) {
        functions.push(text.slice(start, i + 1).trim());
        start = i + 1;
      }
    }
    if (depth !== 0 || text.slice(start).trim() !== '') {
      throw unflattenable('filter ' + text);
    }
    return functions;
  }

  const SHADOW_COLOUR = /(rgba?\([^)]*\)|color\([^)]*\))/;
  const SHADOW_LENGTH = /^-?(?:\d+\.?\d*|\.\d+)(?:px)?$/;

  /** The shadow a computed `drop-shadow()` function draws. */
  function cssShadow(text) {
    const inner = text.slice('drop-shadow('.length, -1);
    const colour = SHADOW_COLOUR.exec(inner);
    if (colour === null) throw unflattenable('drop-shadow ' + inner);
    const lengths = inner.replace(colour[1], ' ').trim().split(/\s+/);
    if (lengths.length < 2 || lengths.length > 3 ||
        !lengths.every((part) => SHADOW_LENGTH.test(part))) {
      throw unflattenable('drop-shadow ' + inner);
    }
    const [dx, dy, deviation] = lengths.map(parseFloat);
    return {dx: dx, dy: dy,
      deviation: Math.min(deviation || 0, LONGEST_DEVIATION),
      color: parseColor(colour[1])};
  }

  /**
   * The shadow a `filter` element draws, which must be one drop shadow of
   * the shape it is set on, laid out in the shape's own units.
   */
  function filterElementShadow(id, context) {
    const filter =
      context.root.querySelector('[id="' + id.replace(/"/g, '') + '"]');
    if (!filter || filter.localName !== 'filter') {
      throw unflattenable('filter #' + id + ' is missing');
    }
    const units = filter.getAttribute('primitiveUnits');
    const primitives = Array.from(filter.children);
    if ((units !== null && units !== 'userSpaceOnUse') ||
        primitives.length !== 1 ||
        primitives[0].localName !== 'feDropShadow' ||
        (primitives[0].getAttribute('in') || 'SourceGraphic') !==
          'SourceGraphic') {
      throw unflattenable('filter #' + id);
    }
    const shadow = primitives[0];
    const deviations = numberList(shadow.getAttribute('stdDeviation') || '2');
    if (deviations.length > 2 ||
        (deviations.length === 2 && deviations[0] !== deviations[1])) {
      throw unflattenable('filter #' + id + ' blurs unevenly');
    }
    const style = getComputedStyle(shadow);
    const color = parseColor(style.floodColor) || {r: 0, g: 0, b: 0, a: 0};
    color.a *= Number(style.floodOpacity);
    return {dx: shadow.dx.baseVal, dy: shadow.dy.baseVal,
      deviation: Math.min(Math.max(0, deviations[0]), LONGEST_DEVIATION),
      color: color};
  }

  const BRIGHTNESS = /^brightness\(\s*((?:\d+\.?\d*|\.\d+))(%?)\s*\)$/;

  /** What filters nothing: no shadow, and colours as they are. */
  const NO_EFFECT = {shadow: null, brightness: 1};

  /**
   * Which filter functions the engine draws on an element of a drawing:
   * `drop-shadow()` and `brightness()`, each true or false, or null while it
   * is not known. [engineFilters] sets it before any drawing is flattened.
   */
  let drawnFilters = null;

  /**
   * What [style]'s filter does to the element: the drop shadow it draws
   * below it, or the factor it brightens its colours by.
   *
   * A `filter` element holding one drop shadow is drawn as one. A filter
   * function is drawn as the engine draws it: an engine may draw a function
   * set on an element inside a drawing or leave it out, and the flattened
   * drawing does what [drawnFilters] found it does. A `drop-shadow()` and
   * `brightness()` are drawn, and any other function the engine draws, or a
   * shadow beside another filter, changes the drawing in a way the flattened
   * drawing cannot and is refused.
   */
  function effectOf(style, context) {
    const text = style.filter;
    if (!text || text === 'none') return NO_EFFECT;
    const functions = filterFunctions(text);
    if (functions.length === 1 && functions[0].startsWith('url(')) {
      const id = urlReference(functions[0]);
      if (id === null) throw unflattenable('filter ' + text);
      return {shadow: filterElementShadow(id, context), brightness: 1};
    }
    if (drawnFilters === null) {
      throw unflattenable('the engine\'s filters are not known');
    }
    const drawn = functions.filter((part) =>
      part.startsWith('drop-shadow(') ? drawnFilters.dropShadow
        : part.startsWith('brightness(') ? drawnFilters.brightness
          : drawnFilters.dropShadow || drawnFilters.brightness);
    if (drawn.length === 0) return NO_EFFECT;
    if (drawn.every((part) => BRIGHTNESS.test(part))) {
      const brightness = drawn.reduce((product, part) => {
        const match = BRIGHTNESS.exec(part);
        return product * Number(match[1]) / (match[2] === '%' ? 100 : 1);
      }, 1);
      // Past this every colour but black is white.
      return {shadow: null, brightness: Math.min(brightness, 256)};
    }
    if (drawn.length === 1 && drawn[0].startsWith('drop-shadow(')) {
      return {shadow: cssShadow(drawn[0]), brightness: 1};
    }
    throw unflattenable('filter ' + text);
  }

  /** A drawing that shows whether the engine draws each filter function. */
  const FILTER_SPECIMEN = 'data:image/svg+xml;charset=utf-8,' +
    encodeURIComponent(
      '<svg xmlns="' + SVG_NS + '" width="8" height="4">' +
      '<rect width="2" height="2" fill="rgb(0,0,0)" ' +
      'style="filter: drop-shadow(rgb(255,0,0) 2px 2px 0px)"/>' +
      '<rect x="4" width="4" height="4" fill="rgb(100,100,100)" ' +
      'style="filter: brightness(2)"/></svg>');

  /** How long the specimen is given to be decoded. */
  const SPECIMEN_WAIT_MS = 2000;

  let filtersPromise = null;

  /**
   * Finds which filter functions the engine draws on an element inside a
   * drawing, by drawing [FILTER_SPECIMEN] the way the engine draws a diagram
   * as a picture and reading two pixels back: the shadow's, and the
   * brightened square's.
   *
   * A specimen the engine does not draw in [SPECIMEN_WAIT_MS] leaves
   * [drawnFilters] unknown, so a diagram with a filter function is drawn as a
   * picture, and the next request measures again.
   */
  function engineFilters() {
    if (!filtersPromise) {
      filtersPromise = (async () => {
        try {
          const image = new Image();
          image.src = FILTER_SPECIMEN;
          let timer = null;
          await Promise.race([
            image.decode(),
            new Promise((resolve, reject) => {
              timer = setTimeout(
                () => reject(new Error('specimen')), SPECIMEN_WAIT_MS);
            }),
          ]).finally(() => clearTimeout(timer));
          const canvas = document.createElement('canvas');
          canvas.width = 8;
          canvas.height = 4;
          const context = canvas.getContext('2d');
          context.drawImage(image, 0, 0);
          const shadow = context.getImageData(3, 3, 1, 1).data;
          const square = context.getImageData(6, 2, 1, 1).data;
          drawnFilters = {
            dropShadow: shadow[0] > 128 && shadow[3] > 128,
            brightness: square[0] > 150,
          };
        } catch (error) {
          drawnFilters = null;
          filtersPromise = null;
        }
      })();
    }
    return filtersPromise;
  }

  /** [m]'s inverse, or null when it has none. */
  function inverse(m) {
    const determinant = m[0] * m[3] - m[1] * m[2];
    if (!(Math.abs(determinant) > 1e-12)) return null;
    return [
      m[3] / determinant, -m[1] / determinant,
      -m[2] / determinant, m[0] / determinant,
      (m[2] * m[5] - m[3] * m[4]) / determinant,
      (m[1] * m[4] - m[0] * m[5]) / determinant,
    ];
  }

  /**
   * The opacities that draw [bands], one over another, so that each reach
   * shows the strength its band asks for, of a colour whose alpha is [alpha].
   */
  function bandOpacities(bands, alpha) {
    let below = 0;
    return bands.map((band) => {
      const target = band.strength * alpha;
      const opacity = 1 - (1 - target) / (1 - below);
      below = target;
      return opacity;
    });
  }

  /**
   * Draws [shadow] of [element] into [parent], below where the element itself
   * is drawn: the element again, offset in its own units and painted in the
   * shadow's colour.
   */
  function emitShadow(element, style, parent, context, shadow) {
    if (!(shadow.color.a > 0)) return;
    const own = transformOf(element, style);
    const undo = inverse(own);
    if (undo === null) return;
    const offset = multiply(
      multiply(own, translation(shadow.dx, shadow.dy)), undo);
    const light = context.brightness;
    // A shadow inside another's is part of the outer shadow's silhouette.
    const color = context.shadow ? context.shadow.color
      : 'rgb(' + brightened(shadow.color.r, light) + ',' +
        brightened(shadow.color.g, light) + ',' +
        brightened(shadow.color.b, light) + ')';
    const bands = shadow.deviation < SHARP_DEVIATION
      ? [{reach: 0, strength: 1}] : SHADOW_BANDS;
    const opacities = bandOpacities(bands, shadow.color.a);
    // The bands sit in one group that offsets them, so the offset is written
    // once and no band reads as a marker placed after the shape before it.
    const group = make('g', {
      transform: isIdentity(offset) ? null : matrixText(offset),
    });
    bands.forEach((band, index) => {
      const layer = make('g', {
        opacity: opacities[index] < 1 ? num(opacities[index]) : null,
      });
      const inside = Object.assign({}, context, {
        shadow: {color: color, grow: 2 * band.reach * shadow.deviation},
      });
      emitElement(element, style, layer, inside);
      if (layer.childNodes.length > 0) group.appendChild(layer);
    });
    if (group.childNodes.length > 0) parent.appendChild(group);
  }

  /**
   * Paints [attributes] in the colour of the shadow being drawn, with the
   * outline grown by the shadow's band: a stroke is widened, and a shape
   * that is only filled is given a stroke.
   */
  function paintAsShadow(attributes, shadow) {
    const filled = attributes.fill !== undefined && attributes.fill !== 'none';
    const stroked =
      attributes.stroke !== undefined && attributes.stroke !== 'none' &&
      attributes['stroke-opacity'] !== '0';
    if (filled) attributes.fill = shadow.color;
    if (stroked) {
      attributes.stroke = shadow.color;
      if (shadow.grow > 0) {
        attributes['stroke-width'] =
          num(Number(attributes['stroke-width'] || 1) + shadow.grow);
      }
    } else if (filled && shadow.grow > 0) {
      attributes.stroke = shadow.color;
      attributes['stroke-width'] = num(shadow.grow);
      attributes['stroke-linejoin'] = 'round';
      if (attributes['fill-opacity'] !== undefined) {
        attributes['stroke-opacity'] = attributes['fill-opacity'];
      }
    }
  }

  /** Elements a later reference can name, which keep their id. */
  const REFERENCED_BY_KIND = new Set(
    ['linearGradient', 'radialGradient', 'clipPath', 'symbol']);

  /**
   * The id of [element] when something refers to it, and nothing otherwise:
   * an id carries no meaning to the drawing and may hold any characters.
   */
  function identifier(element, context) {
    const id = element.getAttribute('id');
    // A shadow is a second drawing of what the id already names.
    if (id === null || context.shadow) return {};
    const needed =
      REFERENCED_BY_KIND.has(element.localName) || context.used.has(id);
    if (!needed) return {};
    if (!ID_PATTERN.test(id)) throw unflattenable('id ' + id);
    return {id: id};
  }

  // -------------------------------------------------------------------------
  // Shapes
  // -------------------------------------------------------------------------

  const length = (animated) => animated.baseVal.value;

  const PATH_TOKEN = new RegExp(
    String.raw`([MmLlHhVvCcSsQqTtAaZz])|` +
    String.raw`([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)|[\s,]`, 'y');

  /** Whether [data] holds only commands, numbers and separators. */
  function checkPathData(data) {
    if (data.length > LIMITS.maxPathChars) {
      throw unflattenable('path data longer than ' + LIMITS.maxPathChars);
    }
    let position = 0;
    while (position < data.length) {
      PATH_TOKEN.lastIndex = position;
      const match = PATH_TOKEN.exec(data);
      if (match === null || match[0] === '') throw unflattenable('path data');
      if (match[2] !== undefined && Math.abs(Number(match[2])) > LIMIT) {
        throw unflattenable('path data number out of range');
      }
      position = PATH_TOKEN.lastIndex;
    }
  }

  function geometryOf(element) {
    switch (element.localName) {
      case 'rect':
        return {
          x: num(length(element.x)), y: num(length(element.y)),
          width: num(length(element.width)),
          height: num(length(element.height)),
          rx: element.rx.baseVal.value ? num(length(element.rx)) : null,
          ry: element.ry.baseVal.value ? num(length(element.ry)) : null,
        };
      case 'circle':
        return {
          cx: num(length(element.cx)), cy: num(length(element.cy)),
          r: num(length(element.r)),
        };
      case 'ellipse':
        return {
          cx: num(length(element.cx)), cy: num(length(element.cy)),
          rx: num(length(element.rx)), ry: num(length(element.ry)),
        };
      case 'line':
        return {
          x1: num(length(element.x1)), y1: num(length(element.y1)),
          x2: num(length(element.x2)), y2: num(length(element.y2)),
        };
      case 'polyline':
      case 'polygon': {
        const points = [];
        for (let i = 0; i < element.points.numberOfItems; i += 1) {
          const p = element.points.getItem(i);
          points.push(num(p.x) + ',' + num(p.y));
        }
        return {points: points.join(' ')};
      }
      case 'path': {
        const d = element.getAttribute('d') || '';
        checkPathData(d);
        return {d: d};
      }
      default:
        throw unflattenable('shape ' + element.localName);
    }
  }

  const MARKED_SHAPES = new Set(['path', 'line', 'polyline', 'polygon']);

  /** Whether a rect, circle or ellipse has no extent, which SVG draws
   * nothing for and a compiler would draw the stroke of as a dot. */
  function hasNoExtent(name, geometry) {
    switch (name) {
      case 'rect': return !(geometry.width > 0) || !(geometry.height > 0);
      case 'circle': return !(geometry.r > 0);
      case 'ellipse': return !(geometry.rx > 0) || !(geometry.ry > 0);
      default: return false;
    }
  }

  function emitShape(element, style, parent, context) {
    const geometry = geometryOf(element);
    if (hasNoExtent(element.localName, geometry)) return;
    const attributes = Object.assign(
      identifier(element, context), geometry,
      commonAttributes(element, style));
    if (context.inClip) {
      // A clip path uses only the geometry; paint on its children is ignored.
      parent.appendChild(make(element.localName, attributes));
      return;
    }
    const paint = paintAttributes(style, element, context);
    if (element.localName === 'line') paint.fill = 'none';
    if (paint.fill !== 'none' || paint.stroke !== 'none') {
      Object.assign(attributes, paint);
      parent.appendChild(make(element.localName, attributes));
    }
    // A marker is drawn whether or not the shape it sits on is.
    if (MARKED_SHAPES.has(element.localName)) {
      emitMarkers(element, style, parent, context);
    }
  }

  // -------------------------------------------------------------------------
  // Markers
  // -------------------------------------------------------------------------

  /** The start and end points, and the directions the path leaves and
   * arrives in. */
  function pathEnds(element) {
    if (element.localName === 'line') {
      const a = {x: length(element.x1), y: length(element.y1)};
      const b = {x: length(element.x2), y: length(element.y2)};
      const angle = Math.atan2(b.y - a.y, b.x - a.x);
      return {start: a, end: b, startAngle: angle, endAngle: angle};
    }
    if (element.localName === 'polyline' || element.localName === 'polygon') {
      const list = element.points;
      if (list.numberOfItems < 2) {
        throw unflattenable('marker on a degenerate polyline');
      }
      const first = list.getItem(0);
      const second = list.getItem(1);
      const penultimate = list.getItem(list.numberOfItems - 2);
      const last = list.getItem(list.numberOfItems - 1);
      return {
        start: {x: first.x, y: first.y}, end: {x: last.x, y: last.y},
        startAngle: Math.atan2(second.y - first.y, second.x - first.x),
        endAngle: Math.atan2(last.y - penultimate.y, last.x - penultimate.x),
      };
    }
    const total = element.getTotalLength();
    const start = element.getPointAtLength(0);
    const end = element.getPointAtLength(total);
    if (!(total > 0)) {
      return {
        start: {x: start.x, y: start.y}, end: {x: end.x, y: end.y},
        startAngle: 0, endAngle: 0,
      };
    }
    const step = Math.min(0.5, total / 100);
    const afterStart = element.getPointAtLength(step);
    const beforeEnd = element.getPointAtLength(total - step);
    return {
      start: {x: start.x, y: start.y}, end: {x: end.x, y: end.y},
      startAngle: Math.atan2(afterStart.y - start.y, afterStart.x - start.x),
      endAngle: Math.atan2(end.y - beforeEnd.y, end.x - beforeEnd.x),
    };
  }

  /** The marker element a computed marker value names, or null for none. */
  function markerFor(value, context) {
    if (!value || value === 'none') return null;
    const id = urlReference(value);
    if (id === null) throw unflattenable('marker ' + value);
    const marker =
      context.root.querySelector('[id="' + id.replace(/"/g, '') + '"]');
    if (!marker || marker.localName !== 'marker') {
      throw unflattenable('marker #' + id + ' is missing');
    }
    return marker;
  }

  /**
   * The matrix that places [marker]'s content with its reference point on
   * [point], turned to [angleRadians].
   */
  function markerMatrix(marker, point, angleRadians, strokeWidth, reverse) {
    const width = marker.markerWidth.baseVal.value;
    const height = marker.markerHeight.baseVal.value;
    const box = marker.viewBox.baseVal;
    const userSpace = marker.markerUnits.baseVal ===
      SVGMarkerElement.SVG_MARKERUNITS_USERSPACEONUSE;
    const unit = userSpace ? 1 : strokeWidth;
    let sx = unit;
    let sy = unit;
    if (box && box.width > 0 && box.height > 0) {
      sx = (width / box.width) * unit;
      sy = (height / box.height) * unit;
      const preserve = marker.preserveAspectRatio.baseVal.align;
      if (preserve !== SVGPreserveAspectRatio.SVG_PRESERVEASPECTRATIO_NONE) {
        sx = Math.min(sx, sy);
        sy = sx;
      }
    }
    let angle = 0;
    const orient = (marker.getAttribute('orient') || '0').trim();
    if (orient === 'auto' || orient === 'auto-start-reverse') {
      angle = (angleRadians * 180) / Math.PI;
      if (orient === 'auto-start-reverse' && reverse) angle += 180;
    } else {
      angle = parseFloat(orient) || 0;
    }
    const refX = marker.refX.baseVal.value;
    const refY = marker.refY.baseVal.value;
    return multiply(
      multiply(
        multiply(translation(point.x, point.y), rotation(angle)),
        scaling(sx, sy)),
      translation(-refX, -refY));
  }

  function emitMarkers(element, style, parent, context) {
    if (style.markerMid && style.markerMid !== 'none') {
      throw unflattenable('marker-mid');
    }
    const start = markerFor(style.markerStart, context);
    const end = markerFor(style.markerEnd, context);
    if (start === null && end === null) return;
    const ends = pathEnds(element);
    const strokeWidth = pixels(style.strokeWidth);
    const place = (marker, point, angle, reverse) => {
      const matrix = markerMatrix(marker, point, angle, strokeWidth, reverse);
      const group = make('g', {transform: matrixText(matrix)});
      const inside = Object.assign({}, context, stretchedBy(context, matrix));
      for (const child of marker.children) emitNode(child, group, inside);
      parent.appendChild(group);
    };
    if (start !== null) place(start, ends.start, ends.startAngle, true);
    if (end !== null) place(end, ends.end, ends.endAngle, false);
  }

  // -------------------------------------------------------------------------
  // Text
  // -------------------------------------------------------------------------

  /**
   * Whether [run] places itself with its own coordinates, rather than
   * flowing on from the run before it.
   */
  function hasOwnPosition(run) {
    return run.hasAttribute('x') || run.hasAttribute('y') ||
      run.hasAttribute('dx') || run.hasAttribute('dy');
  }

  /**
   * The style that must match for two runs on one row to be drawn as one
   * piece of text.
   */
  function runStyleKey(style, decoration, baseline) {
    return [
      style.fontFamily, style.fontSize, style.fontWeight, style.fill,
      style.fillOpacity, style.stroke, style.strokeOpacity, style.strokeWidth,
      decoration, baseline,
    ].join('\u0000');
  }

  /**
   * The elements that each hold one run of text on one line, after wrapping
   * any text that sits beside a tspan so every run is a leaf, and joining
   * runs on the same row that share a decoration and style so an underline
   * or strike does not break at the spaces between them.
   */
  function textRuns(text) {
    const runs = [];
    const visit = (element) => {
      const children = Array.from(element.childNodes);
      const hasElements = children.some((child) => child.nodeType === 1);
      if (!hasElements) {
        if (element.textContent.trim() !== '' ||
            (element !== text && element.textContent !== '' &&
              !/[\n\r]/.test(element.textContent))) {
          runs.push(element);
        }
        return;
      }
      for (const child of children) {
        if (child.nodeType === 3) {
          if (child.data.trim() === '' &&
              (child.data === '' || /[\n\r]/.test(child.data))) {
            continue;
          }
          const wrapper = document.createElementNS(SVG_NS, 'tspan');
          element.replaceChild(wrapper, child);
          wrapper.appendChild(child);
          runs.push(wrapper);
        } else if (child.nodeType === 1) {
          if (child.localName === 'tspan') {
            visit(child);
          } else if (child.localName !== 'title' &&
              child.localName !== 'desc') {
            throw unflattenable('text child ' + child.localName);
          }
        }
      }
    };
    visit(text);
    const groups = [];
    let current = null;
    for (const run of runs) {
      const style = getComputedStyle(run);
      if (style.display === 'none' || style.visibility === 'hidden') {
        current = null;
        groups.push({first: run, extra: []});
        continue;
      }
      const decoration = decorationOf(run);
      const count = run.getNumberOfChars();
      if (decoration === '' || count === 0) {
        current = null;
        groups.push({first: run, extra: []});
        continue;
      }
      const y = run.getStartPositionOfChar(0).y;
      const key = runStyleKey(style, decoration, dominantBaselineOf(run));
      if (current !== null &&
          run.parentElement === current.first.parentElement &&
          !hasOwnPosition(run) &&
          Math.abs(y - current.y) <= 0.5 &&
          key === current.key) {
        current.extra.push(run);
      } else {
        current = {first: run, extra: [], y: y, key: key};
        groups.push(current);
      }
    }
    const merged = [];
    for (const group of groups) {
      if (group.extra.length > 0) {
        for (const extra of group.extra) {
          group.first.textContent += extra.textContent;
          extra.remove();
        }
      }
      if (group.first.textContent.trim() !== '') merged.push(group.first);
    }
    return merged;
  }

  /** The characters the engine addresses in [run], to match its indices. */
  function addressableText(run) {
    const preserve = run.getAttribute('xml:space') === 'preserve' ||
      getComputedStyle(run).whiteSpace.startsWith('pre');
    const raw = run.textContent;
    const total = run.getNumberOfChars();
    if (preserve) {
      const spaced = raw.replace(/[\n\r\t]/g, ' ');
      return spaced.length === total ? spaced : null;
    }
    const collapsed =
      raw.replace(/[\n\r]/g, '').replace(/\t/g, ' ').replace(/ +/g, ' ');
    const candidates = [
      collapsed, collapsed.trimStart(), collapsed.trimEnd(), collapsed.trim(),
    ];
    for (const candidate of candidates) {
      if (candidate.length === total) return candidate;
    }
    return null;
  }

  /**
   * The decorations drawn over [run]. A decoration is not inherited, it is
   * propagated down from the element that declares it, so every ancestor
   * is read.
   */
  function decorationOf(run) {
    const lines = new Set();
    for (let element = run; element && element.nodeType === 1;
        element = element.parentElement) {
      const declared = getComputedStyle(element).textDecorationLine;
      for (const line of declared.split(/\s+/)) {
        if (line === 'underline' || line === 'line-through' ||
            line === 'overline') {
          lines.add(line);
        }
      }
    }
    return Array.from(lines).join(' ');
  }

  /**
   * The family a run of text whose computed [style] the walk read is drawn
   * in: the family the application draws in, which every key of mermaid's
   * configuration that names a family is set to.
   *
   * A source's style statement or class definition can still name another
   * family in CSS, and the engine measures the run in that family's faces,
   * or in whatever it falls back to. The application draws a vector
   * drawing's text in its own faces, by name, so a run measured in another
   * family is refused, and the diagram is drawn as a picture in the faces
   * the engine measured it in.
   */
  function fontFamilyOf(style) {
    const first =
      style.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
    if (first.toLowerCase() !== CONFIG.family.toLowerCase()) {
      throw unflattenable(
        'text in a font family the application does not draw: ' +
        first.slice(0, 80));
    }
    return CONFIG.family;
  }

  /**
   * The weight of the face the engine drew a text in, by the rule a browser
   * picks a face by: the weight asked for if it is bundled, otherwise the
   * nearest one on the side the weight leans to. The application draws the
   * same face, and a weight with no face of its own would be measured in one
   * and drawn in another.
   */
  function faceWeight(text) {
    const keywords = {normal: 400, bold: 700};
    let wanted = keywords[text] !== undefined ? keywords[text] : Number(text);
    if (!Number.isFinite(wanted)) wanted = 400;
    const weights = CONFIG.faces.map((face) => face.weight)
      .sort((a, b) => a - b);
    if (weights.length === 0) return 400;
    if (weights.includes(wanted)) return wanted;
    const lighter = weights.filter((w) => w < wanted).reverse();
    const heavier = weights.filter((w) => w > wanted);
    let order;
    if (wanted < 400) {
      order = lighter.concat(heavier);
    } else if (wanted > 500) {
      order = heavier.concat(lighter);
    } else {
      order = heavier.filter((w) => w <= 500)
        .concat(lighter, heavier.filter((w) => w > 500));
    }
    return Math.max(100, Math.min(900, Math.round(order[0] / 100) * 100));
  }

  const FORBIDDEN_TEXT =
    /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u2028\u2029]/;

  /**
   * The pieces a run of text is written as: where each begins, as an index
   * into [addressable], and what it holds.
   *
   * Control and separator characters are left out, not replaced, since a
   * replacement would have a width the engine never measured. A run is cut
   * into pieces no longer than the check allows, at a space when there is
   * one near the end, and never between the halves of a surrogate pair. Each
   * piece is placed where the engine put its first character.
   */
  function textPieces(addressable) {
    const limit = LIMITS.maxTextChars;
    const pieces = [];
    let text = '';
    let starts = [];
    const finish = (count) => {
      const piece = text.slice(0, count).trimEnd();
      if (piece !== '') pieces.push({start: starts[0], text: piece});
      let rest = count;
      while (rest < text.length && /\s/.test(text[rest])) rest += 1;
      text = text.slice(rest);
      starts = starts.slice(rest);
    };
    for (let i = 0; i < addressable.length; i += 1) {
      const character = addressable[i];
      if (FORBIDDEN_TEXT.test(character)) continue;
      if (text === '' && /\s/.test(character)) continue;
      text += character;
      starts.push(i);
      if (text.length >= limit) {
        let cut = text.lastIndexOf(' ');
        if (cut < limit * 0.8) cut = limit;
        const last = text.charCodeAt(cut - 1);
        if (last >= 0xd800 && last <= 0xdbff) cut -= 1;
        finish(cut);
      }
    }
    finish(text.length);
    return pieces;
  }

  function emitText(text, style, parent, context) {
    if (style.display === 'none') return;
    // The check counts the text a drawing lays out, which a shadow would lay
    // out again past what the page counts.
    if (context.shadow) throw unflattenable('the shadow of a text');
    const base = commonAttributes(text, style);
    for (const run of textRuns(text)) {
      const runStyle = getComputedStyle(run);
      if (runStyle.display === 'none' || runStyle.visibility === 'hidden') {
        continue;
      }
      const total = run.getNumberOfChars();
      if (total === 0) continue;
      const addressable = addressableText(run);
      const pieces = addressable === null
        ? unaddressedPieces(run) : textPieces(addressable);
      for (const piece of pieces) {
        emitTextPiece(run, runStyle, piece, total, base, parent, context);
      }
    }
  }

  /**
   * A run whose characters the engine does not number the way its text reads
   * is written as one piece placed at its first character, so it cannot be
   * cut.
   */
  function unaddressedPieces(run) {
    const content = run.textContent.replace(/\s+/g, ' ').trim()
      .split('').filter((c) => !FORBIDDEN_TEXT.test(c)).join('');
    if (content.length > LIMITS.maxTextChars) {
      throw unflattenable('a run of text that cannot be cut');
    }
    return content === '' ? [] : [{start: 0, text: content}];
  }

  /**
   * The dominant baseline in force for [run]: the nearest ancestor inside the
   * drawing that declares one, or the run's computed value.
   */
  function dominantBaselineOf(run) {
    for (let element = run; element && element.nodeType === 1 &&
        element.localName !== 'svg'; element = element.parentElement) {
      const attribute = element.getAttribute('dominant-baseline');
      if (attribute && attribute !== 'auto' && attribute !== 'inherit') {
        return attribute.trim();
      }
      const computed = getComputedStyle(element).dominantBaseline;
      if (computed && computed !== 'auto' && computed !== 'normal') {
        return computed;
      }
    }
    return 'auto';
  }

  function emitTextPiece(
      run, runStyle, piece, total, base, parent, context) {
    const origin = run.getStartPositionOfChar(Math.min(piece.start, total - 1));
    const fontSize = pixels(runStyle.fontSize);
    const attributes = Object.assign({}, base, {
      x: num(origin.x),
      y: num(origin.y),
      'font-family': fontFamilyOf(runStyle),
      'font-size': num(fontSize),
      'font-weight': String(faceWeight(runStyle.fontWeight)),
      'text-anchor': 'start',
    });
    setPaint(attributes, 'fill', runStyle.fill, runStyle.fillOpacity,
      context.brightness);
    const stroke = runStyle.stroke.startsWith('url')
      ? 'rgb(0,0,0)' : runStyle.stroke;
    const strokeColor = parseColor(stroke);
    if (strokeColor !== null && strokeColor.a > 0 &&
        pixels(runStyle.strokeWidth) > 0) {
      setPaint(attributes, 'stroke', runStyle.stroke, runStyle.strokeOpacity,
        context.brightness);
      attributes['stroke-width'] = num(pixels(runStyle.strokeWidth));
    }
    const decoration = decorationOf(run);
    if (decoration !== '') attributes['text-decoration'] = decoration;
    const element = make('text', attributes);
    element.textContent = piece.text;
    parent.appendChild(element);
    // The renderer that reads the result lays a text out when the next
    // element begins; an empty element after each text makes that happen
    // for the last text of a group as well.
    parent.appendChild(make('path', {d: 'M0 0'}));
  }

  // -------------------------------------------------------------------------
  // The tree walk
  // -------------------------------------------------------------------------

  const DROPPED = new Set(
    ['style', 'title', 'desc', 'metadata', 'filter', 'marker']);
  const NAMED_SHAPES = new Set(
    ['rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'path']);
  const DEFINITIONS = new Set(
    ['defs', 'symbol', 'clipPath', 'linearGradient', 'radialGradient']);

  function emitChildren(element, parent, context) {
    for (const child of element.children) emitNode(child, parent, context);
  }

  function emitGroup(element, style, parent, context, name, extra) {
    const attributes = Object.assign(
      identifier(element, context), commonAttributes(element, style),
      extra || {});
    const group = make(name, attributes);
    emitChildren(element, group, context);
    if (name !== 'g' || group.childNodes.length > 0) {
      parent.appendChild(group);
    }
  }

  /** A nested svg element drawn as a group that maps its viewBox onto its
   * box. */
  function emitNestedSvg(element, style, parent, context) {
    const x = length(element.x);
    const y = length(element.y);
    const width = length(element.width);
    const height = length(element.height);
    const box = element.viewBox.baseVal;
    let matrix = translation(x, y);
    if (box && box.width > 0 && box.height > 0 && width > 0 && height > 0) {
      let sx = width / box.width;
      let sy = height / box.height;
      let offsetX = 0;
      let offsetY = 0;
      const none = SVGPreserveAspectRatio.SVG_PRESERVEASPECTRATIO_NONE;
      if (element.preserveAspectRatio.baseVal.align !== none) {
        const s = Math.min(sx, sy);
        offsetX = (width - box.width * s) / 2;
        offsetY = (height - box.height * s) / 2;
        sx = s;
        sy = s;
      }
      matrix = multiply(
        multiply(matrix, translation(offsetX, offsetY)),
        multiply(scaling(sx, sy), translation(-box.x, -box.y)));
    }
    const attributes = Object.assign(
      identifier(element, context), commonAttributes(element, style));
    const own = attributes.transform
      ? numberList(attributes.transform.slice(7, -1)) : IDENTITY;
    attributes.transform = matrixText(multiply(own, matrix));
    const group = make('g', attributes);
    const inside = Object.assign({}, context, stretchedBy(context, matrix));
    emitChildren(element, group, inside);
    parent.appendChild(group);
  }

  const GRADIENT_ATTRIBUTES = [
    'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'fx', 'fy', 'gradientUnits',
    'spreadMethod'];

  function emitGradient(element, parent, context) {
    const attributes = Object.assign({}, identifier(element, context));
    if (!attributes.id) throw unflattenable('gradient without an id');
    for (const name of GRADIENT_ATTRIBUTES) {
      const value = element.getAttribute(name);
      if (value !== null) {
        if (!/^[A-Za-z0-9.%+-]{1,40}$/.test(value)) {
          throw unflattenable('gradient ' + name);
        }
        attributes[name] = value;
      }
    }
    if (element.getAttribute('gradientTransform') !== null) {
      throw unflattenable('gradientTransform');
    }
    const gradient = make(element.localName, attributes);
    for (const stop of element.children) {
      if (stop.localName !== 'stop') {
        throw unflattenable('gradient child ' + stop.localName);
      }
      const stopStyle = getComputedStyle(stop);
      const color = parseColor(stopStyle.stopColor);
      const stopAttributes = {offset: stop.getAttribute('offset') || '0'};
      if (!/^[0-9.%]{1,10}$/.test(stopAttributes.offset)) {
        throw unflattenable('stop offset');
      }
      stopAttributes['stop-color'] = color === null
        ? 'rgb(0,0,0)'
        : 'rgb(' + color.r + ',' + color.g + ',' + color.b + ')';
      const opacity =
        (color === null ? 0 : color.a) * Number(stopStyle.stopOpacity);
      if (opacity < 1) stopAttributes['stop-opacity'] = num(opacity);
      gradient.appendChild(make('stop', stopAttributes));
    }
    parent.appendChild(gradient);
  }

  /** An image the check admits is a PNG the engine itself wrote out. */
  const IMAGE_PATTERN = /^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/;

  function emitImage(element, style, parent, context) {
    // An image's shadow is the shape of its pixels, which no outline holds,
    // and its pixels are drawn as they are.
    if (context.shadow) throw unflattenable('the shadow of an image');
    if (context.brightness !== 1) throw unflattenable('a brightened image');
    const href = element.href.baseVal;
    if (!IMAGE_PATTERN.test(href) || href.length > LIMITS.maxImageChars) {
      throw unflattenable('image');
    }
    const attributes = Object.assign(
      identifier(element, context), commonAttributes(element, style), {
        x: num(length(element.x)), y: num(length(element.y)),
        width: num(length(element.width)), height: num(length(element.height)),
        href: href,
      });
    parent.appendChild(make('image', attributes));
  }

  function emitUse(element, style, parent, context) {
    // What a use draws carries its own paint, which a shadow cannot reach.
    if (context.shadow) throw unflattenable('the shadow of a use');
    const href = element.href.baseVal;
    if (!/^#[A-Za-z0-9_.:-]{1,200}$/.test(href)) {
      throw unflattenable('use ' + href);
    }
    const attributes = Object.assign(
      identifier(element, context), commonAttributes(element, style), {
        x: num(length(element.x)), y: num(length(element.y)), href: href,
      });
    const width = element.getAttribute('width');
    const height = element.getAttribute('height');
    if (width !== null) attributes.width = num(length(element.width));
    if (height !== null) attributes.height = num(length(element.height));
    Object.assign(attributes, paintAttributes(style, null, context));
    parent.appendChild(make('use', attributes));
  }

  function emitNode(element, parent, context) {
    if (element.namespaceURI !== SVG_NS) {
      throw unflattenable('foreign element ' + element.localName);
    }
    const name = element.localName;
    if (DROPPED.has(name)) return;
    if (context.depth > LIMITS.maxDepth) {
      throw unflattenable('nesting deeper than ' + LIMITS.maxDepth);
    }
    const style = getComputedStyle(element);
    if (style.display === 'none' && !DEFINITIONS.has(name)) return;
    // A definition is drawn where it is referred to, and once.
    if (context.shadow && DEFINITIONS.has(name)) return;
    // The check counts what a clip is copied into, which a shadow would copy
    // again past what the page counts.
    if (context.shadow && style.clipPath && style.clipPath !== 'none') {
      throw unflattenable('the shadow of a clipped element');
    }
    const deeper = Object.assign({}, context,
      stretchedBy(context, transformOf(element, style)),
      {depth: context.depth + 1});
    // A clip uses only the outline, which a filter does not change.
    const effect = DEFINITIONS.has(name) || context.inClip
      ? NO_EFFECT : effectOf(style, context);
    deeper.brightness = context.brightness * effect.brightness;
    if (effect.shadow !== null) {
      emitShadow(element, style, parent, deeper, effect.shadow);
    }
    emitElement(element, style, parent, deeper);
  }

  /** Draws [element] itself, whose [style] the walk has read. */
  function emitElement(element, style, parent, context) {
    const name = element.localName;
    if (NAMED_SHAPES.has(name)) {
      if (style.visibility === 'hidden' && !context.inClip) return;
      emitShape(element, style, parent, context);
    } else if (name === 'text') {
      emitText(element, style, parent, context);
    } else if (name === 'g' || name === 'a') {
      emitGroup(element, style, parent, context, 'g');
    } else if (name === 'svg') {
      emitNestedSvg(element, style, parent, context);
    } else if (name === 'defs') {
      emitGroup(element, style, parent, context, 'defs');
    } else if (name === 'symbol') {
      const extra = {};
      const box = element.getAttribute('viewBox');
      if (box !== null) extra.viewBox = numberList(box).map(num).join(' ');
      emitGroup(element, style, parent, context, 'symbol', extra);
    } else if (name === 'clipPath') {
      emitGroup(
        element, style, parent, Object.assign({}, context, {inClip: true}),
        'clipPath');
    } else if (name === 'linearGradient' || name === 'radialGradient') {
      emitGradient(element, parent, context);
    } else if (name === 'use') {
      emitUse(element, style, parent, context);
    } else if (name === 'image') {
      emitImage(element, style, parent, context);
    } else {
      throw unflattenable('element ' + name);
    }
  }

  // -------------------------------------------------------------------------
  // Flattening
  // -------------------------------------------------------------------------

  /** The width and height the root draws at, from its viewBox. */
  function rootSize(root) {
    const box = root.viewBox.baseVal;
    if (!box || !(box.width > 0) || !(box.height > 0)) {
      throw unflattenable('no viewBox');
    }
    return {x: box.x, y: box.y, width: box.width, height: box.height};
  }

  function textOfReferences(root, attribute) {
    const ids = (root.getAttribute(attribute) || '').split(/\s+/)
      .filter(Boolean);
    const parts = [];
    for (const id of ids) {
      const target = root.querySelector('[id="' + id.replace(/"/g, '') + '"]');
      if (target && target.textContent.trim() !== '') {
        parts.push(target.textContent.trim());
      }
    }
    return parts.join('. ');
  }

  /** The accessible description mermaid writes for accTitle and accDescr. */
  function accessibleLabel(root) {
    const title = textOfReferences(root, 'aria-labelledby');
    const description = textOfReferences(root, 'aria-describedby');
    const label = [title, description].filter(Boolean).join('. ');
    return label === '' ? null : label.slice(0, 1000);
  }

  /** Applies the allow-list to the output: nothing else may be in it. */
  function enforceAllowList(element) {
    const allowed = CONFIG.allowed[element.localName];
    if (!allowed) throw unflattenable('output element ' + element.localName);
    for (const attribute of Array.from(element.attributes)) {
      if (!allowed.includes(attribute.name)) {
        throw unflattenable(
          'output attribute ' + element.localName + '@' + attribute.name);
      }
    }
    for (const child of element.children) enforceAllowList(child);
  }

  function readUint16(bytes, offset, little) {
    return little ?
      bytes[offset] + bytes[offset + 1] * 256 :
      bytes[offset] * 256 + bytes[offset + 1];
  }

  function readUint24Little(bytes, offset) {
    return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536;
  }

  function readUint32(bytes, offset, little) {
    return little ?
      readUint24Little(bytes, offset) + bytes[offset + 3] * 16777216 :
      bytes[offset] * 16777216 + bytes[offset + 1] * 65536 +
        bytes[offset + 2] * 256 + bytes[offset + 3];
  }

  /** Whether [text], in ASCII, stands in [bytes] at [offset]. */
  function asciiAt(bytes, offset, text) {
    if (offset + text.length > bytes.length) return false;
    for (let i = 0; i < text.length; i++) {
      if (bytes[offset + i] !== text.charCodeAt(i)) return false;
    }
    return true;
  }

  /** The size of an image, or null when it has no pixels. */
  function sizeOf(width, height) {
    return width > 0 && height > 0 ? {width: width, height: height} : null;
  }

  /** The bytes a base64 address holds, or null when they are not base64. */
  function bytesOfDataUrl(href) {
    try {
      const binary = atob(href.slice(href.indexOf(',') + 1));
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      return bytes;
    } catch (error) {
      return null;
    }
  }

  /** The size in the header chunk of a PNG, or null. */
  function pngSize(bytes) {
    if (bytes.length < 24 || bytes[0] !== 0x89 || !asciiAt(bytes, 1, 'PNG') ||
        readUint32(bytes, 8, false) !== 13 || !asciiAt(bytes, 12, 'IHDR')) {
      return null;
    }
    return sizeOf(readUint32(bytes, 16, false), readUint32(bytes, 20, false));
  }

  /**
   * The size in the first frame header of a JPEG, or null. The segments before
   * it, the application data among them, are skipped by their lengths.
   */
  function jpegSize(bytes) {
    if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return null;
    let offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset] !== 0xFF) return null;
      const marker = bytes[offset + 1];
      if (marker === 0xFF) {
        offset += 1;
        continue;
      }
      if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        offset += 2;
        continue;
      }
      if (marker === 0xD9 || marker === 0xDA) return null;
      const length = readUint16(bytes, offset + 2, false);
      if (length < 2 || offset + 2 + length > bytes.length) return null;
      if (marker >= 0xC0 && marker <= 0xCF &&
          marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) {
        if (length < 8) return null;
        return sizeOf(readUint16(bytes, offset + 7, false),
          readUint16(bytes, offset + 5, false));
      }
      offset += 2 + length;
    }
    return null;
  }

  /**
   * The size a GIF is decoded at, or null. An engine widens the logical screen
   * to hold the first frame, so the size is the larger of the screen and the
   * first frame's far edges; the blocks before that frame are walked to reach
   * it, and a GIF with no frame whose header is whole is no size.
   */
  function gifSize(bytes) {
    if (bytes.length < 13 ||
        !(asciiAt(bytes, 0, 'GIF87a') || asciiAt(bytes, 0, 'GIF89a'))) {
      return null;
    }
    const screenWidth = readUint16(bytes, 6, true);
    const screenHeight = readUint16(bytes, 8, true);
    let offset = 13;
    if (bytes[10] & 0x80) offset += 3 * (2 << (bytes[10] & 0x07));
    while (offset < bytes.length) {
      const block = bytes[offset];
      if (block === 0x2C) {
        if (offset + 10 > bytes.length) return null;
        return sizeOf(
          Math.max(screenWidth, readUint16(bytes, offset + 1, true) +
            readUint16(bytes, offset + 5, true)),
          Math.max(screenHeight, readUint16(bytes, offset + 3, true) +
            readUint16(bytes, offset + 7, true)));
      }
      if (block !== 0x21) return null;
      offset += 2;
      for (;;) {
        if (offset >= bytes.length) return null;
        const length = bytes[offset];
        offset += 1 + length;
        if (length === 0) break;
      }
    }
    return null;
  }

  /**
   * The size of a WebP, or null. [chunk] is where the chunk to read begins.
   * An extended file names its canvas, and the image chunk inside it must
   * agree.
   */
  function webpSize(bytes, chunk = 12) {
    if (bytes.length < 20 || !asciiAt(bytes, 0, 'RIFF') ||
        !asciiAt(bytes, 8, 'WEBP')) {
      return null;
    }
    if (asciiAt(bytes, chunk, 'VP8 ')) {
      if (bytes.length < chunk + 18 || bytes[chunk + 11] !== 0x9D ||
          bytes[chunk + 12] !== 0x01 || bytes[chunk + 13] !== 0x2A) {
        return null;
      }
      return sizeOf(readUint16(bytes, chunk + 14, true) & 0x3FFF,
        readUint16(bytes, chunk + 16, true) & 0x3FFF);
    }
    if (asciiAt(bytes, chunk, 'VP8L')) {
      if (bytes.length < chunk + 13 || bytes[chunk + 8] !== 0x2F) return null;
      const bits = readUint32(bytes, chunk + 9, true);
      return sizeOf((bits & 0x3FFF) + 1,
        (Math.floor(bits / 16384) & 0x3FFF) + 1);
    }
    if (!asciiAt(bytes, chunk, 'VP8X') || bytes.length < chunk + 18) {
      return null;
    }
    const canvas = sizeOf(readUint24Little(bytes, chunk + 12) + 1,
      readUint24Little(bytes, chunk + 15) + 1);
    let offset = chunk + 18;
    while (offset + 8 <= bytes.length) {
      if (asciiAt(bytes, offset, 'VP8 ') || asciiAt(bytes, offset, 'VP8L')) {
        const image = webpSize(bytes, offset);
        const agrees = image !== null && image.width === canvas.width &&
          image.height === canvas.height;
        return agrees ? canvas : null;
      }
      const length = readUint32(bytes, offset + 4, true);
      offset += 8 + length + (length & 1);
    }
    return canvas;
  }

  /**
   * The size an image announces in its header, read from its bytes, or null
   * when they are no PNG, JPEG, GIF or WebP whose header is whole.
   */
  function readImageSize(bytes) {
    if (bytes.length < 10) return null;
    return pngSize(bytes) || jpegSize(bytes) || gifSize(bytes) ||
      webpSize(bytes);
  }

  /**
   * The size an image announces, once its address and its header are held to
   * the limits, or the failure that refuses it.
   *
   * A decode allocates what the header announces, so the header is read from
   * the bytes the address holds, and an image whose header is unreadable or
   * announces more than the limits allow is refused without the engine being
   * asked to read it.
   */
  function checkImage(href) {
    if (!/^data:image\/(png|jpeg|gif|webp);base64,/.test(href) ||
        href.length > LIMITS.maxImageChars) {
      throw unflattenable('image');
    }
    const bytes = bytesOfDataUrl(href);
    const size = bytes === null ? null : readImageSize(bytes);
    if (size === null) {
      throw unflattenable('an image without a readable header');
    }
    if (size.width > LIMITS.maxSide || size.height > LIMITS.maxSide) {
      throw unflattenable(
        'an image announcing ' + size.width + ' by ' + size.height);
    }
    if (size.width * size.height > LIMITS.maxPixels) {
      throw unflattenable(
        'an image announcing more than ' + LIMITS.maxPixels + ' pixels');
    }
    return size;
  }

  /** An image address wherever a diagram's source writes one. */
  const IMAGE_ADDRESS = /data:\s*image\/[^"'`\s)<>\]]*/gi;

  /** A transparent pixel, which stands where an address was refused. */
  const BLANK_IMAGE = 'data:image/png;base64,' +
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNgYGBgAAAABQAB' +
    'eqhXUAAAAABJRU5ErkJggg==';

  /**
   * [source] with every image address [checkImage] refuses replaced by
   * [BLANK_IMAGE], and why the first was refused, or null when none was.
   *
   * Mermaid lays its drawing out in the page before the page can look at it,
   * and the engine reads an image there at the size it announces, so an
   * address must be held to the limits where the author wrote it. A drawing
   * as an image of its own, an SVG, is not read at a size by the bytes, and
   * is left.
   *
   * The pixel is longer than the shortest address it stands for, so a source
   * that blanking makes longer than `maxSourceChars` is refused as too long:
   * mermaid would draw its own message in place of a source past its
   * `maxTextSize`, and the page would answer with that drawing.
   */
  function withholdRefusedAddresses(source) {
    let refusal = null;
    const text = source.replace(IMAGE_ADDRESS, (address) => {
      if (/^data:\s*image\/svg\+xml/i.test(address)) return address;
      try {
        checkImage(address);
        return address;
      } catch (error) {
        if (!(error instanceof Failure)) throw error;
        if (refusal === null) refusal = error.detail;
        return BLANK_IMAGE;
      }
    });
    if (text.length > LIMITS.maxSourceChars) {
      throw new Failure(
        'tooLarge', 'The diagram is longer than ' + LIMITS.maxSourceChars +
        ' characters once each image it refers to that is not drawn is ' +
        'blanked.');
    }
    return {source: text, refusal: refusal};
  }

  /**
   * Why the first address the layout gate refused was refused, or null while
   * it has refused none; [admittedAddress] sets it.
   */
  let layoutRefusal = null;

  /** Whether mermaid is laying a drawing out, which the gate holds. */
  let layingOut = false;

  /**
   * [value] as the engine would take it for an address, or [BLANK_IMAGE] in
   * its place when it is a data address [checkImage] refuses.
   *
   * A source can spell an address in ways mermaid undoes before it hands the
   * address to the engine, such as an escape in a quoted string of a node's
   * data, so the address is held to the limits where mermaid gives it to the
   * engine as well as where the author wrote it. The engine takes tabs and
   * line breaks out of an address and trims spaces and controls off its ends,
   * and so does the gate before it reads one. An SVG is left, as
   * [withholdRefusedAddresses] leaves it.
   */
  function admittedAddress(value) {
    if (!layingOut) return value;
    const address = String(value).replace(/[\t\n\r]/g, '')
      .replace(/^[\u0000-\u0020]+|[\u0000-\u0020]+$/g, '');
    if (!/^data:/i.test(address) ||
        /^data:\s*image\/svg\+xml/i.test(address)) {
      return value;
    }
    try {
      checkImage(address);
      return value;
    } catch (error) {
      if (!(error instanceof Failure)) throw error;
      if (layoutRefusal === null) layoutRefusal = error.detail;
      return BLANK_IMAGE;
    }
  }

  /** Whether an attribute named [name] is one the engine loads an image by. */
  function isAddressAttribute(name) {
    const lower = String(name).toLowerCase();
    return lower === 'src' || lower === 'href' || lower === 'xlink:href';
  }

  /**
   * Holds every address mermaid gives an image while it lays a drawing out to
   * [admittedAddress]: an image's `src`, and a `src` or `href` attribute set
   * on any element.
   */
  (function gateLayout() {
    const src =
      Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
    Object.defineProperty(HTMLImageElement.prototype, 'src', {
      configurable: false,
      enumerable: src.enumerable,
      get: src.get,
      set(value) {
        src.set.call(this, admittedAddress(value));
      },
    });
    const setAttribute = Element.prototype.setAttribute;
    const setAttributeNS = Element.prototype.setAttributeNS;
    Object.defineProperty(Element.prototype, 'setAttribute', {
      configurable: false,
      writable: false,
      value: function (name, value) {
        return setAttribute.call(this, name,
          isAddressAttribute(name) ? admittedAddress(value) : value);
      },
    });
    Object.defineProperty(Element.prototype, 'setAttributeNS', {
      configurable: false,
      writable: false,
      value: function (namespace, name, value) {
        const local = String(name).slice(String(name).indexOf(':') + 1);
        return setAttributeNS.call(this, namespace, name,
          isAddressAttribute(local) ? admittedAddress(value) : value);
      },
    });
  })();

  /**
   * Takes the address off every image in [document] that [checkImage] refuses
   * and answers why the first was refused, or null when none was.
   *
   * The document is the parsed answer of mermaid, which no engine has laid
   * out: an image in a page the engine lays out, or in a drawing it rasterises,
   * is read at the size it announces, so a refused image must never reach one.
   */
  function withholdRefusedImages(document) {
    let refusal = null;
    for (const image of Array.from(document.getElementsByTagName('image'))) {
      try {
        checkImage(image.href.baseVal);
      } catch (error) {
        if (!(error instanceof Failure)) throw error;
        if (refusal === null) refusal = error.detail;
        for (const attribute of Array.from(image.attributes)) {
          if (attribute.localName === 'href') {
            image.removeAttributeNode(attribute);
          }
        }
      }
    }
    return refusal;
  }

  /**
   * A CSS image function, which names an image without `url()` or around
   * one: `image-set()`, `image()`, `cross-fade()`, `element()`, `src()` and
   * `paint()`, prefixed or not.
   */
  const FOREIGN_IMAGE_FUNCTION = new RegExp('(?:^|[^\\w-])(?:-webkit-|-moz-)?' +
    '(?:image-set|image|cross-fade|element|src|paint)\\(', 'i');

  /** A `url()` as the engine writes it back out, its address in quotes. */
  const CSS_URL =
    /url\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^)"'\s]*))\s*\)/gi;

  /**
   * Whether [address], as the engine writes it in CSS, names an element of
   * the page's own document: `#id`, or the page's address and a fragment,
   * which an engine may write a relative reference back out as.
   */
  function namesElement(address) {
    if (address.startsWith('#')) return true;
    const page = typeof document === 'object' && document
      ? String(document.URL || '').split('#')[0] : '';
    return page !== '' && address.startsWith(page + '#');
  }

  /**
   * Whether the CSS [value], as the engine writes a declaration back out,
   * loads anything but an element of the drawing: a `url()` of any address
   * that does not name one ([namesElement]), a `url(` it cannot read, or an
   * image function.
   */
  function loadsFromAddress(value) {
    const text = String(value);
    if (FOREIGN_IMAGE_FUNCTION.test(text)) return true;
    let fragments = 0;
    for (const match of text.matchAll(CSS_URL)) {
      const address =
        (match[1] ?? match[2] ?? match[3]).replace(/\\(.)/g, '$1');
      if (!namesElement(address)) return true;
      fragments += 1;
    }
    return (text.match(/url\(/gi) || []).length !== fragments;
  }

  /**
   * Takes out of [root], which the engine holds in the page, every CSS
   * declaration and attribute that loads anything but an element of the
   * drawing ([loadsFromAddress]), and answers why, or null where there was
   * none.
   *
   * Mermaid writes the CSS of a source's class definitions and style
   * statements into its drawing as the source writes it, so a source can
   * name an image in CSS, escaped so that no address is written out, which
   * neither the image gate nor [withholdRefusedImages] sees, and which the
   * engine decodes at the size its header announces when it draws the
   * diagram as a picture. The CSS is read as the engine parsed it, so an
   * escape is undone, and whatever a rule selects, since a rule can select
   * an element only in the picture's own document: every rule of each style
   * sheet, however deep, and an `@import` whole; each element's style
   * attribute; and each attribute the engine reads as CSS, parsed as the
   * property of its name. A sheet that loses a declaration is written back
   * out as the engine holds it, and one the engine did not parse is
   * emptied; any other is left as mermaid wrote it.
   */
  function withholdCssImages(root) {
    const declarations = (style) => {
      let removed = false;
      for (let at = style.length - 1; at >= 0; at--) {
        const name = style.item(at);
        if (loadsFromAddress(style.getPropertyValue(name))) {
          style.removeProperty(name);
          removed = true;
        }
      }
      return removed;
    };
    const rules = (owner) => {
      let removed = false;
      for (let at = owner.cssRules.length - 1; at >= 0; at--) {
        const rule = owner.cssRules[at];
        if (typeof rule.href === 'string') {
          owner.deleteRule(at);
          removed = true;
          continue;
        }
        if (rule.style && declarations(rule.style)) removed = true;
        if (rule.cssRules && rules(rule)) removed = true;
      }
      return removed;
    };
    let withheld = false;
    for (const element of Array.from(root.getElementsByTagName('style'))) {
      if (!(element.sheet && element.sheet.cssRules)) {
        if (element.textContent !== '') element.textContent = '';
      } else if (rules(element.sheet)) {
        element.textContent = Array.from(
          element.sheet.cssRules, (rule) => rule.cssText).join('\n');
        withheld = true;
      }
    }
    const scratch = document.createElementNS(SVG_NS, 'g').style;
    for (const element of [root, ...root.getElementsByTagName('*')]) {
      if (element.style && declarations(element.style)) withheld = true;
      for (const attribute of Array.from(element.attributes)) {
        if (attribute.localName === 'style' ||
            !/[(\\]/.test(attribute.value)) {
          continue;
        }
        scratch.cssText = '';
        scratch.setProperty(attribute.localName, attribute.value);
        if (loadsFromAddress(scratch.getPropertyValue(attribute.localName))) {
          element.removeAttributeNode(attribute);
          withheld = true;
        }
      }
    }
    return withheld ? 'a CSS image' : null;
  }

  /**
   * Writes every image in [root] out as a PNG the page drew itself, no larger
   * than an image in a drawing may be.
   *
   * An author's image may be any format the engine reads, spelled in any way
   * it forgives, and announce any size. Drawn onto a canvas and read back it
   * is a PNG in one canonical spelling, of a size the check holds it to.
   */
  async function reencodeImages(root) {
    let total = 0;
    for (const image of Array.from(root.querySelectorAll('image'))) {
      const href = image.href.baseVal;
      checkImage(href);
      const source = new Image();
      source.src = href;
      try {
        await source.decode();
      } catch (error) {
        throw unflattenable('an image the engine cannot read');
      }
      let width = source.naturalWidth;
      let height = source.naturalHeight;
      if (!(width > 0 && height > 0)) throw unflattenable('image without size');
      const shrink = Math.min(
        1, LIMITS.maxImageSide / Math.max(width, height),
        Math.sqrt(LIMITS.maxImagePixels / (width * height)));
      width = Math.max(1, Math.floor(width * shrink));
      height = Math.max(1, Math.floor(height * shrink));
      total += width * height;
      if (total > LIMITS.maxPixels) throw unflattenable('image pixels');
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      canvas.getContext('2d').drawImage(source, 0, 0, width, height);
      const url = canvas.toDataURL('image/png');
      if (!url.startsWith(PNG_PREFIX)) {
        throw unflattenable('the engine did not write the image out');
      }
      if (url.length > LIMITS.maxImageChars) {
        throw unflattenable('an image of ' + width + ' by ' + height +
          ' is ' + url.length + ' characters');
      }
      image.setAttribute('href', url);
    }
  }

  function flatten(root) {
    elementCount = 0;
    const size = rootSize(root);
    const output = make('svg', {
      width: num(size.width),
      height: num(size.height),
      viewBox: [size.x, size.y, size.width, size.height].map(num).join(' '),
    });
    const used = new Set();
    for (const use of root.querySelectorAll('use')) {
      const href = use.href.baseVal;
      if (href.startsWith('#')) used.add(href.slice(1));
    }
    const context = {
      root: root, depth: 0, inClip: false, used: used, scale: 1,
      similar: true, brightness: 1,
      budget: {dashes: 0},
    };
    emitChildren(root, output, context);
    enforceAllowList(output);
    const serialised = new XMLSerializer().serializeToString(output);
    if (serialised.length > LIMITS.maxSvgChars) {
      throw unflattenable('result too large');
    }
    return {svg: serialised, width: size.width, height: size.height};
  }

  // -------------------------------------------------------------------------
  // Raster
  // -------------------------------------------------------------------------

  /** Fits the pixel size of the raster to the limits, lowering the scale if
   * it must. */
  function rasterScale(width, height, scale) {
    let s = Math.max(1, scale);
    const fits = (candidate) =>
      Math.ceil(width * candidate) <= LIMITS.maxSide &&
      Math.ceil(height * candidate) <= LIMITS.maxSide &&
      Math.ceil(width * candidate) * Math.ceil(height * candidate) <=
        LIMITS.maxPixels;
    while (s > 1 && !fits(s)) s = Math.max(1, s - 0.5);
    if (!fits(s)) {
      throw new Failure(
        'tooLarge', 'The diagram is too large to draw as an image.');
    }
    return s;
  }

  /** How long a page waits for a picture's embedded faces to draw: the
   * time a web font may hold its text invisible before the engine gives up
   * on it. */
  const PICTURE_FACES_WAIT_MS = 3000;

  let pictureFacesPromise = null;

  /**
   * Waits, once a page, until the engine draws text in every bundled face
   * inside a picture, or [PICTURE_FACES_WAIT_MS] has passed; it never fails.
   *
   * A picture is the drawing handed to the engine as an image, with the
   * faces embedded in it, and the engine loads an embedded face for an image
   * apart from the page's own, each face apart from the others; an image
   * decoded before a face has loaded draws the text in that face as nothing.
   * A specimen with a line in each face, each in a band of its own, is drawn
   * through the same path until every band holds ink, which only text drawn
   * in a loaded face leaves.
   */
  function pictureFacesReady() {
    if (!pictureFacesPromise) {
      pictureFacesPromise = waitForPictureFaces().catch(() => undefined);
    }
    return pictureFacesPromise;
  }

  async function waitForPictureFaces() {
    const fonts = document.getElementById('finch-fonts');
    if (!fonts || CONFIG.faces.length === 0) return;
    const band = 24;
    const width = 120;
    const height = band * CONFIG.faces.length;
    const specimen = document.createElementNS(SVG_NS, 'svg');
    specimen.setAttribute('width', String(width));
    specimen.setAttribute('height', String(height));
    const style = document.createElementNS(SVG_NS, 'style');
    style.textContent = fonts.textContent;
    specimen.appendChild(style);
    CONFIG.faces.forEach((face, index) => {
      const text = document.createElementNS(SVG_NS, 'text');
      text.setAttribute('x', '2');
      text.setAttribute('y', String(18 + band * index));
      text.setAttribute('font-family', cssFamily());
      text.setAttribute('font-weight', String(face.weight));
      text.setAttribute('font-size', '16');
      text.textContent = 'Abc';
      specimen.appendChild(text);
    });
    const source = 'data:image/svg+xml;charset=utf-8,' +
      encodeURIComponent(new XMLSerializer().serializeToString(specimen));
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    const deadline = now() + PICTURE_FACES_WAIT_MS;
    const inked = (pixels, index) => {
      for (let at = band * width * 4 * index + 3;
        at < band * width * 4 * (index + 1); at += 4) {
        if (pixels[at] !== 0) return true;
      }
      return false;
    };
    for (;;) {
      const left = deadline - now();
      if (left <= 0) return;
      const image = new Image();
      image.src = source;
      let timer = null;
      await Promise.race([
        image.decode(),
        new Promise((resolve, reject) => {
          timer = setTimeout(() => reject(new Error('specimen')), left);
        }),
      ]).finally(() => clearTimeout(timer));
      context.clearRect(0, 0, width, height);
      context.drawImage(image, 0, 0);
      const pixels = context.getImageData(0, 0, width, height).data;
      if (CONFIG.faces.every((face, index) => inked(pixels, index))) return;
      await new Promise((resolve) => setTimeout(resolve, 16));
    }
  }

  /**
   * The drawing as the engine's own PNG, with the bundled faces embedded.
   *
   * WebKit on macOS decodes an SVG image at a whole number of pixels, cutting
   * a fractional size down, and fits the viewBox into that size, centred. A
   * drawing handed over at its own fractional size would come out narrower
   * or shorter than it is, and stretching that onto the canvas would not
   * undo it on both axes. So the image is handed over at the canvas's own
   * whole size, with the viewBox grown from the same origin to match: every
   * unit is then exactly the pixel scale on both axes, and the fraction of a
   * unit added at the right and bottom is outside the drawing's viewBox.
   */
  async function rasterise(root, width, height, scale) {
    await pictureFacesReady();
    const pixelScale = rasterScale(width, height, scale);
    const pixelWidth = Math.ceil(width * pixelScale);
    const pixelHeight = Math.ceil(height * pixelScale);
    const box = root.viewBox.baseVal;
    const clone = root.cloneNode(true);
    clone.setAttribute('viewBox', [box.x, box.y, pixelWidth / pixelScale,
      pixelHeight / pixelScale].map(num).join(' '));
    clone.setAttribute('width', String(pixelWidth));
    clone.setAttribute('height', String(pixelHeight));
    clone.removeAttribute('style');
    const fonts = document.getElementById('finch-fonts');
    if (fonts) {
      const style = document.createElementNS(SVG_NS, 'style');
      style.textContent = fonts.textContent;
      clone.insertBefore(style, clone.firstChild);
    }
    const text = new XMLSerializer().serializeToString(clone);
    const image = new Image();
    image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(text);
    try {
      await image.decode();
    } catch (error) {
      throw unflattenable('The engine could not draw the diagram as an image.');
    }
    const canvas = document.createElement('canvas');
    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
    const context = canvas.getContext('2d');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    let url;
    try {
      url = canvas.toDataURL('image/png');
    } catch (error) {
      throw unflattenable(
        'The engine refused to read the diagram back as an image.');
    }
    if (!url.startsWith(PNG_PREFIX)) {
      throw unflattenable('The engine produced no image.');
    }
    return {
      png: url.slice(PNG_PREFIX.length),
      width: width,
      height: height,
      scale: pixelScale,
    };
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  const TYPE_NAMES = {
    'flowchart-v2': 'flowchart', 'flowchart': 'flowchart',
    'flowchart-elk': 'flowchart',
    'classdiagram': 'class', 'class': 'class',
    'statediagram': 'state', 'state': 'state',
    'er': 'er', 'erdiagram': 'er',
    'gitgraph': 'gitgraph',
    'quadrantchart': 'quadrant',
    'requirement': 'requirement', 'requirementdiagram': 'requirement',
  };

  /** The name of a mermaid diagram type that the host's table of types uses. */
  function canonicalType(type) {
    const lower = String(type || '').toLowerCase();
    return TYPE_NAMES[lower] || lower;
  }

  let fontsPromise = null;

  /** Whether the bundled faces are loaded, so measuring text is trustworthy. */
  function fontsReady() {
    if (!fontsPromise) {
      fontsPromise = (async () => {
        if (CONFIG.faces.length === 0) {
          try {
            await document.fonts.ready;
          } catch (error) {
            // ignore
          }
          return true;
        }
        const specimen = (face) =>
          face.weight + ' 16px "' + CONFIG.family + '"';
        try {
          await Promise.all(CONFIG.faces.map(
            (face) => document.fonts.load(specimen(face), 'Abc')));
          await document.fonts.ready;
          return CONFIG.faces.every(
            (face) => document.fonts.check(specimen(face), 'Abc'));
        } catch (error) {
          return false;
        }
      })();
    }
    return fontsPromise;
  }

  /** The family as a font-family value: quoted when it names a bundled face. */
  function cssFamily() {
    return CONFIG.faces.length > 0 ? '"' + CONFIG.family + '"' : CONFIG.family;
  }

  /** Every key named fontFamily in the default configuration, set to the
   * bundled family. */
  function fontFamilyOverrides() {
    const defaults = mermaid.mermaidAPI.defaultConfig;
    const overrides = {};
    const walk = (source, target) => {
      for (const [key, value] of Object.entries(source)) {
        if (/fontfamily$/i.test(key)) {
          target[key] = cssFamily();
        } else if (value && typeof value === 'object' &&
            !Array.isArray(value)) {
          const child = {};
          walk(value, child);
          if (Object.keys(child).length > 0) target[key] = child;
        }
      }
    };
    walk(defaults, overrides);
    overrides.fontFamily = cssFamily();
    return overrides;
  }

  /**
   * The keys a source may not set in a directive or its front matter, which
   * hold mermaid to the page's level, limits, labels and family, and to
   * what a shape and a label cost; mermaid removes a secure key from a
   * source's configuration wherever it is nested. `numIter` is the most
   * steps the layout of an architecture diagram takes, 2500, which the
   * layout copies into the constants it runs every layout under. `look` and
   * `layout`, the diagram's own as well, and `elk` and the keys mermaid
   * passes to ELK (`nodePlacementStrategy`, `nodePlacementAlignment`,
   * `mergeEdges`, `layeringStrategy`, `layeringLayerBound`,
   * `cycleBreakingStrategy`, `preset`, `considerModelOrder`,
   * `forceNodeModelOrder`, `keepEntryNodeOnTop`, `orientFeedbackEdges`,
   * `straightenEdges`, `lineHops`) keep the `neo` look and the layout and
   * [ELK_PLACEMENT] the page counts for (`elk`, or `cose-bilkent` for a
   * mindmap): the hand-drawn look fills a shape with hatching in proportion
   * to its area, and a label of a thousand characters at a font size of 2000
   * took nine seconds, and another layout such as `tidy-tree` or `elk.stress`
   * or another ELK strategy such as `NETWORK_SIMPLEX` has costs the page's
   * bounds do not cover.
   * `wrap`, `width`, `wrappingWidth`, `maxNodeWidth`, `maxLabelWidth`,
   * `sectionWidth` and `actorMargin` keep the widths mermaid wraps text to,
   * which measures the line again for each word it adds, so a line as wide
   * as a source asks costs the square of its words: a sequence message of
   * eight thousand words wrapped ten million wide took nine seconds. So do
   * the sizes a width text is wrapped to is made of: a sequence diagram's
   * `wrapPadding`, which widens a message, a note and an actor's
   * description by twice itself where it is negative and a message's gap
   * where it is not, `boxMargin` and `boxTextMargin`, which widen a box's
   * name, `noteMargin`, which widens a note beside an actor,
   * `activationWidth`, which widens the gap from an activated actor, and
   * `labelBoxWidth`, which widens a loop's label where it is negative; and
   * an architecture diagram's `iconSize`, a service title being wrapped to
   * an icon and a half, and `padding`, `idealEdgeLengthMultiplier` and
   * `nodeSeparation`, which set a group's box and an edge's length, the
   * widths a group's title and an edge's label are wrapped to. Every key
   * that names a font family or a size of text is secure as well
   * ([secureKeys]).
   */
  const SECURE_KEYS = [
    'secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
    'suppressErrorRendering', 'maxEdges', 'htmlLabels', 'fontFamily',
    'altFontFamily', 'themeCSS', 'numIter', 'look', 'layout', 'elk',
    'nodePlacementStrategy', 'nodePlacementAlignment', 'mergeEdges',
    'layeringStrategy', 'layeringLayerBound', 'cycleBreakingStrategy',
    'preset', 'considerModelOrder', 'forceNodeModelOrder',
    'keepEntryNodeOnTop', 'orientFeedbackEdges', 'straightenEdges',
    'lineHops', 'wrap', 'width', 'wrappingWidth', 'maxNodeWidth',
    'maxLabelWidth', 'sectionWidth', 'actorMargin', 'wrapPadding',
    'boxMargin', 'boxTextMargin', 'noteMargin', 'activationWidth',
    'labelBoxWidth', 'iconSize', 'padding', 'idealEdgeLengthMultiplier',
    'nodeSeparation', 'fontSize', 'textPlacement'];

  /** A configuration key that names a size of text. */
  const TEXT_SIZE_KEY = /(?:font|text)size/i;

  /**
   * [SECURE_KEYS]; the name of each key of [fonts], the font families the
   * page sets ([fontFamilyOverrides]), so a source can set none of them and
   * its text is measured in the family the application draws it in; each key
   * of mermaid's default `elk` configuration; and each key of mermaid's
   * configuration that names a size of text, such as a sequence diagram's
   * `messageFontSize`, so text is measured at the size mermaid gives it.
   */
  function secureKeys(fonts) {
    const keys = new Set(SECURE_KEYS);
    const walk = (level, only) => {
      for (const [key, value] of Object.entries(level)) {
        if (value && typeof value === 'object' && !Array.isArray(value)) {
          walk(value, only);
        } else if (only.test(key)) {
          keys.add(key);
        }
      }
    };
    walk(fonts, /(?:)/);
    walk(mermaid.mermaidAPI.defaultConfig.elk || {}, /(?:)/);
    walk(mermaid.mermaidAPI.defaultConfig, TEXT_SIZE_KEY);
    return Array.from(keys);
  }

  /**
   * Whether [source] is a mindmap, which keeps its radial layout: whether
   * mermaid reads its type as one, past front matter, directives over any
   * number of lines and comments, under any line ends, on a fresh page before
   * mermaid has been initialised as well. A source of no type mermaid knows
   * is not one.
   */
  function isMindmap(source) {
    try {
      if (mermaid.getRegisteredDiagramsMetadata().length === 0) {
        mermaid.initialize({startOnLoad: false, securityLevel: 'strict'});
      }
      return mermaid.detectType(String(source)) === 'mindmap';
    } catch (error) {
      return false;
    }
  }

  /**
   * Whether [source] is a swimlane diagram, which runs the `swimlane` layout
   * algorithm rather than ELK: whether mermaid reads its type as one from the
   * preprocessed text `Diagram.fromText` hands `detectType`, past front
   * matter, directives over any number of lines and comment lines, under any
   * line ends, on a fresh page before mermaid has been initialised as well,
   * and where collapsing newlines inside angle-bracket tags before stripping
   * comment lines agrees on `swimlane`. A source of no type mermaid knows is
   * not one.
   */
  function isSwimlane(source) {
    try {
      if (mermaid.getRegisteredDiagramsMetadata().length === 0) {
        mermaid.initialize({startOnLoad: false, securityLevel: 'strict'});
      }
      const normalized = String(source).replace(/\r\n?/g, '\n');
      const clean = (text) => text
        .replace(/^([ \t]*)---[ \t]*\n[\s\S]*?\n\1---[ \t]*(?:\n|$)/, '')
        .replace(
          /%{2}\{\s*(?:(\w+)\s*:|(\w+))\s*(?:(\w+)|((?:(?!\}%{2}).|\n)*))?\s*(?:\}%{2})?/gi,
          '')
        .replace(/^\s*%%(?!\{)[^\n]+\n?/gm, '')
        .trimStart();
      const cleaned = clean(normalized);
      if (mermaid.detectType(cleaned) !== 'swimlane') return false;
      if (/<(\w+)([^>]*)>/.test(normalized)) {
        const collapsed = clean(
          normalized.replace(
            /<(\w+)([^>]*)>/g, (match) => match.replace(/\n+/g, ' ')));
        if (mermaid.detectType(collapsed) !== 'swimlane') return false;
      }
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * How ELK places what it lays out: each parent centred over its children,
   * edges kept apart, and a cycle broken where the fewest edges turn back.
   */
  const ELK_PLACEMENT = {
    nodePlacementAlignment: 'BALANCED',
    mergeEdges: false,
    nodePlacementStrategy: 'BRANDES_KOEPF',
    cycleBreakingStrategy: 'GREEDY',
  };

  /**
   * The configuration of one drawing.
   *
   * The `default` or `dark` theme, a flowchart padding of 48, gantt and pie
   * charts laid out 1200 wide and a sequence diagram's vertical margin of
   * 40. Every diagram is drawn in the `neo` look and
   * laid out by the ELK layout mermaid bundles, placed by [ELK_PLACEMENT],
   * except a mindmap, which keeps the radial `cose-bilkent` layout, and a
   * swimlane diagram, which runs the `swimlane` layout: a
   * layout set here is taken for a mindmap or swimlane as well, which would
   * otherwise pick its own. Both `look` and `layout`, the diagram's own as
   * well, are secure ([SECURE_KEYS]). Mermaid runs at its strict level with
   * plain-text labels, the limits and the secure keys, every key that names a
   * font family or a size of text among them.
   */
  function mermaidConfiguration(request) {
    const config = fontFamilyOverrides();
    const secure = secureKeys(config);
    config.themeVariables = Object.assign(
      {}, request.themeVariables || {}, config.themeVariables || {});
    config.themeVariables.fontFamily = cssFamily();
    return Object.assign(config, {
      startOnLoad: false,
      securityLevel: 'strict',
      theme: request.dark ? 'dark' : 'default',
      look: 'neo',
      layout: isSwimlane(request.source || '')
        ? 'swimlane'
        : isMindmap(request.source || '') ? 'cose-bilkent' : 'elk',
      elk: Object.assign({}, config.elk || {}, ELK_PLACEMENT),
      htmlLabels: false,
      // Some of mermaid's shapes read the flowchart's own key and not the
      // top-level one, so both are set.
      flowchart: Object.assign(
        {}, config.flowchart || {}, {htmlLabels: false, diagramPadding: 48}),
      gantt: Object.assign({}, config.gantt || {}, {useWidth: 1200}),
      pie: Object.assign({}, config.pie || {}, {useWidth: 1200}),
      sequence: Object.assign({}, config.sequence || {}, {diagramMarginY: 40}),
      // A journey's task names are HTML in a foreignObject by default, which
      // no engine draws in a picture and the flattening refuses: SVG text,
      // as every other diagram's labels are.
      journey: Object.assign(
        {}, config.journey || {}, {textPlacement: 'tspan'}),
      suppressErrorRendering: true,
      maxTextSize: LIMITS.maxSourceChars,
      maxEdges: LIMITS.maxEdges,
      deterministicIds: true,
      deterministicIDSeed: 'finch',
      // The paths of a node are jittered by a random seed unless one is
      // given, so a diagram would be drawn differently each time it was drawn.
      handDrawnSeed: 1,
      secure: secure,
    });
  }

  /**
   * What ends a statement: a line break, a carriage return on its own, which
   * mermaid reads as one, a line or paragraph separator, which can be all
   * that is left between two of a flowchart's statements once a comment
   * line is removed, and a semicolon, which many of its diagram types read
   * as one.
   */
  const STATEMENT_END = /[\n\r\u2028\u2029;]/;

  /**
   * A name a source can give a node, a state or a participant: a run of
   * letters, digits and underscores in any script, which may go on with dots
   * and hyphens.
   */
  const SOURCE_NAME = /[\p{L}\p{N}_][\p{L}\p{N}_.-]*/gu;

  /**
   * What draws an edge in mermaid's diagram types: the two characters every
   * one of their arrows and links holds, such as `-->`, `->>`, `==>`, `-.->`,
   * `..>`, `<|--`, `||--o{` and `~~~`.
   */
  const EDGE_MARK = /--|->|==|\.\.|~~/g;

  /**
   * A token of a railroad grammar, in any of its notations, or a part of
   * one: a run of letters, digits and underscores, or any other mark that is
   * not a space. A quoted terminal is counted a part at a time as well, its
   * quotes among them, so a quote mermaid does not read as one, in a
   * comment or a directive it removes, joins none of the tokens up to the
   * next quote into one.
   */
  const GRAMMAR_TOKEN = /[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]/gu;

  /**
   * What the source of a diagram type holds one of for each item it draws,
   * where neither the statements nor the parsed diagram count the items
   * before they cost: each word and line break of a timeline, and the colon
   * before each of its events, since mermaid fits an event's words to its
   * width by adding one at a time and measuring the whole event again, a
   * time that grows with the square of its words; the comma between an XY
   * chart's categories and values, a radar chart's axes and values and a
   * journey task's actors, a list one statement can hold thousands of,
   * whose databases hand no layout their nodes and edges, and each `axis`
   * and `curve` of a radar chart, since its grammar takes thousands of
   * those on one line with nothing between them, and one of a single name
   * or value holds no comma; the line of each node of a mindmap and each
   * section or card of a kanban board, whose databases read out their nodes
   * and edges in a time that grows faster than they do; each token of a
   * railroad grammar, a rule of thousands of which is one statement, whose
   * parse takes up to a fifth of a millisecond for each; each name in a
   * block diagram, a line of thousands of which, the same name or `space`
   * again and again, is one statement of as many blocks, whose parse grows
   * faster than they do; each quoted item of a cynefin diagram, whose
   * grammar takes any number of strings on one line; and each line of a
   * treeView diagram and each line and `<br>` line break of an ishikawa
   * diagram, whose renderers measure each node or line in the page.
   */
  const ITEM_MARKS = {
    timeline: /<br\s*\/?>|[^\s:<]+|[:<]/gi,
    xychart: /,/g,
    radar: /,|\b(?:axis|curve)\b/g,
    journey: /,/g,
    mindmap: /\S[^\n\r]*/g,
    kanban: /\S[^\n\r]*/g,
    railroad: GRAMMAR_TOKEN,
    railroadEbnf: GRAMMAR_TOKEN,
    railroadAbnf: GRAMMAR_TOKEN,
    railroadPeg: GRAMMAR_TOKEN,
    block: SOURCE_NAME,
    cynefin: /"[^"\\]*(?:\\.[^"\\]*)*"|'[^'\\]*(?:\\.[^'\\]*)*'/g,
    treeView: /\S[^\n\r]*/g,
    ishikawa: /<br\s*\/?>|^[ \t]*(?=\S)/gim,
  };

  /**
   * The diagram types whose databases hand a layout their nodes and edges
   * through `getData`.
   */
  const GET_DATA_TYPES = new Set([
    'flowchart-v2', 'flowchart-elk', 'classDiagram', 'stateDiagram', 'er',
    'requirement', 'mindmap', 'kanban', 'agentflow', 'swimlane', 'usecase']);

  /**
   * A space in a block diagram's source and the columns it is wide, as
   * mermaid's lexer reads it: in lower case, with no space around the colon.
   */
  const SPACE_WIDTH = /space:(\d+)/g;

  /**
   * The blocks a block diagram's parse makes of the spaces in [source]: a
   * block for each column of each space's width, which the parse makes one
   * at a time before anything can count them.
   */
  function spaceBlocks(source) {
    let blocks = 0;
    for (const match of source.matchAll(SPACE_WIDTH)) {
      blocks += Number(match[1]);
    }
    return blocks;
  }

  /**
   * Mermaid's pattern for a directive, from `%%{` to `}%%` or the end of the
   * source, which it removes wherever it stands before it parses a source.
   */
  const DIRECTIVE = new RegExp(
    '%{2}{\\s*(?:(\\w+)\\s*:|(\\w+))\\s*(?:(\\w+)|' +
    '((?:(?!}%{2}).|\\r?\\n)*))?\\s*(?:}%{2})?', 'gi');

  /** White space, as mermaid's front matter and comments read it. */
  const BLANK = /\s/;

  /**
   * What ends a line where mermaid reads a source by lines with a pattern:
   * a line break, a carriage return, and the line and paragraph separators.
   */
  const LINE_TERMINATOR = /[\n\r\u2028\u2029]/;

  /** Whether [char] ends a line of front matter, as mermaid reads one. */
  function isFrontMatterBreak(char) {
    return char === '\n' || char === '\r';
  }

  /**
   * The last line break in the white space from [start] in [text], or -1
   * where that white space holds none.
   */
  function lastBreakInBlank(text, start) {
    let last = -1;
    for (let at = start; at < text.length && BLANK.test(text[at]); at++) {
      if (isFrontMatterBreak(text[at])) last = at;
    }
    return last;
  }

  /**
   * The characters of the front matter mermaid takes from the start of
   * [text], or none, read as mermaid 12 reads it: `---` after an indent of
   * spaces or tabs, white space holding a line break, and the first line of
   * the same indent and `---` after it that white space holding a line
   * break follows, to that white space's last line break.
   */
  function frontMatterLength(text) {
    let indent = 0;
    while (indent < text.length && BLANK.test(text[indent]) &&
        !isFrontMatterBreak(text[indent])) {
      indent += 1;
    }
    if (!text.startsWith('---', indent)) return 0;
    const opening = [];
    for (let at = indent + 3; at < text.length && BLANK.test(text[at]);
        at++) {
      if (isFrontMatterBreak(text[at])) opening.push(at);
    }
    if (opening.length === 0) return 0;
    const fence = text.slice(0, indent) + '---';
    const closingEnd = (at) => isFrontMatterBreak(text[at]) &&
      text.startsWith(fence, at + 1) ?
      lastBreakInBlank(text, at + 1 + fence.length) : -1;
    let lastClosing = -1;
    for (let at = opening[0] + 1; at < text.length; at++) {
      if (closingEnd(at) !== -1) lastClosing = at;
    }
    if (lastClosing === -1) return 0;
    let body = opening[0];
    for (const at of opening) {
      if (at < lastClosing) body = at;
    }
    for (let at = body + 1; at <= lastClosing; at++) {
      const end = closingEnd(at);
      if (end !== -1) return end + 1;
    }
    return 0;
  }

  /**
   * [text] without the lines mermaid removes as comments, and the white
   * space it then opens with, as `/^\s*%%(?!{)[^\n]+\n?/gm` and
   * `trimStart` remove them, read once: a line whose white space, over any
   * blank lines before it, runs to `%%` followed by anything but `{`, to
   * its line break. Beside it, the steps mermaid's pattern takes over
   * [text]: at each line start it takes the white space there, over any
   * blank lines, and gives it back a character at a time, so a run of blank
   * lines costs the square of its length.
   */
  function withoutCommentLines(text) {
    const kept = [];
    let copied = 0;
    let start = 0;
    let steps = 0;
    while (start < text.length) {
      let end = start;
      while (end < text.length && BLANK.test(text[end])) end += 1;
      for (let at = start; at < end; at++) {
        if (at === start || LINE_TERMINATOR.test(text[at - 1])) {
          steps += 2 * (end - at);
        }
      }
      if (text.startsWith('%%', end) && end + 2 < text.length &&
          text[end + 2] !== '{' && text[end + 2] !== '\n') {
        const lineEnd = text.indexOf('\n', end + 2);
        kept.push(text.slice(copied, start));
        copied = start = lineEnd === -1 ? text.length : lineEnd + 1;
        steps += start - end;
      } else {
        // Every line start in the white space runs to the same end.
        let next = end;
        while (next < text.length && !LINE_TERMINATOR.test(text[next])) {
          next += 1;
        }
        steps += next + 1 - end;
        start = next + 1;
      }
    }
    kept.push(text.slice(copied));
    return {text: kept.join('').trimStart(), steps};
  }

  /** A character of a word, as mermaid's patterns read one (`\w`). */
  const WORD_CHAR = /\w/;

  /**
   * The steps mermaid's pattern for an HTML tag, `/<(\w+)([^>]*)>/g`, takes
   * over [text], which it runs before anything else reads a source: a `<`
   * and a word that no `>` follows takes the rest of the text and gives it
   * back once for each character of the word, so a tag that never closes
   * costs the square of its length, and a run of them the square of the
   * run.
   */
  function tagSteps(text) {
    let steps = text.length;
    const lastClose = text.lastIndexOf('>');
    for (let at = text.indexOf('<', lastClose + 1); at !== -1;
        at = text.indexOf('<', at + 1)) {
      let word = at + 1;
      while (word < text.length && WORD_CHAR.test(text[word])) word += 1;
      steps += 2 * (word - at - 1) * (text.length - at);
    }
    return steps;
  }

  /**
   * The steps mermaid's pattern for the last semicolon of a [keyword]
   * definition, `/<keyword>.*:\S*#.*;/g`, takes over [text] where it finds
   * none: from each place the keyword stands it takes the rest of the line
   * and gives it back; at each colon it gives back the word after it; and
   * at each `#` in that word it takes the rest of the line again and gives
   * it back, so a line of colons and marks costs the cube of its length.
   */
  function definitionSteps(text, keyword) {
    let steps = 0;
    for (const line of text.split(LINE_TERMINATOR)) {
      let starts = 0;
      let reaching = 0;
      for (let at = line.indexOf(keyword); at !== -1 && at < line.length;
          at++) {
        if (line.startsWith(keyword, at)) {
          starts += 1;
          steps += 2 * (line.length - at);
        }
        const char = line[at];
        if (BLANK.test(char)) {
          reaching = 0;
        } else {
          steps += 2 * reaching;
          if (char === ':') reaching += starts;
          if (char === '#') steps += 2 * reaching * (line.length - at);
        }
      }
    }
    return steps;
  }

  /**
   * The most steps mermaid's patterns may take to read a source before it
   * parses it, each time it reads it: a parse, the parse of the diagram the
   * page counts, and the drawing. In JavaScriptCore a step of these
   * patterns took from half a nanosecond to six, so a source at the bound
   * is read in at most a twentieth of a second; the recorded fixtures take
   * under a tenth of it.
   */
  const MAX_PREPROCESS_STEPS = 10000000;

  /**
   * [text] with the last semicolon of each line that [keyword] opens a
   * definition on removed, as mermaid removes it with
   * `/<keyword>.*:\S*#.*;/g`, read once a line: a line that holds the
   * keyword, then a colon with a `#` after it before any white space, then
   * a semicolon.
   */
  function withoutLastSemicolon(text, keyword) {
    const lines = text.split(/([\n\r\u2028\u2029])/);
    for (let index = 0; index < lines.length; index += 2) {
      const line = lines[index];
      const from = line.indexOf(keyword);
      const last = line.lastIndexOf(';');
      if (from === -1 || last === -1) continue;
      let afterColon = false;
      for (let at = from + keyword.length; at < last; at++) {
        if (line[at] === '#' && afterColon) {
          lines[index] = line.slice(0, last) + line.slice(last + 1);
          break;
        }
        if (line[at] === ':') afterColon = true;
        else if (BLANK.test(line[at])) afterColon = false;
      }
    }
    return lines.join('');
  }

  /**
   * [text] as mermaid hands it to a diagram's parser, its `encodeEntities`:
   * a style statement's and a class definition's last semicolon removed,
   * and each entity such as `#quot;` or `#9829;` written as marks of its
   * own, which the parser reads back after.
   */
  function withEntitiesEncoded(text) {
    const encoded = withoutLastSemicolon(
      withoutLastSemicolon(text, 'style'), 'classDef');
    return encoded.replace(/#\w+;/g, (entity) => {
      const name = entity.slice(1, -1);
      return (/^\+?\d+$/.test(name) ? '\uFB02\xB0\xB0' : '\uFB02\xB0') +
        name + '\xB6\xDF';
    });
  }

  /**
   * The text mermaid's parser reads of [source] (its `preprocessDiagram`
   * and `encodeEntities`): line ends made line breaks, and no front matter,
   * directive or comment line, a flowchart's comment lines aside, which its
   * parser reads past. Mermaid also writes an HTML tag's attributes in
   * single quotes for double, which changes no count of a source. Beside
   * it, the steps mermaid's patterns that backtrack take to read [source]
   * so: its tags', its comments' and its definitions' ([tagSteps],
   * [withoutCommentLines], [definitionSteps]), a flowchart's comment lines
   * among the lines its definitions are read in, since a flowchart's text
   * keeps them.
   */
  function parsedText(source) {
    const text = source.replace(/\r\n?/g, '\n');
    const body = text.slice(frontMatterLength(text)).replace(DIRECTIVE, '');
    const cleaned = withoutCommentLines(body);
    return {
      text: withEntitiesEncoded(cleaned.text),
      steps: tagSteps(text) + cleaned.steps +
        definitionSteps(body, 'style') + definitionSteps(body, 'classDef'),
    };
  }

  /** Refuses a diagram that hands its drawing more [what] than [limit]. */
  function refuseCount(count, limit, what) {
    if (count > limit) {
      throw new Failure('tooLarge', 'The diagram has ' + count + ' ' + what +
        ', more than the ' + limit + ' drawn.');
    }
  }

  /**
   * What ends a word of a label: a space, a line break or a `<br>`, and no
   * other white space. Mermaid breaks a markdown label into lines at a line
   * break and each line into words at a space alone, so a no-break space or
   * a tab is a part of the word, and a plain label at any white space, which
   * leaves its words no longer than these.
   */
  const WORD_END = /[ \n]|<br\s*\/?>/i;

  /**
   * An image address in a source, or one whose scheme or punctuation is
   * escaped (`image/...;base64,...`), which is held to the image limits
   * rather than drawn as a label's text.
   */
  const SOURCE_NON_TEXT = new RegExp(
    IMAGE_ADDRESS.source + '|' +
    String.raw`image\/[\w.+-]+(?:;|\s*\\3b\s*)base64(?:,|\s*\\2c\s*)[A-Za-z0-9+/=]+`,
    'gi');

  /**
   * What opens a label's first word in a source where no space stands
   * before it: an optional node name, icon or edge mark, and the quote or
   * bracket that opens the label.
   */
  const WORD_OPEN =
    /^(?:[\w-]{1,32}(?:\([\w-]{1,32}\))?|[-=.>~|+]{1,8})?[\["'`({|]{1,4}/;

  /**
   * What closes a label's last word in a source where no space stands after
   * it: the quote, bracket or punctuation that ends the label or clause.
   */
  const WORD_CLOSE = /[\]"'`)}|:;,]{1,4}-?$/;

  /**
   * A line of semicolon-ended node names or a `class` statement's list of
   * node names, each name at most 32 characters, which writes no long word.
   */
  const STATEMENT_LIST =
    /^\s*(?:(?:\w{1,32};)+|class\s+\w{1,32}(?:,\w{1,32})+\s+\w{1,32})\s*$/;

  /**
   * The characters of the longest word in [text], the source text mermaid's
   * parser reads ([parsedText]), past image addresses ([SOURCE_NON_TEXT])
   * and, outside a timeline, lists of short node names ([STATEMENT_LIST]),
   * each word read between [WORD_END] and stripped of the quotes or brackets
   * that open or close its label ([WORD_OPEN], [WORD_CLOSE]).
   */
  function sourceLongestWord(text, type) {
    const cleaned = text.replace(SOURCE_NON_TEXT, ' ');
    let longest = 0;
    for (const line of cleaned.split(LINE_TERMINATOR)) {
      if (type !== 'timeline' && STATEMENT_LIST.test(line)) continue;
      for (const piece of line.split(WORD_END)) {
        const word = piece.replace(WORD_OPEN, '').replace(WORD_CLOSE, '');
        if (word.length > longest) longest = word.length;
      }
    }
    return longest;
  }

  /**
   * The most entries any `stroke-dasharray` declaration in [text] holds, in a
   * `classDef`, `style`, `linkStyle` or any CSS-like declaration, split on
   * commas and white space the way [dashPattern] reads one.
   */
  function sourceDashEntries(text) {
    const key = 'stroke-dasharray';
    const lower = text.toLowerCase();
    let maxEntries = 0;
    for (let at = lower.indexOf(key); at !== -1;
        at = lower.indexOf(key, at + key.length)) {
      if (at > 0 && /[a-z0-9_-]/.test(lower[at - 1])) continue;
      let cursor = at + key.length;
      while (cursor < lower.length &&
          (lower[cursor] === ' ' || lower[cursor] === '\t')) {
        cursor += 1;
      }
      if (lower[cursor] !== ':') continue;
      cursor += 1;
      let end = cursor;
      while (end < lower.length &&
          !/[;\n\r\u2028\u2029}"'!]/.test(lower[end])) {
        end += 1;
      }
      const nextColon = lower.indexOf(':', cursor);
      if (nextColon !== -1 && nextColon < end) {
        let propStart = nextColon;
        while (propStart > cursor &&
            (lower[propStart - 1] === ' ' || lower[propStart - 1] === '\t')) {
          propStart -= 1;
        }
        while (propStart > cursor && /[a-z0-9_-]/.test(lower[propStart - 1])) {
          propStart -= 1;
        }
        end = propStart;
      }
      const entries = lower.slice(cursor, end).trim().split(/[\s,]+/)
        .filter(Boolean).length;
      if (entries > maxEntries) maxEntries = entries;
    }
    return maxEntries;
  }

  /**
   * Refuses [source] when it has more statements, names, edges or listed
   * items than a diagram is drawn with, a `stroke-dasharray` with more
   * entries than `maxSourceDashEntries`, or a word longer than
   * `maxLabelWordChars`, before anything parses it, as empty
   * when it holds no statement at all, with mermaid's own message when it
   * names no type mermaid knows, and naming the type when it names one the
   * page has not bounded (`ITEM_MARKS`, `DIAGRAM_REFUSALS`,
   * `GET_DATA_TYPES`).
   *
   * Mermaid reads every source through patterns that backtrack before any
   * parser sees it, once for each parse and once more for the drawing, so
   * a source whose reading would take them more than
   * `MAX_PREPROCESS_STEPS` ([parsedText]) is refused first: fifty thousand
   * blank lines took its comment pattern seven and a half seconds, and a
   * line of two thousand colons and marks after `style` its entity pattern
   * three quarters of a second, a time that grows with the cube of the
   * line, and with the fourth power where `style` stands again and again.
   *
   * What mermaid's parsers and databases do grows with the statements of a
   * source, and parsing a state diagram's thousand transitions takes most of
   * a second, so they are counted here in one pass over the text mermaid's
   * parser reads ([parsedText]): the statements that are not blank, the
   * distinct names, and the marks that draw an edge, each of which a
   * statement may hold several of. A directive mermaid removes from inside
   * a mark, a name or a number joins its two halves before the parse, and a
   * comment line it removes holds nothing it parses. The type is read as
   * mermaid reads it, past front matter, directives and comments; a type the
   * page has not given a bound is refused before any parser runs, and the
   * items of that type are counted by what marks each
   * (`ITEM_MARKS`): a timeline of thousands of events or an XY chart of
   * thousands of values is one statement, and the chart's parse, like a
   * mindmap's or a kanban board's reading of its nodes, grows faster than
   * what it holds. A block
   * diagram's spaces are counted a block for each column of their width
   * ([spaceBlocks]) and held to `maxSourceNames`, the most blocks it is drawn
   * with: the parse makes a block of each column, so `space:100000000`, one
   * statement of a few characters, would take the parse a minute and tens of
   * gigabytes before the parsed diagram could be counted. Every type's text
   * is held to `maxLabelWordChars` ([sourceLongestWord]) before the parse as
   * well, since mermaid fits or measures a label's words a character at a
   * time across sequence messages (`wrap:`), timelines, git graphs, C4
   * shapes and treemaps as well as the types whose databases expose
   * `getData`, and any `stroke-dasharray` declaration in the source is held
   * to `maxSourceDashEntries` ([sourceDashEntries]) before mermaid applies it
   * to every styled shape during `mermaid.render`.
   */
  function refuseTooLargeSource(source) {
    const {text, steps} = parsedText(source);
    let statements = 0;
    for (const statement of text.split(STATEMENT_END)) {
      if (statement.trim() !== '') statements += 1;
    }
    if (statements === 0) {
      throw new Failure('syntaxError', 'The diagram is empty.');
    }
    if (steps > MAX_PREPROCESS_STEPS) {
      throw new Failure('tooLarge', 'The diagram takes mermaid ' + steps +
        ' steps to read before it parses it, more than the ' +
        MAX_PREPROCESS_STEPS + ' allowed.');
    }
    if (statements > LIMITS.maxSourceStatements) {
      throw new Failure('tooLarge', 'The diagram has ' + statements +
        ' statements, more than the ' + LIMITS.maxSourceStatements +
        ' drawn.');
    }
    const names = new Set(text.match(SOURCE_NAME) || []);
    if (names.size > LIMITS.maxSourceNames) {
      throw new Failure('tooLarge', 'The diagram names ' + names.size +
        ' things, more than the ' + LIMITS.maxSourceNames + ' drawn.');
    }
    const edges = (text.match(EDGE_MARK) || []).length;
    if (edges > LIMITS.maxEdges) {
      throw new Failure('tooLarge', 'The diagram draws ' + edges +
        ' edges, more than the ' + LIMITS.maxEdges + ' drawn.');
    }
    const type = mermaid.detectType(text);
    if (/<(\w+)([^>]*)>/.test(source)) {
      const normalized = source.replace(/\r\n?/g, '\n')
        .replace(/<(\w+)([^>]*)>/g, (match) => match.replace(/\n+/g, ' '));
      const collapsed = withoutCommentLines(
        normalized.slice(frontMatterLength(normalized))
          .replace(DIRECTIVE, '')).text;
      let collapsedType = null;
      try {
        collapsedType = mermaid.detectType(collapsed);
      } catch (_) {}
      if (collapsedType !== type) {
        throw new Failure(
          'tooLarge', 'The diagram type changes across tag preprocessing.');
      }
    }
    if (!Object.prototype.hasOwnProperty.call(ITEM_MARKS, type) &&
        !Object.prototype.hasOwnProperty.call(DIAGRAM_REFUSALS, type) &&
        !GET_DATA_TYPES.has(type)) {
      throw new Failure(
        'syntaxError', 'The diagram type ' + type + ' is not drawn.');
    }
    if (type === 'wardley') {
      const wardleyEdges =
        edges + (text.match(/(?<!-)>|\+<(?!>)/g) || []).length;
      if (wardleyEdges > LIMITS.maxEdges) {
        throw new Failure('tooLarge', 'The diagram draws ' + wardleyEdges +
          ' edges, more than the ' + LIMITS.maxEdges + ' drawn.');
      }
    }
    const mark = ITEM_MARKS[type];
    const items = mark ? (text.match(mark) || []).length : 0;
    if (items > LIMITS.maxSourceItems) {
      throw new Failure('tooLarge', 'The diagram lists ' + items +
        ' items, more than the ' + LIMITS.maxSourceItems + ' drawn.');
    }
    if (type === 'block') {
      refuseCount(spaceBlocks(text), LIMITS.maxSourceNames, 'blocks');
    }
    refuseCount(
      sourceLongestWord(text, type), LIMITS.maxLabelWordChars,
      'characters in one word');
    refuseCount(
      sourceDashEntries(text), LIMITS.maxSourceDashEntries,
      'entries in a dash pattern');
  }

  /**
   * The fields in the rows of a packet diagram's database, a field split
   * across rows counted once in each.
   */
  function packetFields(db) {
    let fields = 0;
    for (const row of db.getPacket()) fields += row.length;
    return fields;
  }

  /**
   * The blocks of a block diagram's database, those inside a composite
   * block among them.
   */
  function blockCount(db) {
    let count = 0;
    const pending = [db.getBlocks()];
    while (pending.length > 0) {
      for (const block of pending.pop()) {
        count += 1;
        if (Array.isArray(block.children)) pending.push(block.children);
      }
    }
    return count;
  }

  /**
   * The times the layout of a block diagram's database sizes its blocks, a
   * block at the top counted once.
   *
   * Mermaid sizes the children of a composite block twice, once to find the
   * widest and again at that width, and each of those sizes the child's own
   * children twice over, so a block is sized twice as often for each
   * composite block it is inside: a chain of twenty took a quarter of a
   * second and one of forty, in six hundred characters, would take days.
   */
  function blockSizings(db) {
    let sizings = 0;
    const pending = [[db.getBlocks(), 1]];
    while (pending.length > 0) {
      const [blocks, times] = pending.pop();
      for (const block of blocks) {
        sizings += times;
        if (Array.isArray(block.children) && block.children.length > 0) {
          pending.push(
            [block.children, Math.min(2 * times, Number.MAX_SAFE_INTEGER)]);
        }
      }
    }
    return sizings;
  }

  /**
   * The areas the layout of a venn diagram's database fits: each set and
   * union it holds, and the pair of every two of its sets that none of them
   * is, which the layout adds.
   */
  function vennAreas(db) {
    const subsets = db.getSubsetData();
    const sets = new Set();
    const pairs = new Set();
    for (const subset of subsets) {
      const names = Array.from(new Set(Array.from(subset.sets || [], String)));
      for (const name of names) sets.add(name);
      if (names.length === 2) pairs.add(names.sort().join('\u0000'));
    }
    return subsets.length + sets.size * (sets.size - 1) / 2 - pairs.size;
  }

  /**
   * Refuses a venn diagram whose union names one of its sets more than once.
   *
   * Mermaid keeps every name a union lists, and its layout measures the
   * overlap of the union's circles over that list at each step it takes:
   * every two circles listed meet in up to two points, and each point is
   * tested against every circle listed, so a measure costs the cube of the
   * list. A union that lists two sets nine hundred times between them took
   * over a second for one measure, of the hundreds the layout takes. A union
   * of distinct sets lists no more than the diagram's sets, which
   * [vennAreas] bounds.
   */
  function refuseRepeatedVennSets(db) {
    for (const subset of db.getSubsetData()) {
      const listed = Array.from(subset.sets || [], String);
      if (new Set(listed).size !== listed.length) {
        throw new Failure('tooLarge', 'A union of the diagram names one of ' +
          'its sets more than once.');
      }
    }
  }

  /** The weekdays a gantt chart excludes by name. */
  const WEEKDAYS = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
    'sunday'];

  const HOUR = 3600000;
  const DAY = 24 * HOUR;

  /** The excluded days past a task's end after which mermaid gives it up. */
  const EXCLUDED_DAYS_GIVEN_UP = 10000;

  /**
   * Whether a gantt chart's date [format] tells each day apart, so a date it
   * excludes is one day: it writes a timestamp, or a year, a month and a day
   * of the month, outside the text it holds in brackets.
   */
  function namesEachDay(format) {
    const tokens = String(format).replace(/\[[^\]]*\]/g, '');
    return /[Xx]/.test(tokens) ||
      (/YYYY/.test(tokens) && /M/.test(tokens) && /D/.test(tokens));
  }

  /** The whole days from [start] to [end], an hour of a clock change aside. */
  function daysBetween(start, end) {
    const days = Math.ceil((end - start - HOUR) / DAY);
    return Number.isFinite(days) ? Math.max(0, days) : 0;
  }

  /**
   * The most times mermaid compiles a gantt chart's tasks: once, and up to
   * ten times more while any task is unresolved.
   */
  const GANTT_COMPILES = 11;

  /** The tasks a gantt task starts after, as mermaid reads its start. */
  const STARTS_AFTER = /^after\s+([\d\w- ]+)/;

  /** The tasks a gantt task ends where they start, as mermaid reads its end. */
  const ENDS_UNTIL = /^until\s+([\d\w- ]+)/;

  /**
   * How many times mermaid compiles the gantt chart's [tasks], read with
   * nothing excluded, each time moving every task it has resolved past the
   * days the chart excludes again.
   *
   * Mermaid compiles every task in order, and all of them again while any is
   * unresolved, up to `GANTT_COMPILES` times. A task is resolved once each
   * task it is read from is: the task before it, where it gives no start,
   * and those it starts after or ends until, the last task of each name.
   * So a task read from one later in the chart waits a compile for it, and
   * two that each start after the other are never resolved.
   */
  function ganttCompiles(tasks) {
    const index = new Map(tasks.map((task, at) => [task.id, at]));
    const named = (pattern, data) => {
      const match = pattern.exec(String(data || '').trim());
      return match ? match[1].split(' ') : [];
    };
    const readFrom = tasks.map((task) => {
      const start = (task.raw && task.raw.startTime) || {};
      const end = (task.raw && task.raw.endTime) || {};
      return [
        ...(start.type === 'prevTaskEnd' ? [task.prevTaskId] : []),
        ...named(STARTS_AFTER, start.startData),
        ...named(ENDS_UNTIL, end.data),
      ].filter((id) => index.has(id)).map((id) => index.get(id));
    });
    const resolved = tasks.map(() => false);
    for (let compile = 1; compile <= GANTT_COMPILES; compile++) {
      let all = true;
      readFrom.forEach((others, at) => {
        resolved[at] = others.every((other) => resolved[other]);
        all = all && resolved[at];
      });
      if (all) return compile;
    }
    return GANTT_COMPILES;
  }

  /**
   * The longest date format, in characters, for which a step past a gantt
   * chart's excluded day is counted once ([ganttStepCost]).
   */
  const STEP_FORMAT_CHARS = 32;

  /**
   * The most days a gantt chart's excludes and includes name together for
   * which a step past an excluded day is counted once ([ganttStepCost]).
   */
  const STEP_LISTED_DAYS = 100;

  /**
   * How many times over a step past an excluded day of the gantt chart in
   * [db] is counted: once for a date format of up to `STEP_FORMAT_CHARS`
   * characters and lists of up to `STEP_LISTED_DAYS` days, and as many times
   * as the format or the lists hold those, whichever is more, past them.
   *
   * Each step writes the day out through the date format and looks it up
   * among the days the chart excludes and includes. In JavaScriptCore a
   * step costs about six microseconds, and each character of a format of
   * short tokens adds a hundredth of that and each date listed a
   * five-hundredth, so a step is counted at no less than two thirds of what
   * it costs, which it comes to at both bounds at once.
   */
  function ganttStepCost(db) {
    const listed = db.getExcludes().length + db.getIncludes().length;
    return Math.max(1, String(db.getDateFormat() || '').length /
      STEP_FORMAT_CHARS, listed / STEP_LISTED_DAYS);
  }

  /**
   * Upper bounds on the days mermaid steps through to move the tasks of the
   * gantt chart in [db] past the days it excludes (`days`), and on the
   * milliseconds from the chart's first start to its last end once they are
   * moved (`span`).
   *
   * Mermaid moves the end of a task it works out, and not one written as a
   * date in the form YYYY-MM-DD, a day at a time from the day after its
   * start, a day further for each excluded day it meets, and gives the task
   * up past `EXCLUDED_DAYS_GIVEN_UP` of those. Excluding k weekdays and D
   * other dates, each one day where the date format tells each day apart, a
   * task of d days ends within 7 / (7 - k) times d + k + D days; with every
   * weekday excluded, or a date that is many days, within d + 10,001. A task
   * that ends where another starts (`until`) ends no later than the chart's
   * last day moved the same way, which bounds the span. Every task is moved
   * again each time mermaid compiles the tasks ([ganttCompiles]). The tasks
   * are read with nothing excluded, which mermaid works out without a step:
   * the database's excluded days are emptied, and the parse that draws the
   * chart holds them again.
   */
  function ganttStepping(db) {
    const excluded = db.getExcludes();
    const weekend = excluded.includes('weekends');
    const named = new Set(excluded.filter((day) => WEEKDAYS.includes(day)));
    const weekdays = named.size + (weekend ? 2 : 0);
    const dates = excluded.length - named.size - (weekend ? 1 : 0);
    const every = weekdays >= 7 ||
      (dates > 0 && !namesEachDay(db.getDateFormat()));
    const factor = 7 / (7 - weekdays);
    const excluding = excluded.length > 0;
    excluded.splice(0);
    if (db.getExcludes().length > 0) return {days: Infinity, span: Infinity};
    const tasks = db.getTasks();
    let first = Infinity;
    let last = -Infinity;
    for (const task of tasks) {
      const start = +task.startTime;
      const end = +task.endTime;
      if (Number.isFinite(start)) first = Math.min(first, start);
      if (Number.isFinite(end)) last = Math.max(last, end);
    }
    const unmoved = first <= last ? last - first : 0;
    if (!excluding) return {days: 0, span: unmoved};
    const stepped = tasks.filter((task) => !task.manualEndTime);
    const range = first <= last ? daysBetween(first, last) : 0;
    const given = EXCLUDED_DAYS_GIVEN_UP + 1;
    const reach = (span) => every ? span + given :
      Math.min(span + given, factor * (span + weekdays + dates));
    const untilSpan = every ? range + given * stepped.length :
      factor * (range + weekdays + dates);
    let total = 0;
    for (const task of stepped) {
      const end = task.raw && task.raw.endTime && task.raw.endTime.data;
      const until = /^\s*until\s/i.test(String(end || ''));
      total += reach(until ? untilSpan :
        daysBetween(task.startTime, task.endTime));
    }
    return {
      days: total * ganttCompiles(tasks),
      span: unmoved + Math.max(0, untilSpan - range) * DAY,
    };
  }

  /** A gantt chart's tick interval, as mermaid reads it. */
  const TICK_INTERVAL =
    /^([1-9]\d*)(millisecond|second|minute|hour|day|week|month)$/;

  /**
   * The milliseconds of each unit of a tick interval, as mermaid estimates
   * the ticks of one: a month is 2,628,000,000, about 30.4 days.
   */
  const TICK_UNIT = {
    millisecond: 1, second: 1000, minute: 60000, hour: HOUR, day: DAY,
    week: 7 * DAY, month: 2628000000,
  };

  /**
   * The most ticks mermaid estimates an axis at for its tick interval;
   * past this it leaves the ticks to d3.
   */
  const MAX_INTERVAL_TICKS = 10000;

  /**
   * The most ticks d3 gives an axis of no tick interval: it aims for ten,
   * at an interval it picks from steps at most five times apart, nearest a
   * tenth of the axis, so it draws at most about twenty-four.
   */
  const D3_TICKS = 30;

  /**
   * The most characters each directive of a d3 time format writes in the
   * locale mermaid draws in: `%A` "Wednesday", `%B` "September", `%c`
   * "12/31/2000, 11:59:59 PM", `%Q` and `%s` milliseconds and seconds from
   * 1970 to the last day a date holds, a year as -9999 at its widest. A
   * directive not here writes its own letter.
   */
  const DIRECTIVE_CHARS = {
    a: 3, A: 9, b: 3, B: 9, c: 24, d: 2, e: 2, f: 6, g: 3, G: 5, H: 2, I: 2,
    j: 3, L: 3, m: 2, M: 2, p: 2, q: 1, Q: 17, s: 14, S: 2, u: 1, U: 2, V: 2,
    w: 1, W: 2, x: 11, X: 11, y: 3, Y: 5, Z: 5,
  };

  /**
   * The most characters a label written through the d3 time [format]
   * holds: each directive at its widest, a `-`, `_` or `0` after the `%`
   * choosing only its padding, and each other character as itself.
   */
  function labelChars(format) {
    const text = String(format);
    let chars = 0;
    for (let at = 0; at < text.length; at++) {
      if (text[at] !== '%' || at + 1 === text.length) {
        chars += 1;
        continue;
      }
      at += 1;
      if ('-_0'.includes(text[at]) && at + 1 < text.length) at += 1;
      chars += Object.prototype.hasOwnProperty.call(DIRECTIVE_CHARS, text[at])
        ? DIRECTIVE_CHARS[text[at]] : 1;
    }
    return chars;
  }

  /**
   * The most characters the axes of the gantt chart in [db] write, across
   * [span] milliseconds once its tasks are moved: a label of its axis
   * format at its widest for each tick, on the top axis as well where it
   * draws one.
   *
   * The format, the tick interval and the top axis are read as mermaid's
   * renderer reads them, from the chart's statements and then from the
   * configuration it is drawn under, its directive and front matter among
   * it. Mermaid estimates an axis's ticks as the span divided by the
   * interval, and leaves an axis estimated past `MAX_INTERVAL_TICKS` to d3
   * ([D3_TICKS]); d3 draws a tick at every interval within the span, which
   * a month of 28 days, or a day a clock change shortens, makes up to a
   * tenth more than the estimate, and one more at its end.
   */
  function axisChars(db, span) {
    const config = db.getConfig() || {};
    const format = ganttAxisFormat(db);
    const interval = TICK_INTERVAL.exec(
      db.getTickInterval() || config.tickInterval || '');
    let ticks = D3_TICKS;
    if (interval !== null) {
      const estimate = Math.ceil(
        span / (Number(interval[1]) * TICK_UNIT[interval[2]]));
      ticks = Math.max(ticks,
        Math.ceil(Math.min(estimate, MAX_INTERVAL_TICKS) * 1.1) + 1);
    }
    const axes = db.topAxisEnabled() || config.topAxis ? 2 : 1;
    return axes * ticks * labelChars(format);
  }

  /**
   * The axis format of the gantt chart in [db], as mermaid's renderer reads
   * it: the chart's own, or the day of the month for a date format of days,
   * or the one the configuration it is drawn under gives.
   */
  function ganttAxisFormat(db) {
    const config = db.getConfig() || {};
    if (db.getAxisFormat()) return db.getAxisFormat();
    if (db.getDateFormat() === 'D') return '%d';
    return config.axisFormat ?? '%Y-%m-%d';
  }

  /**
   * Refuses the gantt chart in [db] whose date or axis format is longer than
   * `maxGanttFormatChars`; past the days mermaid steps through to move its
   * tasks past those it excludes, `maxGanttSteppedDays` divided by what a
   * step through its date format and lists is counted as
   * ([ganttStepCost]); or whose axes write more than `maxDrawnTextChars`
   * characters ([axisChars]), the most text a drawing lays out.
   */
  function refuseLargeGantt(db) {
    for (const [what, format] of [
      ['date', db.getDateFormat()], ['axis', ganttAxisFormat(db)]]) {
      if (String(format || '').length > LIMITS.maxGanttFormatChars) {
        throw new Failure('tooLarge', 'The diagram\'s ' + what +
          ' format is longer than ' + LIMITS.maxGanttFormatChars +
          ' characters.');
      }
    }
    const cost = ganttStepCost(db);
    const drawn = Math.floor(LIMITS.maxGanttSteppedDays / cost);
    const stepping = ganttStepping(db);
    const days = Math.ceil(stepping.days);
    if (!(days <= drawn)) {
      throw new Failure('tooLarge', 'The diagram steps through up to ' +
        days + ' days to pass the days it excludes, more than the ' + drawn +
        (cost > 1 ? ' drawn for its date format and the days it lists.' :
          ' drawn.'));
    }
    const chars = axisChars(db, stepping.span);
    if (!(chars <= LIMITS.maxDrawnTextChars)) {
      throw new Failure('tooLarge', 'The diagram\'s axis labels hold up to ' +
        chars + ' characters, more than the ' + LIMITS.maxDrawnTextChars +
        ' drawn.');
    }
  }

  /**
   * Keys of what a parsed diagram hands its layout whose strings are not
   * drawn as text: the image a node shows, the address it links to, its
   * element's id, and its styles and classes.
   */
  const UNDRAWN_KEYS = new Set([
    'img', 'link', 'linkTarget', 'domId', 'cssStyles', 'cssCompiledStyles',
    'cssClasses', 'classes', 'styles', 'labelStyle', 'style']);

  /**
   * The characters of the longest word in any string [value] holds, itself
   * or in any array or object it holds, past `UNDRAWN_KEYS`: the labels,
   * members, descriptions and other text a parsed diagram hands its layout.
   */
  function longestWord(value) {
    let longest = 0;
    const seen = new Set();
    const pending = [value];
    while (pending.length > 0) {
      const next = pending.pop();
      if (typeof next === 'string') {
        for (const word of next.split(WORD_END)) {
          longest = Math.max(longest, word.length);
        }
      } else if (next && typeof next === 'object' && !seen.has(next)) {
        seen.add(next);
        for (const [key, child] of Object.entries(next)) {
          if (!UNDRAWN_KEYS.has(key)) pending.push(child);
        }
      }
    }
    return longest;
  }

  /**
   * Refuses a diagram whose text, [value] as [longestWord] reads it, holds a
   * word longer than `maxLabelWordChars`.
   *
   * Mermaid fits a word wider than its label a character at a time, copying
   * the rest of the word and measuring the line at each, so a word costs
   * about the square of its length: one of forty thousand characters took
   * ten seconds before the engine's stack ran out.
   */
  function refuseLongWord(value) {
    refuseCount(longestWord(value), LIMITS.maxLabelWordChars,
      'characters in one word');
  }

  /**
   * The most events or periods a timeline is drawn with, the most words one
   * event, period or section holds, and the most words a timeline holds in
   * total, once mermaid has parsed its sections, periods and events.
   */
  const MAX_TIMELINE_EVENTS = 200;
  const MAX_TIMELINE_EVENT_WORDS = 100;
  const MAX_TIMELINE_WORDS = 300;

  /**
   * The words of [text] as mermaid's timeline wrapper splits it, at spaces
   * and `<br>` line breaks.
   */
  function timelineWords(text) {
    const matches = String(text || '')
      .replace(/<br\s*\/?>/gi, ' ')
      .match(/\S+/g);
    return matches ? matches.length : 0;
  }

  /**
   * Refuses the timeline in [db] when it has more than `MAX_TIMELINE_EVENTS`
   * events or periods, an event, period or section of more than
   * `maxLabelWordChars` characters or `MAX_TIMELINE_EVENT_WORDS` words, more
   * than `MAX_TIMELINE_WORDS` words in total, or a word longer than
   * `maxLabelWordChars`.
   *
   * Mermaid wraps each section, period and event of a timeline twice in the
   * page, adding a word at a time to a `<tspan>` and measuring the text at
   * each, so an event of a hundred two-letter words takes nearly a second and
   * one of three hundred and thirty-three takes seven to eleven seconds.
   */
  function refuseTimeline(db) {
    const tasks = db.getTasks();
    const sections = db.getSections();
    let events = 0;
    let longestEvent = 0;
    let longestEventWords = 0;
    let words = 0;
    for (const section of sections) {
      const text = String(section).trim();
      const count = timelineWords(text);
      longestEvent = Math.max(longestEvent, text.length);
      longestEventWords = Math.max(longestEventWords, count);
      words += count;
    }
    for (const task of tasks) {
      const period = String(task.task || '').trim();
      const periodWords = timelineWords(period);
      longestEvent = Math.max(longestEvent, period.length);
      longestEventWords = Math.max(longestEventWords, periodWords);
      words += periodWords;
      for (const event of task.events || []) {
        events += 1;
        const text = String(event).trim();
        const count = timelineWords(text);
        longestEvent = Math.max(longestEvent, text.length);
        longestEventWords = Math.max(longestEventWords, count);
        words += count;
      }
    }
    refuseCount(events, MAX_TIMELINE_EVENTS, 'events');
    refuseCount(tasks.length, MAX_TIMELINE_EVENTS, 'periods');
    refuseCount(
      longestEvent, LIMITS.maxLabelWordChars, 'characters in one event');
    refuseCount(
      longestEventWords, MAX_TIMELINE_EVENT_WORDS, 'words in one event');
    refuseCount(words, MAX_TIMELINE_WORDS, 'words');
    refuseLongWord([sections, tasks]);
  }

  /**
   * The most cards or sections a kanban board is drawn with, once mermaid has
   * parsed its sections and cards.
   *
   * Mermaid draws and measures each section and card of a kanban board one
   * after another in the page, wrapping its label into `<tspan>` lines and
   * reading its bounding box, which took nearly fifteen seconds for a
   * thousand cards of fourteen words.
   */
  const MAX_KANBAN_CARDS = 200;

  /**
   * How many nodes sit in [roots] and their `.children`, walked with an
   * explicit stack so a deep tree cannot overflow the call stack.
   */
  function countTreeNodes(roots) {
    let count = 0;
    const pending = Array.isArray(roots) ? [...roots] : (roots ? [roots] : []);
    while (pending.length > 0) {
      const node = pending.pop();
      count += 1;
      for (const child of node.children || []) {
        pending.push(child);
      }
    }
    return count;
  }

  /**
   * Refuses [roots] when any chain of `.children` from a root in [roots] is
   * deeper than [limit] levels, walked with an explicit stack so a deep tree
   * cannot overflow the call stack.
   */
  function refuseTreeDepth(roots, limit) {
    const list = Array.isArray(roots) ? roots : (roots ? [roots] : []);
    let deepest = 0;
    const pending = list.map((node) => [node, 1]);
    while (pending.length > 0) {
      const [node, depth] = pending.pop();
      if (depth > deepest) deepest = depth;
      for (const child of node.children || []) {
        pending.push([child, depth + 1]);
      }
    }
    refuseCount(deepest, limit, 'levels deep');
  }

  /**
   * How a parsed diagram of each type here is refused when its database
   * hands its drawing more than is drawn, where neither the counts of its
   * source nor the nodes and edges a database hands a layout bound it.
   *
   * Mermaid splits a packet diagram's field into a row for each row of bits
   * it spans, up to ten thousand, so one statement naming a field of a
   * third of a million bits is ten thousand rows, each drawn as a box and
   * three texts; its fields are held to `maxSourceItems`. A block diagram's
   * space of a given width is that many blocks, so `space:100000` is a
   * hundred thousand blocks to lay out; its blocks are held to
   * `maxSourceNames`, the most nodes a diagram lays out, counted once and
   * again as often as its layout sizes them ([blockSizings]), and their
   * labels to [refuseLongWord], since no layout is handed them. A venn
   * diagram's layout measures the overlaps of every area at each of
   * hundreds of steps, the pair of every two sets among them, and does it
   * twice, so a source of two hundred sets takes minutes; its areas are held
   * to `maxVennAreas`, and each union to the sets it names once
   * ([refuseRepeatedVennSets]). A gantt chart is read through its date
   * format and steps past the days it excludes a day at a time, and is held
   * to `refuseLargeGantt`. A timeline is held to [refuseTimeline], and a
   * kanban board's cards and sections to `MAX_KANBAN_CARDS`. An
   * architecture diagram's services, groups and
   * edges are handed to no layout but its own, which fits their titles and
   * labels as a flowchart's are fitted, so their words are held to
   * [refuseLongWord]. A sequence diagram's messages and actors, a pie
   * chart's sections, a git graph's commits and branches, a quadrant
   * chart's points, a sankey diagram's links and nodes, a C4 diagram's
   * relationships, shapes and boundaries, a treemap's nodes, a cynefin
   * diagram's domain items and transitions, a treeView or ishikawa
   * diagram's nodes and nesting depth, a wardley map's size, items, links
   * and trends, an eventmodeling diagram's frames, entities and relations
   * on its syntax tree, and a usecase diagram's items (each row of a JSON
   * node counted), whose databases either have no `getData` or can pack
   * more than one item into a line or node, are held to the pixel,
   * statement, name, edge, item, depth and word limits.
   */
  const DIAGRAM_REFUSALS = {
    packet: (db) => refuseCount(
      packetFields(db), LIMITS.maxSourceItems, 'fields'),
    block: (db) => {
      refuseCount(blockCount(db), LIMITS.maxSourceNames, 'blocks');
      refuseCount(blockSizings(db), LIMITS.maxSourceNames,
        'blocks as its layout sizes them');
      refuseLongWord(db.getBlocks());
    },
    venn: (db) => {
      refuseRepeatedVennSets(db);
      refuseCount(vennAreas(db), LIMITS.maxVennAreas, 'areas');
    },
    gantt: (db) => refuseLargeGantt(db),
    timeline: (db) => refuseTimeline(db),
    kanban: (db) => {
      refuseCount(db.getSections().length, MAX_KANBAN_CARDS, 'sections');
      const nodes = db.getData().nodes;
      refuseCount(
        nodes.filter((node) => !node.isGroup).length,
        MAX_KANBAN_CARDS, 'cards');
    },
    architecture: (db) => refuseLongWord(
      [db.getServices(), db.getGroups(), db.getEdges()]),
    sequence: (db) => {
      refuseCount(
        db.getMessages().length, LIMITS.maxSourceStatements, 'messages');
      refuseCount(
        Object.keys(db.getActors()).length, LIMITS.maxSourceNames, 'actors');
      refuseLongWord([db.getMessages(), db.getActors()]);
    },
    pie: (db) => refuseCount(
      db.getSections().size, LIMITS.maxSourceItems, 'sections'),
    gitGraph: (db) => {
      refuseCount(db.getCommits().size, LIMITS.maxSourceStatements, 'commits');
      refuseCount(db.getBranches().size, LIMITS.maxSourceNames, 'branches');
      refuseLongWord([
        Array.from(db.getCommits().values()),
        Array.from(db.getBranches().keys()),
      ]);
    },
    quadrantChart: (db) => refuseCount(
      db.getQuadrantData().points.length, LIMITS.maxSourceItems, 'points'),
    sankey: (db) => {
      refuseCount(db.getLinks().length, LIMITS.maxEdges, 'edges');
      refuseCount(db.getNodes().length, LIMITS.maxSourceNames, 'nodes');
    },
    c4: (db) => {
      refuseCount(db.getRels().length, LIMITS.maxEdges, 'edges');
      refuseCount(db.getC4ShapeArray().length + db.getBoundaries().length,
        LIMITS.maxSourceNames, 'nodes');
      refuseLongWord([db.getC4ShapeArray(), db.getBoundaries(), db.getRels()]);
    },
    treemap: (db) => {
      refuseCount(db.getNodes().length, LIMITS.maxSourceItems, 'nodes');
      refuseLongWord(db.getNodes());
    },
    cynefin: (db) => {
      const domains = Array.from(db.getDomains().values());
      let items = 0;
      for (const domain of domains) {
        items += (domain.items || []).length;
      }
      refuseCount(items, LIMITS.maxSourceItems, 'items');
      refuseCount(db.getTransitions().length, LIMITS.maxEdges, 'edges');
      refuseLongWord([domains, db.getTransitions(), db.getDiagramTitle()]);
    },
    treeView: (db) => {
      const roots = db.getRoot().children;
      refuseCount(countTreeNodes(roots), LIMITS.maxSourceItems, 'nodes');
      refuseTreeDepth(roots, LIMITS.maxDepth);
      refuseLongWord([roots, db.getDiagramTitle()]);
    },
    ishikawa: (db) => {
      const root = db.getRoot();
      refuseCount(countTreeNodes(root), LIMITS.maxSourceItems, 'nodes');
      refuseTreeDepth(root, LIMITS.maxDepth);
      refuseLongWord(root);
    },
    wardley: (db) => {
      const data = db.getWardleyData();
      const stages = (data.axes && data.axes.stages) || [];
      const pipelines = data.pipelines || [];
      if (data.size) {
        refuseCount(data.size.width, LIMITS.maxSide, 'pixels wide');
        refuseCount(data.size.height, LIMITS.maxSide, 'pixels high');
        refuseCount(
          data.size.width * data.size.height, LIMITS.maxPixels, 'pixels');
      }
      let pipelineItems = pipelines.length;
      let pipelineEdges = 0;
      for (const pipeline of pipelines) {
        const components =
          (pipeline && Array.isArray(pipeline.componentIds))
            ? pipeline.componentIds.length : 0;
        pipelineItems += components;
        if (components > 1) pipelineEdges += components - 1;
      }
      refuseCount(
        data.nodes.length + data.notes.length + data.annotations.length +
          data.accelerators.length + data.deaccelerators.length +
          stages.length + pipelineItems,
        LIMITS.maxSourceItems, 'items');
      refuseCount(
        data.links.length + data.trends.length + pipelineEdges,
        LIMITS.maxEdges, 'edges');
      refuseLongWord([
        data.nodes, data.links, data.notes, data.annotations,
        data.accelerators, data.deaccelerators, stages, pipelines,
        db.getDiagramTitle(),
      ]);
    },
    eventmodeling: (db) => {
      const ast = db.getAst();
      const frames = (ast && ast.frames) || [];
      const dataEntities = (ast && ast.dataEntities) || [];
      const modelEntities = (ast && ast.modelEntities) || [];
      const noteEntities = (ast && ast.noteEntities) || [];
      const gwtEntities = (ast && ast.gwtEntities) || [];
      refuseCount(
        frames.length + dataEntities.length + modelEntities.length +
          noteEntities.length + gwtEntities.length,
        LIMITS.maxSourceItems, 'items');
      const dataCharsByName = new Map();
      for (const entity of dataEntities) {
        if (entity && typeof entity.name === 'string') {
          dataCharsByName.set(
            entity.name,
            typeof entity.dataBlockValue === 'string'
              ? entity.dataBlockValue.length : 0);
        }
      }
      let edges = 0;
      let renderedChars = 0;
      for (let i = 0; i < frames.length; i++) {
        const frame = frames[i];
        const refs = (frame.sourceFrames && frame.sourceFrames.length) || 0;
        edges += refs > 0
          ? refs : (i > 0 && frame.$type === 'EmTimeFrame' ? 1 : 0);
        if (typeof frame.entityIdentifier === 'string') {
          renderedChars += frame.entityIdentifier.length;
        }
        if (typeof frame.dataInlineValue === 'string') {
          renderedChars += frame.dataInlineValue.length;
        }
        const dataRefs = Array.isArray(frame.dataRefs) && frame.dataRefs.length > 0
          ? frame.dataRefs
          : (frame.dataReference ? [frame.dataReference] : []);
        for (const ref of dataRefs) {
          const refName = typeof ref === 'string'
            ? ref : (ref && (ref.$refText || (ref.ref && ref.ref.name)));
          if (typeof refName === 'string' && dataCharsByName.has(refName)) {
            renderedChars += dataCharsByName.get(refName);
          } else if (ref && ref.ref &&
              typeof ref.ref.dataBlockValue === 'string') {
            renderedChars += ref.ref.dataBlockValue.length;
          }
        }
      }
      refuseCount(edges, LIMITS.maxEdges, 'edges');
      refuseCount(renderedChars, LIMITS.maxSourceChars, 'characters');
      refuseLongWord([
        ast && ast.title, ast && ast.accTitle, ast && ast.accDescr,
        frames.map((frame) => [
          frame.name, frame.entityIdentifier, frame.dataInlineValue,
        ]),
        dataEntities.map((entity) => [entity.name, entity.dataBlockValue]),
        modelEntities.map((entity) => entity.name),
        noteEntities.map((note) => note.dataBlockValue),
      ]);
    },
    usecase: (db) => {
      const rawJsonNodes = typeof db.getJsonNodes === 'function'
        ? db.getJsonNodes() : db.jsonNodes;
      const jsonNodes = rawJsonNodes instanceof Map
        ? Array.from(rawJsonNodes.values())
        : (Array.isArray(rawJsonNodes) ? rawJsonNodes : []);
      let deepestJson = 0;
      for (const jsonNode of jsonNodes) {
        const rootValue = jsonNode && jsonNode.value !== undefined
          ? jsonNode.value : jsonNode;
        if (!rootValue || typeof rootValue !== 'object') continue;
        const pending = [[rootValue, 1]];
        while (pending.length > 0) {
          const [current, depth] = pending.pop();
          if (depth > deepestJson) deepestJson = depth;
          if (depth > LIMITS.maxDepth) break;
          const children = Array.isArray(current)
            ? current : Object.values(current);
          for (const child of children) {
            if (child && typeof child === 'object') {
              pending.push([child, depth + 1]);
            }
          }
        }
        refuseCount(deepestJson, LIMITS.maxDepth, 'levels deep');
      }
      const data = db.getData();
      const nodes = (data && data.nodes) || [];
      let items = 0;
      let longestKey = 0;
      for (const node of nodes) {
        if (Array.isArray(node.jsonRows) && node.jsonRows.length > 0) {
          items += node.jsonRows.length;
          for (const row of node.jsonRows) {
            if (row && typeof row.key === 'string' &&
                row.key.length > longestKey) {
              longestKey = row.key.length;
            }
          }
        } else {
          items += 1;
        }
      }
      refuseCount(items, LIMITS.maxSourceItems, 'items');
      refuseCount(
        longestKey, LIMITS.maxLabelWordChars, 'characters in one word');
      return data;
    },
    agentflow: (db) => {
      const vertices = Array.from(db.getVertices().values());
      const subGraphs = db.getSubGraphs();
      refuseCount(vertices.length, LIMITS.maxSourceNames, 'nodes');
      refuseLongWord([vertices, db.getEdges(), subGraphs]);
    },
  };

  /**
   * What opens a configuration a source gives itself: a directive, anywhere
   * in it, or front matter at its start.
   */
  const OWN_CONFIGURATION = /%%\{|^\s*---/;

  /**
   * [source] parsed under the configuration mermaid draws it under: the
   * page's, with the source's own front matter and directives, and no other
   * source's.
   *
   * A parse alone reads a source under whatever configuration mermaid holds,
   * and initialising mermaid keeps the directives of the source it last
   * drew. So a source that gives itself a configuration is parsed after
   * `mermaid.parse`, which applies it, as a diagram such as a git graph
   * naming its main branch or a packet diagram of one bit to a row needs,
   * and one that gives itself none is parsed after mermaid is reset to the
   * page's configuration alone. Where a database stores a Langium syntax tree
   * through `setAst` and exposes only `getState`, which runs the layout and
   * measures text in the page, `setAst` is wrapped so `getAst` returns the
   * syntax tree alone.
   */
  async function parsedDiagram(source) {
    if (OWN_CONFIGURATION.test(source)) {
      await mermaid.parse(source);
    } else {
      mermaid.mermaidAPI.reset();
    }
    const diagram = await mermaid.mermaidAPI.getDiagramFromText(source);
    const db = diagram && diagram.db;
    if (db && typeof db.setAst === 'function' &&
        typeof db.getAst !== 'function') {
      let currentAst;
      const setAst = db.setAst.bind(db);
      const clear = typeof db.clear === 'function'
        ? db.clear.bind(db) : () => undefined;
      db.setAst = (ast) => {
        currentAst = ast;
        setAst(ast);
      };
      db.clear = () => {
        currentAst = undefined;
        clear();
      };
      db.getAst = () => currentAst;
      await diagram.parser.parse(diagram.text);
    }
    return diagram;
  }

  /**
   * Keys of a subgraph, or of the `@{ ... }` metadata attached to one, that
   * pick a layout algorithm or pass options to one.
   */
  const LAYOUT_METADATA_KEYS = [
    'algorithm', 'layout', 'layoutAlgorithm', 'layoutOptions'];

  /**
   * Refuses a diagram whose subgraphs ([items]) exceed `maxSourceItems`, set
   * any of `LAYOUT_METADATA_KEYS` on themselves or in their `metadata`, form a
   * parent cycle, or nest deeper than `maxDepth`, before `getData` or any
   * layout walks subgraph parent chains.
   */
  function refuseLayoutMetadata(items) {
    if (!Array.isArray(items)) return;
    refuseCount(items.length, LIMITS.maxSourceItems, 'subgraphs');
    const subGraphIds = new Set();
    for (const item of items) {
      if (item && typeof item.id === 'string') subGraphIds.add(item.id);
      for (const target of [item, item && item.metadata]) {
        if (!target || typeof target !== 'object') continue;
        for (const key of LAYOUT_METADATA_KEYS) {
          if (Object.prototype.hasOwnProperty.call(target, key) &&
              target[key] !== undefined) {
            throw new Failure('tooLarge',
              'The diagram sets ' + key + ' on a subgraph.');
          }
        }
      }
    }
    const parentById = new Map();
    for (const item of items) {
      if (!item || typeof item.id !== 'string' || !Array.isArray(item.nodes)) {
        continue;
      }
      for (const nodeId of item.nodes) {
        if (subGraphIds.has(nodeId)) {
          parentById.set(nodeId, item.id);
        }
      }
    }
    let deepest = 0;
    for (const id of subGraphIds) {
      const visited = new Set();
      let current = id;
      let depth = 0;
      while (current !== undefined) {
        if (visited.has(current)) {
          throw new Failure(
            'tooLarge', 'The diagram has a cycle in its subgraphs.');
        }
        visited.add(current);
        depth += 1;
        current = parentById.get(current);
      }
      if (depth > deepest) deepest = depth;
    }
    refuseCount(deepest, LIMITS.maxDepth, 'levels deep');
  }

  /**
   * Refuses [source] when its database hands the drawing more than is drawn
   * (`DIAGRAM_REFUSALS`), or its layout more edges than `maxEdges`, more
   * nodes than `maxSourceNames`, a subgraph setting a layout, cycling or
   * nesting past `maxDepth` ([refuseLayoutMetadata]), or text with a word
   * longer than `maxLabelWordChars` ([refuseLongWord]), before any layout
   * runs.
   *
   * Mermaid holds only a flowchart to `maxEdges`, and every diagram whose
   * database hands its layout the nodes and edges to place is laid out by a
   * layout whose time grows with them. The source is parsed under the
   * configuration it is drawn under ([parsedDiagram]), and what its
   * database would hand the drawing and the layout is counted.
   */
  async function refuseTooLargeDiagram(source) {
    const diagram = await parsedDiagram(source);
    const db = diagram && diagram.db;
    if (!db) return;
    if (typeof db.getSubGraphs === 'function') {
      refuseLayoutMetadata(db.getSubGraphs());
    }
    const refusalData =
      Object.prototype.hasOwnProperty.call(DIAGRAM_REFUSALS, diagram.type)
        ? DIAGRAM_REFUSALS[diagram.type](db) : undefined;
    if (typeof db.getData !== 'function') return;
    const data = refusalData !== undefined ? refusalData : db.getData();
    const edges = data && Array.isArray(data.edges) ? data.edges.length : 0;
    if (edges > LIMITS.maxEdges) {
      throw new Failure('tooLarge', 'The diagram has ' + edges +
        ' edges, more than the ' + LIMITS.maxEdges + ' drawn.');
    }
    const nodes = data && Array.isArray(data.nodes) ? data.nodes.length : 0;
    if (nodes > LIMITS.maxSourceNames) {
      throw new Failure('tooLarge', 'The diagram has ' + nodes +
        ' nodes, more than the ' + LIMITS.maxSourceNames + ' drawn.');
    }
    refuseLongWord(data && [data.nodes, data.edges]);
  }

  function plainText(message) {
    return String(message)
      .replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u2028\u2029]/g, ' ')
      .slice(0, MAX_DETAIL_CHARS);
  }

  /** Mermaid's own message when it refuses a diagram for having too many
   * edges. */
  const EDGE_LIMIT = /^Edge limit exceeded\./;

  function classifyMermaidError(error) {
    const message = plainText(error && error.message ? error.message : error);
    if (EDGE_LIMIT.test(message)) return new Failure('tooLarge', message);
    return new Failure('syntaxError', message);
  }

  function now() {
    return performance.now();
  }

  /** Flattens [root] to an SVG answer, or throws why it cannot be. */
  async function flattened(root, request, type, label, started, timings) {
    await reencodeImages(root);
    const flat = flatten(root);
    timings.total = now() - started;
    return {
      id: request.id, kind: 'svg', type: type, svg: flat.svg,
      width: flat.width, height: flat.height, label: label, timings: timings,
    };
  }

  const XLINK_NS = 'http://www.w3.org/1999/xlink';

  /**
   * [svg] with the `xlink` prefix declared on its root element.
   *
   * Mermaid writes a node's link as `<a xlink:href>` without declaring the
   * prefix, which an XML parser refuses as not well formed. The link is not
   * kept: an `a` is flattened to a group, and nothing the page draws can be
   * followed.
   */
  function withXlinkDeclared(svg) {
    const open = /^\s*<svg\b[^>]*>/.exec(svg);
    if (open === null || /\sxmlns:xlink\s*=/.test(open[0])) return svg;
    return svg.replace(/^(\s*<svg)\b/, '$1 xmlns:xlink="' + XLINK_NS + '"');
  }

  /**
   * Turns each run of line breaks in the texts of [root] into a space.
   *
   * Mermaid writes a Sankey node's name and value as one text with a line
   * break between them. SVG's default whitespace handling, which WebKit
   * follows, removes a line break where other engines draw a space, which
   * runs the name into the value ("Liquid0.6") in the vector drawing and
   * the picture alike; this runs before either reads the text.
   */
  function spaceLineBreaksInText(root) {
    for (const text of root.querySelectorAll('text')) {
      const walker = document.createTreeWalker(text, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (/[\r\n]/.test(node.nodeValue)) {
          node.nodeValue = node.nodeValue.replace(/[\r\n]+/g, ' ');
        }
      }
    }
  }

  /** A computed colour as {r, g, b, a}, or null for `none` and for one
   * [parseColor] cannot read. */
  function readColor(text) {
    try {
      return parseColor(text);
    } catch (error) {
      return null;
    }
  }

  /** The room a journey's name keeps from each side of its box, mermaid's
   * `boxTextMargin`. */
  const JOURNEY_NAME_PADDING = 5;

  /**
   * Wraps each name a journey writes on a box to the box's width.
   *
   * Mermaid writes a journey's names as SVG text broken only where the name
   * holds a line break, and a box is as wide as the diagram's settings make
   * it, whatever the name: a long one runs out of its box and over the next.
   * Each name wider than its box, less [JOURNEY_NAME_PADDING] a side, is
   * broken at spaces into lines that fit, as measured in its own face, and a
   * word too wide alone is broken between characters; the lines are a
   * font size apart, centred on the box as mermaid centres its own.
   */
  function wrapJourneyNames(root) {
    for (const name of root.querySelectorAll(
        'text.journey-section, text.task')) {
      const kind = name.classList.contains('task') ? 'task' : 'journey-section';
      const box = Array.from(name.parentNode.children).find((element) =>
        element.localName === 'rect' && element.classList.contains(kind));
      const runs = name.querySelectorAll('tspan');
      if (!box || runs.length !== 1) continue;
      const room = Number(box.getAttribute('width')) -
        2 * JOURNEY_NAME_PADDING;
      if (!(room > 0) || name.getComputedTextLength() <= room) continue;
      const run = runs[0];
      const words = run.textContent.split(/\s+/).filter((word) => word);
      const fits = (line) => {
        run.textContent = line;
        return name.getComputedTextLength() <= room;
      };
      const lines = [];
      let line = '';
      for (const word of words) {
        const longer = line === '' ? word : line + ' ' + word;
        if (fits(longer)) {
          line = longer;
          continue;
        }
        if (line !== '') lines.push(line);
        line = '';
        for (const character of Array.from(word)) {
          if (line !== '' && !fits(line + character)) {
            lines.push(line);
            line = '';
          }
          line += character;
        }
      }
      if (line !== '') lines.push(line);
      const size = parseFloat(getComputedStyle(name).fontSize) || 14;
      const x = run.getAttribute('x');
      run.remove();
      lines.forEach((text, index) => {
        const piece = document.createElementNS(SVG_NS, 'tspan');
        if (x !== null) piece.setAttribute('x', x);
        piece.setAttribute(
          'dy', String(index === 0 ? -size * (lines.length - 1) / 2 : size));
        piece.textContent = text;
        name.appendChild(piece);
      });
    }
  }

  /** The relative luminance WCAG 2 gives a colour of 0 to 255 channels. */
  function luminance(color) {
    const channel = (value) => {
      const c = value / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
  }

  /** The contrast of one colour against another, as WCAG 2 measures it. */
  function contrast(one, other) {
    const a = luminance(one);
    const b = luminance(other);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  }

  /** The contrast a name must have against its box: AA's for its size. */
  const READABLE_CONTRAST = 4.5;

  /**
   * Shows the names a journey writes on its boxes, on every engine.
   *
   * Mermaid's stylesheet fills a section's box and its name alike, by the
   * `section-type-N` class both carry, and a class rule outranks the name's
   * own fill, so a section's name is in its box's colour; and it writes each
   * task's name in white, which on the light theme's pale boxes cannot be
   * read. Each name is given, as an inline style, which outranks both, the
   * diagram's text colour where that reads against its box at
   * [READABLE_CONTRAST], and black or white, whichever reads better, where
   * it does not. The boxes keep their colours. A name whose box or text
   * colour is one [parseColor] cannot read is left as mermaid wrote it.
   */
  function showJourneyNames(root) {
    const text = readColor(getComputedStyle(root).fill);
    const black = {r: 0, g: 0, b: 0, a: 1};
    const white = {r: 255, g: 255, b: 255, a: 1};
    for (const name of root.querySelectorAll(
        'text.journey-section, text.task')) {
      const kind = name.classList.contains('task') ? 'task' : 'journey-section';
      const box = Array.from(name.parentNode.children).find((element) =>
        element.localName === 'rect' && element.classList.contains(kind));
      if (!box) continue;
      const behind = readColor(getComputedStyle(box).fill);
      if (behind === null) continue;
      let chosen = text;
      if (chosen === null || contrast(chosen, behind) < READABLE_CONTRAST) {
        chosen = contrast(black, behind) >= contrast(white, behind)
          ? black : white;
      }
      name.style.fill =
        'rgb(' + chosen.r + ', ' + chosen.g + ', ' + chosen.b + ')';
    }
  }

  async function render(request) {
    if (typeof request.id !== 'string' || request.id === '') {
      throw new Failure('unflattenable', 'request without an id');
    }
    const timings = {};
    const started = now();
    if (typeof request.source !== 'string') {
      throw new Failure('syntaxError', 'The diagram source is missing.');
    }
    if (request.source.length > LIMITS.maxSourceChars) {
      throw new Failure(
        'tooLarge', 'The diagram is longer than ' + LIMITS.maxSourceChars +
        ' characters.');
    }
    const width = Math.max(100, Math.min(Number(request.width) || 1024, 4096));
    document.body.style.width = width + 'px';
    const svgAllowed = await fontsReady();
    await engineFilters();
    mermaid.initialize(mermaidConfiguration(request));

    const addresses = withholdRefusedAddresses(request.source);
    let result;
    layoutRefusal = null;
    layingOut = true;
    try {
      refuseTooLargeSource(addresses.source);
      await refuseTooLargeDiagram(addresses.source);
      result = await mermaid.render(RENDER_ID, addresses.source);
    } catch (error) {
      throw error instanceof Failure ? error : classifyMermaidError(error);
    } finally {
      layingOut = false;
    }
    timings.mermaid = now() - started;
    const type = canonicalType(result.diagramType);
    const holder = document.createElement('div');
    holder.style.cssText = 'position:absolute;left:-100000px;top:0;' +
      'pointer-events:none;width:' + width + 'px';
    document.body.appendChild(holder);
    try {
      const parsed = new DOMParser().parseFromString(
        withXlinkDeclared(result.svg), 'image/svg+xml');
      if (parsed.getElementsByTagName('parsererror').length > 0) {
        throw new Failure('unflattenable', 'The diagram was not well formed.');
      }
      const withheld = withholdRefusedImages(parsed) || addresses.refusal ||
        layoutRefusal;
      const root = document.importNode(parsed.documentElement, true);
      holder.appendChild(root);
      if (type === 'journey') {
        wrapJourneyNames(root);
        showJourneyNames(root);
      }
      if (type === 'sankey') spaceLineBreaksInText(root);
      const refusal = withholdCssImages(root) || withheld;
      const label = accessibleLabel(root);
      const wantsSvg = svgAllowed && !request.raster &&
        (request.svgTypes || []).includes(type);
      // 'no bundled face' is a page whose faces did not load, which the host
      // does not keep; with no faces given every diagram is a picture.
      let fallback = CONFIG.faces.length === 0
        ? 'no face was given' : 'no bundled face';
      if (svgAllowed) fallback = 'type ' + type + ' is drawn as an image';
      if (refusal !== null) fallback = refusal;
      if (wantsSvg && refusal === null) {
        try {
          const answer = await flattened(
            root, request, type, label, started, timings);
          if (request.includeRaw === true) answer.raw = result.svg;
          return answer;
        } catch (error) {
          // Whatever stops the flattening, the diagram is still drawn.
          fallback = plainText(
            error instanceof Failure ? error.detail
              : (error && error.message ? error.message : error));
        }
      }
      const size = rootSize(root);
      const rasterStarted = now();
      const raster = await rasterise(
        root, size.width, size.height, Number(request.scale) || 1);
      timings.raster = now() - rasterStarted;
      timings.total = now() - started;
      return {
        id: request.id, kind: 'png', type: type, png: raster.png,
        width: raster.width, height: raster.height, scale: raster.scale,
        label: label, fallback: fallback, timings: timings,
      };
    } finally {
      holder.remove();
    }
  }

  /**
   * Answers a request as a JSON string; a failure is an answer, not an
   * exception. The request is the object a host passes as an argument, or its
   * JSON text for a host that can only pass a string.
   */
  async function answer(input) {
    let id = null;
    try {
      const request = typeof input === 'string' ? JSON.parse(input) : input;
      id = typeof request.id === 'string' ? request.id : null;
      return JSON.stringify(await render(request));
    } catch (error) {
      const failure = error instanceof Failure ? error : new Failure(
        'unflattenable',
        plainText(error && error.message ? error.message : error));
      return JSON.stringify({
        id: id, kind: 'failure', failure: failure.kind,
        detail: plainText(failure.detail),
      });
    }
  }

  /**
   * The function that sends the host a message, taken from whichever channel
   * the host provides when the page loads, so a script that runs later cannot
   * replace what answers are sent through.
   */
  const send = (function () {
    const helper = window.finchHost;
    if (helper && typeof helper.postMessage === 'function') {
      return (text) => helper.postMessage(text);
    }
    const webkit = window.webkit && window.webkit.messageHandlers &&
      window.webkit.messageHandlers.FinchMermaid;
    if (webkit) return (text) => webkit.postMessage(text);
    if (window.FinchMermaid) {
      return (text) => window.FinchMermaid.postMessage(text);
    }
    if (window.chrome && window.chrome.webview) {
      return (text) => window.chrome.webview.postMessage(text);
    }
    return () => undefined;
  })();

  Object.defineProperty(window, 'finchMermaid', {
    value: Object.freeze({
      /** Resolves to the JSON answer for the request. */
      render: answer,
      /** Posts the JSON answer to the host's channel. */
      run: async (input) => send(await answer(input)),
    }),
    writable: false,
    configurable: false,
    enumerable: false,
  });

  Object.defineProperty(window, 'finchPage', {
    value: Object.freeze({
      /**
       * Posts the JSON answer for the request's JSON text, and settles once
       * it has been posted.
       */
      request: async (text) => {
        send(await answer(String(text)));
      },
    }),
    writable: false,
    configurable: false,
    enumerable: false,
  });
  send(JSON.stringify({kind: 'ready'}));
})();

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
    String.raw`^url\(\s*["']?[^"')#]*#([^"')\s]+)["']?\s*\)`);

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
    return match ? match[1] : null;
  }

  /** The id a reference names, which must be one a drawing may carry. */
  function referenceId(text) {
    const id = urlReference(text);
    if (id !== null && !ID_PATTERN.test(id)) {
      throw unflattenable('reference ' + id);
    }
    return id;
  }

  /**
   * Writes the fill or stroke named by [kind] from a computed paint value
   * and its opacity, splitting an rgba colour into rgb plus an opacity.
   */
  function setPaint(attributes, kind, value, opacityText) {
    const reference = referenceId(value);
    const opacity = Number(
      opacityText === undefined || opacityText === '' ? 1 : opacityText);
    if (reference !== null) {
      attributes[kind] = 'url(#' + reference + ')';
      if (opacity < 1) attributes[kind + '-opacity'] = num(opacity);
      return;
    }
    const color = parseColor(value);
    if (color === null || color.a === 0) {
      attributes[kind] = 'none';
      return;
    }
    attributes[kind] = 'rgb(' + color.r + ',' + color.g + ',' + color.b + ')';
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

  /**
   * The dashes a stroke is cut into, or null for a solid one.
   *
   * A pattern is cut into a path command for each of its entries along the
   * whole stroke, so a pattern that is a fraction of a unit long, or has a
   * negative entry, cannot be drawn this way.
   */
  function dashPattern(style) {
    const text = style.strokeDasharray;
    if (!text || text === 'none') return null;
    let list = numberList(text.replace(/px/g, '').replace(/%/g, ''));
    if (list.some((n) => n < 0)) throw unflattenable('negative dash');
    while (list.length >= 2 && list[0] === 0 && list[1] === 0) {
      list.splice(0, 2);
    }
    while (list.length >= 2 &&
        list[list.length - 2] === 0 &&
        list[list.length - 1] === 0) {
      list.splice(list.length - 2, 2);
    }
    if (list.length > 2 && list.length % 2 === 1 &&
        list[list.length - 1] === 0) {
      list.pop();
    }
    if (list.length === 2 && list[1] === 0) return null;
    if ((list.length >= 3 && list.slice(0, -1).every((n) => n === 2)) ||
        (list.length >= 5 && list[0] === 0 &&
          list.slice(2, -1).every((n) => n === 2))) {
      list = [2, 2];
    }
    list = list.map((n) => (n === 0 ? 0.01 : n));
    if (list.length > LIMITS.maxDashEntries) {
      throw unflattenable('more than ' + LIMITS.maxDashEntries + ' dashes');
    }
    const total = list.reduce((sum, n) => sum + n, 0);
    if (!(total > 0)) return null;
    const odd = list.length % 2 === 1;
    const period = odd ? total * 2 : total;
    if (period < LIMITS.minDashPeriod) {
      throw unflattenable('dashes shorter than ' + LIMITS.minDashPeriod);
    }
    return {list: list, entries: odd ? list.length * 2 : list.length,
      period: period};
  }

  /** The length of the outline of a shape, in its own units. */
  function outlineLength(element) {
    if (typeof element.getTotalLength !== 'function') {
      throw unflattenable('length of ' + element.localName);
    }
    return element.getTotalLength();
  }

  /**
   * A value to write as a presentation attribute, from an rgba-split style.
   * [shape] is the element the stroke belongs to, or null for one that
   * passes its paint to what it refers to, which may not be dashed.
   */
  function paintAttributes(style, shape, context) {
    const attributes = {};
    setPaint(attributes, 'fill', style.fill, style.fillOpacity);
    setPaint(attributes, 'stroke', style.stroke, style.strokeOpacity);
    if (attributes.stroke !== 'none') {
      attributes['stroke-width'] = num(pixels(style.strokeWidth));
      const dashes = dashPattern(style);
      if (dashes !== null) {
        if (shape === null) throw unflattenable('a dash on a reference');
        context.budget.dashes += outlineLength(shape) * context.scale *
          dashes.entries / dashes.period;
        if (context.budget.dashes > LIMITS.maxDashSegments) {
          throw unflattenable('more than ' + LIMITS.maxDashSegments +
            ' dashes');
        }
        attributes['stroke-dasharray'] = dashes.list.map(num).join(',');
        const offset = pixels(style.strokeDashoffset);
        if (offset !== 0) attributes['stroke-dashoffset'] = num(offset);
      }
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

  /** Elements a later reference can name, which keep their id. */
  const REFERENCED_BY_KIND = new Set(
    ['linearGradient', 'radialGradient', 'clipPath', 'symbol']);

  /**
   * The id of [element] when something refers to it, and nothing otherwise:
   * an id carries no meaning to the drawing and may hold any characters.
   */
  function identifier(element, context) {
    const id = element.getAttribute('id');
    if (id === null) return {};
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
      const inside = Object.assign(
        {}, context, {scale: context.scale * stretch(matrix)});
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
   * The elements that each hold one run of text on one line, after wrapping
   * any text that sits beside a tspan so every run is a leaf.
   */
  function textRuns(text) {
    const runs = [];
    const visit = (element) => {
      const children = Array.from(element.childNodes);
      const hasElements = children.some((child) => child.nodeType === 1);
      if (!hasElements) {
        if (element.textContent.trim() !== '') runs.push(element);
        return;
      }
      for (const child of children) {
        if (child.nodeType === 3) {
          if (child.data.trim() === '') continue;
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
    return runs;
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

  function fontFamilyOf(style) {
    const first =
      style.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
    if (first.toLowerCase() === CONFIG.family.toLowerCase()) {
      return CONFIG.family;
    }
    if (!/^[A-Za-z0-9 _-]{1,80}$/.test(first)) return CONFIG.family;
    return first;
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
        emitTextPiece(run, runStyle, piece, total, base, parent);
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

  function emitTextPiece(run, runStyle, piece, total, base, parent) {
    const origin = run.getStartPositionOfChar(Math.min(piece.start, total - 1));
    const attributes = Object.assign({}, base, {
      x: num(origin.x),
      y: num(origin.y),
      'font-family': fontFamilyOf(runStyle),
      'font-size': num(pixels(runStyle.fontSize)),
      'font-weight': String(faceWeight(runStyle.fontWeight)),
      'text-anchor': 'start',
    });
    setPaint(attributes, 'fill', runStyle.fill, runStyle.fillOpacity);
    const stroke = runStyle.stroke.startsWith('url')
      ? 'rgb(0,0,0)' : runStyle.stroke;
    const strokeColor = parseColor(stroke);
    if (strokeColor !== null && strokeColor.a > 0 &&
        pixels(runStyle.strokeWidth) > 0) {
      setPaint(attributes, 'stroke', runStyle.stroke, runStyle.strokeOpacity);
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
    const inside = Object.assign(
      {}, context, {scale: context.scale * stretch(matrix)});
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
    const deeper = Object.assign({}, context, {
      depth: context.depth + 1,
      scale: context.scale * stretch(transformOf(element, style)),
    });
    if (NAMED_SHAPES.has(name)) {
      if (style.visibility === 'hidden' && !context.inClip) return;
      emitShape(element, style, parent, deeper);
    } else if (name === 'text') {
      emitText(element, style, parent, deeper);
    } else if (name === 'g' || name === 'a') {
      emitGroup(element, style, parent, deeper, 'g');
    } else if (name === 'svg') {
      emitNestedSvg(element, style, parent, deeper);
    } else if (name === 'defs') {
      emitGroup(element, style, parent, deeper, 'defs');
    } else if (name === 'symbol') {
      const extra = {};
      const box = element.getAttribute('viewBox');
      if (box !== null) extra.viewBox = numberList(box).map(num).join(' ');
      emitGroup(element, style, parent, deeper, 'symbol', extra);
    } else if (name === 'clipPath') {
      emitGroup(
        element, style, parent, Object.assign({}, deeper, {inClip: true}),
        'clipPath');
    } else if (name === 'linearGradient' || name === 'radialGradient') {
      emitGradient(element, parent, deeper);
    } else if (name === 'use') {
      emitUse(element, style, parent, deeper);
    } else if (name === 'image') {
      emitImage(element, style, parent, deeper);
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
    if (!CONFIG.allowed) return;
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

  /** The drawing as the engine's own PNG, with the bundled faces embedded. */
  async function rasterise(root, width, height, scale) {
    const pixelScale = rasterScale(width, height, scale);
    const clone = root.cloneNode(true);
    clone.setAttribute('width', num(width));
    clone.setAttribute('height', num(height));
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
    canvas.width = Math.ceil(width * pixelScale);
    canvas.height = Math.ceil(height * pixelScale);
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
    return {png: url.slice(PNG_PREFIX.length), width: width, height: height};
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

  const SECURE_KEYS = [
    'secure', 'securityLevel', 'startOnLoad', 'maxTextSize',
    'suppressErrorRendering', 'maxEdges', 'htmlLabels', 'fontFamily',
    'altFontFamily', 'themeCSS'];

  function mermaidConfiguration(request) {
    const config = fontFamilyOverrides();
    config.themeVariables = Object.assign(
      {}, request.themeVariables || {}, config.themeVariables || {});
    config.themeVariables.fontFamily = cssFamily();
    return Object.assign(config, {
      startOnLoad: false,
      securityLevel: 'strict',
      theme: request.dark ? 'dark' : 'default',
      look: 'neo',
      layout: /^\s*mindmap\b/m.test(request.source || '') ? 'cose-bilkent' : 'elk',
      htmlLabels: false,
      flowchart: Object.assign({}, config.flowchart || {}, {
        htmlLabels: false,
        diagramPadding: 48,
      }),
      gantt: Object.assign({}, config.gantt || {}, {useWidth: 1200}),
      pie: Object.assign({}, config.pie || {}, {useWidth: 1200}),
      sequence: Object.assign({}, config.sequence || {}, {diagramMarginY: 40}),
      elk: Object.assign({}, config.elk || {}, {
        mergeEdges: false,
        nodePlacementStrategy: 'BRANDES_KOEPF',
        nodePlacementAlignment: 'BALANCED',
        cycleBreakingStrategy: 'GREEDY',
      }),
      suppressErrorRendering: true,
      maxTextSize: LIMITS.maxSourceChars,
      maxEdges: LIMITS.maxEdges,
      deterministicIds: true,
      deterministicIDSeed: 'finch',
      // The paths of a node are jittered by a random seed unless one is
      // given, so a diagram would be drawn differently each time it was drawn.
      handDrawnSeed: 1,
      secure: SECURE_KEYS,
    });
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
    mermaid.initialize(mermaidConfiguration(request));

    const addresses = withholdRefusedAddresses(request.source);
    let result;
    layoutRefusal = null;
    layingOut = true;
    try {
      result = await mermaid.render(RENDER_ID, addresses.source);
    } catch (error) {
      throw classifyMermaidError(error);
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
      const svgXml = /xmlns:xlink\s*=/.test(result.svg)
        ? result.svg
        : result.svg.replace(
            /<svg\b/,
            '<svg xmlns:xlink="http://www.w3.org/1999/xlink"');
      const parsed =
        new DOMParser().parseFromString(svgXml, 'image/svg+xml');
      if (parsed.getElementsByTagName('parsererror').length > 0) {
        throw new Failure('unflattenable', 'The diagram was not well formed.');
      }
      const refusal = withholdRefusedImages(parsed) || addresses.refusal ||
        layoutRefusal;
      const root = document.importNode(parsed.documentElement, true);
      holder.appendChild(root);
      const label = accessibleLabel(root);
      const svgTypes = request.svgTypes;
      const wantsSvg = svgAllowed && !request.raster &&
        (!svgTypes || svgTypes.length === 0 || svgTypes.includes(type));
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
        width: raster.width, height: raster.height, label: label,
        fallback: fallback, timings: timings,
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

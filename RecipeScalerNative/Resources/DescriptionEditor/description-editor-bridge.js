/* global YjsBundle */
(function () {
  'use strict';

  const Y = YjsBundle;
  const DEBOUNCE_MS = 400;
  const handlerName = 'descriptionEditor';
  const MIN_INLINE_HEIGHT = 280;
  const HIGHLIGHT_COLOR = '#fef08a';

  let ydoc = null;
  let fragment = null;
  let applyingRemote = false;
  let pushTimer = null;
  let ready = false;
  let inlineMode = true;
  let resizeObserver = null;
  let savedSelectionRange = null;
  var holdSelectionForMarkup = false;
  let pendingRepairUpdate = null;

  const editorEl = document.getElementById('editor');

  function isYXmlText(node) {
    return node && typeof node.toDelta === 'function';
  }

  function isYXmlElement(node) {
    return node && typeof node.getAttributes === 'function' && typeof node.insert === 'function';
  }

  function post(type, payload) {
    const msg = Object.assign({}, payload || {}, { type: type });
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handlerName]) {
      window.webkit.messageHandlers[handlerName].postMessage(msg);
    }
  }

  function escapeHtml(text) {
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function elementTag(node) {
    if (!node || typeof node.nodeName !== 'string') return '';
    if (node.nodeName === 'timer') return 'timer';
    if (node.nodeName === 'ingredient') return 'ingredient';
    return node.nodeName.toLowerCase();
  }

  function attrsToString(node) {
    if (!node || !node.getAttributes) return '';
    const attrs = node.getAttributes();
    return Object.keys(attrs)
      .map((key) => key + '="' + escapeHtml(String(attrs[key])) + '"')
      .join(' ');
  }

  const TIMER_ATTRS = ['data-timer-id', 'data-duration', 'data-type', 'data-value', 'data-name'];
  const INGREDIENT_ATTRS = ['data-ingredient-id', 'data-original-amount', 'data-ratio'];

  function copyAllowedAttributesFromDom(node, allowed) {
    const out = {};
    allowed.forEach((name) => {
      const value = node.getAttribute(name);
      if (value != null && value !== '') out[name] = value;
    });
    return out;
  }

  function applyAllowedAttributes(elem, attrs) {
    Object.keys(attrs).forEach((key) => {
      elem.setAttribute(key, attrs[key]);
    });
  }

  function insertMarkedText(text, marks) {
    const node = new Y.XmlText();
    if (text) node.insert(0, text, marks || {});
    return node;
  }

  function parseAmount(value) {
    if (value == null || value === '') return null;
    var n = parseFloat(String(value).replace(',', '.'));
    return isNaN(n) ? null : n;
  }

  function ingredientDisplayLabel(elem) {
    var attrs = elem && elem.getAttributes ? elem.getAttributes() : {};
    var original = attrs['data-original-amount'];
    var ratio = attrs['data-ratio'] != null ? attrs['data-ratio'] : '1';
    var origN = parseAmount(original);
    var ratioN = parseAmount(ratio);
    if (origN != null && ratioN != null) return formatAmount(origN * ratioN);
    if (original != null && original !== '') return String(original);
    return '';
  }

  function timerDisplayLabelFromAttrs(elem) {
    var attrs = elem && elem.getAttributes ? elem.getAttributes() : {};
    var name = attrs['data-name'] || '';
    if (name) return String(name);
    var value = attrs['data-value'];
    if (value != null && value !== '') return String(value);
    return '';
  }

  function ingredientSpanDisplayText(span) {
    if (!span) return '';
    var original = span.getAttribute('data-original-amount') || '';
    var ratio = span.getAttribute('data-ratio') || '1';
    var origN = parseAmount(original);
    var ratioN = parseAmount(ratio);
    if (origN != null && ratioN != null) return formatAmount(origN * ratioN);
    return span.textContent || original || '';
  }

  function resolveLinkHref(attrs, text) {
    if (!attrs) return null;
    var link = attrs.link;
    if (link && typeof link === 'object' && link.href) return String(link.href);
    if (typeof link === 'string' && link) return link;
    var keys = Object.keys(attrs);
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      if (key === 'link' || key.indexOf('link--') === 0) {
        var val = attrs[key];
        if (val && typeof val === 'object' && val.href) return String(val.href);
      }
    }
    var trimmed = (text || '').trim();
    if (trimmed.indexOf('http://') === 0 || trimmed.indexOf('https://') === 0) return trimmed;
    return null;
  }

  function ingredientReferenceAttrsToString(elem) {
    var attrs = elem && elem.getAttributes ? elem.getAttributes() : {};
    var parts = [];
    INGREDIENT_ATTRS.forEach(function (name) {
      if (attrs[name] != null && attrs[name] !== '') {
        parts.push(name + '="' + escapeHtml(String(attrs[name])) + '"');
      }
    });
    return parts.join(' ');
  }

  function timerReferenceAttrsToString(elem) {
    var attrs = elem && elem.getAttributes ? elem.getAttributes() : {};
    var duration = attrs['data-duration'] != null ? attrs['data-duration'] : attrs.duration;
    var type = attrs['data-type'] || attrs.type || 'minutes';
    var value = attrs['data-value'] != null ? attrs['data-value'] : attrs.value;
    var name = attrs['data-name'] || attrs.name || '';
    var timerId = attrs['data-timer-id'] || attrs.timerId || '';
    var parts = [];
    if (timerId) parts.push('data-timer-id="' + escapeHtml(String(timerId)) + '"');
    if (duration != null && duration !== '') parts.push('data-duration="' + escapeHtml(String(duration)) + '"');
    if (type) parts.push('data-type="' + escapeHtml(String(type)) + '"');
    if (value != null && value !== '') parts.push('data-value="' + escapeHtml(String(value)) + '"');
    if (name) parts.push('data-name="' + escapeHtml(String(name)) + '"');
    return parts.join(' ');
  }

  function readTimerNodePayload(span) {
    var duration = span.getAttribute('data-duration') || span.getAttribute('duration') || '0';
    var type = span.getAttribute('data-type') || span.getAttribute('type') || 'minutes';
    var value = span.getAttribute('data-value') || span.getAttribute('value') || '0';
    var text = (span.textContent || '').trim();
    if ((!duration || duration === '0') && value && value !== '0') {
      var numeric = parseFloat(String(value).replace(',', '.'));
      if (!isNaN(numeric) && numeric > 0) {
        if (type === 'hours') duration = String(Math.round(numeric * 3600));
        else if (type === 'minutes') duration = String(Math.round(numeric * 60));
        else duration = String(Math.round(numeric));
      }
    }
    return {
      nodeType: 'timer',
      timerId: span.getAttribute('data-timer-id') || '',
      duration: duration,
      timerType: type,
      value: value,
      name: span.getAttribute('data-name') || span.getAttribute('name') || '',
      text: text
    };
  }

  function renderXmlText(textNode) {
    const delta = textNode.toDelta ? textNode.toDelta() : [];
    if (!delta.length) {
      const plain = textNode.toString();
      return plain ? escapeHtml(plain) : '';
    }
    return delta
      .map((chunk) => {
        const content = chunk.insert || '';
        if (!content) return '';
        const escaped = escapeHtml(content);
        const attrs = chunk.attributes || {};
        const href = resolveLinkHref(attrs, content);
        if (href) {
          const safeHref = escapeHtml(href);
          const label = escaped || safeHref;
          return '<a href="' + safeHref + '" target="_blank" rel="noopener noreferrer">' + label + '</a>';
        }
        let out = escaped;
        if (attrs.bold) out = '<strong>' + out + '</strong>';
        if (attrs.italic) out = '<em>' + out + '</em>';
        if (attrs.strike) out = '<s>' + out + '</s>';
        if (attrs.code) out = '<code>' + out + '</code>';
        if (attrs.highlight) out = '<mark>' + out + '</mark>';
        return out;
      })
      .join('');
  }

  function renderElement(elem) {
    const tag = elementTag(elem);
    const inner = renderChildren(elem);
    const attrStr = attrsToString(elem);
    const open = attrStr ? '<' + tag + ' ' + attrStr + '>' : '<' + tag + '>';

    switch (tag) {
      case 'paragraph':
        return '<p>' + inner + '</p>';
      case 'heading': {
        const level = (elem.getAttribute && elem.getAttribute('level')) || '1';
        const n = Math.min(6, Math.max(1, parseInt(level, 10) || 1));
        return '<h' + n + '>' + inner + '</h' + n + '>';
      }
      case 'bulletlist':
      case 'bulletList':
        return '<ul>' + inner + '</ul>';
      case 'orderedlist':
      case 'orderedList':
        return '<ol>' + inner + '</ol>';
      case 'listitem':
      case 'listItem':
        return '<li>' + inner + '</li>';
      case 'blockquote':
        return '<blockquote>' + inner + '</blockquote>';
      case 'codeblock':
      case 'codeBlock':
        return '<pre>' + inner + '</pre>';
      case 'hardbreak':
      case 'hardBreak':
        return '<br/>';
      case 'horizontalrule':
      case 'horizontalRule':
        return '<hr/>';
      case 'timer':
      case 'ingredient': {
        const cls = tag === 'timer' ? 'timer-reference' : 'ingredient-reference edit-mode';
        const attrStr = tag === 'timer'
          ? timerReferenceAttrsToString(elem)
          : ingredientReferenceAttrsToString(elem);
        const label = inner || (tag === 'timer' ? timerDisplayLabelFromAttrs(elem) : ingredientDisplayLabel(elem));
        return '<span class="' + cls + '" contenteditable="false"' + (attrStr ? ' ' + attrStr : '') + '>' + escapeHtml(label) + '</span>';
      }
      case 'bold':
        return '<strong>' + inner + '</strong>';
      case 'italic':
        return '<em>' + inner + '</em>';
      case 'strike':
        return '<s>' + inner + '</s>';
      case 'highlight':
        return '<mark>' + inner + '</mark>';
      case 'code':
        return '<code>' + inner + '</code>';
      case 'link':
      case 'a': {
        const href = (elem.getAttribute && elem.getAttribute('href')) || '';
        return '<a href="' + escapeHtml(href) + '" target="_blank" rel="noopener noreferrer">' + inner + '</a>';
      }
      default:
        return inner;
    }
  }

  function renderChildren(parent) {
    let html = '';
    if (!parent || !parent.length) return html;
    for (let i = 0; i < parent.length; i++) {
      const child = parent.get(i);
      if (!child) continue;
      if (isYXmlText(child)) {
        html += renderXmlText(child);
      } else if (isYXmlElement(child)) {
        html += renderElement(child);
      }
    }
    return html;
  }

  function fragmentToHtml() {
    if (!fragment || !fragment.length) return '<p><br></p>';
    const html = renderChildren(fragment);
    return html || '<p><br></p>';
  }

  function clearFragment() {
    if (!fragment) return;
    while (fragment.length > 0) {
      fragment.delete(0, 1);
    }
  }

  function appendParagraphFromElement(el) {
    const tag = el.tagName.toLowerCase();
    if (tag === 'ul' || tag === 'ol') {
      const listTag = tag === 'ul' ? 'bulletList' : 'orderedList';
      const list = new Y.XmlElement(listTag);
      Array.from(el.children).forEach((li) => {
        if (li.tagName.toLowerCase() !== 'li') return;
        const item = new Y.XmlElement('listItem');
        const para = new Y.XmlElement('paragraph');
        const liInline = collectInlineNodes(li);
        if (liInline.length) {
          para.insert(0, liInline);
        }
        item.insert(0, [para]);
        list.insert(list.length, [item]);
      });
      fragment.insert(fragment.length, [list]);
      return;
    }

    const pmTag =
      tag === 'h1' ? 'heading' :
      tag === 'blockquote' ? 'blockquote' :
      tag === 'pre' ? 'codeBlock' :
      'paragraph';

    const para = new Y.XmlElement(pmTag);
    if (pmTag === 'heading') {
      para.setAttribute('level', String(tag.replace('h', '') || '1'));
    }
    const inline = collectInlineNodes(el);
    if (inline.length) {
      para.insert(0, inline);
    }
    fragment.insert(fragment.length, [para]);
  }

  function collectInlineNodes(root) {
    const parts = [];
    function walkChildren(node, marks) {
      Array.from(node.childNodes).forEach((child) => walk(child, marks));
    }
    function walk(node, marks) {
      marks = marks || {};
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent || '';
        if (text) parts.push(insertMarkedText(text, marks));
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      const tag = node.tagName.toLowerCase();
      if (tag === 'br') {
        parts.push(new Y.XmlElement('hardBreak'));
        return;
      }
      if (tag === 'span' && node.classList.contains('timer-reference')) {
        const elem = new Y.XmlElement('timer');
        applyAllowedAttributes(elem, copyAllowedAttributesFromDom(node, TIMER_ATTRS));
        const label = node.textContent || '';
        if (label) elem.insert(0, [new Y.XmlText(label)]);
        parts.push(elem);
        return;
      }
      if (tag === 'span' && node.classList.contains('ingredient-reference')) {
        const elem = new Y.XmlElement('ingredient');
        applyAllowedAttributes(elem, copyAllowedAttributesFromDom(node, INGREDIENT_ATTRS));
        parts.push(elem);
        return;
      }
      if (tag === 'strong' || tag === 'b') {
        walkChildren(node, Object.assign({}, marks, { bold: true }));
        return;
      }
      if (tag === 'em' || tag === 'i') {
        walkChildren(node, Object.assign({}, marks, { italic: true }));
        return;
      }
      if (tag === 'mark') {
        walkChildren(node, Object.assign({}, marks, { highlight: true }));
        return;
      }
      if (tag === 'code') {
        walkChildren(node, Object.assign({}, marks, { code: true }));
        return;
      }
      if (tag === 's' || tag === 'strike') {
        walkChildren(node, Object.assign({}, marks, { strike: true }));
        return;
      }
      if (tag === 'a') {
        const href = node.getAttribute('href') || '';
        const linkMarks = Object.assign({}, marks, href ? { link: { href: href } } : {});
        walkChildren(node, linkMarks);
        return;
      }
      walkChildren(node, marks);
    }
    Array.from(root.childNodes).forEach((child) => walk(child, {}));
    return parts;
  }

  /**
   * Repair legacy/native XmlFragment shapes so web Tiptap Collaboration can load them.
   * - link must be a mark on XmlText, not a link XmlElement node
   * - ingredient is atom: no text children, only data-* attrs
   * - timer/ingredient must not persist class/contenteditable in Y.Xml attrs
   */
  function normalizeFragmentForWeb(frag) {
    if (!frag || !frag.length || !ydoc) return false;
    let changed = false;

    function stripExtraAttrs(elem, allowed) {
      const attrs = elem.getAttributes();
      Object.keys(attrs).forEach((key) => {
        if (allowed.indexOf(key) < 0) {
          elem.removeAttribute(key);
          changed = true;
        }
      });
    }

    function linkElementToMarkedText(elem) {
      const href = elem.getAttribute('href') || '';
      let text = '';
      for (let j = 0; j < elem.length; j++) {
        const child = elem.get(j);
        if (child && isYXmlText(child)) text += child.toString();
      }
      return insertMarkedText(text, href ? { link: { href: href } } : {});
    }

    function normalizeParent(parent) {
      for (let i = 0; i < parent.length; i++) {
        const child = parent.get(i);
        if (!child || !isYXmlElement(child)) continue;
        const tag = elementTag(child);

        if (tag === 'link' || tag === 'a') {
          parent.delete(i, 1);
          parent.insert(i, [linkElementToMarkedText(child)]);
          changed = true;
          continue;
        }

        if (tag === 'ingredient') {
          while (child.length > 0) {
            child.delete(0, 1);
            changed = true;
          }
          stripExtraAttrs(child, INGREDIENT_ATTRS);
        }

        if (tag === 'timer') {
          stripExtraAttrs(child, TIMER_ATTRS);
        }

        if (
          tag === 'paragraph' ||
          tag === 'listitem' ||
          tag === 'heading' ||
          tag === 'blockquote' ||
          tag === 'bulletlist' ||
          tag === 'orderedlist' ||
          tag === 'bulletList' ||
          tag === 'orderedList'
        ) {
          normalizeParent(child);
        }
      }
    }

    ydoc.transact(() => {
      normalizeParent(frag);
    }, 'repair');
    return changed;
  }

  function htmlToFragment(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    clearFragment();
    const blocks = [];
    template.content.childNodes.forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE) blocks.push(node);
    });
    if (!blocks.length) {
      const para = new Y.XmlElement('paragraph');
      fragment.insert(0, [para]);
      return;
    }
    blocks.forEach((el) => appendParagraphFromElement(el));
  }

  function schedulePush() {
    if (!ready || applyingRemote) return;
    if (pushTimer) clearTimeout(pushTimer);
    pushTimer = setTimeout(pushLocalEdit, DEBOUNCE_MS);
  }

  function pushLocalEdit() {
    if (!ydoc || !fragment) return;
    const html = editorEl.innerHTML;
    ydoc.transact(() => {
      htmlToFragment(html);
    });
  }

  function saveSelection() {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || !editorEl) return null;
    const range = sel.getRangeAt(0);
    if (!editorEl.contains(range.commonAncestorContainer)) return null;
    return range.cloneRange();
  }

  function restoreSelection() {
    if (!savedSelectionRange || !editorEl) return false;
    const sel = window.getSelection();
    if (!sel) return false;
    sel.removeAllRanges();
    sel.addRange(savedSelectionRange);
    return true;
  }

  function captureSelection() {
    const range = saveSelection();
    if (range) savedSelectionRange = range;
  }

  function getSelectedText() {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || !editorEl) return '';
    const range = sel.getRangeAt(0);
    if (!editorEl.contains(range.commonAncestorContainer)) {
      if (savedSelectionRange) {
        return savedSelectionRange.toString();
      }
      return '';
    }
    return sel.toString();
  }

  function insertNodeAtSelection(node) {
    restoreSelection();
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) {
      editorEl.appendChild(node);
      return;
    }
    const range = sel.getRangeAt(0);
    if (!editorEl.contains(range.commonAncestorContainer)) return;
    range.deleteContents();
    range.insertNode(node);
    const after = document.createRange();
    after.setStartAfter(node);
    after.collapse(true);
    sel.removeAllRanges();
    sel.addRange(after);
    savedSelectionRange = after.cloneRange();
  }

  function surroundSelection(tagName) {
    restoreSelection();
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;
    const range = sel.getRangeAt(0);
    if (!editorEl.contains(range.commonAncestorContainer) || range.collapsed) return;
    const wrapper = document.createElement(tagName);
    try {
      range.surroundContents(wrapper);
    } catch (_err) {
      const contents = range.extractContents();
      wrapper.appendChild(contents);
      range.insertNode(wrapper);
    }
    const after = document.createRange();
    after.setStartAfter(wrapper);
    after.collapse(true);
    sel.removeAllRanges();
    sel.addRange(after);
    savedSelectionRange = after.cloneRange();
  }

  /**
   * Walk up from a DOM node to check for an explicit <strong> or <b> ancestor
   * inside the editor. Stops at the editor element or a heading block.
   * Used to distinguish real bold marks from headings' inherent font-weight.
   */
  function hasExplicitBoldAncestor(node) {
    var el = node;
    if (!el) return false;
    if (el.nodeType === 3) el = el.parentNode;
    while (el && el !== editorEl) {
      var tag = el.nodeName;
      if (tag === 'STRONG' || tag === 'B') return true;
      if (tag === 'H1' || tag === 'H2' || tag === 'H3' || tag === 'H4' || tag === 'H5' || tag === 'H6') return false;
      el = el.parentNode;
    }
    return false;
  }

  function postSelectionState() {
    try {
      const selectedText = getSelectedText();
      const hasSelection = selectedText.length > 0;
      var fmtBlock = document.queryCommandValue('formatBlock').toLowerCase();
      var isH1 = fmtBlock === 'h1';
      var isHeading = fmtBlock.charAt(0) === 'h' && fmtBlock.length === 2;

      // queryCommandState('bold') is unreliable inside headings — WebKit
      // treats the heading's inherent font-weight (≥600) as bold even when
      // no explicit <strong>/<b> tag exists. Fall back to DOM walk when
      // inside a heading block.
      var bold;
      if (isHeading && document.queryCommandState('bold')) {
        var sel = window.getSelection();
        bold = sel && sel.anchorNode ? hasExplicitBoldAncestor(sel.anchorNode) : false;
      } else {
        bold = document.queryCommandState('bold');
      }

      post('selectionState', {
        bold: bold,
        heading1: isH1,
        highlight: document.queryCommandState('hiliteColor') || document.queryCommandState('backColor'),
        bulletList: document.queryCommandState('insertUnorderedList'),
        orderedList: document.queryCommandState('insertOrderedList'),
        hasSelection: hasSelection,
        selectedText: selectedText,
        canBold: true,
        canHeading1: true,
        canHighlight: true,
        canBulletList: true,
        canOrderedList: true,
      });
    } catch (_err) {
      // queryCommandState unavailable during early init in some WebKit builds
    }
  }

  function measureContentHeight() {
    if (!editorEl) return;
    const height = Math.max(MIN_INLINE_HEIGHT, editorEl.scrollHeight + 8);
    post('contentHeight', { height: height });
  }

  function setupResizeObserver() {
    if (!editorEl || typeof ResizeObserver === 'undefined') return;
    if (resizeObserver) resizeObserver.disconnect();
    resizeObserver = new ResizeObserver(measureContentHeight);
    resizeObserver.observe(editorEl);
  }

  function injectFonts(config) {
    const family = config.fontFamily || 'Martian Grotesk Nr Lt';
    const regularURL = config.fontRegularURL;
    const mediumURL = config.fontMediumURL;
    if (!regularURL && !mediumURL) {
      if (editorEl) editorEl.style.fontFamily = '"' + family + '", -apple-system, BlinkMacSystemFont, sans-serif';
      return;
    }
    const style = document.createElement('style');
    let css = '';
    if (regularURL) {
      css += '@font-face { font-family: "' + family + '"; src: url("' + regularURL + '") format("opentype"); font-weight: 400; font-style: normal; }';
    }
    if (mediumURL) {
      css += '@font-face { font-family: "' + family + ' Medium"; src: url("' + mediumURL + '") format("opentype"); font-weight: 500; font-style: normal; }';
    }
    style.textContent = css;
    document.head.appendChild(style);
    if (editorEl) {
      editorEl.style.fontFamily = '"' + family + '", -apple-system, BlinkMacSystemFont, sans-serif';
    }
  }

  function applyTypography(config) {
    const fontSize = config.fontSize || 16;
    if (!editorEl) return;
    editorEl.style.fontSize = fontSize + 'px';
    editorEl.style.lineHeight = '1.5';
    if (config.recipeColor) {
      document.documentElement.style.setProperty('--recipeColor', config.recipeColor);
      document.documentElement.style.setProperty('--recipeColorBg', config.recipeColor + '26');
    }
    if (config.linkColor) {
      document.documentElement.style.setProperty('--linkColor', config.linkColor);
    }
    injectFonts(config);
  }

  function applyInlinePresentation(config) {
    document.body.classList.add('inline-embedded');
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';
    applyTypography(config || {});
    measureContentHeight();
    setupResizeObserver();
  }

  function toggleHighlight() {
    if (document.queryCommandSupported('hiliteColor')) {
      document.execCommand('hiliteColor', false, HIGHLIGHT_COLOR);
      return;
    }
    if (document.queryCommandSupported('backColor')) {
      document.execCommand('backColor', false, HIGHLIGHT_COLOR);
      return;
    }
    surroundSelection('mark');
  }

  function toggleHeading1() {
    const current = document.queryCommandValue('formatBlock').toLowerCase();
    if (current === 'h1') {
      document.execCommand('formatBlock', false, 'p');
    } else {
      document.execCommand('formatBlock', false, 'h1');
    }
  }

  function markAsTimer(args) {
    const a = args || {};
    const selectedText = getSelectedText();
    const span = document.createElement('span');
    span.className = 'timer-reference';
    span.setAttribute('data-duration', String(a.duration || 0));
    span.setAttribute('data-type', a.type || 'minutes');
    span.setAttribute('data-value', String(a.value || 0));
    span.setAttribute('data-timer-id', a.timerId || ('timer-' + Date.now()));
    if (a.name) span.setAttribute('data-name', a.name);
    span.textContent = selectedText || String(a.value || '');
    span.contentEditable = 'false';
    insertNodeAtSelection(span);
  }

  function formatAmount(n) {
    if (Number.isInteger(n)) return String(n);
    var s = n.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
    return s;
  }

  function markAsIngredient(args) {
    const a = args || {};
    const span = document.createElement('span');
    span.className = 'ingredient-reference edit-mode';
    span.setAttribute('data-ingredient-id', a.ingredientId || '');
    if (a.originalAmount != null && a.originalAmount !== '') {
      span.setAttribute('data-original-amount', String(a.originalAmount));
    }
    if (a.ratio != null && a.ratio !== '') {
      span.setAttribute('data-ratio', String(a.ratio));
    }
    // Compute displayed value: originalAmount * ratio
    if (a.ratio != null && a.originalAmount) {
      var numeric = parseFloat(String(a.originalAmount).replace(',', '.'));
      var ratio = parseFloat(String(a.ratio));
      if (!isNaN(numeric) && !isNaN(ratio)) {
        span.textContent = formatAmount(numeric * ratio);
      } else {
        span.textContent = String(a.originalAmount);
      }
    } else {
      var selectedText = getSelectedText();
      span.textContent = selectedText || String(a.originalAmount || '');
    }
    span.contentEditable = 'false';
    insertNodeAtSelection(span);
  }

  function runCommand(name, args) {
    if (!editorEl) return;
    const a = args || {};
    switch (name) {
      case 'toggleBold':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        document.execCommand('bold');
        break;
      case 'toggleHeading1':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        toggleHeading1();
        break;
      case 'toggleHighlight':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        toggleHighlight();
        break;
      case 'toggleBulletList':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        document.execCommand('insertUnorderedList');
        break;
      case 'toggleOrderedList':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        document.execCommand('insertOrderedList');
        break;
      case 'toggleItalic':
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        document.execCommand('italic');
        break;
      case 'markAsTimer':
        holdSelectionForMarkup = false;
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        markAsTimer(a);
        break;
      case 'markAsIngredient':
        holdSelectionForMarkup = false;
        editorEl.focus({ preventScroll: true });
        restoreSelection();
        markAsIngredient(a);
        break;
      case 'removeTimerMarkup':
        removeTimerMarkup(a);
        captureSelection();
        postSelectionState();
        measureContentHeight();
        return;
      case 'removeIngredientMarkup':
        removeIngredientMarkup(a);
        captureSelection();
        postSelectionState();
        measureContentHeight();
        return;
      case 'renameTimer':
        renameTimer(a);
        break;
      case 'updateIngredientMarkup':
        updateIngredientMarkup(a);
        break;
      case 'prepareMarkupSelection':
        captureSelection();
        holdSelectionForMarkup = true;
        if (savedSelectionRange) restoreSelection();
        return;
      case 'releaseMarkupSelection':
        holdSelectionForMarkup = false;
        return;
      case 'focus':
        editorEl.focus({ preventScroll: true });
        notifyFocus();
        return;
      case 'blur':
        holdSelectionForMarkup = false;
        editorEl.blur();
        notifyBlur();
        return;
      default:
        break;
    }
    captureSelection();
    schedulePush();
    postSelectionState();
    measureContentHeight();
  }

  function escapeSelectorValue(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  function timerSpanMatches(span, args) {
    if (!span || !args) return false;
    var timerId = args.timerId ? String(args.timerId) : '';
    if (timerId) {
      var spanId = span.getAttribute('data-timer-id') || '';
      if (spanId && spanId === timerId) return true;
    }
    var duration = args.duration != null ? String(args.duration) : '';
    var type = args.type != null ? String(args.type) : '';
    var value = args.value != null ? String(args.value) : '';
    var text = args.text != null ? String(args.text).trim() : '';
    var spanDuration = span.getAttribute('data-duration') || '';
    var spanType = span.getAttribute('data-type') || '';
    var spanValue = span.getAttribute('data-value') || '';
    var spanText = (span.textContent || '').trim();
    if (duration && spanDuration === duration && type && spanType === type) {
      if (text && spanText === text) return true;
      if (value && spanValue === value) return true;
      if (!text && !value) return true;
    }
    return false;
  }

  function findTimerSpan(args) {
    args = args || {};
    var timerId = args.timerId;
    if (timerId) {
      var byId = editorEl.querySelector('.timer-reference[data-timer-id="' + escapeSelectorValue(timerId) + '"]');
      if (byId) return byId;
    }
    var spans = editorEl.querySelectorAll('.timer-reference');
    for (var i = 0; i < spans.length; i++) {
      if (timerSpanMatches(spans[i], args)) return spans[i];
    }
    return null;
  }

  function findIngredientSpan(args) {
    const ingredientId = args && args.ingredientId;
    if (!ingredientId) return null;
    return editorEl.querySelector('.ingredient-reference[data-ingredient-id="' + escapeSelectorValue(ingredientId) + '"]');
  }

  function replaceSpanWithText(span, text) {
    if (!span || !span.parentNode) return;
    var node = document.createTextNode(text);
    span.parentNode.replaceChild(node, span);
    schedulePush();
    measureContentHeight();
  }

  function removeTimerMarkup(args) {
    var span = findTimerSpan(args || {});
    if (!span) return;
    var text = (args && args.text) || span.textContent || span.getAttribute('data-value') || '';
    replaceSpanWithText(span, text);
  }

  function removeIngredientMarkup(args) {
    var span = findIngredientSpan(args || {});
    if (!span) return;
    var text = (args && args.displayText) || ingredientSpanDisplayText(span);
    replaceSpanWithText(span, text);
  }

  function renameTimer(args) {
    var span = findTimerSpan(args || {});
    if (!span || !args || !args.name) return;
    if (!span.getAttribute('data-timer-id')) {
      span.setAttribute('data-timer-id', 'timer-' + Date.now());
    }
    span.setAttribute('data-name', String(args.name));
    schedulePush();
  }

  function updateIngredientMarkup(args) {
    var span = findIngredientSpan(args || {});
    if (!span || !args) return;
    if (args.ratio != null && args.ratio !== '') {
      span.setAttribute('data-ratio', String(args.ratio));
    }
    if (args.displayText != null && args.displayText !== '') {
      span.textContent = String(args.displayText);
    }
    schedulePush();
    measureContentHeight();
  }

  function handleNativeMessage(msg) {
    if (!msg || !msg.type) return;
    switch (msg.type) {
      case 'configure':
        inlineMode = msg.inline !== false;
        if (inlineMode) applyInlinePresentation(msg);
        else applyTypography(msg);
        break;
      case 'init': {
        const state = new Uint8Array(msg.state || []);
        ydoc = new Y.Doc();
        ydoc.on('update', (update, origin) => {
          if (origin === 'remote') return;
          if (origin === 'repair') {
            pendingRepairUpdate = update;
            return;
          }
          if (!ready || applyingRemote) return;
          post('update', { update: Array.from(update) });
        });
        if (state.length) {
          Y.applyUpdate(ydoc, state, 'remote');
        }
        fragment = ydoc.getXmlFragment('description');
        normalizeFragmentForWeb(fragment);
        editorEl.innerHTML = fragmentToHtml();
        ready = true;
        if (pendingRepairUpdate) {
          post('update', { update: Array.from(pendingRepairUpdate) });
          pendingRepairUpdate = null;
        }
        post('ready', { fragmentLength: fragment.length });
        measureContentHeight();
        postSelectionState();
        break;
      }
      case 'applyUpdate': {
        if (!ydoc) return;
        applyingRemote = true;
        try {
          const beforePlain = (editorEl.textContent || '').length;
          Y.applyUpdate(ydoc, new Uint8Array(msg.update || []), 'remote');
          if (fragment) editorEl.innerHTML = fragmentToHtml();
          measureContentHeight();
        } finally {
          applyingRemote = false;
        }
        break;
      }
      case 'command':
        runCommand(msg.name, msg.args);
        break;
      default:
        break;
    }
  }

  window.__descriptionEditorReceive = handleNativeMessage;

  editorEl.addEventListener('input', () => {
    schedulePush();
    measureContentHeight();
  });

  function notifyFocus() {
    post('focus');
  }

  function notifyBlur() {
    captureSelection();
    post('blur');
    if (holdSelectionForMarkup && savedSelectionRange) {
      requestAnimationFrame(function () {
        restoreSelection();
      });
    }
  }

  function isInsideEditor(node) {
    return node && editorEl && (node === editorEl || editorEl.contains(node));
  }

  editorEl.addEventListener('focusin', notifyFocus);
  editorEl.addEventListener('focusout', function (e) {
    if (isInsideEditor(e.relatedTarget)) return;
    notifyBlur();
  });
  editorEl.addEventListener('pointerdown', function (e) {
    if (e.target.closest && (e.target.closest('.timer-reference') || e.target.closest('.ingredient-reference'))) {
      return;
    }
    notifyFocus();
  });
  editorEl.addEventListener('pointerup', captureSelection);
  editorEl.addEventListener('keyup', captureSelection);

  // Guard: prevent editing inside timer/ingredient spans
  editorEl.addEventListener('beforeinput', function (e) {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;
    var node = sel.anchorNode;
    while (node && node !== editorEl) {
      if (node.nodeType === Node.ELEMENT_NODE &&
          (node.classList.contains('timer-reference') || node.classList.contains('ingredient-reference'))) {
        e.preventDefault();
        return;
      }
      node = node.parentNode;
    }
  });

  function postNodeClick(span, payload) {
    notifyBlur();
    var rect = span.getBoundingClientRect();
    post('nodeClick', Object.assign({
      anchorX: rect.left,
      anchorY: rect.top,
      anchorWidth: rect.width,
      anchorHeight: rect.height
    }, payload || {}));
  }

  var suppressReferenceClickUntil = 0;

  function handleReferenceNodeTap(e, fromClick) {
    var timerSpan = e.target.closest && e.target.closest('.timer-reference');
    var ingredientSpan = e.target.closest && e.target.closest('.ingredient-reference');
    if (!timerSpan && !ingredientSpan) return false;

    var now = Date.now();
    if (fromClick && now < suppressReferenceClickUntil) {
      e.preventDefault();
      e.stopPropagation();
      return true;
    }

    e.preventDefault();
    e.stopPropagation();

    if (!fromClick) {
      suppressReferenceClickUntil = now + 450;
    }

    if (timerSpan) {
      postNodeClick(timerSpan, readTimerNodePayload(timerSpan));
      return true;
    }
    if (ingredientSpan) {
      postNodeClick(ingredientSpan, {
        nodeType: 'ingredient',
        ingredientId: ingredientSpan.getAttribute('data-ingredient-id') || '',
        originalAmount: ingredientSpan.getAttribute('data-original-amount') || '',
        ratio: ingredientSpan.getAttribute('data-ratio') || '',
        text: ingredientSpan.textContent || ''
      });
      return true;
    }
    return false;
  }

  // Handle taps on timer/ingredient references (capture phase for reliability in WKWebView)
  editorEl.addEventListener('pointerup', function (e) {
    handleReferenceNodeTap(e, false);
  }, true);
  editorEl.addEventListener('click', function (e) {
    handleReferenceNodeTap(e, true);
  }, true);

  document.addEventListener('selectionchange', () => {
    if (!ready) return;
    const sel = window.getSelection();
    if (!sel || !editorEl) return;
    if (sel.anchorNode && editorEl.contains(sel.anchorNode)) {
      captureSelection();
      postSelectionState();
    }
  });

  post('loaded');
})();

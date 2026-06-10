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

  const editorEl = document.getElementById('editor');

  function post(type, payload) {
    const msg = Object.assign({ type: type }, payload || {});
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
        if (attrs.link && attrs.link.href) {
          const href = escapeHtml(attrs.link.href);
          return '<a href="' + href + '" target="_blank" rel="noopener noreferrer">' + escaped + '</a>';
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
        const cls = tag === 'timer' ? 'timer-reference' : 'ingredient-reference';
        return '<span class="' + cls + '" ' + attrsToString(elem) + '>' + inner + '</span>';
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
      if (child.constructor === Y.XmlText) {
        html += renderXmlText(child);
      } else if (child.constructor === Y.XmlElement) {
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
    function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent || '';
        if (text) parts.push(new Y.XmlText(text));
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      const tag = node.tagName.toLowerCase();
      if (tag === 'br') {
        const br = new Y.XmlElement('hardBreak');
        parts.push(br);
        return;
      }
      if (tag === 'span' && (node.classList.contains('timer-reference') || node.classList.contains('ingredient-reference'))) {
        const pmTag = node.classList.contains('timer-reference') ? 'timer' : 'ingredient';
        const elem = new Y.XmlElement(pmTag);
        Array.from(node.attributes).forEach((attr) => {
          elem.setAttribute(attr.name, attr.value);
        });
        const label = node.textContent || '';
        if (label) elem.insert(0, [new Y.XmlText(label)]);
        parts.push(elem);
        return;
      }
      if (tag === 'strong' || tag === 'b') {
        const elem = new Y.XmlElement('bold');
        elem.insert(0, [new Y.XmlText(node.textContent || '')]);
        parts.push(elem);
        return;
      }
      if (tag === 'em' || tag === 'i') {
        const elem = new Y.XmlElement('italic');
        elem.insert(0, [new Y.XmlText(node.textContent || '')]);
        parts.push(elem);
        return;
      }
      if (tag === 'mark') {
        const elem = new Y.XmlElement('highlight');
        elem.insert(0, [new Y.XmlText(node.textContent || '')]);
        parts.push(elem);
        return;
      }
      if (tag === 'a') {
        const elem = new Y.XmlElement('link');
        const href = node.getAttribute('href') || '';
        if (href) elem.setAttribute('href', href);
        elem.insert(0, [new Y.XmlText(node.textContent || '')]);
        parts.push(elem);
        return;
      }
      Array.from(node.childNodes).forEach(walk);
    }
    Array.from(root.childNodes).forEach(walk);
    return parts;
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
    // #region agent log
    fetch('http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'9c8634'},body:JSON.stringify({sessionId:'9c8634',hypothesisId:'H1',location:'description-editor-bridge.js:schedulePush',message:'debounce_scheduled',data:{debounceMs:DEBOUNCE_MS,htmlLen:(editorEl&&editorEl.innerHTML)?editorEl.innerHTML.length:0},timestamp:Date.now(),runId:'pre-fix'})}).catch(function(){});
    // #endregion
    pushTimer = setTimeout(pushLocalEdit, DEBOUNCE_MS);
  }

  function pushLocalEdit() {
    if (!ydoc || !fragment) return;
    const html = editorEl.innerHTML;
    const plainLen = (editorEl.textContent || '').length;
    ydoc.transact(() => {
      htmlToFragment(html);
    });
    // #region agent log
    fetch('http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'9c8634'},body:JSON.stringify({sessionId:'9c8634',hypothesisId:'H2',location:'description-editor-bridge.js:pushLocalEdit',message:'pushed_to_ydoc',data:{htmlLen:String(html.length),plainLen:String(plainLen),fragLen:String(fragment?fragment.length:0)},timestamp:Date.now(),runId:'pre-fix'})}).catch(function(){});
    // #endregion
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

  function postSelectionState() {
    const selectedText = getSelectedText();
    const hasSelection = selectedText.length > 0;
    post('selectionState', {
      bold: document.queryCommandState('bold'),
      heading1: document.queryCommandValue('formatBlock').toLowerCase() === 'h1',
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
    editorEl.focus({ preventScroll: true });
    restoreSelection();
    const a = args || {};
    switch (name) {
      case 'toggleBold':
        document.execCommand('bold');
        break;
      case 'toggleHeading1':
        toggleHeading1();
        break;
      case 'toggleHighlight':
        toggleHighlight();
        break;
      case 'toggleBulletList':
        document.execCommand('insertUnorderedList');
        break;
      case 'toggleOrderedList':
        document.execCommand('insertOrderedList');
        break;
      case 'toggleItalic':
        document.execCommand('italic');
        break;
      case 'markAsTimer':
        markAsTimer(a);
        break;
      case 'markAsIngredient':
        markAsIngredient(a);
        break;
      case 'focus':
        editorEl.focus({ preventScroll: true });
        return;
      case 'blur':
        editorEl.blur();
        return;
      default:
        break;
    }
    captureSelection();
    schedulePush();
    postSelectionState();
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
          if (!ready || applyingRemote || origin === 'remote') return;
          // #region agent log
          fetch('http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'9c8634'},body:JSON.stringify({sessionId:'9c8634',hypothesisId:'H1',location:'description-editor-bridge.js:ydoc.on(update)',message:'posting_update_to_swift',data:{updateBytes:String(update?update.length:0)},timestamp:Date.now(),runId:'pre-fix'})}).catch(function(){});
          // #endregion
          post('update', { update: Array.from(update) });
        });
        if (state.length) {
          Y.applyUpdate(ydoc, state, 'remote');
        }
        fragment = ydoc.getXmlFragment('description');
        editorEl.innerHTML = fragmentToHtml();
        ready = true;
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
          // #region agent log
          fetch('http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'9c8634'},body:JSON.stringify({sessionId:'9c8634',hypothesisId:'H5',location:'description-editor-bridge.js:applyUpdate',message:'remote_apply_overwrote_dom',data:{beforePlain:String(beforePlain),afterPlain:String((editorEl.textContent||'').length)},timestamp:Date.now(),runId:'pre-fix'})}).catch(function(){});
          // #endregion
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
  }

  editorEl.addEventListener('focus', notifyFocus);
  editorEl.addEventListener('blur', notifyBlur);
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

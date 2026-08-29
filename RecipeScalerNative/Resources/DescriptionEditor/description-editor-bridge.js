/* global YjsBundle */
(function () {
  'use strict';

  const {
    Editor,
    StarterKit,
    Highlight,
    Link,
    Collaboration,
    Y,
    TimerNode,
    IngredientNode,
    HeadingWithHash,
    ScaleStorageExtension,
  } = YjsBundle;

  const handlerName = 'descriptionEditor';
  const MIN_FULLSCREEN_HEIGHT = 280;
  const MIN_INLINE_CONTENT_HEIGHT = 36;

  let ydoc = null;
  let editor = null;
  let applyingRemote = false;
  let ready = false;
  let inlineMode = true;
  let resizeObserver = null;
  let savedSelection = null;
  let holdSelectionForMarkup = false;
  let pendingScale = null;
  let pendingOutboundUpdates = [];
  let outboundFlushTimer = null;
  let selectionStateTimer = null;
  let contentHeightTimer = null;
  const OUTBOUND_DEBOUNCE_MS = 50;
  const UI_POST_DEBOUNCE_MS = 80;

  const editorEl = document.getElementById('editor');

  function post(type, payload) {
    const msg = Object.assign({}, payload || {}, { type: type });
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handlerName]) {
      window.webkit.messageHandlers[handlerName].postMessage(msg);
    }
  }

  function editorDom() {
    return editor && editor.view ? editor.view.dom : editorEl;
  }

  function buildExtensions(fragment) {
    return [
      StarterKit.configure({ undoRedo: false, heading: false, link: false }),
      HeadingWithHash.configure({ levels: [1] }),
      Highlight.configure({
        HTMLAttributes: { class: 'highlight-mark' },
      }),
      Link.configure({
        openOnClick: false,
        autolink: true,
        HTMLAttributes: { class: 'text-link' },
      }),
      ScaleStorageExtension,
      TimerNode,
      IngredientNode,
      Collaboration.configure({ fragment: fragment }),
    ];
  }

  function destroyEditor() {
    if (editor) {
      editor.destroy();
      editor = null;
    }
  }

  function applyPendingScale() {
    if (!editor || !pendingScale) return;
    const storage = editor.storage.scaleStorage;
    if (!storage) return;
    storage.scaleFactor = pendingScale.scaleFactor != null ? pendingScale.scaleFactor : 1;
    storage.ingredients = pendingScale.ingredients || [];
    storage.locale = pendingScale.locale || 'en';
    const tr = editor.state.tr;
    tr.setMeta('scaleUpdate', storage.scaleFactor);
    tr.setMeta('addToHistory', false);
    editor.view.dispatch(tr);
  }

  function createEditor(fragment) {
    destroyEditor();
    editor = new Editor({
      element: editorEl,
      extensions: buildExtensions(fragment),
      editable: true,
      shouldRerenderOnTransaction: true,
      editorProps: {
        attributes: {
          class: 'tiptap-description ProseMirror',
          spellcheck: 'true',
        },
      },
      onCreate: function () {
        applyPendingScale();
      },
      onUpdate: function () {
        measureContentHeight();
        postSelectionState();
      },
      onSelectionUpdate: function () {
        postSelectionState();
      },
      onFocus: function () {
        if (inlineMode) {
          requestAnimationFrame(function () {
            measureContentHeightNow();
          });
        }
        post('focus');
      },
      onBlur: function () {
        captureSelection();
        post('blur');
        if (holdSelectionForMarkup && savedSelection) {
          requestAnimationFrame(restoreSelection);
        }
      },
    });
  }

  function captureSelection() {
    if (!editor) return;
    const { from, to } = editor.state.selection;
    savedSelection = { from: from, to: to };
  }

  function restoreSelection() {
    if (!editor || !savedSelection) return;
    editor.commands.setTextSelection(savedSelection);
  }

  function getSelectedText() {
    if (!editor) return '';
    const { from, to, empty } = editor.state.selection;
    if (empty) return '';
    return editor.state.doc.textBetween(from, to);
  }

  function postSelectionStateNow() {
    if (!editor) return;
    try {
      const { empty } = editor.state.selection;
      const selectedText = getSelectedText();
      post('selectionState', {
        bold: editor.isActive('bold'),
        heading1: editor.isActive('heading', { level: 1 }),
        highlight: editor.isActive('highlight'),
        bulletList: editor.isActive('bulletList'),
        orderedList: editor.isActive('orderedList'),
        hasSelection: !empty,
        selectedText: selectedText,
        canBold: editor.can().toggleBold(),
        canHeading1: editor.can().toggleHeading({ level: 1 }),
        canHighlight: editor.can().toggleHighlight(),
        canBulletList: editor.can().toggleBulletList(),
        canOrderedList: editor.can().toggleOrderedList(),
      });
    } catch (_err) {
      /* early init */
    }
  }

  function postSelectionState() {
    if (selectionStateTimer) clearTimeout(selectionStateTimer);
    selectionStateTimer = setTimeout(function () {
      selectionStateTimer = null;
      postSelectionStateNow();
    }, UI_POST_DEBOUNCE_MS);
  }

  function getCaretRectInEditor() {
    if (!editor || !editor.view) return null;
    try {
      const view = editor.view;
      const dom = editorDom();
      if (!dom) return null;
      const from = editor.state.selection.from;
      const to = editor.state.selection.to;
      const start = view.coordsAtPos(from);
      const end = view.coordsAtPos(to);
      const domRect = dom.getBoundingClientRect();
      const top = Math.min(start.top, end.top) - domRect.top;
      const bottom = Math.max(start.bottom, end.bottom) - domRect.top;
      const left = Math.min(start.left, end.left) - domRect.left;
      const right = Math.max(start.right, end.right) - domRect.left;
      const minHeight = 24;
      return {
        x: left,
        y: top,
        width: Math.max(right - left, 1),
        height: Math.max(bottom - top, minHeight),
      };
    } catch (_err) {
      return null;
    }
  }

  function blockHasVisibleContent(el) {
    if (!el) return false;
    var text = (el.textContent || '').replace(/\u200b/g, '').trim();
    if (text.length > 0) return true;
    return !!(
      el.querySelector &&
      el.querySelector(
        'img, ul, ol, hr, table, .timer-reference, .ingredient-reference, [data-timer-id], [data-ingredient-id]'
      )
    );
  }

  function pmBlockHasVisibleContent(node) {
    if (!node || !node.isBlock) return false;
    var text = (node.textContent || '').replace(/\u200b/g, '').trim();
    if (text.length > 0) return true;
    var hasAtom = false;
    node.descendants(function (child) {
      if (child.type && (child.type.name === 'timer' || child.type.name === 'ingredient')) {
        hasAtom = true;
      }
    });
    return hasAtom;
  }

  function measureLastTextBottom(root, domRect) {
    var bottom = 0;
    if (!root) return 0;
    try {
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
      var node;
      while ((node = walker.nextNode())) {
        var text = (node.nodeValue || '').replace(/\u200b/g, '').trim();
        if (!text) continue;
        var range = document.createRange();
        range.setStart(node, 0);
        range.setEnd(node, node.nodeValue.length);
        var rects = range.getClientRects();
        for (var i = 0; i < rects.length; i++) {
          if (rects[i].height > 0) {
            bottom = Math.max(bottom, rects[i].bottom - domRect.top);
          }
        }
      }
    } catch (_rangeErr) {
      /* layout mid-transaction */
    }
    return bottom;
  }

  function measurePaintedContentBottom(dom, domRect) {
    var root = dom.classList && dom.classList.contains('ProseMirror') ? dom : dom.querySelector('.ProseMirror') || dom;
    var bottom = measureLastTextBottom(root, domRect);

    if (bottom <= 0) {
      for (var i = root.children.length - 1; i >= 0; i--) {
        var child = root.children[i];
        if (!blockHasVisibleContent(child)) continue;
        var layoutBottom = child.offsetTop + child.offsetHeight;
        if (layoutBottom > 0) bottom = Math.max(bottom, layoutBottom);
        var rect = child.getBoundingClientRect();
        if (rect.height > 0) bottom = Math.max(bottom, rect.bottom - domRect.top);
        break;
      }
    }

    if (editor && editor.view && editor.state.doc.content.size > 0) {
      try {
        var headCoords = editor.view.coordsAtPos(editor.state.selection.from);
        var caretBottom = headCoords.bottom - domRect.top;
        if (bottom <= 0 || (caretBottom > 0 && caretBottom <= bottom + 48)) {
          bottom = Math.max(bottom, caretBottom);
        }
      } catch (_coordsErr) {
        /* layout mid-transaction */
      }
    }

    return bottom;
  }

  function withInlineShrinkWrapMeasure(dom, measureFn) {
    var editorHost = document.getElementById('editor');
    var saved = {
      hostHeight: editorHost ? editorHost.style.height : '',
      hostMinHeight: editorHost ? editorHost.style.minHeight : '',
      domHeight: dom.style.height,
      domMinHeight: dom.style.minHeight,
    };
    if (editorHost) {
      editorHost.style.height = 'auto';
      editorHost.style.minHeight = '0';
    }
    dom.style.height = 'auto';
    dom.style.minHeight = '0';
    void dom.offsetHeight;
    var result = measureFn();
    if (editorHost) {
      editorHost.style.height = saved.hostHeight;
      editorHost.style.minHeight = saved.hostMinHeight;
    }
    dom.style.height = saved.domHeight;
    dom.style.minHeight = saved.domMinHeight;
    return result;
  }

  function measureInlineLayoutHeight(dom) {
    withInlineShrinkWrapMeasure(dom, function () {
      var scrollHeight = dom.scrollHeight;
      var domRect = dom.getBoundingClientRect();
      var paintedBottom = measurePaintedContentBottom(dom, domRect);
      var trailing = 8;
      var height =
        paintedBottom > 0
          ? Math.max(MIN_INLINE_CONTENT_HEIGHT, paintedBottom + trailing)
          : Math.max(MIN_INLINE_CONTENT_HEIGHT, scrollHeight);
      post('contentHeight', {
        height: height,
        scrollHeight: scrollHeight,
        paintedBottom: paintedBottom,
      });
    });
  }

  function measureContentHeightNow() {
    const dom = editorDom();
    if (!dom) return;
    if (inlineMode) {
      measureInlineLayoutHeight(dom);
      return;
    }
    const measured = dom.scrollHeight;
    const height = Math.max(MIN_FULLSCREEN_HEIGHT, measured + 8);
    post('contentHeight', { height: height });
  }

  function measureContentHeight() {
    if (contentHeightTimer) clearTimeout(contentHeightTimer);
    contentHeightTimer = setTimeout(function () {
      contentHeightTimer = null;
      measureContentHeightNow();
    }, UI_POST_DEBOUNCE_MS);
  }

  function flushOutboundUpdates() {
    if (outboundFlushTimer) {
      clearTimeout(outboundFlushTimer);
      outboundFlushTimer = null;
    }
    if (!pendingOutboundUpdates.length) return;
    const merged =
      pendingOutboundUpdates.length === 1
        ? pendingOutboundUpdates[0]
        : Y.mergeUpdates(pendingOutboundUpdates);
    pendingOutboundUpdates = [];
    post('update', { update: Array.from(merged) });
  }

  function scheduleOutboundUpdate(update) {
    pendingOutboundUpdates.push(update);
    if (outboundFlushTimer) clearTimeout(outboundFlushTimer);
    outboundFlushTimer = setTimeout(flushOutboundUpdates, OUTBOUND_DEBOUNCE_MS);
  }

  function setupResizeObserver() {
    const dom = editorDom();
    if (!dom || typeof ResizeObserver === 'undefined') return;
    if (resizeObserver) resizeObserver.disconnect();
    resizeObserver = new ResizeObserver(measureContentHeight);
    resizeObserver.observe(dom);
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
      css +=
        '@font-face { font-family: "' +
        family +
        '"; src: url("' +
        regularURL +
        '") format("opentype"); font-weight: 400; font-style: normal; }';
    }
    if (mediumURL) {
      css +=
        '@font-face { font-family: "' +
        family +
        ' Medium"; src: url("' +
        mediumURL +
        '") format("opentype"); font-weight: 500; font-style: normal; }';
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
    document.documentElement.style.height = 'auto';
    document.body.style.background = 'transparent';
    document.body.style.height = 'auto';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.overflow = 'hidden';
    var editorHost = document.getElementById('editor');
    if (editorHost) {
      editorHost.style.minHeight = '0';
      editorHost.style.height = 'auto';
      editorHost.style.overflow = 'hidden';
    }
    applyTypography(config || {});
    measureContentHeight();
    setupResizeObserver();
  }

  function findTimerNodePos(args) {
    if (!editor) return null;
    const timerId = args && args.timerId ? String(args.timerId) : '';
    let found = null;
    editor.state.doc.descendants(function (node, pos) {
      if (found || node.type.name !== 'timer') return;
      const attrs = node.attrs;
      if (timerId && attrs['data-timer-id'] === timerId) {
        found = { node: node, pos: pos };
        return false;
      }
      if (!timerId) {
        const duration = args.duration != null ? String(args.duration) : '';
        const type = args.type != null ? String(args.type) : '';
        const value = args.value != null ? String(args.value) : '';
        const text = args.text != null ? String(args.text).trim() : '';
        const spanDuration = attrs['data-duration'] || '';
        const spanType = attrs['data-type'] || '';
        const spanValue = attrs['data-value'] || '';
        const spanText = node.textContent.trim();
        if (duration && spanDuration === duration && type && spanType === type) {
          if (text && spanText === text) {
            found = { node: node, pos: pos };
            return false;
          }
          if (value && spanValue === value) {
            found = { node: node, pos: pos };
            return false;
          }
          if (!text && !value) {
            found = { node: node, pos: pos };
            return false;
          }
        }
      }
    });
    return found;
  }

  function findIngredientNodePos(ingredientId) {
    if (!editor || !ingredientId) return null;
    let found = null;
    editor.state.doc.descendants(function (node, pos) {
      if (found || node.type.name !== 'ingredient') return;
      if (node.attrs['data-ingredient-id'] === ingredientId) {
        found = { node: node, pos: pos };
        return false;
      }
    });
    return found;
  }

  function markAsTimer(args) {
    const a = args || {};
    const selectedText = getSelectedText();
    editor
      .chain()
      .focus()
      .deleteSelection()
      .insertContent({
        type: 'timer',
        attrs: {
          'data-timer-id': a.timerId || 'timer-' + Date.now(),
          'data-duration': String(a.duration || 0),
          'data-type': a.type || 'minutes',
          'data-name': a.name || '',
          'data-value': String(a.value || 0),
        },
        content: selectedText ? [{ type: 'text', text: selectedText }] : undefined,
      })
      .run();
  }

  function markAsIngredient(args) {
    const a = args || {};
    const selectedText = getSelectedText();
    let amountToStore = a.originalAmount;
    if (amountToStore == null || amountToStore === '') {
      const parsed = parseFloat(selectedText);
      if (!isNaN(parsed)) amountToStore = parsed;
    }
    editor
      .chain()
      .focus()
      .deleteSelection()
      .insertContent({
        type: 'ingredient',
        attrs: {
          'data-ingredient-id': a.ingredientId || '',
          'data-original-amount':
            amountToStore != null && amountToStore !== ''
              ? String(amountToStore)
              : selectedText || null,
          'data-ratio': a.ratio != null && a.ratio !== '' ? String(a.ratio) : null,
        },
      })
      .run();
  }

  function removeTimerMarkup(args) {
    const hit = findTimerNodePos(args || {});
    if (!hit) return;
    const text = (args && args.text) || hit.node.textContent || hit.node.attrs['data-value'] || '';
    editor
      .chain()
      .focus()
      .insertContentAt({ from: hit.pos, to: hit.pos + hit.node.nodeSize }, text)
      .run();
  }

  function removeIngredientMarkup(args) {
    const ingredientId = args && args.ingredientId;
    const hit = findIngredientNodePos(ingredientId);
    if (!hit) return;
    const text =
      (args && args.displayText) ||
      hit.node.attrs['data-original-amount'] ||
      '';
    editor
      .chain()
      .focus()
      .insertContentAt({ from: hit.pos, to: hit.pos + hit.node.nodeSize }, text)
      .run();
  }

  function renameTimer(args) {
    const hit = findTimerNodePos(args || {});
    if (!hit || !args || !args.name) return;
    const attrs = Object.assign({}, hit.node.attrs);
    if (!attrs['data-timer-id']) {
      attrs['data-timer-id'] = 'timer-' + Date.now();
    }
    attrs['data-name'] = String(args.name);
    editor.view.dispatch(
      editor.state.tr.setNodeMarkup(hit.pos, undefined, attrs, hit.node.marks)
    );
  }

  function updateIngredientMarkup(args) {
    const hit = findIngredientNodePos(args && args.ingredientId);
    if (!hit || !args) return;
    const attrs = Object.assign({}, hit.node.attrs);
    if (args.ratio != null && args.ratio !== '') {
      attrs['data-ratio'] = String(args.ratio);
    }
    editor.view.dispatch(
      editor.state.tr.setNodeMarkup(hit.pos, undefined, attrs, hit.node.marks)
    );
    if (args.displayText != null && args.displayText !== '') {
      /* atom node — display comes from NodeView / attrs */
    }
    measureContentHeight();
  }

  function runCommand(name, args) {
    if (!editor) return;
    const a = args || {};
    switch (name) {
      case 'toggleBold':
        restoreSelection();
        editor.chain().focus().toggleBold().run();
        break;
      case 'toggleItalic':
        restoreSelection();
        editor.chain().focus().toggleItalic().run();
        break;
      case 'toggleHeading1':
        restoreSelection();
        editor.chain().focus().toggleHeading({ level: 1 }).run();
        break;
      case 'toggleHighlight':
        restoreSelection();
        editor.chain().focus().toggleHighlight().run();
        break;
      case 'toggleBulletList':
        restoreSelection();
        editor.chain().focus().toggleBulletList().run();
        break;
      case 'toggleOrderedList':
        restoreSelection();
        editor.chain().focus().toggleOrderedList().run();
        break;
      case 'markAsTimer':
        holdSelectionForMarkup = false;
        restoreSelection();
        markAsTimer(a);
        break;
      case 'markAsIngredient':
        holdSelectionForMarkup = false;
        restoreSelection();
        markAsIngredient(a);
        break;
      case 'removeTimerMarkup':
        removeTimerMarkup(a);
        postSelectionState();
        measureContentHeight();
        return;
      case 'removeIngredientMarkup':
        removeIngredientMarkup(a);
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
        restoreSelection();
        return;
      case 'releaseMarkupSelection':
        holdSelectionForMarkup = false;
        return;
      case 'focus':
        editor.commands.focus();
        post('focus');
        return;
      case 'focusEnd':
        editor.chain().focus().setTextSelection(editor.state.doc.content.size).run();
        measureContentHeightNow();
        post('focus');
        return;
      case 'focusMid': {
        var midSize = editor.state.doc.content.size;
        var midPos = Math.max(1, Math.floor(midSize / 2));
        editor.chain().focus().setTextSelection(midPos).run();
        measureContentHeightNow();
        post('focus');
        return;
      }
      case 'flush':
        flushOutboundUpdates();
        if (ydoc) {
          try {
            var fullState = Y.encodeStateAsUpdate(ydoc);
            if (fullState && fullState.length > 2) {
              post('syncState', { update: Array.from(fullState) });
            }
          } catch (_flushErr) {
            /* keep outboundFlushed */
          }
        }
        post('outboundFlushed');
        return;
      case 'blur':
        holdSelectionForMarkup = false;
        editor.commands.blur();
        notifyBlur();
        return;
      case 'getHTML':
        try {
          post('html', { html: editor.getHTML() });
        } catch (htmlErr) {
          post('html', { html: '' });
        }
        return;
      case 'simulateText': {
        const text = String(a.text || '');
        if (text) editor.chain().focus().insertContent(text).run();
        return;
      }
      default:
        break;
    }
    captureSelection();
    postSelectionState();
    measureContentHeight();
  }

  function notifyBlur() {
    captureSelection();
    post('blur');
  }

  function readTimerNodePayload(span) {
    return {
      nodeType: 'timer',
      timerId: span.getAttribute('data-timer-id') || '',
      duration: span.getAttribute('data-duration') || '',
      timerType: span.getAttribute('data-type') || '',
      type: span.getAttribute('data-type') || '',
      value: span.getAttribute('data-value') || '',
      name: span.getAttribute('data-name') || '',
      text: span.textContent || '',
    };
  }

  function postNodeClick(span, payload) {
    notifyBlur();
    var rect = span.getBoundingClientRect();
    post(
      'nodeClick',
      Object.assign(
        {
          anchorX: rect.left,
          anchorY: rect.top,
          anchorWidth: rect.width,
          anchorHeight: rect.height,
        },
        payload || {}
      )
    );
  }

  function handleReferenceNodeTap(e, fromClick) {
    var timerSpan = e.target.closest && e.target.closest('.timer-reference');
    var ingredientSpan = e.target.closest && e.target.closest('.ingredient-reference');
    if (!timerSpan && !ingredientSpan) return false;

    e.preventDefault();
    e.stopPropagation();

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
        text: ingredientSpan.textContent || '',
      });
      return true;
    }
    return false;
  }

  function wireDomHandlers() {
    const dom = editorDom();
    if (!dom) return;
    dom.addEventListener(
      'pointerup',
      function (e) {
        handleReferenceNodeTap(e, false);
      },
      true
    );
    dom.addEventListener(
      'click',
      function (e) {
        handleReferenceNodeTap(e, true);
      },
      true
    );
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
        try {
          const state = new Uint8Array(msg.state || []);
          destroyEditor();
          ydoc = new Y.Doc();
          ydoc.on('update', function (update, origin) {
            if (origin === 'remote') return;
            if (!ready || applyingRemote) return;
            scheduleOutboundUpdate(update);
          });
          if (state.length) {
            Y.applyUpdate(ydoc, state, 'remote');
          }
          const fragment = ydoc.getXmlFragment('description');
          createEditor(fragment);
          ready = true;
          wireDomHandlers();
          setupResizeObserver();
          const plainLen = editor ? editor.state.doc.textContent.length : 0;
          post('ready', {
            fragmentLength: fragment.length,
            editorPlainLen: plainLen,
          });
          measureContentHeightNow();
          postSelectionStateNow();
          applyPendingScale();
        } catch (err) {
          ready = true;
          post('ready', {
            fragmentLength: 0,
            editorPlainLen: 0,
            initError: String(err && err.message ? err.message : err),
          });
        }
        break;
      }
      case 'applyUpdate': {
        if (!ydoc) return;
        applyingRemote = true;
        try {
          Y.applyUpdate(ydoc, new Uint8Array(msg.update || []), 'remote');
          measureContentHeight();
        } finally {
          applyingRemote = false;
        }
        break;
      }
      case 'setScale':
        pendingScale = {
          scaleFactor: msg.scaleFactor != null ? Number(msg.scaleFactor) : 1,
          ingredients: msg.ingredients || [],
          locale: msg.locale || 'en',
        };
        applyPendingScale();
        break;
      case 'command':
        runCommand(msg.name, msg.args);
        break;
      case 'simulateText': {
        if (!ready || !editor) return;
        const text = String(msg.text || '');
        if (!text) return;
        editor.chain().focus().insertContent(text).run();
        break;
      }
      default:
        break;
    }
  }

  window.__descriptionEditorReceive = handleNativeMessage;
  window.__descriptionEditorGetCaretRect = getCaretRectInEditor;

  post('loaded');

  if (typeof globalThis !== 'undefined' && globalThis.__DESCRIPTION_EDITOR_TEST__) {
    globalThis.__descriptionEditorTest = {
      Y: Y,
      Editor: Editor,
      buildExtensions: buildExtensions,
      initDoc: function (update) {
        ydoc = new Y.Doc();
        if (update && update.length) Y.applyUpdate(ydoc, update, 'remote');
        const fragment = ydoc.getXmlFragment('description');
        createEditor(fragment);
        ready = true;
        return { ydoc: ydoc, fragment: fragment, editor: editor };
      },
      getEditor: function () {
        return editor;
      },
      getDoc: function () {
        return ydoc;
      },
      encodeUpdate: function (sv) {
        return Y.encodeStateAsUpdate(ydoc, sv);
      },
      stateVector: function () {
        return Y.encodeStateVector(ydoc);
      },
    };
  }
})();

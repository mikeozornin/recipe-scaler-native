/* global YjsBundle */
(function () {
  'use strict';

  const Y = YjsBundle;
  const DEBOUNCE_MS = 400;
  const handlerName = 'descriptionEditor';

  let ydoc = null;
  let fragment = null;
  let applyingRemote = false;
  let pushTimer = null;
  let ready = false;

  const editorEl = document.getElementById('editor');
  const statusEl = document.getElementById('status');

  function post(type, payload) {
    const msg = Object.assign({ type: type }, payload || {});
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handlerName]) {
      window.webkit.messageHandlers[handlerName].postMessage(msg);
    }
  }

  function setStatus(text) {
    if (statusEl) statusEl.textContent = text;
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
        para.insert(0, [collectInlineNodes(li)]);
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
    para.insert(0, [collectInlineNodes(el)]);
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
    pushTimer = setTimeout(pushLocalEdit, DEBOUNCE_MS);
  }

  function pushLocalEdit() {
    if (!ydoc || !fragment) return;
    const html = editorEl.innerHTML;
    ydoc.transact(() => {
      htmlToFragment(html);
    });
  }

  function handleNativeMessage(msg) {
    if (!msg || !msg.type) return;
    switch (msg.type) {
      case 'init': {
        const state = new Uint8Array(msg.state || []);
        ydoc = new Y.Doc();
        ydoc.on('update', (update, origin) => {
          if (!ready || applyingRemote || origin === 'remote') return;
          post('update', { update: Array.from(update) });
        });
        if (state.length) {
          Y.applyUpdate(ydoc, state, 'remote');
        }
        fragment = ydoc.getXmlFragment('description');
        editorEl.innerHTML = fragmentToHtml();
        ready = true;
        setStatus('Ready');
        post('ready', { fragmentLength: fragment.length });
        break;
      }
      case 'applyUpdate': {
        if (!ydoc) return;
        applyingRemote = true;
        try {
          Y.applyUpdate(ydoc, new Uint8Array(msg.update || []), 'remote');
          if (fragment) editorEl.innerHTML = fragmentToHtml();
        } finally {
          applyingRemote = false;
        }
        break;
      }
      case 'command': {
        if (!editorEl) return;
        document.execCommand(msg.name, false, msg.value || null);
        schedulePush();
        break;
      }
      default:
        break;
    }
  }

  window.__descriptionEditorReceive = handleNativeMessage;

  editorEl.addEventListener('input', schedulePush);

  document.getElementById('toolbar').addEventListener('click', (event) => {
    const btn = event.target.closest('button[data-cmd]');
    if (!btn) return;
    const cmd = btn.getAttribute('data-cmd');
    editorEl.focus();
    if (cmd === 'bold') document.execCommand('bold');
    else if (cmd === 'italic') document.execCommand('italic');
    else if (cmd === 'h1') document.execCommand('formatBlock', false, 'h1');
    else if (cmd === 'bullet') document.execCommand('insertUnorderedList');
    schedulePush();
  });

  post('loaded');
})();
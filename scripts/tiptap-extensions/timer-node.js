import { Node, mergeAttributes } from '@tiptap/core';

/** Vanilla port of web timer-node.tsx — schema must match y.XmlFragment wire format. */
export const TimerNode = Node.create({
  name: 'timer',
  group: 'inline',
  inline: true,
  atom: false,
  content: 'text*',

  addAttributes() {
    return {
      'data-timer-id': { default: null, parseHTML: (el) => el.getAttribute('data-timer-id') },
      'data-duration': { default: null, parseHTML: (el) => el.getAttribute('data-duration') },
      'data-type': { default: null, parseHTML: (el) => el.getAttribute('data-type') },
      'data-name': { default: null, parseHTML: (el) => el.getAttribute('data-name') },
      'data-value': { default: null, parseHTML: (el) => el.getAttribute('data-value') },
    };
  },

  parseHTML() {
    return [{ tag: 'span.timer-reference' }];
  },

  renderHTML({ HTMLAttributes, node }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, { class: 'timer-reference', contenteditable: 'false' }),
      node.textContent || '',
    ];
  },

  addCommands() {
    return {
      setTimer:
        (attributes) =>
        ({ commands }) =>
          commands.insertContent({
            type: this.name,
            attrs: {
              'data-timer-id': attributes.timerId,
              'data-duration': String(attributes.duration),
              'data-type': attributes.type,
              'data-name': attributes.name || '',
              'data-value': String(attributes.value),
            },
            content: attributes.text ? [{ type: 'text', text: attributes.text }] : undefined,
          }),
    };
  },
});

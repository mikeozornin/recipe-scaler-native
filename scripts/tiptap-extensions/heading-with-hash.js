import { Heading } from '@tiptap/extension-heading';
import { textblockTypeInputRule } from '@tiptap/core';

/** Web heading-with-hash.tsx — `# ` at line start → h1. */
export const HeadingWithHash = Heading.extend({
  addInputRules() {
    return [
      textblockTypeInputRule({
        find: /^#\s/,
        type: this.type,
        getAttributes: () => ({ level: 1 }),
      }),
    ];
  },
});

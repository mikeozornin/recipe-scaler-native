import { Node, mergeAttributes } from '@tiptap/core';

function formatAmount(value, locale) {
  const n = typeof value === 'number' ? value : parseFloat(String(value).replace(',', '.'));
  if (isNaN(n)) return String(value ?? '');
  const rounded = Math.round(n * 100) / 100;
  if (Number.isInteger(rounded)) return String(rounded);
  return rounded.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

function scaledDisplay(node, storage) {
  const ingredientId = node.attrs['data-ingredient-id'];
  const originalAmountStr = node.attrs['data-original-amount'];
  const ratioStr = node.attrs['data-ratio'];
  let displayValue = originalAmountStr || '';

  if (!ingredientId || !storage) return displayValue;

  const ingredients = storage.ingredients || [];
  const ingredient = ingredients.find((ing) => ing.id === ingredientId);
  const fromModel = ingredient?.originalAmount;
  const parsedModel =
    fromModel != null && fromModel !== '' ? parseFloat(String(fromModel).replace(',', '.')) : null;
  const parsedAttr = originalAmountStr ? parseFloat(String(originalAmountStr).replace(',', '.')) : null;
  const originalAmount = parsedModel != null && !isNaN(parsedModel) ? parsedModel : parsedAttr;

  if (originalAmount == null || isNaN(originalAmount)) return displayValue;

  const ratio = ratioStr ? parseFloat(String(ratioStr).replace(',', '.')) : 1;
  const scaleFactor = storage.scaleFactor != null ? storage.scaleFactor : 1;
  if (scaleFactor !== 1 || ratio !== 1) {
    displayValue = formatAmount(originalAmount * scaleFactor * ratio, storage.locale);
  }
  return displayValue;
}

/** Vanilla port of web ingredient-node.tsx + ingredient-component.tsx NodeView. */
export const IngredientNode = Node.create({
  name: 'ingredient',
  group: 'inline',
  inline: true,
  atom: true,

  addAttributes() {
    return {
      'data-ingredient-id': { default: null, parseHTML: (el) => el.getAttribute('data-ingredient-id') },
      'data-original-amount': {
        default: null,
        parseHTML: (el) => {
          const attr = el.getAttribute('data-original-amount');
          if (attr) return attr;
          const text = el.textContent;
          if (text && !isNaN(parseFloat(text))) return text;
          return null;
        },
      },
      'data-ratio': { default: null, parseHTML: (el) => el.getAttribute('data-ratio') },
    };
  },

  parseHTML() {
    return [{ tag: 'span.ingredient-reference' }];
  },

  renderHTML({ HTMLAttributes, node }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, {
        class: 'ingredient-reference edit-mode',
        contenteditable: 'false',
      }),
      node.attrs['data-original-amount'] || '',
    ];
  },

  addCommands() {
    return {
      setIngredient:
        (attributes) =>
        ({ commands }) =>
          commands.insertContent({
            type: this.name,
            attrs: {
              'data-ingredient-id': attributes.ingredientId,
              'data-original-amount': attributes.originalAmount?.toString() || null,
              'data-ratio': attributes.ratio?.toString() || null,
            },
          }),
    };
  },

  addNodeView() {
    return ({ node, editor }) => {
      const dom = document.createElement('span');
      dom.className = 'ingredient-reference edit-mode';
      dom.contentEditable = 'false';

      let currentNode = node;

      function refresh() {
        const attrs = currentNode.attrs;
        const id = attrs['data-ingredient-id'];
        const original = attrs['data-original-amount'];
        const ratio = attrs['data-ratio'];
        if (id) dom.setAttribute('data-ingredient-id', id);
        else dom.removeAttribute('data-ingredient-id');
        if (original != null) dom.setAttribute('data-original-amount', String(original));
        else dom.removeAttribute('data-original-amount');
        if (ratio != null) dom.setAttribute('data-ratio', String(ratio));
        else dom.removeAttribute('data-ratio');
        dom.textContent = scaledDisplay(currentNode, editor.storage.scaleStorage);
      }

      refresh();

      const onTransaction = ({ transaction }) => {
        if (transaction.getMeta('scaleUpdate') !== undefined) refresh();
      };
      editor.on('transaction', onTransaction);

      return {
        dom,
        update(updatedNode) {
          if (updatedNode.type.name !== 'ingredient') return false;
          currentNode = updatedNode;
          refresh();
          return true;
        },
        destroy() {
          editor.off('transaction', onTransaction);
        },
        ignoreMutation: () => true,
      };
    };
  },
});

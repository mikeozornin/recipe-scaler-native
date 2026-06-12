import { Extension } from '@tiptap/core';

/** Mutable storage for live ingredient scaling (web scale-storage.ts). */
export const ScaleStorageExtension = Extension.create({
  name: 'scaleStorage',

  addStorage() {
    return {
      scaleFactor: 1,
      ingredients: [],
      locale: 'en',
    };
  },
});

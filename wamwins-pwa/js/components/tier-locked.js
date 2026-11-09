import { h, icon } from '../core/dom.js';
import { canUse } from '../tier/capabilities.js';
import { infoButton } from './info.js';

/**
 * TierLockedFeature: shows a higher-tier capability where it is contextually useful, visibly locked in Basic.
 * Decided ONLY through the capability service (never "which tier?"). It never imports or initializes the
 * feature's module: in Basic nothing heavy is loaded (low-RAM rule). Locked state is shown with an icon and text,
 * not color alone.
 */
export async function tierLockedFeatures(householdId, features, { heading = 'More ways to add this (not in WAMWins Basic)' } = {}) {
  const states = await Promise.all(features.map(f => householdId ? canUse(householdId, f.capability) : false));
  const locked = features.filter((_, i) => !states[i]);
  if (!locked.length) return null;
  return h('section', { class: 'locked-features', 'aria-label': heading },
    h('p', { class: 'locked-head' }, icon('lock', 16), h('span', { text: heading })),
    h('div', { class: 'locked-grid' }, locked.map(f => h('div', { class: 'locked-card', 'aria-disabled': 'true', 'data-capability': f.capability },
      h('span', { class: 'locked-ico' }, icon(f.icon ?? 'camera', 18)),
      h('span', { class: 'locked-title', text: f.title }),
      h('span', { class: 'locked-state' }, icon('lock', 14), h('span', { text: 'Higher tier' })),
      infoButton({ label: f.title, title: f.title, body: [f.text, 'This works automatically in a higher WAMWins tier. In WAMWins Basic you add the same details by hand, and they are stored in exactly the same place.'] })))));
}

// Where they appear (capabilities already exist in the 7-tier engine; Basic has them disabled).
export const STORAGE_LOCKED = [
  { capability: 'AUTOMATIC_KITCHEN_MAPPING', title: 'Scan Kitchen', icon: 'camera', text: 'Walk through your kitchen with the camera and let WAMWins map it.' },
  { capability: 'IMAGE_RECOGNITION', title: 'Recognize Storage From Photo', icon: 'image', text: 'Take a photo of a refrigerator or cabinet and WAMWins suggests its shelves and sections.' },
  { capability: 'VIDEO_RECOGNITION', title: 'Recognize Storage From Video', icon: 'camera', text: 'Record a short video of a storage area and WAMWins suggests its structure.' },
  { capability: 'AUTOMATIC_KITCHEN_MAPPING', title: 'Automatic Kitchen Mapping', icon: 'box', text: 'WAMWins builds your kitchens, storage areas and sections automatically.' },
  { capability: 'IMAGE_RECOGNITION', title: 'Automatic Item Detection', icon: 'search', text: 'WAMWins recognizes the items it sees in a storage area.' },
];
export const FOOD_LOCKED = [
  { capability: 'IMAGE_RECOGNITION', title: 'Scan Food With Camera', icon: 'camera', text: 'Point the camera at food and WAMWins fills in what it is.' },
  { capability: 'IMAGE_RECOGNITION', title: 'Image Recognition', icon: 'image', text: 'Recognize foods from a photo.' },
  { capability: 'BARCODE_SCANNING', title: 'Barcode Scan', icon: 'search', text: 'Scan a product barcode to add it with its brand and size.' },
  { capability: 'RECEIPT_SCANNING', title: 'Receipt Scan', icon: 'download', text: 'Photograph a grocery receipt to add everything on it.' },
  { capability: 'OCR_CAPTURE', title: 'OCR Import', icon: 'edit', text: 'Read printed lists and labels into your inventory.' },
  { capability: 'EXTERNAL_INTEGRATIONS', title: 'Store Purchase Import', icon: 'basket', text: 'Import purchases from a store account.' },
  { capability: 'EXTERNAL_INTEGRATIONS', title: 'Store API Sync', icon: 'share', text: 'Keep inventory in step with a store or delivery service.' },
  { capability: 'AUTOMATION', title: 'Automated Inventory Capture', icon: 'box', text: 'Inventory updates itself as food comes and goes.' },
];

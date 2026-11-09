import { h, icon, clear, toast, field } from '../core/dom.js';
import { tx } from '../data/db.js';
import { openInfo, infoButton } from './info.js';

/**
 * Manual reference photos (ACTIVE in WAMWins Basic): take or choose a photo of a kitchen, storage unit, section,
 * shelf, drawer or container, add a label and description, view, download/save and share it.
 * WAMWins Basic NEVER interprets the image - no recognition code is loaded or called here.
 * Metadata goes to location_media; the image bytes to media_blob (kept out of large rows). While onboarding, a
 * photo is linked by its location's draft key; the real ids are filled in when the entries are saved.
 */
const THUMB = 320, MAX = 1600;
async function shrink(file, max, quality = 0.85) {
  try {
    const bmp = await createImageBitmap(file);
    const k = Math.min(1, max / Math.max(bmp.width, bmp.height));
    const c = Object.assign(document.createElement('canvas'), { width: Math.round(bmp.width * k), height: Math.round(bmp.height * k) });
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
    return await new Promise(r => c.toBlob(b => r(b ?? file), 'image/jpeg', quality));
  } catch { return file; }                                                      // unsupported format: keep the original
}
const blobOf = (ref) => tx(['media_blob'], 'readonly', t => t.get('media_blob', ref.replace('idb:media_blob/', ''))).then(r => r?.blob);

export async function photosFor(hh, locationKey) {
  if (!hh) return [];
  return (await tx(['location_media'], 'readonly', t => t.byIndex('location_media', 'household_id', hh)))
    .filter(m => m.location_draft_key === locationKey && m.active && !m.archived_at).sort((a, b) => a.created_at.localeCompare(b.created_at));
}

export function referencePhotos({ hh, userId, locationKey, locationName, onChange }) {
  const grid = h('div', { class: 'photo-grid' });
  const form = h('div');
  const urls = [];
  const pickFile = h('input', { type: 'file', accept: 'image/*', hidden: true, 'aria-hidden': 'true' });
  const takePhoto = h('input', { type: 'file', accept: 'image/*', capture: 'environment', hidden: true, 'aria-hidden': 'true' });
  async function draw() {
    clear(grid);
    for (const m of await photosFor(hh, locationKey)) {
      const blob = await blobOf(m.thumbnail_ref ?? m.blob_ref);
      const url = blob ? URL.createObjectURL(blob) : ''; if (url) urls.push(url);
      grid.append(h('button', { type: 'button', class: 'photo-thumb', 'aria-label': `View photo: ${m.title || locationName}`, onclick: () => view(m) },
        url ? h('img', { src: url, alt: m.title || `Reference photo of ${locationName}` }) : icon('image'), h('span', { text: m.title || 'Photo' })));
    }
  }
  async function view(m) {
    const blob = await blobOf(m.blob_ref); if (!blob) return toast('This photo is no longer available.');
    const url = URL.createObjectURL(blob); urls.push(url);
    const name = `${(m.title || locationName || 'reference').replace(/[^\w -]+/g, '').trim() || 'reference'}.jpg`;
    const file = new File([blob], name, { type: blob.type || 'image/jpeg' });
    const close = openInfo({ title: m.title || `Photo of ${locationName}`, body: m.caption || 'Reference photo' });
    const body = document.querySelector('.info-modal:last-of-type .info-body');
    const share = h('button', { type: 'button', class: 'btn btn-ghost' }, icon('share', 18), h('span', { text: 'Share' }));
    share.onclick = async () => {
      try {
        if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: m.title || locationName, text: m.caption || '' });
        else { await navigator.clipboard?.writeText?.(`${m.title || locationName}${m.caption ? ` - ${m.caption}` : ''}`); toast('Sharing files isn’t supported in this browser. Use Download instead.'); }
      } catch { /* cancelled by the user */ }
    };
    const archive = h('button', { type: 'button', class: 'btn-text', text: 'Remove photo' });
    archive.onclick = async () => {
      await tx(['location_media', 'local_mutation_outbox'], 'readwrite', async t => t.update('location_media', { ...(await t.get('location_media', m.id)), active: false, archived_at: new Date().toISOString() }));
      close(); toast('Photo removed.'); draw(); onChange?.();
    };
    body.prepend(h('img', { class: 'photo-full', src: url, alt: m.title || `Reference photo of ${locationName}` }));
    body.append(h('div', { class: 'row' }, h('a', { class: 'btn btn-ghost', href: url, download: name }, icon('download', 18), h('span', { text: 'Download' })), share, archive));
  }
  async function stage(file) {
    if (!file) return;
    if (!hh) return toast('Save “About You” first, then add photos.');
    clear(form);
    const title = h('input', { class: 'input', id: `ph-title-${locationKey}`, maxlength: '80', placeholder: `e.g. ${locationName}` });
    const caption = h('input', { class: 'input', id: `ph-cap-${locationKey}`, maxlength: '240', placeholder: 'What should this photo remind you of?' });
    const save = h('button', { type: 'button', class: 'btn btn-primary', text: 'Save photo' });
    const preview = URL.createObjectURL(file); urls.push(preview);
    save.onclick = async () => {
      save.disabled = true;
      const [full, thumb] = await Promise.all([shrink(file, MAX), shrink(file, THUMB, 0.7)]);
      const id = crypto.randomUUID(), blobId = crypto.randomUUID(), thumbId = crypto.randomUUID();
      await tx(['location_media', 'media_blob', 'local_mutation_outbox'], 'readwrite', async t => {
        await t.put('media_blob', { id: blobId, household_id: hh, mime_type: full.type || 'image/jpeg', blob: full, created_at: new Date().toISOString() });
        await t.put('media_blob', { id: thumbId, household_id: hh, mime_type: 'image/jpeg', blob: thumb, created_at: new Date().toISOString() });
        await t.insert('location_media', { id, household_id: hh, kitchen_id: null, storage_instance_id: null, storage_section_id: null, container_id: null, inventory_item_id: null,
          location_draft_key: locationKey, media_type: 'IMAGE', blob_ref: `idb:media_blob/${blobId}`, thumbnail_ref: `idb:media_blob/${thumbId}`, mime_type: full.type || 'image/jpeg',
          byte_size: full.size, title: title.value.trim() || null, caption: caption.value.trim() || null, uploaded_by_user_id: userId, source_type: 'MANUAL', active: true, archived_at: null });
      });
      clear(form); toast('Reference photo saved.'); await draw(); onChange?.();
    };
    form.append(h('div', { class: 'photo-stage' }, h('img', { src: preview, alt: 'Selected photo preview' }),
      h('div', { class: 'stack-s' }, field({ label: 'Label', input: title }), field({ label: 'Description (optional)', input: caption }),
        h('div', { class: 'row' }, save, h('button', { type: 'button', class: 'btn-text', text: 'Cancel', onclick: () => clear(form) })))));
    title.focus();
  }
  pickFile.onchange = () => { stage(pickFile.files?.[0]); pickFile.value = ''; };
  takePhoto.onchange = () => { stage(takePhoto.files?.[0]); takePhoto.value = ''; };
  draw();
  const el = h('div', { class: 'ref-photos' },
    h('div', { class: 'row' },
      h('button', { type: 'button', class: 'btn btn-ghost btn-sm', onclick: () => pickFile.click() }, icon('image', 18), h('span', { text: 'Add Reference Photo' })),
      h('button', { type: 'button', class: 'btn-text', onclick: () => takePhoto.click() }, h('span', { text: 'Take photo' })),
      infoButton({ label: 'Reference photos', title: 'Reference photos', body: ['Keep a picture of where things are, like the inside of a cabinet or a labeled bin. Only your household can see it.',
        'WAMWins Basic does not read or analyze photos; they are for you to look at, download and share.'] })),
    pickFile, takePhoto, form, grid);
  return { el, dispose: () => urls.forEach(u => URL.revokeObjectURL(u)) };
}

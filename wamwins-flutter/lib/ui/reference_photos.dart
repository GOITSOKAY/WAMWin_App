import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../media/media_store.dart';
import 'info.dart';
import 'widgets.dart';

/// "Add Reference Photo": take or choose a photo of a kitchen, storage unit, section, shelf, drawer or container, add a
/// label and description, then view, save (download) and share it. Manual only - WAMWins Basic never analyzes the image.
class ReferencePhotos extends StatefulWidget {
  const ReferencePhotos({super.key, required this.householdId, required this.userId, required this.locationKey, required this.locationName, this.onChange});
  final String householdId, userId, locationKey, locationName;
  final VoidCallback? onChange;
  @override
  State<ReferencePhotos> createState() => _ReferencePhotosState();
}

class _ReferencePhotosState extends State<ReferencePhotos> {
  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final title = TextEditingController(), caption = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Save reference photo'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, height: 160, fit: BoxFit.cover, semanticLabel: 'Selected photo preview')),
        const SizedBox(height: 12),
        TextField(controller: title, maxLength: 80, decoration: wamField(ctx).copyWith(labelText: 'Label', hintText: 'e.g. ${widget.locationName}')),
        TextField(controller: caption, maxLength: 240, decoration: wamField(ctx).copyWith(labelText: 'Description (optional)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save photo'))],
    ));
    if (ok == true && mounted) {
      await MediaStore(AppScope.of(context).db).add(householdId: widget.householdId, userId: widget.userId, locationKey: widget.locationKey, bytes: bytes,
          mime: file.mimeType ?? 'image/jpeg', title: title.text.trim().isEmpty ? null : title.text.trim(), caption: caption.text.trim().isEmpty ? null : caption.text.trim());
      if (!mounted) return;
      AppScope.of(context).toast('Reference photo saved.');
      setState(() {});
      widget.onChange?.call();
    }
    title.dispose(); caption.dispose();
  }

  Future<File> _file(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/${name.replaceAll(RegExp(r'[^\w -]+'), '').trim().isEmpty ? 'reference' : name.replaceAll(RegExp(r'[^\w -]+'), '').trim()}.jpg');
    return f.writeAsBytes(bytes, flush: true);
  }

  Future<void> _view(DbRowLike m, MediaStore store) async {
    final bytes = store.bytes(m['blob_ref'] as String);
    if (bytes == null) return;
    final name = (m['title'] as String?) ?? widget.locationName;
    await showInfo(context, title: name, body: [if (m['caption'] != null) m['caption'] as String], extra: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, semanticLabel: 'Reference photo of ${widget.locationName}')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.download_outlined), label: const Text('Save to device'), onPressed: () async {
          final f = await _file(bytes, name);
          if (mounted) AppScope.of(context).toast('Saved: ${f.path.split('/').last}');
        }),
        OutlinedButton.icon(icon: const Icon(Icons.share_outlined), label: const Text('Share'), onPressed: () async {
          final f = await _file(bytes, name);
          await Share.shareXFiles([XFile(f.path, mimeType: m['mime_type'] as String?)], text: name);
        }),
        TextButton(onPressed: () { store.archive(m['id'] as String); Navigator.of(context).pop(); setState(() {}); widget.onChange?.call(); }, child: const Text('Remove photo')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = MediaStore(AppScope.of(context).db);
    final photos = store.forLocation(widget.householdId, widget.locationKey);
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add Reference Photo'), onPressed: () => _pick(ImageSource.gallery)),
        TextButton.icon(icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo'), onPressed: () => _pick(ImageSource.camera)),
        const InfoButton(label: 'Reference photos', title: 'Reference photos', body: ['Keep a picture of where things are, like the inside of a cabinet or a labeled bin. Only your household can see it.',
          'WAMWins Basic does not read or analyze photos; they are for you to look at, save and share.']),
      ]),
      if (photos.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (final m in photos) InkWell(
        onTap: () => _view(m, store),
        child: Semantics(button: true, label: 'View photo: ${m['title'] ?? widget.locationName}', excludeSemantics: true, child: Container(
          width: 96, padding: const EdgeInsets.all(4), decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(store.bytes((m['thumbnail_ref'] ?? m['blob_ref']) as String) ?? Uint8List(0), height: 72, width: 88, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))),
            Text((m['title'] as String?) ?? 'Photo', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ]),
        )),
      )]),
    ]);
  }
}

typedef DbRowLike = Map<String, Object?>;

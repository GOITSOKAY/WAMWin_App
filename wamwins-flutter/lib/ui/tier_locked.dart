import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import 'info.dart';

/// Higher-tier capabilities shown where useful, visibly locked in WAMWins Basic. Decided ONLY by the capability service
/// (never "which tier?"); the feature's code is never imported or started here (low-RAM rule). Locked state uses an
/// icon and text, not color alone.
class LockedFeature {
  const LockedFeature(this.capability, this.title, this.icon, this.text);
  final String capability, title, text;
  final IconData icon;
}
const storageLocked = [
  LockedFeature('AUTOMATIC_KITCHEN_MAPPING', 'Scan Kitchen', Icons.photo_camera_outlined, 'Walk through your kitchen with the camera and let WAMWins map it.'),
  LockedFeature('IMAGE_RECOGNITION', 'Recognize Storage From Photo', Icons.image_outlined, 'Take a photo of a refrigerator or cabinet and WAMWins suggests its shelves and sections.'),
  LockedFeature('VIDEO_RECOGNITION', 'Recognize Storage From Video', Icons.videocam_outlined, 'Record a short video of a storage area and WAMWins suggests its structure.'),
  LockedFeature('AUTOMATIC_KITCHEN_MAPPING', 'Automatic Kitchen Mapping', Icons.account_tree_outlined, 'WAMWins builds your kitchens, storage areas and sections automatically.'),
  LockedFeature('IMAGE_RECOGNITION', 'Automatic Item Detection', Icons.search, 'WAMWins recognizes the items it sees in a storage area.'),
];
const foodLocked = [
  LockedFeature('IMAGE_RECOGNITION', 'Scan Food With Camera', Icons.photo_camera_outlined, 'Point the camera at food and WAMWins fills in what it is.'),
  LockedFeature('IMAGE_RECOGNITION', 'Image Recognition', Icons.image_outlined, 'Recognize foods from a photo.'),
  LockedFeature('BARCODE_SCANNING', 'Barcode Scan', Icons.qr_code_scanner, 'Scan a product barcode to add it with its brand and size.'),
  LockedFeature('RECEIPT_SCANNING', 'Receipt Scan', Icons.receipt_long_outlined, 'Photograph a grocery receipt to add everything on it.'),
  LockedFeature('OCR_CAPTURE', 'OCR Import', Icons.document_scanner_outlined, 'Read printed lists and labels into your inventory.'),
  LockedFeature('EXTERNAL_INTEGRATIONS', 'Store Purchase Import', Icons.shopping_basket_outlined, 'Import purchases from a store account.'),
  LockedFeature('EXTERNAL_INTEGRATIONS', 'Store API Sync', Icons.sync, 'Keep inventory in step with a store or delivery service.'),
  LockedFeature('AUTOMATION', 'Automated Inventory Capture', Icons.auto_mode, 'Inventory updates itself as food comes and goes.'),
];

class TierLockedFeatures extends StatelessWidget {
  const TierLockedFeatures({super.key, required this.householdId, required this.features});
  final String? householdId;
  final List<LockedFeature> features;
  @override
  Widget build(BuildContext context) {
    final caps = AppScope.of(context).capabilities;
    final locked = features.where((f) => householdId == null || !caps.canUse(householdId!, f.capability)).toList();
    if (locked.isEmpty) return const SizedBox.shrink();
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3B1416) : Brand.redSoft,
          border: Border.all(color: Brand.redFor(context), width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(Icons.lock_outline, size: 16, color: Brand.redFor(context)), const SizedBox(width: 6),
          Expanded(child: Text('More ways to add this (not in WAMWins Basic)', style: TextStyle(color: Brand.redFor(context), fontWeight: FontWeight.w500)))]),
        const SizedBox(height: 8),
        for (final f in locked) Semantics(enabled: false, label: '${f.title}, higher tier, locked', child: Container(
          margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(f.icon, size: 20, color: p.text2), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, style: TextStyle(color: p.text2, fontWeight: FontWeight.w500)),
              Row(children: [Icon(Icons.lock_outline, size: 12, color: Brand.redFor(context)), const SizedBox(width: 4), Text('Higher tier', style: TextStyle(color: Brand.redFor(context), fontSize: 12, fontWeight: FontWeight.w500))]),
            ])),
            InfoButton(label: f.title, title: f.title, body: [f.text, 'This works automatically in a higher WAMWins tier. In WAMWins Basic you add the same details by hand, and they are stored in exactly the same place.']),
          ]),
        )),
      ]),
    );
  }
}

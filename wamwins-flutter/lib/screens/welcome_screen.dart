import 'package:flutter/material.dart';

import '../app/scope.dart';
import '../app/theme.dart';
import '../ui/brand.dart';
import '../ui/widgets.dart';
import 'auth_layout.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final centered = MediaQuery.sizeOf(context).width < 1024;           // phone + tablet: centred title (brand request)
    final align = centered ? TextAlign.center : TextAlign.start;
    Widget point(IconData icon, bool yellow, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: yellow ? Brand.yellow50 : p.tagBlueBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 22, color: yellow ? const Color(0xFF8A6400) : p.link)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ])),
          ]),
        );
    return AuthLayout(children: [
      Semantics(header: true, child: tmTitle(context, 'Welcome to WAMWins', align: align)),
      const SizedBox(height: 12),
      Text('Tell us about your household, kitchens and family once. WAMWins uses your answers to suggest meals that are safe for everyone and use what you already have.',
          textAlign: align, style: TextStyle(color: p.text2)),
      const SizedBox(height: 20),
      point(Icons.groups_outlined, false, 'Built around your family', 'Allergies and diets are checked before anything is suggested.'),
      point(Icons.inventory_2_outlined, true, 'Only what you really have', 'Your kitchens, storage and tools, set up exactly as they are at home.'),
      point(Icons.wifi_off_rounded, false, 'Works without internet', 'Everything is saved on this device and stays available offline.'),
      const SizedBox(height: 8),
      PrimaryButton(label: 'Create account', onPressed: () => s.router.go('register')),
      const SizedBox(height: 10),
      GhostButton(onPressed: () => s.router.go('login'), child: const Text('Log in')),
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.verified_user_outlined, size: 18, color: p.ok),
        const SizedBox(width: 10),
        Expanded(child: Text('Your household’s information is private. Only people you invite can see it, and your password is never stored in readable form.',
            style: Theme.of(context).textTheme.bodySmall)),
      ]),
    ]);
  }
}

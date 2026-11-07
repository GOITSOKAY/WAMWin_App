import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/scope.dart';
import 'core/db.dart';
import 'security/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  try {
    final db = await AppDb.open();
    runApp(WamWinsApp(services: AppServices(db: db, secure: DeviceSecureStore())));
  } catch (e) {
    runApp(StartupErrorApp(message: e.toString()));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/recipes/image_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ImageStore.init();
  runApp(const ProviderScope(child: MealPlannerApp()));
}


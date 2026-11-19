import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/app/app.dart';
import 'package:meal_planner/app/providers.dart';

void main() {
  testWidgets('shows five bottom navigation tabs', (tester) async {
    // The shell is tested without a real database (Drift I/O does not run in
    // the widget-test fake-async zone); data providers are stubbed empty.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => Stream.value(<String, String>{})),
        recipesProvider.overrideWith((ref) => Stream.value([])),
        categoriesProvider.overrideWith((ref) => Stream.value([])),
        ingredientsProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: const MealPlannerApp(),
    ));
    await tester.pump();
    for (final label in ['Recipes', 'Planner', 'Calendar', 'Calories', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}


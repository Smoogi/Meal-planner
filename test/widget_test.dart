import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_planner/app/app.dart';

void main() {
  testWidgets('shows five bottom navigation tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MealPlannerApp()));
    await tester.pumpAndSettle();
    for (final label in ['Recipes', 'Planner', 'Calendar', 'Calories', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule and meal history (Phase 3).'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';

import '../foundations/app_breakpoints.dart';

class AppNavigationDestination {
  const AppNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AdaptiveAppShell extends StatelessWidget {
  const AdaptiveAppShell({
    required this.body,
    this.destinations = const [],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    super.key,
  });

  final Widget body;
  final List<AppNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowClass = AppBreakpoints.windowClassFor(constraints.maxWidth);
        final showNavigation = destinations.length >= 2;
        // Short landscape and split-screen windows need the horizontally compact
        // navigation bar; a rail can otherwise consume the entire usable height.
        final useRail =
            showNavigation &&
            windowClass != AppWindowClass.compact &&
            constraints.maxHeight >= 520;

        return Scaffold(
          body: useRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      labelType: windowClass == AppWindowClass.expanded
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.selected,
                      extended: windowClass == AppWindowClass.expanded,
                      destinations: [
                        for (final destination in destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: showNavigation && !useRail
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

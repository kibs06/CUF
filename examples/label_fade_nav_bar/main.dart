import 'package:flutter/material.dart';

import 'label_fade_nav_bar.dart';

void main() => runApp(const LabelFadeNavExampleApp());

class LabelFadeNavExampleApp extends StatelessWidget {
  const LabelFadeNavExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Label Fade Nav Bar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B4513)),
        scaffoldBackgroundColor: const Color(0xFFF5F0E8),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<NavBarItem> _items = [
    NavBarItem(icon: Icons.home_outlined, label: 'Home'),
    NavBarItem(icon: Icons.storefront_outlined, label: 'Store'),
    NavBarItem(
      icon: Icons.notifications_outlined,
      label: 'Notifications',
      badgeCount: 16,
    ),
    NavBarItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final active = _items[_selectedIndex];

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active.icon, size: 48, color: const Color(0xFF8B4513)),
            const SizedBox(height: 12),
            Text(
              '${active.label} tab',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B3B2F),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap a tab below — the label fades/slides and the '
              'icon color animates to accent.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: LabelFadeNavBar(
        items: _items,
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

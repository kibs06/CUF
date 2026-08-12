import 'package:flutter/material.dart';

import 'animated_pill_nav_bar.dart';

void main() => runApp(const PillNavExampleApp());

class PillNavExampleApp extends StatelessWidget {
  const PillNavExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animated Pill Nav Bar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B4A2B)),
        scaffoldBackgroundColor: const Color(0xFFF3EDE3),
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
  int _currentIndex = 0;

  static const List<NavItem> _items = [
    NavItem(icon: Icons.home_outlined, label: 'Home'),
    NavItem(icon: Icons.storefront_outlined, label: 'Store'),
    NavItem(
      icon: Icons.notifications_outlined,
      label: 'Notifications',
      badgeCount: 16,
    ),
    NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (final item in _items)
            _PlaceholderPage(
              icon: item.icon,
              title: item.label,
            ),
        ],
      ),
      bottomNavigationBar: AnimatedPillNavBar(
        items: _items,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlaceholderPage({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: const Color(0xFF6B4A2B)),
          const SizedBox(height: 16),
          Text(
            '$title tab',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B3B2F),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a tab — the pill slides and the icon tints brown.',
            style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }
}

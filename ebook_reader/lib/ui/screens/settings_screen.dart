// lib/ui/screens/settings_screen.dart
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/debouncer.dart';
import '../../data/models.dart';
import '../widgets/neon_bar.dart';

class SettingsScreen extends StatefulWidget {
  final AppTheme theme;
  final ValueChanged<AppTheme> onThemeChanged;
  final Accent accent;
  final ValueChanged<Accent> onAccentChanged;

  final UserPrefs prefs;
  final ValueChanged<UserPrefs> onSavePrefs;

  /// Common app bar actions (account, etc.) injected from MainScreen.
  final List<Widget> Function() commonActions;

  const SettingsScreen({
    super.key,
    required this.theme,
    required this.onThemeChanged,
    required this.accent,
    required this.onAccentChanged,
    required this.prefs,
    required this.onSavePrefs,
    required this.commonActions,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _name;
  late TextEditingController _email;
  late AppTheme _theme;
  late Accent _accent;
  double _fontSize = 18;
  double _lineHeight = 1.5;
  bool _useSerif = false;

  // Debounce live preference saves so Reader updates smoothly
  final Debouncer _prefsDebounce = Debouncer(const Duration(milliseconds: 200));

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prefs.displayName);
    _email = TextEditingController(text: widget.prefs.email);
    _theme = widget.theme;
    _accent = widget.accent;
    _fontSize = widget.prefs.defaultFontSize.clamp(12.0, 40.0);
    _lineHeight = widget.prefs.lineHeight.clamp(1.2, 2.0);
    _useSerif = widget.prefs.useSerif;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _savePrefs() {
    widget.onSavePrefs(UserPrefs(
      displayName: _name.text.trim(),
      email: _email.text.trim(),
      defaultFontSize: _fontSize,
      lineHeight: _lineHeight,
      useSerif: _useSerif,
    ));
  }

  // Save immediately (debounced) so Reader reflects changes live
  void _savePrefsDebounced() {
    _prefsDebounce(_savePrefs);
  }

  @override
  Widget build(BuildContext context) {
    final accentColorVal = accentColor(_accent);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: neonText(accentColorVal, size: 20, weight: FontWeight.w800)),
        actions: widget.commonActions(),
        flexibleSpace: NeonBar(accent: accentColorVal),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Appearance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ChoiceChip(label: const Text('Light'), selected: _theme == AppTheme.light, onSelected: (_) => setState(() => _theme = AppTheme.light)),
              ChoiceChip(label: const Text('Dark'), selected: _theme == AppTheme.dark, onSelected: (_) => setState(() => _theme = AppTheme.dark)),
              ChoiceChip(label: const Text('Sepia'), selected: _theme == AppTheme.sepia, onSelected: (_) => setState(() => _theme = AppTheme.sepia)),
              ChoiceChip(label: const Text('Neon'), selected: _theme == AppTheme.neon, onSelected: (_) => setState(() => _theme = AppTheme.neon)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onThemeChanged(_theme),
            icon: const Icon(Icons.palette),
            label: const Text('Apply Theme'),
          ),

          const SizedBox(height: 16),
          Text('Theme Accent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: Accent.values.map((a) {
              final c = accentColor(a);
              return ChoiceChip(
                selected: _accent == a,
                label: Text(a.name.toUpperCase()),
                onSelected: (_) => setState(() => _accent = a),
                avatar: CircleAvatar(radius: 8, backgroundColor: c),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onAccentChanged(_accent),
            icon: const Icon(Icons.color_lens),
            label: const Text('Apply Accent'),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email (for future login)', border: OutlineInputBorder()),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.format_size),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 40,
                  divisions: 14,
                  label: 'Default font: ${_fontSize.toStringAsFixed(0)}',
                  onChanged: (v) {
                    setState(() => _fontSize = v);
                    _savePrefsDebounced(); // live update Reader
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.format_line_spacing),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _lineHeight,
                  min: 1.2,
                  max: 2.0,
                  divisions: 8,
                  label: 'Line height: ${_lineHeight.toStringAsFixed(1)}',
                  onChanged: (v) {
                    setState(() => _lineHeight = v);
                    _savePrefsDebounced(); // live update Reader
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            value: _useSerif,
            onChanged: (v) {
              setState(() => _useSerif = v);
              _savePrefsDebounced(); // live update Reader
            },
            title: const Text('Use serif font'),
            subtitle: const Text('Georgia-like body font for reading comfort'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _savePrefs,
            icon: const Icon(Icons.save),
            label: const Text('Save Preferences'),
          ),
        ],
      ),
    );
  }
}

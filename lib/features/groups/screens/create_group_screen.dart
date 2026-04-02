import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/group_service.dart';
import 'package:bitemates/features/groups/screens/group_detail_screen.dart';

/// Create a new group — category, name, description, privacy, optional cover.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final GroupService _groupService = GroupService();
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _cityController = TextEditingController();

  String _selectedCategory = 'other';
  String _selectedPrivacy = 'public';
  String? _selectedEmoji;
  File? _coverImage;
  bool _isCreating = false;

  static const _categories = <String, Map<String, dynamic>>{
    'food': {'label': 'Food', 'icon': Icons.restaurant, 'emoji': '🍕'},
    'nightlife': {'label': 'Nightlife', 'icon': Icons.nightlife, 'emoji': '🌃'},
    'travel': {'label': 'Travel', 'icon': Icons.flight, 'emoji': '✈️'},
    'fitness': {'label': 'Fitness', 'icon': Icons.fitness_center, 'emoji': '💪'},
    'outdoors': {'label': 'Outdoors', 'icon': Icons.terrain, 'emoji': '🏔️'},
    'gaming': {'label': 'Gaming', 'icon': Icons.sports_esports, 'emoji': '🎮'},
    'arts': {'label': 'Arts', 'icon': Icons.palette, 'emoji': '🎨'},
    'music': {'label': 'Music', 'icon': Icons.music_note, 'emoji': '🎵'},
    'professional': {'label': 'Professional', 'icon': Icons.work_outline, 'emoji': '💼'},
    'other': {'label': 'Other', 'icon': Icons.groups, 'emoji': '🌟'},
  };

  static const _privacyOptions = <String, Map<String, dynamic>>{
    'public': {
      'label': 'Public',
      'icon': Icons.public,
      'desc': 'Anyone can find and join',
      'color': Colors.green,
    },
    'private': {
      'label': 'Private',
      'icon': Icons.lock_outline,
      'desc': 'Visible but requires approval',
      'color': Colors.orange,
    },
    'hidden': {
      'label': 'Hidden',
      'icon': Icons.visibility_off,
      'desc': 'Invite-only, hidden from search',
      'color': Colors.red,
    },
  };

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _coverImage = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);
    HapticFeedback.mediumImpact();

    final result = await _groupService.createGroup(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      rules: _rulesController.text.trim().isNotEmpty
          ? _rulesController.text.trim()
          : null,
      category: _selectedCategory,
      privacy: _selectedPrivacy,
      iconEmoji: _selectedEmoji ??
          _categories[_selectedCategory]?['emoji'] as String?,
      locationCity: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      coverImage: _coverImage,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context); // Return to groups list
      // Then navigate to the new group
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GroupDetailScreen(groupId: result['group_id'] as String),
        ),
      );
    } else {
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Failed to create group')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Cover Image Picker
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.teal.withOpacity(0.3),
                    style: BorderStyle.solid,
                  ),
                  image: _coverImage != null
                      ? DecorationImage(
                          image: FileImage(_coverImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _coverImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 40, color: Colors.teal[300]),
                          const SizedBox(height: 8),
                          Text('Add Cover Image',
                              style: TextStyle(
                                  color: Colors.teal[400],
                                  fontWeight: FontWeight.w500)),
                          Text('(Optional)',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 12)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            // ── Group Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Group Name *',
                hintText: 'e.g. Manila Foodies',
                prefixIcon: const Icon(Icons.edit_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLength: 60,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Give your group a name';
                }
                if (v.trim().length < 3) return 'At least 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Category Selector
            const Text('Category',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.entries.map((entry) {
                final isSelected = _selectedCategory == entry.key;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(entry.value['icon'] as IconData,
                          size: 16,
                          color: isSelected ? Colors.white : Colors.teal),
                      const SizedBox(width: 4),
                      Text(entry.value['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: Colors.teal,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w500,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = entry.key;
                      _selectedEmoji = entry.value['emoji'] as String;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ── Privacy
            const Text('Privacy',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            ..._privacyOptions.entries.map((entry) {
              final isSelected = _selectedPrivacy == entry.key;
              final color = entry.value['color'] as Color;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedPrivacy = entry.key),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withOpacity(0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? color.withOpacity(0.5)
                          : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(entry.value['icon'] as IconData,
                          color: isSelected ? color : Colors.grey[500],
                          size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value['label'] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected ? color : null,
                              ),
                            ),
                            Text(
                              entry.value['desc'] as String,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 22),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),

            // ── Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'What is this group about?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 8),

            // ── Rules (optional)
            TextFormField(
              controller: _rulesController,
              decoration: InputDecoration(
                labelText: 'Group Rules (optional)',
                hintText: '1. Be respectful\n2. No spam',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 8),

            // ── City
            TextFormField(
              controller: _cityController,
              decoration: InputDecoration(
                labelText: 'City (optional)',
                hintText: 'e.g. Manila, Tokyo',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Create Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Group'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

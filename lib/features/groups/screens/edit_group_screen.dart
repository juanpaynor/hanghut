import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bitemates/core/services/group_service.dart';

/// Edit an existing group — same fields as create, pre-populated.
class EditGroupScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const EditGroupScreen({super.key, required this.group});

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final GroupService _groupService = GroupService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _rulesController;
  late final TextEditingController _cityController;

  late String _selectedCategory;
  late String _selectedPrivacy;
  File? _newCoverImage;
  bool _isSaving = false;

  String? get _existingCoverUrl =>
      widget.group['cover_image_url'] as String?;

  static const _categories = <String, Map<String, dynamic>>{
    'food': {'label': 'Food', 'icon': Icons.restaurant, 'emoji': '🍕'},
    'nightlife': {
      'label': 'Nightlife',
      'icon': Icons.nightlife,
      'emoji': '🌃'
    },
    'travel': {'label': 'Travel', 'icon': Icons.flight, 'emoji': '✈️'},
    'fitness': {
      'label': 'Fitness',
      'icon': Icons.fitness_center,
      'emoji': '💪'
    },
    'outdoors': {'label': 'Outdoors', 'icon': Icons.terrain, 'emoji': '🏔️'},
    'gaming': {
      'label': 'Gaming',
      'icon': Icons.sports_esports,
      'emoji': '🎮'
    },
    'arts': {'label': 'Arts', 'icon': Icons.palette, 'emoji': '🎨'},
    'music': {'label': 'Music', 'icon': Icons.music_note, 'emoji': '🎵'},
    'professional': {
      'label': 'Professional',
      'icon': Icons.work_outline,
      'emoji': '💼'
    },
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
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.group['name'] ?? '');
    _descriptionController =
        TextEditingController(text: widget.group['description'] ?? '');
    _rulesController =
        TextEditingController(text: widget.group['rules'] ?? '');
    _cityController =
        TextEditingController(text: widget.group['location_city'] ?? '');
    _selectedCategory = widget.group['category'] ?? 'other';
    _selectedPrivacy = widget.group['privacy'] ?? 'public';
  }

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
        setState(() => _newCoverImage = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _saveGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final groupId = widget.group['id'] as String;

    final result = await _groupService.updateGroup(
      groupId,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      rules: _rulesController.text.trim().isNotEmpty
          ? _rulesController.text.trim()
          : null,
      category: _selectedCategory,
      privacy: _selectedPrivacy,
      iconEmoji: _categories[_selectedCategory]?['emoji'] as String?,
      locationCity: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      coverImage: _newCoverImage,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true); // true = refresh parent
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Failed to update group')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Group'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveGroup,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Save',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    )),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Cover Image
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]
                      : primaryColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.grey[800]!
                        : primaryColor.withOpacity(0.2),
                  ),
                  image: _newCoverImage != null
                      ? DecorationImage(
                          image: FileImage(_newCoverImage!),
                          fit: BoxFit.cover,
                        )
                      : _existingCoverUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_existingCoverUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                ),
                child:
                    (_newCoverImage == null && _existingCoverUrl == null)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 36,
                                  color: isDark
                                      ? Colors.grey[500]
                                      : primaryColor.withOpacity(0.5)),
                              const SizedBox(height: 8),
                              Text('Add Cover Image',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[500]
                                        : primaryColor.withOpacity(0.7),
                                    fontWeight: FontWeight.w500,
                                  )),
                            ],
                          )
                        : Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('Change',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Group Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Group Name *',
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

            // ── Category
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
                          color: isSelected
                              ? Colors.white
                              : primaryColor),
                      const SizedBox(width: 4),
                      Text(entry.value['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w500,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedCategory = entry.key);
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
                          : (isDark
                              ? Colors.grey[800]!
                              : Colors.grey[300]!),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(entry.value['icon'] as IconData,
                          color:
                              isSelected ? color : Colors.grey[500],
                          size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
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
                                  fontSize: 12,
                                  color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle,
                            color: color, size: 22),
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

            // ── Rules
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
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

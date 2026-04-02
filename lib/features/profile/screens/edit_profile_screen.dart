import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitemates/core/config/supabase_config.dart';
import 'package:bitemates/core/theme/app_theme.dart';
import 'package:bitemates/core/services/image_crop_service.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final List<Map<String, dynamic>> userPhotos;

  const EditProfileScreen({
    super.key,
    required this.userProfile,
    required this.userPhotos,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _occupationController;
  late TextEditingController _instagramController;

  bool _isLoading = false;
  String? _usernameError;
  List<String> _selectedTags = [];
  List<Map<String, dynamic>> _localPhotos = [];
  final ImagePicker _picker = ImagePicker();

  // Suggest some default tags
  final List<String> _availableTags = [
    'Coffee Lover',
    'Foodie',
    'Techie',
    'Gym Rat',
    'Traveler',
    'Gamer',
    'Artist',
    'Night Owl',
    'Early Bird',
    'Bookworm',
    'Music Lover',
    'Chill',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.userProfile['display_name'],
    );
    _usernameController = TextEditingController(
      text: widget.userProfile['username'],
    );
    _bioController = TextEditingController(text: widget.userProfile['bio']);
    _occupationController = TextEditingController(
      text: widget.userProfile['occupation'],
    );
    _instagramController = TextEditingController(
      text: widget.userProfile['social_instagram'],
    );

    if (widget.userProfile['tags'] != null) {
      _selectedTags = List<String>.from(widget.userProfile['tags']);
    }

    _localPhotos = List<Map<String, dynamic>>.from(widget.userPhotos);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _occupationController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _validateUsername(String value) async {
    final username = value.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() => _usernameError = null);
      return;
    }
    if (username.length < 3) {
      setState(() => _usernameError = 'At least 3 characters');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() => _usernameError = 'Only letters, numbers, and underscores');
      return;
    }
    // Check availability
    try {
      final available = await SupabaseConfig.client.rpc(
        'check_username_available',
        params: {
          'p_username': username,
          'p_exclude_user_id': widget.userProfile['id'],
        },
      );
      if (mounted) {
        setState(() {
          _usernameError = available == true ? null : 'Username already taken';
        });
      }
    } catch (e) {
      print('Error checking username: $e');
    }
  }

  Future<void> _pickImage() async {
    if (_localPhotos.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Max 5 photos allowed')));
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final croppedFile = await ImageCropService.cropImage(
        sourcePath: image.path,
        context: context,
      );

      if (croppedFile == null) return;

      setState(() => _isLoading = true);

      final file = File(croppedFile.path);
      final fileExt = croppedFile.path.split('.').last;
      final fileName = '${DateTime.now().toIso8601String()}.$fileExt';
      final userId = widget.userProfile['id'];
      final filePath = '$userId/$fileName';

      await SupabaseConfig.client.storage
          .from('profile-photos')
          .upload(filePath, file);

      final imageUrl = SupabaseConfig.client.storage
          .from('profile-photos')
          .getPublicUrl(filePath);

      setState(() {
        _localPhotos.add({
          'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
          'photo_url': imageUrl,
          'is_new': true,
        });
        _isLoading = false;
      });
    } catch (e) {
      print('Upload Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = widget.userProfile['id'];

      // 1. Update User Profile Fields
      await SupabaseConfig.client
          .from('users')
          .update({
            'display_name': _displayNameController.text.trim(),
            'username': _usernameController.text.trim().toLowerCase(),
            'bio': _bioController.text.trim(),
            'occupation': _occupationController.text.trim(),
            'social_instagram': _instagramController.text.trim().replaceAll(
              '@',
              '',
            ),
            'tags': _selectedTags,
          })
          .eq('id', userId);

      // 2. Update Photos
      // First, reset all photos to non-primary to avoid unique constraint violations
      // (idx_user_photos_one_primary)
      await SupabaseConfig.client
          .from('user_photos')
          .update({'is_primary': false})
          .eq('user_id', userId);

      for (int i = 0; i < _localPhotos.length; i++) {
        final photo = _localPhotos[i];
        final isPrimary = (i == 0);

        if (photo['is_new'] == true) {
          await SupabaseConfig.client.from('user_photos').insert({
            'user_id': userId,
            'photo_url': photo['photo_url'],
            'is_primary': isPrimary,
            'sort_order': i,
          });
        } else {
          await SupabaseConfig.client
              .from('user_photos')
              .update({'is_primary': isPrimary, 'sort_order': i})
              .eq('id', photo['id']);
        }
      }

      final localIds = _localPhotos.map((p) => p['id']).toSet();
      for (var original in widget.userPhotos) {
        if (!localIds.contains(original['id'])) {
          await SupabaseConfig.client
              .from('user_photos')
              .delete()
              .eq('id', original['id']);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Save Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? colorScheme.surface : AppTheme.primaryColor,
        title: Text(
          'Edit Profile',
          style: TextStyle(color: isDark ? colorScheme.onSurface : Colors.white),
        ),
        iconTheme: IconThemeData(color: isDark ? colorScheme.onSurface : Colors.white),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentColor,
                    ),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: isDark ? AppTheme.primaryColor : AppTheme.accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Media Manager ---
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Photos (Max 5)',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 140,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _localPhotos.length + 1,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > _localPhotos.length) return;
                  if (oldIndex >= _localPhotos.length) return;

                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _localPhotos.removeAt(oldIndex);
                    _localPhotos.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  if (index == _localPhotos.length) {
                    // Add Button
                    return GestureDetector(
                      key: const ValueKey('add_button'),
                      onTap: _pickImage,
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkSurface : AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add_photo_alternate,
                            color: isDark ? Colors.grey.shade500 : Colors.grey,
                            size: 32,
                          ),
                        ),
                      ),
                    );
                  }

                  final photo = _localPhotos[index];
                  final isHero = index == 0;

                  return Container(
                    key: ValueKey(photo['id']),
                    width: 100,
                    margin: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        // Image
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: isHero
                                ? Border.all(
                                    color: AppTheme.accentColor,
                                    width: 3,
                                  )
                                : null,
                            image: DecorationImage(
                              image: NetworkImage(photo['photo_url']),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Hero Badge
                        if (isHero)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.8),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(9),
                                ),
                              ),
                              child: Text(
                                'Main',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        // Delete Button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _localPhotos.removeAt(index);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade800 : Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                color: isDark ? Colors.white : Colors.black,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),
            Divider(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),

            // --- Identity Form ---
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Display Name'),
                  _buildTextField(_displayNameController, 'e.g. Rich'),

                  const SizedBox(height: 16),
                  _buildLabel('Username', icon: Icons.alternate_email),
                  _buildTextField(
                    _usernameController,
                    'e.g. richsantos',
                    prefix: '@',
                    onChanged: _validateUsername,
                    errorText: _usernameError,
                  ),

                  const SizedBox(height: 16),
                  _buildLabel('Occupation', icon: Icons.work_outline),
                  _buildTextField(
                    _occupationController,
                    'e.g. Product Designer',
                  ),

                  const SizedBox(height: 16),
                  _buildLabel('Instagram', icon: Icons.camera_alt_outlined),
                  _buildTextField(
                    _instagramController,
                    'username',
                    prefix: '@',
                  ),

                  const SizedBox(height: 24),
                  Divider(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                  const SizedBox(height: 16),

                  // --- Vibe Check ---
                  _buildLabel('Bio (The Story)', icon: Icons.format_quote),
                  _buildTextField(
                    _bioController,
                    'Tell us about yourself...',
                    maxLines: 4,
                  ),

                  const SizedBox(height: 24),
                  _buildLabel(
                    'Your Vibe (Select Tags)',
                    icon: Icons.local_offer_outlined,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableTags.map((tag) {
                      final isSelected = _selectedTags.contains(tag);
                      return ChoiceChip(
                        label: Text(tag),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.surfaceColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (_selectedTags.length < 5) {
                                _selectedTags.add(tag);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Max 5 tags allowed'),
                                  ),
                                );
                              }
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: labelColor, size: 16),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(
              color: labelColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    String? prefix,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: errorText != null
                  ? Colors.red.shade300
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            ),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            ),
            maxLines: maxLines,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              prefixIcon: prefix != null
                  ? Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        prefix,
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade500 : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorText,
              style: TextStyle(color: Colors.red.shade400, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

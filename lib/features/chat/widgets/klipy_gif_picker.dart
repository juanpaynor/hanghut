import 'package:flutter/material.dart';
import 'package:bitemates/core/services/klipy_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// GIF picker backed by the KLIPY API (migrated from Tenor).
/// Attribution per KLIPY guidelines: "Search KLIPY" placeholder (required) +
/// "Powered by KLIPY" mark.
class KlipyGifPicker extends StatefulWidget {
  final bool isEmbedded;
  final Function(String gifUrl) onGifSelected;

  const KlipyGifPicker({
    super.key,
    required this.onGifSelected,
    this.isEmbedded = false,
  });

  @override
  State<KlipyGifPicker> createState() => _KlipyGifPickerState();
}

class _KlipyGifPickerState extends State<KlipyGifPicker> {
  final KlipyService _klipyService = KlipyService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _gifs = [];
  bool _isLoading = true;
  // 'gifs' | 'stickers' | 'memes' — all flow through the same onGifSelected
  // callback and the same gif_url storage/render pipeline.
  String _mode = 'gifs';

  // Only stickers are transparent (rendered with `contain` + a backdrop).
  bool get _isStickers => _mode == 'stickers';

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _switchMode(String mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _searchController.clear();
    });
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoading = true);
    final items = switch (_mode) {
      'stickers' => await _klipyService.getTrendingStickers(limit: 30),
      'memes' => await _klipyService.getTrendingMemes(limit: 30),
      _ => await _klipyService.getTrendingGifs(limit: 30),
    };
    if (mounted) {
      setState(() {
        _gifs = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchGifs(String query) async {
    if (query.isEmpty) {
      _loadTrending();
      return;
    }

    setState(() => _isLoading = true);
    final items = switch (_mode) {
      'stickers' => await _klipyService.searchStickers(query, limit: 30),
      'memes' => await _klipyService.searchMemes(query, limit: 30),
      _ => await _klipyService.searchGifs(query, limit: 30),
    };
    if (mounted) {
      setState(() {
        _gifs = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.isEmbedded ? null : MediaQuery.of(context).size.height * 0.7,
      decoration: widget.isEmbedded
          ? null
          : const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
      child: Column(
        children: [
          // Drag handle - Only if not embedded
          if (!widget.isEmbedded)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (_mode) {
                        'stickers' => 'Send a sticker',
                        'memes' => 'Send a meme',
                        _ => 'Send a GIF',
                      },
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Powered by KLIPY',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (!widget.isEmbedded)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),

          // GIF / Sticker toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _ModeToggle(mode: _mode, onChanged: _switchMode),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                // "Search KLIPY" placeholder is REQUIRED by KLIPY attribution
                // guidelines.
                hintText: 'Search KLIPY',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _searchGifs,
            ),
          ),

          // Content
          Expanded(child: _buildGifGrid(_gifs, _isLoading)),
        ],
      ),
    );
  }

  Widget _buildGifGrid(List<Map<String, dynamic>> gifs, bool isLoading) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (gifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (_mode) {
                'stickers' => Icons.emoji_emotions_outlined,
                'memes' => Icons.image_outlined,
                _ => Icons.gif_box_outlined,
              },
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? switch (_mode) {
                      'stickers' => 'No stickers found',
                      'memes' => 'No memes found',
                      _ => 'No GIFs found',
                    }
                  : 'No results found',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Stickers are transparent: use `contain` so the whole sticker shows (not
    // cropped) and a light backdrop so pale stickers stay visible.
    final isStickers = _isStickers;
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: gifs.length,
      itemBuilder: (context, index) {
        final gif = gifs[index];
        final gifUrl = _klipyService.getGifUrl(gif);
        final previewUrl = _klipyService.getPreviewUrl(gif);

        return GestureDetector(
          onTap: () {
            widget.onGifSelected(gifUrl);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Colors.grey[100],
              padding: isStickers ? const EdgeInsets.all(8) : EdgeInsets.zero,
              child: CachedNetworkImage(
                imageUrl: previewUrl.isNotEmpty ? previewUrl : gifUrl,
                fit: isStickers ? BoxFit.contain : BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.error_outline, color: Colors.grey),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Segmented GIFs / Stickers / Memes toggle for the picker.
class _ModeToggle extends StatelessWidget {
  final String mode; // 'gifs' | 'stickers' | 'memes'
  final ValueChanged<String> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  static const _segments = [
    ('GIFs', 'gifs'),
    ('Stickers', 'stickers'),
    ('Memes', 'memes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (label, value) in _segments) _seg(context, label, value),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, String value) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.black87 : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }
}

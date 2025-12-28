import 'package:flutter/material.dart';
import 'package:bitemates/core/services/tenor_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TenorGifPicker extends StatefulWidget {
  final bool isEmbedded;
  final Function(String gifUrl) onGifSelected;

  const TenorGifPicker({
    super.key, 
    required this.onGifSelected,
    this.isEmbedded = false,
  });

  @override
  State<TenorGifPicker> createState() => _TenorGifPickerState();
}

class _TenorGifPickerState extends State<TenorGifPicker> {
  final TenorService _tenorService = TenorService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _gifs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrendingGifs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrendingGifs() async {
    // ... (rest of method unchanged)
    setState(() => _isLoading = true);
    final gifs = await _tenorService.getTrendingGifs(limit: 30);
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchGifs(String query) async {
    // ... (rest of method unchanged)
    if (query.isEmpty) {
      _loadTrendingGifs();
      return;
    }

    setState(() => _isLoading = true);
    final gifs = await _tenorService.searchGifs(query, limit: 30);
    if (mounted) {
      setState(() {
        _gifs = gifs;
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
                    const Text(
                      'Send a GIF',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Powered By Tenor',
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

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search Tenor',
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
            Icon(Icons.gif_box_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No GIFs found'
                  : 'No results found',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ],
        ),
      );
    }

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
        final gifUrl = _tenorService.getGifUrl(gif);
        final previewUrl = _tenorService.getPreviewUrl(gif);

        return GestureDetector(
          onTap: () {
            widget.onGifSelected(gifUrl);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: previewUrl.isNotEmpty ? previewUrl : gifUrl,
              fit: BoxFit.cover,
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
        );
      },
    );
  }
}

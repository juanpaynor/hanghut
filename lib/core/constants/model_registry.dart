class ModelRegistry {
  // Base path for 3D models
  static const String _basePath = 'assets/models/';

  // 3D Model Assets
  static const String tennisRacket = '${_basePath}tennis_racket.glb';
  static const String basketball = '${_basePath}basketball.glb';
  static const String soccerBall = '${_basePath}soccer_ball.glb';
  static const String burger = '${_basePath}burger.glb';
  static const String pizza = '${_basePath}pizza.glb';
  static const String chineseFood = '${_basePath}chinese_food_box.glb';
  static const String creamedCoffee = '${_basePath}creamed_coffee.glb';
  static const String coffeeCup = '${_basePath}coffee_shop_cup.glb';
  static const String arrow = '${_basePath}arrow.glb';

  // Keyword Dictionary
  // Ordered by priority (Specific -> Generic)
  static final Map<String, List<String>> _keywords = {
    // Top Priority: Specific Coffee
    creamedCoffee: [
      'starbucks',
      'frappuccino',
      'latte',
      'cappuccino',
      'mocha',
      'flat white',
    ],

    // Sports
    tennisRacket: ['tennis', 'racket', 'court', 'wimbledon', 'serve', 'ace'],
    basketball: ['basket', 'hoop', 'dunk', 'nba', 'shoot', 'ballin'],
    soccerBall: ['soccer', 'football', 'goal', 'kick', 'fifa', 'futsal'],

    // Food
    burger: ['burger', 'patty', 'fast food', 'mcdonalds', 'shake shack'],
    pizza: ['pizza', 'slice', 'pepperoni', 'pie', 'dominos', 'hut'],
    chineseFood: [
      'asian',
      'chinese',
      'noodle',
      'rice',
      'dim sum',
      'sushi',
      'ramen',
      'curry',
      'thai',
    ],

    // Generic Coffee (Lowest Priority of specific items)
    coffeeCup: ['coffee', 'cafe', 'espresso', 'tea', 'morning', 'brew', 'java'],
  };

  // Scale Normalization Factors (Final Extreme Calibration)
  // "Pixel Size" Logic: These multipliers cancel out the source file size differences.
  // Goal: All objects appear roughly "Building Sized" (approx 10-20 meters high).
  static final Map<String, double> _baseScales = {
    // 1. SPORTS (Source files are HUGE ~500m) -> Reduce to 0.04x
    basketball: 0.04,
    soccerBall: 0.04,
    tennisRacket: 0.1, // Slightly smaller source than ball, so 0.1x
    // 2. FOOD (Source files are OK ~10m) -> Keep at 1.0x
    burger: 1.0,
    pizza: 1.0,
    chineseFood: 1.0,
    creamedCoffee: 1.0,
    coffeeCup: 1.0,

    // 3. UTILS (Source files are TINY ~0.2m) -> Boost to 50.0x
    arrow: 50.0,
  };

  /// Main Parser: Detects the appropriate 3D model based on text content.
  /// Returns the asset path (e.g., 'assets/models/burger.glb').
  /// Defaults to 'assets/models/arrow.glb' if no match found.
  static String detectActivityModel(String? text) {
    if (text == null || text.trim().isEmpty) {
      return arrow;
    }

    final lowerText = text.toLowerCase();

    for (final entry in _keywords.entries) {
      final modelPath = entry.key;
      final keywords = entry.value;

      for (final keyword in keywords) {
        if (lowerText.contains(keyword)) {
          return modelPath;
        }
      }
    }

    return arrow;
  }

  /// Returns the visual scale factor for a given model path.
  /// Used to normalize different model sizes on the map.
  static double getScaleFactor(String assetPath) {
    return _baseScales[assetPath] ?? 1.0;
  }
}

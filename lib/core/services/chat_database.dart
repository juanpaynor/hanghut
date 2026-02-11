import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:bitemates/core/config/supabase_config.dart';

/// Local SQLite database for chat messages (Telegram model)
/// Used for tables with chat_storage_type = 'telegram'
class ChatDatabase {
  static final ChatDatabase _instance = ChatDatabase._internal();
  factory ChatDatabase() => _instance;
  ChatDatabase._internal();

  Database? _database;

  Future<void> init() async {
    if (_database != null) return;

    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'bitemates_chat.db');

    _database = await openDatabase(
      path,
      version: 3, // Bumped for sequence_number
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    print('✅ ChatDatabase initialized');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        table_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT,
        content TEXT,
        timestamp INTEGER NOT NULL,
        sequence_number INTEGER,
        reply_to_id TEXT,
        message_type TEXT DEFAULT 'text',
        gif_url TEXT,
        chat_type TEXT DEFAULT 'table',
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_table_messages 
      ON messages(table_id, sequence_number DESC)
    ''');

    print('✅ ChatDatabase schema created');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE messages ADD COLUMN chat_type TEXT DEFAULT 'table'",
      );
      print('🆙 Upgraded ChatDatabase to v2 (added chat_type)');
    }

    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE messages ADD COLUMN sequence_number INTEGER",
      );
      // Recreate index to use sequence_number
      await db.execute("DROP INDEX IF EXISTS idx_table_messages");
      await db.execute('''
        CREATE INDEX idx_table_messages 
        ON messages(table_id, sequence_number DESC)
      ''');
      print('🆙 Upgraded ChatDatabase to v3 (added sequence_number)');
    }
  }

  /// Get messages with pagination support
  /// [limit] - Number of messages to fetch (default: 50)
  /// [offset] - Number of messages to skip (for pagination)
  /// Orders by sequence_number (server-assigned) for guaranteed correct order
  Future<List<Map<String, dynamic>>> getMessages(
    String tableId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await init();

    final messages = await _database!.query(
      'messages',
      where: 'table_id = ?',
      whereArgs: [tableId],
      // Order by sequence_number (with fallback to timestamp for old messages)
      orderBy: 'COALESCE(sequence_number, timestamp) DESC',
      limit: limit,
      offset: offset,
    );

    // Reverse to show oldest first in UI
    return messages;
  }

  /// Get total message count for a table (for pagination UI)
  Future<int> getMessageCount(String tableId) async {
    await init();

    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE table_id = ?',
      [tableId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedMessages(String tableId) async {
    await init();

    final messages = await _database!.query(
      'messages',
      where: 'table_id = ? AND synced = ?',
      whereArgs: [tableId, 0],
      orderBy: 'timestamp ASC',
    );

    return messages;
  }

  Future<void> saveMessage(Map<String, dynamic> message) async {
    await init();

    await _database!.insert(
      'messages',
      message,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('💾 Message saved locally: ${message['id']}');
  }

  Future<void> saveMessages(List<Map<String, dynamic>> messages) async {
    await init();

    final batch = _database!.batch();
    for (var msg in messages) {
      batch.insert(
        'messages',
        msg,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    print('💾 Saved ${messages.length} messages locally');
  }

  Future<void> syncToCloud(Map<String, dynamic> message) async {
    try {
      final chatType = message['chat_type'] ?? 'table';
      String tableName = 'messages';
      String idColumn = 'table_id';
      bool isTrip = chatType == 'trip';
      bool isDM = chatType == 'dm';

      if (isTrip) {
        tableName = 'trip_messages';
        idColumn = 'chat_id';
      } else if (isDM) {
        tableName = 'direct_messages';
        idColumn = 'chat_id';
      }

      // Check if reply_to_id message exists in Supabase
      String? validReplyToId;
      if (message['reply_to_id'] != null) {
        try {
          final replyMsg = await SupabaseConfig.client
              .from(tableName)
              .select('id')
              .eq('id', message['reply_to_id'])
              .maybeSingle();

          if (replyMsg != null) {
            validReplyToId = message['reply_to_id'];
          } else {
            print(
              '⚠️ Reply target message not in cloud yet, skipping reply_to_id',
            );
          }
        } catch (e) {
          print('⚠️ Error checking reply_to_id: $e');
        }
      }

      final msgForCloud = {
        'id': message['id'],
        idColumn: message['table_id'], // Local DB always calls it table_id
        'sender_id': message['sender_id'],
        'content': message['content'],
        if (isTrip)
          'sent_at': DateTime.fromMillisecondsSinceEpoch(
            message['timestamp'],
          ).toIso8601String(),
        if (isDM)
          'created_at': DateTime.fromMillisecondsSinceEpoch(
            message['timestamp'],
          ).toIso8601String(),
        if (!isTrip && !isDM)
          'timestamp': DateTime.fromMillisecondsSinceEpoch(
            message['timestamp'],
          ).toIso8601String(),
        if (isTrip || isDM)
          'message_type':
              message['message_type'] ?? 'text', // Trip/DM use message_type
        if (!isTrip && !isDM)
          'content_type':
              message['message_type'] ?? 'text', // Legacy uses content_type
        if (validReplyToId != null) 'reply_to_id': validReplyToId,
        if (message['gif_url'] != null) 'gif_url': message['gif_url'],
        if (message['sender_name'] != null)
          'sender_name': message['sender_name'],
        'sequence_number': message['sequence_number'],
      };

      // Use upsert to avoid duplicate key errors
      await SupabaseConfig.client.from(tableName).upsert(msgForCloud);

      await _database!.update(
        'messages',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [message['id']],
      );

      print('☁️ Message synced to cloud: ${message['id']}');
    } catch (e) {
      print('⚠️ Failed to sync message to cloud: $e');
      // Still mark as synced if it's a duplicate error
      if (e.toString().contains('duplicate') ||
          e.toString().contains('already exists')) {
        await _database!.update(
          'messages',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [message['id']],
        );
        print('✅ Message already exists in cloud, marked as synced');
      }
    }
  }

  Future<void> initialSyncFromCloud(
    String tableId, {
    String chatType = 'table',
  }) async {
    try {
      String tableName = 'messages';
      String idColumn = 'table_id';
      String timeColumn = 'timestamp';

      if (chatType == 'trip') {
        tableName = 'trip_messages';
        idColumn = 'chat_id';
        timeColumn = 'sent_at';
      } else if (chatType == 'dm') {
        tableName = 'direct_messages';
        idColumn = 'chat_id';
        timeColumn = 'created_at';
      }

      final cloudMessages = await SupabaseConfig.client
          .from(tableName)
          .select('*, sender:users(display_name)')
          .eq(idColumn, tableId)
          .order(
            'sequence_number',
            ascending: true,
          ); // Order by sequence number

      if (cloudMessages.isEmpty) return;

      final localMessages = cloudMessages.map((msg) {
        final senderName = msg['sender'] != null
            ? msg['sender']['display_name'] as String?
            : null;

        return {
          'id': msg['id'],
          'table_id': tableId, // Standardize on table_id locally
          'sender_id': msg['sender_id'],
          'sender_name': senderName,
          'content': msg['content'],
          'timestamp': DateTime.parse(msg[timeColumn]).millisecondsSinceEpoch,
          'sequence_number': msg['sequence_number'], // Include sequence number
          'reply_to_id': msg['reply_to_id'],
          'message_type': msg['message_type'] ?? msg['content_type'] ?? 'text',
          'gif_url': msg['gif_url'],
          'chat_type': chatType,
          'synced': 1,
        };
      }).toList();

      await saveMessages(localMessages);
      print('✅ Initial sync complete: ${localMessages.length} messages');
    } catch (e) {
      print('❌ Initial sync failed: $e');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await init();

    await _database!.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    print('🗑️ Deleted message: $messageId');
  }

  Future<void> deleteTableMessages(String tableId) async {
    await init();

    await _database!.delete(
      'messages',
      where: 'table_id = ?',
      whereArgs: [tableId],
    );

    print('🗑️ Deleted all messages for table: $tableId');
  }

  /// Cleanup old messages (older than 30 days)
  /// Keeps recent messages to prevent unlimited database growth
  Future<void> cleanupOldMessages() async {
    await init();

    final cutoffTimestamp = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final deletedCount = await _database!.delete(
      'messages',
      where: 'timestamp < ? AND synced = 1', // Only delete synced messages
      whereArgs: [cutoffTimestamp],
    );

    print('🧹 Cleaned up $deletedCount old messages (>30 days)');
  }

  /// Update message delivery status
  Future<void> updateMessageStatus({
    required String messageId,
    required String status,
  }) async {
    await init();

    await _database!.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    print('✅ Updated message $messageId status to: $status');
  }

  /// Get unsynced message count for monitoring
  Future<int> getUnsyncedCount(String tableId) async {
    await init();

    final result = await _database!.query(
      'messages',
      columns: ['COUNT(*) as count'],
      where: 'table_id = ? AND synced = 0',
      whereArgs: [tableId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }
}

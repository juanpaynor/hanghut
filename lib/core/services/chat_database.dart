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
      version: 2,
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
        reply_to_id TEXT,
        message_type TEXT DEFAULT 'text',
        reply_to_id TEXT,
        message_type TEXT DEFAULT 'text',
        gif_url TEXT,
        chat_type TEXT DEFAULT 'table',
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_table_messages 
      ON messages(table_id, timestamp ASC)
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
  }

  Future<List<Map<String, dynamic>>> getMessages(String tableId) async {
    await init();

    final messages = await _database!.query(
      'messages',
      where: 'table_id = ?',
      whereArgs: [tableId],
      orderBy: 'timestamp ASC',
    );

    return messages;
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
      final isTrip = message['chat_type'] == 'trip';
      final tableName = isTrip ? 'trip_messages' : 'messages';
      final idColumn = isTrip ? 'chat_id' : 'table_id';

      final msgForCloud = {
        'id': message['id'],
        idColumn: message['table_id'], // Local DB always calls it table_id
        'sender_id': message['sender_id'],
        'content': message['content'],
        if (!isTrip)
          'timestamp': DateTime.fromMillisecondsSinceEpoch(
            message['timestamp'],
          ).toIso8601String(),
        if (isTrip)
          'message_type':
              message['message_type'] ?? 'text', // Trip uses message_type
        if (!isTrip)
          'content_type':
              message['message_type'] ?? 'text', // Legacy uses content_type
        if (message['reply_to_id'] != null)
          'reply_to_id': message['reply_to_id'],
        if (message['gif_url'] != null) 'gif_url': message['gif_url'],
      };

      await SupabaseConfig.client.from(tableName).insert(msgForCloud);

      await _database!.update(
        'messages',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [message['id']],
      );

      print('☁️ Message synced to cloud: ${message['id']}');
    } catch (e) {
      print('⚠️ Failed to sync message to cloud: $e');
    }
  }

  Future<void> initialSyncFromCloud(
    String tableId, {
    String chatType = 'table',
  }) async {
    try {
      final isTrip = chatType == 'trip';
      final tableName = isTrip ? 'trip_messages' : 'messages';
      final idColumn = isTrip ? 'chat_id' : 'table_id';
      final timeColumn = isTrip ? 'sent_at' : 'timestamp';

      final cloudMessages = await SupabaseConfig.client
          .from(tableName)
          .select()
          .eq(idColumn, tableId)
          .order(timeColumn, ascending: true);

      if (cloudMessages.isEmpty) return;

      final localMessages = cloudMessages.map((msg) {
        return {
          'id': msg['id'],
          'table_id': tableId, // Standardize on table_id locally
          'sender_id': msg['sender_id'],
          'sender_name': msg['sender_name'], // Might be null depending on query
          'content': msg['content'],
          'timestamp': DateTime.parse(msg[timeColumn]).millisecondsSinceEpoch,
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

  Future<void> deleteTableMessages(String tableId) async {
    await init();

    await _database!.delete(
      'messages',
      where: 'table_id = ?',
      whereArgs: [tableId],
    );

    print('🗑️ Deleted all messages for table: $tableId');
  }
}

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

    _database = await openDatabase(path, version: 1, onCreate: _onCreate);

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
        gif_url TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_table_messages 
      ON messages(table_id, timestamp ASC)
    ''');

    print('✅ ChatDatabase schema created');
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
      final msgForCloud = {
        'id': message['id'],
        'table_id': message['table_id'],
        'sender_id': message['sender_id'],
        'content': message['content'],
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          message['timestamp'],
        ).toIso8601String(),
        'content_type': message['message_type'] ?? 'text',
        if (message['reply_to_id'] != null)
          'reply_to_id': message['reply_to_id'],
        if (message['gif_url'] != null) 'gif_url': message['gif_url'],
      };

      await SupabaseConfig.client.from('messages').insert(msgForCloud);

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

  Future<void> initialSyncFromCloud(String tableId) async {
    try {
      final cloudMessages = await SupabaseConfig.client
          .from('messages')
          .select()
          .eq('table_id', tableId)
          .order('timestamp', ascending: true);

      if (cloudMessages.isEmpty) return;

      final localMessages = cloudMessages.map((msg) {
        return {
          'id': msg['id'],
          'table_id': msg['table_id'],
          'sender_id': msg['sender_id'],
          'sender_name': msg['sender_name'],
          'content': msg['content'],
          'timestamp': DateTime.parse(msg['timestamp']).millisecondsSinceEpoch,
          'reply_to_id': msg['reply_to_id'],
          'message_type': msg['content_type'] ?? 'text',
          'gif_url': msg['gif_url'],
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

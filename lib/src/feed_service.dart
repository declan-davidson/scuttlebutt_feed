import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'feed_message.dart';

class FeedService{
  static Future<Database> _createOrOpenDatabase() async {
    return openDatabase(
      join(await getDatabasesPath(), "peer_messages.db"),
      version: 1,
      onCreate: (db, version) {
        db.execute("PRAGMA foreign_keys = ON");
        db.execute("CREATE TABLE peers(identity VARCHAR PRIMARY KEY, hops INTEGER NOT NULL)");
        db.execute("CREATE TABLE messages(id VARCHAR PRIMARY KEY, previous VARCHAR, hash VARCHAR, author VARCHAR, sequence INTEGER, timestamp INTEGER, json_content VARCHAR, signature VARCHAR, likes INTEGER)"); 
        return db.execute("create table follows(follower VARCHAR, followee VARCHAR, FOREIGN key(follower) references peers(identity), FOREIGN key(followee) REFERENCES peers(identity))");
      },
      onConfigure: (db) { db.execute("PRAGMA foreign_keys = ON"); }
    );
  }

  static Future<void> postMessage(String body, String identity, String encodedSk) async {
    try{
      Database database = await _createOrOpenDatabase();
      dynamic previous = null;
      int sequence = 1;
      Map<String, dynamic> content = { "type": "post", "content": body };
      

      List<Map<String, Object?>> mappedPreviousMessage = await database.rawQuery('select * from messages where author = "$identity" order by sequence desc limit 1');
      if(mappedPreviousMessage.isNotEmpty){
        FeedMessage previousMessage = FeedMessage.fromRetrievedMessage(mappedPreviousMessage[0]);
        previous = previousMessage.id;
        sequence = previousMessage.sequence + 1;
      }

      FeedMessage message = FeedMessage.fromMessageToPostData(previous, identity, sequence, content, encodedSk);
      await _storeMessage(message);
      //database.close();
    }
    on Exception {
      rethrow;
    }
  }

  static Future<void> likeMessage(String messageId) async {
    try{
      Database database = await _createOrOpenDatabase();
      await database.rawUpdate('UPDATE messages SET likes = likes + 1 WHERE id = "$messageId"');
    }
    on Exception {
      rethrow;
    }
  }

  static void receiveMessage(Map<String, dynamic> receivedMessage){
    FeedMessage message = FeedMessage.fromReceivedMessage(receivedMessage);
    _storeMessage(message);
  }

  static Future<void> _storeMessage(FeedMessage message) async {
    try{
      Database database = await _createOrOpenDatabase();

      if(message.verifySignature()){

        //If the message is a follow, we need to take account of that and update our hops to the followee if necessary. Need to think about how to handle this when WE follow people
        if(message.content["type"] == "contact"){

          //If the peer has been newly-followed
          if(message.content["following"]){
            await database.rawInsert('insert into follows(follower, followee) values("${message.author}", "${message.content["contact"]}")');
          }
          //If the peer has been unfollowed
          else{
            await database.rawDelete('delete from follows where follower = "${message.author}" and followee = "${message.content["contact"]}"');
          }

          //Update hops
          List<Map<String, Object?>> map = await database.rawQuery('select hops from follows inner join peers on peers.identity = follows.follower where followee = "${message.content["contact"]}" order by hops asc limit 1'); //Obtains lowest hop distance of all followers of this followee
          int authorHops = map[0]["hops"] as int;

          await database.execute('insert into peers(identity, hops) values("${message.content["contact"]}", ${authorHops + 1}) on CONFLICT(identity) DO update set hops = ${authorHops + 1}');
        }

        await database.insert("messages", message.toMapForDatabaseInsertion(), conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      //database.close();
    }
    on Exception {
      rethrow;
    }
  }

  static Future<List<FeedMessage>> retrieveMessages({ required String identity, int? hops, int? sequence, int? limit } /* We may have more parameters here in future */) async {
    List<FeedMessage> messages = [];
    String query = 'select * from messages left outer join peers on messages.author = peers.identity where messages.author = "$identity"';
    if(hops != null) query += ' or peers.hops <= $hops';
    if(sequence != null) query += ' and messages.sequence > $sequence';
    query += ' order by timestamp asc'; //To fulfil requirement of limit to return the EARLIEST x messages
    if(limit != null) query += ' limit $limit';

    try{
      Database database = await _createOrOpenDatabase();
      
      //List<Map<String, Object?>> mappedMessages = await database.rawQuery(query);
      List<Map<String, Object?>> mappedMessages = await database.rawQuery("select * from messages order by timestamp asc");

      for(Map<String, Object?> message in mappedMessages){
        messages.insert(0, FeedMessage.fromRetrievedMessage(message)); //To attain descending order
      }

      //database.close();
      return messages;
    }
    on Exception{
      rethrow;
    }
  }
}
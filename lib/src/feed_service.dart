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
        db.execute("CREATE TABLE messages(id VARCHAR PRIMARY KEY, previous VARCHAR, author VARCHAR, sequence INTEGER, timestamp INTEGER, content VARCHAR, signature VARCHAR, FOREIGN KEY(author) references peers(identity))"); 
        db.execute("create table follows(follower VARCHAR, followee VARCHAR, FOREIGN key(follower) references peers(identity), FOREIGN key(followee) REFERENCES peers(identity))");
      },
      onConfigure: (db) { db.execute("PRAGMA foreign_keys = ON"); }
    );
  }

  static Future<void> postMessage(String body, String identity, String encodedSk) async {
    Database database = await _createOrOpenDatabase();
    dynamic previous = null;
    int sequence = 0;
    Map<String, dynamic> content = { "type": "post", "content": body };
    

    List<Map<String, Object?>> mappedPreviousMessage = await database.rawQuery('select * from messages where author = "$identity" order by sequence desc limit 1');
    if(mappedPreviousMessage.isNotEmpty){
      FeedMessage previousMessage = FeedMessage.fromRetrievedMessage(mappedPreviousMessage[0]);
      previous = previousMessage.id;
      sequence = previousMessage.sequence + 1;
    }

    FeedMessage message = FeedMessage.fromMessageToPostData(previous, identity, sequence, content, encodedSk);
    _storeMessage(message);
    //database.close();
  }

  static void receiveMessage(String jsonMessage){
    FeedMessage message = FeedMessage.fromReceivedMessage(jsonMessage);
    _storeMessage(message);
  }

  static void _storeMessage(FeedMessage message) async {
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

        await database.execute("insert into peers(identity, hops) values(${message.content["contact"]}, ${authorHops + 1}) on CONFLICT(identity) DO update set hops = ${authorHops + 1}");
      }

      database.insert("messages", message.toFullMap());
    }

    //database.close();
  }

  static Future<List<FeedMessage>> retrieveMessages({ required String identity, int hops = 2 } /* We may have more parameters here in future */) async {
    List<FeedMessage> messages = [];
    Database database = await _createOrOpenDatabase();
    
    List<Map<String, Object?>> mappedMessages = await database.rawQuery('select * from messages inner join peers on messages.author = peers.identity where author = "$identity" or peers.hops < 3 order by timestamp desc');

    for(Map<String, Object?> message in mappedMessages){
      messages.add(FeedMessage.fromRetrievedMessage(message));
    }

    //database.close();
    return messages;
  }
}
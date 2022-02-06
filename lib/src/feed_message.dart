import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_sodium/flutter_sodium.dart';
import 'package:crypto/crypto.dart' show sha256;

class FeedMessage{
  late dynamic previous;
  late String author; //base64-encoded
  final String hash = "sha256";
  late int sequence;
  late dynamic timestamp;
  late Map content;
  late String signature;
  late String id;

/*   FeedMessage(this.previous, this.author, this.sequence, this.content, { required Uint8List secretKey }){
    sign(secretKey);
    _generateId();
  } */

  FeedMessage.fromRetrievedMessage(Map<String, dynamic> mappedMessage){
    try{
      previous = mappedMessage["previous"];
      author = mappedMessage["author"];
      sequence = mappedMessage["sequence"];
      timestamp = mappedMessage["timestamp"];
      content = mappedMessage["content"];
      signature = mappedMessage["signature"];
      id = mappedMessage["id"];
    }
    on Exception{
      rethrow;
    }
  }

  FeedMessage.fromMessageToPostData(this.previous, this.author, this.sequence, this.content, String encodedSk) : timestamp = "strftime('%s','now')" {
    Uint8List sk = base64Decode(encodedSk);
    _sign(sk);
  }

  factory FeedMessage.fromReceivedMessage(String jsonMessage){
    Map<String, dynamic> mappedMessage = jsonDecode(jsonMessage);
    return FeedMessage._fromMap(mappedMessage);
  }

  FeedMessage._fromMap(Map<String, dynamic> mappedMessage):
    previous = mappedMessage["previous"],
    author = mappedMessage["author"],
    sequence = mappedMessage["sequence"],
    timestamp = mappedMessage["timestamp"],
    content = mappedMessage["content"],
    signature = mappedMessage["signature"];

  Map<String, dynamic> toMap(){
    return {
      "previous": previous,
      "author": author,
      "sequence": sequence,
      "timestamp": timestamp,
      "hash": hash,
      "content": content,
      "signature": signature
    };
  }

  Map<String, dynamic> toFullMap(){
    Map<String, dynamic> map = toMap();
    map["id"] = _generateId();
    return map;
  }

  Map<String, dynamic> toSignaturelessMap(){
    return {
      "previous": previous,
      "author": author,
      "sequence": sequence,
      "timestamp": timestamp,
      "hash": hash,
      "content": content
    };
  }

  String toJson(){
    return jsonEncode(toMap());
  }

  String toSignaturelessJson(){
    return jsonEncode(toSignaturelessMap());
  }

  void _sign(Uint8List secretKey){
    String jsonMessage = toSignaturelessJson();
    Uint8List signature = Sodium.cryptoSignDetached(Uint8List.fromList(jsonMessage.codeUnits), secretKey);

    String stringifiedSignature = base64Encode(signature);
    this.signature = stringifiedSignature + ".sig.ed25519";
  }

  bool verifySignature(){
    String jsonMessage = toSignaturelessJson();
    Uint8List messageBytes = Uint8List.fromList(jsonMessage.codeUnits);
    Uint8List signatureBytes = _decodeSignature();
    Uint8List authorBytes = _decodeAuthor();

    return Sodium.cryptoSignVerifyDetached(signatureBytes, messageBytes, authorBytes) == 0 ? true : false;
  }

  String _generateId(){
    List<int> hash = sha256.convert(toJson().codeUnits).bytes;
    id = base64Encode(hash) + ".sha256";
    return id;
  }

  Uint8List _decodeSignature(){
    String preparedSig = signature.substring(0, signature.length - 12);
    return base64Decode(preparedSig);
  }

  Uint8List _decodeAuthor(){
    String preparedAuthor = author.substring(1, author.length - 8);
    return base64Decode(preparedAuthor);
  }
}
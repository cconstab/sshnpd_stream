import 'dart:isolate';


void main() {
 createIsolate();
}



Future createIsolate() async {
 /// Where I listen to the message from Mike's port
 ReceivePort myReceivePort = ReceivePort(); 
 /// Spawn an isolate, passing my receivePort sendPort
 Isolate.spawn<SendPort>(heavyComputationTask, myReceivePort.sendPort); 
 /// Mike sends a senderPort for me to enable me to send him a message via his sendPort.
 
 // I receive Mike's senderPort via my receivePort
 SendPort mikeSendPort = await myReceivePort.first; 
 /// I set up another receivePort to receive Mike's response.
 ReceivePort mikeResponseReceivePort = ReceivePort(); 
 /// I send Mike a message using mikeSendPort. I send him a list,
 /// which includes my message, preferred type of coffee, and finally
 /// a sendPort from mikeResponseReceivePort that enables Mike to send a message back to me.
 
 
 mikeSendPort.send([
   "Mike, I'm taking an Espresso coffee",
   "Espresso",
   mikeResponseReceivePort.sendPort
 ]); 
 
 /// I get Mike's response by listening to mikeResponseReceivePort
 final mikeResponse = await mikeResponseReceivePort.first;
 print("MIKE'S RESPONSE: ==== $mikeResponse");
}


void heavyComputationTask(SendPort mySendPort) async {
 /// Set up a receiver port for Mike
 ReceivePort mikeReceivePort = ReceivePort(); /// Send Mike receivePort sendPort via mySendPort
 mySendPort.send(mikeReceivePort.sendPort); /// Listen to messages sent to Mike's receive port
 await for (var message in mikeReceivePort) {
   if (message is List) {
     final myMessage = message[0];
     final coffeeType = message[1];
     print(myMessage + coffeeType);     /// Get Mike's response sendPort
     final SendPort mikeResponseSendPort = message[2];     /// Send Mike's response via mikeResponseSendPort
     mikeResponseSendPort.send("You're taking $coffeeType, and I'm taking Latte");
   }
 }
}
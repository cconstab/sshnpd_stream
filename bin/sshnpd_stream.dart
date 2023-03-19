import 'dart:io';
import 'dart:isolate';

import 'package:socket_connector/socket_connector.dart';

void main(List<String> arguments) async {
  int portA = 8000;
  int portB = 9000;

  List a = await connectSpawn(portA, portB);
  print(a.toString());

  portA = 0;
  portB = 0;
  int count = 0;
  while (count < 100) {
    a = await connectSpawn(portA, portB);
    print(a.toString());
    count++;
  }

  print('sleep');
  await Future.delayed(Duration(seconds: 4000));
}

Future<List<int>> connectSpawn(int portA, int portB) async {
  /// Spawn an isolate, passing my receivePort sendPort

  ReceivePort myReceivePort = ReceivePort();
  Isolate.spawn<SendPort>(connect, myReceivePort.sendPort);

  SendPort mySendPort = await myReceivePort.first;

  myReceivePort = ReceivePort();
  mySendPort.send([portA, portB, myReceivePort.sendPort]);

  List message = await myReceivePort.first as List;

  portA = message[0];
  portB = message[1];

  return ([portA, portB]);
}

Future<void> connect(SendPort mySendPort) async {
  int portA = 0;
  int portB = 0;
  ReceivePort myReceivePort = ReceivePort();
  mySendPort.send(myReceivePort.sendPort);

  List message = await myReceivePort.first as List;
  portA = message[0];
  portB = message[1];
  mySendPort = message[2];

  SocketConnector socketStream = await SocketConnector.serverToServer(
    serverAddressA: InternetAddress.anyIPv4,
    serverAddressB: InternetAddress.anyIPv4,
    serverPortA: portA,
    serverPortB: portB,
    verbose: true,
  );

  portA = socketStream.senderPort()!;
  portB = socketStream.receiverPort()!;

  /// Send Mike's response via mikeResponseSendPort
  mySendPort.send([portA, portB]);

  // await Future.delayed(Duration(seconds: 10));
  bool closed = false;
  while (closed == false) {
    closed = await socketStream.closed();
  }
  print('Ports $portA & $portB closed');
}

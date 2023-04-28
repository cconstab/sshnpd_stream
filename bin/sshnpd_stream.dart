// dart packages
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

// atPlatform packages
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

// external packages
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_connector/socket_connector.dart';
import 'package:version/version.dart';

// local packages
import 'package:sshnpd_stream/service_factories.dart';
import 'package:sshnpd_stream/version.dart';
import 'package:sshnpd_stream/home_directory.dart';
import 'package:sshnpd_stream/check_file_exists.dart';

void main(List<String> args) async {
  final AtSignLogger logger = AtSignLogger(' sshnp ');
  logger.hierarchicalLoggingEnabled = true;
  logger.logger.level = Level.SHOUT;

  var uuid = Uuid();
  //String sessionId = uuid.v4();
  String atSign = 'unknown';
  String? homeDirectory = getHomeDirectory();
  dynamic results;
  String atsignFile;
  String ipAddress;
  String nameSpace = 'stream';

  // Get the command line arguments to fill in the details
  var parser = ArgParser();
  // Basic arguments
  parser.addOption('key-file',
      abbr: 'k', mandatory: false, help: 'Sending atSign\'s atKeys file if not in ~/.atsign/keys/');
  parser.addOption('atsign', abbr: 'a', mandatory: true, help: 'atSign for service');
  parser.addOption('ip', abbr: 'i', mandatory: true, help: 'IP address to send to clients');
  parser.addFlag('verbose', abbr: 'v', help: 'More logging');

  try {
    // Arg check
    results = parser.parse(args);
    // Find atSign key file
    atSign = results['atsign'];
    ipAddress = results['ip'];
    if (results['key-file'] != null) {
      atsignFile = results['key-file'];
    } else {
      atsignFile = '${atSign}_key.atKeys';
      atsignFile = '$homeDirectory/.atsign/keys/$atsignFile';
    }
    // Check atKeyFile selected exists
    if (!await fileExists(atsignFile)) {
      throw ('\n Unable to find .atKeys file : $atsignFile');
    }

    // Add a namespace separator just cause its neater.
  } catch (e) {
    version();
    stdout.writeln(parser.usage);
    stderr.writeln(e);
    exit(1);
  }

  // Loging setup
  // Now on to the atPlatform startup
  AtSignLogger.root_level = 'WARNING';
  logger.logger.level = Level.WARNING;
  if (results['verbose']) {
    logger.logger.level = Level.INFO;

    AtSignLogger.root_level = 'INFO';
  }

    AtServiceFactory? atServiceFactory;

    atServiceFactory = ServiceFactoryWithNoOpSyncService();


  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    //..qrCodePath = '<location of image>'
    ..hiveStoragePath = '$homeDirectory/.stream/$atSign/storage'
    ..namespace = nameSpace
    ..downloadPath = '$homeDirectory/.stream/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = '$homeDirectory/.stream/$atSign/storage/commitLog'
    ..fetchOfflineNotifications = false
    //..cramSecret = '<your cram secret>';
    ..atKeysFilePath = atsignFile
    ..atProtocolEmitted = Version(2, 0, 0);

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(atSign, atOnboardingConfig,atServiceFactory: atServiceFactory);

  await onboardingService.authenticate();

  var atClient = AtClientManager.getInstance().atClient;

  NotificationService notificationService = atClient.notificationService;

  // bool syncComplete = false;
  // void onSyncDone(syncResult) {
  //   logger.info("syncResult.syncStatus: ${syncResult.syncStatus}");
  //   logger.info("syncResult.lastSyncedOn ${syncResult.lastSyncedOn}");
  //   syncComplete = true;
  // }

  // // Wait for initial sync to complete
  // logger.info("Waiting for initial sync");
  // syncComplete = false;
  // // ignore: deprecated_member_use
  // atClient.syncService.sync(onDone: onSyncDone);
  // while (!syncComplete) {
  //   await Future.delayed(Duration(milliseconds: 100));
  // }
  // logger.info("Initial sync complete");

  notificationService.subscribe(regex: 'stream@', shouldDecrypt: true).listen(((notification) async {
    print(notification.key);
    if (notification.key.contains('stream')) {
      var ports = await connectSpawn(0, 0);

      logger.warning('Setting stream session ${notification.value} for ${notification.from} using ports $ports');
      var metaData = Metadata()
        ..isPublic = false
        ..isEncrypted = true
        ..ttl = 10000
        ..namespaceAware = true;

      var atKey = AtKey()
        ..key = notification.value
        ..sharedBy = atSign
        ..sharedWith = notification.from
        ..namespace = nameSpace
        ..metadata = metaData;

      String data = '$ipAddress,${ports[0]},${ports[1]}';
      print(atKey.toString());
      print(data);
      try {
        await atClient.put(atKey, data);
      } catch (e) {
        stderr.writeln("Error writting session ${notification.value} atKey");
      }
    } else {
      stderr.writeln('Unknown error: ${notification.value}');
    }
  }));
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

  mySendPort.send([portA, portB]);

  // await Future.delayed(Duration(seconds: 10));
  bool closed = false;
  while (closed == false) {
    closed = await socketStream.closed();
  }
  print('Ports $portA & $portB closed');
}

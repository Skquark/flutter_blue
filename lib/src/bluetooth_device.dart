// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of flutter_blue;

class BluetoothDevice {
  final DeviceIdentifier id;
  final String name;
  final BluetoothDeviceType type;

  BluetoothDevice.fromProto(protos.BluetoothDevice p)
      : id = new DeviceIdentifier(p.remoteId),
        name = p.name,
        type = BluetoothDeviceType.values[p.type.value];

  /// Creates a BluetoothDevice with a predefined device ID. Be aware that the
  /// device ID could change anytime so the proper way is to scan for the
  /// device first. This constructor is created for a workaround to be able to
  /// reconnect on Android to devices which has still an unreleased connection
  /// with the phone after app restart.
  BluetoothDevice.fromDeviceId(String deviceId)
      : id = new DeviceIdentifier(deviceId),
        name = deviceId,
        type = BluetoothDeviceType.unknown;

  BehaviorSubject<bool> _isDiscoveringServices = BehaviorSubject.seeded(false);
  Stream<bool> get isDiscoveringServices => _isDiscoveringServices.stream;

  /// Establishes a connection to the Bluetooth Device.
  Future<BluetoothDeviceState> connect({
    Duration? timeout,
    bool autoConnect = true,
  }) async {
    var request = protos.ConnectRequest.create()
      ..remoteId = id.toString()
      ..androidAutoConnect = autoConnect;

    //final res = await state.firstWhere((s) => s.state == BluetoothDeviceStateEnum.connected);
    final nextStateCompleter = Completer<BluetoothDeviceState>();
    var firsStateArrived = false;

    final stateSubscription = state.listen(
      null,
    );

    stateSubscription.onError((err) {
      stateSubscription.cancel();
      nextStateCompleter.completeError(err);
    });
    stateSubscription.onData((state) {
      if (firsStateArrived &&
          (state is BluetoothDeviceConnected ||
              state is BluetoothDeviceDisconnected)) {
        stateSubscription.cancel();
        nextStateCompleter.complete(state);
        return;
      }
      firsStateArrived = true;
    });

    await FlutterBlue.instance._channel
        .invokeMethod('connect', request.writeToBuffer());

    return nextStateCompleter.future;
  }

  /// Cancels connection to the Bluetooth Device
  Future<BluetoothDeviceState> disconnect(Duration? timeout) async {
    final stateCompleter =
        state.firstWhere((state) => state is BluetoothDeviceDisconnected);

    await FlutterBlue.instance._channel
        .invokeMethod('disconnect', id.toString());

    if (timeout != null) {
      return await stateCompleter.timeout(timeout);
    } else {
      return await stateCompleter;
    }
  }

  /* implementation not finished and this is not available on iOS
  Future<void> createBond() async {
    var request = protos.ConnectRequest.create()
      ..remoteId = id.toString()
      ..androidAutoConnect = false;

    await FlutterBlue.instance._channel
        .invokeMethod('createBond', request.writeToBuffer());
  }
   */

  BehaviorSubject<List<BluetoothService>> _services =
      BehaviorSubject.seeded([]);

  /// Discovers services offered by the remote device as well as their characteristics and descriptors
  Future<List<BluetoothService>> discoverServices() async {
    final s = await state.first;
    if (s is! BluetoothDeviceConnected) {
      return Future.error(new Exception(
          'Cannot discoverServices while device is not connected. State == $s'));
    }
    var response = FlutterBlue.instance._methodStream
        .where((m) => m.method == "DiscoverServicesResult")
        .map((m) => m.arguments)
        .map((buffer) => new protos.DiscoverServicesResult.fromBuffer(buffer))
        .where((p) => p.remoteId == id.toString())
        .map((p) => p.services)
        .map((s) => s.map((p) => new BluetoothService.fromProto(p)).toList())
        .first
        .then((list) {
      _services.add(list);
      _isDiscoveringServices.add(false);
      return list;
    });

    await FlutterBlue.instance._channel
        .invokeMethod('discoverServices', id.toString());

    _isDiscoveringServices.add(true);

    return response;
  }

  /// Returns a list of Bluetooth GATT services offered by the remote device
  /// This function requires that discoverServices has been completed for this device
  Stream<List<BluetoothService>> get services async* {
    yield await FlutterBlue.instance._channel
        .invokeMethod('services', id.toString())
        .then((buffer) =>
            new protos.DiscoverServicesResult.fromBuffer(buffer).services)
        .then((i) => i.map((s) => new BluetoothService.fromProto(s)).toList());
    yield* _services.stream;
  }

  /// The current connection state of the device
  Stream<BluetoothDeviceState> get state async* {
    yield await FlutterBlue.instance._channel
        .invokeMethod('deviceState', id.toString())
        .then((buffer) => new protos.DeviceStateResponse.fromBuffer(buffer))
        .then((p) => BluetoothDeviceState.fromId(
            p.state.value, BluetoothStatusCode.fromId(p.status)));

    yield* FlutterBlue.instance._methodStream
        .where((m) => m.method == "DeviceState")
        .map((m) => m.arguments)
        .map((buffer) => new protos.DeviceStateResponse.fromBuffer(buffer))
        .where((p) => p.remoteId == id.toString())
        .map((p) => BluetoothDeviceState.fromId(
            p.state.value, BluetoothStatusCode.fromId(p.status)));
  }

  /// The MTU size in bytes
  Stream<int> get mtu async* {
    yield await FlutterBlue.instance._channel
        .invokeMethod('mtu', id.toString())
        .then((buffer) => new protos.MtuSizeResponse.fromBuffer(buffer))
        .then((p) => p.mtu);

    yield* FlutterBlue.instance._methodStream
        .where((m) => m.method == "MtuSize")
        .map((m) => m.arguments)
        .map((buffer) => new protos.MtuSizeResponse.fromBuffer(buffer))
        .where((p) => p.remoteId == id.toString())
        .map((p) => p.mtu);
  }

  /// Request to change the MTU Size
  /// Throws error if request did not complete successfully
  Future<void> requestMtu(int desiredMtu) async {
    var request = protos.MtuSizeRequest.create()
      ..remoteId = id.toString()
      ..mtu = desiredMtu;

    return FlutterBlue.instance._channel
        .invokeMethod('requestMtu', request.writeToBuffer());
  }

  Future<int> readRemoteRSSI() async {
    final rssiGetResult = await FlutterBlue.instance._channel
        .invokeMethod('readRemoteRSSI', id.toString());
    if (!rssiGetResult) {
      throw Error();
    }

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == 'onReadRemoteRssi')
        .map((m) => m.arguments)
        .map((buffer) => protos.RSSIResponse.fromBuffer(buffer))
        .where((p) => p.remoteId == id.toString())
        .map((p) => p.rssi)
        .first;
  }

  /// Indicates whether the Bluetooth Device can send a write without response
  Future<bool> get canSendWriteWithoutResponse =>
      new Future.error(new UnimplementedError());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'BluetoothDevice{id: $id, name: $name, type: $type, isDiscoveringServices: ${_isDiscoveringServices.value}, _services: ${_services.value}';
  }
}

enum BluetoothDeviceType { unknown, classic, le, dual }

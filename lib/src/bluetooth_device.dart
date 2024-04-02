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

  Timer? _connectTimeoutTimer;
  StreamSubscription<BluetoothDeviceState>? _stateSubscription;
  Completer<BluetoothDeviceState>? _connectCompleter;
  BluetoothDeviceState? _lastState;

  void killPendingConnection() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    if (_connectCompleter != null) {
      if (!(_connectCompleter!.isCompleted)) {
        return _connectCompleter!.completeError(
          Exception('BLE pending connection killed'),
        );
      }
    }
  }

  /// Establishes a connection to the Bluetooth Device.
  Future<BluetoothDeviceState> connect({
    Duration? timeout,
    bool autoConnect = true,
  }) async {
    var request = protos.ConnectRequest.create()
      ..remoteId = id.toString()
      ..androidAutoConnect = autoConnect;

    // if we have a running connect process, return with the future
    if (_connectCompleter != null) {
      if (!(_connectCompleter!.isCompleted)) {
        return _connectCompleter!.future;
      }
    }

    // if we are connected return with the last state
    if (_lastState != null && _lastState is BluetoothDeviceConnected) {
      return _lastState!;
    }

    // else start a new connect process
    _connectCompleter = Completer<BluetoothDeviceState>();
    // this 2 call shouldn't be necessary so test it without them??
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    _stateSubscription?.cancel();
    _stateSubscription = null;

    var firsStateArrived = false;
    _stateSubscription = state.listen((state) {
      if (firsStateArrived &&
          (state is BluetoothDeviceConnected ||
              state is BluetoothDeviceDisconnected)) {
        _connectTimeoutTimer?.cancel();
        _stateSubscription!.cancel();
        _stateSubscription = null;
        _connectCompleter!.complete(state);
        _connectCompleter = null;
        return;
      }
      firsStateArrived = true;
    }, onError: (err) {
      _connectTimeoutTimer?.cancel();
      _stateSubscription!.cancel();
      _stateSubscription = null;
      _connectCompleter!.completeError(err);
      _connectCompleter = null;
    });

    if (timeout != null) {
      _connectTimeoutTimer = Timer(timeout, () {
        _stateSubscription?.cancel();
        _connectCompleter!.completeError(TimeoutException('BLE connect'));
        _connectCompleter = null;
      });
    }

    final returnFuture = _connectCompleter!.future;

    await FlutterBlue.instance._channel
        .invokeMethod('connect', request.writeToBuffer());

    return returnFuture;
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
        .then((p) {
      _lastState = BluetoothDeviceState.fromId(
          p.state.value, BluetoothStatusCode.fromId(p.status));
      return _lastState!;
    });

    yield* FlutterBlue.instance._methodStream
        .where((m) => m.method == "DeviceState")
        .map((m) => m.arguments)
        .map((buffer) => new protos.DeviceStateResponse.fromBuffer(buffer))
        .where((p) => p.remoteId == id.toString())
        .map((p) {
      _lastState = BluetoothDeviceState.fromId(
          p.state.value, BluetoothStatusCode.fromId(p.status));
      return _lastState!;
    });
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

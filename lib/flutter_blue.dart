// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library flutter_blue;

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'gen/flutterblue.pb.dart' as protos;

part 'src/bluetooth_status_code.dart';
part 'src/bluetooth_device_state.dart';
part 'src/bluetooth_characteristic.dart';
part 'src/bluetooth_descriptor.dart';
part 'src/bluetooth_device.dart';
part 'src/bluetooth_service.dart';
part 'src/constants.dart';
part 'src/flutter_blue.dart';
part 'src/guid.dart';
part 'src/advertising_mode.dart';
part 'src/advertising_tx_power.dart';

import 'dart:io';

import 'package:event/event.dart';
import 'package:pikapika/basic/Method.dart';

import '../Entities.dart';

/// Windows 本地版本启用会员功能，不修改渠道会员记录。
bool get isLocalProEnabled => Platform.isWindows;

bool get isPro {
  return isLocalProEnabled ||
      _proInfoAll.proInfoAf.isPro ||
      _proInfoAll.proInfoPat.isPro;
}

ProInfoAf get proInfoAf => _proInfoAll.proInfoAf;
ProInfoPat get proInfoPat => _proInfoAll.proInfoPat;

final proEvent = Event();
late ProInfoAll _proInfoAll;

Future reloadIsPro() async {
  _proInfoAll = await method.proInfoAll();
  proEvent.broadcast();
}

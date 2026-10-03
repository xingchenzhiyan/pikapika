import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pikapika/basic/Entities.dart';
import 'package:pikapika/basic/config/EBookScrolling.dart';
import 'package:pikapika/basic/config/IsPro.dart';
import 'package:pikapika/basic/config/ListLayout.dart';
import 'package:pikapika/basic/enum/Sort.dart';
import 'package:pikapika/i18.dart';
import 'package:pikapika/screens/ProScreen.dart';
import 'package:pikapika/screens/components/ComicPager.dart';

Map<String, dynamic> membership(bool af, bool pat) => {
      'pro_info_af': {'is_pro': af, 'expire': 1},
      'pro_info_pat': {
        'is_pro': pat,
        'pat_id': '',
        'bind_uid': '',
        'request_delete': 0,
        're_bind': 0,
        'error_type': 0,
        'error_msg': '',
        'access_key': '',
      },
    };

ComicsPage page(int number) => ComicsPage.fromJson({
      'docs': [],
      'total': 12,
      'limit': 1,
      'page': number,
      'pages': 12,
    });

Future<void> jump(WidgetTester tester, String label, int number) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '$number');
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

Future<void> loadNext(WidgetTester tester) async {
  final list = tester.widget<ListView>(find.byType(ListView));
  // 空内容的模拟响应仍可触发分页，无需加载远程封面。
  list.controller!.position.notifyListeners();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var remoteMembership = membership(false, false);
  const channel = MethodChannel('method');

  setUpAll(loadTranslations);
  setUp(() async {
    remoteMembership = membership(false, false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      switch (args['method']) {
        case 'proInfoAll':
          return jsonEncode(remoteMembership);
        case 'loadProperty':
          return (jsonDecode(args['params'] as String) as Map)['defaultValue'];
        case 'getUsername':
          return 'test-account';
        default:
          throw StateError('Unexpected method: ${args['method']}');
      }
    });
    currentLayout = ListLayout.INFO_CARD;
    await initEBookScrolling();
    await reloadIsPro();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('有效会员状态保留平台规则及真实渠道信息', () async {
    expect(isLocalProEnabled, Platform.isWindows);
    for (final af in [false, true]) {
      for (final pat in [false, true]) {
        remoteMembership = membership(af, pat);
        await reloadIsPro();
        expect(isPro, Platform.isWindows || af || pat);
        expect(proInfoAf.isPro, af);
        expect(proInfoAf.expire, 1);
        expect(proInfoPat.isPro, pat);
        expect(proInfoPat.accessKey, isEmpty);
      }
    }
  });

  testWidgets('Windows 显示本地已发电和真实未发电渠道', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProScreen()));
    await tester.pumpAndSettle();
    expect(find.text('已发电（本地版本）'), findsOneWidget);
    expect(find.text('本地会员功能已启用'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('真实渠道会员信息'), findsOneWidget);
    expect(find.text('未发电'), findsNWidgets(2));
  }, skip: !Platform.isWindows);

  testWidgets('按钮分页的两个下一页入口及直接跳转均可超过10页', (tester) async {
    final requested = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: ControllerComicPager(
        coll: true,
        comicListController: null,
        fetchPage: (_, number) async {
          requested.add(number);
          return page(number);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await jump(tester, '第 1 / 12 页', 10);
    await tester.tap(find.text('下一页').first);
    await tester.pumpAndSettle();
    expect(requested.last, 11);
    await jump(tester, '第 11 / 12 页', 10);
    await tester.tap(find.text('下一页').last);
    await tester.pumpAndSettle();
    expect(requested.last, 11);
    await jump(tester, '第 11 / 12 页', 12);
    expect(requested.last, 12);
    await jump(tester, '第 12 / 12 页', 0);
    await jump(tester, '第 12 / 12 页', 13);
    expect(requested.last, 12);
    await tester.tap(find.text('上一页'));
    await tester.pumpAndSettle();
    expect(requested.last, 11);
  }, skip: !Platform.isWindows);

  testWidgets('瀑布流超过10页，到末页后可跳回并继续加载', (tester) async {
    final requested = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: StreamComicPager(
        coll: true,
        comicListController: null,
        fetchPage: (sort, number) async {
          expect([SORT_TIME_NEWEST, SORT_TIME_OLDEST], contains(sort));
          requested.add(number);
          return page(number);
        },
      ),
    ));
    await tester.pumpAndSettle();
    for (var i = 2; i <= 12; i++) {
      await loadNext(tester);
    }
    expect(requested, List.generate(12, (i) => i + 1));
    await loadNext(tester);
    expect(requested.length, 12);
    await jump(tester, '已经加载 12 / 12 页', 1);
    await loadNext(tester);
    expect(requested.sublist(12), [1, 2]);
    await jump(tester, '已经加载 2 / 12 页', 11);
    expect(requested.last, 11);
    await tester
        .tap(find.byWidgetPredicate((w) => w is DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LABEL_TIME_OLDEST).last);
    await tester.pumpAndSettle();
    expect(requested.last, 1);
    await loadNext(tester);
    expect(requested.last, 2);
  }, skip: !Platform.isWindows);

  testWidgets('瀑布流网络错误可重试当前页', (tester) async {
    var attempts = 0;
    final requested = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: StreamComicPager(
        coll: true,
        comicListController: null,
        fetchPage: (_, number) async {
          requested.add(number);
          if (attempts++ == 0) {
            return Future<ComicsPage>.error(
                Exception('network error'), StackTrace.empty);
          }
          return page(number);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网络错误 / 点击刷新'));
    await tester.pumpAndSettle();
    expect(requested, [1, 1]);
    expect(find.text('网络错误 / 点击刷新'), findsNothing);
  });

  testWidgets('切换排序忽略旧请求，退出页面忽略未完成请求', (tester) async {
    final pending = <Completer<ComicsPage>>[];
    await tester.pumpWidget(MaterialApp(
      home: StreamComicPager(
        coll: true,
        comicListController: null,
        fetchPage: (_, number) {
          final completer = Completer<ComicsPage>();
          pending.add(completer);
          return completer.future;
        },
      ),
    ));
    await tester.pump();
    await tester
        .tap(find.byWidgetPredicate((w) => w is DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LABEL_TIME_OLDEST).last);
    await tester.pumpAndSettle();
    pending[1].complete(page(1));
    await tester.pumpAndSettle();
    pending[0].complete(page(12));
    await tester.pumpAndSettle();
    expect(find.text('已经加载 1 / 12 页'), findsOneWidget);
    await loadNext(tester);
    await tester.pumpWidget(const SizedBox());
    pending[2].complete(page(2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

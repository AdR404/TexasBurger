import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:texas_burger/models/producto.dart';
import 'package:texas_burger/models/sale_context.dart';
import 'package:texas_burger/models/venta.dart';
import 'package:texas_burger/models/venta_item.dart';
import 'package:texas_burger/theme/app_theme.dart';
import 'package:texas_burger/widgets/ticket_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the application's real font metrics, not Flutter test's Ahem font.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((p) => p['name'] == 'flutter');
    final root = configFile.uri.resolve('${flutter['rootUri']}/');
    final font = File.fromUri(
      root.resolve(
        '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ),
    );
    await (FontLoader(
      'Roboto',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  });

  for (final width in [320.0, 360.0, 400.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'ticket at $width dp / text $scale aligns values and fits actions',
        (tester) async {
          tester.view.physicalSize = Size(width, 560);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          String? clipboard;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final code = scale == 1 ? 'Sí' : 'PROMOCIONCUPONCONNOMBRELARGO50';
          final sale = Venta(
            id: 'layout',
            ticketNumber: 12,
            items: [
              VentaItem(
                product: Producto(
                  id: 'burger',
                  name: 'HAMBURGUESA TEXANA ESPECIAL CON QUESO',
                  description: '',
                  price: 150,
                  category: 'Hamburguesas',
                ),
                quantity: 1,
                unitPrice: 150,
                notes: 'Sin cebolla, con salsa y servilletas adicionales',
              ),
            ],
            subtotal: 150,
            discount: 75,
            total: 75,
            iva: 10.34,
            ivaRate: 0.16,
            ivaIncluded: true,
            discountCode: code,
            paymentMethod: 'Efectivo',
            cashGiven: 100,
            changeReturned: 25,
            timestamp: DateTime(2026, 10, 26, 14, 30),
            saleContext: const SaleContext(
              branchId: 'norte',
              branchName: 'Sucursal Norte Plaza Principal',
              employeeId: 'sofia',
              employeeName: 'Sofía Reyes Hernández',
            ),
          );
          final original = sale.toJson();
          final theme = AppTheme.lightTheme;
          // Button theme styles omit fontFamily and otherwise use Ahem in tests.
          ButtonStyle androidFont(ButtonStyle style) => style.copyWith(
            textStyle: WidgetStateProperty.resolveWith(
              (states) => style.textStyle!
                  .resolve(states)!
                  .copyWith(fontFamily: 'Roboto'),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: androidFont(theme.outlinedButtonTheme.style!),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: androidFont(theme.elevatedButtonTheme.style!),
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => TicketDialog(venta: sale),
                    ),
                    child: const Text('Abrir ticket'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir ticket'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final values = [
            '\$150.00',
            '-\$75.00',
            code,
            '\$64.66',
            '\$10.34',
            '\$75.00',
          ];
          final rightEdge = tester.getRect(find.text('\$150.00').last).right;
          for (final value in values) {
            final finder = find.text(value).last;
            expect(finder, findsOneWidget);
            expect(
              tester.getRect(finder).right,
              closeTo(rightEdge, 0.01),
              reason: value,
            );
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            expect(paragraph.didExceedMaxLines, isFalse);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: value.length),
            );
            if (value != code) {
              expect(
                boxes.length,
                1,
                reason: 'Amount must stay on one line: $value',
              );
            }
            for (final box in boxes) {
              expect(box.left, greaterThanOrEqualTo(-1));
              expect(box.right, lessThanOrEqualTo(paragraph.size.width + 1));
            }
          }
          for (final label in [
            'Subtotal:',
            'Descuento / Promo:',
            'Código aplicado:',
            'Base sin IVA:',
            'IVA incluido (16%):',
            'Total:',
          ]) {
            expect(find.text(label), findsOneWidget);
            expect(
              tester.getRect(find.text(label)).left,
              closeTo(tester.getRect(find.text('Subtotal:')).left, 0.01),
            );
          }

          // Text may wrap, with one logical pixel allowed for glyph/letter-spacing overhang.
          for (final element
              in find
                  .descendant(
                    of: find.byType(TicketDialog),
                    matching: find.byType(RichText),
                  )
                  .evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            expect(paragraph.didExceedMaxLines, isFalse);
            final text = paragraph.text.toPlainText();
            for (var index = 0; index < text.length; index++) {
              // Selection boxes include trailing spaces after a wrapped line.
              if (text[index].trim().isEmpty) continue;
              for (final box in paragraph.getBoxesForSelection(
                TextSelection(baseOffset: index, extentOffset: index + 1),
              )) {
                expect(box.left, greaterThanOrEqualTo(-1), reason: text);
                expect(
                  box.right,
                  lessThanOrEqualTo(paragraph.size.width + 1),
                  reason: text,
                );
              }
            }
          }
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(TicketDialog),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(scrollable.position.maxScrollExtent, greaterThan(0));
          final whatsapp = find.widgetWithText(OutlinedButton, 'WhatsApp');
          final accept = find.widgetWithText(ElevatedButton, 'Aceptar');
          await tester.ensureVisible(whatsapp);
          await tester.pumpAndSettle();
          final whatsappRect = tester.getRect(whatsapp);
          final acceptRect = tester.getRect(accept);
          expect(whatsappRect.height, greaterThanOrEqualTo(48));
          expect(acceptRect.height, greaterThanOrEqualTo(48));
          if (width == 400 && scale == 1) {
            expect(whatsappRect.center.dy, closeTo(acceptRect.center.dy, 0.01));
          }
          if (scale == 2) {
            expect(acceptRect.top, greaterThanOrEqualTo(whatsappRect.bottom));
          }
          final whatsappText = tester.renderObject<RenderParagraph>(
            find.text('WhatsApp'),
          );
          final boxes = whatsappText.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 8),
          );
          expect(boxes.length, 1);
          expect(
            boxes.single.right,
            lessThanOrEqualTo(whatsappText.size.width + 1),
          );
          expect(
            tester.getRect(find.text('WhatsApp')).right,
            lessThan(whatsappRect.right),
          );
          expect(
            find.descendant(of: whatsapp, matching: find.byIcon(Icons.share)),
            findsOneWidget,
          );
          await tester.tap(whatsapp);
          await tester.pump();
          expect(clipboard, contains('Subtotal: \$150.00'));
          expect(clipboard, contains('Descuento: -\$75.00'));
          expect(clipboard, contains('Código: $code'));
          expect(clipboard, contains('Base sin IVA: \$64.66'));
          expect(clipboard, contains('IVA incluido (16%): \$10.34'));
          expect(clipboard, contains('Total: \$75.00'));
          expect(sale.toJson(), original);
          await tester.ensureVisible(accept);
          await tester.tap(accept);
          await tester.pumpAndSettle();
          expect(find.byType(TicketDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

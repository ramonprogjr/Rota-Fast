import 'package:flutter_test/flutter_test.dart';
import 'package:rota_pizza/core/utils/phone_utils.dart';

void main() {
  test('adiciona DDI 55 em celular com DDD', () {
    expect(PhoneUtils.toWhatsAppNumber('(11) 98888-1234'), '5511988881234');
    expect(PhoneUtils.whatsAppUrl('11988881234'), 'https://wa.me/5511988881234');
  });

  test('mantém número que já tem 55', () {
    expect(PhoneUtils.toWhatsAppNumber('+55 11 98888-1234'), '5511988881234');
  });

  test('rejeita número curto', () {
    expect(PhoneUtils.toWhatsAppNumber('123'), isNull);
    expect(PhoneUtils.telUrl('123'), isNull);
  });

  test('monta tel: com dígitos', () {
    expect(PhoneUtils.telUrl('(11) 3333-4444'), 'tel:1133334444');
  });
}

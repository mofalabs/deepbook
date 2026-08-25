import 'package:flutter_test/flutter_test.dart';
import 'package:deepbook/deepbook.dart';
// Conversion helpers are internal (not exported, matching the official SDK).
import 'package:deepbook/src/conversion.dart';

void main() {
  group('conversion', () {
    test('convertQuantity scales num and passes through BigInt', () {
      expect(convertQuantity(1.5, 1000000000), BigInt.from(1500000000));
      expect(convertQuantity(BigInt.from(42), 1000000000), BigInt.from(42));
      expect(convertQuantity(0.000001, 1000000), BigInt.one);
    });

    test('convertPrice uses the cross-scalar formula', () {
      // price 2.5 in a SUI(1e9)/DBUSDC(1e6) pool:
      // 2.5 * 1e9 * 1e6 / 1e9 = 2.5e6
      expect(
        convertPrice(2.5, FLOAT_SCALAR, 1000000, 1000000000),
        BigInt.from(2500000),
      );
      expect(convertPrice(BigInt.two, FLOAT_SCALAR, 1, 1), BigInt.two);
    });

    test('convertRate scales by FLOAT_SCALAR', () {
      expect(convertRate(0.001, FLOAT_SCALAR), BigInt.from(1000000));
    });
  });

  group('DeepBookConfig', () {
    test('testnet defaults resolve', () {
      final config = DeepBookConfig(network: 'testnet', address: '0x1');
      expect(config.DEEPBOOK_PACKAGE_ID,
          '0xd874d2417a55bfa6479bffa06ad950fea144ef93a94cc6c49f32b03e386bbb24');
      expect(config.getCoin('DEEP').scalar, 1000000);
      expect(config.getPool('SUI_DBUSDC').baseCoin, 'SUI');
      expect(config.getMarginPool('SUI').address, isNotEmpty);
      expect(config.pyth.pythStateId, isNotEmpty);
      expect(config.address,
          '0x0000000000000000000000000000000000000000000000000000000000000001');
    });

    test('mainnet defaults resolve', () {
      final config = DeepBookConfig(network: 'mainnet', address: '0x2');
      expect(config.getPool('SUI_USDC').quoteCoin, 'USDC');
      expect(config.getCoin('USDC').priceInfoObjectId, isNotNull);
    });

    test('unknown network without packageIds throws', () {
      expect(() => DeepBookConfig(network: 'devnet', address: '0x1'),
          throwsA(isA<ConfigurationError>()));
    });

    test('custom packageIds bypass built-ins', () {
      final config = DeepBookConfig(
        network: 'localnet',
        address: '0x1',
        packageIds: const DeepbookPackageIds(deepbookPackageId: '0xabc'),
      );
      expect(config.DEEPBOOK_PACKAGE_ID, '0xabc');
      expect(
          () => config.getCoin('SUI'), throwsA(isA<ResourceNotFoundError>()));
      expect(config.requirePyth, throwsA(isA<ConfigurationError>()));
    });

    test('missing resources throw typed errors', () {
      final config = DeepBookConfig(network: 'testnet', address: '0x1');
      expect(
          () => config.getPool('NOPE'), throwsA(isA<ResourceNotFoundError>()));
      expect(() => config.getBalanceManager('NOPE'),
          throwsA(isA<DeepBookError>()));
    });
  });
}

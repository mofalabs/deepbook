import 'package:sui/types/sui_bcs.dart';

final deepbookBCS = bcs..registerStructType('Order', {
  "orderId": 'u64',
  "clientOrderId": 'u64',
  "price": 'u64',
  "originalQuantity": 'u64',
  "quantity": 'u64',
  "isBid": 'bool',
  "owner": 'address',
  "expireTimestamp": 'u64',
  "selfMatchingPrevention": 'u8',
});
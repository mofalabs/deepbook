import 'package:sui/sui.dart';
import 'package:sui/types/common.dart';

const PACKAGE_ID = '0xdee9';

const MODULE_CLOB = 'clob_v2';

const MODULE_CUSTODIAN = 'custodian_v2';

const CREATION_FEE = 100000000000;

String NORMALIZED_SUI_COIN_TYPE = normalizeStructTagString(SUI_TYPE_ARG);

const ORDER_DEFAULT_EXPIRATION_IN_MS = 1000 * 60 * 60 * 24; // 24 hours

int FLOAT_SCALING_FACTOR = 1000000000;

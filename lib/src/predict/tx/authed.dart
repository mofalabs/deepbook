/// Owner-authorized single calls, mirroring `predict/tx/authed.ts`.
///
/// Every builder here expands to auth → call (the call consuming the
/// hot-potato `Auth` minted by `generate_auth`). The builder-code pair lives
/// in the PREDICT package's `predict_account` module, not the account
/// package.
library;

import '../../contracts/account/account.dart' as account;
import '../../contracts/deepbook_predict/plp.dart' as plp;
import '../../contracts/deepbook_predict/predict_account.dart'
    as predict_account;
import '../../contracts/utils.dart' show MoveCallBuilder;
import '../config.dart' show GeneratedConfig;
import 'common.dart' show withAuth;

/// `account::deposit_funds` with the auth slot already supplied. [coin] is a
/// transaction argument carrying a `Coin<coinType>`.
MoveCallBuilder depositFunds({
  required GeneratedConfig config,
  required dynamic wrapper,
  required dynamic coin,
  required List<String> typeArguments,
}) =>
    withAuth(
        config,
        (auth) => account.depositFunds(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth, 'coin': coin},
              typeArguments: typeArguments,
            ));

/// `account::withdraw_funds` with the auth slot already supplied; returns the
/// minted `Coin<T>` handle.
MoveCallBuilder withdrawFunds({
  required GeneratedConfig config,
  required dynamic wrapper,
  required BigInt amount,
  required List<String> typeArguments,
}) =>
    withAuth(
        config,
        (auth) => account.withdrawFunds(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth, 'amount': amount},
              typeArguments: typeArguments,
            ));

/// `plp::request_supply` with the auth slot already supplied.
MoveCallBuilder requestSupply({
  required GeneratedConfig config,
  required dynamic wrapper,
  required BigInt amount,
  required BigInt minPlpOut,
}) =>
    withAuth(
        config,
        (auth) => plp.requestSupply(
              config: config,
              arguments: {
                'wrapper': wrapper,
                'auth': auth,
                'amount': amount,
                'minPlpOut': minPlpOut,
              },
            ));

/// `plp::request_withdraw` with the auth slot already supplied. `amount`
/// counts PLP SHARES, not USDC.
MoveCallBuilder requestWithdraw({
  required GeneratedConfig config,
  required dynamic wrapper,
  required BigInt amount,
  required BigInt minUsdcOut,
}) =>
    withAuth(
        config,
        (auth) => plp.requestWithdraw(
              config: config,
              arguments: {
                'wrapper': wrapper,
                'auth': auth,
                'amount': amount,
                'minUsdcOut': minUsdcOut,
              },
            ));

/// `plp::cancel_supply_request` with the auth slot already supplied.
MoveCallBuilder cancelSupplyRequest({
  required GeneratedConfig config,
  required dynamic wrapper,
  required BigInt index,
}) =>
    withAuth(
        config,
        (auth) => plp.cancelSupplyRequest(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth, 'index': index},
            ));

/// `plp::cancel_withdraw_request` with the auth slot already supplied.
MoveCallBuilder cancelWithdrawRequest({
  required GeneratedConfig config,
  required dynamic wrapper,
  required BigInt index,
}) =>
    withAuth(
        config,
        (auth) => plp.cancelWithdrawRequest(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth, 'index': index},
            ));

/// `predict_account::set_builder_code` with the auth slot already supplied.
MoveCallBuilder setBuilderCode({
  required GeneratedConfig config,
  required dynamic wrapper,
  required dynamic code,
}) =>
    withAuth(
        config,
        (auth) => predict_account.setBuilderCode(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth, 'code': code},
            ));

/// `predict_account::unset_builder_code` with the auth slot already supplied.
MoveCallBuilder unsetBuilderCode({
  required GeneratedConfig config,
  required dynamic wrapper,
}) =>
    withAuth(
        config,
        (auth) => predict_account.unsetBuilderCode(
              config: config,
              arguments: {'wrapper': wrapper, 'auth': auth},
            ));

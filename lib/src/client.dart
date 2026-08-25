/// DeepBookClient facade, mirroring the official SDK's `client.ts`.
///
/// Composes all transaction contracts (public fields) and query classes
/// (private, forwarded through one-line methods). Unlike the TS SDK there is
/// no client-extension mechanism: construct a [DeepBookClient] directly with
/// a [GrpcCoreClient].
library;

import 'package:sui/sui.dart' show GrpcCoreClient, Transaction;

import 'config.dart';
import 'constants.dart';
import 'queries/account_queries.dart';
import 'queries/balance_manager_queries.dart';
import 'queries/margin_manager_queries.dart';
import 'queries/margin_pool_queries.dart';
import 'queries/order_queries.dart';
import 'queries/pool_queries.dart';
import 'queries/price_feed_queries.dart';
import 'queries/quantity_queries.dart';
import 'queries/query_context.dart';
import 'queries/referral_queries.dart';
import 'queries/registry_queries.dart';
import 'queries/tpsl_queries.dart';
import 'transactions/balance_manager.dart';
import 'transactions/deepbook.dart';
import 'transactions/deepbook_admin.dart';
import 'transactions/flash_loans.dart';
import 'transactions/governance.dart';
import 'transactions/margin_admin.dart';
import 'transactions/margin_liquidations.dart';
import 'transactions/margin_maintainer.dart';
import 'transactions/margin_manager.dart';
import 'transactions/margin_pool.dart';
import 'transactions/margin_registry.dart';
import 'transactions/margin_tpsl.dart';
import 'transactions/pool_proxy.dart';
import 'types.dart';

/// DeepBookClient class for managing DeepBook operations.
///
/// Read-only queries are exposed as async methods that simulate transactions
/// (e.g. [midPrice], [account]); transaction builders are grouped in the
/// public contract fields (e.g. [deepBook], [balanceManager]) and return
/// closures that append Move calls to a [Transaction].
///
/// ```dart
/// final db = DeepBookClient(
///   client: grpcClient,
///   network: 'mainnet',
///   address: '0x...',
/// );
/// final mid = await db.midPrice('SUI_USDC');
/// ```
class DeepBookClient {
  late final BalanceManagerQueries _balanceManagerQueries;
  late final PoolQueries _poolQueries;
  late final QuantityQueries _quantityQueries;
  late final OrderQueries _orderQueries;
  late final AccountQueries _accountQueries;
  late final ReferralQueries _referralQueries;
  late final PriceFeedQueries _priceFeedQueries;
  late final MarginPoolQueries _marginPoolQueries;
  late final MarginManagerQueries _marginManagerQueries;
  late final TPSLQueries _tpslQueries;
  late final RegistryQueries _registryQueries;

  /// The resolved configuration shared by all contracts and queries.
  late final DeepBookConfig config;

  /// Transaction builders for [BalanceManager] operations (create, deposit,
  /// withdraw, capability management).
  late final BalanceManagerContract balanceManager;

  /// Transaction builders for core DeepBook trading operations (orders,
  /// swaps, claims).
  late final DeepBookContract deepBook;

  /// Transaction builders for admin-gated DeepBook operations (requires
  /// [DeepBookConfig.adminCap]).
  late final DeepBookAdminContract deepBookAdmin;

  /// Transaction builders for borrowing and returning flash loans.
  late final FlashLoanContract flashLoans;

  /// Transaction builders for pool governance (stake, unstake, proposals,
  /// votes).
  late final GovernanceContract governance;

  /// Transaction builders for margin admin operations (requires
  /// [DeepBookConfig.marginAdminCap]).
  late final MarginAdminContract marginAdmin;

  /// Transaction builders for margin maintainer operations (requires
  /// [DeepBookConfig.marginMaintainerCap]).
  late final MarginMaintainerContract marginMaintainer;

  /// Transaction builders for margin pool supply and withdraw operations.
  late final MarginPoolContract marginPool;

  /// Transaction builders for margin manager operations (create, deposit,
  /// withdraw, borrow, repay).
  late final MarginManagerContract marginManager;

  /// Transaction builders for margin registry read-only operations.
  late final MarginRegistryContract marginRegistry;

  /// Transaction builders for liquidation vault operations.
  late final MarginLiquidationsContract marginLiquidations;

  /// Transaction builders for trading on a pool through a margin manager.
  late final PoolProxyContract poolProxy;

  /// Transaction builders for take-profit / stop-loss conditional orders.
  late final MarginTPSLContract marginTPSL;

  /// Creates a new DeepBookClient instance
  DeepBookClient({
    required GrpcCoreClient client,
    required String network,
    required String address,
    Map<String, BalanceManager>? balanceManagers,
    Map<String, MarginManager>? marginManagers,
    CoinMap? coins,
    PoolMap? pools,
    MarginPoolMap? marginPools,
    String? adminCap,
    String? marginAdminCap,
    String? marginMaintainerCap,
    DeepbookPackageIds? packageIds,
    PythConfig? pyth,
  }) {
    config = DeepBookConfig(
      network: network,
      address: address,
      balanceManagers: balanceManagers,
      marginManagers: marginManagers,
      coins: coins,
      pools: pools,
      marginPools: marginPools,
      adminCap: adminCap,
      marginAdminCap: marginAdminCap,
      marginMaintainerCap: marginMaintainerCap,
      packageIds: packageIds,
      pyth: pyth,
    );

    balanceManager = BalanceManagerContract(config);
    deepBook = DeepBookContract(config);
    deepBookAdmin = DeepBookAdminContract(config);
    flashLoans = FlashLoanContract(config);
    governance = GovernanceContract(config);
    marginAdmin = MarginAdminContract(config);
    marginMaintainer = MarginMaintainerContract(config);
    marginPool = MarginPoolContract(config);
    marginManager = MarginManagerContract(config);
    marginRegistry = MarginRegistryContract(config);
    marginLiquidations = MarginLiquidationsContract(config);
    poolProxy = PoolProxyContract(config);
    marginTPSL = MarginTPSLContract(config);

    final ctx = QueryContext(core: client, config: config);

    _balanceManagerQueries = BalanceManagerQueries(ctx);
    _poolQueries = PoolQueries(ctx);
    _quantityQueries = QuantityQueries(ctx);
    _orderQueries = OrderQueries(ctx);
    _accountQueries = AccountQueries(ctx);
    _referralQueries = ReferralQueries(ctx);
    _priceFeedQueries = PriceFeedQueries(ctx);
    _marginPoolQueries = MarginPoolQueries(ctx);
    _marginManagerQueries = MarginManagerQueries(ctx);
    _tpslQueries = TPSLQueries(ctx);
    _registryQueries = RegistryQueries(ctx);
  }

  // === Balance Manager Queries ===

  /// Returns the balance of [coinKey] held by the configured manager
  /// [managerKey], in human units.
  Future<ManagerBalance> checkManagerBalance(
      String managerKey, String coinKey) {
    return _balanceManagerQueries.checkManagerBalance(managerKey, coinKey);
  }

  /// Returns the balance of [coinKey] held by the manager at
  /// [managerAddress], in human units.
  Future<ManagerBalance> checkManagerBalanceWithAddress(
      String managerAddress, String coinKey) {
    return _balanceManagerQueries.checkManagerBalanceWithAddress(
        managerAddress, coinKey);
  }

  /// Returns the balances for the cross product of [managerAddresses] ×
  /// [coinKeys], keyed by manager address then coin type.
  Future<Map<String, Map<String, double>>> checkManagerBalancesWithAddress(
      List<String> managerAddresses, List<String> coinKeys) {
    return _balanceManagerQueries.checkManagerBalancesWithAddress(
        managerAddresses, coinKeys);
  }

  /// Returns the [BalanceManager] ids registered by [owner].
  Future<List<String>> getBalanceManagerIds(String owner) {
    return _balanceManagerQueries.getBalanceManagerIds(owner);
  }

  /// Returns whether [managerKey] has an account in the pool identified by
  /// [poolKey].
  Future<bool> accountExists(String poolKey, String managerKey) {
    return _balanceManagerQueries.accountExists(poolKey, managerKey);
  }

  // === Pool Queries ===

  /// Returns whether the pool identified by [poolKey] is whitelisted.
  Future<bool> whitelisted(String poolKey) {
    return _poolQueries.whitelisted(poolKey);
  }

  /// Returns the base/quote/DEEP balances held in the pool vault, in human
  /// units.
  Future<VaultBalances> vaultBalances(String poolKey) {
    return _poolQueries.vaultBalances(poolKey);
  }

  /// Returns the pool id for the asset pair ([baseType], [quoteType]).
  Future<String> getPoolIdByAssets(String baseType, String quoteType) {
    return _poolQueries.getPoolIdByAssets(baseType, quoteType);
  }

  /// Returns the mid price of the pool identified by [poolKey], in human
  /// units.
  Future<double> midPrice(String poolKey) {
    return _poolQueries.midPrice(poolKey);
  }

  /// Returns the current trade params (taker fee, maker fee, stake required)
  /// of the pool.
  Future<PoolTradeParams> poolTradeParams(String poolKey) {
    return _poolQueries.poolTradeParams(poolKey);
  }

  /// Returns the book params (tick size, lot size, min size) of the pool, in
  /// human units.
  Future<PoolBookParams> poolBookParams(String poolKey) {
    return _poolQueries.poolBookParams(poolKey);
  }

  /// Returns whether the pool identified by [poolKey] is a stable pool.
  Future<bool> stablePool(String poolKey) {
    return _poolQueries.stablePool(poolKey);
  }

  /// Returns whether the pool identified by [poolKey] is registered.
  Future<bool> registeredPool(String poolKey) {
    return _poolQueries.registeredPool(poolKey);
  }

  /// Returns the trade params that will apply to the pool next epoch.
  Future<PoolTradeParams> poolTradeParamsNext(String poolKey) {
    return _poolQueries.poolTradeParamsNext(poolKey);
  }

  /// Returns the governance quorum of the pool, in DEEP units.
  Future<double> quorum(String poolKey) {
    return _poolQueries.quorum(poolKey);
  }

  /// Returns the object id of the pool identified by [poolKey].
  Future<String> poolId(String poolKey) {
    return _poolQueries.poolId(poolKey);
  }

  /// Returns whether a limit order with [params] could be placed.
  Future<bool> canPlaceLimitOrder(CanPlaceLimitOrderParams params) {
    return _poolQueries.canPlaceLimitOrder(params);
  }

  /// Returns whether a market order with [params] could be placed.
  Future<bool> canPlaceMarketOrder(CanPlaceMarketOrderParams params) {
    return _poolQueries.canPlaceMarketOrder(params);
  }

  /// Returns whether the market order [quantity] is valid for the pool.
  Future<bool> checkMarketOrderParams(String poolKey, Object quantity) {
    return _poolQueries.checkMarketOrderParams(poolKey, quantity);
  }

  /// Returns whether the limit order [price], [quantity] and
  /// [expireTimestamp] are valid for the pool.
  Future<bool> checkLimitOrderParams(
      String poolKey, Object price, Object quantity, int expireTimestamp) {
    return _poolQueries.checkLimitOrderParams(
        poolKey, price, quantity, expireTimestamp);
  }

  // === Quantity Queries ===

  /// Returns the quote quantity received for selling [baseQuantity], with
  /// fees paid in DEEP.
  Future<QuoteQuantityOut> getQuoteQuantityOut(
      String poolKey, Object baseQuantity) {
    return _quantityQueries.getQuoteQuantityOut(poolKey, baseQuantity);
  }

  /// Returns the base quantity received for spending [quoteQuantity], with
  /// fees paid in DEEP.
  Future<BaseQuantityOut> getBaseQuantityOut(
      String poolKey, Object quoteQuantity) {
    return _quantityQueries.getBaseQuantityOut(poolKey, quoteQuantity);
  }

  /// Returns the output quantities for [baseQuantity] or [quoteQuantity],
  /// with fees paid in DEEP.
  Future<QuantityOut> getQuantityOut(
      String poolKey, Object baseQuantity, Object quoteQuantity) {
    return _quantityQueries.getQuantityOut(
        poolKey, baseQuantity, quoteQuantity);
  }

  /// Returns the quote quantity received for selling [baseQuantity], with
  /// fees paid in the input token.
  Future<QuoteQuantityOut> getQuoteQuantityOutInputFee(
      String poolKey, Object baseQuantity) {
    return _quantityQueries.getQuoteQuantityOutInputFee(poolKey, baseQuantity);
  }

  /// Returns the base quantity received for spending [quoteQuantity], with
  /// fees paid in the input token.
  Future<BaseQuantityOut> getBaseQuantityOutInputFee(
      String poolKey, Object quoteQuantity) {
    return _quantityQueries.getBaseQuantityOutInputFee(poolKey, quoteQuantity);
  }

  /// Returns the output quantities for [baseQuantity] or [quoteQuantity],
  /// with fees paid in the input token.
  Future<QuantityOut> getQuantityOutInputFee(
      String poolKey, Object baseQuantity, Object quoteQuantity) {
    return _quantityQueries.getQuantityOutInputFee(
        poolKey, baseQuantity, quoteQuantity);
  }

  /// Returns the base quantity needed to receive [targetQuoteQuantity].
  Future<BaseQuantityIn> getBaseQuantityIn(
      String poolKey, Object targetQuoteQuantity, bool payWithDeep) {
    return _quantityQueries.getBaseQuantityIn(
        poolKey, targetQuoteQuantity, payWithDeep);
  }

  /// Returns the quote quantity needed to receive [targetBaseQuantity].
  Future<QuoteQuantityIn> getQuoteQuantityIn(
      String poolKey, Object targetBaseQuantity, bool payWithDeep) {
    return _quantityQueries.getQuoteQuantityIn(
        poolKey, targetBaseQuantity, payWithDeep);
  }

  /// Returns the DEEP required as taker and maker for an order of
  /// [baseQuantity] at [price].
  Future<OrderDeepRequiredResult> getOrderDeepRequired(
      String poolKey, Object baseQuantity, Object price) {
    return _quantityQueries.getOrderDeepRequired(poolKey, baseQuantity, price);
  }

  // === Order Queries ===

  /// Returns the open order ids of [managerKey] in [poolKey], as decimal
  /// u128 strings.
  Future<List<String>> accountOpenOrders(String poolKey, String managerKey) {
    return _orderQueries.accountOpenOrders(poolKey, managerKey);
  }

  /// Returns the raw on-chain order for [orderId], or null when not found.
  Future<Map<String, dynamic>?> getOrder(String poolKey, String orderId) {
    return _orderQueries.getOrder(poolKey, orderId);
  }

  /// Returns the order for [orderId] with quantities and prices normalized
  /// to human units, or null when not found.
  Future<Map<String, dynamic>?> getOrderNormalized(
      String poolKey, String orderId) {
    return _orderQueries.getOrderNormalized(poolKey, orderId);
  }

  /// Returns the raw on-chain orders for [orderIds], or null on failure.
  Future<List<Map<String, dynamic>>?> getOrders(
      String poolKey, List<String> orderIds) {
    return _orderQueries.getOrders(poolKey, orderIds);
  }

  /// Returns the level 2 order book in the price range
  /// [priceLow]..[priceHigh] ([isBid] selects the side), in human units.
  Future<Level2Range> getLevel2Range(
      String poolKey, Object priceLow, Object priceHigh, bool isBid) {
    return _orderQueries.getLevel2Range(poolKey, priceLow, priceHigh, isBid);
  }

  /// Returns the level 2 order book [ticks] ticks away from the mid price on
  /// both sides, in human units.
  Future<Level2TicksFromMid> getLevel2TicksFromMid(String poolKey, int ticks) {
    return _orderQueries.getLevel2TicksFromMid(poolKey, ticks);
  }

  /// Returns the raw on-chain details of every open order [managerKey] has
  /// in [poolKey].
  Future<List<Map<String, dynamic>>> getAccountOrderDetails(
      String poolKey, String managerKey) {
    return _orderQueries.getAccountOrderDetails(poolKey, managerKey);
  }

  // === Account Queries ===

  /// Returns the account state of [managerKey] in [poolKey], in human units.
  Future<AccountInfo> account(String poolKey, String managerKey) {
    return _accountQueries.account(poolKey, managerKey);
  }

  /// Returns the locked balances of [balanceManagerKey] in [poolKey], in
  /// human units.
  Future<LockedBalances> lockedBalance(
      String poolKey, String balanceManagerKey) {
    return _accountQueries.lockedBalance(poolKey, balanceManagerKey);
  }

  /// Returns the pool's DEEP price conversion rate, in human units.
  Future<PoolDeepPrice> getPoolDeepPrice(String poolKey) {
    return _accountQueries.getPoolDeepPrice(poolKey);
  }

  // === Referral Queries ===

  /// Returns the owner address of the referral object [referral].
  Future<String> balanceManagerReferralOwner(String referral) {
    return _referralQueries.balanceManagerReferralOwner(referral);
  }

  /// Returns the accumulated referral balances of [referral] in [poolKey],
  /// in human units.
  Future<ReferralBalances> getPoolReferralBalances(
      String poolKey, String referral) {
    return _referralQueries.getPoolReferralBalances(poolKey, referral);
  }

  /// Returns the pool id the referral object [referral] belongs to.
  Future<String> balanceManagerReferralPoolId(String referral) {
    return _referralQueries.balanceManagerReferralPoolId(referral);
  }

  /// Returns the rebate multiplier of [referral] in [poolKey].
  Future<double> poolReferralMultiplier(String poolKey, String referral) {
    return _referralQueries.poolReferralMultiplier(poolKey, referral);
  }

  /// Returns the referral id set on [managerKey] for [poolKey], or null when
  /// unset.
  Future<String?> getBalanceManagerReferralId(
      String managerKey, String poolKey) {
    return _referralQueries.getBalanceManagerReferralId(managerKey, poolKey);
  }

  // === Price Feed Queries ===

  /// Returns the id of a fresh PriceInfoObject for [coinKey], adding
  /// price-update commands to [tx] when the on-chain object is stale.
  Future<String> getPriceInfoObject(Transaction tx, String coinKey) {
    return _priceFeedQueries.getPriceInfoObject(tx, coinKey);
  }

  /// Returns a coin key → PriceInfoObject id map for [coinKeys], adding
  /// price-update commands to [tx] for stale feeds.
  Future<Map<String, String>> getPriceInfoObjects(
      Transaction tx, List<String> coinKeys) {
    return _priceFeedQueries.getPriceInfoObjects(tx, coinKeys);
  }

  /// Returns the arrival time (unix seconds) of the on-chain PriceInfoObject
  /// for [coinKey].
  Future<int> getPriceInfoObjectAge(String coinKey) {
    return _priceFeedQueries.getPriceInfoObjectAge(coinKey);
  }

  // === Margin Pool Queries ===

  /// Returns the margin pool id for [coinKey].
  Future<String> getMarginPoolId(String coinKey) {
    return _marginPoolQueries.getMarginPoolId(coinKey);
  }

  /// Returns whether the DeepBook pool [deepbookPoolId] is allowed to borrow
  /// from the [coinKey] margin pool.
  Future<bool> isDeepbookPoolAllowed(String coinKey, String deepbookPoolId) {
    return _marginPoolQueries.isDeepbookPoolAllowed(coinKey, deepbookPoolId);
  }

  /// Returns the total supply of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolTotalSupply(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolTotalSupply(coinKey, decimals);
  }

  /// Returns the total supply shares of the [coinKey] margin pool, formatted
  /// with [decimals] fractional digits.
  Future<String> getMarginPoolSupplyShares(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolSupplyShares(coinKey, decimals);
  }

  /// Returns the total borrow of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolTotalBorrow(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolTotalBorrow(coinKey, decimals);
  }

  /// Returns the total borrow shares of the [coinKey] margin pool, formatted
  /// with [decimals] fractional digits.
  Future<String> getMarginPoolBorrowShares(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolBorrowShares(coinKey, decimals);
  }

  /// Returns the last update timestamp (ms) of the [coinKey] margin pool.
  Future<int> getMarginPoolLastUpdateTimestamp(String coinKey) {
    return _marginPoolQueries.getMarginPoolLastUpdateTimestamp(coinKey);
  }

  /// Returns the supply cap of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolSupplyCap(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolSupplyCap(coinKey, decimals);
  }

  /// Returns the max utilization rate of the [coinKey] margin pool, as a
  /// fraction.
  Future<double> getMarginPoolMaxUtilizationRate(String coinKey) {
    return _marginPoolQueries.getMarginPoolMaxUtilizationRate(coinKey);
  }

  /// Returns the protocol spread of the [coinKey] margin pool, as a
  /// fraction.
  Future<double> getMarginPoolProtocolSpread(String coinKey) {
    return _marginPoolQueries.getMarginPoolProtocolSpread(coinKey);
  }

  /// Returns the minimum borrow amount of the [coinKey] margin pool,
  /// formatted with [decimals] fractional digits.
  Future<String> getMarginPoolMinBorrow(String coinKey, [int decimals = 6]) {
    return _marginPoolQueries.getMarginPoolMinBorrow(coinKey, decimals);
  }

  /// Returns the current interest rate of the [coinKey] margin pool, as a
  /// fraction.
  Future<double> getMarginPoolInterestRate(String coinKey) {
    return _marginPoolQueries.getMarginPoolInterestRate(coinKey);
  }

  /// Returns the supply shares held by supplier cap [supplierCapId] in the
  /// [coinKey] margin pool, formatted with [decimals] fractional digits.
  Future<String> getUserSupplyShares(String coinKey, String supplierCapId,
      [int decimals = 6]) {
    return _marginPoolQueries.getUserSupplyShares(
        coinKey, supplierCapId, decimals);
  }

  /// Returns the supply amount held by supplier cap [supplierCapId] in the
  /// [coinKey] margin pool, formatted with [decimals] fractional digits.
  Future<String> getUserSupplyAmount(String coinKey, String supplierCapId,
      [int decimals = 6]) {
    return _marginPoolQueries.getUserSupplyAmount(
        coinKey, supplierCapId, decimals);
  }

  // === Margin Manager Queries ===

  /// Returns the owner address of the margin manager [marginManagerKey].
  Future<String> getMarginManagerOwner(String marginManagerKey) {
    return _marginManagerQueries.getMarginManagerOwner(marginManagerKey);
  }

  /// Returns the DeepBook pool id associated with the margin manager
  /// [marginManagerKey].
  Future<String> getMarginManagerDeepbookPool(String marginManagerKey) {
    return _marginManagerQueries.getMarginManagerDeepbookPool(marginManagerKey);
  }

  /// Returns the margin pool id the margin manager [marginManagerKey]
  /// borrows from, or null when no loan is outstanding.
  Future<String?> getMarginManagerMarginPoolId(String marginManagerKey) {
    return _marginManagerQueries.getMarginManagerMarginPoolId(marginManagerKey);
  }

  /// Returns the borrowed base and quote shares of the margin manager
  /// [marginManagerKey].
  Future<BorrowedShares> getMarginManagerBorrowedShares(
      String marginManagerKey) {
    return _marginManagerQueries
        .getMarginManagerBorrowedShares(marginManagerKey);
  }

  /// Returns the borrowed base shares of the margin manager
  /// [marginManagerKey].
  Future<String> getMarginManagerBorrowedBaseShares(String marginManagerKey) {
    return _marginManagerQueries
        .getMarginManagerBorrowedBaseShares(marginManagerKey);
  }

  /// Returns the borrowed quote shares of the margin manager
  /// [marginManagerKey].
  Future<String> getMarginManagerBorrowedQuoteShares(String marginManagerKey) {
    return _marginManagerQueries
        .getMarginManagerBorrowedQuoteShares(marginManagerKey);
  }

  /// Returns whether the margin manager [marginManagerKey] has base-asset
  /// debt.
  Future<bool> getMarginManagerHasBaseDebt(String marginManagerKey) {
    return _marginManagerQueries.getMarginManagerHasBaseDebt(marginManagerKey);
  }

  /// Returns the underlying [BalanceManager] id of the margin manager object
  /// at [marginManagerAddress].
  Future<String> getMarginManagerBalanceManagerId(String marginManagerAddress) {
    return _marginManagerQueries
        .getMarginManagerBalanceManagerId(marginManagerAddress);
  }

  /// Returns the base and quote assets of the margin manager
  /// [marginManagerKey], formatted with [decimals] fractional digits.
  Future<MarginManagerAssets> getMarginManagerAssets(String marginManagerKey,
      [int decimals = 6]) {
    return _marginManagerQueries.getMarginManagerAssets(
        marginManagerKey, decimals);
  }

  /// Returns the base and quote debts of the margin manager
  /// [marginManagerKey], formatted with [decimals] fractional digits.
  Future<MarginManagerDebts> getMarginManagerDebts(String marginManagerKey,
      [int decimals = 6]) {
    return _marginManagerQueries.getMarginManagerDebts(
        marginManagerKey, decimals);
  }

  /// Returns the comprehensive state of the margin manager
  /// [marginManagerKey].
  Future<MarginManagerState> getMarginManagerState(String marginManagerKey,
      [int decimals = 6]) {
    return _marginManagerQueries.getMarginManagerState(
        marginManagerKey, decimals);
  }

  /// Returns the states of multiple margin managers, keyed by manager id;
  /// [marginManagers] maps manager id (address) to its pool key.
  Future<Map<String, MarginManagerState>> getMarginManagerStates(
      Map<String, String> marginManagers,
      [int decimals = 6]) {
    return _marginManagerQueries.getMarginManagerStates(
        marginManagers, decimals);
  }

  /// Returns the base asset balance of the margin manager
  /// [marginManagerKey], formatted with [decimals] fractional digits.
  Future<String> getMarginManagerBaseBalance(String marginManagerKey,
      [int decimals = 9]) {
    return _marginManagerQueries.getMarginManagerBaseBalance(
        marginManagerKey, decimals);
  }

  /// Returns the quote asset balance of the margin manager
  /// [marginManagerKey], formatted with [decimals] fractional digits.
  Future<String> getMarginManagerQuoteBalance(String marginManagerKey,
      [int decimals = 9]) {
    return _marginManagerQueries.getMarginManagerQuoteBalance(
        marginManagerKey, decimals);
  }

  /// Returns the DEEP token balance of the margin manager
  /// [marginManagerKey], formatted with [decimals] fractional digits.
  Future<String> getMarginManagerDeepBalance(String marginManagerKey,
      [int decimals = 6]) {
    return _marginManagerQueries.getMarginManagerDeepBalance(
        marginManagerKey, decimals);
  }

  /// Returns base/quote/DEEP balances for multiple margin managers, keyed by
  /// manager id; [marginManagers] maps manager id (address) to its pool key.
  Future<Map<String, MarginManagerBalancesResult>> getMarginManagerBalances(
      Map<String, String> marginManagers,
      [int decimals = 9]) {
    return _marginManagerQueries.getMarginManagerBalances(
        marginManagers, decimals);
  }

  // === TPSL Queries ===

  /// Returns all conditional order ids of the margin manager
  /// [marginManagerKey].
  Future<List<String>> getConditionalOrderIds(String marginManagerKey) {
    return _tpslQueries.getConditionalOrderIds(marginManagerKey);
  }

  /// Returns the lowest trigger price among trigger-above orders of
  /// [marginManagerKey], or `max_u64` when there are none.
  Future<BigInt> getLowestTriggerAbovePrice(String marginManagerKey) {
    return _tpslQueries.getLowestTriggerAbovePrice(marginManagerKey);
  }

  /// Returns the highest trigger price among trigger-below orders of
  /// [marginManagerKey], or 0 when there are none.
  Future<BigInt> getHighestTriggerBelowPrice(String marginManagerKey) {
    return _tpslQueries.getHighestTriggerBelowPrice(marginManagerKey);
  }

  // === Registry Queries ===

  /// Returns whether the pool identified by [poolKey] is enabled for margin
  /// trading.
  Future<bool> isPoolEnabledForMargin(String poolKey) {
    return _registryQueries.isPoolEnabledForMargin(poolKey);
  }

  /// Returns the [MarginManager] ids registered by [owner].
  Future<List<String>> getMarginManagerIdsForOwner(String owner) {
    return _registryQueries.getMarginManagerIdsForOwner(owner);
  }

  /// Returns the base margin pool id for [poolKey].
  Future<String> getBaseMarginPoolId(String poolKey) {
    return _registryQueries.getBaseMarginPoolId(poolKey);
  }

  /// Returns the quote margin pool id for [poolKey].
  Future<String> getQuoteMarginPoolId(String poolKey) {
    return _registryQueries.getQuoteMarginPoolId(poolKey);
  }

  /// Returns the minimum withdraw risk ratio for [poolKey].
  Future<double> getMinWithdrawRiskRatio(String poolKey) {
    return _registryQueries.getMinWithdrawRiskRatio(poolKey);
  }

  /// Returns the minimum borrow risk ratio for [poolKey].
  Future<double> getMinBorrowRiskRatio(String poolKey) {
    return _registryQueries.getMinBorrowRiskRatio(poolKey);
  }

  /// Minimum risk ratio required to open a new position on the pool. Gates
  /// position opening, unlike `getMinBorrowRiskRatio`, which gates borrowing.
  Future<double> getMinOpenRiskRatio(String poolKey) {
    return _registryQueries.getMinOpenRiskRatio(poolKey);
  }

  /// Returns the liquidation risk ratio for [poolKey].
  Future<double> getLiquidationRiskRatio(String poolKey) {
    return _registryQueries.getLiquidationRiskRatio(poolKey);
  }

  /// Returns the target liquidation risk ratio for [poolKey].
  Future<double> getTargetLiquidationRiskRatio(String poolKey) {
    return _registryQueries.getTargetLiquidationRiskRatio(poolKey);
  }

  /// Returns the user liquidation reward for [poolKey].
  Future<double> getUserLiquidationReward(String poolKey) {
    return _registryQueries.getUserLiquidationReward(poolKey);
  }

  /// Returns the pool liquidation reward for [poolKey].
  Future<double> getPoolLiquidationReward(String poolKey) {
    return _registryQueries.getPoolLiquidationReward(poolKey);
  }

  /// Returns the addresses allowed as margin maintainers.
  Future<List<String>> getAllowedMaintainers() {
    return _registryQueries.getAllowedMaintainers();
  }

  /// Returns the ids of the allowed pause caps.
  Future<List<String>> getAllowedPauseCaps() {
    return _registryQueries.getAllowedPauseCaps();
  }

  // === Synchronous Utilities ===

  /// Decodes an encoded u128 order id into side, raw price and order id.
  DecodedOrderId decodeOrderId(BigInt encodedOrderId) {
    return OrderQueries.decodeOrderId(encodedOrderId);
  }
}

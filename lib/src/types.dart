/// Public parameter and result types, mirroring the official SDK's
/// `types/index.ts`.
///
/// Quantity-like fields are typed [Object] and accept either a [num]
/// (human units, scaled by the coin scalar) or a [BigInt] (raw on-chain
/// u64) — see `conversion.dart`.
library;

/// A BalanceManager and its optional capability object ids.
class BalanceManager {
  final String address;
  final String? tradeCap;
  final String? depositCap;
  final String? withdrawCap;
  const BalanceManager({
    required this.address,
    this.tradeCap,
    this.depositCap,
    this.withdrawCap,
  });
}

/// A MarginManager object address and the pool key it trades on.
class MarginManager {
  final String address;
  final String poolKey;
  const MarginManager({required this.address, required this.poolKey});
}

/// A coin known to the SDK config (address, full type tag, decimal scalar,
/// and — where margin trading is supported — its Pyth feed metadata).
class Coin {
  final String address;
  final String type;
  final num scalar;
  final String? feed;
  final String? currencyId;
  final String? priceInfoObjectId;
  const Coin({
    required this.address,
    required this.type,
    required this.scalar,
    this.feed,
    this.currencyId,
    this.priceInfoObjectId,
  });
}

/// A DeepBook pool known to the SDK config (object address and the base and
/// quote coin keys).
class Pool {
  final String address;
  final String baseCoin;
  final String quoteCoin;
  const Pool({
    required this.address,
    required this.baseCoin,
    required this.quoteCoin,
  });
}

/// A margin pool known to the SDK config (object address and full coin type
/// tag).
class MarginPool {
  final String address;
  final String type;
  const MarginPool({required this.address, required this.type});
}

/// Pyth and Wormhole state object ids used for price feed operations.
class PythConfig {
  final String pythStateId;
  final String wormholeStateId;
  const PythConfig({required this.pythStateId, required this.wormholeStateId});
}

/// Per-network DeepBook package/object ids.
class DeepbookPackageIds {
  final String deepbookPackageId;
  final String registryId;
  final String deepTreasuryId;
  final String marginPackageId;
  final String marginV1;
  final String marginRegistryId;
  final String liquidationPackageId;
  const DeepbookPackageIds({
    this.deepbookPackageId = '',
    this.registryId = '',
    this.deepTreasuryId = '',
    this.marginPackageId = '',
    this.marginV1 = '',
    this.marginRegistryId = '',
    this.liquidationPackageId = '',
  });
}

/// Order restriction, `deepbook::order_info` u8 constants.
enum OrderType {
  noRestriction,
  immediateOrCancel,
  fillOrKill,
  postOnly,
}

/// Self-matching behavior, `deepbook::order_info` u8 constants.
enum SelfMatchingOptions {
  selfMatchingAllowed,
  cancelTaker,
  cancelMaker,
}

/// Parameters for placing a limit order.
class PlaceLimitOrderParams {
  final String poolKey;
  final String balanceManagerKey;
  final String clientOrderId;
  final Object price;
  final Object quantity;
  final bool isBid;

  /// Expiration timestamp in ms; defaults to no expiration (`MAX_TIMESTAMP`).
  final Object? expiration;

  /// Order restriction; defaults to [OrderType.noRestriction].
  final OrderType? orderType;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;
  const PlaceLimitOrderParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.clientOrderId,
    required this.price,
    required this.quantity,
    required this.isBid,
    this.expiration,
    this.orderType,
    this.selfMatchingOption,
    this.payWithDeep,
  });
}

/// Parameters for placing a market order.
class PlaceMarketOrderParams {
  final String poolKey;
  final String balanceManagerKey;
  final String clientOrderId;
  final Object quantity;
  final bool isBid;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;
  const PlaceMarketOrderParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.clientOrderId,
    required this.quantity,
    required this.isBid,
    this.selfMatchingOption,
    this.payWithDeep,
  });
}

/// Parameters for checking whether a limit order could be placed.
class CanPlaceLimitOrderParams {
  final String poolKey;
  final String balanceManagerKey;
  final Object price;
  final Object quantity;
  final bool isBid;

  /// Whether fees are paid in DEEP instead of the input coin.
  final bool payWithDeep;

  /// Expiration timestamp in ms.
  final int expireTimestamp;
  const CanPlaceLimitOrderParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.price,
    required this.quantity,
    required this.isBid,
    required this.payWithDeep,
    required this.expireTimestamp,
  });
}

/// Parameters for checking whether a market order could be placed.
class CanPlaceMarketOrderParams {
  final String poolKey;
  final String balanceManagerKey;
  final Object quantity;
  final bool isBid;

  /// Whether fees are paid in DEEP instead of the input coin.
  final bool payWithDeep;
  const CanPlaceMarketOrderParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.quantity,
    required this.isBid,
    required this.payWithDeep,
  });
}

/// Parameters for placing a limit order through a margin manager.
class PlaceMarginLimitOrderParams {
  final String poolKey;
  final String marginManagerKey;
  final String clientOrderId;
  final Object price;
  final Object quantity;
  final bool isBid;

  /// Expiration timestamp in ms; defaults to no expiration (`MAX_TIMESTAMP`).
  final Object? expiration;

  /// Order restriction; defaults to [OrderType.noRestriction].
  final OrderType? orderType;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;
  const PlaceMarginLimitOrderParams({
    required this.poolKey,
    required this.marginManagerKey,
    required this.clientOrderId,
    required this.price,
    required this.quantity,
    required this.isBid,
    this.expiration,
    this.orderType,
    this.selfMatchingOption,
    this.payWithDeep,
  });
}

/// Parameters for placing a market order through a margin manager.
class PlaceMarginMarketOrderParams {
  final String poolKey;
  final String marginManagerKey;
  final String clientOrderId;
  final Object quantity;
  final bool isBid;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;
  const PlaceMarginMarketOrderParams({
    required this.poolKey,
    required this.marginManagerKey,
    required this.clientOrderId,
    required this.quantity,
    required this.isBid,
    this.selfMatchingOption,
    this.payWithDeep,
  });
}

/// The limit order to place when a conditional order triggers.
class PendingLimitOrderParams {
  final String clientOrderId;

  /// Order restriction; defaults to [OrderType.noRestriction].
  final OrderType? orderType;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;
  final Object price;
  final Object quantity;
  final bool isBid;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;

  /// Expiration timestamp in ms; defaults to no expiration (`MAX_TIMESTAMP`).
  final Object? expireTimestamp;
  const PendingLimitOrderParams({
    required this.clientOrderId,
    this.orderType,
    this.selfMatchingOption,
    required this.price,
    required this.quantity,
    required this.isBid,
    this.payWithDeep,
    this.expireTimestamp,
  });
}

/// The market order to place when a conditional order triggers.
class PendingMarketOrderParams {
  final String clientOrderId;

  /// How to handle matching against the sender's own orders; defaults to
  /// [SelfMatchingOptions.selfMatchingAllowed].
  final SelfMatchingOptions? selfMatchingOption;
  final Object quantity;
  final bool isBid;

  /// Whether fees are paid in DEEP (true, the default) or in the input coin.
  final bool? payWithDeep;
  const PendingMarketOrderParams({
    required this.clientOrderId,
    this.selfMatchingOption,
    required this.quantity,
    required this.isBid,
    this.payWithDeep,
  });
}

/// Parameters for adding a take-profit / stop-loss conditional order.
class AddConditionalOrderParams {
  final String marginManagerKey;
  final String conditionalOrderId;

  /// Whether the order triggers when the price falls below [triggerPrice]
  /// (true) or rises above it (false).
  final bool triggerBelowPrice;
  final Object triggerPrice;

  /// A [PendingLimitOrderParams] or [PendingMarketOrderParams].
  final Object pendingOrder;
  const AddConditionalOrderParams({
    required this.marginManagerKey,
    required this.conditionalOrderId,
    required this.triggerBelowPrice,
    required this.triggerPrice,
    required this.pendingOrder,
  });
}

/// Parameters for submitting a governance proposal on a pool.
class ProposalParams {
  final String poolKey;
  final String balanceManagerKey;
  final Object takerFee;
  final Object makerFee;
  final Object stakeRequired;
  const ProposalParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.takerFee,
    required this.makerFee,
    required this.stakeRequired,
  });
}

/// Fee and stake values for a governance proposal submitted through a margin
/// manager.
class MarginProposalParams {
  final Object takerFee;
  final Object makerFee;
  final Object stakeRequired;
  const MarginProposalParams({
    required this.takerFee,
    required this.makerFee,
    required this.stakeRequired,
  });
}

/// Parameters for a direct swap of an exact input [amount].
class SwapParams {
  final String poolKey;
  final Object amount;

  /// The DEEP amount provided to cover trading fees.
  final Object deepAmount;

  /// The minimum acceptable output amount (slippage protection).
  final Object minOut;

  /// Optional pre-built coin inputs (transaction arguments).
  final dynamic deepCoin;
  final dynamic baseCoin;
  final dynamic quoteCoin;
  const SwapParams({
    required this.poolKey,
    required this.amount,
    required this.deepAmount,
    required this.minOut,
    this.deepCoin,
    this.baseCoin,
    this.quoteCoin,
  });
}

/// Parameters for a swap funded through a [BalanceManager] (requires its
/// trade, deposit and withdraw caps).
class SwapWithManagerParams {
  final String poolKey;
  final String balanceManagerKey;
  final String tradeCap;
  final String depositCap;
  final String withdrawCap;
  final Object amount;

  /// The minimum acceptable output amount (slippage protection).
  final Object minOut;
  final dynamic baseCoin;
  final dynamic quoteCoin;
  const SwapWithManagerParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.tradeCap,
    required this.depositCap,
    required this.withdrawCap,
    required this.amount,
    required this.minOut,
    this.baseCoin,
    this.quoteCoin,
  });
}

/// Parameters for staking DEEP in a pool.
class StakeParams {
  final String poolKey;
  final String balanceManagerKey;
  final Object amount;
  const StakeParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.amount,
  });
}

/// Parameters for voting on a governance proposal.
class VoteParams {
  final String poolKey;
  final String balanceManagerKey;
  final String proposalId;
  const VoteParams({
    required this.poolKey,
    required this.balanceManagerKey,
    required this.proposalId,
  });
}

/// Parameters for borrowing a flash loan from a pool.
class FlashLoanParams {
  final String poolKey;
  final Object amount;
  const FlashLoanParams({required this.poolKey, required this.amount});
}

/// Parameters for creating a pool as admin.
class CreatePoolAdminParams {
  final String baseCoinKey;
  final String quoteCoinKey;
  final Object tickSize;
  final Object lotSize;
  final Object minSize;
  final bool whitelisted;
  final bool stablePool;
  const CreatePoolAdminParams({
    required this.baseCoinKey,
    required this.quoteCoinKey,
    required this.tickSize,
    required this.lotSize,
    required this.minSize,
    required this.whitelisted,
    required this.stablePool,
  });
}

/// Parameters for creating a permissionless pool (the creation fee is paid
/// in DEEP).
class CreatePermissionlessPoolParams {
  final String baseCoinKey;
  final String quoteCoinKey;
  final Object tickSize;
  final Object lotSize;
  final Object minSize;
  final dynamic deepCoin;
  const CreatePermissionlessPoolParams({
    required this.baseCoinKey,
    required this.quoteCoinKey,
    required this.tickSize,
    required this.lotSize,
    required this.minSize,
    this.deepCoin,
  });
}

/// Parameters for configuring the EWMA-based additional taker fee.
class SetEwmaParams {
  final Object alpha;
  final Object zScoreThreshold;
  final Object additionalTakerFee;
  const SetEwmaParams({
    required this.alpha,
    required this.zScoreThreshold,
    required this.additionalTakerFee,
  });
}

/// Risk ratio and liquidation reward configuration for a margin-enabled
/// pool.
class PoolConfigParams {
  final Object minWithdrawRiskRatio;
  final Object minBorrowRiskRatio;
  final Object liquidationRiskRatio;
  final Object targetLiquidationRiskRatio;
  final Object userLiquidationReward;
  final Object poolLiquidationReward;
  const PoolConfigParams({
    required this.minWithdrawRiskRatio,
    required this.minBorrowRiskRatio,
    required this.liquidationRiskRatio,
    required this.targetLiquidationRiskRatio,
    required this.userLiquidationReward,
    required this.poolLiquidationReward,
  });
}

/// Supply cap, utilization and rate-limit configuration for a margin pool.
class MarginPoolConfigParams {
  final Object supplyCap;
  final Object maxUtilizationRate;
  final Object protocolSpread;
  final Object minBorrow;
  final Object? rateLimitCapacity;
  final Object? rateLimitRefillRatePerMs;
  final bool? rateLimitEnabled;
  const MarginPoolConfigParams({
    required this.supplyCap,
    required this.maxUtilizationRate,
    required this.protocolSpread,
    required this.minBorrow,
    this.rateLimitCapacity,
    this.rateLimitRefillRatePerMs,
    this.rateLimitEnabled,
  });
}

/// Interest rate curve configuration for a margin pool.
class InterestConfigParams {
  final Object baseRate;
  final Object baseSlope;
  final Object optimalUtilization;
  final Object excessSlope;
  const InterestConfigParams({
    required this.baseRate,
    required this.baseSlope,
    required this.optimalUtilization,
    required this.excessSlope,
  });
}

// === Named return types (query layer) ===

/// A manager's balance of a single coin, in human units.
class ManagerBalance {
  final String coinType;
  final double balance;
  const ManagerBalance({required this.coinType, required this.balance});
}

/// Base/quote/DEEP balances held in a pool vault, in human units.
class VaultBalances {
  final double base, quote, deep;
  const VaultBalances(
      {required this.base, required this.quote, required this.deep});
}

/// Base/quote/DEEP balances locked by open orders and stakes, in human
/// units.
class LockedBalances {
  final double base, quote, deep;
  const LockedBalances(
      {required this.base, required this.quote, required this.deep});
}

/// Accumulated base/quote/DEEP referral rebates, in human units.
class ReferralBalances {
  final double base, quote, deep;
  const ReferralBalances(
      {required this.base, required this.quote, required this.deep});
}

/// A pool's taker fee, maker fee and required stake.
class PoolTradeParams {
  final double takerFee, makerFee, stakeRequired;
  const PoolTradeParams(
      {required this.takerFee,
      required this.makerFee,
      required this.stakeRequired});
}

/// A pool's tick size, lot size and minimum size, in human units.
class PoolBookParams {
  final double tickSize, lotSize, minSize;
  const PoolBookParams(
      {required this.tickSize, required this.lotSize, required this.minSize});
}

/// `assetIsBase == true` → [deepPerBase] is set; otherwise [deepPerQuote].
class PoolDeepPrice {
  final bool assetIsBase;
  final double? deepPerBase;
  final double? deepPerQuote;
  const PoolDeepPrice(
      {required this.assetIsBase, this.deepPerBase, this.deepPerQuote});
}

/// The estimated output of selling [baseQuantity] of the base asset.
class QuoteQuantityOut {
  final double baseQuantity, baseOut, quoteOut, deepRequired;
  const QuoteQuantityOut(
      {required this.baseQuantity,
      required this.baseOut,
      required this.quoteOut,
      required this.deepRequired});
}

/// The estimated output of spending [quoteQuantity] of the quote asset.
class BaseQuantityOut {
  final double quoteQuantity, baseOut, quoteOut, deepRequired;
  const BaseQuantityOut(
      {required this.quoteQuantity,
      required this.baseOut,
      required this.quoteOut,
      required this.deepRequired});
}

/// The estimated output for a base or quote input quantity.
class QuantityOut {
  final double baseQuantity, quoteQuantity, baseOut, quoteOut, deepRequired;
  const QuantityOut(
      {required this.baseQuantity,
      required this.quoteQuantity,
      required this.baseOut,
      required this.quoteOut,
      required this.deepRequired});
}

/// The base input required to receive a target quote quantity.
class BaseQuantityIn {
  final double baseIn, quoteOut, deepRequired;
  const BaseQuantityIn(
      {required this.baseIn,
      required this.quoteOut,
      required this.deepRequired});
}

/// The quote input required to receive a target base quantity.
class QuoteQuantityIn {
  final double baseOut, quoteIn, deepRequired;
  const QuoteQuantityIn(
      {required this.baseOut,
      required this.quoteIn,
      required this.deepRequired});
}

/// The DEEP required as taker and as maker for an order.
class OrderDeepRequiredResult {
  final double deepRequiredTaker, deepRequiredMaker;
  const OrderDeepRequiredResult(
      {required this.deepRequiredTaker, required this.deepRequiredMaker});
}

/// Level 2 price/quantity arrays for one side of the order book.
class Level2Range {
  final List<double> prices;
  final List<double> quantities;
  const Level2Range({required this.prices, required this.quantities});
}

/// Level 2 bid and ask arrays around the mid price.
class Level2TicksFromMid {
  final List<double> bidPrices, bidQuantities, askPrices, askQuantities;
  const Level2TicksFromMid(
      {required this.bidPrices,
      required this.bidQuantities,
      required this.askPrices,
      required this.askQuantities});
}

/// Base/quote/DEEP balances of an account, in human units.
class AccountBalances {
  final double base, quote, deep;
  const AccountBalances(
      {required this.base, required this.quote, required this.deep});
}

/// The full account state of a manager in a pool.
class AccountInfo {
  final String epoch;
  final List<String> openOrders;
  final double takerVolume, makerVolume, activeStake, inactiveStake;
  final bool createdProposal;
  final String? votedProposal;
  final AccountBalances unclaimedRebates, settledBalances, owedBalances;
  const AccountInfo({
    required this.epoch,
    required this.openOrders,
    required this.takerVolume,
    required this.makerVolume,
    required this.activeStake,
    required this.inactiveStake,
    required this.createdProposal,
    required this.votedProposal,
    required this.unclaimedRebates,
    required this.settledBalances,
    required this.owedBalances,
  });
}

/// A decoded u128 order id: side, raw price and plain order id.
class DecodedOrderId {
  final bool isBid;
  final double price;
  final BigInt orderId;
  const DecodedOrderId(
      {required this.isBid, required this.price, required this.orderId});
}

/// Comprehensive state of a margin manager (assets, debts, risk ratio and
/// Pyth prices).
class MarginManagerState {
  final String managerId;
  final String deepbookPoolId;
  final double riskRatio;
  final String baseAsset, quoteAsset, baseDebt, quoteDebt;
  final String basePythPrice;
  final int basePythDecimals;
  final String quotePythPrice;
  final int quotePythDecimals;
  final BigInt currentPrice;
  final BigInt lowestTriggerAbovePrice;
  final BigInt highestTriggerBelowPrice;
  const MarginManagerState({
    required this.managerId,
    required this.deepbookPoolId,
    required this.riskRatio,
    required this.baseAsset,
    required this.quoteAsset,
    required this.baseDebt,
    required this.quoteDebt,
    required this.basePythPrice,
    required this.basePythDecimals,
    required this.quotePythPrice,
    required this.quotePythDecimals,
    required this.currentPrice,
    required this.lowestTriggerAbovePrice,
    required this.highestTriggerBelowPrice,
  });
}

/// Base and quote assets of a margin manager.
class MarginManagerAssets {
  final String baseAsset, quoteAsset;
  const MarginManagerAssets(
      {required this.baseAsset, required this.quoteAsset});
}

/// Base and quote debts of a margin manager.
class MarginManagerDebts {
  final String baseDebt, quoteDebt;
  const MarginManagerDebts({required this.baseDebt, required this.quoteDebt});
}

/// Base/quote/DEEP balances of a margin manager.
class MarginManagerBalancesResult {
  final String base, quote, deep;
  const MarginManagerBalancesResult(
      {required this.base, required this.quote, required this.deep});
}

/// Borrowed base and quote shares of a margin manager.
class BorrowedShares {
  final String baseShares, quoteShares;
  const BorrowedShares({required this.baseShares, required this.quoteShares});
}

/// Deposit into a margin manager: exactly one of [amount] / [coin].
class DepositParams {
  final String managerKey;
  final Object? amount;
  final dynamic coin;
  const DepositParams({required this.managerKey, this.amount, this.coin})
      : assert((amount != null) ^ (coin != null),
            'provide exactly one of amount/coin');
}

/// Deposit during margin manager initialization: [coinType] is a coin key
/// from config; exactly one of [amount] / [coin].
class DepositDuringInitParams {
  final dynamic manager;
  final String poolKey;
  final String coinType;
  final Object? amount;
  final dynamic coin;
  const DepositDuringInitParams({
    required this.manager,
    required this.poolKey,
    required this.coinType,
    this.amount,
    this.coin,
  }) : assert((amount != null) ^ (coin != null),
            'provide exactly one of amount/coin');
}

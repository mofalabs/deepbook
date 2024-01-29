import 'package:sui/models/sui_event.dart';

class PoolSummary {
	String poolId;
	String baseAsset;
	String quoteAsset;

  PoolSummary(
    this.poolId, 
    this.baseAsset, 
    this.quoteAsset
  );
}

/// `next_cursor` points to the last item in the page; Reading with `next_cursor` will start from the
/// next item after `next_cursor` if `next_cursor` is `Some`, otherwise it will start from the first
/// item.
class PaginatedPoolSummary {
	List<PoolSummary> data;
	bool hasNextPage;
	EventId? nextCursor;

  PaginatedPoolSummary(
    this.data, 
    this.hasNextPage, 
    this.nextCursor
  );
}

class UserPosition {
	int availableBaseAmount;
	int lockedBaseAmount;
	int availableQuoteAmount;
	int lockedQuoteAmount;

  UserPosition(
    this.availableBaseAmount, 
    this.lockedBaseAmount, 
    this.availableQuoteAmount, 
    this.lockedQuoteAmount
  );
}

enum LimitOrderType {
	// Fill as much quantity as possible in the current transaction as taker, and inject the remaining as a maker order.
	NO_RESTRICTION,
	// Fill as much quantity as possible in the current transaction as taker, and cancel the rest of the order.
	IMMEDIATE_OR_CANCEL,
	// Only fill if the entire order size can be filled as taker in the current transaction. Otherwise, abort the entire transaction.
	FILL_OR_KILL,
	// Only proceed if the entire order size can be posted to the order book as maker in the current transaction. Otherwise, abort the entire transaction.
	POST_OR_ABORT,
}

// The self-matching prevention mechanism ensures that the matching engine takes measures to avoid unnecessary trades
// when matching a user's buy/sell order with their own sell/buy order.
// NOTE: we have only implemented one variant for now
enum SelfMatchingPreventionStyle {
	// Cancel older (resting) order in full. Continue to execute the newer taking order.
	CANCEL_OLDEST,
}

class Order {
	int orderId;
	int clientOrderId;
	int price;
	int originalQuantity;
	int quantity;
	bool isBid;
	String owner;
	String expireTimestamp;
	SelfMatchingPreventionStyle selfMatchingPrevention;

  Order(
    this.orderId, 
    this.clientOrderId, 
    this.price, 
    this.originalQuantity, 
    this.quantity, 
    this.isBid, 
    this.owner, 
    this.expireTimestamp, 
    this.selfMatchingPrevention
  );

  factory Order.fromJson(dynamic data) {
    return Order(
      int.parse(data["orderId"]),
      int.parse(data["clientOrderId"]),
      int.parse(data["price"]),
      int.parse(data["originalQuantity"]),
      int.parse(data["quantity"]),
      data["isBid"],
      data["owner"],
      data["expireTimestamp"],
      SelfMatchingPreventionStyle.values[data["selfMatchingPrevention"]]
    );
  }
}

class MarketPrice {
	int? bestBidPrice;
	int? bestAskPrice;

  MarketPrice(this.bestBidPrice, this.bestAskPrice);
}

class Level2BookStatusPoint {
	int price;
	int depth;

  Level2BookStatusPoint(this.price, this.depth);
}

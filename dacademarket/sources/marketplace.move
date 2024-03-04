module dacademarket::marketplace {

    use sui::dynamic_object_field as ofield;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Bag, Self};
    use sui::table::{Table, Self};
    use sui::transfer;
    use sui::event;

    // Error codes
    const EAmountIncorrect: u64 = 0;
    const ENotOwner: u64 = 1;

    // Shared object representing a marketplace that accepts only one type of coin for all listings
    struct Marketplace<phantom COIN> has key {
        id: UID,
        items: Bag,
        payments: Table<address, Coin<COIN>>
    }

    // Create a new shared marketplace
    private fun create<COIN>(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let items = bag::new(ctx);
        let payments = table::new<address, Coin<COIN>>(ctx);
        transfer::share_object(Marketplace<COIN> { 
            id, 
            items,
            payments
        });
    }

    // Single listing containing the listed item and its price in COIN
    // Attach the actual item as a dynamic object field
    struct Listing has key, store {
        id: UID,
        ask: u64,
        owner: address
    }

    // List an item at the marketplace
    public entry fun list<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let item_id = object::id(&item);
        let listing = Listing {
            id: object::new(ctx),
            ask: ask,
            owner: tx_context::sender(ctx),
        };

        ofield::add(&mut listing.id, true, item);
        bag::add(&mut marketplace.items, item_id, listing);

        // Log the listing event
        event::emit(ListingEvent {
            item_id: item_id,
            ask: ask,
            owner: tx_context::sender(ctx),
        });
    }

    // Internal function to remove a listing and get the item back, only the owner can do this
    fun delist<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        ctx: &mut TxContext
    ): T {
        let Listing { id, owner, ask: _ } = bag::remove(&mut marketplace.items, item_id);
        assert!(tx_context::sender(ctx) == owner, ENotOwner);

        let item = ofield::remove(&mut id, true);
        object::delete(id);
        item
    }

    // Call delist function and transfer the item to the sender
    public entry fun delist_and_take<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let item = delist<T, COIN>(marketplace, item_id, ctx);
        transfer::public_transfer(item, tx_context::sender(ctx));
    }

    // Internal function to purchase an item using a known Listing
    // Payment is done in Coin<C>
    // If conditions are correct, the owner of the item gets paid, and the buyer receives the item
    fun buy<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
        ctx: &mut TxContext
    ): T {
        let Listing { id, ask, owner } = bag::remove(&mut marketplace.items, item_id);
        assert!(ask == coin::value(&paid), EAmountIncorrect);
        // Perform additional access control checks here if needed
        
        if table::contains<address, Coin<COIN>>(&marketplace.payments, owner) {
            coin::join(
                table::borrow_mut<address, Coin<COIN>>(&mut marketplace.payments, owner),
                paid
            );
        } else {
            table::add(&mut marketplace.payments, owner, paid);
        }

        let item = ofield::remove(&mut id, true);
        object::delete(id);
        item
    }

    // Call buy function and transfer the item to the sender
    public entry fun buy_and_take<T: key + store, COIN>(
        marketplace: &mut Marketplace<COIN>,
        item_id: ID,
        paid: Coin<COIN>,
        ctx: &mut TxContext
    ) {
        let item = buy<T, COIN>(marketplace, item_id, paid, ctx);
        transfer::public_transfer(item, tx_context::sender(ctx));
    }

    // Internal function to take profits from selling items on the marketplace
    fun take_profits<COIN>(
        marketplace: &mut Marketplace<COIN>,
        ctx: &mut TxContext
    ): Coin<COIN> {
        table::remove<address, Coin<COIN>>(&mut marketplace.payments, tx_context::sender(ctx))
    }

    // Call take_profits function and transfer the Coin object to the sender
    public entry fun take_profits_and_keep<COIN>(
        marketplace: &mut Marketplace<COIN>,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(take_profits(marketplace, ctx), tx_context::sender(ctx))
    }

    // Event emitted when an item is listed on the marketplace
    struct ListingEvent {
        item_id: ID,
        ask: u64,
        owner: address,
    }
}

module dacademarket::widget {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct Widget has key, store {
        id: UID
    }

    public entry fun mint(ctx: &mut TxContext) {
        let object = Widget { id: object::new(ctx) };
        transfer::transfer(object, tx_context::sender(ctx));
    }
}
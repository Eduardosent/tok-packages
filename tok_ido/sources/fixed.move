module tok_ido::fixed {

    use sui::coin::{Coin, CoinMetadata};
    use sui::clock::Clock;
    use tok_ido::launchpad::{Self, LaunchPool};

    const EInvalidPrice: u64 = 5;  

    public struct FixedSale has key {
        id: UID,
        price_per_unit: u64,
    }

    public fun create_pool<T, P>(
        token_coin: Coin<T>,
        metadata: &CoinMetadata<T>,
        start_time: u64,
        duration_ms: u64,
        min_raise: u64,
        price_per_unit: u64,
        dist_type: u8,
        cliff_time: u64,
        release_amount: u64,
        release_period: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (resolved_start, token_unit) = launchpad::validate_pool_params(
            &token_coin, metadata, start_time, duration_ms, dist_type, clock,
        );
        assert!(price_per_unit > 0, EInvalidPrice);

        let sale = FixedSale { id: object::new(ctx), price_per_unit };
        let sale_id = object::id(&sale);
        transfer::share_object(sale);

        launchpad::new_pool<T, P, FixedSale>(
            token_coin, sale_id, resolved_start, duration_ms, min_raise, token_unit,
            dist_type, cliff_time, release_amount, release_period, ctx,
        );
    }

    public fun buy<T, P>(
        pool: &mut LaunchPool<T, P, FixedSale>,
        sale: &FixedSale,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        launchpad::assert_active(pool, clock);
    
        let paid = payment.value();
        let (final_tokens, cost) = calculate_purchase(pool, sale, paid);
    
        launchpad::settle_buy(pool, payment, final_tokens, cost, ctx);
    }
    
    public fun calculate_purchase<T, P>(
        pool: &LaunchPool<T, P, FixedSale>,
        sale: &FixedSale,
        payment_amount: u64
    ): (u64, u64) {
        let paid = payment_amount as u128;
        let price = sale.price_per_unit as u128;
        // Acceso mediante getter para corregir el error de acceso
        let token_unit = launchpad::get_token_unit(pool) as u128;
        
        // Calculate max tokens based on payment
        let max_purchasable_by_payment = (paid / price) * token_unit;
        // Acceso mediante getter para corregir el error de acceso
        let available_stock = launchpad::get_pool_balance(pool) as u128;
        
        // Determine the actual amount to purchase based on stock limit
        let final_tokens = if (max_purchasable_by_payment > available_stock) {
            available_stock
        } else {
            max_purchasable_by_payment
        };
        
        // Calculate the exact cost for the final tokens
        let cost = ((final_tokens / token_unit) * price) as u64;
    
        (final_tokens as u64, cost)
    }
}
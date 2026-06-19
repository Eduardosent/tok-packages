module tok_ido::bonding {

    use sui::coin::{Coin, CoinMetadata};
    use sui::clock::Clock;
    use tok_ido::launchpad::{Self, LaunchPool};

    const EInvalidPrice: u64 = 5; 

    public struct BondingSale has key {
        id: UID,
        start_price: u64,
        end_price: u64,
    }

    public fun create_pool<T, P>(
        token_coin: Coin<T>,
        metadata: &CoinMetadata<T>,
        start_time: u64,
        duration_ms: u64,
        min_raise: u64,
        start_price: u64,
        end_price: u64,
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
        assert!(start_price > 0 && end_price > start_price, EInvalidPrice);

        let sale = BondingSale { id: object::new(ctx), start_price, end_price };
        let sale_id = object::id(&sale);
        transfer::share_object(sale);

        launchpad::new_pool<T, P, BondingSale>(
            token_coin, sale_id, resolved_start, duration_ms, min_raise, token_unit,
            dist_type, cliff_time, release_amount, release_period, ctx,
        );
    }

    public fun buy<T, P>(
        pool: &mut LaunchPool<T, P, BondingSale>,
        sale: &BondingSale,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        launchpad::assert_active(pool, clock);

        let paid = payment.value();
        let token_unit = launchpad::get_token_unit(pool);
        let total_sold = launchpad::get_total_sold(pool);
        let available_stock = launchpad::get_pool_balance(pool);

        // Calculate tokens and cost using the dedicated function
        let (tokens, cost) = calculate_purchase(sale, paid, token_unit, total_sold, available_stock);
        
        launchpad::settle_buy(pool, payment, tokens, cost, ctx);
    }

    public fun calculate_purchase(
        sale: &BondingSale,
        payment_amount: u64,
        token_unit: u64,
        total_sold: u64,
        available_stock: u64,
    ): (u64, u64) {
        let paid = payment_amount as u128;
        let total_tokens = (total_sold + available_stock) as u128; // Total supply base
        let sold = total_sold as u128;
        let unit = token_unit as u128;
        
        let start = sale.start_price as u128;
        let end = sale.end_price as u128;

        // Calculate dynamic price based on bonding curve
        let price = start + ((end - start) * sold / total_tokens);
        
        // Calculate max tokens the payment can afford
        let raw = paid / price;
        let mut tokens_to_buy = (raw / unit) * unit;

        // Cap tokens to available stock
        if (tokens_to_buy > (available_stock as u128)) {
            tokens_to_buy = available_stock as u128;
        };

        let tokens = tokens_to_buy as u64;
        let cost = (tokens_to_buy * price) as u64;

        (tokens, cost)
    }
}
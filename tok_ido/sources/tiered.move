module tok_ido::tiered {

    use sui::coin::{Coin, CoinMetadata};
    use sui::clock::Clock;
    use tok_ido::launchpad::{Self, LaunchPool};

    const MAX_TIERS: u64 = 20;

    const EInvalidTiers: u64 = 6; 
    const ETooManyTiers: u64 = 7;

    public struct PriceTier has store, copy, drop {
        tokens_available: u64,
        price_per_unit: u64,
    }

    public struct TieredSale has key {
        id: UID,
        tiers: vector<PriceTier>,
        current_tier: u64,
    }

    public fun create_pool<T, P>(
        token_coin: Coin<T>,
        metadata: &CoinMetadata<T>,
        start_time: u64,
        duration_ms: u64,
        min_raise: u64,
        tiers: vector<PriceTier>,
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
        assert!(tiers.length() <= MAX_TIERS, ETooManyTiers);
        validate_tiers(&tiers, token_coin.value());

        let sale = TieredSale { id: object::new(ctx), tiers, current_tier: 0 };
        let sale_id = object::id(&sale);
        transfer::share_object(sale);

        launchpad::new_pool<T, P, TieredSale>(
            token_coin, sale_id, resolved_start, duration_ms, min_raise, token_unit,
            dist_type, cliff_time, release_amount, release_period, ctx,
        );
    }

    public fun buy<T, P>(
        pool: &mut LaunchPool<T, P, TieredSale>,
        sale: &mut TieredSale,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        launchpad::assert_active(pool, clock);

        let paid = payment.value();
        let token_unit = launchpad::get_token_unit(pool) as u128;
        let total_sold = launchpad::get_total_sold(pool);

        let (tokens, cost) = calculate_tokens(
                sale, 
                paid, 
                token_unit, 
                total_sold, 
                launchpad::get_pool_balance(pool)
            );
        launchpad::settle_buy(pool, payment, tokens, cost, ctx);
    }

    fun calculate_tokens(
        sale: &mut TieredSale,
        paid: u64,
        token_unit: u128,
        total_sold: u64,
        available_pool_stock: u64,
    ): (u64, u64) {
        let mut tokens_bought = 0u64;
        let mut total_cost = 0u128;
        let mut remaining_paid = paid as u128;
        let mut current_sold = total_sold;
        let mut accumulated = 0u64;
        let len = sale.tiers.length();

        let mut i = 0;
        while (i < sale.current_tier) {
            accumulated = accumulated + sale.tiers[i].tokens_available;
            i = i + 1;
        };

        i = sale.current_tier;
        let mut final_tier_reached = i;
        while (i < len && remaining_paid > 0) {
            let tier = &sale.tiers[i];
            accumulated = accumulated + tier.tokens_available;

            if (current_sold < accumulated) {
                let available_in_tier = accumulated - current_sold;
                let price = tier.price_per_unit as u128;
                let cost_to_exhaust = (available_in_tier as u128) * price;

                if (remaining_paid >= cost_to_exhaust) {
                    tokens_bought = tokens_bought + available_in_tier;
                    total_cost = total_cost + cost_to_exhaust;
                    remaining_paid = remaining_paid - cost_to_exhaust;
                    current_sold = accumulated;
                    final_tier_reached = i + 1;
                } else {
                    let raw = remaining_paid / price;
                    let whole = (raw / token_unit) * token_unit;
                    tokens_bought = tokens_bought + (whole as u64);
                    total_cost = total_cost + (whole as u128) * price;
                    remaining_paid = 0;
                    final_tier_reached = i;
                };
            };
            i = i + 1;
        };

        // Final consistency check: adjust if stock is insufficient
        if ((tokens_bought as u64) > available_pool_stock) {
            tokens_bought = available_pool_stock;
            // Recalculate cost based on the exact tokens delivered
            // We use the price of the last touched tier for the adjustment
            let price = (sale.tiers[final_tier_reached - 1].price_per_unit as u128);
            total_cost = (tokens_bought as u128) * price;
        };

        sale.current_tier = final_tier_reached;
        (tokens_bought, total_cost as u64)
    }

    fun validate_tiers(tiers: &vector<PriceTier>, total_tokens: u64) {
        let mut total = 0u64;
        let mut i = 0;
        while (i < tiers.length()) {
            total = total + tiers[i].tokens_available;
            i = i + 1;
        };
        assert!(total == total_tokens, EInvalidTiers);
    }
}
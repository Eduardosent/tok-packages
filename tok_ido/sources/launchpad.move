#[allow(lint(self_transfer))]
module tok_ido::launchpad {

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin, CoinMetadata};
    use sui::clock::Clock;
    use sui::table::{Self, Table};

    const MIN_DURATION_MS: u64 = 432_000_000;
    const IMMEDIATE: u8 = 0;
    const VESTED: u8 = 1;

    const EInvalidDistType: u64 = 1;
    const EInvalidStartTime: u64 = 2;
    const EInvalidDuration: u64 = 3;
    const EInvalidTokenAmount: u64 = 4;
    // const EInvalidPrice: u64 = 5;       // fixed.move
    // const EInvalidTiers: u64 = 6;       // tiered.move
    const ENotStarted: u64 = 7;
    const EEnded: u64 = 8;
    const EAlreadyFinalized: u64 = 9;
    const EInsufficientTokens: u64 = 10;

    public struct LaunchPool<phantom T, phantom P, phantom S> has key {
        id: UID,
        owner: address,
        sale_id: ID,
        config: LaunchConfig,
        state: LaunchState,
        distribution: DistConfig,
        balance: Balance<T>,
        proceeds: Balance<P>,
        accounts: Table<address, Allocation>,
    }

    public struct LaunchConfig has store {
        start_time: u64,
        end_time: u64,
        min_raise: u64,
        total_tokens: u64,
        token_unit: u64,
    }

    public struct LaunchState has store {
        total_sold: u64,
        finalized: bool,
    }

    public struct DistConfig has store {
        dist_type: u8,
        cliff_time: u64,
        release_amount: u64,
        release_period: u64,
    }

    public struct Allocation has store {
        paid: u64,
        tokens: u64,
        claimed: bool,
    }

    public(package) fun pow10(exp: u8): u64 {
        let mut result = 1u64;
        let mut i = 0u8;
        while (i < exp) {
            result = result * 10;
            i = i + 1;
        };
        result
    }

    public(package) fun validate_pool_params<T>(
        token_coin: &Coin<T>,
        metadata: &CoinMetadata<T>,
        start_time: u64,
        duration_ms: u64,
        dist_type: u8,
        clock: &Clock,
    ): (u64, u64) {
        assert!(dist_type == IMMEDIATE || dist_type == VESTED, EInvalidDistType);
        assert!(start_time == 0 || start_time >= clock.timestamp_ms(), EInvalidStartTime);
        assert!(duration_ms >= MIN_DURATION_MS, EInvalidDuration);
        let decimals = coin::get_decimals(metadata);
        let unit = pow10(decimals);
        assert!(token_coin.value() % unit == 0, EInvalidTokenAmount);
        let resolved_start = if (start_time == 0) clock.timestamp_ms() else start_time;
        (resolved_start, unit)
    }

    public(package) fun new_pool<T, P, S: key>(
        token_coin: Coin<T>,
        sale_id: ID,
        start_time: u64,
        duration_ms: u64,
        min_raise: u64,
        token_unit: u64,
        dist_type: u8,
        cliff_time: u64,
        release_amount: u64,
        release_period: u64,
        ctx: &mut TxContext
    ) {
        let distribution = if (dist_type == IMMEDIATE) {
            DistConfig { dist_type: IMMEDIATE, cliff_time: 0, release_amount: 0, release_period: 0 }
        } else {
            DistConfig { dist_type: VESTED, cliff_time, release_amount, release_period }
        };

        let pool = LaunchPool<T, P, S> {
            id: object::new(ctx),
            owner: ctx.sender(),
            sale_id,
            config: LaunchConfig {
                start_time,
                end_time: start_time + duration_ms,
                min_raise,
                total_tokens: token_coin.value(),
                token_unit,
            },
            state: LaunchState { total_sold: 0, finalized: false },
            distribution,
            balance: token_coin.into_balance(),
            proceeds: balance::zero(),
            accounts: table::new(ctx),
        };

        transfer::share_object(pool);
    }

    public(package) fun assert_active<T, P, S: key>(pool: &LaunchPool<T, P, S>, clock: &Clock) {
        let now = clock.timestamp_ms();
        assert!(!pool.state.finalized, EAlreadyFinalized);
        assert!(now >= pool.config.start_time, ENotStarted);
        assert!(now < pool.config.end_time, EEnded);
    }

    public(package) fun settle_buy<T, P, S: key>(
        pool: &mut LaunchPool<T, P, S>,
        payment: Coin<P>,
        tokens: u64,
        cost: u64,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();
        assert!(tokens > 0 && tokens <= pool.balance.value(), EInsufficientTokens);

        let paid = payment.value();
        let mut payment = payment;
        if (cost < paid) {
            let change = payment.split(paid - cost, ctx);
            transfer::public_transfer(change, sender);
        };

        coin::put(&mut pool.proceeds, payment);
        pool.state.total_sold = pool.state.total_sold + tokens;

        if (pool.accounts.contains(sender)) {
            let alloc = pool.accounts.borrow_mut(sender);
            alloc.paid = alloc.paid + cost;
            alloc.tokens = alloc.tokens + tokens;
        } else {
            pool.accounts.add(sender, Allocation { paid: cost, tokens, claimed: false });
        };
    }

    public(package) fun get_token_unit<T, P, S: key>(pool: &LaunchPool<T, P, S>): u64 {
        pool.config.token_unit
    }

    public(package) fun get_pool_balance<T, P, S: key>(pool: &LaunchPool<T, P, S>): u64 {
        pool.balance.value()
    }

    public(package) fun get_total_sold<T, P, S: key>(pool: &LaunchPool<T, P, S>): u64 {
        pool.state.total_sold
    }
}
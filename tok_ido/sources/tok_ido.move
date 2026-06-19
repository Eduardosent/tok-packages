// #[allow(lint(self_transfer))]
// module tok_ido::launchpad {

//     use sui::balance::{Self, Balance};
//     use sui::coin::{Self, Coin, CoinMetadata};
//     use sui::clock::Clock;
//     use sui::table::{Self, Table};

//     // === Constants ===
//     const MIN_DURATION_MS: u64 = 432_000_000; // 5 days minimum

//     // sale_type
//     const FIXED_PRICE: u8 = 0;
//     const TIERED_PRICE: u8 = 1;
//     const BONDING_CURVE: u8 = 2;

//     // dist_type
//     const IMMEDIATE: u8 = 0;
//     const VESTED: u8 = 1;

//     // === Errors ===
//     const EInvalidDistType: u64 = 1;
//     const EInvalidStartTime: u64 = 2;
//     const EInvalidDuration: u64 = 3;
//     const EInvalidTokenAmount: u64 = 4;
//     const EInvalidPrice: u64 = 5;
//     const EInvalidTiers: u64 = 6;
//     const ENotStarted: u64 = 7;
//     const EEnded: u64 = 8;
//     const EAlreadyFinalized: u64 = 9;
//     const EInsufficientTokens: u64 = 10;

//     // === Structs ===

//     /// Shared pool representing an IDO launch.
//     /// T = token being sold, P = payment token.
//     public struct LaunchPool<phantom T, phantom P> has key {
//         id: UID,
//         owner: address,
//         config: LaunchConfig,
//         state: LaunchState,
//         sale: SaleConfig,
//         distribution: DistConfig,
//         balance: Balance<T>,
//         proceeds: Balance<P>,
//         accounts: Table<address, Allocation>,
//     }

//     /// Immutable parameters set at pool creation.
//     public struct LaunchConfig has store {
//         start_time: u64,
//         end_time: u64,
//         min_raise: u64,
//         total_tokens: u64,
//         token_decimals: u8,
//     }

//     /// Mutable state updated during the IDO lifecycle.
//     public struct LaunchState has store {
//         total_sold: u64,
//         finalized: bool,
//     }

//     /// Sale pricing configuration.
//     /// Fields used depend on sale_type; unused fields are zero/empty.
//     public struct SaleConfig has store {
//         sale_type: u8,
//         fixed_price: u64,
//         start_price: u64,
//         end_price: u64,
//         tiers: vector<PriceTier>,
//     }

//     /// A single price tranche in a tiered sale.
//     public struct PriceTier has store, copy, drop {
//         tokens_available: u64,
//         price_per_unit: u64,
//     }

//     /// Distribution configuration for purchased tokens.
//     /// Fields used depend on dist_type; unused fields are zero.
//     public struct DistConfig has store {
//         dist_type: u8,
//         cliff_time: u64,
//         release_amount: u64,
//         release_period: u64,
//     }

//     /// Tracks a buyer's position in the pool.
//     public struct Allocation has store {
//         paid: u64,
//         tokens: u64,
//         claimed: bool,
//     }

//     // === Internal Helpers ===

//     fun pow10(exp: u8): u64 {
//         let mut result = 1u64;
//         let mut i = 0u8;
//         while (i < exp) {
//             result = result * 10;
//             i = i + 1;
//         };
//         result
//     }

//     fun validate_pool_params<T>(
//         token_coin: &Coin<T>,
//         metadata: &CoinMetadata<T>,
//         start_time: u64,
//         duration_ms: u64,
//         dist_type: u8,
//         clock: &Clock,
//     ): (u64, u8) {
//         assert!(dist_type == IMMEDIATE || dist_type == VESTED, EInvalidDistType);
//         assert!(start_time == 0 || start_time >= clock.timestamp_ms(), EInvalidStartTime);
//         assert!(duration_ms >= MIN_DURATION_MS, EInvalidDuration);
//         let decimals = coin::get_decimals(metadata);
//         let unit = pow10(decimals);
//         assert!(token_coin.value() % unit == 0, EInvalidTokenAmount);
//         let resolved_start = if (start_time == 0) clock.timestamp_ms() else start_time;
//         (resolved_start, decimals)
//     }

//     fun validate_tiers(tiers: &vector<PriceTier>, total_tokens: u64) {
//         let mut total = 0u64;
//         let mut i = 0;
//         while (i < tiers.length()) {
//             total = total + tiers[i].tokens_available;
//             i = i + 1;
//         };
//         assert!(total == total_tokens, EInvalidTiers);
//     }

//     fun new_pool<T, P>(
//         token_coin: Coin<T>,
//         start_time: u64,
//         duration_ms: u64,
//         min_raise: u64,
//         token_decimals: u8,
//         sale: SaleConfig,
//         dist_type: u8,
//         cliff_time: u64,
//         release_amount: u64,
//         release_period: u64,
//         ctx: &mut TxContext
//     ) {
//         let distribution = if (dist_type == IMMEDIATE) {
//             DistConfig { dist_type: IMMEDIATE, cliff_time: 0, release_amount: 0, release_period: 0 }
//         } else {
//             DistConfig { dist_type: VESTED, cliff_time, release_amount, release_period }
//         };

//         let pool = LaunchPool<T, P> {
//             id: object::new(ctx),
//             owner: ctx.sender(),
//             config: LaunchConfig {
//                 start_time,
//                 end_time: start_time + duration_ms,
//                 min_raise,
//                 total_tokens: token_coin.value(),
//                 token_decimals,
//             },
//             state: LaunchState {
//                 total_sold: 0,
//                 finalized: false,
//             },
//             sale,
//             distribution,
//             balance: token_coin.into_balance(),
//             proceeds: balance::zero(),
//             accounts: table::new(ctx),
//         };

//         transfer::share_object(pool);
//     }

//     // === Public Functions ===

//     public fun create_pool_fixed<T, P>(
//         token_coin: Coin<T>,
//         metadata: &CoinMetadata<T>,
//         start_time: u64,
//         duration_ms: u64,
//         min_raise: u64,
//         price_per_unit: u64,
//         dist_type: u8,
//         cliff_time: u64,
//         release_amount: u64,
//         release_period: u64,
//         clock: &Clock,
//         ctx: &mut TxContext
//     ) {
//         let (start_time, decimals) = validate_pool_params(&token_coin, metadata, start_time, duration_ms, dist_type, clock);
//         assert!(price_per_unit > 0, EInvalidPrice);
//         new_pool<T, P>(
//             token_coin, start_time, duration_ms, min_raise, decimals,
//             SaleConfig { sale_type: FIXED_PRICE, fixed_price: price_per_unit, start_price: 0, end_price: 0, tiers: vector::empty() },
//             dist_type, cliff_time, release_amount, release_period, ctx,
//         );
//     }

//     public fun create_pool_tiered<T, P>(
//         token_coin: Coin<T>,
//         metadata: &CoinMetadata<T>,
//         start_time: u64,
//         duration_ms: u64,
//         min_raise: u64,
//         tiers: vector<PriceTier>,
//         dist_type: u8,
//         cliff_time: u64,
//         release_amount: u64,
//         release_period: u64,
//         clock: &Clock,
//         ctx: &mut TxContext
//     ) {
//         let (start_time, decimals) = validate_pool_params(&token_coin, metadata, start_time, duration_ms, dist_type, clock);
//         validate_tiers(&tiers, token_coin.value());
//         new_pool<T, P>(
//             token_coin, start_time, duration_ms, min_raise, decimals,
//             SaleConfig { sale_type: TIERED_PRICE, fixed_price: 0, start_price: 0, end_price: 0, tiers },
//             dist_type, cliff_time, release_amount, release_period, ctx,
//         );
//     }

//     public fun create_pool_bonding<T, P>(
//         token_coin: Coin<T>,
//         metadata: &CoinMetadata<T>,
//         start_time: u64,
//         duration_ms: u64,
//         min_raise: u64,
//         start_price: u64,
//         end_price: u64,
//         dist_type: u8,
//         cliff_time: u64,
//         release_amount: u64,
//         release_period: u64,
//         clock: &Clock,
//         ctx: &mut TxContext
//     ) {
//         let (start_time, decimals) = validate_pool_params(&token_coin, metadata, start_time, duration_ms, dist_type, clock);
//         assert!(start_price > 0 && end_price > start_price, EInvalidPrice);
//         new_pool<T, P>(
//             token_coin, start_time, duration_ms, min_raise, decimals,
//             SaleConfig { sale_type: BONDING_CURVE, fixed_price: 0, start_price, end_price, tiers: vector::empty() },
//             dist_type, cliff_time, release_amount, release_period, ctx,
//         );
//     }

//     public fun buy<T, P>(
//         pool: &mut LaunchPool<T, P>,
//         payment: Coin<P>,
//         clock: &Clock,
//         ctx: &mut TxContext
//     ) {
//         let sender = ctx.sender();
//         let now = clock.timestamp_ms();

//         assert!(!pool.state.finalized, EAlreadyFinalized);
//         assert!(now >= pool.config.start_time, ENotStarted);
//         assert!(now < pool.config.end_time, EEnded);

//         let paid = payment.value();
//         let unit = pow10(pool.config.token_decimals);
//         let (tokens, cost) = calculate_tokens(pool, paid, unit);
//         assert!(tokens > 0 && tokens <= pool.balance.value(), EInsufficientTokens);

//         let mut payment = payment;
//         if (cost < paid) {
//             let change = payment.split(paid - cost, ctx);
//             transfer::public_transfer(change, sender);
//         };

//         coin::put(&mut pool.proceeds, payment);
//         pool.state.total_sold = pool.state.total_sold + tokens;

//         if (pool.accounts.contains(sender)) {
//             let alloc = pool.accounts.borrow_mut(sender);
//             alloc.paid = alloc.paid + cost;
//             alloc.tokens = alloc.tokens + tokens;
//         } else {
//             pool.accounts.add(sender, Allocation { paid: cost, tokens, claimed: false });
//         };
//     }

//     fun calculate_tokens<T, P>(pool: &LaunchPool<T, P>, paid: u64, unit: u64): (u64, u64) {
//         let sale = &pool.sale;

//         if (sale.sale_type == FIXED_PRICE) {
//             let tokens_base = (paid as u128) / (sale.fixed_price as u128);
//             let tokens = ((tokens_base / (unit as u128)) * (unit as u128)) as u64;
//             let cost = tokens * sale.fixed_price;
//             (tokens, cost)
//         } else if (sale.sale_type == TIERED_PRICE) {
//             let mut tokens_bought = 0u64;
//             let mut total_cost = 0u128;
//             let mut remaining_paid = paid as u128;
//             let mut current_sold = pool.state.total_sold;
//             let mut accumulated = 0u64;
//             let mut i = 0;
//             let len = sale.tiers.length();
//             let unit128 = unit as u128;

//             while (i < len && remaining_paid > 0) {
//                 let tier = &sale.tiers[i];
//                 accumulated = accumulated + tier.tokens_available;

//                 if (current_sold < accumulated) {
//                     let available_in_tier = accumulated - current_sold;
//                     let price = tier.price_per_unit as u128;
//                     let cost_to_exhaust = (available_in_tier as u128) * price;

//                     if (remaining_paid >= cost_to_exhaust) {
//                         tokens_bought = tokens_bought + available_in_tier;
//                         total_cost = total_cost + cost_to_exhaust;
//                         remaining_paid = remaining_paid - cost_to_exhaust;
//                         current_sold = accumulated;
//                     } else {
//                         let raw = remaining_paid / price;
//                         let whole = (raw / unit128) * unit128;
//                         tokens_bought = tokens_bought + (whole as u64);
//                         total_cost = total_cost + whole * price;
//                         remaining_paid = 0;
//                     };
//                 };
//                 i = i + 1;
//             };
//             (tokens_bought, total_cost as u64)
//         } else {
//             let total_tokens = pool.config.total_tokens as u128;
//             let total_sold = pool.state.total_sold as u128;
//             let start = sale.start_price as u128;
//             let end = sale.end_price as u128;
//             let unit128 = unit as u128;

//             let price = start + ((end - start) * total_sold / total_tokens);
//             let raw = (paid as u128) / price;
//             let tokens = ((raw / unit128) * unit128) as u64;
//             let cost = ((tokens as u128) * price) as u64;
//             (tokens, cost)
//         }
//     }
// }

// // 1. token_unit
// // 2. quizá current_tier
// // max tiers vec length?
// // organizar por tipo de launchpad y dentro de cada tipo por función (create, buy, claim, etc)
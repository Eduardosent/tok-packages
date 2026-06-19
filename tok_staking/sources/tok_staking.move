#[allow(lint(self_transfer))]
module tok_staking::staking {

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};
    use sui::clock::Clock;
    use tok_fees::multi_token::{Self, MultiTokenFee};

    // === Constants ===
    const STAKING_FEE_ID: address = @0x76e73c409420757b9a4896f31b8267d0f19e0e9b023b380448483a8c2e5ea991;
    const MS_PER_DAY: u64 = 86_400_000;

    // === Errors ===
    const EInvalidFeeObject: u64 = 0;
    const ENotOwner: u64 = 1;
    const EInvalidOption: u64 = 2;
    const EOptionAlreadyExists: u64 = 3;
    const EOptionNotActive: u64 = 4;
    const EStillLocked: u64 = 5;
    const EInvalidPool: u64 = 6;
    const EInsufficientRewards: u64 = 7;

    // === Structs ===

    /// Shared pool that holds staked tokens and reward reserves.
    /// Any user can stake into it; only the owner can manage options and deposit rewards.
    public struct StakePool<phantom T> has key {
        id: UID,
        owner: address,
        stake_balance: Balance<T>,   // tokens deposited by stakers
        reward_balance: Balance<T>,  // tokens reserved for rewards
        stake_options: vector<StakeOption>,
        accounts: Table<address, StakeAccount>, // tracks total staked per user
    }

    /// Defines a staking option available in the pool.
    /// lock_days = 0 means flexible (unlocked) staking, capped at 1 year of rewards.
    public struct StakeOption has store, drop {
        id: u8,
        lock_days: u16,  // lock period in days, 0 = flexible
        apr: u16,        // annual rate in basis points (100 bps = 1%)
        is_active: bool,
    }

    /// Tracks the total amount staked by a single user in this pool.
    /// Lives inside StakePool.accounts table, keyed by staker address.
    public struct StakeAccount has store {
        total_staked: u64,
    }

    /// Owned by the staker. Represents a single stake position.
    /// Burned on unstake to release principal and rewards.
    public struct StakeEntry has key, store {
        id: UID,
        pool_id: ID,
        lock_days: u16,
        apr: u16,
        amount: u64,
        staked_at: u64, // timestamp in ms at the moment of staking
    }

    // === Public Functions ===

    /// Creates a new StakePool, funded with an initial reward balance.
    /// Charges a protocol fee via MultiTokenFee before creating the pool.
    public fun create_pool<T, PAY>(
        fee: &MultiTokenFee,
        payment: Coin<PAY>,
        reward_coin: Coin<T>,
        ctx: &mut TxContext
    ) {
        // validate the fee object belongs to this protocol
        assert!(object::id_address(fee) == STAKING_FEE_ID, EInvalidFeeObject);
        multi_token::pay_fee(fee, payment);

        let pool = StakePool<T> {
            id: object::new(ctx),
            owner: ctx.sender(),
            stake_balance: balance::zero(),
            // fund the reward reserve with the provided coins
            reward_balance: reward_coin.into_balance(),
            stake_options: vector::empty(),
            accounts: table::new(ctx),
        };

        // share the pool so any user can interact with it
        transfer::share_object(pool);
    }

    /// Stakes tokens into the pool under the selected option.
    /// Creates a StakeAccount for the sender if one does not exist yet.
    /// Mints a StakeEntry owned by the sender representing this position.
    public fun stake<T>(
        pool: &mut StakePool<T>,
        option_id: u8,
        coin: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();

        // auto-create account on first stake
        if (!pool.accounts.contains(sender)) {
            pool.accounts.add(sender, StakeAccount { total_staked: 0 });
        };

        let len = pool.stake_options.length();
        let mut i = 0;
        let mut lock_days = 0u16;
        let mut apr = 0u16;
        let mut found = false;

        // find the selected option and read its parameters
        while (i < len) {
            let option = &pool.stake_options[i];
            if (option.id == option_id) {
                assert!(option.is_active, EOptionNotActive);
                lock_days = option.lock_days;
                apr = option.apr;
                found = true;
                break
            };
            i = i + 1;
        };
        assert!(found, EInvalidOption);

        let amount = coin.value();
        // move tokens into the pool's stake balance
        coin::put(&mut pool.stake_balance, coin);
        // update the user's total staked amount
        pool.accounts.borrow_mut(sender).total_staked = pool.accounts.borrow_mut(sender).total_staked + amount;

        // create and transfer the stake entry to the staker
        transfer::transfer(StakeEntry {
            id: object::new(ctx),
            pool_id: object::id(pool),
            lock_days,
            apr,
            amount,
            staked_at: clock.timestamp_ms(),
        }, sender);
    }

    /// Unstakes tokens and pays out earned rewards.
    /// For locked options, the lock period must have expired.
    /// For flexible options (lock_days = 0), rewards are capped at 365 days.
    public fun unstake<T>(
        pool: &mut StakePool<T>,
        entry: StakeEntry,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();
        // verify the entry belongs to this pool
        assert!(entry.pool_id == object::id(pool), EInvalidPool);

        let now = clock.timestamp_ms();

        // calculate reward-eligible days based on lock type
        let reward_days = if (entry.lock_days == 0) {
            // flexible stake: cap rewards at 1 year
            let days = (now - entry.staked_at) / MS_PER_DAY;
            if (days > 365) 365 else days
        } else {
            // locked stake: must wait full lock period, rewards = exact lock duration
            assert!(now >= entry.staked_at + (entry.lock_days as u64) * MS_PER_DAY, EStillLocked);
            entry.lock_days as u64
        };

        // calculate reward using u128 to prevent overflow on large amounts
        // formula: amount * apr_bps * days / (365 * 10000)
        let reward = (((entry.amount as u128) * (entry.apr as u128) * (reward_days as u128)) / (365 * 10000)) as u64;

        // ensure the pool can fulfill the reward promise before proceeding
        assert!(pool.reward_balance.value() >= reward, EInsufficientRewards);

        // burn the stake entry
        let StakeEntry { id, pool_id: _, lock_days: _, apr: _, amount, staked_at: _ } = entry;
        object::delete(id);

        // deduct from user's total staked
        pool.accounts.borrow_mut(sender).total_staked = pool.accounts.borrow_mut(sender).total_staked - amount;

        // return principal to staker
        let principal = coin::take(&mut pool.stake_balance, amount, ctx);
        transfer::public_transfer(principal, sender);

        // pay out rewards if any
        if (reward > 0) {
            let reward_coin = coin::take(&mut pool.reward_balance, reward, ctx);
            transfer::public_transfer(reward_coin, sender);
        }
    }

    // === Admin Functions ===

    /// Adds a new staking option to the pool. Only callable by the pool owner.
    public fun add_stake_option<T>(
        pool: &mut StakePool<T>,
        id: u8,
        lock_days: u16,
        apr: u16,
        ctx: &TxContext
    ) {
        assert!(pool.owner == ctx.sender(), ENotOwner);

        let len = pool.stake_options.length();
        let mut i = 0;
        // ensure no duplicate option id exists
        while (i < len) {
            assert!(pool.stake_options[i].id != id, EOptionAlreadyExists);
            i = i + 1;
        };

        pool.stake_options.push_back(StakeOption {
            id,
            lock_days,
            apr,
            is_active: true,
        });
    }

    /// Enables or disables a staking option. Only callable by the pool owner.
    public fun set_option_active<T>(
        pool: &mut StakePool<T>,
        option_id: u8,
        is_active: bool,
        ctx: &TxContext
    ) {
        assert!(pool.owner == ctx.sender(), ENotOwner);

        let len = pool.stake_options.length();
        let mut i = 0;
        while (i < len) {
            let option = &mut pool.stake_options[i];
            if (option.id == option_id) {
                option.is_active = is_active;
                return
            };
            i = i + 1;
        };

        abort EInvalidOption
    }

    /// Deposits additional tokens into the reward reserve. Only callable by the pool owner.
    public fun deposit_rewards<T>(
        pool: &mut StakePool<T>,
        reward_coin: Coin<T>,
        ctx: &TxContext
    ) {
        assert!(pool.owner == ctx.sender(), ENotOwner);
        coin::put(&mut pool.reward_balance, reward_coin);
    }

    // === Getters ===

    /// Returns the total amount staked by a given address in this pool.
    /// Returns 0 if the address has never staked.
    public fun get_total_staked<T>(pool: &StakePool<T>, staker: address): u64 {
        if (!pool.accounts.contains(staker)) return 0;
        pool.accounts.borrow(staker).total_staked
    }

    #[test_only]
    public fun create_pool_for_testing<T>(
        reward_coin: Coin<T>,
        ctx: &mut TxContext
    ) {
        let pool = StakePool<T> {
            id: object::new(ctx),
            owner: ctx.sender(),
            stake_balance: balance::zero(),
            reward_balance: reward_coin.into_balance(),
            stake_options: vector::empty(),
            accounts: table::new(ctx),
        };
        transfer::share_object(pool);
    }
}
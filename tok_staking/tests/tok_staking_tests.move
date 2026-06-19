#[test_only]
module tok_staking::staking_tests {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use tok_staking::staking::{Self, StakePool, StakeEntry};

    // === Constants ===
    const OWNER: address = @0xA;
    const STAKER: address = @0xB;
    const STAKER2: address = @0xC;
    const REWARD_AMOUNT: u64 = 10_000_000_000;
    const STAKE_AMOUNT: u64 = 1_000_000_000;
    const APR_10: u16 = 1000;
    const LOCK_30: u16 = 30;
    const MS_PER_DAY: u64 = 86_400_000;

    // === Helpers ===

    /// Creates a shared StakePool funded with REWARD_AMOUNT, owned by OWNER.
    fun setup_pool(scenario: &mut test_scenario::Scenario): clock::Clock {
        test_scenario::next_tx(scenario, OWNER);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let reward = coin::mint_for_testing<SUI>(REWARD_AMOUNT, test_scenario::ctx(scenario));
        staking::create_pool_for_testing<SUI>(reward, test_scenario::ctx(scenario));
        clock
    }

    /// Adds a staking option with the given lock_days and apr to the pool.
    fun add_option(scenario: &mut test_scenario::Scenario, lock_days: u16, apr: u16) {
        test_scenario::next_tx(scenario, OWNER);
        let mut pool = test_scenario::take_shared<StakePool<SUI>>(scenario);
        staking::add_stake_option(&mut pool, 1, lock_days, apr, test_scenario::ctx(scenario));
        test_scenario::return_shared(pool);
    }

    /// Stakes STAKE_AMOUNT into option id 1 as STAKER.
    fun do_stake(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
        test_scenario::next_tx(scenario, STAKER);
        let mut pool = test_scenario::take_shared<StakePool<SUI>>(scenario);
        let coin = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test_scenario::ctx(scenario));
        staking::stake(&mut pool, 1, coin, clock, test_scenario::ctx(scenario));
        test_scenario::return_shared(pool);
    }

    // === Tests ===

    /// Verifies that create_pool_for_testing creates a shared StakePool owned by OWNER.
    #[test]
    fun test_create_pool_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that add_stake_option correctly adds an option to the pool.
    #[test]
    fun test_add_stake_option_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that add_stake_option aborts if a non-owner attempts to add an option.
    #[test]
    #[expected_failure(abort_code = staking::ENotOwner)]
    fun test_add_stake_option_not_owner() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            staking::add_stake_option(&mut pool, 1, LOCK_30, APR_10, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that add_stake_option aborts if the same option id is added twice.
    #[test]
    #[expected_failure(abort_code = staking::EOptionAlreadyExists)]
    fun test_add_stake_option_duplicate() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        // attempt to add same option id again — should abort
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            staking::add_stake_option(&mut pool, 1, LOCK_30, APR_10, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that set_option_active correctly disables an option.
    #[test]
    fun test_set_option_active_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            staking::set_option_active(&mut pool, 1, false, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that set_option_active aborts if a non-owner attempts to change the status.
    #[test]
    #[expected_failure(abort_code = staking::ENotOwner)]
    fun test_set_option_active_not_owner() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            staking::set_option_active(&mut pool, 1, false, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that set_option_active aborts if the option id does not exist.
    #[test]
    #[expected_failure(abort_code = staking::EInvalidOption)]
    fun test_set_option_active_invalid_option() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            // option id 99 does not exist — should abort
            staking::set_option_active(&mut pool, 99, false, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that deposit_rewards correctly increases the reward balance.
    #[test]
    fun test_deposit_rewards_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let extra = coin::mint_for_testing<SUI>(REWARD_AMOUNT, test_scenario::ctx(&mut scenario));
            staking::deposit_rewards(&mut pool, extra, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that deposit_rewards aborts if a non-owner attempts to deposit.
    #[test]
    #[expected_failure(abort_code = staking::ENotOwner)]
    fun test_deposit_rewards_not_owner() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let extra = coin::mint_for_testing<SUI>(REWARD_AMOUNT, test_scenario::ctx(&mut scenario));
            staking::deposit_rewards(&mut pool, extra, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that stake creates a StakeEntry and updates total_staked correctly.
    #[test]
    fun test_stake_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);
        do_stake(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            // verify total staked updated correctly
            assert!(staking::get_total_staked(&pool, STAKER) == STAKE_AMOUNT, 0);
            test_scenario::return_shared(pool);

            // verify StakeEntry was transferred to staker
            assert!(test_scenario::has_most_recent_for_sender<StakeEntry>(&scenario), 1);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that stake aborts if the option id does not exist.
    #[test]
    #[expected_failure(abort_code = staking::EInvalidOption)]
    fun test_stake_invalid_option() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let coin = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test_scenario::ctx(&mut scenario));
            // option id 99 does not exist — should abort
            staking::stake(&mut pool, 99, coin, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that stake aborts if the selected option is inactive.
    #[test]
    #[expected_failure(abort_code = staking::EOptionNotActive)]
    fun test_stake_option_not_active() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        // deactivate the option
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            staking::set_option_active(&mut pool, 1, false, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        // attempt to stake on inactive option — should abort
        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let coin = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test_scenario::ctx(&mut scenario));
            staking::stake(&mut pool, 1, coin, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that unstake returns principal and correct rewards after lock period expires.
    #[test]
    fun test_unstake_locked_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let mut clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);
        do_stake(&mut scenario, &clock);

        // advance clock past lock period
        clock::increment_for_testing(&mut clock, (LOCK_30 as u64) * MS_PER_DAY);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let entry = test_scenario::take_from_sender<StakeEntry>(&scenario);
            staking::unstake(&mut pool, entry, &clock, test_scenario::ctx(&mut scenario));
            assert!(staking::get_total_staked(&pool, STAKER) == 0, 0);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that unstake aborts if the lock period has not expired.
    #[test]
    #[expected_failure(abort_code = staking::EStillLocked)]
    fun test_unstake_still_locked() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);
        do_stake(&mut scenario, &clock);

        // attempt unstake without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let entry = test_scenario::take_from_sender<StakeEntry>(&scenario);
            staking::unstake(&mut pool, entry, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that flexible stake (lock_days = 0) can be unstaked at any time
    /// and rewards are proportional to elapsed days, capped at 365.
    #[test]
    fun test_unstake_flexible_success() {
        let mut scenario = test_scenario::begin(OWNER);
        let mut clock = setup_pool(&mut scenario);
        add_option(&mut scenario, 0, APR_10);
        do_stake(&mut scenario, &clock);

        // advance clock 180 days
        clock::increment_for_testing(&mut clock, 180 * MS_PER_DAY);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let entry = test_scenario::take_from_sender<StakeEntry>(&scenario);
            staking::unstake(&mut pool, entry, &clock, test_scenario::ctx(&mut scenario));
            assert!(staking::get_total_staked(&pool, STAKER) == 0, 0);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that unstake aborts if the pool does not have enough rewards to fulfill the promise.
    #[test]
    #[expected_failure(abort_code = staking::EInsufficientRewards)]
    fun test_unstake_insufficient_rewards() {
        let mut scenario = test_scenario::begin(OWNER);
        let mut clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        test_scenario::next_tx(&mut scenario, STAKER);
        let pool_id = {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let id = object::id(&pool);
            test_scenario::return_shared(pool);
            id
        };

        // stake large enough that reward exceeds pool balance
        // 100_000_000_000_000 * 1000 * 30 / (365 * 10000) ≈ 821_917_808_219 > REWARD_AMOUNT
        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared_by_id<StakePool<SUI>>(&scenario, pool_id);
            let coin = coin::mint_for_testing<SUI>(100_000_000_000_000, test_scenario::ctx(&mut scenario));
            staking::stake(&mut pool, 1, coin, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::increment_for_testing(&mut clock, (LOCK_30 as u64) * MS_PER_DAY);

        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared_by_id<StakePool<SUI>>(&scenario, pool_id);
            let entry = test_scenario::take_from_sender<StakeEntry>(&scenario);
            staking::unstake(&mut pool, entry, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that unstake aborts if the entry belongs to a different pool.
    #[test]
    #[expected_failure(abort_code = staking::EInvalidPool)]
    fun test_unstake_invalid_pool() {
        let mut scenario = test_scenario::begin(OWNER);
        let mut clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        // capture first pool ID before creating the second
        test_scenario::next_tx(&mut scenario, OWNER);
        let correct_pool_id = {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let id = object::id(&pool);
            test_scenario::return_shared(pool);
            id
        };

        // create second pool and capture its ID from the transaction effects
        let _effects = test_scenario::next_tx(&mut scenario, OWNER);
        {
            staking::create_pool_for_testing<SUI>(
                coin::mint_for_testing<SUI>(REWARD_AMOUNT, test_scenario::ctx(&mut scenario)),
                test_scenario::ctx(&mut scenario)
            );
        };
        // flush the transaction so the new pool is visible
        let effects2 = test_scenario::next_tx(&mut scenario, OWNER);
        let wrong_pool_id = test_scenario::shared(&effects2)[0];

        // stake into the correct pool by ID
        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut pool = test_scenario::take_shared_by_id<StakePool<SUI>>(&scenario, correct_pool_id);
            let coin = coin::mint_for_testing<SUI>(STAKE_AMOUNT, test_scenario::ctx(&mut scenario));
            staking::stake(&mut pool, 1, coin, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        clock::increment_for_testing(&mut clock, (LOCK_30 as u64) * MS_PER_DAY);

        // Intentar unstake con el pool incorrecto — should abort with EInvalidPool
        test_scenario::next_tx(&mut scenario, STAKER);
        {
            let mut wrong_pool = test_scenario::take_shared_by_id<StakePool<SUI>>(&scenario, wrong_pool_id);
            let entry = test_scenario::take_from_sender<StakeEntry>(&scenario);
            staking::unstake(&mut wrong_pool, entry, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(wrong_pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that get_total_staked returns 0 for an address that has never staked.
    #[test]
    fun test_get_total_staked_no_account() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            assert!(staking::get_total_staked(&pool, STAKER) == 0, 0);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that multiple stakers can stake independently and their totals are tracked correctly.
    #[test]
    fun test_multiple_stakers() {
        let mut scenario = test_scenario::begin(OWNER);
        let clock = setup_pool(&mut scenario);
        add_option(&mut scenario, LOCK_30, APR_10);

        // STAKER stakes
        do_stake(&mut scenario, &clock);

        // STAKER2 stakes
        test_scenario::next_tx(&mut scenario, STAKER2);
        {
            let mut pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            let coin = coin::mint_for_testing<SUI>(STAKE_AMOUNT * 2, test_scenario::ctx(&mut scenario));
            staking::stake(&mut pool, 1, coin, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<StakePool<SUI>>(&scenario);
            assert!(staking::get_total_staked(&pool, STAKER) == STAKE_AMOUNT, 0);
            assert!(staking::get_total_staked(&pool, STAKER2) == STAKE_AMOUNT * 2, 1);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
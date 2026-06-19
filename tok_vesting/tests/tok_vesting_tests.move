#[test_only]
module tok_vesting::vesting_tests {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use tok_vesting::vesting::{Self, Vesting};

    // === Constants ===
    const CREATOR: address = @0xA;
    const RECIPIENT: address = @0xB;

    // 5_000 tokens total, 1_000 per month, 3 month cliff, 1 month periods
    const TOTAL_AMOUNT: u64 = 5_000;
    const RELEASE_AMOUNT: u64 = 1_000;
    const CLIFF_TIME: u64 = 90 * 86_400_000;
    const RELEASE_PERIOD: u64 = 30 * 86_400_000;

    // === Helpers ===

    fun setup_vesting(scenario: &mut test_scenario::Scenario): clock::Clock {
        test_scenario::next_tx(scenario, CREATOR);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let coin = coin::mint_for_testing<SUI>(TOTAL_AMOUNT, test_scenario::ctx(scenario));
        vesting::create_vesting_for_testing<SUI>(
            coin, CLIFF_TIME, RELEASE_AMOUNT, RELEASE_PERIOD,
            RECIPIENT, &clock, test_scenario::ctx(scenario)
        );
        clock
    }

    // === Tests ===

    /// Vesting object is created and transferred to the recipient.
    #[test]
    fun test_create_vesting_success() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = setup_vesting(&mut scenario);

        test_scenario::next_tx(&mut scenario, RECIPIENT);
        assert!(test_scenario::has_most_recent_for_sender<Vesting<SUI>>(&scenario), 0);

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Claim before cliff elapses must abort.
    #[test]
    #[expected_failure(abort_code = vesting::ECliffNotReached)]
    fun test_claim_before_cliff() {
        let mut scenario = test_scenario::begin(CREATOR);
        let clock = setup_vesting(&mut scenario);

        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Claim immediately after cliff unlocks exactly the first period.
    #[test]
    fun test_claim_first_period_at_cliff() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = setup_vesting(&mut scenario);
        clock::increment_for_testing(&mut clock, CLIFF_TIME);

        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // recipient should have received RELEASE_AMOUNT and vesting returned
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            test_scenario::return_to_sender(&scenario, v);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Claiming twice in the same period must abort on the second attempt.
    #[test]
    #[expected_failure(abort_code = vesting::ENothingToClaim)]
    fun test_claim_nothing_to_claim() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = setup_vesting(&mut scenario);
        clock::increment_for_testing(&mut clock, CLIFF_TIME);

        // first claim
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // second claim same period — should abort
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// After cliff + 2 periods, claiming unlocks 3 periods at once.
    #[test]
    fun test_claim_multiple_periods() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = setup_vesting(&mut scenario);
        // cliff + 2 full periods = 3 periods available
        clock::increment_for_testing(&mut clock, CLIFF_TIME + 2 * RELEASE_PERIOD);

        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // vesting still exists with 2_000 remaining
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            test_scenario::return_to_sender(&scenario, v);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Final claim drains the residual balance and destroys the vesting object.
    #[test]
    fun test_claim_final_destroys_vesting() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = setup_vesting(&mut scenario);
        // advance past all 5 periods
        clock::increment_for_testing(&mut clock, CLIFF_TIME + 4 * RELEASE_PERIOD);

        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // vesting object must no longer exist
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        assert!(!test_scenario::has_most_recent_for_sender<Vesting<SUI>>(&scenario), 0);

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Final claim with residual (non-divisible total) drains remainder and destroys vesting.
    #[test]
    fun test_claim_final_with_residue() {
        let mut scenario = test_scenario::begin(CREATOR);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        // 5_200 total, 1_000 per period — last claim should drain 200
        test_scenario::next_tx(&mut scenario, CREATOR);
        {
            let coin = coin::mint_for_testing<SUI>(5_200, test_scenario::ctx(&mut scenario));
            vesting::create_vesting_for_testing<SUI>(
                coin, CLIFF_TIME, RELEASE_AMOUNT, RELEASE_PERIOD,
                RECIPIENT, &clock, test_scenario::ctx(&mut scenario)
            );
        };

        // advance past 5 full periods (5_000 claimable), leaving 200
        clock::increment_for_testing(&mut clock, CLIFF_TIME + 4 * RELEASE_PERIOD);
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // advance one more period to unlock the residual 200
        clock::increment_for_testing(&mut clock, RELEASE_PERIOD);
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        {
            let v = test_scenario::take_from_sender<Vesting<SUI>>(&scenario);
            vesting::claim(v, &clock, test_scenario::ctx(&mut scenario));
        };

        // vesting destroyed
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        assert!(!test_scenario::has_most_recent_for_sender<Vesting<SUI>>(&scenario), 0);

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
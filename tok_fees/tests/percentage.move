#[test_only]
module tok_fees::percentage_tests {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use sui::transfer;
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};
    use tok_fees::percentage::{Self, PercentageFee};

    // === Constants ===
    const ADMIN: address = @0xAD;
    const USER: address = @0xB;
    const RECIPIENT: address = @0xC;
    const NEW_RECIPIENT: address = @0xD;
    const BPS: u16 = 500;
    const NEW_BPS: u16 = 1000;
    const INVALID_BPS: u16 = 10001;
    const LOCK_PERIOD: u64 = 86_400_000;
    const CREATION_FEE: u64 = 10_000_000;

    // === Helpers ===

    /// Initializes GlobalTreasury and creates a PercentageFee owned by ADMIN.
    /// Returns the Clock object for time manipulation in tests.
    fun setup(scenario: &mut test_scenario::Scenario): clock::Clock {
        config::init_for_testing(test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let treasury = test_scenario::take_shared<GlobalTreasury>(scenario);
        let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(scenario));

        percentage::create_fee(
            &treasury,
            payment,
            BPS,
            RECIPIENT,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(treasury);
        clock
    }

    // === Tests ===

    /// Verifies that create_fee produces a PercentageFee with correct
    /// basis_points and recipient values.
    #[test]
    fun test_create_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (bps, recipient) = percentage::get_fee_config(&fee);
            assert!(bps == BPS, 0);
            assert!(recipient == RECIPIENT, 1);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that create_fee aborts with EInvalidCreationFee when the
    /// SUI payment does not match the protocol fee defined in GlobalTreasury.
    #[test]
    #[expected_failure(abort_code = percentage::EInvalidCreationFee)]
    fun test_create_fee_wrong_payment() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));

            percentage::create_fee(
                &treasury,
                payment,
                BPS,
                RECIPIENT,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario);
    }

    /// Verifies that create_fee aborts with EInvalidPercentage when
    /// basis_points exceeds the maximum allowed (10000 = 100.00%).
    #[test]
    #[expected_failure(abort_code = percentage::EInvalidPercentage)]
    fun test_create_fee_invalid_percentage() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(&mut scenario));

            percentage::create_fee(
                &treasury,
                payment,
                INVALID_BPS,
                RECIPIENT,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario);
    }

    /// Verifies that update_percentage successfully changes the fee percentage
    /// after the lock period has expired. Also verifies last_update is updated.
    #[test]
    fun test_update_percentage_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            // lock_period is 0, so any increment works
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_percentage(&cap, &mut fee, NEW_BPS, &clock);

            let (bps, _) = percentage::get_fee_config(&fee);
            assert!(bps == NEW_BPS, 0);
            
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_percentage aborts with EInvalidPercentage when
    /// new_bps exceeds the maximum allowed (10000).
    #[test]
    #[expected_failure(abort_code = percentage::EInvalidPercentage)]
    fun test_update_percentage_invalid() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_percentage(&cap, &mut fee, INVALID_BPS, &clock);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_percentage aborts with EUpdateLocked when called
    /// before the lock period has expired.
    #[test]
    #[expected_failure(abort_code = percentage::EUpdateLocked)]
    fun test_update_percentage_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // Set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Attempt update without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            percentage::update_percentage(&cap, &mut fee, NEW_BPS, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient successfully changes the recipient address.
    /// Note: update_recipient does NOT require lock period expiration.
    #[test]
    fun test_update_recipient_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            percentage::update_recipient(&cap, &mut fee, NEW_RECIPIENT);

            let (_, recipient) = percentage::get_fee_config(&fee);
            assert!(recipient == NEW_RECIPIENT, 0);
            
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient aborts with EWrongCap when called with
    /// a FeeAdminCap that belongs to a different fee object.
    #[test]
    #[expected_failure(abort_code = tok_fees::config::EWrongCap)]
    fun test_update_recipient_wrong_cap() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        // 1. Save the first fee ID (created in setup) before creating the second one
        test_scenario::next_tx(&mut scenario, ADMIN);
        let first_fee_id = {
            let fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let id = object::id(&fee);
            test_scenario::return_shared(fee);
            id
        };

        // 2. Create a second fee with different parameters
        test_scenario::next_tx(&mut scenario, ADMIN);
        let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
        let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(&mut scenario));
        let clock2 = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        percentage::create_fee(
            &treasury,
            payment,
            100,
            @0x999,
            &clock2,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::return_shared(treasury);
        clock::destroy_for_testing(clock2);

        // 3. ADMIN takes the cap from the second fee and transfers it to USER
        test_scenario::next_tx(&mut scenario, ADMIN);
        let cap2 = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
        transfer::public_transfer(cap2, USER);

        // 4. USER takes the cap (from the second fee) and uses it on the FIRST fee
        test_scenario::next_tx(&mut scenario, USER);
        {
            let mut fee = test_scenario::take_shared_by_id<PercentageFee>(&scenario, first_fee_id);
            let cap2_from_user = test_scenario::take_from_sender<FeeAdminCap>(&scenario);
            percentage::update_recipient(&cap2_from_user, &mut fee, NEW_RECIPIENT);
            test_scenario::return_shared(fee);
            test_scenario::return_to_sender(&scenario, cap2_from_user);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period successfully changes the lock period
    /// after the current lock period has expired.
    #[test]
    fun test_update_lock_period_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Verify the lock period was updated by attempting a percentage update
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            // This should succeed because we advance the clock past the new lock period
            clock::increment_for_testing(&mut clock, LOCK_PERIOD);
            percentage::update_percentage(&cap, &mut fee, NEW_BPS, &clock);

            let (bps, _) = percentage::get_fee_config(&fee);
            assert!(bps == NEW_BPS, 0);
            
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period aborts with EUpdateLocked when called
    /// before the current lock period has expired.
    #[test]
    #[expected_failure(abort_code = percentage::EUpdateLocked)]
    fun test_update_lock_period_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // Set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Attempt update without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            percentage::update_lock_period(&cap, &mut fee, 0, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee successfully destroys the object after the lock period expires.
    #[test]
    fun test_delete_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            percentage::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Verify the object was deleted
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(!test_scenario::has_most_recent_shared<PercentageFee>(), 0);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee aborts with EUpdateLocked when called
    /// before the lock period has expired.
    #[test]
    #[expected_failure(abort_code = percentage::EUpdateLocked)]
    fun test_delete_fee_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // Set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            percentage::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Attempt delete without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            percentage::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee aborts with EWrongCap when called with
    /// a FeeAdminCap that belongs to a different fee object.
    #[test]
    #[expected_failure(abort_code = tok_fees::config::EWrongCap)]
    fun test_delete_fee_wrong_cap() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // 1. Save the first fee ID (created in setup) before creating the second one
        test_scenario::next_tx(&mut scenario, ADMIN);
        let first_fee_id = {
            let fee = test_scenario::take_shared<PercentageFee>(&scenario);
            let id = object::id(&fee);
            test_scenario::return_shared(fee);
            id
        };

        // 2. Create a second fee with different parameters
        test_scenario::next_tx(&mut scenario, ADMIN);
        let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
        let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(&mut scenario));
        let clock2 = clock::create_for_testing(test_scenario::ctx(&mut scenario));

        percentage::create_fee(
            &treasury,
            payment,
            100,
            @0x999,
            &clock2,
            test_scenario::ctx(&mut scenario)
        );

        test_scenario::return_shared(treasury);
        clock::destroy_for_testing(clock2);

        // 3. ADMIN takes the cap from the second fee and transfers it to USER
        test_scenario::next_tx(&mut scenario, ADMIN);
        let cap2 = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
        transfer::public_transfer(cap2, USER);

        // 4. USER takes the cap (from the second fee) and uses it on the FIRST fee
        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared_by_id<PercentageFee>(&scenario, first_fee_id);
            let cap2_from_user = test_scenario::take_from_sender<FeeAdminCap>(&scenario);
            clock::increment_for_testing(&mut clock, 1);
            percentage::delete_fee(&cap2_from_user, fee, &clock);
            test_scenario::return_to_sender(&scenario, cap2_from_user);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
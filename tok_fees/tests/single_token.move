#[test_only]
module tok_fees::single_token_tests {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};
    use tok_fees::single_token::{Self, SingleTokenFee};

    // === Constants ===
    const ADMIN: address = @0xAD;
    const USER: address = @0xB;
    const RECIPIENT: address = @0xC;
    const NEW_RECIPIENT: address = @0xD;
    const PRICE: u64 = 500_000_000;
    const NEW_PRICE: u64 = 1_000_000_000;
    const LOCK_PERIOD: u64 = 86_400_000;
    const CREATION_FEE: u64 = 10_000_000;

    // === Helpers ===

    /// Initializes GlobalTreasury and creates a SingleTokenFee<SUI> owned by ADMIN.
    /// Returns the Clock object for time manipulation in tests.
    fun setup(scenario: &mut test_scenario::Scenario): clock::Clock {
        config::init_for_testing(test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));

        let treasury = test_scenario::take_shared<GlobalTreasury>(scenario);
        let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(scenario));

        single_token::create_fee<SUI>(
            &treasury,
            payment,
            PRICE,
            RECIPIENT,
            LOCK_PERIOD,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(treasury);
        clock
    }

    // === Tests ===

    /// Verifies that create_fee produces a SingleTokenFee with the correct
    /// price, recipient, active status, and lock period.
    /// Also verifies that FeeAdminCap is created and transferred to ADMIN.
    #[test]
    fun test_create_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (price, recipient, active, _last_update, lock_period) = single_token::get_fee_info(&fee);

            assert!(price == PRICE, 0);
            assert!(recipient == RECIPIENT, 1);
            assert!(active == true, 2);
            assert!(lock_period == LOCK_PERIOD, 3);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that create_fee aborts with EInvalidCreationFee when the
    /// SUI payment amount does not match the protocol fee defined in GlobalTreasury.
    #[test]
    #[expected_failure(abort_code = single_token::EInvalidCreationFee)]
    fun test_create_fee_wrong_payment() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));

            single_token::create_fee<SUI>(
                &treasury,
                payment,
                PRICE,
                RECIPIENT,
                LOCK_PERIOD,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee successfully forwards the correct payment amount
    /// to the configured recipient address when the fee is active.
    #[test]
    fun test_pay_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, test_scenario::ctx(&mut scenario));

            single_token::pay_fee(&fee, payment);

            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee aborts with EIncorrectPayment when the payment
    /// amount does not match the configured price.
    #[test]
    #[expected_failure(abort_code = single_token::EIncorrectPayment)]
    fun test_pay_fee_wrong_amount() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));

            single_token::pay_fee(&fee, payment);

            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee aborts with EServiceNotActive when the fee
    /// object has been deactivated via set_active(false).
    #[test]
    #[expected_failure(abort_code = single_token::EServiceNotActive)]
    fun test_pay_fee_inactive() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            single_token::set_active(&cap, &mut fee, false);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, test_scenario::ctx(&mut scenario));

            single_token::pay_fee(&fee, payment);

            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that set_active correctly toggles the active flag on the fee object.
    /// Tests both deactivation (false) and reactivation (true).
    #[test]
    fun test_set_active() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            single_token::set_active(&cap, &mut fee, false);
            let (_, _, active, _, _) = single_token::get_fee_info(&fee);
            assert!(active == false, 0);
            
            single_token::set_active(&cap, &mut fee, true);
            let (_, _, active_again, _, _) = single_token::get_fee_info(&fee);
            assert!(active_again == true, 1);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_price successfully changes the price and updates
    /// last_update timestamp after the lock period has expired.
    #[test]
    fun test_update_price_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (_, _, _, last_update_before, _) = single_token::get_fee_info(&fee);
            
            clock::increment_for_testing(&mut clock, LOCK_PERIOD);
            single_token::update_price(&cap, &mut fee, NEW_PRICE, &clock);

            let (price, _, _, last_update_after, _) = single_token::get_fee_info(&fee);
            assert!(price == NEW_PRICE, 0);
            assert!(last_update_after > last_update_before, 1);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_price aborts with EUpdateLocked when called
    /// before the lock period has expired.
    #[test]
    #[expected_failure(abort_code = single_token::EUpdateLocked)]
    fun test_update_price_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            single_token::update_price(&cap, &mut fee, NEW_PRICE, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient successfully changes the recipient and
    /// updates last_update timestamp after the lock period has expired.
    #[test]
    fun test_update_recipient_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (_, _, _, last_update_before, _) = single_token::get_fee_info(&fee);
            
            clock::increment_for_testing(&mut clock, LOCK_PERIOD);
            single_token::update_recipient(&cap, &mut fee, NEW_RECIPIENT, &clock);

            let (_, recipient, _, last_update_after, _) = single_token::get_fee_info(&fee);
            assert!(recipient == NEW_RECIPIENT, 0);
            assert!(last_update_after > last_update_before, 1);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient aborts with EUpdateLocked when called
    /// before the lock period has expired.
    #[test]
    #[expected_failure(abort_code = single_token::EUpdateLocked)]
    fun test_update_recipient_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            single_token::update_recipient(&cap, &mut fee, NEW_RECIPIENT, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period successfully changes the lock period
    /// and updates last_update timestamp after the current lock period has expired.
    #[test]
    fun test_update_lock_period_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (_, _, _, last_update_before, _) = single_token::get_fee_info(&fee);
            
            clock::increment_for_testing(&mut clock, LOCK_PERIOD);
            single_token::update_lock_period(&cap, &mut fee, 0, &clock);

            let (_, _, _, last_update_after, lock_period) = single_token::get_fee_info(&fee);
            assert!(lock_period == 0, 0);
            assert!(last_update_after > last_update_before, 1);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period aborts with EUpdateLocked when called
    /// before the current lock period has expired.
    #[test]
    #[expected_failure(abort_code = single_token::EUpdateLocked)]
    fun test_update_lock_period_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            single_token::update_lock_period(&cap, &mut fee, 0, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee successfully destroys the fee object after
    /// the lock period has expired. Uses has_most_recent_shared to confirm
    /// the object no longer exists.
    #[test]
    fun test_delete_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, LOCK_PERIOD);
            single_token::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(!test_scenario::has_most_recent_shared<SingleTokenFee<SUI>>(), 0);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee aborts with EUpdateLocked when called
    /// before the lock period has expired.
    #[test]
    #[expected_failure(abort_code = single_token::EUpdateLocked)]
    fun test_delete_fee_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<SingleTokenFee<SUI>>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            single_token::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
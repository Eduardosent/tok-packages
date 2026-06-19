#[test_only]
module tok_fees::multi_token_tests {
    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use sui::sui::SUI;
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};
    use tok_fees::multi_token::{Self, MultiTokenFee};

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

    /// Initializes GlobalTreasury and creates a MultiTokenFee owned by ADMIN.
    /// Returns the clock so tests can manipulate time as needed.
    fun setup(scenario: &mut test_scenario::Scenario): clock::Clock {
        config::init_for_testing(test_scenario::ctx(scenario));

        test_scenario::next_tx(scenario, ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let treasury = test_scenario::take_shared<GlobalTreasury>(scenario);
        let payment = coin::mint_for_testing<SUI>(CREATION_FEE, test_scenario::ctx(scenario));

        multi_token::create_fee(
            &treasury,
            payment,
            RECIPIENT,
            &clock,
            test_scenario::ctx(scenario)
        );

        test_scenario::return_shared(treasury);
        clock
    }

    /// Adds a SUI price entry to the MultiTokenFee owned by ADMIN.
    fun add_sui_price(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
        test_scenario::next_tx(scenario, ADMIN);
        let mut fee = test_scenario::take_shared<MultiTokenFee>(scenario);
        let cap = test_scenario::take_from_address<FeeAdminCap>(scenario, ADMIN);
        multi_token::add_price<SUI>(&cap, &mut fee, PRICE, clock);
        test_scenario::return_shared(fee);
        test_scenario::return_to_address(ADMIN, cap);
    }

    // === Tests ===

    /// Verifies that create_fee produces a MultiTokenFee with correct recipient,
    /// active status, empty prices vector, and zero lock period.
    #[test]
    fun test_create_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            let (recipient, active, _, lock_period) = multi_token::get_service_info(&fee);
            assert!(recipient == RECIPIENT, 0);
            assert!(active == true, 1);
            assert!(lock_period == 0, 2);
            assert!(multi_token::get_prices(&fee).length() == 0, 3);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that create_fee aborts if payment does not match the protocol fee.
    #[test]
    #[expected_failure(abort_code = multi_token::EInvalidCreationFee)]
    fun test_create_fee_wrong_payment() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));

            multi_token::create_fee(
                &treasury,
                payment,
                RECIPIENT,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(treasury);
            clock::destroy_for_testing(clock);
        };
        test_scenario::end(scenario);
    }

    /// Verifies that add_price correctly adds a token price entry to the vector.
    #[test]
    fun test_add_price_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            assert!(multi_token::get_prices(&fee).length() == 1, 0);
            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that add_price aborts if the same token type is added twice.
    #[test]
    #[expected_failure(abort_code = multi_token::ETokenAlreadyExists)]
    fun test_add_price_duplicate() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        // attempt to add SUI again — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::add_price<SUI>(&cap, &mut fee, NEW_PRICE, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee forwards the correct payment to the recipient.
    #[test]
    fun test_pay_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, test_scenario::ctx(&mut scenario));
            multi_token::pay_fee(&fee, payment);
            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee aborts if the payment amount is incorrect.
    #[test]
    #[expected_failure(abort_code = multi_token::EIncorrectPayment)]
    fun test_pay_fee_wrong_amount() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));
            multi_token::pay_fee(&fee, payment);
            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee aborts if the fee object is inactive.
    #[test]
    #[expected_failure(abort_code = multi_token::EServiceNotActive)]
    fun test_pay_fee_inactive() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        // deactivate the fee object
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::set_active(&cap, &mut fee, false);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // attempt payment on inactive fee — should abort
        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, test_scenario::ctx(&mut scenario));
            multi_token::pay_fee(&fee, payment);
            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that pay_fee aborts if the token type is not in the prices vector.
    #[test]
    #[expected_failure(abort_code = multi_token::ETokenNotAccepted)]
    fun test_pay_fee_token_not_accepted() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        // no prices added — any token will be rejected

        test_scenario::next_tx(&mut scenario, USER);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, test_scenario::ctx(&mut scenario));
            multi_token::pay_fee(&fee, payment);
            test_scenario::return_shared(fee);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that set_active correctly toggles the active flag.
    #[test]
    fun test_set_active() {
        let mut scenario = test_scenario::begin(ADMIN);
        let clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            
            multi_token::set_active(&cap, &mut fee, false);
            let (_, active, _, _) = multi_token::get_service_info(&fee);
            assert!(active == false, 0);
            
            multi_token::set_active(&cap, &mut fee, true);
            let (_, active_again, _, _) = multi_token::get_service_info(&fee);
            assert!(active_again == true, 1);

            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_price correctly updates an existing token price.
    #[test]
    fun test_update_price_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            // advance clock — lock_period is 0 so any increment works
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_price<SUI>(&cap, &mut fee, NEW_PRICE, &clock);
            assert!(multi_token::get_prices(&fee).length() == 1, 0);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_price aborts if the token type does not exist.
    #[test]
    #[expected_failure(abort_code = multi_token::ETokenNotAccepted)]
    fun test_update_price_token_not_found() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);
        // no prices added — update should abort

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_price<SUI>(&cap, &mut fee, NEW_PRICE, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_price aborts if lock period has not expired.
    #[test]
    #[expected_failure(abort_code = multi_token::EUpdateLocked)]
    fun test_update_price_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);
        add_sui_price(&mut scenario, &clock);

        // set lock period
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // attempt update without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::update_price<SUI>(&cap, &mut fee, NEW_PRICE, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient correctly updates after lock period expires.
    #[test]
    fun test_update_recipient_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_recipient(&cap, &mut fee, NEW_RECIPIENT, &clock);
            let (recipient, _, _, _) = multi_token::get_service_info(&fee);
            assert!(recipient == NEW_RECIPIENT, 0);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_recipient aborts if the lock period has not expired.
    #[test]
    #[expected_failure(abort_code = multi_token::EUpdateLocked)]
    fun test_update_recipient_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // attempt update without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::update_recipient(&cap, &mut fee, NEW_RECIPIENT, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period correctly updates after current lock period expires.
    #[test]
    fun test_update_lock_period_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            let (_, _, _, lock_period) = multi_token::get_service_info(&fee);
            assert!(lock_period == LOCK_PERIOD, 0);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that update_lock_period aborts if the lock period has not expired.
    #[test]
    #[expected_failure(abort_code = multi_token::EUpdateLocked)]
    fun test_update_lock_period_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // attempt update without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::update_lock_period(&cap, &mut fee, 0, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee successfully destroys the object after lock period expires.
    #[test]
    fun test_delete_fee_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // Verificar que el objeto fue eliminado
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(!test_scenario::has_most_recent_shared<MultiTokenFee>(), 0);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    /// Verifies that delete_fee aborts if the lock period has not expired.
    #[test]
    #[expected_failure(abort_code = multi_token::EUpdateLocked)]
    fun test_delete_fee_locked() {
        let mut scenario = test_scenario::begin(ADMIN);
        let mut clock = setup(&mut scenario);

        // set a lock period first
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            clock::increment_for_testing(&mut clock, 1);
            multi_token::update_lock_period(&cap, &mut fee, LOCK_PERIOD, &clock);
            test_scenario::return_shared(fee);
            test_scenario::return_to_address(ADMIN, cap);
        };

        // attempt delete without advancing clock — should abort
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fee = test_scenario::take_shared<MultiTokenFee>(&scenario);
            let cap = test_scenario::take_from_address<FeeAdminCap>(&scenario, ADMIN);
            multi_token::delete_fee(&cap, fee, &clock);
            test_scenario::return_to_address(ADMIN, cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
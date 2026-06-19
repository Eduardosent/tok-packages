#[test_only]
module tok_fees::config_tests {
    use sui::test_scenario;
    use tok_fees::config::{Self, AdminCap, GlobalTreasury};

    const ADMIN: address = @0xAD;
    const USER: address = @0x666;
    const NUEVO_ADMIN: address = @0x42;
    const NEW_TREASURY_ADDR: address = @0xFEED;

    /// Verifies init creates a shared GlobalTreasury with correct default fee (10000000 mist)
    /// and treasury address set to deployer. Also confirms AdminCap is transferred to deployer.
    #[test]
    fun test_init_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario), 0);

            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            assert!(config::get_fee(&treasury) == 10000000, 1);
            assert!(config::get_treasury(&treasury) == ADMIN, 2);

            let (addr, fee) = config::get_treasury_info(&treasury);
            assert!(addr == ADMIN && fee == 10000000, 3);

            test_scenario::return_shared(treasury);
        };
        test_scenario::end(scenario);
    }

    /// Verifies the AdminCap holder can update both the fee and treasury address,
    /// and that changes are correctly reflected in GlobalTreasury.
    #[test]
    fun test_admin_updates() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            config::update_fee(&cap, &mut treasury, 50000);
            config::update_treasury(&cap, &mut treasury, NEW_TREASURY_ADDR);

            assert!(config::get_fee(&treasury) == 50000, 4);
            assert!(config::get_treasury(&treasury) == NEW_TREASURY_ADDR, 5);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, cap);
        };
        test_scenario::end(scenario);
    }

    /// Verifies that an address without AdminCap cannot perform admin operations.
    /// The test_scenario framework aborts with EEmptyInventory when trying to take
    /// an object the sender does not own.
    #[test]
    #[expected_failure(abort_code = sui::test_scenario::EEmptyInventory)]
    fun test_unauthorized_update_fails() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        // intruder attempts to take AdminCap they don't own — aborts here
        test_scenario::next_tx(&mut scenario, USER);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            config::update_fee(&cap, &mut treasury, 0);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, cap);
        };
        test_scenario::end(scenario);
    }

    /// Verifies AdminCap can be transferred to a new address,
    /// and the new holder can successfully perform admin operations.
    #[test]
    fun test_transfer_admin_and_use() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        // original admin transfers cap to new admin
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            sui::transfer::public_transfer(cap, NUEVO_ADMIN);
        };

        // new admin successfully updates the fee
        test_scenario::next_tx(&mut scenario, NUEVO_ADMIN);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            config::update_fee(&cap, &mut treasury, 777);
            assert!(config::get_fee(&treasury) == 777, 6);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, cap);
        };
        test_scenario::end(scenario);
    }
}
#[test_only]
module tok_fees::config_tests {
    use sui::test_scenario;
    use tok_fees::config::{Self, AdminCap, GlobalTreasury};

    // Direcciones constantes para mantener consistencia
    const ADMIN: address = @0xAD;
    const USER_ATREVIDO: address = @0x666;
    const NUEVO_ADMIN: address = @0x42;
    const NEW_TREASURY_ADDR: address = @0xFEED;

    // --- 1. Test de Inicialización y Getters ---
    #[test]
    fun test_init_success() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            // Verificar que el AdminCap fue entregado
            assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario), 0);
            
            let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            
            // Validar getters individuales
            assert!(config::get_fee(&treasury) == 10000, 1);
            assert!(config::get_treasury(&treasury) == ADMIN, 2);

            // Validar getter combinado
            let (addr, fee) = config::get_treasury_info(&treasury);
            assert!(addr == ADMIN && fee == 10000, 3);

            test_scenario::return_shared(treasury);
        };
        test_scenario::end(scenario);
    }

    // --- 2. Test de Actualización Administrativa (Flujo Exitoso) ---
    #[test]
    fun test_admin_updates() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            config::update_fee(&admin_cap, &mut treasury, 50000);
            config::update_treasury(&admin_cap, &mut treasury, NEW_TREASURY_ADDR);

            assert!(config::get_fee(&treasury) == 50000, 4);
            assert!(config::get_treasury(&treasury) == NEW_TREASURY_ADDR, 5);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    // --- 3. Test de Seguridad (Fallo por falta de AdminCap) ---
    #[test]
    #[expected_failure(abort_code = sui::test_scenario::EEmptyInventory)]
    fun test_unauthorized_update_fails() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        // El intruso intenta robar el AdminCap que no tiene
        test_scenario::next_tx(&mut scenario, USER_ATREVIDO);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            
            // Aquí revienta la ejecución
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            config::update_fee(&admin_cap, &mut treasury, 0);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    // --- 4. Test de Transferencia de Poder (Movilidad de AdminCap) ---
    #[test]
    fun test_transfer_admin_and_use() {
        let mut scenario = test_scenario::begin(ADMIN);
        config::init_for_testing(test_scenario::ctx(&mut scenario));

        // ADMIN original transfiere el mando
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            sui::transfer::public_transfer(admin_cap, NUEVO_ADMIN);
        };

        // NUEVO_ADMIN ahora tiene el control
        test_scenario::next_tx(&mut scenario, NUEVO_ADMIN);
        {
            let mut treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

            config::update_fee(&admin_cap, &mut treasury, 777);
            assert!(config::get_fee(&treasury) == 777, 6);

            test_scenario::return_shared(treasury);
            test_scenario::return_to_sender(&scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }
}
// #[test_only]
// module tok_fees::multi_token_tests {
//     use sui::test_scenario::{Self};
//     use sui::coin;
//     use sui::sui::SUI;
//     use tok_fees::config::{Self, GlobalTreasury};
//     use tok_fees::multi_token::{Self, MultiTokenFee};

//     // Direcciones de prueba
//     const ADMIN: address = @0xAD;
//     const USER_OWNER: address = @0x111;
//     const CLIENTE: address = @0x222;
//     const RECIPIENT_V1: address = @0x333;
//     const RECIPIENT_V2: address = @0x444;

//     // Tokens de prueba
//     public struct USDC has drop {}
//     public struct BUCK has drop {}

//     #[test]
//     fun test_multi_token_flow() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         // 1. Crear el MultiTokenFee (Pagando comisión a TOK)
//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));
            
//             multi_token::create_fee(
//                 &treasury, 
//                 payment, 
//                 RECIPIENT_V1, 
//                 test_scenario::ctx(&mut scenario)
//             );
//             test_scenario::return_shared(treasury);
//         };

//         // 2. Configurar precios para USDC y BUCK
//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let mut fee_config = test_scenario::take_from_sender<MultiTokenFee>(&scenario);
            
//             multi_token::set_price<USDC>(&mut fee_config, 100); // 100 USDC
//             multi_token::set_price<BUCK>(&mut fee_config, 50);  // 50 BUCK
            
//             assert!(multi_token::get_token_price<USDC>(&fee_config) == 100, 0);
//             assert!(multi_token::get_token_price<BUCK>(&fee_config) == 50, 1);

//             test_scenario::return_to_sender(&scenario, fee_config);
//         };

//         // 3. Cliente paga con USDC
//         test_scenario::next_tx(&mut scenario, CLIENTE);
//         {
//             let fee_config = test_scenario::take_from_address<MultiTokenFee>(&scenario, USER_OWNER);
//             let payment = coin::mint_for_testing<USDC>(100, test_scenario::ctx(&mut scenario));

//             multi_token::pay_fee<USDC>(&fee_config, payment);

//             test_scenario::return_to_address(USER_OWNER, fee_config);
//         };

//         // 4. Verificar que el RECIPIENT_V1 recibió los USDC
//         test_scenario::next_tx(&mut scenario, RECIPIENT_V1);
//         {
//             let check_payment = test_scenario::take_from_sender<coin::Coin<USDC>>(&scenario);
//             assert!(coin::value(&check_payment) == 100, 2);
//             test_scenario::return_to_sender(&scenario, check_payment);
//         };

//         // 5. Actualizar Recipient y remover un Token
//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let mut fee_config = test_scenario::take_from_sender<MultiTokenFee>(&scenario);
            
//             multi_token::update_recipient(&mut fee_config, RECIPIENT_V2);
//             multi_token::remove_price<BUCK>(&mut fee_config);
            
//             let (rec, active) = multi_token::get_service_info(&fee_config);
//             assert!(rec == RECIPIENT_V2, 3);
//             assert!(active == true, 4);

//             test_scenario::return_to_sender(&scenario, fee_config);
//         };
//         test_scenario::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = tok_fees::multi_token::ETokenNotAccepted)]
//     fun test_fail_unsupported_token() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));
//             multi_token::create_fee(&treasury, payment, RECIPIENT_V1, test_scenario::ctx(&mut scenario));
//             test_scenario::return_shared(treasury);
//         };

//         // Intentar pagar con un token no registrado (USDC)
//         test_scenario::next_tx(&mut scenario, CLIENTE);
//         {
//             let fee_config = test_scenario::take_from_address<MultiTokenFee>(&scenario, USER_OWNER);
//             let payment = coin::mint_for_testing<USDC>(100, test_scenario::ctx(&mut scenario));

//             multi_token::pay_fee<USDC>(&fee_config, payment); // Debe abortar aquí

//             test_scenario::return_to_address(USER_OWNER, fee_config);
//         };
//         test_scenario::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = tok_fees::multi_token::EServiceNotActive)]
//     fun test_fail_inactive_service() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));
//             multi_token::create_fee(&treasury, payment, RECIPIENT_V1, test_scenario::ctx(&mut scenario));
//             test_scenario::return_shared(treasury);
//         };

//         // Apagar el servicio
//         test_scenario::next_tx(&mut scenario, USER_OWNER);
//         {
//             let mut fee_config = test_scenario::take_from_sender<MultiTokenFee>(&scenario);
//             multi_token::set_price<USDC>(&mut fee_config, 100);
//             multi_token::set_active(&mut fee_config, false);
//             test_scenario::return_to_sender(&scenario, fee_config);
//         };

//         // Intentar pagar servicio inactivo
//         test_scenario::next_tx(&mut scenario, CLIENTE);
//         {
//             let fee_config = test_scenario::take_from_address<MultiTokenFee>(&scenario, USER_OWNER);
//             let payment = coin::mint_for_testing<USDC>(100, test_scenario::ctx(&mut scenario));
//             multi_token::pay_fee<USDC>(&fee_config, payment);
//             test_scenario::return_to_address(USER_OWNER, fee_config);
//         };
//         test_scenario::end(scenario);
//     }
// }
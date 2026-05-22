// #[test_only]
// module tok_fees::single_token_tests {
//     use sui::test_scenario::{Self};
//     use sui::coin;
//     use sui::sui::SUI;
//     use tok_fees::config::{Self, GlobalTreasury};
//     use tok_fees::single_token::{Self, SingleTokenFee};

//     // Direcciones de prueba
//     const ADMIN: address = @0xAD;
//     const USER: address = @0x8008;
//     const RECIPIENT: address = @0xFEED;

//     // Un token de prueba cualquiera
//     public struct COBITO has drop {}

//     #[test]
//     fun test_create_fee_success() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         // 1. Crear el objeto de cobro pagando la comisión al GlobalTreasury
//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             // El fee configurado en el init es 10000 SUI
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));

//             single_token::create_fee<COBITO>(
//                 &treasury,
//                 payment,
//                 500, // Precio del servicio: 500 COBITOS
//                 RECIPIENT,
//                 test_scenario::ctx(&mut scenario)
//             );

//             test_scenario::return_shared(treasury);
//         };

//         // 2. Verificar que el objeto SingleTokenFee<COBITO> llegó al USER
//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             assert!(test_scenario::has_most_recent_for_sender<SingleTokenFee<COBITO>>(&scenario), 0);
//         };
//         test_scenario::end(scenario);
//     }

//     #[test]
//     fun test_pay_service_fee() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         // SETUP: Crear el fee object primero
//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));
//             single_token::create_fee<COBITO>(&treasury, payment, 500, RECIPIENT, test_scenario::ctx(&mut scenario));
//             test_scenario::return_shared(treasury);
//         };

//         // ACCIÓN: Un cliente paga el servicio usando el objeto creado
//         let cliente = @0x444;
//         test_scenario::next_tx(&mut scenario, cliente);
//         {
//             let fee_config = test_scenario::take_from_address<SingleTokenFee<COBITO>>(&scenario, USER);
//             let payment_tokens = coin::mint_for_testing<COBITO>(500, test_scenario::ctx(&mut scenario));

//             single_token::pay_fee<COBITO>(&fee_config, payment_tokens);

//             test_scenario::return_to_address(USER, fee_config);
//         };

//         // VERIFICACIÓN: El RECIPIENT recibió los 500 COBITOS
//         test_scenario::next_tx(&mut scenario, RECIPIENT);
//         {
//             let coin_recibida = test_scenario::take_from_sender<coin::Coin<COBITO>>(&scenario);
//             assert!(coin::value(&coin_recibida) == 500, 1);
//             test_scenario::return_to_sender(&scenario, coin_recibida);
//         };
//         test_scenario::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = tok_fees::single_token::EInvalidCreationFee)]
//     fun test_fail_creation_wrong_payment() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             // Pagando menos de lo que pide el GlobalTreasury (10000)
//             let payment = coin::mint_for_testing<SUI>(5000, test_scenario::ctx(&mut scenario));

//             single_token::create_fee<COBITO>(&treasury, payment, 500, RECIPIENT, test_scenario::ctx(&mut scenario));

//             test_scenario::return_shared(treasury);
//         };
//         test_scenario::end(scenario);
//     }

//     #[test]
//     fun test_admin_updates_fee_object() {
//         let mut scenario = test_scenario::begin(ADMIN);
//         config::init_for_testing(test_scenario::ctx(&mut scenario));

//         // USER crea su fee object
//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             let treasury = test_scenario::take_shared<GlobalTreasury>(&scenario);
//             let payment = coin::mint_for_testing<SUI>(10000, test_scenario::ctx(&mut scenario));
//             single_token::create_fee<COBITO>(&treasury, payment, 500, RECIPIENT, test_scenario::ctx(&mut scenario));
//             test_scenario::return_shared(treasury);
//         };

//         // USER actualiza su propio objeto
//         test_scenario::next_tx(&mut scenario, USER);
//         {
//             let mut fee_config = test_scenario::take_from_sender<SingleTokenFee<COBITO>>(&scenario);
            
//             single_token::update_price(&mut fee_config, 1000);
//             single_token::set_active(&mut fee_config, false);

//             let (price, _, active) = single_token::get_fee_info(&fee_config);
//             assert!(price == 1000, 2);
//             assert!(active == false, 3);

//             test_scenario::return_to_sender(&scenario, fee_config);
//         };
//         test_scenario::end(scenario);
//     }
// }
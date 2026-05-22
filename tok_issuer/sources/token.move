#[allow(lint(self_transfer))]
module tok_issuer::token {
    use sui::coin::{Coin};
    use sui::coin_registry::{Self, CoinRegistry};
    use std::string::{String};
    use tok_fees::multi_token::{Self, MultiTokenFee};

    const ISSUER_FEE_ID: address = @0xd7798816def02049b04fc2d593fee898d0a0597dac60b17d81a34a10d1d4fc4d;
    const EInvalidFeeObject: u64 = 0;

    fun process_fee<PAY>(fee: &MultiTokenFee, payment_coin: Coin<PAY>) {
        assert!(object::id_address(fee) == ISSUER_FEE_ID, EInvalidFeeObject);
        multi_token::pay_fee(fee, payment_coin);
    }

    /// T ahora tiene 'key' y 'drop' para satisfacer al Registry
    public fun create_token<T: key + drop, PAY>(
        fee: &MultiTokenFee,
        payment_coin: Coin<PAY>,
        registry: &mut CoinRegistry,
        decimals: u8,
        symbol: String,
        name: String,
        description: String,
        icon_url: String,
        ctx: &mut TxContext
    ) {
        process_fee<PAY>(fee, payment_coin);

        let (initializer, treasury) = coin_registry::new_currency<T>(
            registry, 
            decimals, 
            symbol, 
            name, 
            description, 
            icon_url, 
            ctx
        );

        let metadata = initializer.finalize(ctx);

        let sender = ctx.sender();
        transfer::public_transfer(treasury, sender);
        transfer::public_transfer(metadata, sender);
    }

    /// T ahora tiene 'key' y 'drop' aquí también
    public fun create_regulated_token<T: key + drop, PAY>(
        fee: &MultiTokenFee,
        payment_coin: Coin<PAY>,
        registry: &mut CoinRegistry,
        decimals: u8,
        symbol: String,
        name: String,
        description: String,
        icon_url: String,
        allow_global_pause: bool,
        ctx: &mut TxContext
    ) {
        process_fee(fee, payment_coin);

        let (mut initializer, treasury) = coin_registry::new_currency<T>(
            registry, 
            decimals, 
            symbol, 
            name, 
            description, 
            icon_url, 
            ctx
        );
        
        let deny = coin_registry::make_regulated(&mut initializer, allow_global_pause, ctx);
        let metadata = initializer.finalize(ctx);

        let sender = ctx.sender();
        transfer::public_transfer(treasury, sender);
        transfer::public_transfer(metadata, sender);
        transfer::public_transfer(deny, sender);
    }
}

// #[allow(lint(self_transfer))]
// module tok_issuer::token {
//     use sui::coin::{Coin};
//     use sui::coin_registry::{Self, CoinRegistry};
//     use std::string::{String};
//     use tok_fees::multi_token::{Self, MultiTokenFee};

//     const ISSUER_FEE_ID: address = @0xd7798816def02049b04fc2d593fee898d0a0597dac60b17d81a34a10d1d4fc4d;
//     const EInvalidFeeObject: u64 = 0;

//     /// 🔥 LA ESTRUCTURA UNIVERSAL
//     /// Corto, claro y sin pendejadas. 
//     /// Todas las memecoins y tokens de juegos nacerán de aquí.
//     public struct Token has key {
//         id: UID
//     }

//     fun process_fee<PAY>(fee: &MultiTokenFee, payment_coin: Coin<PAY>) {
//         assert!(object::id_address(fee) == ISSUER_FEE_ID, EInvalidFeeObject);
//         multi_token::pay_fee(fee, payment_coin);
//     }

//     /// Crea un token estándar usando el tipo Coin del módulo
//     public fun create_token<PAY>(
//         fee: &MultiTokenFee,
//         payment_coin: Coin<PAY>,
//         registry: &mut CoinRegistry,
//         decimals: u8,
//         symbol: String,
//         name: String,
//         description: String,
//         icon_url: String,
//         ctx: &mut TxContext
//     ) {
//         process_fee<PAY>(fee, payment_coin);

//         // Creamos la moneda bajo el tipo 'Coin' de este módulo
//         let (initializer, treasury) = coin_registry::new_currency<Token>(
//             registry,decimals, symbol, name, description, icon_url, ctx
//         );

//         let metadata = initializer.finalize(ctx);

//         let sender = ctx.sender();
//         transfer::public_transfer(treasury, sender);
//         transfer::public_transfer(metadata, sender);
//     }

//     /// Crea un token regulado usando el tipo Coin del módulo
//     public fun create_regulated_token<PAY>(
//         fee: &MultiTokenFee,
//         payment_coin: Coin<PAY>,
//         registry: &mut CoinRegistry,
//         decimals: u8,
//         symbol: String,
//         name: String,
//         description: String,
//         icon_url: String,
//         allow_global_pause: bool,
//         ctx: &mut TxContext
//     ) {
//         process_fee(fee, payment_coin);

//         let (mut initializer, treasury) = coin_registry::new_currency<Token>(
//             registry,decimals, symbol, name, description, icon_url, ctx
//         );
        
//         let deny = coin_registry::make_regulated(&mut initializer, allow_global_pause, ctx);
//         let metadata = initializer.finalize(ctx);

//         let sender = ctx.sender();
//         transfer::public_transfer(treasury, sender);
//         transfer::public_transfer(metadata, sender);
//         transfer::public_transfer(deny, sender);
//     }
// }
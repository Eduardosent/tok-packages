#[allow(lint(self_transfer))]
module tok_issuer::with_otw {
    use sui::coin::{Coin, DenyCapV2, TreasuryCap};
    use sui::coin_registry::{Self, MetadataCap, CoinRegistry, Currency};
    use std::string::{String};
    use tok_fees::multi_token::{Self, MultiTokenFee};
    use sui::transfer::Receiving;

    // === Constants ===
    const ISSUER_FEE_ID: address = @0xc7ad3d5ff0bdf2f9f29271716a4a367d6010698a9d98099ac0ffa5231730846e;

    // === Errors ===
    const EInvalidFeeObject: u64 = 0;
    
    public struct IssuerVault<phantom T> has key {
        id: UID,
        treasury: TreasuryCap<T>,
        metadata: MetadataCap<T>
    }

    public struct RegulatedIssuerVault<phantom T> has key {
        id: UID,
        treasury: TreasuryCap<T>,
        metadata: MetadataCap<T>,
        deny: DenyCapV2<T>
    }

    fun process_fee<PAY>(fee: &MultiTokenFee, payment_coin: Coin<PAY>) {
        assert!(object::id_address(fee) == ISSUER_FEE_ID, EInvalidFeeObject);
        multi_token::pay_fee(fee, payment_coin);
    }

    public fun create_token<T: drop>(
        witness: T,
        decimals: u8,
        symbol: String,
        name: String,
        description: String,
        icon_url: String,
        ctx: &mut TxContext
    ) {
        let (initializer, treasury) = coin_registry::new_currency_with_otw(
            witness, decimals, symbol, name, description, icon_url, ctx
        );

        let metadata = initializer.finalize(ctx);

        let vault = IssuerVault<T> {
            id: object::new(ctx),
            treasury,
            metadata
        };
        // 🔥 IMPORTANTE: owned, no shared
        transfer::transfer(vault, ctx.sender());
    }

    // 🔥 Ahora crea y transfiere la Bóveda Regulada al sender
    public fun create_regulated_token<T: drop>(
        witness: T,
        decimals: u8,
        symbol: String,
        name: String,
        description: String,
        icon_url: String,
        allow_global_pause: bool,
        ctx: &mut TxContext
    ) {
        let (mut initializer, treasury) = coin_registry::new_currency_with_otw(
            witness, decimals, symbol, name, description, icon_url, ctx
        );
        let deny = coin_registry::make_regulated(&mut initializer, allow_global_pause, ctx);
        let metadata = initializer.finalize(ctx);

        let vault = RegulatedIssuerVault<T> {
            id: object::new(ctx),
            treasury,
            metadata,
            deny
        };

        transfer::transfer(vault, ctx.sender());
    }

    /// Paga el fee y recibe los Caps estándar.
    public fun pay_token<T, PAY>(
        fee: &MultiTokenFee,
        coin: Coin<PAY>,
        registry: &mut CoinRegistry,
        currency: Receiving<Currency<T>>,
        vault: IssuerVault<T>,
        ctx: &mut TxContext
    ) {
        process_fee(fee, coin);

        coin_registry::finalize_registration(registry, currency, ctx);

        let IssuerVault { id, treasury, metadata } = vault;
        object::delete(id);

        let sender = ctx.sender();
        transfer::public_transfer(treasury, sender);
        transfer::public_transfer(metadata, sender);
    }

    // 🔥 Ahora recibe la Bóveda Regulada y entrega los 3 Caps
    public fun pay_regulated_token<T, PAY>(
        fee: &MultiTokenFee,
        coin: Coin<PAY>,
        registry: &mut CoinRegistry,
        currency: Receiving<Currency<T>>,
        vault: RegulatedIssuerVault<T>,
        ctx: &mut TxContext
    ) {
        process_fee(fee, coin);
        coin_registry::finalize_registration(registry, currency, ctx);

        let RegulatedIssuerVault { id, treasury, metadata, deny } = vault;
        object::delete(id);

        let sender = ctx.sender();
        transfer::public_transfer(treasury, sender);
        transfer::public_transfer(metadata, sender);
        transfer::public_transfer(deny, sender);
    }
}
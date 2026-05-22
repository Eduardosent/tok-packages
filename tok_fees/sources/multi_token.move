#[allow(lint(self_transfer))]
module tok_fees::multi_token {
    use sui::coin::{ Coin};
    use sui::sui::SUI;
    use sui::clock::{ Clock};
    use std::type_name::{Self, TypeName};
    use tok_fees::config::{Self, GlobalTreasury};

    public struct MultiTokenFee has key, store {
        id: UID,
        prices: vector<TokenFee>,
        recipient: address,
        active: bool,
        last_update: u64,
        lock_period: u64
    }

    public struct TokenFee has store, copy, drop {
        token: TypeName,
        price: u64
    }

    /// Errores de validación
    const EInvalidCreationFee: u64 = 0;
    const EIncorrectPayment: u64 = 1;
    const EServiceNotActive: u64 = 2;
    const ETokenNotAccepted: u64 = 3;
    const EUpdateLocked: u64 = 4;
    const ETokenAlreadyExists: u64 = 5;

    /// Crea el contenedor pagando la cuota a la tesorería
    public fun create_fee(
        global_treasury: &GlobalTreasury,
        payment: Coin<SUI>,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (treasury_address, fee_required) = config::get_treasury_info(global_treasury);
        assert!(payment.value() == fee_required, EInvalidCreationFee);
        
        transfer::public_transfer(payment, treasury_address);

        let fee_obj = MultiTokenFee {
            id: object::new(ctx),
            prices: vector::empty(),
            recipient,
            active: true,
            last_update: clock.timestamp_ms(),
            lock_period: 0
        };

        transfer::public_transfer(fee_obj, ctx.sender());
    }

    /// Pago al servicio buscando en el vector (Optimizado para Gas)
    public fun pay_fee<T>(
        fee_config: &MultiTokenFee,
        payment: Coin<T>
    ) {
        assert!(fee_config.active, EServiceNotActive);
        
        let type_n = type_name::with_defining_ids<T>();
        let prices = &fee_config.prices;
        let len = prices.length();
        let payment_value = payment.value();

        let mut i = 0;
        while (i < len) {
            let entry = &prices[i];
            if (entry.token == type_n) {
                assert!(payment_value == entry.price, EIncorrectPayment);
                transfer::public_transfer(payment, fee_config.recipient);
                return 
            };
            i = i + 1;
        };

        abort ETokenNotAccepted
    }

    // --- Helper de Validación ---

    fun assert_lock_expired(self: &MultiTokenFee, clock: &Clock) {
        assert!(clock.timestamp_ms() >= self.last_update + self.lock_period, EUpdateLocked);
    }

    // --- Funciones Administrativas ---

    public fun add_price<T>(self: &mut MultiTokenFee, amount: u64, clock: &Clock) {
        let type_n = type_name::with_defining_ids<T>();
        let mut i = 0;
        let len = self.prices.length();

        while (i < len) {
            assert!(self.prices[i].token != type_n, ETokenAlreadyExists);
            i = i + 1;
        };

        self.prices.push_back(TokenFee { token: type_n, price: amount });
        self.last_update = clock.timestamp_ms();
    }

    public fun update_price<T>(self: &mut MultiTokenFee, new_amount: u64, clock: &Clock) {
        self.assert_lock_expired(clock);
        
        let type_n = type_name::with_defining_ids<T>();
        let mut i = 0;
        let len = self.prices.length();

        while (i < len) {
            let entry = &mut self.prices[i];
            if (entry.token == type_n) {
                entry.price = new_amount;
                self.last_update = clock.timestamp_ms();
                return 
            };
            i = i + 1;
        };

        abort ETokenNotAccepted
    }

    public fun delete_fee(self: MultiTokenFee, clock: &Clock) {
        self.assert_lock_expired(clock);
        let MultiTokenFee { id, prices: _, .. } = self;
        id.delete();
    }

    // --- Setters y Getters ---

    public fun update_recipient(self: &mut MultiTokenFee, new_recipient: address, clock: &Clock) {
        self.assert_lock_expired(clock);
        self.recipient = new_recipient;
        self.last_update = clock.timestamp_ms();
    }

    public fun set_active(self: &mut MultiTokenFee, status: bool) {
        self.active = status;
    }

    public fun update_lock_period(self: &mut MultiTokenFee, new_period: u64, clock: &Clock) {
        self.assert_lock_expired(clock);
        self.lock_period = new_period;
        self.last_update = clock.timestamp_ms();
    }

    public fun get_service_info(self: &MultiTokenFee): (address, bool, u64, u64) {
        (self.recipient, self.active, self.last_update, self.lock_period)
    }

    public fun get_prices(self: &MultiTokenFee): &vector<TokenFee> {
        &self.prices
    }
}
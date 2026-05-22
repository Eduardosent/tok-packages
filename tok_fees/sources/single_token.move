#[allow(lint(self_transfer))]
module tok_fees::single_token {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use tok_fees::config::{Self, GlobalTreasury};

    public struct SingleTokenFee<phantom T> has key, store {
        id: UID,
        price: u64,   
        recipient: address,
        active: bool,
        last_update: u64,    // Timestamp del último cambio (ms)
        lock_period: u64     // Tiempo de bloqueo obligatorio (ms)
    }

    /// Errores de validación
    const EInvalidCreationFee: u64 = 0;
    const EIncorrectPayment: u64 = 1;
    const EServiceNotActive: u64 = 2;
    const EUpdateLocked: u64 = 3; // El tiempo de bloqueo no ha expirado

    /// Crea un objeto de cobro con transparencia nativa
    public fun create_fee<T>(
        global_treasury: &GlobalTreasury,
        payment: Coin<SUI>,
        price: u64,
        recipient: address,
        lock_period: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (treasury_address, fee_required) = config::get_treasury_info(global_treasury);

        assert!(coin::value(&payment) == fee_required, EInvalidCreationFee);
        transfer::public_transfer(payment, treasury_address);

        let fee_obj = SingleTokenFee<T> {
            id: object::new(ctx),
            price,
            recipient,
            active: true,
            last_update: clock::timestamp_ms(clock),
            lock_period
        };

        transfer::public_transfer(fee_obj, ctx.sender());
    }

    /// Realiza el pago al servicio
    public fun pay_fee<T>(
        fee_config: &SingleTokenFee<T>,
        payment: Coin<T>
    ) {
        assert!(fee_config.active, EServiceNotActive);
        assert!(coin::value(&payment) == fee_config.price, EIncorrectPayment);
        
        transfer::public_transfer(payment, fee_config.recipient);
    }

    // --- Helper Reutilizable de Validación ---

    /// Función interna para validar que el candado de tiempo haya expirado
    fun assert_lock_expired<T>(self: &SingleTokenFee<T>, clock: &Clock) {
        let now = clock::timestamp_ms(clock);
        assert!(now >= self.last_update + self.lock_period, EUpdateLocked);
    }

    // --- Getters ---

    public fun get_fee_info<T>(self: &SingleTokenFee<T>): (u64, address, bool, u64, u64) {
        (self.price, self.recipient, self.active, self.last_update, self.lock_period)
    }

    // --- Funciones Administrativas Protegidas ---

    public fun update_price<T>(self: &mut SingleTokenFee<T>, new_price: u64, clock: &Clock) {
        assert_lock_expired(self, clock);
        self.price = new_price;
        self.last_update = clock::timestamp_ms(clock);
    }

    public fun update_recipient<T>(self: &mut SingleTokenFee<T>, new_recipient: address, clock: &Clock) {
        assert_lock_expired(self, clock);
        self.recipient = new_recipient;
        self.last_update = clock::timestamp_ms(clock);
    }

    public fun update_lock_period<T>(self: &mut SingleTokenFee<T>, new_period: u64, clock: &Clock) {
        assert_lock_expired(self, clock);
        self.lock_period = new_period;
        self.last_update = clock::timestamp_ms(clock);
    }

    /// El estado activo/inactivo se deja fuera del lock por seguridad (pausa de emergencia)
    public fun set_active<T>(self: &mut SingleTokenFee<T>, status: bool) {
        self.active = status;
    }

    public fun delete_fee<T>(self: SingleTokenFee<T>, clock: &Clock) {
        assert_lock_expired(&self, clock);

        let SingleTokenFee { id, .. } = self;
        object::delete(id);
    }
}
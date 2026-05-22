module tok_fees::config {

    /// Capacidad que otorga permisos administrativos sobre el Treasury
    public struct AdminCap has key, store {
        id: UID
    }

    /// El Singleton que consultarán todos tus otros contratos
    public struct GlobalTreasury has key {
        id: UID,
        treasury: address, // Donde caen las comisiones de TOK
        fee: u64          // Costo base por usar tus herramientas
    }

    fun init(ctx: &mut TxContext) {
        // 1. Crear y entregar el AdminCap al publicador
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));

        // 2. Crear el Treasury y hacerlo compartido (Shared)
        // para que tok_dex, tok_lend, etc., puedan leerlo.
        let treasury = GlobalTreasury {
            id: object::new(ctx),
            treasury: tx_context::sender(ctx),
            fee: 10000, // 0.01 SUI de ejemplo (ajustable)
        };
        transfer::share_object(treasury);
    }

    // --- Getters para tus otros contratos (DEX, Lend, Rent) ---

    public fun get_treasury_info(self: &GlobalTreasury): (address, u64) {
        (self.treasury, self.fee)
    }

    public fun get_fee(self: &GlobalTreasury): u64 {
        self.fee
    }

    public fun get_treasury(self: &GlobalTreasury): address {
        self.treasury
    }

    // --- Funciones Administrativas (Requieren AdminCap) ---

    public fun update_fee(_: &AdminCap, treasury: &mut GlobalTreasury, new_fee: u64) {
        treasury.fee = new_fee;
    }

    public fun update_treasury(_: &AdminCap, treasury: &mut GlobalTreasury, new_addr: address) {
        treasury.treasury = new_addr;
    }

    // LA FUNCIÓN QUE EL TEST NECESITA (Sin tocar la lógica de init)
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
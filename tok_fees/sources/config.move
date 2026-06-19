module tok_fees::config {

    /// Error code for unauthorized Cap usage.
    const EWrongCap: u64 = 0;

    /// Administrative capability granted to the deployer on initialization.
    /// Required to call any admin function on GlobalTreasury.
    public struct AdminCap has key, store {
        id: UID
    }

    /// Shared singleton that stores the protocol treasury address and base fee.
    /// Used internally by tok_fees to validate payments when creating fee objects.
    public struct GlobalTreasury has key {
        id: UID,
        treasury: address, // address that receives protocol fees
        fee: u64           // base creation fee in MIST
    }

    /// Capability granted to the fee creator to authorize updates.
    public struct FeeAdminCap has key, store {
        id: UID,
        fee_id: ID, // Linked to the specific fee object ID
    }

    fun init(ctx: &mut TxContext) {
        // create and transfer AdminCap to the deployer
        let admin_cap = AdminCap {
            id: object::new(ctx)
        };
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));

        // create GlobalTreasury and share it so create_fee can read it
        let treasury = GlobalTreasury {
            id: object::new(ctx),
            treasury: tx_context::sender(ctx),
            fee: 10000000, // default: 10000000 MIST, adjustable via update_fee
        };
        transfer::share_object(treasury);
    }

    // === Shared Admin Logic ===

    /// Validates that the provided FeeAdminCap matches the targeted fee object ID.
    public fun assert_cap_match(cap: &FeeAdminCap, fee_id: ID) {
        assert!(cap.fee_id == fee_id, EWrongCap);
    }

    /// Creates the capability and transfers it immediately to the recipient.
    public fun create_and_transfer_admin_cap(fee_id: ID, recipient: address, ctx: &mut TxContext) {
        let cap = FeeAdminCap {
            id: object::new(ctx),
            fee_id
        };
        transfer::public_transfer(cap, recipient);
    }

    // === Getters ===

    /// Returns both treasury address and fee in a single call.
    public fun get_treasury_info(self: &GlobalTreasury): (address, u64) {
        (self.treasury, self.fee)
    }

    /// Returns the current base fee in MIST.
    public fun get_fee(self: &GlobalTreasury): u64 {
        self.fee
    }

    /// Returns the current treasury address.
    public fun get_treasury(self: &GlobalTreasury): address {
        self.treasury
    }

    // === Admin Functions ===

    /// Updates the base fee. Requires AdminCap.
    public fun update_fee(_: &AdminCap, treasury: &mut GlobalTreasury, new_fee: u64) {
        treasury.fee = new_fee;
    }

    /// Updates the treasury address. Requires AdminCap.
    public fun update_treasury(_: &AdminCap, treasury: &mut GlobalTreasury, new_addr: address) {
        treasury.treasury = new_addr;
    }

    /// Test-only entry point that calls init directly.
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
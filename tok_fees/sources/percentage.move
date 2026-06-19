#[allow(lint(self_transfer))]
module tok_fees::percentage {
    use sui::coin::{Coin};
    use sui::sui::SUI;
    use sui::clock::{Clock};
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};

    /// Fee object that charges a percentage fee on processed tokens.
    /// Now shared so administrative functions can be called with the Cap.
    public struct PercentageFee has key, store {
        id: UID,
        basis_points: u16,         // fee percentage in basis points (e.g., 100 = 1.00%)
        recipient: address,        // address that receives incoming fee payments
        last_update: u64,          // timestamp in ms of the last admin update
        lock_period: u64           // minimum ms that must pass between admin updates
    }

    // === Constants ===
    const MAX_BPS: u16 = 10000;    // Represents 100.00%

    // === Errors ===
    const EInvalidCreationFee: u64 = 0;  // payment does not match the required protocol fee
    const EUpdateLocked: u64 = 1;        // lock period has not expired, admin update rejected
    const EInvalidPercentage: u64 = 2;   // percentage exceeds the maximum allowed 100.00%

    /// Creates a PercentageFee object, shares it, and transfers the Admin Cap to the caller.
    public fun create_fee(
        global_treasury: &GlobalTreasury,
        payment: Coin<SUI>,
        basis_points: u16,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (treasury_address, fee_required) = config::get_treasury_info(global_treasury);
        assert!(payment.value() == fee_required, EInvalidCreationFee);
        assert!(basis_points <= MAX_BPS, EInvalidPercentage);
        transfer::public_transfer(payment, treasury_address);

        let fee_obj = PercentageFee {
            id: object::new(ctx),
            basis_points,
            recipient,
            last_update: clock.timestamp_ms(),
            lock_period: 0
        };

        // Create the Admin Cap and transfer it to the creator
        let fee_id = object::id(&fee_obj);
        config::create_and_transfer_admin_cap(fee_id, ctx.sender(), ctx);

        // Make the object shared so it can be managed via Cap
        transfer::public_share_object(fee_obj);
    }

    // === Public On-Chain Getters ===

    public fun get_fee_config(self: &PercentageFee): (u16, address) {
        (self.basis_points, self.recipient)
    }

    // === Internal Helpers ===

    fun assert_lock_expired(self: &PercentageFee, clock: &Clock) {
        assert!(clock.timestamp_ms() >= self.last_update + self.lock_period, EUpdateLocked);
    }

    // === Admin Functions ===

    /// Updates the fee percentage. Requires FeeAdminCap.
    public fun update_percentage(cap: &FeeAdminCap, self: &mut PercentageFee, new_bps: u16, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        assert_lock_expired(self, clock);
        assert!(new_bps <= MAX_BPS, EInvalidPercentage);
        
        self.basis_points = new_bps;
        self.last_update = clock.timestamp_ms();
    }

    /// Updates the recipient address. Requires FeeAdminCap.
    public fun update_recipient(cap: &FeeAdminCap, self: &mut PercentageFee, new_recipient: address) {
        config::assert_cap_match(cap, object::id(self));
        self.recipient = new_recipient;
    }

    /// Updates the lock period. Requires FeeAdminCap.
    public fun update_lock_period(cap: &FeeAdminCap, self: &mut PercentageFee, new_period: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        assert_lock_expired(self, clock);
        self.lock_period = new_period;
        self.last_update = clock.timestamp_ms();
    }

    /// Permanently deletes the fee object. Requires FeeAdminCap.
    public fun delete_fee(cap: &FeeAdminCap, self: PercentageFee, clock: &Clock) {
        config::assert_cap_match(cap, object::id(&self));
        assert_lock_expired(&self, clock);
        let PercentageFee { id, .. } = self;
        id.delete();
    }
}
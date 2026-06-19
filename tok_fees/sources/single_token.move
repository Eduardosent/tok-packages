#[allow(lint(self_transfer))]
module tok_fees::single_token {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};

    /// Fee object for a single token type.
    /// Owned by the service creator after paying the protocol creation fee.
    /// Used to charge users a fixed price in token T for accessing a service.
    public struct SingleTokenFee<phantom T> has key, store {
        id: UID,
        price: u64,          // amount in token T required per payment
        recipient: address,  // address that receives incoming payments
        active: bool,        // if false, pay_fee will abort
        last_update: u64,    // timestamp in ms of the last admin update
        lock_period: u64     // minimum ms that must pass between admin updates
    }

    // === Errors ===
    const EInvalidCreationFee: u64 = 0;  // payment does not match the required protocol fee
    const EIncorrectPayment: u64 = 1;    // payment amount does not match the configured price
    const EServiceNotActive: u64 = 2;   // fee object is paused, payments are rejected
    const EUpdateLocked: u64 = 3;       // lock period has not expired, admin update rejected

    /// Creates a SingleTokenFee object for token T.
    /// Charges the protocol creation fee in SUI before creating the object.
    /// The created object is shared and the Admin Cap transferred to the caller.
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

        // verify the payment matches the required protocol fee exactly
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

        // Create the Admin Cap linked to this new object
        let fee_id = object::id(&fee_obj);
        config::create_and_transfer_admin_cap(fee_id, ctx.sender(), ctx);

        // Make the object shared so everyone can call pay_fee
        transfer::public_share_object(fee_obj);
    }

    /// Accepts a payment in token T and forwards it to the recipient.
    /// Aborts if the fee object is inactive or the payment amount is incorrect.
    public fun pay_fee<T>(
        fee_config: &SingleTokenFee<T>,
        payment: Coin<T>
    ) {
        assert!(fee_config.active, EServiceNotActive);
        assert!(coin::value(&payment) == fee_config.price, EIncorrectPayment);
        transfer::public_transfer(payment, fee_config.recipient);
    }

    // === Internal Helpers ===

    /// Asserts that the lock period has expired since the last update.
    /// Called before any admin mutation to enforce the time lock.
    fun assert_lock_expired<T>(self: &SingleTokenFee<T>, clock: &Clock) {
        let now = clock::timestamp_ms(clock);
        assert!(now >= self.last_update + self.lock_period, EUpdateLocked);
    }

    // === Getters ===

    /// Returns all fee configuration fields as a tuple.
    public fun get_fee_info<T>(self: &SingleTokenFee<T>): (u64, address, bool, u64, u64) {
        (self.price, self.recipient, self.active, self.last_update, self.lock_period)
    }

    // === Admin Functions ===

    /// Updates the price charged per payment. Requires lock period to have expired and FeeAdminCap.
    public fun update_price<T>(cap: &FeeAdminCap, self: &mut SingleTokenFee<T>, new_price: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        assert_lock_expired(self, clock);
        self.price = new_price;
        self.last_update = clock::timestamp_ms(clock);
    }

    /// Updates the recipient address for incoming payments. Requires lock period to have expired and FeeAdminCap.
    public fun update_recipient<T>(cap: &FeeAdminCap, self: &mut SingleTokenFee<T>, new_recipient: address, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        assert_lock_expired(self, clock);
        self.recipient = new_recipient;
        self.last_update = clock::timestamp_ms(clock);
    }

    /// Updates the lock period duration. Requires current lock period to have expired and FeeAdminCap.
    public fun update_lock_period<T>(cap: &FeeAdminCap, self: &mut SingleTokenFee<T>, new_period: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        assert_lock_expired(self, clock);
        self.lock_period = new_period;
        self.last_update = clock::timestamp_ms(clock);
    }

    /// Activates or deactivates the fee object. Requires FeeAdminCap.
    /// Intentionally excluded from the time lock to allow emergency pausing.
    public fun set_active<T>(cap: &FeeAdminCap, self: &mut SingleTokenFee<T>, status: bool) {
        config::assert_cap_match(cap, object::id(self));
        self.active = status;
    }

    /// Permanently deletes the fee object. Requires lock period to have expired and FeeAdminCap.
    public fun delete_fee<T>(cap: &FeeAdminCap, self: SingleTokenFee<T>, clock: &Clock) {
        config::assert_cap_match(cap, object::id(&self));
        assert_lock_expired(&self, clock);
        let SingleTokenFee { id, .. } = self;
        object::delete(id);
    }
}
#[allow(lint(self_transfer))]
module tok_fees::multi_token {
    use sui::coin::{ Coin};
    use sui::sui::SUI;
    use sui::clock::{ Clock};
    use std::type_name::{Self, TypeName};
    use tok_fees::config::{Self, GlobalTreasury, FeeAdminCap};

    /// Fee object that accepts multiple token types as payment.
    /// Owned by the service creator after paying the protocol creation fee.
    /// Stores a vector of accepted tokens and their prices.
    public struct MultiTokenFee has key, store {
        id: UID,
        prices: vector<TokenFee>,  // accepted tokens and their required payment amounts
        recipient: address,        // address that receives incoming payments
        active: bool,              // if false, pay_fee will abort
        last_update: u64,          // timestamp in ms of the last admin update
        lock_period: u64           // minimum ms that must pass between admin updates
    }

    /// Represents a single accepted token and its required payment amount.
    public struct TokenFee has store, copy, drop {
        token: TypeName,  // fully qualified token type identifier
        price: u64        // required payment amount in the token's base unit
    }

    // === Errors ===
    const EInvalidCreationFee: u64 = 0;  // payment does not match the required protocol fee
    const EIncorrectPayment: u64 = 1;    // payment amount does not match the configured price
    const EServiceNotActive: u64 = 2;   // fee object is paused, payments are rejected
    const ETokenNotAccepted: u64 = 3;   // token type is not in the accepted prices vector
    const EUpdateLocked: u64 = 4;       // lock period has not expired, admin update rejected
    const ETokenAlreadyExists: u64 = 5; // token type already has a price entry in the vector

    /// Creates a MultiTokenFee object and transfers it to the caller.
    /// Charges the protocol creation fee in SUI before creating the object.
    /// The prices vector starts empty — use add_price to register accepted tokens.
    public fun create_fee(
        global_treasury: &GlobalTreasury,
        payment: Coin<SUI>,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (treasury_address, fee_required) = config::get_treasury_info(global_treasury);
        // verify payment matches the protocol fee exactly
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

        let fee_id = object::id(&fee_obj);
        config::create_and_transfer_admin_cap(fee_id, ctx.sender(), ctx);

        transfer::public_share_object(fee_obj);
    }

    /// Accepts a payment in token T and forwards it to the recipient.
    /// Searches the prices vector for a matching token type.
    /// Aborts if the fee is inactive, the token is not accepted, or the amount is wrong.
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
                // token found — verify amount and forward payment
                assert!(payment_value == entry.price, EIncorrectPayment);
                transfer::public_transfer(payment, fee_config.recipient);
                return 
            };
            i = i + 1;
        };

        abort ETokenNotAccepted
    }

    // === Internal Helpers ===

    /// Asserts that the lock period has expired since the last admin update.
    /// Called before any admin mutation to enforce the time lock.
    fun assert_lock_expired(self: &MultiTokenFee, clock: &Clock) {
        assert!(clock.timestamp_ms() >= self.last_update + self.lock_period, EUpdateLocked);
    }

    // === Admin Functions ===

    /// Adds a new accepted token and its price to the vector.
    /// Aborts if the token type already exists to prevent duplicates.
    public fun add_price<T>(cap: &FeeAdminCap, self: &mut MultiTokenFee, amount: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        let type_n = type_name::with_defining_ids<T>();
        let mut i = 0;
        let len = self.prices.length();

        // scan vector to ensure no duplicate token type exists
        while (i < len) {
            assert!(self.prices[i].token != type_n, ETokenAlreadyExists);
            i = i + 1;
        };

        self.prices.push_back(TokenFee { token: type_n, price: amount });
        self.last_update = clock.timestamp_ms();
    }

    /// Updates the price for an existing token type. Requires lock period to have expired.
    /// Aborts if the token type is not found in the prices vector.
    public fun update_price<T>(cap: &FeeAdminCap, self: &mut MultiTokenFee, new_amount: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
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

    /// Permanently deletes the fee object. Requires lock period to have expired.
    public fun delete_fee(cap: &FeeAdminCap, self: MultiTokenFee, clock: &Clock) {
        config::assert_cap_match(cap, object::id(&self));
        self.assert_lock_expired(clock);
        let MultiTokenFee { id, prices: _, .. } = self;
        id.delete();
    }

    /// Updates the recipient address for incoming payments. Requires lock period to have expired.
    public fun update_recipient(cap: &FeeAdminCap, self: &mut MultiTokenFee, new_recipient: address, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        self.assert_lock_expired(clock);
        self.recipient = new_recipient;
        self.last_update = clock.timestamp_ms();
    }

    /// Activates or deactivates the fee object.
    /// Intentionally excluded from the time lock to allow emergency pausing.
    public fun set_active(cap: &FeeAdminCap, self: &mut MultiTokenFee, status: bool) {
        config::assert_cap_match(cap, object::id(self));
        self.active = status;
    }

    /// Updates the lock period duration. Requires current lock period to have expired.
    public fun update_lock_period(cap: &FeeAdminCap, self: &mut MultiTokenFee, new_period: u64, clock: &Clock) {
        config::assert_cap_match(cap, object::id(self));
        self.assert_lock_expired(clock);
        self.lock_period = new_period;
        self.last_update = clock.timestamp_ms();
    }

    // === Getters ===

    /// Returns recipient, active status, last update timestamp, and lock period.
    public fun get_service_info(self: &MultiTokenFee): (address, bool, u64, u64) {
        (self.recipient, self.active, self.last_update, self.lock_period)
    }

    /// Returns a reference to the full prices vector.
    public fun get_prices(self: &MultiTokenFee): &vector<TokenFee> {
        &self.prices
    }
}
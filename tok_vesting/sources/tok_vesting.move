#[allow(lint(self_transfer))]
module tok_vesting::vesting {

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event::{Self};
    use std::type_name::{Self, TypeName};
    use tok_fees::multi_token::{Self, MultiTokenFee};

    // === Constants ===

    const VESTING_FEE_ID: address = @0x209826d00371e3186dd899d00358f778aba71fee3d9523c913d5f354377fe805;

    // === Errors ===

    const EInvalidFeeObject: u64 = 0;
    const ECliffNotReached: u64 = 1;
    const ENothingToClaim: u64 = 2;

    // === Structs ===

    /// Vesting schedule for token T. Owned and transferable by the beneficiary.
    /// Destroyed once fully claimed.
    public struct Vesting<phantom T> has key, store {
        id: UID,
        total_amount: u64,       // tokens locked at creation
        balance: Balance<T>,     // remaining tokens
        start_time: u64,         // creation timestamp (ms)
        cliff_time: u64,         // lockup duration before first claim (ms)
        release_amount: u64,     // tokens unlocked per period
        release_period: u64,     // period duration (ms)
    }

    /// Emitted on vesting creation for off-chain indexing.
    public struct VestingCreated has copy, drop {
        vesting_id: ID,
        from: address,
        to: address,
        total_amount: u64,
        coin_type: TypeName,
    }

    // === Public Functions ===

    /// Creates a vesting schedule and sends it to the recipient.
    /// Charges a protocol fee via MultiTokenFee.
    public fun create_vesting<T, PAY>(
        fee: &MultiTokenFee,
        payment: Coin<PAY>,
        coin: Coin<T>,
        cliff_time: u64,
        release_amount: u64,
        release_period: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(object::id_address(fee) == VESTING_FEE_ID, EInvalidFeeObject);
        multi_token::pay_fee(fee, payment);

        let total_amount = coin.value();
        let start_time = clock.timestamp_ms();

        let vesting = Vesting<T> {
            id: object::new(ctx),
            total_amount,
            balance: coin.into_balance(),
            start_time,
            cliff_time,
            release_amount,
            release_period,
        };

        event::emit(VestingCreated {
            vesting_id: object::id(&vesting),
            from: ctx.sender(),
            to: recipient,
            total_amount,
            coin_type: type_name::with_defining_ids<T>(),
        });

        transfer::public_transfer(vesting, recipient);
    }

    /// Claims all unlocked periods since the cliff.
    /// First period is claimable immediately at cliff. Subsequent periods follow release_period.
    /// Final claim handles any residual amount and destroys the vesting object.
    public fun claim<T>(
        mut vesting: Vesting<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let now = clock.timestamp_ms();
        assert!(now >= vesting.start_time + vesting.cliff_time, ECliffNotReached);

        let periods_available = (now - (vesting.start_time + vesting.cliff_time)) / vesting.release_period + 1;
        let periods_claimed = (vesting.total_amount - vesting.balance.value()) / vesting.release_amount;
        let periods_pending = periods_available - periods_claimed;
        assert!(periods_pending > 0, ENothingToClaim);

        let amount = {
            let full = periods_pending * vesting.release_amount;
            let bal = vesting.balance.value();
            if (full >= bal) bal else full
        };

        let coin = coin::take(&mut vesting.balance, amount, ctx);
        transfer::public_transfer(coin, ctx.sender());

        if (vesting.balance.value() == 0) {
            let Vesting { id, total_amount: _, balance, start_time: _, cliff_time: _, release_amount: _, release_period: _ } = vesting;
            object::delete(id);
            balance::destroy_zero(balance);
        } else {
            transfer::public_transfer(vesting, ctx.sender());
        }
    }

    /// Bypasses fee check for unit testing.
    #[test_only]
    public fun create_vesting_for_testing<T>(
        coin: Coin<T>,
        cliff_time: u64,
        release_amount: u64,
        release_period: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let total_amount = coin.value();

        let vesting = Vesting<T> {
            id: object::new(ctx),
            total_amount,
            balance: coin.into_balance(),
            start_time: clock.timestamp_ms(),
            cliff_time,
            release_amount,
            release_period,
        };

        event::emit(VestingCreated {
            vesting_id: object::id(&vesting),
            from: ctx.sender(),
            to: recipient,
            total_amount,
            coin_type: type_name::with_defining_ids<T>(),
        });

        transfer::public_transfer(vesting, recipient);
    }
}
use starknet::{ContractAddress, testing};
use starknet::{contract_address_const};

fn ZERO() -> ContractAddress {
    contract_address_const::<0>()
}

fn pop_log<T, +Drop<T>, +starknet::Event<T>>(address: ContractAddress) -> Option<T> {
    let (mut keys, mut data) = testing::pop_log_raw(address)?;

    // Remove the event ID from the keys
    keys.pop_front();

    let ret = starknet::Event::deserialize(ref keys, ref data);
    assert(data.is_empty(), 'Event has extra data');
    assert(keys.is_empty(), 'Event has extra keys');
    ret
}

/// Asserts that `expected_keys` exactly matches the indexed keys from `event`.
///
/// `expected_keys` must include all indexed event keys for `event` in the order
/// that they're defined.
fn assert_indexed_keys<T, +Drop<T>, +starknet::Event<T>>(event: T, expected_keys: Span<felt252>) {
    let mut keys = array![];
    let mut data = array![];

    event.append_keys_and_data(ref keys, ref data);
    assert(expected_keys == keys.span(), 'Invalid keys');
}

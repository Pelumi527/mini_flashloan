use starknet::{contract_address_const, ContractAddress};

fn ZERO() -> ContractAddress {
    contract_address_const::<0>()
}

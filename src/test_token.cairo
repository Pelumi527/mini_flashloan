use starknet::{get_caller_address, ContractAddress};

#[starknet::interface]
trait ITestToken<TContractState> {
    // @param token_address The erc_20 token you are receiving your flashloan on
    // @param amount The amount of tokens lent.
    // @param fee The additional amount of tokens to repay.
    // @param data Forwarded data from the flash loan request
    fn mint_to(ref self: TContractState, to: ContractAddress, amount: u256,);
}


#[starknet::contract]
mod TestToken {
    use openzeppelin::token::erc20::erc20::ERC20Component::InternalTrait;
    use openzeppelin::token::erc20::erc20::ERC20Component;
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        let name = 'TestToken';
        let symbol = 'TT';

        self.erc20.initializer(name, symbol);
    }

    #[external(v0)]
    impl TestTokenImpl of super::ITestToken<ContractState> {
        fn mint_to(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.erc20._mint(to, amount)
        }
    }
}

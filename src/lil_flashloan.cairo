use starknet::ContractAddress;

// @dev all contract must implement this interface in order to receive a flashload from our smart contract
#[starknet::interface]
trait FlashBorrower<TContractState> {
    // @param token_address The erc_20 token you are receiving your flashloan on
    // @param amount The amount of tokens lent.
    // @param fee The additional amount of tokens to repay.
    // @param data Forwarded data from the flash loan request
    fn onFlashLoan(
        ref self: TContractState,
        token_address: ContractAddress,
        amount: u256,
        fee: u256,
        data: felt252
    );
}

#[starknet::interface]
trait ILilFlashLoan<TContractState> {
    fn flashloan(
        ref self: TContractState,
        receiver: ContractAddress,
        token_address: ContractAddress,
        amount: u256,
        data: felt252
    );
    fn get_flash_fee(
        ref self: TContractState, token_address: ContractAddress, amount: u256
    ) -> u256;
    fn set_flash_fee(ref self: TContractState, token_address: ContractAddress, fee: u256);
    fn max_flashloan(self: @TContractState, token_address: ContractAddress) -> u256;
    fn setSupportToken(ref self: TContractState, token_address: ContractAddress, isSupported: bool);
    fn get_token_fee(self: @TContractState, token_address: ContractAddress) -> u256;
    fn withdraw(ref self: TContractState, amount: u256, token_address: ContractAddress);
    fn is_token_supported(self: @TContractState, token_address: ContractAddress) -> bool;
}

mod Error {
    const UNAUTHORIZED: felt252 = 'UNAUTHORIZED';
    const UNSUPPORTED_TOKEN: felt252 = 'UNSUPPORTED_TOKEN';
    const TOKEN_NOT_RETURNED: felt252 = 'TOKEN_NOT_RETURNED';
    const INVALID_PERCENTAGE: felt252 = 'INVALID_PERCENTAGE';
}

#[starknet::contract]
mod LilFlashLoan {
    use openzeppelin::access::ownable::interface::IOwnable;
    use core::debug::PrintTrait;
    use core::array::Array;
    use core::starknet::event::EventEmitter;
    use mini_flashloan::lil_flashloan::FlashBorrowerDispatcherTrait;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::ownable::OwnableComponent::InternalTrait;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;

    use starknet::{get_caller_address, ContractAddress, get_contract_address};
    use super::Error;
    use super::FlashBorrowerDispatcher;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        supportedToken: LegacyMap::<ContractAddress, bool>,
        token_fee: LegacyMap::<ContractAddress, u256>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        FlashLoaned: FlashLoaned,
        FeeUpdated: FeeUpdated,
        TokenSupportUpdated: TokenSupportUpdated,
        Withdraw: Withdraw
    }


    #[derive(Drop, starknet::Event)]
    struct FlashLoaned {
        #[key]
        receiver: ContractAddress,
        #[key]
        token: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct FeeUpdated {
        #[key]
        token: ContractAddress,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenSupportUpdated {
        #[key]
        token: ContractAddress,
        isSupported: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        token: ContractAddress,
        amount: u256,
    }


    #[constructor]
    fn constructor(ref self: ContractState, _supportedToken: ContractAddress, fee: u256) {
        let caller = get_caller_address();
        self.ownable.initializer(caller);

        self.supportedToken.write(_supportedToken, true);
        self.token_fee.write(_supportedToken, fee);
    }


    #[generate_trait]
    impl InternalFunction of InternalFunctionTrait {
        fn _flashFee(ref self: ContractState, token: ContractAddress, amount: u256) -> u256 {
            let token_fee: u256 = self.token_fee.read(token);
            let fee = amount * token_fee / 10000;
            fee
        }
        fn check_is_token_supported(self: @ContractState, token_address: ContractAddress) {
            assert(self.supportedToken.read(token_address), Error::UNSUPPORTED_TOKEN);
        }
    }

    #[external(v0)]
    impl FlashLoanImpl of super::ILilFlashLoan<ContractState> {
        fn flashloan(
            ref self: ContractState,
            receiver: ContractAddress,
            token_address: ContractAddress,
            amount: u256,
            data: felt252
        ) {
            self.check_is_token_supported(token_address);
            let contract_address = get_contract_address();
            let currentBalance = IERC20Dispatcher { contract_address: token_address }
                .balance_of(contract_address);
            let fee = self._flashFee(token_address, amount);
            IERC20Dispatcher { contract_address: token_address }.transfer(receiver, amount);
            FlashBorrowerDispatcher { contract_address: receiver }
                .onFlashLoan(token_address, amount, fee, data);
            assert(
                IERC20Dispatcher { contract_address: token_address }
                    .balance_of(contract_address) >= (currentBalance + fee),
                Error::TOKEN_NOT_RETURNED
            );

            self.emit(FlashLoaned { receiver: receiver, token: token_address, amount })
        }
        fn get_flash_fee(
            ref self: ContractState, token_address: ContractAddress, amount: u256
        ) -> u256 {
            self.check_is_token_supported(token_address);
            self._flashFee(token_address, amount)
        }
        fn set_flash_fee(ref self: ContractState, token_address: ContractAddress, fee: u256) {
            self.ownable.assert_only_owner();
            self.check_is_token_supported(token_address);
            assert(fee <= 10000, Error::INVALID_PERCENTAGE);
            self.token_fee.write(token_address, fee);
            self.emit(FeeUpdated { token: token_address, fee })
        }
        fn max_flashloan(self: @ContractState, token_address: ContractAddress) -> u256 {
            self.check_is_token_supported(token_address);
            let contract_address = get_contract_address();
            IERC20Dispatcher { contract_address: token_address }.balance_of(contract_address)
        }
        fn setSupportToken(
            ref self: ContractState, token_address: ContractAddress, isSupported: bool
        ) {
            self.ownable.assert_only_owner();
            self.supportedToken.write(token_address, isSupported);
            self.emit(TokenSupportUpdated { token: token_address, isSupported })
        }
        fn get_token_fee(self: @ContractState, token_address: ContractAddress) -> u256 {
            self.check_is_token_supported(token_address);
            self.token_fee.read(token_address)
        }
        fn withdraw(ref self: ContractState, amount: u256, token_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self.check_is_token_supported(token_address);
            let contract_address = get_contract_address();
            IERC20Dispatcher { contract_address: token_address }.transfer(self.owner(), amount);
            self.emit(Withdraw { token: token_address, amount })
        }
        fn is_token_supported(self: @ContractState, token_address: ContractAddress) -> bool {
            self.supportedToken.read(token_address)
        }
    }
}

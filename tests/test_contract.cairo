use core::debug::PrintTrait;
use mini_flashloan::lil_flashloan::{ILilFlashLoanDispatcher, ILilFlashLoanDispatcherImpl};
use mini_flashloan::test_token::{ITestTokenDispatcher, ITestTokenDispatcherImpl};
use super::utils::{assert_indexed_keys, pop_log};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherImpl};
use snforge_std::{declare, ContractClassTrait, start_prank, stop_prank, spy_events};
use starknet::{get_caller_address, ContractAddress};
const INITIAL_SUPPLY: u256 = 0;
fn deploy_contract(name: felt252) -> ContractAddress {
    let contract = declare(name);
    contract.deploy(@ArrayTrait::new()).unwrap()
}

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

// #[starknet::interface]
// trait ITestToken<TContractState> {
//     // @param token_address The erc_20 token you are receiving your flashloan on
//     // @param amount The amount of tokens lent.
//     // @param fee The additional amount of tokens to repay.
//     // @param data Forwarded data from the flash loan request
//     fn mint_to(ref self: TContractState, to: ContractAddress, amount: u256,);
// }

//#[starknet::contract]
// mod TestReceiver {
//     use mini_flashloan::IFlashLoanDispatcher;
//     use mini_flashloan::IFlashLoanDispatcherTrait;
//     use mini_flashloan::test_token::ITestTokenDispatcher;
//     use mini_flashloan::test_token::ITestTokenDispatcherTrait;
//     use openzeppelin::token::erc20::interface::IERC20Dispatcher;
//     use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
//     use starknet::{get_caller_address, ContractAddress};

//     #[storage]
//     struct Storage {
//         shouldRepay: bool,
//         shouldRepayFee: bool
//     }

//     #[external(v0)]
//     impl TestReceiverImpl of super::FlashBorrower<ContractState> {
//         fn onFlashLoan(
//             ref self: ContractState,
//             token_address: ContractAddress,
//             amount: u256,
//             fee: u256,
//             data: felt252
//         ) {
//             let shouldRepay = self.shouldRepay.read();
//             let shouldRepayFee = self.shouldRepayFee.read();
//             if (!shouldRepay) {
//                 return;
//             }
//             let msgSender = get_caller_address();
//             IERC20Dispatcher { contract_address: token_address }.transfer(msgSender, amount);
//             if (!shouldRepayFee) {
//                 return;
//             }
//             let ownedFee = IFlashLoanDispatcher { contract_address: msgSender }
//                 .get_flash_fee(token_address, amount);
//             ITestTokenDispatcher { contract_address: token_address }.mint_to(msgSender, amount);
//         }
//     }
// }

//#[starknet::contract]
// mod TestToken {
//     use openzeppelin::token::erc20::erc20::ERC20Component::InternalTrait;
//     use openzeppelin::token::erc20::erc20::ERC20Component;
//     use starknet::ContractAddress;

//     component!(path: ERC20Component, storage: erc20, event: ERC20Event);

//     #[abi(embed_v0)]
//     impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
//     #[abi(embed_v0)]
//     impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
//     impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

//     #[storage]
//     struct Storage {
//         #[substorage(v0)]
//         erc20: ERC20Component::Storage
//     }

//     #[event]
//     #[derive(Drop, starknet::Event)]
//     enum Event {
//         #[flat]
//         ERC20Event: ERC20Component::Event
//     }

//     #[constructor]
//     fn constructor(ref self: ContractState, initial_supply: u256, recipient: ContractAddress) {
//         let name = 'TestToken';
//         let symbol = 'TT';

//         self.erc20.initializer(name, symbol);
//         self.erc20._mint(recipient, initial_supply);
//     }

//     #[external(v0)]
//     impl TestTokenImpl of super::ITestToken<ContractState> {
//         fn mint_to(ref self: ContractState, to: ContractAddress, amount: u256) {
//             self.erc20._mint(to, amount)
//         }
//     }
// }

fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
    let test_token = deploy_contract('TestToken');
    let test_receiver = deploy_contract('TestReceiver');
    let mut calldata = ArrayTrait::new();
    test_token.serialize(ref calldata);
    INITIAL_SUPPLY.serialize(ref calldata);
   
    let contract = declare('LilFlashLoan');
    let lil_flashloan = contract.deploy(@calldata).unwrap();

    (test_token, test_receiver, lil_flashloan)
}
#[test]
//#[available_gas(2000000)]
fn test_can_flashloan() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    test_token.print();
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 100, '');
    //assert_flashloan_event(test_receiver, test_token, 100);
    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 100, 'incorrect')
}
// #[test]                                             
// fn assert_flashloan_event(receiver: ContractAddress, token: ContractAddress, amount: u256) {
//     let event = pop_log::<FlashLoaned>(ZERO()).unwrap();
//     assert(event.receiver == receiver, 'Invalid `receiver`');
//     assert(event.token == token, 'Invalid `token`');
//     assert(event.amount == amount, 'Invalid `amount`');

//     let mut indexed_keys = array![];
//     indexed_keys.append_serde(from);
//     indexed_keys.append_serde(to);
//     assert_indexed_keys(event, indexed_keys.span());
// }



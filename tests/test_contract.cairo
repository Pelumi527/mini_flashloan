use mini_flashloan::lil_flashloan::ILilFlashLoanDispatcherTrait;
use core::debug::PrintTrait;
use mini_flashloan::lil_flashloan::{
    ILilFlashLoanDispatcher, ILilFlashLoanDispatcherImpl, LilFlashLoan
};
use mini_flashloan::test_token::{
    ITestTokenDispatcher, TestToken, TestToken::{Event::ERC20Event}, ITestTokenDispatcherTrait
};
use super::utils::{assert_indexed_keys, pop_log};
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherImpl, IERC20DispatcherTrait
};
use openzeppelin::token::erc20::ERC20Component;
use snforge_std::{
    declare, EventSpy, ContractClassTrait, start_prank, stop_prank, spy_events, SpyOn, CheatTarget,
    EventAssertions
};
use starknet::{get_caller_address, ContractAddress, contract_address_const};
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
fn test_can_flashloan() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    let mut spy_one = spy_events(SpyOn::Multiple(array![lil_flashloan, test_token, test_receiver]));

    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 100, '');

    spy_one
        .assert_emitted(
            @array![
                (
                    lil_flashloan,
                    LilFlashLoan::Event::FlashLoaned(
                        LilFlashLoan::FlashLoaned {
                            receiver: test_receiver, token: test_token, amount: 100
                        }
                    )
                )
            ]
        );

    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 100, 'incorrect')
}

#[test]
fn test_can_flashloan_with_fees() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .set_flash_fee(test_token, 1000); //10%
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 100, '');
    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 110, 'incorrect')
}

#[test]
fn test_cannot_flasloan_if_not_enough_balance() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
}

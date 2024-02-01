use mini_flashloan::test_receiver::ITestReceiverDispatcherTrait;
use mini_flashloan::lil_flashloan::ILilFlashLoanDispatcherTrait;
use core::debug::PrintTrait;
use mini_flashloan::lil_flashloan::{
    ILilFlashLoanDispatcher, ILilFlashLoanDispatcherImpl, LilFlashLoan, Error
};
use mini_flashloan::test_token::{
    ITestTokenDispatcher, TestToken, TestToken::{Event::ERC20Event}, ITestTokenDispatcherTrait
};
use mini_flashloan::test_receiver::{ITestReceiverDispatcher};
use super::utils::{assert_indexed_keys, pop_log};
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherImpl, IERC20DispatcherTrait
};
use openzeppelin::token::erc20::ERC20Component;
use snforge_std::{
    declare, EventSpy, ContractClassTrait, start_prank, stop_prank, spy_events, SpyOn, CheatTarget,
    EventAssertions
};
use starknet::{get_caller_address, ContractAddress, contract_address_const, get_contract_address};
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
    assert(lil_flashloan_balance == 110, 'Incorrect Balance')
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_cannot_flashloan_if_not_enough_balance() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 110, '');
    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 100, 'Incorrect Balance')
}

#[test]
#[should_panic(expected: ('TOKEN_NOT_RETURNED',))]
fn test_flashloan_reverts_if_not_repaid() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ITestReceiverDispatcher { contract_address: test_receiver }.setRepay(false);
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 100, '');
    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 100, 'Incorrect Balance')
}

#[test]
#[should_panic(expected: ('TOKEN_NOT_RETURNED',))]
fn test_flashloan_reverts_if_fee_not_repaid() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ITestReceiverDispatcher { contract_address: test_receiver }.setRepayFee(false);
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .set_flash_fee(test_token, 1000); //10%
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .flashloan(test_receiver, test_token, 100, '');
    let lil_flashloan_balance = IERC20Dispatcher { contract_address: test_token }
        .balance_of(lil_flashloan);
    assert(lil_flashloan_balance == 100, 'Incorrect Balance')
}

#[test]
fn test_manager_can_set_fee() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    let fee: u256 = 1000;
    let mut spy = spy_events(SpyOn::One(lil_flashloan));
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }.get_token_fee(test_token) == 0,
        'Token Fee Set'
    );
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.set_flash_fee(test_token, fee);
    spy
        .assert_emitted(
            @array![
                (
                    lil_flashloan,
                    LilFlashLoan::Event::FeeUpdated(
                        LilFlashLoan::FeeUpdated { token: test_token, fee }
                    )
                )
            ]
        );
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }
            .get_token_fee(test_token) == fee,
        'Token Fee Not Set'
    );
}
#[test]
#[should_panic(expected: ('INVALID_PERCENTAGE',))]
fn test_fee_should_not_exceed_100_percent() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }.get_token_fee(test_token) == 0,
        'Token Fee Set'
    );
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.set_flash_fee(test_token, 10001);
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }.get_token_fee(test_token) == 0,
        'Token Fee Set'
    );
}
#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_non_manager_cannot_set_fee() {
    let (test_token, test_receiver, lil_flashloan) = setup();
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }.get_token_fee(test_token) == 0,
        'Token Fee Set'
    );
    let caller_address: ContractAddress = 123.try_into().unwrap();
    start_prank(CheatTarget::One(lil_flashloan), caller_address);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.set_flash_fee(test_token, 1000);
    assert(
        ILilFlashLoanDispatcher { contract_address: lil_flashloan }.get_token_fee(test_token) == 0,
        'Token Fee Set'
    );
}
#[test]
fn test_manager_can_withdraw() {
    let manager = get_contract_address();
    let (test_token, test_receiver, lil_flashloan) = setup();
    let mut spy = spy_events(SpyOn::One(lil_flashloan));
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    assert(
        IERC20Dispatcher { contract_address: test_token }.balance_of(manager) == 0, 'Has a balance'
    );
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.withdraw(50, test_token);
    spy
        .assert_emitted(
            @array![
                (
                    lil_flashloan,
                    LilFlashLoan::Event::Withdraw(
                        LilFlashLoan::Withdraw { amount: 50, token: test_token }
                    )
                )
            ]
        );
    assert(
        IERC20Dispatcher { contract_address: test_token }.balance_of(manager) == 50, 'Wrong Balance'
    );
}

#[test]
fn test_manager_can_add_support_token() {
    let manager = get_contract_address();
    let (test_token, test_receiver, lil_flashloan) = setup();
    let mut spy = spy_events(SpyOn::One(lil_flashloan));
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    spy
        .assert_emitted(
            @array![
                (
                    lil_flashloan,
                    LilFlashLoan::Event::TokenSupportUpdated(
                        LilFlashLoan::TokenSupportUpdated { token: test_token, isSupported: true }
                    )
                )
            ]
        );
    let is_supported = ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .is_token_supported(test_token);
    assert(is_supported, 'Token is Not Supported');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_non_manager_cannot_set_supported_token () {
    let (test_token, test_receiver, lil_flashloan) = setup();
    let mut spy = spy_events(SpyOn::One(lil_flashloan));
    let caller_address: ContractAddress = 123.try_into().unwrap();
    start_prank(CheatTarget::One(lil_flashloan), caller_address);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    let is_supported = ILilFlashLoanDispatcher { contract_address: lil_flashloan }
        .is_token_supported(test_token);
    assert(!is_supported, 'Token is Supported');

}
#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_non_manager_cannot_withdraw() {
    let manager = get_contract_address();
    let (test_token, test_receiver, lil_flashloan) = setup();
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.setSupportToken(test_token, true);
    ITestTokenDispatcher { contract_address: test_token }.mint_to(lil_flashloan, 100);
    assert(
        IERC20Dispatcher { contract_address: test_token }.balance_of(manager) == 0, 'Has a balance'
    );
    let caller_address: ContractAddress = 123.try_into().unwrap();
    start_prank(CheatTarget::One(lil_flashloan), caller_address);
    ILilFlashLoanDispatcher { contract_address: lil_flashloan }.withdraw(50, test_token);
    assert(
        IERC20Dispatcher { contract_address: test_token }.balance_of(caller_address) == 0,
        'Wrong Balance'
    );
    assert(
        IERC20Dispatcher { contract_address: test_token }.balance_of(lil_flashloan) == 100,
        'Wrong Balance'
    );
}

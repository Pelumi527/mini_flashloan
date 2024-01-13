use starknet::{get_caller_address, ContractAddress};


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

#[starknet::contract]
mod TestReceiver {
    use mini_flashloan::lil_flashloan::ILilFlashLoanDispatcher;
    use mini_flashloan::lil_flashloan::ILilFlashLoanDispatcherTrait;
    use mini_flashloan::test_token::ITestTokenDispatcher;
    use mini_flashloan::test_token::ITestTokenDispatcherTrait;
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use starknet::{get_caller_address, ContractAddress};
    #[storage]
    struct Storage {
        shouldRepay: bool,
        shouldRepayFee: bool
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.shouldRepay.write(true);
        self.shouldRepayFee.write(true);
    }

    #[external(v0)]
    impl TestReceiverImpl of super::FlashBorrower<ContractState> {
        fn onFlashLoan(
            ref self: ContractState,
            token_address: ContractAddress,
            amount: u256,
            fee: u256,
            data: felt252
        ) {
            let shouldRepay = self.shouldRepay.read();
            let shouldRepayFee = self.shouldRepayFee.read();
            if (!shouldRepay) {
                return;
            }
            let msgSender = get_caller_address();
            IERC20Dispatcher { contract_address: token_address }.transfer(msgSender, amount);
            if (!shouldRepayFee) {
                return;
            }
            let ownedFee = ILilFlashLoanDispatcher { contract_address: msgSender }
                .get_flash_fee(token_address, amount);
            ITestTokenDispatcher { contract_address: token_address }.mint_to(msgSender, ownedFee);
        }
    }
}

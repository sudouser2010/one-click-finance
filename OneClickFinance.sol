pragma solidity 0.8.19;
pragma abicoder v2;
// SPDX-License-Identifier: BSD-Protection
// Author: Hadron DaVinci




interface LpContract{
    function getReserves() external view returns (uint256, uint256, uint256);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

interface TokenContract{
    function approve(address spender, uint256 amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

interface RouterContract{
    function swapExactTokensForTokens(
        uint256 amountIn, uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);
    function getAmountsOut(
        uint256 amountIn, address[] memory path
    ) external view returns (uint256[] memory);
    function addLiquidity(
        address tokenA, address tokenB,
        uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external;
    function removeLiquidity(
        address tokenA, address tokenB,
        uint256 liquidity,
        uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external;
}
interface RouterContractStartingSwapTime{
    function addLiquidity(
        address tokenA, address tokenB,
        uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin,
        address to,
        uint256 deadline,
        uint256 startingSwapTime
    ) external;
}

contract OneClickFinanceV1{

   address admin;
   constructor() {
      admin = msg.sender;
   }

    // for events
    event cow_say_moo_int(string variable, uint256 value);
    event cow_say_moo_address(string variable, address value);
    event cow_say_moo_addresses(string variable, address[] value);

    // forward path from tokenA to tokenB
    struct Path {
        address[] forward_path;
        address[] reverse_path;
        uint256 tokenA_amount;
        uint256 tokenB_amount;
    }


    // ---------------------------- HELPER FUNCTIONS
    function approve_zero_then_amount(
        address token,
        address spender,
        uint256 amount_to_approve
    ) internal {
        /*
            To work with tokens that require approving to zero before
            approving the desired the amount_to_approve
        */
        TokenContract(token).approve(spender, 0);
        TokenContract(token).approve(spender, amount_to_approve);
    }

    function fund_contract(address token, uint256 amount) internal {
        // transfer tokens from user to contract
        bool success = TokenContract(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer To Contract Failed");
    }

    function reward_admin(address input_token, uint256 input_token_amount) internal returns (uint256) {
        /*
            .5% of input tokens are transferred to admin
        */
        uint256 input_token_reward = input_token_amount * 5 / 1000;
        bool success = TokenContract(input_token).transfer(admin, input_token_reward);
        require(success, "Transfer Reward Amount To Admin Failed");
        return input_token_reward;
    }

    function swap(
        address router,
        uint256 tokenA_amount,
        uint256 tokenB_amount,
        uint256 swap_tolerance,
        address[] memory path
    ) internal returns (uint256) {
        /*
            * swap (tokenA_amount) of tokenA for (tokenB_amount) of tokenB
            * returns tokenB_actual_amount
        */

        if (tokenA_amount == 0) {
            // no need to swap if amount is zero
            emit cow_say_moo_address("(TokenA Is Zero, No Swap Needed):", path[0]);
            return 0;
        }

        address tokenA = path[0];
        address tokenB = path[path.length - 1];

        // if first and last addresses are same, then return the input amount
        // since no swap was needed and tokenB_amount equals tokenA_amount
        if (tokenA == tokenB) {
            emit cow_say_moo_addresses("(TokenA Equals TokenB, No Swap Needed):", path);
            return tokenA_amount;
        }


        // contract should have atleast the input tokenA_amount of tokenA
        TokenContract tokenA_contract = TokenContract(tokenA);
        require(tokenA_contract.balanceOf(address(this)) >= tokenA_amount, "NOT ENOUGH tokenA FUNDS TO TRADE");

        // approve tokenA for router interaction
        approve_zero_then_amount(tokenA, router, tokenA_amount);

        // calculate the min tokenB amount
        uint256 min_tokenB_amount = tokenB_amount * swap_tolerance/1000;

        // do the actual swap with router
        // swap fails when tokenB_amount is less than tokenB_expected_amount
        RouterContract router_contract = RouterContract(router);
        uint256[] memory actual_amounts_out =  router_contract.swapExactTokensForTokens(
            tokenA_amount,
            min_tokenB_amount,
            path,
            address(this),
            block.timestamp + 30
        );

        // return tokenB_amount
        return actual_amounts_out[actual_amounts_out.length - 1];
    }

    function transfer_max_amount(address token_address) internal returns (uint256) {
        // sends maximum amount of token back to user

        TokenContract token = TokenContract(token_address);
        uint256 token_balance = token.balanceOf(address(this));

        if (token_balance > 0) {
            bool success = token.transfer(msg.sender, token_balance);
            require(success, "Transfer MaxAmount Failed");
        }

        emit cow_say_moo_int("(Transfer Max Amount) Amount Transferred:", token_balance);
        return token_balance;
    }
    // ---------------------------- HELPER FUNCTIONS


    //-------------------------------------------------GET LP CODE
    function obtain_lp_tokens(
        address lp_token,

        address router,
        bool useStartingSwapTime,

        address token0,
        address token1,
        uint256 token0_amount,
        uint256 token1_amount
    ) internal returns (uint256) {
        /*
        Adds Liquidity by exchanging token0 and token1 for LP token
        */

        // approve token0 and token1 for router interaction
        approve_zero_then_amount(token0, router, token0_amount);
        approve_zero_then_amount(token1, router, token1_amount);

        uint256 lp_tokens_before = LpContract(lp_token).balanceOf(address(this));
        uint256 deadline = block.timestamp + 30;


        if (useStartingSwapTime) {
            RouterContractStartingSwapTime(router).addLiquidity(
                token0,
                token1,
                token0_amount,
                token1_amount,
                0,
                0,
                address(this),
                deadline,

                // for startingSwapTime parameter
                // price was calculated off-chain so we don't need to wait
                0
            );
        } else {
            RouterContract(router).addLiquidity(
                token0,
                token1,
                token0_amount,
                token1_amount,
                0,
                0,
                address(this),
                deadline
            );
        }


        uint256 lp_tokens_after = LpContract(lp_token).balanceOf(address(this));
        uint256 lp_tokens_obtained = lp_tokens_after - lp_tokens_before;

        return lp_tokens_obtained;
    }


    function obtain_base_token_from_dust_path(
        address router,
        address[] memory tokenX_to_base_token_path
    )
    internal {
        /*
        Objective of this code is to get rid of any TokenX (dust)
        by converting it to base_token
        */

        // get contract's balance of tokenX
        uint256 contract_tokenX_balance = TokenContract(
            tokenX_to_base_token_path[0]
        ).balanceOf(address(this));
        emit cow_say_moo_int("(Dust Token Amount):", contract_tokenX_balance);


        // Since dust is expected to be small, we don't have to worry about front running.
        // so we use a swap tolerance of zero
        swap(
            router,
            contract_tokenX_balance,
            0,
            0,
            tokenX_to_base_token_path
        );
    }


    function get_lp(
        address base_token,
        uint256 base_token_amount,
        uint256 swap_tolerance,
        address lp_token,

        address router,
        address swap_router,
        bool useStartingSwapTime,

        Path memory base_token_to_token0__path,
        Path memory base_token_to_token1__path
    ) public returns (uint256) {
        /*
        Converts base_token into lp_token
        */


        // transfer base token to contract
        fund_contract(
            base_token,
            base_token_amount
        );

        // pay admin fee
        uint256 admin_reward_amount = reward_admin(base_token, base_token_amount);
        uint256 base_token_amount_minus_reward = base_token_amount - admin_reward_amount;

        // contract uses funded base_token to get lp_token
        // then transfers the lp_token to user
        {

            // obtain token0 amount for pool
            uint256 amount_token0_obtained = swap(
                swap_router,
                base_token_amount_minus_reward / 2,
                base_token_to_token0__path.tokenB_amount,
                swap_tolerance,
                base_token_to_token0__path.forward_path
            );
            // obtain token1 amount for pool
            uint256 amount_token1_obtained = swap(
                swap_router,
                base_token_amount_minus_reward / 2,
                base_token_to_token1__path.tokenB_amount,
                swap_tolerance,
                base_token_to_token1__path.forward_path
            );

            // emit amounts obtained
            emit cow_say_moo_int("(Token0 Obtained):", amount_token0_obtained);
            emit cow_say_moo_int("(Token1 Obtained):", amount_token1_obtained);

            // obtain lp tokens
            obtain_lp_tokens(
                lp_token,
                router,
                useStartingSwapTime,

                base_token_to_token0__path.reverse_path[0],  // for token0
                base_token_to_token1__path.reverse_path[0],  // for token1
                amount_token0_obtained,
                amount_token1_obtained
            );


        }

        // convert any left over token0 and token1 dust back to base_token
        obtain_base_token_from_dust_path(
            swap_router,
            base_token_to_token0__path.reverse_path
        );
        obtain_base_token_from_dust_path(
            swap_router,
            base_token_to_token1__path.reverse_path
        );


        // transfer max base_token back to user
        transfer_max_amount(base_token);

        // transfer max lp_token back to user
        uint256 lp_token_amount_obtained = transfer_max_amount(lp_token);

        return lp_token_amount_obtained;
    }
    //-------------------------------------------------GET LP CODE


    //-------------------------------------------------GET BASE-TOKEN CODE
   function obtain_token0_and_token1(
        address lp_token,
        uint256 lp_token_amount,
        address router,
        address token0,
        address token1
    ) internal {
        /*
        Removes Liquidity by exchanging LP token for token0 and token1
        */

        // approve lp_token for router interaction
        approve_zero_then_amount(lp_token, router, lp_token_amount);

        // decompose lp_token into token0 and token1
        RouterContract(router).removeLiquidity(
            token0, token1,
            lp_token_amount,
            0, 0,
            address(this),
            block.timestamp + 30
        );
    }

    function get_base_token(
        address lp_token,
        uint256 lp_token_amount,
        address base_token,
        uint256 swap_tolerance,

        address router,
        address swap_router,
        address token0,
        address token1,
        Path memory token0_to_base_token__path,
        Path memory token1_to_base_token__path
    ) public returns (uint256) {
        /*
        Converts lp_token into base_token
        */


        // transfer lp_token to contract
        fund_contract(
            lp_token,
            lp_token_amount
        );

        // contract uses funded lp_token to get base_token
        // then transfers the base_token to user
        {

            // obtain token0 and token1
            obtain_token0_and_token1(
                lp_token,
                lp_token_amount,
                router,
                token0,
                token1
            );


            uint256 token0_amount = TokenContract(token0).balanceOf(address(this));
            uint256 token1_amount = TokenContract(token1).balanceOf(address(this));

            // obtain base_token from token0
            swap(
                swap_router,
                token0_amount,
                token0_to_base_token__path.tokenB_amount,
                swap_tolerance,
                token0_to_base_token__path.forward_path
            );

            // obtain base_token from token1
            swap(
                swap_router,
                token1_amount,
                token1_to_base_token__path.tokenB_amount,
                swap_tolerance,
                token1_to_base_token__path.forward_path
            );

        }

        // pay admin fee
        TokenContract token = TokenContract(base_token);
        uint256 base_token_amount = token.balanceOf(address(this));
        reward_admin(base_token, base_token_amount);

        // transfer max base_token back to user
        uint256 base_token_obtained = transfer_max_amount(base_token);
        return base_token_obtained;

    }
    //-------------------------------------------------GET BASE-TOKEN CODE

}

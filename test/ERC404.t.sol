// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ExampleERC404} from "../src/examples/ExampleERC404.sol";

contract ERC404Test is Test {
    // Test addresses
    address ALICE = address(0xc02Aaa39b223fE8d0a0e5C4F27EAd9022C756cC2);
    address BOB = address(0xC02Aaa39b223Fe8d0a0E5c4F27EAD9022c752cc2);

    // Deployment params
    string name = "Example";
    string symbol = "EXM";
    uint8 decimals = 18;
    uint256 units = 10 ** decimals;
    uint256 maxTotalSupplyERC721 = 100;
    uint256 maxTotalSupplyERC20 = maxTotalSupplyERC721 * units;

    ExampleERC404 token;

    function setUp() public {
        token = new ExampleERC404(name, symbol, decimals, maxTotalSupplyERC721, address(this), address(this));

        // Transfer tokens to non-deployer
        token.setWhitelist(address(this), true);
        token.transfer(ALICE, token.balanceOf(address(this)));
    }

    function testWholeTokenReceive() public {
        uint256 senderBalanceBefore = token.balanceOf(ALICE);
        uint256 fractionalAmount = (9 * units) / 10;

        // Transfer partial token to BOB
        vm.prank(ALICE);
        token.transfer(BOB, fractionalAmount);

        // BOB should have received fractional representation but no ERC721
        assertEq(token.balanceOf(BOB), fractionalAmount);
        assertEq(token.erc721BalanceOf(BOB), 0);

        assertEq(token.balanceOf(ALICE), senderBalanceBefore - fractionalAmount);
        assertEq(token.erc721BalanceOf(ALICE), 99);

        fractionalAmount = units / 10;

        // Transfer the rest to BOB
        vm.prank(ALICE);
        token.transfer(BOB, fractionalAmount);

        // BOB should now have received a full ERC721 along with fractional
        assertEq(token.balanceOf(BOB), units);
        assertEq(token.erc721BalanceOf(BOB), 1);

        assertEq(token.balanceOf(ALICE), senderBalanceBefore - units);
        assertEq(token.erc721BalanceOf(ALICE), 99);
    }

    function testPartialSendWithRevokedToken() public {
        uint256 senderBalanceBefore = token.balanceOf(ALICE);

        // Transfer a whole token to BOB
        vm.prank(ALICE);
        token.transfer(BOB, units);

        assertEq(token.balanceOf(BOB), units);
        assertEq(token.erc721BalanceOf(BOB), 1);

        assertEq(token.balanceOf(ALICE), senderBalanceBefore - units);
        assertEq(token.erc721BalanceOf(ALICE), 99);

        // Transfer partial token back to ALICE
        vm.prank(BOB);
        token.transfer(ALICE, units / 10);

        // BOB should have lost the ERC721
        assertEq(token.balanceOf(BOB), units - units / 10);
        assertEq(token.erc721BalanceOf(BOB), 0);

        assertEq(token.balanceOf(ALICE), senderBalanceBefore - (9 * units) / 10);
        assertEq(token.erc721BalanceOf(ALICE), 99);
    }

    function testTransferWholeTokens() public {
        uint256 senderBalanceBefore = token.balanceOf(ALICE);

        // Transfer two tokens to BOB
        vm.prank(ALICE);
        token.transfer(BOB, 2 * units);

        // Verify ERC20 balances after transfer
        assertEq(token.balanceOf(BOB), 2 * units);
        assertEq(token.balanceOf(ALICE), senderBalanceBefore - 2 * units);

        // Verify ERC721 balances after transfer
        assertEq(token.erc721BalanceOf(BOB), 2);
        assertEq(token.erc721BalanceOf(ALICE), 98);
    }

    function testTransferMultiPath() public {
        uint256 senderBalanceBefore = token.balanceOf(ALICE);

        // Transfer 0.9 tokens to BOB
        vm.prank(ALICE);
        token.transfer(BOB, (9 * units) / 10);

        // BOB should have 0.9 tokens and no ERC721
        assertEq(token.balanceOf(BOB), (9 * units) / 10);
        assertEq(token.erc721BalanceOf(BOB), 0);

        vm.prank(ALICE);
        token.transfer(BOB, (32 * units) / 10);

        // BOB should have 4.1 tokens and 4 ERC721
        assertEq(token.balanceOf(BOB), (41 * units) / 10);
        assertEq(token.erc721BalanceOf(BOB), 4);

        assertEq(token.balanceOf(ALICE), senderBalanceBefore - (41 * units) / 10);
        assertEq(token.erc721BalanceOf(ALICE), 95);
    }
}

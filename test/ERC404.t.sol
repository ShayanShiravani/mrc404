// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ExampleERC404} from "../src/examples/ExampleERC404.sol";

contract PandoraTest is Test {
    // Test addresses
    address ALICE = address(0xc02Aaa39b223fE8d0a0e5C4F27EAd9022C756cC2);
    address BOB = address(0xC02Aaa39b223Fe8d0a0E5c4F27EAD9022c752cc2);

    // Deployment params
    string name = "Example";
    string symbol = "EXM";
    uint256 decimals = 18;
    uint256 units = 10 ** decimals;
    uint256 maxTotalSupplyERC721 = 100;
    uint256 maxTotalSupplyERC20 = maxTotalSupplyERC721 * units;

    ExampleERC404 token;

    function setUp() public {
        token = new ExampleERC404(name, symbol, decimals, maxTotalSupplyERC721, address(this), address(this));
    }
}

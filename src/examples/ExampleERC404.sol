//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC404} from "./erc404/ERC404.sol";
import {ERC404MerkleClaim} from "./erc404/extensions/ERC404MerkleClaim.sol";

contract ExampleERC404 is Ownable, ERC404, ERC404MerkleClaim {
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    uint256 maxTotalSupplyERC721_,
    address initialOwner_,
    address initialMintRecipient_
  )
    ERC404(name_, symbol_, decimals_, maxTotalSupplyERC721_)
    Ownable(initialOwner_)
  {
    // Do not mint the ERC721s to the initial owner, as it's a waste of gas.
    _setWhitelist(initialMintRecipient_, true);
    _mintERC20(initialMintRecipient_, maxTotalSupplyERC20, false);
  }

  function tokenURI(uint256 id) public pure override returns (string memory) {
    return string.concat("https://example.com/token/", Strings.toString(id));
  }

  function airdropMint(
    bytes32[] memory proof_,
    uint256 value_
  ) public override whenAirdropIsOpen {
    super.airdropMint(proof_, value_);
    _mintERC20(_msgSender(), value_, true);
  }

  function setAirdropMerkleRoot(bytes32 airdropMerkleRoot_) external onlyOwner {
    _setAirdropMerkleRoot(airdropMerkleRoot_);
  }

  function toggleAirdropIsOpen() external onlyOwner {
    _toggleAirdropIsOpen();
  }

  function setWhitelist(address account, bool value) external onlyOwner {
    _setWhitelist(account, value);
  }
}

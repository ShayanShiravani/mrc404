//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC404} from "./IERC404.sol";
import {ERC721Receiver} from "../lib/ERC721Receiver.sol";

abstract contract ERC404 is Context, IERC404 {
  using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

  /// @dev The queue of ERC721 tokens stored in the contract.
  DoubleEndedQueue.Bytes32Deque private _storedERC721Ids;

  /// @dev Token name
  string public name;

  /// @dev Token symbol
  string public symbol;

  /// @dev Decimals for ERC20 representation
  uint8 public immutable decimals;

  /// @dev Units for ERC20 representation
  uint256 public immutable units;

  /// @dev Max supply for ERC20 representation
  uint256 public immutable maxTotalSupplyERC20;

  /// @dev Max supply for ERC721 representation
  uint256 public immutable maxTotalSupplyERC721;

  /// @dev Total supply in ERC20 representation
  uint256 public totalSupply;

  /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
  uint256 public minted;

  /// @dev Balance of user in ERC20 representation
  mapping(address => uint256) public balanceOf;

  /// @dev Allowance of user in ERC20 representation
  mapping(address => mapping(address => uint256)) public allowance;

  /// @dev Approval in ERC721 representaion
  mapping(uint256 => address) public getApproved;

  /// @dev Approval for all in ERC721 representation
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /// @dev Owner of id in ERC721 representation
  mapping(uint256 => address) internal _ownerOf;

  /// @dev Array of owned ids in ERC721 representation
  mapping(address => uint256[]) internal _owned;

  /// @dev Tracks indices for the _owned mapping
  mapping(uint256 => uint256) internal _ownedIndex;

  /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
  mapping(address => bool) public whitelist;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256 _maxTotalSupplyERC721
  ) {
    name = _name;
    symbol = _symbol;

    if (_decimals < 18) {
      revert DecimalsTooLow();
    }

    decimals = _decimals;
    units = 10 ** decimals;
    maxTotalSupplyERC721 = _maxTotalSupplyERC721;
    maxTotalSupplyERC20 = maxTotalSupplyERC721 * units;
  }

  /// @notice Function to find owner of a given ERC721 token
  function ownerOf(uint256 id) public view virtual returns (address nftOwner) {
    nftOwner = _ownerOf[id];

    if (nftOwner == address(0)) {
      revert NotFound();
    }
  }

  function erc721BalanceOf(
    address owner_
  ) public view virtual returns (uint256) {
    return _owned[owner_].length;
  }

  function erc20BalanceOf(
    address owner_
  ) public view virtual returns (uint256) {
    return balanceOf[owner_];
  }

  /// @notice tokenURI must be implemented by child contract
  function tokenURI(uint256 id) public view virtual returns (string memory);

  /// @notice Function for token approvals
  /// @dev This function assumes id ERC721 if value less than or equal to current max id
  function approve(
    address spender,
    uint256 valueOrId
  ) public virtual returns (bool) {
    if (valueOrId <= minted && valueOrId > 0) {
      // Intention is to approve as ERC-721 token (id).
      uint256 id = valueOrId;
      address nftOwner = _ownerOf[id];

      if (
        _msgSender() != nftOwner && !isApprovedForAll[nftOwner][_msgSender()]
      ) {
        revert Unauthorized();
      }

      getApproved[id] = spender;

      emit Approval(nftOwner, spender, id);
      emit ERC721Approval(nftOwner, spender, id);
    } else {
      // Intention is to approve as ERC-20 token (value).
      uint256 value = valueOrId;
      allowance[_msgSender()][spender] = value;

      emit Approval(_msgSender(), spender, value);
      emit ERC20Approval(_msgSender(), spender, value);
    }

    return true;
  }

  /// @notice Function for ERC721 approvals
  function setApprovalForAll(address operator, bool approved) public virtual {
    isApprovedForAll[_msgSender()][operator] = approved;
    emit ApprovalForAll(_msgSender(), operator, approved);
  }

  /// @notice Function for mixed transfers
  /// @dev This function assumes id ERC721 if value less than or equal to current max id
  function transferFrom(
    address from,
    address to,
    uint256 valueOrId
  ) public virtual {
    if (valueOrId <= minted) {
      // Intention is to transfer as ERC-721 token (id).
      uint256 id = valueOrId;
      if (from != _ownerOf[id]) {
        revert InvalidSender();
      }

      // TODO: Redundant, already in _transferERC20
      if (to == address(0)) {
        revert InvalidRecipient();
      }

      if (
        _msgSender() != from &&
        !isApprovedForAll[from][_msgSender()] &&
        _msgSender() != getApproved[id]
      ) {
        revert Unauthorized();
      }

      // Transfer 1 * units ERC20 and 1 ERC721 token.
      _transferERC20(from, to, units);
      _transferERC721(from, to, id);
    } else {
      // Intention is to transfer as ERC-20 token (value).
      uint256 value = valueOrId;
      uint256 allowed = allowance[from][_msgSender()];

      if (allowed != type(uint256).max) {
        if (allowed < value) {
          revert InsufficientAllowance();
        }
        allowance[from][_msgSender()] = allowed - value;
      }

      // Transferring ERC20s directly requires the _transfer function.
      _transfer(from, to, value);
    }
  }

  /// @notice Function for ERC20 transfers
  function transfer(address to, uint256 value) public virtual returns (bool) {
    return _transfer(_msgSender(), to, value);
  }

  /// @notice Function for ERC721 transfers with contract support
  function safeTransferFrom(
    address from,
    address to,
    uint256 id
  ) public virtual {
    transferFrom(from, to, id);

    if (
      to.code.length != 0 &&
      ERC721Receiver(to).onERC721Received(_msgSender(), from, id, "") !=
      ERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  /// @notice Function for ERC721 transfers with contract support and callback data
  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    bytes calldata data
  ) public virtual {
    transferFrom(from, to, id);

    if (
      to.code.length != 0 &&
      ERC721Receiver(to).onERC721Received(_msgSender(), from, id, data) !=
      ERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  // TODO: consider how minting and burning should be handled.
  function _transferERC20(address from, address to, uint256 value) internal {
    if (from == address(0) || to == address(0)) {
      revert InvalidRecipient();
    }

    if (balanceOf[from] < value) {
      revert InsufficientBalance();
    }

    balanceOf[from] -= value;

    unchecked {
      balanceOf[to] += value;
    }

    emit Transfer(from, to, value);
    emit ERC20Transfer(from, to, value);
  }

  /// @notice Consolidated record keeping function for transferring ERC721s.
  /// @dev Assign the token to the new owner, and remove from the old owner.
  function _transferERC721(
    address from,
    address to,
    uint256 id
  ) public virtual {
    _ownerOf[id] = to;

    // On transfer of an NFT, any previous approval is reset.
    delete getApproved[id];

    // update _owned for sender
    // Last
    uint256 updatedId = _owned[from][_owned[from].length - 1];
    _owned[from][_ownedIndex[id]] = updatedId;
    // pop
    _owned[from].pop();
    // update index for the moved id
    _ownedIndex[updatedId] = _ownedIndex[id];
    // push token to to owned
    _owned[to].push(id);
    // update index for to owned
    _ownedIndex[id] = _owned[to].length - 1;

    emit Transfer(from, to, id);
    emit ERC721Transfer(from, to, id);
  }

  /// @notice Internal function for ERC20 transfers. Also handles any NFT transfers that may be required.
  function _transfer(
    address from,
    address to,
    uint256 value
  ) internal returns (bool) {
    uint256 balanceBeforeSender = balanceOf[from];
    uint256 balanceBeforeReceiver = balanceOf[to];

    _transferERC20(from, to, value);

    // Skip _withdrawAndStoreERC721 and/or _retrieveOrMintERC721 for whitelisted addresses 1) to save gas, 
    // and 2) because whitelisted addresses won't always have/need NFTs corresponding to their ERC20s.
    if (whitelist[from] && whitelist[to]) {
      // Case 1) Both sender and recipient are whitelisted. No NFTs need to be transferred.
      // NOOP.
    } else if (whitelist[from]) {
      // Case 2) The sender is whitelisted, but the recipient is not. Contract should not attempt to 
      //         transfer NFTs from the sender, but the recipient should receive NFTs from the bank/minted.
      // Only cares about whole number increments.
      uint256 tokensToRetrieveOrMint = (balanceOf[to] / units) -
        (balanceBeforeReceiver / units);
      for (uint256 i = 0; i < tokensToRetrieveOrMint; i++) {
        _retrieveOrMintERC721(to);
      }
    } else if (whitelist[to]) {
      // Case 3) The sender is not whitelisted, but the recipient is. Contract should 
      //         attempt to withdraw and store NFTs from the sender, but the recipient should not 
      //         receive NFTs from the bank/minted.
      // Only cares about whole number increments.
      uint256 tokensToWithdrawAndStore = (balanceBeforeSender / units) -
        (balanceOf[from] / units);
      for (uint256 i = 0; i < tokensToWithdrawAndStore; i++) {
        _withdrawAndStoreERC721(from);
      }
    } else {
      // Case 4) Neither the sender nor the recipient are whitelisted.
      // Strategy:
      // 1. First deal with the whole tokens. These are easy and will just be transferred.
      // 2. Look at the fractional part of the value:
      //   a) If it causes the sender to lose a whole token that was represented by an NFT 
      //      due to a fractional part being transferred, withdraw and store an additional NFT from the sender.
      //   b) If it causes the receiver to gain a whole new token that should be represented 
      //      by an NFT due to receiving a fractional part that completes a whole token, retrieve 
      //      or mint an NFT to the recevier.

      // Whole tokens worth of ERC20s get transferred as NFTs without any burning/minting.
      uint256 nftsToTransfer = value / units;
      for (uint256 i = 0; i < nftsToTransfer; i++) {
        // TODO: review this -- pop LIFO from sender's nfts and transfer them
        uint256 indexOfLastToken = _owned[from].length - 1;
        uint256 tokenId = _owned[from][indexOfLastToken];
        _transferERC721(from, to, tokenId);
      }

      // If the sender's transaction changes their holding from a fractional to a 
      // non-fractional amount (or vice versa), adjust NFTs.
      //
      // Check if the send causes the sender to lose a whole token that was represented 
      // by an NFT due to a fractional part being transferred.
      //
      // To check this, look if subtracting the fractional amount from the balance causes 
      // the balance to drop below the original balance % units, which represents the number 
      // of whole tokens they started with.
      uint256 fractionalAmount = value % units;

      if (
        (balanceBeforeSender - fractionalAmount) / units <
        (balanceBeforeSender / units)
      ) {
        _withdrawAndStoreERC721(from);
      }

      // Check if the receive causes the receiver to gain a whole new token that 
      /// should be represented by an NFT due to receiving a fractional part that completes a whole token.
      if (
        (balanceBeforeReceiver + fractionalAmount) / units >
        (balanceBeforeReceiver / units)
      ) {
        _retrieveOrMintERC721(to);
      }
    }

    return true;
  }

  /// @notice Internal function for ERC20 minting
  /// @dev This function will allow minting of new ERC20s up to the maxTotalSupplyERC20. If mintCorrespondingERC721s_ 
  /// is true, it will also mint the corresponding ERC721s. Note that you cannot mint to the zero address,
  /// nor to this contract.
  function _mintERC20(
    address to,
    uint256 value,
    bool mintCorrespondingERC721s_
  ) internal virtual {
    if (to == address(0) || to == address(this)) {
      revert InvalidRecipient();
    }

    if (totalSupply + value > maxTotalSupplyERC20) {
      revert MaxERC20SupplyReached();
    }

    unchecked {
      balanceOf[to] += value;
      totalSupply += value;
    }

    emit Transfer(address(0), to, value);
    emit ERC20Transfer(address(0), to, value);

    // If mintCorrespondingERC721s_ is true, mint the corresponding ERC721s. This uses _retrieveOrMintERC721,  
    // which will first try to pull from the bank, and if the bank is empty, it will mint a new token.
    if (mintCorrespondingERC721s_) {
      uint256 nftsToRetrieveOrMint = value / units;
      for (uint256 i = 0; i < nftsToRetrieveOrMint; i++) {
        _retrieveOrMintERC721(to);
      }
    }
  }

  /// @notice Internal function for ERC721 minting and retrieval from the bank.
  /// @dev This function will allow minting of new ERC721s up to the maxTotalSupplyERC20. It 
  /// will first try to pull from the bank, and if the bank is empty, it will mint a new token.
  function _retrieveOrMintERC721(address to) internal virtual {
    if (to == address(0) || to == address(this)) {
      revert InvalidRecipient();
    }

    uint256 id;

    if (!DoubleEndedQueue.empty(_storedERC721Ids)) {
      // If there are any tokens in the bank, use those first.
      // Pop off the end of the queue (FIFO).
      id = uint256(_storedERC721Ids.popBack());
    } else {
      // Otherwise, mint a new token, unless it would put us over the max total supply in ERC721 terms.
      // id is 0-indexed, and minted is the absolute count of minted tokens.
      id = minted;
      minted++;
      if (minted > maxTotalSupplyERC20 / units) {
        revert MaxERC721SupplyReached();
      }
    }

    address nftOwner = _ownerOf[id];

    // The token should not already belong to anyone besides 0x0 or this contract. If it does, something is wrong.
    if (nftOwner != address(0) && nftOwner != address(this)) {
      revert AlreadyExists();
    }

    _ownerOf[id] = to;
    _owned[to].push(id);
    _ownedIndex[id] = _owned[to].length - 1;

    emit Transfer(nftOwner, to, id);
    emit ERC721Transfer(nftOwner, to, id);
  }

  /// @notice Internal function for ERC721 deposits to bank (this contract).
  /// @dev This function will allow depositing of ERC721s to the bank, which can be retrieved by future minters.
  function _withdrawAndStoreERC721(address from) internal virtual {
    if (from == address(0) || from == address(this)) {
      revert InvalidSender();
    }

    // Pull off the latest token added to the owner's stack (LIFO).
    uint256 id = _owned[from][_owned[from].length - 1];
    _owned[from].pop();

    // Transfer ownership to this contract and place it into the queue (FIFO).
    _ownerOf[id] = address(this);
    // TODO: This doesn't update _owned like other erc721 transfers.
    _storedERC721Ids.pushFront(bytes32(id));

    // Always delete approvals on NFT transfers.
    delete getApproved[id];

    emit Transfer(from, address(this), id);
    emit ERC721Transfer(from, address(this), id);
  }

  /// @notice Initialization function to set pairs / etc, saving gas by avoiding mint / burn on unnecessary targets
  function _setWhitelist(address target, bool state) internal {
    whitelist[target] = state;
  }
}

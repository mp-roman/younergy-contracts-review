// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// Custom error message for whitelist proof

error NotInWhiteList(address _address, bytes32 _root, bytes32[] _proof, bytes32 _leaf);

contract YounergyToken is ERC20Upgradeable, ERC20SnapshotUpgradeable, AccessControlEnumerableUpgradeable, ReentrancyGuardUpgradeable {

  using SafeMathUpgradeable for uint256;

  /// @notice role for admin users who has not a DEFAULT_ADMIN_ROLE
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  /// @notice role for web2.0 api 
  bytes32 public constant API_ROLE = keccak256("API_ROLE");

  /// @notice role for revenue distributor that allow to create new snapshots
  bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

  /// @notice We can't store float inside variables, so exchange rate is calculated as _exchangeRateNumerator / _exchangeRateDenominator
  uint8 private _exchangeRateNumerator;
  uint16 private _exchangeRateDenominator;

  /// @dev TokenSale Whitelist MerkelTree root
  bytes32 public whiteListMerkleRoot;

  /**
   * @dev Emitted when `balance` updated on `account`
   *
   * @notice Note `balance` may be zero.
   */
  event Balance(address indexed addr, uint256 balance);

  function initialize(string memory name, string memory symbol) public initializer {
    __ERC20_init_unchained(name, symbol);
    __ERC20Snapshot_init_unchained();
    __YounergyToken_init_unchained();
  }

  function __YounergyToken_init_unchained() internal onlyInitializing {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _exchangeRateNumerator = 100;
    _exchangeRateDenominator = 100;
  }

  function mint(address, uint256) pure public {
    revert("Direct minting in not allowed. Please use startPresale() method instead.");
  }

  /// @dev return current exchange rate
  function getExchangeRate() public view returns (uint8, uint16) {
    return (_exchangeRateNumerator, _exchangeRateDenominator);
  }

  /// @dev return current exchange rate
  function getCurrentSnapshotId() public view returns (uint256) {
    return _getCurrentSnapshotId();
  }

  /// @param _rate exchange rate for token sale
  /// @notice actual rate calculated as _exchangeRateNumerator / _exchangeRateDenominator
  function setExchangeRate(uint16 _rate) external returns (bool) {
    require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyToken: must have admin role to change rate");
    _exchangeRateDenominator = _rate;
    return true;
  }

  /// @param _merkleRoot hash used for proof address in whitelist 
  /// @dev set current revenue share MerkleRoot
  function setWhiteListMerkleRoot(bytes32 _merkleRoot) external returns (bool) {
    require(hasRole(API_ROLE, _msgSender()), "YounergyToken: must have api role to set whitelist proof");
    whiteListMerkleRoot = _merkleRoot;
    return true;
  }

  /// @param _rate exchange rate for token sale
  /// @param _merkleRoot hash used for proof address in whitelist 
  /// @param _amount creates `amount` new tokens for `this` contract.
  /// @dev start presale as one batch call
  function startPresale (uint8 _rate, bytes32 _merkleRoot, uint256 _amount) external returns (bool) {
    require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyToken: must have admin role to start presale");
    _exchangeRateDenominator = _rate;
    whiteListMerkleRoot = _merkleRoot;
    _mint(address(this), _amount);
    return true;
  }

  /// @dev we verify the merkle proof before transfer tokens to user
  function deposit(bytes32[] calldata _merkleProof) external payable returns (bool) {
    bytes32 _leaf = keccak256(abi.encodePacked(_msgSender()));
    if (!MerkleProofUpgradeable.verify(_merkleProof, whiteListMerkleRoot, _leaf)) {
      revert NotInWhiteList(_msgSender(), whiteListMerkleRoot, _merkleProof, _leaf);
    }
    _transfer(address(this), _msgSender(), msg.value.mul(_exchangeRateNumerator).div(_exchangeRateDenominator));
    return true;
  }

  function withdrawBalanceTo(address payable _to) external nonReentrant() {
    require(_to != address(0), "YounergyToken: Withdraw to zero address is not possible");
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyToken: must have super admin role to withdraw balance");
    (bool sent, ) = _to.call{value: address(this).balance}("");
    require(sent, "Funds were not withdrawn correctly!");
  }

  /// @dev increase snapshot id used for revenue calculation
  function makeSnapshot() external returns (uint256) {
    require(hasRole(SNAPSHOT_ROLE, _msgSender()), "YounergyToken: must have snapshot role for making new snapshot");
    return _snapshot();
  }

  /// @dev override required
  function _beforeTokenTransfer(
      address from,
      address to,
      uint256 amount
  ) internal override(ERC20Upgradeable, ERC20SnapshotUpgradeable) {
    super._beforeTokenTransfer(from, to, amount);
  }

  /// @dev uses by api for credit shares revenue calculation
  function _afterTokenTransfer (
      address from,
      address to,
      uint256
  ) internal override {

    if (from != address(this) || to != address(this)) {
      emit Balance(from, balanceOf(from));
      emit Balance(to, balanceOf(to));
    }
  }

}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";

contract YounergyNFT is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, ERC721BurnableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeMathUpgradeable for uint256;

    CountersUpgradeable.Counter private _tokenIdCounter;

    enum DataType {
        Less,
        More,
        Credits
    }

    mapping(DataType => uint256) public avoidedCarbonOffset;
    mapping(DataType => uint256) public mintedAvoidedCarbonOffset;
    mapping(DataType => uint256) public priceCarbonOffset;

    bytes32 public constant API_ROLE = keccak256("API_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @param from Address who minted NFT.
    /// @param to Address NFT minted for.
    /// @param id NFT ID.
    /// @param datatype Data Granular Mint NFT for.
    /// @param amount amount of Carbon Offset mint NFT for.
    /// @dev This event emitted for minting a new NFT with additional Carbon Offset info
    event Mint(address indexed from, address indexed to, uint256 indexed id, DataType datatype, uint256 amount);

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __YounergyNFT_init_unchained();
    }

    function __YounergyNFT_init_unchained() internal onlyInitializing {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        // _setupRole(API_ROLE, _msgSender());
        // _setupRole(ADMIN_ROLE, _msgSender());

        priceCarbonOffset[DataType.Less] = 0.075 ether;  // 75 xDAI = 1000 kg
        priceCarbonOffset[DataType.More] = 0.125 ether;  // 125 xDAI = 1000 kg
    }

    // Set amount of avoided CO2 (Carbon Offset) available for spending on NFT purchase
    function setAvoidedCarbonOffset(DataType _datatype, uint256 _amount) external onlyRole(API_ROLE) {
        require(_amount > avoidedCarbonOffset[_datatype], "Incorrect amount");
        avoidedCarbonOffset[_datatype] = _amount;
    }

    // price in xDAI of 1 tonne Carbon Offset
    function setPriceCarbonOffset(DataType _datatype, uint256 price) external {
        require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyNFT: must have admin role to change rate");
        priceCarbonOffset[_datatype] = price;
    }

    /// @param _address Address mint NFT to.
    /// @param _datatype Data Granular Mint NFT for.
    /// @param _amount amount of Carbon Offset mint NFT for.
    /// @dev This method should be invoked by admin from WEB3 for minting a new NFT
    function mint(address _address, DataType _datatype, uint256 _amount) external {
        require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyNFT: must have admin role to change rate");
        _offsetMint(_msgSender(), _address, _datatype, _amount);
    }

    /// @param _datatype Data Granular Mint NFT for.
    /// @param _amount amount of Carbon Offset mint NFT for.
    /// @dev This method may be invoked by any user for minting a new NFT
    function payableMint(DataType _datatype, uint256 _amount) external payable {
        require(msg.value >= _amount.mul(priceCarbonOffset[_datatype]), "Not enough Funds payed for minting");
        _offsetMint(address(0), _msgSender(), _datatype, _amount);
    }

    /// @param _amount amount of Carbon Offset mint NFT for.
    /// @dev This method may be invoked by any user for minting a new NFT
    function creditMint(address _address, uint256 _amount) external onlyRole(API_ROLE) {
        _offsetMint(address(0), _address, DataType.Credits, _amount);
    }

    function setTokenURI(uint256 _tokenId, string memory _tokenURI) external onlyRole(API_ROLE) {
        _setTokenURI(_tokenId, _tokenURI);
    }

    function withdrawBalanceTo(address payable _to) external nonReentrant() {
        require(_to != address(0), "YounergyToken: Withdraw to zero address");
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "YounergyNFT: must have super admin role to withdraw balance");
        (bool sent, ) = _to.call{value: address(this).balance}("");
        require(sent, "Funds were not withdrawn correctly!");
    }

    /// @notice Returns a list of all NFT IDs assigned to an address.
    /// @param _owner The owner whose NFTs we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire NFTs array looking for NFT belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(address _owner) public view onlyRole(API_ROLE) returns(uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 resultIndex = 0;

            // We count on the fact that all NFTs have IDs starting at 1 and increasing
            // sequentially up to the totalNFT count.
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[resultIndex] = tokenOfOwnerByIndex(_owner ,index);
                resultIndex++;
            }
            return result;
        }
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256, uint256)
        pure
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        require(from == address(0) || to == address(0), "Not allowed to transfer token");
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _offsetMint(address _from, address _to, DataType _datatype, uint256 _amount) internal {
        // check if carbonOffset > minted
        // avoidedCarbonOffset[type] > amount + mintedCarbonOffset
        if ( _datatype != DataType.Credits ) {
            require(_amount > 0, "Amount must be greater than 0");
            require(avoidedCarbonOffset[_datatype] >= _amount + mintedAvoidedCarbonOffset[_datatype], "Not enough Carbon Offset for minting");
            mintedAvoidedCarbonOffset[_datatype] += _amount;
        }

        uint256 tokenId = _tokenIdCounter.current();

        _tokenIdCounter.increment();
        _safeMint(_to, tokenId);

        emit Mint(_from, _to, tokenId, _datatype, _amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

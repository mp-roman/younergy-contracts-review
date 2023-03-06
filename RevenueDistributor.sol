// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./YounergyToken.sol";

contract RevenueDistributor is Initializable, ContextUpgradeable {

    using SafeMathUpgradeable for uint256;

    mapping(uint256 => uint256) private snapshotRevenue;
    mapping(address => uint256) public lastRevenueWithdrawAt;

    YounergyToken private younergyToken;
    
    event Distribute(uint256 id, uint256 amount);
    event Withdraw(uint256 id, address to, uint256 amount);

    function initialize(YounergyToken _younergyToken) initializer public {
        __RewardDistributor_init(_younergyToken);
    }

    function __RewardDistributor_init(YounergyToken _younergyToken) internal onlyInitializing {
        younergyToken = _younergyToken;
    }

    function distribute() external payable {
        uint256 currentSnapshotID = younergyToken.makeSnapshot();
        uint256 tokenTotalSupplyWithoutDecimals = younergyToken.totalSupplyAt(currentSnapshotID).div(10**younergyToken.decimals());
        if (tokenTotalSupplyWithoutDecimals != 0) {
            uint256 revenuePerToken = msg.value.div(tokenTotalSupplyWithoutDecimals);
            require(revenuePerToken > 0, "Insufficient revenue per token for distribution");
            snapshotRevenue[currentSnapshotID] = revenuePerToken;
            emit Distribute(currentSnapshotID, msg.value);
        } else {
            revert("No Token Holders for Reward");
        }
    }

    function withdraw() external returns(bool) {
        uint256 currentSnapshotID = younergyToken.getCurrentSnapshotId();
        uint256 currentRevenue = _revenue(currentSnapshotID);
        require(currentRevenue > 0, 'insufficient revenue for withdraw');
        require(address(this).balance >= currentRevenue, 'insufficient native currency on contract balance');
        payable(_msgSender()).transfer(currentRevenue);
        lastRevenueWithdrawAt[_msgSender()] = currentSnapshotID;
        emit Withdraw(currentSnapshotID, _msgSender(), currentRevenue);
        return true;
    }

    function getRevenue() view external returns(uint256) {
        uint256 currentSnapshotID = younergyToken.getCurrentSnapshotId();
        return _revenue(currentSnapshotID);
    }

    function getRevenueAt(uint256 _snapshotID) view external returns(uint256) {
        return snapshotRevenue[_snapshotID];
    }

    function _revenue(uint256 _snapshotID) view internal returns(uint256) {
        uint256 _currentRevenue = 0;
        for(uint256 i = lastRevenueWithdrawAt[_msgSender()].add(1); i <= _snapshotID; i++) {
            _currentRevenue = _currentRevenue.add(younergyToken.balanceOfAt(_msgSender(), i).mul(snapshotRevenue[i]).div(1 ether));
        }
        return _currentRevenue;
    }
}
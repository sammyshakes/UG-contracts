// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;


import "./IUGNFTs.sol";

interface IUGArena {

    struct Stake {
        uint64 bloodPerRank;
        uint32 stakeTimestamp;
        address owner;
    }
    function setGameContract(address _ugGame) external;
    function numUserStakedFighters(address user) external view returns (uint256);
    function getStake(uint256 tokenId) external view returns (Stake memory);
    function getStakeOwner(uint256 tokenId) external view returns (address);
    function verifyAllStakedByUser(address, uint256[] calldata) external view returns (bool);
    function getAmuletRingInfo(address user) external view returns(uint256, uint256, uint256);

    function stakeRing(uint256 tokenId) external;
    function stakeAmulet(uint256 tokenId) external;
    function unstakeRing(uint256 tokenId) external;
    function unstakeAmulet(uint256 tokenId) external;

    function stakeManyToArena(uint256[] calldata ) external ;
    function claimManyFromArena(uint256[] calldata , bool ) external;
    function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed);
    function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256 owed);
    function getStakedRingIDForUser(address user) external view returns (uint256);
    function getStakedAmuletIDForUser(address user) external view returns (uint256);
    
    function addAdmin(address) external; // onlyOwner 
    function removeAdmin(address) external; // onlyOwner
    function payRaidRevenueToYakuza(uint256 amount) external; //onlyAdmin
    function getOwnerLastClaimAllTime(address user) external view returns (uint256);
    function setOwnerLastClaimAllTime(address user) external;
    function setPaused(bool) external;
}
